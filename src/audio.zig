//! Procedural NES-style chiptune music generator
//! Creates music similar to Mega Man style themes
//! Also provides simple SFX API for game sounds

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");

// ============================================================================
// SFX System - Simple sound effects API
// ============================================================================

pub const SfxType = enum {
    Jump,
    Pounce,
    Stomp,
};

const SFX_COUNT = 3; // Number of SfxType variants

var sfx_sounds: [SFX_COUNT]rl.Sound = undefined;
var sfx_loaded: bool = false;

// The "power stomp" POW is synthesized procedurally (see generatePowWave) rather
// than loaded from disk, so it needs no authored asset and behaves identically on
// native and web builds. It is a heavier, lower-pitched cousin of the normal stomp.
var pow_sound: rl.Sound = undefined;
var pow_loaded: bool = false;

const sfx_paths = [SFX_COUNT][:0]const u8{
    "assets/audio/jump.wav",
    "assets/audio/pounce.wav",
    "assets/audio/stomp.wav",
};

/// Load all SFX from disk. Call once at game startup after audio device init.
pub fn loadSfx() void {
    if (sfx_loaded) return;

    for (0..SFX_COUNT) |i| {
        sfx_sounds[i] = rl.loadSound(sfx_paths[i]) catch {
            // Failed to load, continue with next sound
            continue;
        };
    }

    // Synthesize the power-stomp POW and keep it resident alongside the file SFX.
    const pow_wave = generatePowWave();
    pow_sound = rl.loadSoundFromWave(pow_wave);
    rl.unloadWave(pow_wave);
    pow_loaded = true;

    sfx_loaded = true;
}

/// Play the procedural "POW!" for a power stomp — a beefier, lower impact than the
/// regular stomp. `volume` is 0.0 to 1.0.
pub fn playPowStomp(volume: f32) void {
    if (!pow_loaded) return;
    if (pow_sound.frameCount == 0) return;
    rl.setSoundVolume(pow_sound, volume);
    rl.playSound(pow_sound);
}

/// Build a loud, bomb-like "POW" impact wave for a power stomp. Designed to be
/// perceptibly louder than the regular stomp: the energy sits in the audible
/// mid-low band (not near-inaudible sub-bass), a sharp noise "crack" opens the
/// hit, and the whole thing is driven through a tanh saturator so its RMS — what
/// the ear reads as loudness — sits close to full scale rather than just peaking
/// there briefly. Mono 22050 Hz 16-bit — the same format family as the chiptune.
fn generatePowWave() rl.Wave {
    const sample_rate: u32 = 22050;
    const duration: f32 = 0.45; // seconds — a longer, booming tail
    const frame_count: u32 = @intFromFloat(@as(f32, @floatFromInt(sample_rate)) * duration);

    var wave = rl.Wave{
        .frameCount = frame_count,
        .sampleRate = sample_rate,
        .sampleSize = 16,
        .channels = 1,
        .data = undefined,
    };

    const data_size = frame_count * @sizeOf(i16);
    wave.data = @ptrCast(rl.memAlloc(@intCast(data_size)));
    const samples: [*]i16 = @ptrCast(@alignCast(wave.data));

    // Simple deterministic LCG so the noise burst is reproducible and needs no state.
    var rng: u32 = 0x1234_5678;

    // Accumulated oscillator phase so the pitch sweep stays continuous (computing
    // sin(freq*t) directly would glitch as freq changes). Radians.
    var phase: f32 = 0;

    const two_pi: f32 = 2.0 * std.math.pi;
    const sr_f: f32 = @floatFromInt(sample_rate);

    var i: u32 = 0;
    while (i < frame_count) : (i += 1) {
        const t: f32 = @as(f32, @floatFromInt(i)) / sr_f;
        const progress: f32 = t / duration; // 0 -> 1

        // Pitch dives from a punchy ~300 Hz down to a chesty ~55 Hz — kept out of
        // the near-inaudible sub-bass so it reads loud on laptop/phone speakers.
        const freq: f32 = 55.0 + 245.0 * @exp(-progress * 6.0);
        phase += two_pi * freq / sr_f;
        const tone: f32 = @sin(phase);
        // A little square-ish grit an octave up thickens the body.
        const grit: f32 = @sin(phase * 2.0) * 0.3;

        // White-noise "crack" transient, concentrated at the very start.
        rng = rng *% 1_664_525 +% 1_013_904_223;
        const noise: f32 = (@as(f32, @floatFromInt(rng >> 8 & 0xFFFF)) / 32768.0) - 1.0;
        const noise_env: f32 = @exp(-progress * 22.0); // decays fast

        // Very sharp attack, slow booming decay so the hit sustains and hits hard.
        const attack: f32 = @min(t / 0.002, 1.0);
        const body_env: f32 = @exp(-progress * 3.2);

        const raw: f32 = (tone + grit + noise * noise_env * 0.9) * body_env * attack;

        // Drive hard through a soft saturator: pushes RMS (perceived loudness) up
        // toward the peak instead of leaving a spiky, quiet-feeling waveform.
        const saturated: f32 = std.math.tanh(raw * 3.0);

        samples[i] = @intFromFloat(saturated * 32000.0);
    }

    return wave;
}

/// Play a sound effect with the given volume (0.0 to 1.0).
pub fn playSfx(sfx: SfxType, volume: f32) void {
    if (!sfx_loaded) return;

    const idx = @intFromEnum(sfx);
    const sound = sfx_sounds[idx];

    if (sound.frameCount == 0) return; // Sound not loaded

    rl.setSoundVolume(sound, volume);
    rl.playSound(sound);
}

/// Unload all SFX from memory. Call once at game shutdown.
pub fn unloadSfx() void {
    if (!sfx_loaded) return;

    for (0..SFX_COUNT) |i| {
        if (sfx_sounds[i].frameCount > 0) {
            rl.unloadSound(sfx_sounds[i]);
        }
    }

    if (pow_loaded and pow_sound.frameCount > 0) {
        rl.unloadSound(pow_sound);
    }
    pow_loaded = false;

    sfx_loaded = false;
}

// ============================================================================
// ChiptunePlayer - Music generation
// ============================================================================

pub const ChiptunePlayer = struct {
    // This struct manages a single procedural music track that loops indefinitely. Commenting out to revert back if desired.
    // wave: rl.Wave,
    // sound: rl.Sound,

    // Add Music field for file-based playback
    music: rl.Music,
    is_playing: bool,
    play_timer: f32,

    const Self = @This();

    pub fn init() !Self {
        // OPTION 1: Use MP3 file (current)
        const music = try rl.loadMusicStream("assets/music/lost_in_hyperspace.mp3");

        // OPTION 2: Use procedural chiptune (comment out above, uncomment below)
        // const wave = generateChiptuneWave();
        // const sound = rl.loadSoundFromWave(wave);

        return Self{
            // For MP3:
            .music = music,

            // For chiptune (comment out above, uncomment below):
            // .wave = wave,
            // .sound = sound,

            .is_playing = false,
            .play_timer = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();

        // For MP3:
        rl.unloadMusicStream(self.music);

        // For chiptune (uncomment when switching back):
        // rl.unloadSound(self.sound);
        // rl.unloadWave(self.wave);
    }

    pub fn play(self: *Self) void {
        // For MP3:
        rl.setMusicVolume(self.music, config.MUSIC_VOLUME);
        rl.playMusicStream(self.music);

        // For chiptune (uncomment when switching back):
        // rl.setSoundVolume(self.sound, config.MUSIC_VOLUME);
        // rl.playSound(self.sound);

        self.is_playing = true;
    }

    pub fn update(self: *Self, _: f32) void {
        if (self.is_playing) {
            // For MP3 - IMPORTANT: Must call this every frame for streaming
            rl.updateMusicStream(self.music);

            // Loop the music when it finishes
            if (!rl.isMusicStreamPlaying(self.music)) {
                rl.playMusicStream(self.music);
            }

            // For chiptune (uncomment when switching back):
            // if (!rl.isSoundPlaying(self.sound)) {
            //     rl.playSound(self.sound);
            // }
        }
    }

    pub fn stop(self: *Self) void {
        if (self.is_playing) {
            // For MP3:
            rl.stopMusicStream(self.music);

            // For chiptune (uncomment when switching back):
            // rl.stopSound(self.sound);

            self.is_playing = false;
        }
    }

    /// Switch to a different music track at runtime.
    /// Stops and unloads the current stream, then loads and plays the new one.
    /// If loading fails, the player is left in a stopped state with the old
    /// stream already unloaded — callers should handle a subsequent play()
    /// gracefully (the update() loop already checks is_playing).
    pub fn switchTrack(self: *Self, path: [:0]const u8) void {
        // Stop current playback
        self.stop();

        // Unload the old stream
        rl.unloadMusicStream(self.music);

        // Load the new stream
        if (rl.loadMusicStream(path)) |new_music| {
            self.music = new_music;
            self.play();
        } else |_| {
            // Loading failed — mark as not playing.
            // music field is now invalid, but we won't touch it until
            // a successful switchTrack or deinit replaces it.
            self.is_playing = false;
        }
    }

    fn generateChiptuneWave() rl.Wave {
        const sample_rate: u32 = 22050;
        const duration: f32 = 8.0; // Longer loop for better melody
        const frame_count: u32 = @intFromFloat(sample_rate * duration);

        var wave = rl.Wave{
            .frameCount = frame_count,
            .sampleRate = sample_rate,
            .sampleSize = 16,
            .channels = 2,
            .data = undefined,
        };

        const data_size = frame_count * 2 * @sizeOf(i16);
        wave.data = @ptrCast(rl.memAlloc(@intCast(data_size)));
        const samples: [*]i16 = @ptrCast(@alignCast(wave.data));

        const bpm: f32 = 140.0;
        const sixteenth_note: f32 = (60.0 / bpm) / 4.0; // 16th note duration

        // Note frequencies
        const C4: f32 = 261.63;
        const E4: f32 = 329.63;
        const G4: f32 = 392.00;
        const A4: f32 = 440.00;
        const B4: f32 = 493.88;
        const C5: f32 = 523.25;
        const D5: f32 = 587.33;
        const E5: f32 = 659.25;
        const REST: f32 = 0.0;

        // Mega Man-inspired melody (in 16th notes)
        // This is similar to the intro of Mega Man 2's Dr. Wily Stage theme
        const melody = [_]f32{
            // Phrase 1: Energetic ascending run
            E5,   E5,   REST, E5,   REST, D5,   E5,   REST,
            REST, B4,   REST, REST, REST, REST, REST, REST,

            // Phrase 2: Answer phrase
            D5,   D5,   REST, D5,   REST, C5,   D5,   REST,
            REST, A4,   REST, REST, REST, REST, REST, REST,

            // Phrase 3: Build up
            E5,   E5,   REST, E5,   REST, G4,   REST, A4,
            B4,   C5,   D5,   E5,   REST, REST, REST,

            // Phrase 4: Big finish
            E5,
            D5,   C5,   B4,   A4,   G4,   A4,   B4,   C5,
            REST, REST, REST, C5,   REST, REST, REST,
        };

        // Bass line (whole notes, simple root-fifth pattern)
        const bass_notes = [_]f32{ C4, G4, C4, G4, C4, G4, A4, E4 };

        var i: u32 = 0;
        while (i < frame_count) : (i += 1) {
            const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sample_rate));

            // Which note are we on?
            const note_index: usize = @intFromFloat(@mod(t / sixteenth_note, @as(f32, @floatFromInt(melody.len))));
            const bass_index: usize = @intFromFloat(@mod(t / (sixteenth_note * 16.0), @as(f32, @floatFromInt(bass_notes.len))));

            const melody_freq = melody[note_index];
            const bass_freq = bass_notes[bass_index] * 0.5; // One octave down

            var mixed: f32 = 0.0;

            // Only play melody if not a rest
            if (melody_freq > 0.0) {
                const melody_phase = @mod(t * melody_freq, 1.0);
                const melody_square: f32 = if (melody_phase < 0.5) 1.0 else -1.0;
                mixed += melody_square * 0.35;

                // Add harmony (perfect fifth above)
                const harmony_phase = @mod(t * melody_freq * 1.5, 1.0);
                const harmony_square: f32 = if (harmony_phase < 0.5) 0.5 else -0.5;
                mixed += harmony_square * 0.15;
            }

            // Bass (always playing)
            const bass_phase = @mod(t * bass_freq, 1.0);
            const bass_square: f32 = if (bass_phase < 0.125) 1.0 else -1.0; // 12.5% duty for punchy bass
            mixed += bass_square * 0.4;

            // Simple volume envelope for each note
            const note_phase = @mod(t / sixteenth_note, 1.0);
            const envelope = 1.0 - (note_phase * 0.4); // Decay over the note

            const sample_value: i16 = @intFromFloat(mixed * envelope * 14000.0);
            samples[i * 2] = sample_value;
            samples[i * 2 + 1] = sample_value;
        }

        return wave;
    }
};

// ============================================================================
// VictoryMusic - Victory track player
// ============================================================================

pub const VictoryMusic = struct {
    music: rl.Music,
    is_playing: bool,

    const Self = @This();

    pub fn init() !Self {
        const music = try rl.loadMusicStream("assets/music/snowball_game.mp3");

        return Self{
            .music = music,
            .is_playing = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        rl.unloadMusicStream(self.music);
    }

    pub fn play(self: *Self) void {
        rl.setMusicVolume(self.music, config.SFX_VOLUME);
        rl.playMusicStream(self.music);
        self.is_playing = true;
    }

    pub fn update(self: *Self) void {
        if (self.is_playing) {
            rl.updateMusicStream(self.music);
        }
    }

    pub fn stop(self: *Self) void {
        if (self.is_playing) {
            rl.stopMusicStream(self.music);
            self.is_playing = false;
        }
    }
};

// ============================================================================
// CreditsMusic - End credits track player
// ============================================================================

pub const CreditsMusic = struct {
    music: rl.Music,
    is_playing: bool,

    const Self = @This();

    pub fn init() !Self {
        const music = try rl.loadMusicStream("assets/music/a_hero_is_born.mp3");

        return Self{
            .music = music,
            .is_playing = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        rl.unloadMusicStream(self.music);
    }

    pub fn play(self: *Self) void {
        rl.setMusicVolume(self.music, config.MUSIC_VOLUME);
        rl.playMusicStream(self.music);
        self.is_playing = true;
    }

    pub fn update(self: *Self) void {
        if (self.is_playing) {
            rl.updateMusicStream(self.music);
            // Loop the track while the credits roll
            if (!rl.isMusicStreamPlaying(self.music)) {
                rl.playMusicStream(self.music);
            }
        }
    }

    pub fn stop(self: *Self) void {
        if (self.is_playing) {
            rl.stopMusicStream(self.music);
            self.is_playing = false;
        }
    }
};

// ============================================================================
// GameOverMusic - Game over track player
// ============================================================================

pub const GameOverMusic = struct {
    music: rl.Music,
    is_playing: bool,

    const Self = @This();

    pub fn init() !Self {
        const music = try rl.loadMusicStream("assets/music/the_world_ stood_ still.mp3");

        return Self{
            .music = music,
            .is_playing = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        rl.unloadMusicStream(self.music);
    }

    pub fn play(self: *Self) void {
        rl.setMusicVolume(self.music, config.MUSIC_VOLUME);
        rl.playMusicStream(self.music);
        self.is_playing = true;
    }

    pub fn update(self: *Self) void {
        if (self.is_playing) {
            rl.updateMusicStream(self.music);
            // Loop the track while the game over screen is showing
            if (!rl.isMusicStreamPlaying(self.music)) {
                rl.playMusicStream(self.music);
            }
        }
    }

    pub fn stop(self: *Self) void {
        if (self.is_playing) {
            rl.stopMusicStream(self.music);
            self.is_playing = false;
        }
    }
};

// ============================================================================
// OpeningMusic - Opening screen track player
// ============================================================================

pub const OpeningMusic = struct {
    music: rl.Music,
    is_playing: bool,

    const Self = @This();

    pub fn init() !Self {
        const music = try rl.loadMusicStream("assets/music/their_spears_fell_like_rain_full.ogg");

        return Self{
            .music = music,
            .is_playing = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        rl.unloadMusicStream(self.music);
    }

    pub fn play(self: *Self) void {
        rl.setMusicVolume(self.music, config.MUSIC_VOLUME);
        rl.playMusicStream(self.music);
        self.is_playing = true;
    }

    pub fn update(self: *Self) void {
        if (self.is_playing) {
            rl.updateMusicStream(self.music);
            // Loop the track while the opening screen is showing
            if (!rl.isMusicStreamPlaying(self.music)) {
                rl.playMusicStream(self.music);
            }
        }
    }

    pub fn stop(self: *Self) void {
        if (self.is_playing) {
            rl.stopMusicStream(self.music);
            self.is_playing = false;
        }
    }
};

