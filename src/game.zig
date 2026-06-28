//! Game module - Main game state management and coordination
//! Game module - Main game state management and coordination

const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const config = @import("config.zig");
const controls = @import("controls.zig");
const Player = @import("player.zig").Player;
const Tilemap = @import("tilemap.zig").Tilemap;
const tilemap_builder = @import("tilemap.zig");
const BugManager = @import("enemy.zig").BugManager;
const AiType = @import("tilemap.zig").AiType;
const SparkManager = @import("hazards.zig").SparkManager;
const MovingPlatformManager = @import("platform.zig").MovingPlatformManager;
const audio = @import("audio.zig");
const touch = @import("touch.zig");

// Web only: the custom shell's "Click to Start" button sets window.Module.pmStarted
// (see web/shell.html). raylib only sees input that lands on the <canvas>, so a
// click on that HTML overlay button never registers as an in-game gesture. Poll
// the JS flag via emscripten's script eval so the button arms audio and starts
// the game exactly like a canvas gesture would. The dead branch — and therefore
// this extern symbol — is comptime-eliminated on native builds.
extern fn emscripten_run_script_int(script: [*:0]const u8) c_int;

fn webStartPressed() bool {
    if (builtin.target.os.tag != .emscripten) return false;
    return emscripten_run_script_int("(window.Module&&window.Module.pmStarted)?1:0") != 0;
}

pub const GameState = enum {
    opening,
    playing,
    paused,
    game_over,
    victory,
    credits,
};

pub const Camera = struct {
    rl_camera: rl.Camera2D,

    pub fn init() Camera {
        return Camera{
            .rl_camera = .{
                .offset = .{ .x = @as(f32, @floatFromInt(config.GAME_WIDTH)) / 2.0, .y = @as(f32, @floatFromInt(config.GAME_HEIGHT)) / 2.0 },
                .target = .{ .x = @as(f32, @floatFromInt(config.GAME_WIDTH)) / 2.0, .y = @as(f32, @floatFromInt(config.GAME_HEIGHT)) / 2.0 },
                .rotation = 0,
                .zoom = 1.0,
            },
        };
    }

    /// Follow the player, clamping so the camera never shows beyond the world bounds.
    pub fn follow(self: *Camera, player_x: f32, player_y: f32, level_pixel_w: f32, level_pixel_h: f32) void {
        const half_w = @as(f32, @floatFromInt(config.GAME_WIDTH)) / 2.0;
        const half_h = @as(f32, @floatFromInt(config.GAME_HEIGHT)) / 2.0;

        // Target = player position, clamped so edges never exceed world bounds
        var tx = player_x;
        var ty = player_y;

        // Clamp horizontal
        if (tx < half_w) tx = half_w;
        if (tx > level_pixel_w - half_w) tx = level_pixel_w - half_w;

        // Clamp vertical
        if (ty < half_h) ty = half_h;
        if (ty > level_pixel_h - half_h) ty = level_pixel_h - half_h;

        // If level is smaller than the viewport, centre it
        if (level_pixel_w <= @as(f32, @floatFromInt(config.GAME_WIDTH))) {
            tx = level_pixel_w / 2.0;
        }
        if (level_pixel_h <= @as(f32, @floatFromInt(config.GAME_HEIGHT))) {
            ty = level_pixel_h / 2.0;
        }

        self.rl_camera.target = .{ .x = tx, .y = ty };
    }

    /// Return the top-left corner of the visible area in world coordinates.
    pub fn getWorldOffset(self: *const Camera) struct { x: f32, y: f32 } {
        return .{
            .x = self.rl_camera.target.x - self.rl_camera.offset.x,
            .y = self.rl_camera.target.y - self.rl_camera.offset.y,
        };
    }
};

/// A single line of scrolling credits text.
const CreditLine = struct {
    text: [:0]const u8,
    size: i32,
    color: rl.Color,
};

const credit_title = rl.Color{ .r = 100, .g = 180, .b = 255, .a = 255 }; // Programmer blue
const credit_body = rl.Color{ .r = 0, .g = 255, .b = 128, .a = 255 }; // Terminal green
const credit_dim = rl.Color{ .r = 150, .g = 150, .b = 160, .a = 255 }; // Muted grey (URLs)
const credit_track = rl.Color{ .r = 230, .g = 200, .b = 120, .a = 255 }; // Warm gold (track titles)

/// The end-credits roll. Scrolls from the bottom of the screen to the top.
const credit_lines = [_]CreditLine{
    .{ .text = "PROGRAMMER_MAN", .size = 48, .color = credit_title },
    .{ .text = "", .size = 80, .color = credit_body },
    .{ .text = "Thank You", .size = 40, .color = credit_body },
    .{ .text = "", .size = 40, .color = credit_body },

    .{ .text = "To the creators of Zig", .size = 28, .color = credit_body },
    .{ .text = "and the creators of Raylib", .size = 28, .color = credit_body },
    .{ .text = "for the tools that made this game possible", .size = 22, .color = credit_body },
    .{ .text = "", .size = 40, .color = credit_body },

    .{ .text = "To everyone who loves playing games", .size = 28, .color = credit_body },
    .{ .text = "and to everyone who creates them", .size = 28, .color = credit_body },
    .{ .text = "for others to enjoy", .size = 28, .color = credit_body },
    .{ .text = "", .size = 40, .color = credit_body },

    .{ .text = "A special thanks for the amazing 8-bit music", .size = 26, .color = credit_title },
    .{ .text = "found on OpenGameArt", .size = 22, .color = credit_body },
    .{ .text = "https://opengameart.org/", .size = 18, .color = credit_dim },
    .{ .text = "", .size = 28, .color = credit_body },

    .{ .text = "shiru8bit  -  Alex Semenov", .size = 24, .color = credit_body },
    .{ .text = "https://shiru.untergrund.net/", .size = 18, .color = credit_dim },
    .{ .text = "Lost In Hyperspace", .size = 20, .color = credit_track },
    .{ .text = "Lone Fighter", .size = 20, .color = credit_track },
    .{ .text = "Transmission", .size = 20, .color = credit_track },
    .{ .text = "Danger Streets", .size = 20, .color = credit_track },
    .{ .text = "Snowball Game", .size = 20, .color = credit_track },
    .{ .text = "", .size = 24, .color = credit_body },

    .{ .text = "request", .size = 24, .color = credit_body },
    .{ .text = "http://request.moe/", .size = 18, .color = credit_dim },
    .{ .text = "Their Spears Fell Like Rain", .size = 20, .color = credit_track },
    .{ .text = "", .size = 24, .color = credit_body },

    .{ .text = "quantumelle  -  Jordan Trudgett", .size = 24, .color = credit_body },
    .{ .text = "A Hero Is Born", .size = 20, .color = credit_track },
    .{ .text = "", .size = 50, .color = credit_body },

    .{ .text = "And finally...", .size = 28, .color = credit_body },

    // A full screen of blank space so every earlier line scrolls away and the
    // closing line rises into view — and comes to rest — entirely on its own.
    .{ .text = "", .size = config.SCREEN_HEIGHT, .color = credit_body },

    .{ .text = "Thanks for playing!", .size = 44, .color = credit_title },
};

/// Vertical advance between consecutive lines (pixels of padding added to size).
const CREDIT_LINE_PADDING: i32 = 16;

/// Total pixel height of the whole credits block (computed at comptime).
const credits_block_height: f32 = blk: {
    var h: f32 = 0;
    for (credit_lines) |line| {
        h += @floatFromInt(line.size + CREDIT_LINE_PADDING);
    }
    break :blk h;
};

pub const Game = struct {
    player: Player,
    tilemap: Tilemap,
    bugs: BugManager,
    sparks: SparkManager,
    moving_platforms: MovingPlatformManager,
    camera: Camera,
    state: GameState,
    current_level: u8,
    music: ?audio.ChiptunePlayer,
    victory_music: ?audio.VictoryMusic,
    game_over_music: ?audio.GameOverMusic,
    opening_music: ?audio.OpeningMusic,
    credits_music: ?audio.CreditsMusic,
    credits_scroll: f32,
    all_bugs_defeated: bool,
    terminal_pos: ?struct { x: i32, y: i32 },
    player_texture: ?rl.Texture2D,
    opening_texture: ?rl.Texture2D,
    game_complete: bool,
    has_gamepad: bool,
    gamepad_name: ?[:0]const u8,
    /// Web autoplay gate: browsers mute all audio until the first user gesture,
    /// so on emscripten we hold off starting the opening track until then. On
    /// native there is no such restriction, so audio is armed from the start
    /// and behaviour is unchanged. (PM_BrowserGameplay.md Phase 4.)
    audio_armed: bool,

    const Self = @This();
    const MAX_LEVELS: u8 = 4; // Total number of levels (Level 1 = index 0, ..., Level 4 = index 3)

    pub fn init() Self {
        // Audio device is initialized in main.zig
        // Load SFX first
        audio.loadSfx();

        const music_player: ?audio.ChiptunePlayer = audio.ChiptunePlayer.init() catch null;

        const victory_music_player: ?audio.VictoryMusic = audio.VictoryMusic.init() catch null;
        const game_over_music_player: ?audio.GameOverMusic = audio.GameOverMusic.init() catch null;
        const opening_music_player: ?audio.OpeningMusic = audio.OpeningMusic.init() catch null;
        const credits_music_player: ?audio.CreditsMusic = audio.CreditsMusic.init() catch null;

        const player_texture = rl.loadTexture("assets/sprites/player.png") catch null;
        const opening_texture = rl.loadTexture("assets/images/PM_OpeningImage.png") catch null;

        var game = Self{
            .player = Player.init(),
            .tilemap = Tilemap.initDefault(),
            .bugs = BugManager.init(),
            .sparks = SparkManager.init(),
            .moving_platforms = MovingPlatformManager.init(),
            .camera = Camera.init(),
            .state = .opening,
            .current_level = 0,
            .music = music_player,
            .victory_music = victory_music_player,
            .game_over_music = game_over_music_player,
            .opening_music = opening_music_player,
            .credits_music = credits_music_player,
            .credits_scroll = 0,
            .opening_texture = opening_texture,
            .all_bugs_defeated = false,
            .terminal_pos = null,
            .player_texture = player_texture,
            .game_complete = false,
            .has_gamepad = false,
            .gamepad_name = null,
            // Native: armed immediately (no autoplay restriction). Web: wait
            // for the first user gesture before starting any track.
            .audio_armed = builtin.target.os.tag != .emscripten,
        };

        // Only start the opening track now if audio is already armed (native).
        // On web, armAudio() starts it on the first input gesture instead.
        if (game.audio_armed) {
            if (game.opening_music) |*m| {
                m.play();
            }
        }

        return game;
    }

    pub fn deinit(self: *Self) void {
        if (self.music) |*music| {
            music.deinit();
        }
        if (self.victory_music) |*victory_music| {
            victory_music.deinit();
        }
        if (self.game_over_music) |*game_over_music| {
            game_over_music.deinit();
        }
        if (self.opening_music) |*opening_music| {
            opening_music.deinit();
        }
        if (self.credits_music) |*credits_music| {
            credits_music.deinit();
        }
        if (self.opening_texture) |tex| {
            rl.unloadTexture(tex);
        }
        audio.unloadSfx();

        if (self.player_texture) |tex| {
            rl.unloadTexture(tex);
        }
    }

    /// Camera's world-space X offset (pixels from left edge of level).
    pub fn getCameraWorldX(self: *const Self) f32 {
        const wo = self.camera.getWorldOffset();
        return wo.x;
    }

    pub fn loadLevel(self: *Self, level: u8) void {
        self.current_level = level;

        // Reset tilemap (keep current dimensions; loadLevel can resize if needed)
        self.tilemap = Tilemap.initDefault();
        self.tilemap.setBackgroundTheme(switch (level) {
            0 => .motherboard,
            1 => .cooling_bay,
            2 => .core_chamber,
            3 => .silicon_ascent,
            else => .motherboard,
        });

        // Reset bugs
        self.bugs.reset();

        // Reset sparks
        self.sparks.reset();

        // Reset moving platforms
        self.moving_platforms.reset();

        // Reset terminal state
        self.all_bugs_defeated = false;

        // Player spawn defaults (overridden by JSON data when available)
        var spawn_x: i32 = config.SPAWN_TILE_X;
        var spawn_y: i32 = config.SPAWN_TILE_Y;

        // Load level data
        switch (level) {
            0 => {
                if (tilemap_builder.loadLevel1FromJson(&self.tilemap)) |level_data| {
                    self.applyLevelData(level_data, &spawn_x, &spawn_y);
                } else |_| {
                    // Fallback to hardcoded level if JSON parsing fails
                    tilemap_builder.createLevel1(&self.tilemap);
                    self.spawnBugsLevel1();
                    self.spawnSparksLevel1();
                    self.terminal_pos = .{ .x = 6, .y = 28 };
                }
            },
            1 => {
                if (tilemap_builder.loadLevelFromJson(&self.tilemap, "assets/data/level2.json")) |level_data| {
                    self.applyLevelData(level_data, &spawn_x, &spawn_y);
                } else |_| {
                    // Fallback to hardcoded Level 1 if Level 2 JSON fails
                    tilemap_builder.createLevel1(&self.tilemap);
                    self.spawnBugsLevel1();
                    self.spawnSparksLevel1();
                    self.terminal_pos = .{ .x = 6, .y = 28 };
                }
            },
            2 => {
                if (tilemap_builder.loadLevelFromJson(&self.tilemap, "assets/data/level3.json")) |level_data| {
                    self.applyLevelData(level_data, &spawn_x, &spawn_y);
                } else |_| {
                    // Fallback to hardcoded Level 1 if Level 3 JSON fails
                    tilemap_builder.createLevel1(&self.tilemap);
                    self.spawnBugsLevel1();
                    self.spawnSparksLevel1();
                    self.terminal_pos = .{ .x = 6, .y = 28 };
                }
            },
            3 => {
                if (tilemap_builder.loadLevelFromJson(&self.tilemap, "assets/data/level4.json")) |level_data| {
                    self.applyLevelData(level_data, &spawn_x, &spawn_y);
                } else |_| {
                    tilemap_builder.createLevel1(&self.tilemap);
                    self.spawnBugsLevel1();
                    self.spawnSparksLevel1();
                    self.terminal_pos = .{ .x = 6, .y = 28 };
                }
            },
            else => {
                // Default fallback for any unknown level index
                tilemap_builder.createLevel1(&self.tilemap);
                self.spawnBugsLevel1();
                self.spawnSparksLevel1();
                self.terminal_pos = .{ .x = 6, .y = 28 };
            },
        }

        // Switch background music based on level (only if not in opening state)
        if (self.state != .opening) {
            if (self.music) |*music| {
                switch (level) {
                    0 => music.switchTrack("assets/music/lost_in_hyperspace.mp3"),
                    1 => music.switchTrack("assets/music/danger_streets.mp3"),
                    2 => music.switchTrack("assets/music/lone_fighter.mp3"),
                    3 => music.switchTrack("assets/music/transmission.mp3"),
                    else => music.switchTrack("assets/music/lost_in_hyperspace.mp3"),
                }
            }
        }

        // Reset player and position at the level's spawn point
        // Preserve score and lives across level transitions
        const saved_score = self.player.score;
        const saved_lives = self.player.lives;
        self.player = Player.init();
        self.player.score = saved_score;
        self.player.lives = saved_lives;
        self.player.spawn_tile_x = spawn_x;
        self.player.spawn_tile_y = spawn_y;
        self.player.x = @as(f32, @floatFromInt(spawn_x * config.TILE_SIZE)) + config.PLAYER_WIDTH / 2;
        self.player.y = @as(f32, @floatFromInt(spawn_y * config.TILE_SIZE));
        self.state = .playing;

        // Snap the camera onto the new spawn point. Without this, the camera
        // keeps the previous level's position, and the very first frame after a
        // level transition renders with a stale/out-of-bounds camera (the
        // transition frame runs render() before updatePlaying re-clamps it).
        // For a narrow level following a wide one (e.g. Level 3 -> Level 4) that
        // stale x is past the new level's right edge, which made tilemap.render
        // compute start_col > end_col and panic.
        self.camera.follow(
            self.player.x,
            self.player.y - config.PLAYER_HEIGHT / 2.0,
            self.tilemap.getLevelPixelWidth(),
            self.tilemap.getLevelPixelHeight(),
        );
    }

    fn applyLevelData(self: *Self, level_data: tilemap_builder.LevelData, spawn_x: *i32, spawn_y: *i32) void {
        // Spawn bugs from loaded data
        for (0..level_data.bug_count) |i| {
            const bug = level_data.bug_spawns[i];
            const actual_speed = config.BUG_WALK_SPEED * bug.speed;
            self.bugs.spawn(bug.tile_x, bug.tile_y, bug.facing_right, actual_speed, bug.ai);
        }

        // Register spark spawn points from loaded data
        for (0..level_data.spark_count) |i| {
            const sp = level_data.spark_spawns[i];
            self.sparks.addSpawnPoint(
                @as(f32, @floatFromInt(sp.tile_x * config.TILE_SIZE)),
                @as(f32, @floatFromInt(sp.tile_y * config.TILE_SIZE)),
            );
        }

        // Tell spark manager how tall the level is (for deactivation)
        self.sparks.level_pixel_height = self.tilemap.getLevelPixelHeight();

        // Spawn moving platforms from loaded data
        for (0..level_data.moving_platform_count) |i| {
            self.moving_platforms.spawn(level_data.moving_platforms[i]);
        }

        self.terminal_pos = .{ .x = level_data.terminal_x, .y = level_data.terminal_y };
        spawn_x.* = level_data.player_spawn_x;
        spawn_y.* = level_data.player_spawn_y;
    }

    fn spawnBugsLevel1(self: *Self) void {
        // Spawn bugs at strategic locations
        // Bug on ground floor, left side
        self.bugs.spawn(8, 34, true, config.BUG_WALK_SPEED, .walker);

        // Bug on ground floor, middle
        self.bugs.spawn(22, 34, false, config.BUG_WALK_SPEED, .walker);

        // Bug on Platform 2
        self.bugs.spawn(20, 27, true, config.BUG_WALK_SPEED, .walker);

        // Bug on Platform 3
        self.bugs.spawn(34, 23, false, config.BUG_WALK_SPEED, .walker);

        // Bug on high platform
        self.bugs.spawn(44, 17, true, config.BUG_WALK_SPEED, .walker);

        // NEW: Bug on bottom far-right platform
        self.bugs.spawn(46, 34, false, config.BUG_WALK_SPEED, .walker);
    }

    /// Fallback: register hardcoded spark spawn points for Level 1.
    fn spawnSparksLevel1(self: *Self) void {
        const ts: f32 = @floatFromInt(config.TILE_SIZE);
        const spark_offset: f32 = 1.5 * ts; // 1.5 tiles below platform
        self.sparks.addSpawnPoint(20.0 * ts, (27.0 * ts) + spark_offset); // Platform 2
        self.sparks.addSpawnPoint(34.0 * ts, (23.0 * ts) + spark_offset); // Platform 3
        self.sparks.addSpawnPoint(44.0 * ts, (17.0 * ts) + spark_offset); // Platform 5
    }

    /// Web audio-unlock gate. On the first user gesture (mouse/key/gamepad) we
    /// mark audio as armed and start the track for whatever screen we're on. In
    /// practice the gesture always lands on the opening screen, since every
    /// later screen transition is itself driven by input (a gesture) and starts
    /// its own track. The same gesture also unlocks the browser's WebAudio
    /// context, so playback is audible from here on (SFX included).
    fn armAudio(self: *Self) void {
        self.audio_armed = true;
        switch (self.state) {
            .opening => if (self.opening_music) |*m| m.play(),
            else => {},
        }
    }

    pub fn update(self: *Self, dt: f32) void {
        // Hold off starting audio on web until the player starts the game: either
        // by clicking the shell's "Click to Start" button (webStartPressed) or by
        // any input that lands on the canvas (isAudioUnlockGesture). On native
        // audio_armed is already true at init, so this is a no-op.
        if (!self.audio_armed and (webStartPressed() or controls.isAudioUnlockGesture())) {
            self.armAudio();
        }

        // DEBUG PREVIEW: press F12 to jump straight to the end-credits roll.
        // Temporary aid for previewing the credits without a full playthrough.
        if (rl.isKeyPressed(.f12) and self.state != .credits) {
            if (self.music) |*m| m.stop();
            if (self.victory_music) |*m| m.stop();
            if (self.opening_music) |*m| m.stop();
            if (self.game_over_music) |*m| m.stop();
            if (self.credits_music) |*cm| cm.play();
            self.credits_scroll = 0;
            self.game_complete = true;
            self.state = .credits;
        }

        self.tilemap.updateBackground(dt);
        const input = controls.poll();
        self.has_gamepad = input.has_gamepad;
        self.gamepad_name = input.gamepad_name;

        // Update music stream
        if (self.music) |*music| {
            music.update(dt);
        }

        // Update victory music stream
        if (self.victory_music) |*victory_music| {
            victory_music.update();
        }

        // Update game over music stream
        if (self.game_over_music) |*game_over_music| {
            game_over_music.update();
        }

        // Update opening music stream
        if (self.opening_music) |*opening_music| {
            opening_music.update();
        }

        // Update credits music stream
        if (self.credits_music) |*credits_music| {
            credits_music.update();
        }

        switch (self.state) {
            .opening => self.updateOpening(input),
            .playing => self.updatePlaying(dt, input),
            .paused => self.updatePaused(input),
            .game_over => self.updateGameOver(input),
            .victory => self.updateVictory(input),
            .credits => self.updateCredits(dt, input),
        }
    }

    fn updateOpening(self: *Self, input: controls.FrameInput) void {
        _ = input;
        if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter) or controls.isAnyGamepadButtonPressed() or touch.anyTapPressed()) {
            if (self.opening_music) |*m| {
                m.stop();
            }
            self.state = .playing;
            self.loadLevel(0);
        }
    }

    fn updatePlaying(self: *Self, dt: f32, input: controls.FrameInput) void {
        // Check for pause
        if (input.pause_pressed) {
            self.state = .paused;
            return;
        }

        // Advance moving platforms first so their per-frame delta is current,
        // then run player tile physics, then land/carry the player on top.
        self.moving_platforms.update(dt);

        // Update player
        self.player.handleInput(input);
        self.player.update(dt, &self.tilemap);

        // Land the player on / carry the player with any ridden moving platform
        self.moving_platforms.resolvePlayer(&self.player);

        // Update enemies
        self.bugs.update(dt, &self.tilemap);

        // Update sparks
        self.sparks.update(dt);

        // Update camera to follow player
        self.camera.follow(
            self.player.x,
            self.player.y - config.PLAYER_HEIGHT / 2.0, // Centre on player's middle
            self.tilemap.getLevelPixelWidth(),
            self.tilemap.getLevelPixelHeight(),
        );

        // Check player-enemy collisions
        self.bugs.checkPlayerCollision(&self.player, dt);

        // Check player-spark collisions
        self.sparks.checkPlayerCollision(&self.player);

        // Check for player death (game over)
        if (self.player.state == .dead) {
            // Stop background music and play game over track
            if (self.music) |*music| {
                music.stop();
            }
            if (self.game_over_music) |*game_over_music| {
                game_over_music.play();
            }
            self.state = .game_over;
        }

        // Check if all bugs defeated (but don't trigger victory yet)
        if (self.bugs.getActiveCount() == 0 and !self.all_bugs_defeated) {
            self.all_bugs_defeated = true;
        }

        // Check for terminal interaction to submit PR and win
        if (self.all_bugs_defeated) {
            if (self.terminal_pos) |term| {
                const term_x = @as(f32, @floatFromInt(term.x * config.TILE_SIZE));
                const term_y = @as(f32, @floatFromInt(term.y * config.TILE_SIZE));
                const term_w: f32 = 32.0;
                const term_h: f32 = 48.0;

                const player_rect = self.player.getRect();
                const overlaps = player_rect.x < term_x + term_w and
                    player_rect.x + player_rect.width > term_x and
                    player_rect.y < term_y + term_h and
                    player_rect.y + player_rect.height > term_y;

                if (overlaps and input.submit_pressed) {
                    // STOP BACKGROUND MUSIC AND PLAY VICTORY MUSIC
                    if (self.music) |*music| {
                        music.stop();
                    }
                    if (self.victory_music) |*victory_music| {
                        victory_music.play();
                    }

                    // Determine if this is the final level
                    self.game_complete = (self.current_level >= Self.MAX_LEVELS - 1);
                    self.state = .victory;
                }
            }
        }
    }

    fn updatePaused(self: *Self, input: controls.FrameInput) void {
        // A fresh touch anywhere resumes (the pause button maps to pause_pressed;
        // tapping elsewhere on the dimmed screen works too).
        if (input.pause_pressed or touch.anyTapPressed()) {
            self.state = .playing;
        }
    }

    fn updateGameOver(self: *Self, input: controls.FrameInput) void {
        if (input.restart_pressed or touch.anyTapPressed()) {
            // Stop game over music before restarting
            if (self.game_over_music) |*game_over_music| {
                game_over_music.stop();
            }
            // Full reset: go back to level 1 with fresh lives and score
            self.player.lives = config.INITIAL_LIVES;
            self.player.score = 0;
            self.loadLevel(0);
        }
    }

    fn updateVictory(self: *Self, input: controls.FrameInput) void {
        if (self.game_complete) {
            // Final victory — once the victory fanfare has played, any button
            // rolls the end credits.
            if (controls.isAnyInputPressed() or touch.anyTapPressed()) {
                if (self.victory_music) |*victory_music| {
                    victory_music.stop();
                }
                if (self.credits_music) |*credits_music| {
                    credits_music.play();
                }
                self.credits_scroll = 0;
                self.state = .credits;
            }
        } else {
            // Level complete — press Enter to advance to next level
            if (input.submit_pressed or touch.anyTapPressed()) {
                if (self.victory_music) |*victory_music| {
                    victory_music.stop();
                }
                if (self.current_level + 1 < Self.MAX_LEVELS) {
                    self.loadLevel(self.current_level + 1);
                }
            }
        }
    }

    /// Highest scroll value — credits stop here so the final lines rest on
    /// screen rather than disappearing off the top.
    fn creditsMaxScroll() f32 {
        const last = credit_lines[credit_lines.len - 1];
        const last_h: f32 = @floatFromInt(last.size + CREDIT_LINE_PADDING);
        const screen_h: f32 = @floatFromInt(config.SCREEN_HEIGHT);
        const rest_y: f32 = screen_h * 0.45; // Final line settles ~45% down
        return screen_h - rest_y + (credits_block_height - last_h);
    }

    fn updateCredits(self: *Self, dt: f32, input: controls.FrameInput) void {
        // Scroll the credits upward until the final line settles into place.
        const max_scroll = creditsMaxScroll();
        if (self.credits_scroll < max_scroll) {
            self.credits_scroll += config.CREDITS_SCROLL_SPEED * dt;
            if (self.credits_scroll > max_scroll) self.credits_scroll = max_scroll;
        }

        // Once the roll has finished, return to the opening screen — same
        // music and image the player sees when first starting the game.
        if (self.credits_scroll >= max_scroll and (input.restart_pressed or touch.anyTapPressed())) {
            if (self.credits_music) |*credits_music| {
                credits_music.stop();
            }
            self.game_complete = false;
            self.credits_scroll = 0;
            self.current_level = 0;
            self.player.score = 0;
            self.player.lives = config.INITIAL_LIVES;
            self.state = .opening;
            if (self.opening_music) |*opening_music| {
                opening_music.play();
            }
        }
    }

    pub fn render(self: *Self) void {
        if (self.state == .credits) {
            self.renderCredits();
            return;
        }

        if (self.state == .opening) {
            rl.clearBackground(rl.Color.black);
            if (self.opening_texture) |tex| {
                const src = rl.Rectangle{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(tex.width),
                    .height = @floatFromInt(tex.height),
                };
                const dest = rl.Rectangle{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(config.GAME_WIDTH),
                    .height = @floatFromInt(config.GAME_HEIGHT),
                };
                rl.drawTexturePro(tex, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, rl.Color.white);
            }
            // Draw a subtle flashing text prompt at the bottom of the screen
            const text = "PRESS ENTER OR ANY CONTROLLER BUTTON TO START";
            const font_size = 20;
            const text_width = rl.measureText(text, font_size);
            const x = @divTrunc(config.GAME_WIDTH - text_width, 2);
            // Flash text using time (sine wave)
            const time = @as(f32, @floatCast(rl.getTime()));
            const alpha = @as(u8, @intFromFloat(127.0 + 127.0 * @sin(time * 4.0)));
            var text_color = config.HUD_COLOR;
            text_color.a = alpha;
            rl.drawText(text, x, config.GAME_HEIGHT - 60, font_size, text_color);
            return;
        }

        // === World-space rendering (scrolls with camera) ===
        self.camera.rl_camera.begin();
        {
            // Render background first
            self.tilemap.renderBackground();

            // Render tilemap (viewport-culled)
            const cam_wo = self.camera.getWorldOffset();
            self.tilemap.render(cam_wo.x, cam_wo.y);

            // Render terminal
            self.renderTerminal();

            // Render moving platforms (after tilemap, before bugs/player)
            self.moving_platforms.render();

            // Render sparks (behind bugs and player)
            self.sparks.render();

            // Render enemies
            self.bugs.render();

            // Render player
            // Render player
            if (self.player_texture) |tex| {
                self.player.render(tex);
            } else {
                const rect = self.player.getRect();
                rl.drawRectangleRec(rect, config.PLAYER_COLOR);
            }
        }
        self.camera.rl_camera.end();

        // === Screen-space rendering (HUD & overlays — not affected by camera) ===
        self.player.renderHUD(self.has_gamepad, self.gamepad_name);

        // Render terminal hint if all bugs defeated
        if (self.all_bugs_defeated and self.state == .playing) {
            self.renderTerminalHint();
        }

        // Render state-specific overlays
        switch (self.state) {
            .paused => self.renderPausedOverlay(),
            .victory => self.renderVictoryOverlay(),
            else => {},
        }

        // On-screen touch controls (web/tablet only; no-op on native and until a
        // touch is detected). Drawn last so the buttons sit above the HUD/overlays.
        touch.render(self.state);
    }

    fn renderPausedOverlay(self: *Self) void {
        // Semi-transparent overlay
        var overlay_color = rl.Color.white;
        overlay_color.a = 150;
        rl.drawRectangle(0, 0, config.SCREEN_WIDTH, config.SCREEN_HEIGHT, overlay_color);
        overlay_color.r = 0;
        overlay_color.g = 0;
        overlay_color.b = 0;
        rl.drawRectangle(0, 0, config.SCREEN_WIDTH, config.SCREEN_HEIGHT, overlay_color);

        // Pause text
        rl.drawText("PAUSED", config.SCREEN_WIDTH / 2 - 80, config.SCREEN_HEIGHT / 2 - 30, 40, config.HUD_COLOR);
        var continue_buf: [96]u8 = undefined;
        const continue_prompt = controls.getActionPrompt(.pause, self.has_gamepad);
        const continue_text = std.fmt.bufPrintZ(&continue_buf, "Press {s} to continue", .{continue_prompt}) catch "Press P or ESC to continue";
        const continue_text_width = rl.measureText(continue_text, 20);
        const continue_x: i32 = @divTrunc(config.SCREEN_WIDTH - continue_text_width, 2);
        rl.drawText(continue_text, continue_x, config.SCREEN_HEIGHT / 2 + 20, 20, config.HUD_COLOR);
    }

    fn renderVictoryOverlay(self: *Self) void {
        // Semi-transparent overlay
        var overlay_color = rl.Color.black;
        overlay_color.a = 150;
        rl.drawRectangle(0, 0, config.SCREEN_WIDTH, config.SCREEN_HEIGHT, overlay_color);

        var green = rl.Color.green;
        green.a = 255;

        if (self.game_complete) {
            // Final victory — all levels beaten
            rl.drawText("You beat the game!", config.SCREEN_WIDTH / 2 - 160, config.SCREEN_HEIGHT / 2 - 60, 40, green);
            rl.drawText("All PRs merged successfully!", config.SCREEN_WIDTH / 2 - 160, config.SCREEN_HEIGHT / 2 - 15, 24, green);

            // Final score display
            var score_buf: [64]u8 = undefined;
            const score_text = std.fmt.bufPrintZ(&score_buf, "Final Score: {d}", .{self.player.score}) catch "Final Score: ???";
            rl.drawText(score_text, config.SCREEN_WIDTH / 2 - 80, config.SCREEN_HEIGHT / 2 + 25, 24, config.HUD_COLOR);

            const credits_text = "Press any button for the credits";
            const credits_text_width = rl.measureText(credits_text, 20);
            const credits_x: i32 = @divTrunc(config.SCREEN_WIDTH - credits_text_width, 2);
            rl.drawText(credits_text, credits_x, config.SCREEN_HEIGHT / 2 + 65, 20, config.HUD_COLOR);
        } else {
            // Level complete — more levels ahead
            // Show which level was completed (current_level is 0-indexed, display as 1-indexed)
            var level_buf: [64]u8 = undefined;
            const level_text = std.fmt.bufPrintZ(&level_buf, "PR Submitted - Level {d} Complete!", .{self.current_level + 1}) catch "PR Submitted - Level Complete!";
            // Measure and center the level text to ensure proper alignment on any screen size
            const level_text_width: i32 = rl.measureText(level_text, 32);
            const level_x: i32 = @divTrunc(config.SCREEN_WIDTH - level_text_width, 2);
            rl.drawText(level_text, level_x, config.SCREEN_HEIGHT / 2 - 60, 32, green);

            // Score display
            var score_buf: [64]u8 = undefined;
            const score_text = std.fmt.bufPrintZ(&score_buf, "Score: {d}", .{self.player.score}) catch "Score: ???";
            const score_text_width: i32 = rl.measureText(score_text, 24);
            const score_x: i32 = @divTrunc(config.SCREEN_WIDTH - score_text_width, 2);
            rl.drawText(score_text, score_x, config.SCREEN_HEIGHT / 2 - 10, 24, config.HUD_COLOR);

            var continue_buf: [112]u8 = undefined;
            const continue_prompt = controls.getActionPrompt(.submit, self.has_gamepad);
            const continue_text = std.fmt.bufPrintZ(&continue_buf, "Press {s} to continue", .{continue_prompt}) catch "Press Enter to continue";
            const continue_text_width = rl.measureText(continue_text, 20);
            const continue_x: i32 = @divTrunc(config.SCREEN_WIDTH - continue_text_width, 2);
            rl.drawText(continue_text, continue_x, config.SCREEN_HEIGHT / 2 + 30, 20, config.HUD_COLOR);
        }
    }

    fn renderCredits(self: *Self) void {
        // NOTE: do NOT clear the framebuffer here. main.zig already clears the
        // whole frame to BACKGROUND_COLOR and then draws the animated circuit
        // background (background.render) *before* this runs. Clearing again
        // would wipe that backdrop. On native it only survived by accident —
        // raylib's batched geometry flushed after the clear — but on the web
        // build the clear erased the chips/traces/grid, leaving just the dots.

        // First line's top starts just below the screen, then rises as the
        // scroll value grows.
        var cursor_y: f32 = @as(f32, @floatFromInt(config.SCREEN_HEIGHT)) - self.credits_scroll;

        for (credit_lines) |line| {
            const line_h: f32 = @floatFromInt(line.size + CREDIT_LINE_PADDING);

            // Only draw lines that fall within (or just outside) the viewport.
            if (line.text.len > 0 and cursor_y > -line_h and cursor_y < @as(f32, @floatFromInt(config.SCREEN_HEIGHT))) {
                const text_width = rl.measureText(line.text, line.size);
                const x = @divTrunc(config.SCREEN_WIDTH - text_width, 2);
                rl.drawText(line.text, x, @intFromFloat(cursor_y), line.size, line.color);
            }

            cursor_y += line_h;
        }

        // Once the roll has settled, show a gentle flashing restart prompt.
        if (self.credits_scroll >= creditsMaxScroll()) {
            var prompt_buf: [96]u8 = undefined;
            const restart_prompt = controls.getActionPrompt(.restart, self.has_gamepad);
            const prompt = std.fmt.bufPrintZ(&prompt_buf, "Press {s} to play again", .{restart_prompt}) catch "Press R to play again";
            const prompt_width = rl.measureText(prompt, 18);
            const prompt_x: i32 = @divTrunc(config.SCREEN_WIDTH - prompt_width, 2);

            const time = @as(f32, @floatCast(rl.getTime()));
            const alpha = @as(u8, @intFromFloat(127.0 + 127.0 * @sin(time * 4.0)));
            var prompt_color = config.HUD_COLOR;
            prompt_color.a = alpha;
            rl.drawText(prompt, prompt_x, config.SCREEN_HEIGHT - 40, 18, prompt_color);
        }
    }

    fn renderTerminal(self: *Self) void {
        if (self.terminal_pos) |term| {
            const px = term.x * config.TILE_SIZE;
            const py = term.y * config.TILE_SIZE;

            // Terminal body (2x2 tiles)
            const body_color = rl.Color{ .r = 30, .g = 30, .b = 35, .a = 255 };
            rl.drawRectangle(px, py, 32, 32, body_color);

            // Screen area
            const screen_color = if (self.all_bugs_defeated)
                rl.Color{ .r = 0, .g = 200, .b = 100, .a = 255 } // Green when active
            else
                rl.Color{ .r = 50, .g = 50, .b = 60, .a = 255 }; // Dim when inactive
            rl.drawRectangle(px + 3, py + 3, 26, 18, screen_color);

            // Terminal text/cursor
            if (self.all_bugs_defeated) {
                rl.drawText(">", px + 5, py + 5, 12, rl.Color.black);
            }

            // Stand/base
            rl.drawRectangle(px + 10, py + 24, 12, 6, rl.Color{ .r = 50, .g = 50, .b = 55, .a = 255 });

            // Border highlight
            rl.drawRectangleLines(px, py, 32, 32, rl.Color{ .r = 80, .g = 80, .b = 90, .a = 255 });
        }
    }

    fn renderTerminalHint(self: *Self) void {
        // Draw hint at top center of screen
        var hint_buf: [128]u8 = undefined;
        const submit_prompt = controls.getActionPrompt(.submit, self.has_gamepad);
        const hint = std.fmt.bufPrintZ(&hint_buf, "Bugs squashed! Go to terminal and press {s}", .{submit_prompt}) catch "Bugs squashed! Go to terminal";
        const hint_y: i32 = 90;

        // Measure the exact pixel width of the hint text and add padding so the
        // background box always covers the full length of the rendered text.
        const hint_text_width: i32 = rl.measureText(hint, 18);
        const padding: i32 = 10;
        const hint_x: i32 = @divTrunc(config.SCREEN_WIDTH - hint_text_width, 2);

        // Background box
        var bg_color = rl.Color.black;
        bg_color.a = 180;
        rl.drawRectangle(hint_x - padding, hint_y - 5, hint_text_width + (padding * 2), 30, bg_color);

        // Hint text
        rl.drawText(hint, hint_x, hint_y, 18, config.HUD_COLOR);
    }
};
