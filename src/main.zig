//! Programmer_Man - A 2D Platformer in Zig with raylib
//! Main entry point and game loop

const std = @import("std");
const rl = @import("raylib");

const Game = @import("game.zig").Game;
const Background = @import("background.zig").Background;
const config = @import("config.zig");

pub fn main() !void {
    // Enable window resizing BEFORE creating window
    if (config.WINDOW_RESIZABLE) {
        const flags: rl.ConfigFlags = @bitCast(@as(u32, 0x00000004));
        rl.setConfigFlags(flags);
    }

    // Initialize raylib window
    rl.initWindow(config.INITIAL_WINDOW_WIDTH, config.INITIAL_WINDOW_HEIGHT, "Programmer_Man");
    defer rl.closeWindow();

    // Initialize audio device
    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.setTargetFPS(60);

    // Create render texture for fixed internal resolution
    // This is the key to resizable windows: we always render the game at 800x600,
    // then scale that texture to fit whatever size window the user has
    const render_target = try rl.loadRenderTexture(config.GAME_WIDTH, config.GAME_HEIGHT);
    defer rl.unloadRenderTexture(render_target);

    // Try option 1 (most common):
    // rl.setTextureFilter(render_target.texture, .filter_point);

    // If that fails, try option 2:
    rl.setTextureFilter(render_target.texture, .point);

    // // If that fails, try option 3:
    // rl.setTextureFilter(render_target.texture, .nearest);

    // Initialize game state
    var game = Game.init();
    defer game.deinit();
    game.loadLevel(0);

    // Initialize background effects
    var background = Background.init();

    // Main game loop
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();

        // === UPDATE (all game logic at fixed 800x600 resolution) ===
        game.update(dt);
        background.update(dt); // ← ADD THIS! Updates particles and animations

        // === RENDER ===
        // Step 1: Render game to fixed-size texture (always 800x600)
        rl.beginTextureMode(render_target);
        {
            rl.clearBackground(config.BACKGROUND_COLOR);

            // Render background effects first (behind everything)
            background.render(); // ← ADD THIS! Draws the cool effects

            // Render game on top of background
            game.render();
        }
        rl.endTextureMode();

        // Step 2: Calculate how to scale the 800x600 game to fit the current window
        const window_width = rl.getScreenWidth();
        const window_height = rl.getScreenHeight();

        const scale = calculateScale(config.GAME_WIDTH, config.GAME_HEIGHT, window_width, window_height);

        // Calculate dimensions and position to center the scaled game
        const scaled_width: f32 = @as(f32, @floatFromInt(config.GAME_WIDTH)) * scale;
        const scaled_height: f32 = @as(f32, @floatFromInt(config.GAME_HEIGHT)) * scale;
        const offset_x: f32 = (@as(f32, @floatFromInt(window_width)) - scaled_width) / 2.0;
        const offset_y: f32 = (@as(f32, @floatFromInt(window_height)) - scaled_height) / 2.0;

        // Step 3: Draw the scaled texture to the actual window
        rl.beginDrawing();
        {
            // Black letterbox bars if window aspect ratio doesn't match game
            rl.clearBackground(rl.Color.black);

            const source = rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(config.GAME_WIDTH),
                .height = @floatFromInt(-config.GAME_HEIGHT),
            };

            const dest = rl.Rectangle{
                .x = offset_x,
                .y = offset_y,
                .width = scaled_width,
                .height = scaled_height,
            };

            rl.drawTexturePro(render_target.texture, source, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, rl.Color.white);
        }
        rl.endDrawing();
    }

    // Ensure clean exit - explicitly flush any pending operations
    std.debug.print("Game window closed, shutting down...\n", .{});
}

/// Calculates the scale factor to fit the game into the window while maintaining aspect ratio
///
/// How this works:
/// - If window is 1600x1200 and game is 800x600 → scale is 2.0 (perfect fit, no bars)
/// - If window is 1600x900 and game is 800x600 → scale_x=2.0, scale_y=1.5 → use 1.5 (black bars on sides)
/// - If window is 1200x1200 and game is 800x600 → scale_x=1.5, scale_y=2.0 → use 1.5 (black bars top/bottom)
///
/// We always use the SMALLER scale to ensure the entire game fits in the window
// Calculates the scale factor to fit the game into the window while maintaining aspect ratio
fn calculateScale(game_width: i32, game_height: i32, window_width: i32, window_height: i32) f32 {
    const scale_x: f32 = @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(game_width));
    const scale_y: f32 = @as(f32, @floatFromInt(window_height)) / @as(f32, @floatFromInt(game_height));
    return @min(scale_x, scale_y);
}

test "basic game initialization" {
    const game = Game.init();
    _ = game;
}
