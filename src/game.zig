//! Game module - Main game state management and coordination
//! Game module - Main game state management and coordination

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const controls = @import("controls.zig");
const Player = @import("player.zig").Player;
const Tilemap = @import("tilemap.zig").Tilemap;
const tilemap_builder = @import("tilemap.zig");
const BugManager = @import("enemy.zig").BugManager;
const AiType = @import("tilemap.zig").AiType;
const SparkManager = @import("hazards.zig").SparkManager;
const audio = @import("audio.zig");

pub const GameState = enum {
    opening,
    playing,
    paused,
    game_over,
    victory,
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

pub const Game = struct {
    player: Player,
    tilemap: Tilemap,
    bugs: BugManager,
    sparks: SparkManager,
    camera: Camera,
    state: GameState,
    current_level: u8,
    music: ?audio.ChiptunePlayer,
    victory_music: ?audio.VictoryMusic,
    game_over_music: ?audio.GameOverMusic,
    opening_music: ?audio.OpeningMusic,
    all_bugs_defeated: bool,
    terminal_pos: ?struct { x: i32, y: i32 },
    player_texture: ?rl.Texture2D,
    opening_texture: ?rl.Texture2D,
    game_complete: bool,
    has_gamepad: bool,
    gamepad_name: ?[:0]const u8,

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

        const player_texture = rl.loadTexture("assets/sprites/player.png") catch null;
        const opening_texture = rl.loadTexture("assets/Images/PM_OpeningImage.png") catch null;

        var game = Self{
            .player = Player.init(),
            .tilemap = Tilemap.initDefault(),
            .bugs = BugManager.init(),
            .sparks = SparkManager.init(),
            .camera = Camera.init(),
            .state = .opening,
            .current_level = 0,
            .music = music_player,
            .victory_music = victory_music_player,
            .game_over_music = game_over_music_player,
            .opening_music = opening_music_player,
            .opening_texture = opening_texture,
            .all_bugs_defeated = false,
            .terminal_pos = null,
            .player_texture = player_texture,
            .game_complete = false,
            .has_gamepad = false,
            .gamepad_name = null,
        };

        if (game.opening_music) |*m| {
            m.play();
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
            3 => .motherboard, // silicon_ascent added in Phase 2
            else => .motherboard,
        });

        // Reset bugs
        self.bugs.reset();

        // Reset sparks
        self.sparks.reset();

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

    pub fn update(self: *Self, dt: f32) void {
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

        switch (self.state) {
            .opening => self.updateOpening(input),
            .playing => self.updatePlaying(dt, input),
            .paused => self.updatePaused(input),
            .game_over => self.updateGameOver(input),
            .victory => self.updateVictory(input),
        }
    }

    fn updateOpening(self: *Self, input: controls.FrameInput) void {
        _ = input;
        if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter) or controls.isAnyGamepadButtonPressed()) {
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

        // Update player
        self.player.handleInput(input);
        self.player.update(dt, &self.tilemap);

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
        self.bugs.checkPlayerCollision(&self.player);

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
        if (input.pause_pressed) {
            self.state = .playing;
        }
    }

    fn updateGameOver(self: *Self, input: controls.FrameInput) void {
        if (input.restart_pressed) {
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
            // Final victory — press R to restart from Level 1 with fresh stats
            if (input.restart_pressed) {
                if (self.victory_music) |*victory_music| {
                    victory_music.stop();
                }
                self.game_complete = false;
                // Reset score and lives for a fresh start
                self.player.score = 0;
                self.player.lives = config.INITIAL_LIVES;
                self.loadLevel(0);
            }
        } else {
            // Level complete — press Enter to advance to next level
            if (input.submit_pressed) {
                if (self.victory_music) |*victory_music| {
                    victory_music.stop();
                }
                if (self.current_level + 1 < Self.MAX_LEVELS) {
                    self.loadLevel(self.current_level + 1);
                }
            }
        }
    }

    pub fn render(self: *Self) void {
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

            var restart_buf: [96]u8 = undefined;
            const restart_prompt = controls.getActionPrompt(.restart, self.has_gamepad);
            const restart_text = std.fmt.bufPrintZ(&restart_buf, "Press {s} to Restart", .{restart_prompt}) catch "Press R to Restart";
            const restart_text_width = rl.measureText(restart_text, 20);
            const restart_x: i32 = @divTrunc(config.SCREEN_WIDTH - restart_text_width, 2);
            rl.drawText(restart_text, restart_x, config.SCREEN_HEIGHT / 2 + 65, 20, config.HUD_COLOR);
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
