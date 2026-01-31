//! Programmer_Man - A 2D Platformer in Zig with raylib
//! Main entry point and game loop

const std = @import("std");
const rl = @import("raylib");

const Game = @import("game.zig").Game;
const config = @import("config.zig");

pub fn main() !void {
    // Initialize raylib window
    rl.initWindow(config.SCREEN_WIDTH, config.SCREEN_HEIGHT, "Programmer_Man");
    defer rl.closeWindow();

    // Initialize audio device
    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.setTargetFPS(60);

    // Initialize game state
    var game = Game.init();
    defer game.deinit();
    game.loadLevel(0);

    // Main game loop
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();

        // Update game logic
        game.update(dt);

        // Render
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(config.BACKGROUND_COLOR);
        game.render();
    }

    // Ensure clean exit - explicitly flush any pending operations
    std.debug.print("Game window closed, shutting down...\n", .{});
}

test "basic game initialization" {
    const game = Game.init();
    _ = game;
}
