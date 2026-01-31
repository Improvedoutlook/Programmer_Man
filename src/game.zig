//! Game module - Main game state management and coordination

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const Player = @import("player.zig").Player;
const Tilemap = @import("tilemap.zig").Tilemap;
const tilemap_builder = @import("tilemap.zig");
const BugManager = @import("enemy.zig").BugManager;
const audio = @import("audio.zig");

pub const GameState = enum {
    playing,
    paused,
    game_over,
    victory,
};

pub const Game = struct {
    player: Player,
    tilemap: Tilemap,
    bugs: BugManager,
    state: GameState,
    current_level: u8,
    music: ?audio.ChiptunePlayer,
    all_bugs_defeated: bool,
    terminal_pos: ?struct { x: i32, y: i32 },

    const Self = @This();

    pub fn init() Self {
        // Audio device is initialized in main.zig
        // Load SFX first
        audio.loadSfx();

        var music_player: ?audio.ChiptunePlayer = audio.ChiptunePlayer.init() catch null;

        if (music_player) |*m| {
            m.play();
        }

        return Self{
            .player = Player.init(),
            .tilemap = Tilemap.init(),
            .bugs = BugManager.init(),
            .state = .playing,
            .current_level = 0,
            .music = music_player,
            .all_bugs_defeated = false,
            .terminal_pos = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.music) |*music| {
            music.deinit();
        }
        audio.unloadSfx();
    }

    pub fn loadLevel(self: *Self, level: u8) void {
        self.current_level = level;

        // Reset tilemap
        self.tilemap = Tilemap.init();

        // Reset bugs
        self.bugs.reset();

        // Reset terminal state
        self.all_bugs_defeated = false;

        // Load level data
        switch (level) {
            0 => {
                tilemap_builder.createLevel1(&self.tilemap);
                self.spawnBugsLevel1();
                // Terminal on far-left platform (tile y=30, terminal is 2 tiles tall, so start at y=28 to sit on top)
                self.terminal_pos = .{ .x = 6, .y = 28 };
            },
            else => {
                tilemap_builder.createLevel1(&self.tilemap);
                self.spawnBugsLevel1();
                self.terminal_pos = .{ .x = 6, .y = 28 };
            },
        }

        // Reset player
        self.player = Player.init();
        self.state = .playing;
    }

    fn spawnBugsLevel1(self: *Self) void {
        // Spawn bugs at strategic locations
        // Bug on ground floor, left side
        self.bugs.spawn(8, 34, true);

        // Bug on ground floor, middle
        self.bugs.spawn(22, 34, false);

        // Bug on Platform 2
        self.bugs.spawn(20, 27, true);

        // Bug on Platform 3
        self.bugs.spawn(34, 23, false);

        // Bug on high platform
        self.bugs.spawn(44, 17, true);
    }

    pub fn update(self: *Self, dt: f32) void {
        // Update music stream
        if (self.music) |*music| {
            music.update(dt);
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

        // Check player-enemy collisions
        self.bugs.checkPlayerCollision(&self.player);

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
                // Terminal bounding box (2 tiles wide, extended height for easier interaction)
                const term_x = @as(f32, @floatFromInt(term.x * config.TILE_SIZE));
                const term_y = @as(f32, @floatFromInt(term.y * config.TILE_SIZE));
                const term_w: f32 = 32.0;
                const term_h: f32 = 48.0; // Extended to reach down to platform level

                // Player bounding box
                const px = self.player.x;
                const py = self.player.y;
                const pw = config.PLAYER_WIDTH;
                const ph = config.PLAYER_HEIGHT;

                // AABB overlap check
                const overlaps = px < term_x + term_w and
                    px + pw > term_x and
                    py < term_y + term_h and
                    py + ph > term_y;

                // Check for Enter/Return key (both main keyboard and numpad)
                const enter_pressed = rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter) or rl.isKeyPressed(.e);
                
                if (overlaps and enter_pressed) {
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
            self.loadLevel(self.current_level);
        }
    }

    fn updateVictory(self: *Self) void {
        if (rl.isKeyPressed(.r)) {
            self.loadLevel(self.current_level);
        }
    }

    pub fn render(self: *Self) void {
        // Render background first
        self.tilemap.renderBackground();

        // Render tilemap
        self.tilemap.render();

        // Render terminal
        self.renderTerminal();

        // Render enemies
        self.bugs.render();

        // Render player
        self.player.render();

        // Render HUD
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
        const hint_y = 60;

        // Background box
        var bg_color = rl.Color.black;
        bg_color.a = 180;
        rl.drawRectangle(hint_x - 10, hint_y - 5, hint_width + 20, 30, bg_color);

        // Hint text
        rl.drawText(hint, hint_x, hint_y, 18, config.HUD_COLOR);
    }
};
