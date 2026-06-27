//! On-screen touch controls for the web / tablet build (iPad, phones, etc.).
//!
//! raylib's web backend reports multitouch points in the same fixed 800x600
//! framebuffer space the game renders to (getTouchPosition), so we can define
//! virtual buttons at fixed coordinates, hit-test every active finger against
//! them each frame, and fold the result into the normal input path. Multitouch
//! is the whole point: it lets a player hold ◀/▶ with one thumb and tap JUMP
//! with the other at the same time — something the browser's single synthesized
//! mouse cannot express.
//!
//! Everything here is compiled in only on the web target. On native builds
//! `is_web` is comptime-false, so every entry point collapses to a no-op /
//! default and not a single raylib touch or draw call is emitted — desktop is
//! completely untouched.

const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const config = @import("config.zig");

const is_web = builtin.target.os.tag == .emscripten;

const GW: f32 = @floatFromInt(config.GAME_WIDTH);
const GH: f32 = @floatFromInt(config.GAME_HEIGHT);

// --- Virtual button geometry (in the 800x600 framebuffer space) -------------
// Left thumb gets the two movement buttons in the bottom-left; the right thumb
// gets a larger JUMP button in the bottom-right. The pause button sits top-right
// to clear the score/lives/health HUD (top-left) and the HTML fullscreen button
// (very top-right corner of the canvas).
const dpad_r: f32 = 56; // movement button radius
const jump_r: f32 = 70; // jump button radius (deliberately bigger)
const margin: f32 = 30;

const left_c = Vec{ .x = margin + dpad_r, .y = GH - margin - dpad_r };
const right_c = Vec{ .x = margin + dpad_r * 3 + 24, .y = GH - margin - dpad_r };
const jump_c = Vec{ .x = GW - margin - jump_r, .y = GH - margin - jump_r };
const pause_rect = rl.Rectangle{ .x = GW - 64 - 70, .y = 16, .width = 64, .height = 48 };

const Vec = rl.Vector2;

const accent = rl.Color{ .r = 74, .g = 214, .b = 196, .a = 255 };

// --- Per-frame state --------------------------------------------------------
var seen_touch: bool = false; // have we ever seen a finger? (controls UI visibility)
var left_held: bool = false;
var right_held: bool = false;
var jump_held: bool = false;
var jump_held_prev: bool = false;
var pause_held: bool = false;
var pause_held_prev: bool = false;
var fresh_tap: bool = false; // a brand-new finger touched down this frame

// Touch-point ids active last frame, used to detect a *new* tap (rising edge)
// robustly even when other fingers are already down.
var prev_ids: [16]i32 = [_]i32{-1} ** 16;
var prev_id_count: usize = 0;

/// Sample all active touch points and recompute button state. Call once per
/// frame, before anything reads the queries below (controls.poll does this).
pub fn update() void {
    if (!is_web) return;

    jump_held_prev = jump_held;
    pause_held_prev = pause_held;

    left_held = false;
    right_held = false;
    jump_held = false;
    pause_held = false;

    const count: usize = @intCast(@max(0, rl.getTouchPointCount()));
    if (count > 0) seen_touch = true;

    var cur_ids: [16]i32 = [_]i32{-1} ** 16;
    var cur_id_count: usize = 0;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const idx: i32 = @intCast(i);
        const p = rl.getTouchPosition(idx);

        if (rl.checkCollisionPointCircle(p, left_c, dpad_r)) left_held = true;
        if (rl.checkCollisionPointCircle(p, right_c, dpad_r)) right_held = true;
        if (rl.checkCollisionPointCircle(p, jump_c, jump_r)) jump_held = true;
        if (rl.checkCollisionPointRec(p, pause_rect)) pause_held = true;

        if (cur_id_count < cur_ids.len) {
            cur_ids[cur_id_count] = rl.getTouchPointId(idx);
            cur_id_count += 1;
        }
    }

    // A fresh tap = an id present now that was not present last frame.
    fresh_tap = false;
    for (cur_ids[0..cur_id_count]) |id| {
        var was_down = false;
        for (prev_ids[0..prev_id_count]) |pid| {
            if (pid == id) {
                was_down = true;
                break;
            }
        }
        if (!was_down) {
            fresh_tap = true;
            break;
        }
    }

    prev_ids = cur_ids;
    prev_id_count = cur_id_count;
}

// --- Queries (folded into FrameInput / used by menu handlers) ---------------

pub fn isLeftDown() bool {
    return is_web and left_held;
}
pub fn isRightDown() bool {
    return is_web and right_held;
}
pub fn isJumpDown() bool {
    return is_web and jump_held;
}
pub fn isJumpPressed() bool {
    return is_web and jump_held and !jump_held_prev;
}
pub fn isPausePressed() bool {
    return is_web and pause_held and !pause_held_prev;
}

/// True on the frame a new finger touches down anywhere. Menu screens
/// (opening / paused / game over / victory / credits) treat this as
/// "confirm / continue" so the whole screen is one big button.
pub fn anyTapPressed() bool {
    return is_web and fresh_tap;
}

/// True once any touch has been seen this session. Used to decide whether to
/// draw the on-screen controls at all, so desktop (mouse/keyboard) users never
/// see them.
pub fn isActive() bool {
    return is_web and seen_touch;
}

// --- Rendering --------------------------------------------------------------

const GameState = @import("game.zig").GameState;

/// Draw the on-screen controls appropriate to the current screen. No-op on
/// native, and on web until the first touch is detected.
pub fn render(state: GameState) void {
    if (!is_web or !seen_touch) return;

    switch (state) {
        .playing => {
            drawDpadButton(left_c, left_held, .left);
            drawDpadButton(right_c, right_held, .right);
            drawJumpButton();
            drawPauseButton(false);
        },
        .paused => {
            drawPauseButton(true);
            drawCenterButton("TAP TO RESUME");
        },
        .game_over => drawCenterButton("RESTART"),
        .victory => drawCenterButton("TAP TO CONTINUE"),
        else => {},
    }
}

const Dir = enum { left, right };

fn fillFor(held: bool) rl.Color {
    return rl.Color{ .r = accent.r, .g = accent.g, .b = accent.b, .a = if (held) 150 else 60 };
}

fn drawDpadButton(c: Vec, held: bool, dir: Dir) void {
    rl.drawCircleV(c, dpad_r, fillFor(held));
    rl.drawCircleLinesV(c, dpad_r, accent);

    // Arrow triangle. Backface culling is off in raylib's 2D path, so winding
    // does not matter here (cf. the moving-platform chevrons in platform.zig).
    const s = dpad_r * 0.45;
    switch (dir) {
        .left => rl.drawTriangle(
            .{ .x = c.x - s, .y = c.y },
            .{ .x = c.x + s * 0.7, .y = c.y - s },
            .{ .x = c.x + s * 0.7, .y = c.y + s },
            rl.Color.white,
        ),
        .right => rl.drawTriangle(
            .{ .x = c.x + s, .y = c.y },
            .{ .x = c.x - s * 0.7, .y = c.y + s },
            .{ .x = c.x - s * 0.7, .y = c.y - s },
            rl.Color.white,
        ),
    }
}

fn drawJumpButton() void {
    rl.drawCircleV(jump_c, jump_r, fillFor(jump_held));
    rl.drawCircleLinesV(jump_c, jump_r, accent);

    // Up arrow.
    const s = jump_r * 0.4;
    rl.drawTriangle(
        .{ .x = jump_c.x, .y = jump_c.y - s - 6 },
        .{ .x = jump_c.x - s, .y = jump_c.y + 2 },
        .{ .x = jump_c.x + s, .y = jump_c.y + 2 },
        rl.Color.white,
    );

    const label = "JUMP";
    const fs = 18;
    const w = rl.measureText(label, fs);
    rl.drawText(label, @as(i32, @intFromFloat(jump_c.x)) - @divTrunc(w, 2), @as(i32, @intFromFloat(jump_c.y)) + 14, fs, rl.Color.white);
}

fn drawPauseButton(is_paused: bool) void {
    rl.drawRectangleRounded(pause_rect, 0.3, 6, fillFor(pause_held));
    rl.drawRectangleRoundedLinesEx(pause_rect, 0.3, 6, 1.5, accent);

    const cx = pause_rect.x + pause_rect.width / 2;
    const cy = pause_rect.y + pause_rect.height / 2;
    if (is_paused) {
        // Play triangle (resume).
        rl.drawTriangle(
            .{ .x = cx - 7, .y = cy - 10 },
            .{ .x = cx - 7, .y = cy + 10 },
            .{ .x = cx + 11, .y = cy },
            rl.Color.white,
        );
    } else {
        // Two pause bars.
        rl.drawRectangle(@intFromFloat(cx - 9), @intFromFloat(cy - 10), 6, 20, rl.Color.white);
        rl.drawRectangle(@intFromFloat(cx + 3), @intFromFloat(cy - 10), 6, 20, rl.Color.white);
    }
}

/// A wide pill near the bottom of the screen used as the touch affordance on
/// menu screens. The whole screen already accepts a tap (anyTapPressed), so
/// this is purely a visual cue showing where to press.
fn drawCenterButton(label: [:0]const u8) void {
    const fs = 28;
    const w: f32 = @floatFromInt(rl.measureText(label, fs));
    const pad: f32 = 28;
    const rect = rl.Rectangle{
        .x = GW / 2 - (w / 2 + pad),
        .y = GH - 110,
        .width = w + pad * 2,
        .height = 56,
    };
    rl.drawRectangleRounded(rect, 0.5, 8, rl.Color{ .r = accent.r, .g = accent.g, .b = accent.b, .a = 70 });
    rl.drawRectangleRoundedLinesEx(rect, 0.5, 8, 2, accent);
    rl.drawText(
        label,
        @as(i32, @intFromFloat(rect.x + pad)),
        @as(i32, @intFromFloat(rect.y + 14)),
        fs,
        rl.Color.white,
    );
}
