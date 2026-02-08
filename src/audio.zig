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
    Victory,
};

const SFX_COUNT = 4; // Number of SfxType variants

var sfx_sounds: [SFX_COUNT]rl.Sound = undefined;
var sfx_loaded: bool = false;

const sfx_paths = [SFX_COUNT][:0]const u8{
    "assets/audio/jump.wav",
    "assets/audio/pounce.wav",
    "assets/audio/stomp.wav",
    "assets/audio/victory.wav",
};

/// Generate a simple victory/success sound wave (OS-style "ding!")
pub fn generateVictorySound() rl.Sound {
    const sample_rate: u32 = 22050;
    const duration: f32 = 0.8; // Short and sweet
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

    // Two-tone ding: C5 -> E5 (classic success sound)
    const freq1: f32 = 523.25; // C5
    const freq2: f32 = 659.25; // E5

    var i: u32 = 0;
    while (i < frame_count) : (i += 1) {
        const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sample_rate));

        // Switch from first tone to second tone halfway through
        const freq = if (t < 0.15) freq1 else freq2;

        // Use sine wave for a clean, pleasant tone
        const phase = t * freq * 2.0 * std.math.pi;
        const sine = @sin(phase);

        // Envelope: quick attack, gentle decay
        const envelope = if (t < 0.05)
            t / 0.05 // Attack
        else
            1.0 - ((t - 0.05) / (duration - 0.05)) * 0.7; // Decay

        const sample_value: i16 = @intFromFloat(sine * envelope * 20000.0);
        samples[i * 2] = sample_value;
        samples[i * 2 + 1] = sample_value;
    }

    const sound = rl.loadSoundFromWave(wave);
    rl.unloadWave(wave);
    return sound;
}

/// Load all SFX from disk. Call once at game startup after audio device init.
pub fn loadSfx() void {
    if (sfx_loaded) return;

    for (0..SFX_COUNT) |i| {
        // Special case for victory sound - generate it procedurally
        if (i == @intFromEnum(SfxType.Victory)) {
            sfx_sounds[i] = generateVictorySound();
            continue;
        }

        sfx_sounds[i] = rl.loadSound(sfx_paths[i]) catch {
            // Failed to load, continue with next sound
            continue;
        };
    }
    sfx_loaded = true;
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
