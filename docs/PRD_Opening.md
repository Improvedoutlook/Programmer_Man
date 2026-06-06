# Product Requirements Document (PRD)

## Feature: Game Opening Screen (Splash / Title Screen)

### Project: Programmer_Man

---

## 1. Overview
The goal is to implement an opening screen that displays immediately when **Programmer_Man** is launched. This screen will display a splash image and play background music simultaneously. The user can exit this screen and begin the gameplay loop by pressing a keyboard key or any button on a wireless controller.

---

## 2. Goals
- **Immersive Introduction**: Set the tone for the game with immediate audio-visual feedback.
- **Robust Resizing**: Ensure the opening screen handles window resizing correctly and matches the letterboxing/scaling behavior of the active gameplay window.
- **Seamless Transition**: Allow easy navigation into the game via keyboard (`Enter`) or any controller button, instantly switching assets (stopping introductory audio and starting gameplay systems).

---

## 3. Scope & Assets

### Assets Included:
1. **Opening Image**:
   - File Path: [PM_OpeningImage.png](file:///C:/Programmer_Man/tile-based-raylib-game/assets/Images/PM_OpeningImage.png)
   - Location: `assets/Images/PM_OpeningImage.png`
2. **Opening Music**:
   - File Path: [their_spears_fell_like_rain_full.ogg](file:///C:/Programmer_Man/tile-based-raylib-game/assets/music/their_spears_fell_like_rain_full.ogg)
   - Location: `assets/music/their_spears_fell_like_rain_full.ogg`
   - Format: Ogg Vorbis (`.ogg`), which must be streamed dynamically to conserve memory.

---

## 4. Functional Requirements

### 4.1 Opening Screen Rendering & Resizing
- **Startup State**: The game must start in the `.opening` (or `.title`) state.
- **Image Display**: `PM_OpeningImage.png` is displayed centered in the window.
- **Dynamic Resizing**:
  - The opening image must scale and maintain its aspect ratio when the window is resized.
  - To prevent rendering errors and ensure consistency with the gameplay window, the image should be rendered to the 800x600 virtual `render_target` texture. The standard scaling and letterboxing math defined in `main.zig` will then draw this texture onto the window.

### 4.2 Background Music Playback
- **Synchronization**: The music `their_spears_fell_like_rain_full.ogg` must start playing at the exact same frame that the opening image is displayed.
- **Looping**: The music must loop indefinitely while the opening screen is active.
- **Ogg Vorbis Support**: Since this is a `.ogg` file (in contrast to the `.mp3` files used in the rest of the game), the audio module must handle the file path correctly using Raylib's streaming API.

### 4.3 Dismissal & Transition Input
- The opening screen remains active until a dismiss input is detected.
- **Keyboard Trigger**: Pressing `Enter` (or `Numpad Enter`).
- **Controller Trigger**: Pressing **any button** on a connected wireless controller.
- **Action on Trigger**:
  1. Stop the looping opening music.
  2. Transition the `GameState` to `.playing` (or start the first level).
  3. Load and play the level music track.

---

## 5. Technical Specifications (Zig & Raylib)

### 5.1 Game State Addition
In `src/game.zig`, the `GameState` enum should be updated:
```zig
pub const GameState = enum {
    opening,
    playing,
    paused,
    game_over,
    victory,
};
```
On initialization (`Game.init`), the initial state will be set to `.opening`.

### 5.2 Audio Streaming Support
In `src/audio.zig`, a new struct `OpeningMusic` (or modifications to the existing stream structures) will manage the music stream for the `.ogg` file:
```zig
pub const OpeningMusic = struct {
    music: rl.Music,
    is_playing: bool,

    const Self = @This();

    pub fn init() !Self {
        // Load the OGG file
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
            if (!rl.isMusicStreamPlaying(self.music)) {
                rl.playMusicStream(self.music); // Loop playback
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
```

### 5.3 Any-Button Controller Input Detection
To detect any button pressed on a controller, we can implement a helper function in `src/controls.zig` (or check inside `main.zig` / `game.zig`):
```zig
pub fn isAnyGamepadButtonPressed(gamepad_idx: i32) bool {
    // Standard raylib GamepadButton count goes from 0 to 14
    var button: i32 = 0;
    while (button < 15) : (button += 1) {
        if (rl.isGamepadButtonPressed(gamepad_idx, @enumFromInt(button))) {
            return true;
        }
    }
    return false;
}
```

---

## 6. File Structure & Changes

The implementation will affect the following files:
- [src/game.zig](file:///C:/Programmer_Man/tile-based-raylib-game/src/game.zig):
  - Add `.opening` to `GameState`.
  - Handle state initialization and transition.
- [src/audio.zig](file:///C:/Programmer_Man/tile-based-raylib-game/src/audio.zig):
  - Add `OpeningMusic` structure.
- [src/main.zig](file:///C:/Programmer_Man/tile-based-raylib-game/src/main.zig):
  - Update loops to stream the opening music.
  - Render `PM_OpeningImage.png` when `GameState == .opening`.
  - Check for keyboard `Enter` and wireless controller input to transition.
- [src/controls.zig](file:///C:/Programmer_Man/tile-based-raylib-game/src/controls.zig):
  - Add button-polling helper if needed.

---

## 7. Acceptance Criteria

- [ ] **Instant Splash**: The game opens directly to the splash image `PM_OpeningImage.png`.
- [ ] **Audio Synced**: The intro music (`their_spears_fell_like_rain_full.ogg`) starts playing immediately.
- [ ] **Seamless Audio Looping**: The intro music loops seamlessly without gaps.
- [ ] **No Resize Errors**: Resizing the window while on the opening screen works cleanly without crashes or distortion, matching the letterboxing/aspect-ratio scaling of the main game.
- [ ] **Keyboard Advance**: Pressing `Enter` on the keyboard advances the game to Level 1.
- [ ] **Controller Advance**: Pressing any button on a connected wireless controller advances the game to Level 1.
- [ ] **Clean Asset Transition**: When advancing, the intro music stops, the gameplay music starts playing, and the gameplay interface displays.
