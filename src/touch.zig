//! Gesture touch controls for the web / tablet build (iPad, phones, etc.).
//!
//! Instead of fixed on-screen buttons (which ate the bottom third of the
//! screen), the whole play area is the controller:
//!
//!   * Tap anywhere      -> jump
//!   * Hold & swipe left  -> run left  (for as long as the finger stays left)
//!   * Hold & swipe right -> run right
//!
//! Movement is a "relative joystick": each finger remembers where it first
//! touched down, and the character runs in the direction the finger has since
//! been dragged. Releasing back toward the start stops the run. Because raylib's
//! web backend reports every finger separately (getTouchPosition by index), one
//! thumb can hold a run while the other taps to jump at the same time — the
//! multitouch that a browser's single synthesized mouse cannot express.
//!
//! Tap vs. swipe is decided per finger: a finger that never travels past the
//! move deadzone and lifts again quickly is a tap (jump); a finger that crosses
//! the deadzone becomes a move and can no longer fire a jump. Because a tap is
//! only known on release, the jump fires on lift — but to keep jumps full
//! height (the player physics use a held-jump flag for variable height,
//! player.zig) the held flag is latched on for a short window after the tap.
//!
//! A small pause button is kept top-right; a touch that starts on it pauses
//! rather than moving/jumping. Everything here compiles in only on the web
//! target: on native `is_web` is comptime-false and every entry point collapses
//! to a no-op, so desktop is completely untouched.

const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const config = @import("config.zig");

const is_web = builtin.target.os.tag == .emscripten;

const GW: f32 = @floatFromInt(config.GAME_WIDTH);
const GH: f32 = @floatFromInt(config.GAME_HEIGHT);

const Vec = rl.Vector2;
const accent = rl.Color{ .r = 74, .g = 214, .b = 196, .a = 255 };

// --- Tuning (all in the 800x600 framebuffer space) --------------------------
const move_deadzone: f32 = 36; // horizontal travel before a finger becomes a "move"
const move_hysteresis: f32 = 12; // |dx| under this (while moving) = standing still
const tap_max_move: f32 = 24; // a tap must not drift more than this
const tap_max_time: f64 = 0.30; // ...nor be held longer than this (seconds)
const jump_hold_window: f32 = 0.35; // how long the jump flag stays latched after a tap

// Small pause button, top-right, clear of the HUD (top-left) and the HTML
// fullscreen button (very top-right corner of the canvas).
const pause_rect = rl.Rectangle{ .x = GW - 64 - 70, .y = 16, .width = 64, .height = 48 };

// --- Per-finger tracking ----------------------------------------------------
const Kind = enum { pending, move, pause };

const Tracked = struct {
    id: i32 = -1,
    active: bool = false,
    kind: Kind = .pending,
    start: Vec = .{ .x = 0, .y = 0 },
    last: Vec = .{ .x = 0, .y = 0 },
    start_time: f64 = 0,
    dir: i32 = 0, // -1 left, 0 none, +1 right (only meaningful for .move)
};

var tracked: [16]Tracked = [_]Tracked{.{}} ** 16;

// --- Aggregated per-frame state (read by the queries below) ------------------
var seen_touch: bool = false; // ever seen a finger? (controls UI visibility)
var has_interacted: bool = false; // jumped or moved at least once (hides the hint)
var left_held: bool = false;
var right_held: bool = false;
var jump_pressed: bool = false; // rising edge: a tap lifted this frame
var jump_hold_timer: f32 = 0; // > 0 => report jump as held (full-height jumps)
var pause_pressed: bool = false; // rising edge: a finger landed on the pause button
var pause_active: bool = false; // a finger is currently on the pause button (for highlight)
var fresh_tap: bool = false; // a brand-new finger touched down this frame (menus)

fn findTracked(id: i32) ?*Tracked {
    for (&tracked) |*t| {
        if (t.active and t.id == id) return t;
    }
    return null;
}

fn freeSlot() ?*Tracked {
    for (&tracked) |*t| {
        if (!t.active) return t;
    }
    return null;
}

/// Sample all active touch points and recompute gesture state. Call once per
/// frame, before anything reads the queries below (controls.poll does this).
pub fn update() void {
    if (!is_web) return;

    const now = rl.getTime();
    const dt = rl.getFrameTime();

    // Reset per-frame edges; decay the latched jump-hold window.
    jump_pressed = false;
    pause_pressed = false;
    fresh_tap = false;
    if (jump_hold_timer > 0) jump_hold_timer = @max(0, jump_hold_timer - dt);

    // Mark every tracked finger unseen; we re-confirm the ones still down.
    var seen_this_frame: [16]bool = [_]bool{false} ** 16;

    const count: usize = @intCast(@max(0, rl.getTouchPointCount()));
    if (count > 0) seen_touch = true;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const idx: i32 = @intCast(i);
        const id = rl.getTouchPointId(idx);
        const p = rl.getTouchPosition(idx);

        if (findTracked(id)) |t| {
            t.last = p;
            for (&tracked, 0..) |*tt, k| {
                if (tt == t) seen_this_frame[k] = true;
            }
        } else {
            // New finger down.
            fresh_tap = true;
            const slot = freeSlot() orelse continue;
            slot.* = .{
                .id = id,
                .active = true,
                .start = p,
                .last = p,
                .start_time = now,
                .kind = if (rl.checkCollisionPointRec(p, pause_rect)) .pause else .pending,
            };
            for (&tracked, 0..) |*tt, k| {
                if (tt == slot) seen_this_frame[k] = true;
            }
            if (slot.kind == .pause) {
                pause_pressed = true; // fire pause immediately on press
            }
        }
    }

    // Promote pending fingers to moves once they cross the deadzone, and resolve
    // their current direction. Detect releases (tracked but not seen) and turn a
    // quick, near-stationary pending release into a jump.
    left_held = false;
    right_held = false;
    pause_active = false;

    for (&tracked, 0..) |*t, k| {
        if (!t.active) continue;

        if (!seen_this_frame[k]) {
            // Finger lifted this frame.
            if (t.kind == .pending) {
                const ddx = t.last.x - t.start.x;
                const ddy = t.last.y - t.start.y;
                const dist2 = ddx * ddx + ddy * ddy;
                if ((now - t.start_time) <= tap_max_time and dist2 <= tap_max_move * tap_max_move) {
                    jump_pressed = true;
                    jump_hold_timer = jump_hold_window;
                    has_interacted = true;
                }
            }
            t.* = .{}; // free the slot
            continue;
        }

        const dx = t.last.x - t.start.x;
        if (t.kind == .pending and @abs(dx) > move_deadzone) {
            t.kind = .move;
            has_interacted = true;
        }
        if (t.kind == .move) {
            t.dir = if (dx <= -move_hysteresis) -1 else if (dx >= move_hysteresis) 1 else 0;
            if (t.dir < 0) left_held = true;
            if (t.dir > 0) right_held = true;
        }
        if (t.kind == .pause) pause_active = true;
    }
}

// --- Queries (folded into FrameInput / used by menu handlers) ---------------

pub fn isLeftDown() bool {
    return is_web and left_held;
}
pub fn isRightDown() bool {
    return is_web and right_held;
}
/// Held while a tap-jump is still within its latch window, so the variable
/// jump-height physics (player.zig) produce a full jump from a quick tap.
pub fn isJumpDown() bool {
    return is_web and jump_hold_timer > 0;
}
pub fn isJumpPressed() bool {
    return is_web and jump_pressed;
}
pub fn isPausePressed() bool {
    return is_web and pause_pressed;
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

/// Draw the (minimal) touch UI for the current screen. No-op on native, and on
/// web until the first touch is detected.
pub fn render(state: GameState) void {
    if (!is_web or !seen_touch) return;

    switch (state) {
        .playing => {
            drawPauseButton(false);
            if (!has_interacted) drawHint();
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

fn fillFor(held: bool) rl.Color {
    return rl.Color{ .r = accent.r, .g = accent.g, .b = accent.b, .a = if (held) 150 else 60 };
}

/// Faint one-time hint shown until the player first jumps or moves.
fn drawHint() void {
    const label = "Tap to Jump  -  Swipe to Move";
    const fs = 20;
    const w = rl.measureText(label, fs);
    const x = @divTrunc(config.GAME_WIDTH, 2) - @divTrunc(w, 2);
    const y = config.GAME_HEIGHT - 46;
    rl.drawText(label, x, y, fs, rl.Color{ .r = accent.r, .g = accent.g, .b = accent.b, .a = 150 });
}

fn drawPauseButton(is_paused: bool) void {
    rl.drawRectangleRounded(pause_rect, 0.3, 6, fillFor(pause_active));
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
