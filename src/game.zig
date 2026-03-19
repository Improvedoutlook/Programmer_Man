//! Game module - Main game state management and coordination

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const Player = @import("player.zig").Player;
const Tilemap = @import("tilemap.zig").Tilemap;
const tilemap_builder = @import("tilemap.zig");
const BugManager = @import("enemy.zig").BugManager;
const SparkManager = @import("hazards.zig").SparkManager;
const audio = @import("audio.zig");

pub const GameState = enum {
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
    all_bugs_defeated: bool,
    terminal_pos: ?struct { x: i32, y: i32 },
    player_texture: ?rl.Texture2D,

    const Self = @This();

    pub fn init() Self {
        // Audio device is initialized in main.zig
        // Load SFX first
        audio.loadSfx();

        var music_player: ?audio.ChiptunePlayer = audio.ChiptunePlayer.init() catch null;

        if (music_player) |*m| {
            m.play();
        }

        const victory_music_player: ?audio.VictoryMusic = audio.VictoryMusic.init() catch null;
        const player_texture = rl.loadTexture("assets/sprites/player.png") catch null;

        return Self{
            .player = Player.init(),
            .tilemap = Tilemap.initDefault(),
            .bugs = BugManager.init(),
            .sparks = SparkManager.init(),
            .camera = Camera.init(),
            .state = .playing,
            .current_level = 0,
            .music = music_player,
            .victory_music = victory_music_player,
            .all_bugs_defeated = false,
            .terminal_pos = null,
            .player_texture = player_texture,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.music) |*music| {
            music.deinit();
        }
        if (self.victory_music) |*victory_music| {
            victory_music.deinit();
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
            else => {
                // Default fallback for any unknown level index
                tilemap_builder.createLevel1(&self.tilemap);
                self.spawnBugsLevel1();
                self.spawnSparksLevel1();
                self.terminal_pos = .{ .x = 6, .y = 28 };
            },
        }

        // Switch background music based on level
        if (self.music) |*music| {
            switch (level) {
                0 => music.switchTrack("assets/music/lost_in_hyperspace.mp3"),
                1 => music.switchTrack("assets/music/danger_streets.mp3"),
                else => music.switchTrack("assets/music/lost_in_hyperspace.mp3"),
            }
        }

        // Reset player and position at the level's spawn point
        self.player = Player.init();
        self.player.x = @as(f32, @floatFromInt(spawn_x * config.TILE_SIZE)) + config.PLAYER_WIDTH / 2;
        self.player.y = @as(f32, @floatFromInt(spawn_y * config.TILE_SIZE));
        self.state = .playing;
    }

    fn applyLevelData(self: *Self, level_data: tilemap_builder.LevelData, spawn_x: *i32, spawn_y: *i32) void {
        // Spawn bugs from loaded data
        for (0..level_data.bug_count) |i| {
            const bug = level_data.bug_spawns[i];
            const actual_speed = config.BUG_WALK_SPEED * bug.speed;
            self.bugs.spawn(bug.tile_x, bug.tile_y, bug.facing_right, actual_speed);
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
        self.bugs.spawn(8, 34, true, config.BUG_WALK_SPEED);

        // Bug on ground floor, middle
        self.bugs.spawn(22, 34, false, config.BUG_WALK_SPEED);

        // Bug on Platform 2
        self.bugs.spawn(20, 27, true, config.BUG_WALK_SPEED);

        // Bug on Platform 3
        self.bugs.spawn(34, 23, false, config.BUG_WALK_SPEED);

        // Bug on high platform
        self.bugs.spawn(44, 17, true, config.BUG_WALK_SPEED);

        // NEW: Bug on bottom far-right platform
        self.bugs.spawn(46, 34, false, config.BUG_WALK_SPEED);
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
        // Update music stream
        if (self.music) |*music| {
            music.update(dt);
        }

        // Update victory music stream
        if (self.victory_music) |*victory_music| {
            victory_music.update();
        }

        switch (self.state) {
            .playing => self.updatePlaying(dt),
            .paused => self.updatePaused(),
            .game_over => self.updateGameOver(),
            .victory => self.updateVictory(),
        }
    }

    fn updatePlaying(self: *Self, dt: f32) void {
        // Check for pause
        if (rl.isKeyPressed(.escape) or rl.isKeyPressed(.p)) {
            self.state = .paused;
            return;
        }

        // Update player
        self.player.handleInput();
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

                const px = self.player.x;
                const py = self.player.y;
                const pw = config.PLAYER_WIDTH;
                const ph = config.PLAYER_HEIGHT;

                const overlaps = px < term_x + term_w and
                    px + pw > term_x and
                    py < term_y + term_h and
                    py + ph > term_y;

                const enter_pressed = rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter) or rl.isKeyPressed(.e);

                if (overlaps and enter_pressed) {
                    // STOP BACKGROUND MUSIC AND PLAY VICTORY MUSIC
                    if (self.music) |*music| {
                        music.stop();
                    }
                    if (self.victory_music) |*victory_music| {
                        victory_music.play();
                    }

                    self.state = .victory;
                }
            }
        }
    }

    fn updatePaused(self: *Self) void {
        if (rl.isKeyPressed(.escape) or rl.isKeyPressed(.p)) {
            self.state = .playing;
        }
    }

    fn updateGameOver(self: *Self) void {
        if (rl.isKeyPressed(.r)) {
            // loadLevel now handles music switching, no need to play() here
            self.loadLevel(self.current_level);
        }
    }

    fn updateVictory(self: *Self) void {
        if (rl.isKeyPressed(.r)) {
            if (self.victory_music) |*victory_music| {
                victory_music.stop();
            }
            // loadLevel now handles music switching, no need to play() here
            self.loadLevel(self.current_level);
        }
    }

    pub fn render(self: *Self) void {
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
        self.player.renderHUD();

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

    fn renderPausedOverlay(_: *Self) void {
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
        rl.drawText("Press P or ESC to continue", config.SCREEN_WIDTH / 2 - 120, config.SCREEN_HEIGHT / 2 + 20, 20, config.HUD_COLOR);
    }

    fn renderVictoryOverlay(self: *Self) void {
        // Semi-transparent overlay
        var overlay_color = rl.Color.black;
        overlay_color.a = 150;
        rl.drawRectangle(0, 0, config.SCREEN_WIDTH, config.SCREEN_HEIGHT, overlay_color);

        // Victory text
        var green = rl.Color.green;
        green.a = 255;
        rl.drawText("You win!", config.SCREEN_WIDTH / 2 - 80, config.SCREEN_HEIGHT / 2 - 60, 40, green);
        rl.drawText("Pull request successfully submitted!", config.SCREEN_WIDTH / 2 - 180, config.SCREEN_HEIGHT / 2 - 15, 24, green);

        // Score display
        var score_buf: [64]u8 = undefined;
        const score_text = std.fmt.bufPrintZ(&score_buf, "Final Score: {d}", .{self.player.score}) catch "Final Score: ???";
        rl.drawText(score_text, config.SCREEN_WIDTH / 2 - 80, config.SCREEN_HEIGHT / 2 + 25, 24, config.HUD_COLOR);

        rl.drawText("Press R to Restart", config.SCREEN_WIDTH / 2 - 90, config.SCREEN_HEIGHT / 2 + 65, 20, config.HUD_COLOR);
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

    fn renderTerminalHint(_: *Self) void {
        // Draw hint at top center of screen
        const hint = "Bugs defeated! Go to terminal and press Enter";
        const hint_width = 360;
        const hint_x = config.SCREEN_WIDTH / 2 - hint_width / 2;
        const hint_y = 90;

        // Background box
        var bg_color = rl.Color.black;
        bg_color.a = 180;
        rl.drawRectangle(hint_x - 10, hint_y - 5, hint_width + 20, 30, bg_color);

        // Hint text
        rl.drawText(hint, hint_x, hint_y, 18, config.HUD_COLOR);
    }
};
