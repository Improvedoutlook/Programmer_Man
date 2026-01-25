//! Procedural NES-style chiptune music generator
//! Creates music similar to Mega Man style themes

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");

pub const ChiptunePlayer = struct {
    wave: rl.Wave,
    sound: rl.Sound,
    is_playing: bool,
    play_timer: f32,

    const Self = @This();

    pub fn init() !Self {
        // Generate a short chiptune wave
        const wave = generateChiptuneWave();

        // Debug: check if wave data is valid
        std.debug.print("[AUDIO] Wave data pointer: {*}, frame count: {}\n", .{ wave.data, wave.frameCount });
        std.debug.print("[AUDIO] Wave sampleRate: {}, sampleSize: {}, channels: {}\n", .{ wave.sampleRate, wave.sampleSize, wave.channels });

        const sound = rl.loadSoundFromWave(wave);
        // More important: check if sound loaded successfully
        std.debug.print("[AUDIO] Sound frameCount after load: {}\n", .{sound.frameCount});
        std.debug.print("[AUDIO] Sound struct: {*}, frameCount: {}\n", .{ &sound, sound.frameCount });
        // Note: Printing sound.stream directly is not supported due to type safety in Zig's formatter.

        // Check if sound data is valid (frameCount > 0)
        if (sound.frameCount == 0) {
            std.debug.print("[AUDIO] ERROR: Sound frameCount is 0! Sound may not have loaded properly.\n", .{});
        }

        return Self{
            .wave = wave,
            .sound = sound,
            .is_playing = false,
            .play_timer = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        rl.unloadSound(self.sound);
        rl.unloadWave(self.wave);
    }

    pub fn play(self: *Self) void {
        std.debug.print("[AUDIO] play() called, is_playing = {}\n", .{self.is_playing});
        rl.setSoundVolume(self.sound, config.MUSIC_VOLUME);
        rl.playSound(self.sound);
        self.is_playing = true;
        std.debug.print("[AUDIO] playSound called. isSoundPlaying: {}\n", .{rl.isSoundPlaying(self.sound)});
    }

    pub fn update(self: *Self, _: f32) void {
        if (self.is_playing) {
            const is_playing = rl.isSoundPlaying(self.sound);
            std.debug.print("[AUDIO] update(): is_playing = {}, isSoundPlaying = {}\n", .{ self.is_playing, is_playing });
            if (!is_playing) {
                std.debug.print("[AUDIO] Sound finished, restarting...\n", .{});
                rl.playSound(self.sound);
                std.debug.print("[AUDIO] playSound called from update. isSoundPlaying: {}\n", .{rl.isSoundPlaying(self.sound)});
            }
        }
    }

    pub fn stop(self: *Self) void {
        if (self.is_playing) {
            std.debug.print("[AUDIO] stop() called. Stopping sound.\n", .{});
            rl.stopSound(self.sound);
            self.is_playing = false;
            std.debug.print("[AUDIO] Sound stopped. isSoundPlaying: {}\n", .{rl.isSoundPlaying(self.sound)});
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
