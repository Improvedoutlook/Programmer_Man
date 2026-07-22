//! Programmer_Man - A 2D Platformer in Zig with raylib
//! Main entry point and game loop

const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");

const Game = @import("game.zig").Game;
const Background = @import("background.zig").Background;
const config = @import("config.zig");
const controls = @import("controls.zig");

pub fn main() !void {
    // Enable window resizing BEFORE creating window.
    // Native only: on web the <canvas> size is owned by the HTML shell + CSS
    // (see PM_BrowserGameplay.md Phase 5), so raylib must not also drive window
    // resizing. We keep a fixed 800x600 framebuffer on web and let CSS scale it.
    if (builtin.target.os.tag != .emscripten and config.WINDOW_RESIZABLE) {
        const flags: rl.ConfigFlags = @bitCast(@as(u32, 0x00000004));
        rl.setConfigFlags(flags);
    }

    // Initialize raylib window
    rl.initWindow(config.INITIAL_WINDOW_WIDTH, config.INITIAL_WINDOW_HEIGHT, "Programmer_Man");

    // Initialize audio device
    rl.initAudioDevice();

    rl.setTargetFPS(60);
    controls.init();

    // On web the CSS inside shell.html already scales the 800×600 <canvas> to
    // fill the #stage div, so we don't need an intermediate render texture.
    // On native we still render to an FBO first so the game can be scaled to
    // any window size with letterboxing.
    const is_web = builtin.target.os.tag == .emscripten;

    // NOTE: no `defer` teardown here on purpose — shutdown is explicit at the
    // bottom of this function so that "window closed" and "process gone" are the
    // same event (see the SHUTDOWN block). The only way out of main before that
    // point is an init failure, and the process exits on that path anyway.
    const render_target = if (!is_web)
        try rl.loadRenderTexture(config.GAME_WIDTH, config.GAME_HEIGHT)
    else
        undefined;
    if (!is_web) rl.setTextureFilter(render_target.texture, .point);

    // Initialize game state
    var game = Game.init();

    // Initialize background effects
    var background = Background.init();

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Clamp dt to prevent physics explosion when the OS blocks the
        // event loop (e.g. window resize on Windows).  Without this the
        // player accumulates huge velocity in a single frame and falls
        // through the world, losing a life.
        const raw_dt = rl.getFrameTime();
        const dt = if (raw_dt > 0.1) @as(f32, 0.0) else raw_dt;

        // === UPDATE (all game logic at fixed 800x600 resolution) ===
        game.update(dt);
        background.update(dt);

        // === RENDER ===
        if (is_web) {
            // Web: draw directly to the canvas — CSS handles scaling to fit the
            // browser window, so the FBO intermediate step is not needed.
            rl.beginDrawing();
            rl.clearBackground(config.BACKGROUND_COLOR);
            background.render(game.getCameraWorldX());
            game.render();
            rl.endDrawing();
        } else {
            // Native: render to a fixed 800×600 FBO, then scale+letterbox to
            // fit whatever size window the user has opened.
            rl.beginTextureMode(render_target);
            rl.clearBackground(config.BACKGROUND_COLOR);
            background.render(game.getCameraWorldX());
            game.render();
            rl.endTextureMode();

            const window_width = rl.getScreenWidth();
            const window_height = rl.getScreenHeight();
            const scale = calculateScale(config.GAME_WIDTH, config.GAME_HEIGHT, window_width, window_height);
            const scaled_width: f32 = @as(f32, @floatFromInt(config.GAME_WIDTH)) * scale;
            const scaled_height: f32 = @as(f32, @floatFromInt(config.GAME_HEIGHT)) * scale;
            const offset_x: f32 = (@as(f32, @floatFromInt(window_width)) - scaled_width) / 2.0;
            const offset_y: f32 = (@as(f32, @floatFromInt(window_height)) - scaled_height) / 2.0;

            rl.beginDrawing();
            rl.clearBackground(rl.Color.black);
            rl.drawTexturePro(
                render_target.texture,
                rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(config.GAME_WIDTH), .height = @floatFromInt(-config.GAME_HEIGHT) },
                rl.Rectangle{ .x = offset_x, .y = offset_y, .width = scaled_width, .height = scaled_height },
                rl.Vector2{ .x = 0, .y = 0 },
                0,
                rl.Color.white,
            );
            rl.endDrawing();
        }
    }

    // === SHUTDOWN ===
    // The window is gone (X button, Alt+F4, or the exit key). From here the only
    // acceptable outcome is a dead process: closing the window must be equivalent
    // to killing the game, with no windowless programmer_man.exe left behind.
    //
    // Graceful teardown alone doesn't guarantee that. raylib's shutdown path can
    // block indefinitely on Windows — miniaudio's WASAPI device uninit inside
    // closeAudioDevice() is the usual suspect, and unloading five streaming
    // rl.Music handles first gives it plenty of chances. So we arm a watchdog
    // thread FIRST, then tear down: whichever finishes first ends the process.
    //
    // Note (web): under -sASYNCIFY the browser owns the event loop and
    // windowShouldClose() never returns true, so nothing below runs on
    // emscripten — closing the tab is what reclaims everything there. Do NOT put
    // gameplay-critical logic after the loop, or it silently never executes on
    // the web build.
    if (!is_web) {
        if (std.Thread.spawn(.{}, shutdownWatchdog, .{})) |watchdog| {
            watchdog.detach();
        } else |_| {
            // Couldn't spawn the watchdog — teardown below still runs, it just
            // has no backstop. Not worth aborting shutdown over.
        }
    }

    game.deinit();
    if (!is_web) rl.unloadRenderTexture(render_target);
    rl.closeAudioDevice();
    rl.closeWindow();

    hardExit();
}

/// How long graceful teardown gets after the window closes before the process is
/// terminated outright. Long enough for a healthy shutdown (which takes single
/// -digit milliseconds), short enough that a wedged one is never a mystery
/// process in Task Manager.
const SHUTDOWN_GRACE_MS: u64 = 2000;

/// Backstop for a teardown that never returns. Runs detached, so if the main
/// thread is still inside raylib when the grace period expires, this kills the
/// process out from under it.
fn shutdownWatchdog() void {
    std.time.sleep(SHUTDOWN_GRACE_MS * std.time.ns_per_ms);
    hardExit();
}

/// End the process immediately, running no further teardown.
///
/// On Windows this is TerminateProcess rather than ExitProcess: ExitProcess
/// still runs DLL detach handlers and can itself block on the very audio/GPU
/// driver threads we're trying to escape. Everything this process owns —
/// memory, file handles, the audio device — is reclaimed by the OS regardless.
fn hardExit() noreturn {
    if (builtin.target.os.tag == .windows) {
        const win = std.os.windows;
        _ = win.kernel32.TerminateProcess(win.kernel32.GetCurrentProcess(), 0);
    }
    std.process.exit(0);
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

test "calculateScale preserves aspect ratio" {
    try std.testing.expect(calculateScale(800, 600, 1600, 1200) == 2.0);
    try std.testing.expect(calculateScale(800, 600, 1600, 900) == 1.5);
    try std.testing.expect(calculateScale(800, 600, 1200, 1200) == 1.5);
}
