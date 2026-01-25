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

    const Self = @This();

    pub fn init() Self {
        // Audio device is initialized in main.zig
        var music_player: ?audio.ChiptunePlayer = audio.ChiptunePlayer.init() catch |err| blk: {
            std.debug.print("Failed to initialize music: {any}\n", .{err});
            std.debug.print("Continuing without music...\n", .{});
            break :blk null;
        };

        std.debug.print("Music player created: {}\n", .{music_player != null}); // ADD THIS LINE

        if (music_player) |*m| {
            std.debug.print("About to call play()...\n", .{}); // ADD THIS LINE
            m.play();
        } else {
            std.debug.print("Music player is null!\n", .{}); // ADD THIS LINE
        }

        return Self{
            .player = Player.init(),
            .tilemap = Tilemap.init(),
            .bugs = BugManager.init(),
            .state = .playing,
            .current_level = 0,
            .music = music_player,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.music) |*music| {
            music.deinit();
        }
    }

    pub fn loadLevel(self: *Self, level: u8) void {
        self.current_level = level;

        // Reset tilemap
        self.tilemap = Tilemap.init();

        // Reset bugs
        self.bugs.reset();

        // Load level data
        switch (level) {
            0 => {
                tilemap_builder.createLevel1(&self.tilemap);
                self.spawnBugsLevel1();
            },
            else => {
                tilemap_builder.createLevel1(&self.tilemap);
                self.spawnBugsLevel1();
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

        // Check for victory (all bugs defeated)
        if (self.bugs.getActiveCount() == 0) {
            self.state = .victory;
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

        // Render enemies
        self.bugs.render();

        // Render player
        self.player.render();

        // Render HUD
        self.player.renderHUD();

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
        rl.drawText("LEVEL COMPLETE!", config.SCREEN_WIDTH / 2 - 150, config.SCREEN_HEIGHT / 2 - 50, 40, green);

        // Score display
        var score_buf: [64]u8 = undefined;
        const score_text = std.fmt.bufPrintZ(&score_buf, "Final Score: {d}", .{self.player.score}) catch "Final Score: ???";
        rl.drawText(score_text, config.SCREEN_WIDTH / 2 - 80, config.SCREEN_HEIGHT / 2, 24, config.HUD_COLOR);

        rl.drawText("Press R to Restart", config.SCREEN_WIDTH / 2 - 90, config.SCREEN_HEIGHT / 2 + 40, 20, config.HUD_COLOR);
    }
};
