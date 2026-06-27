//! Centralized control bindings for keyboard and gamepad input.

const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const config = @import("config.zig");
const touch = @import("touch.zig");

// On the web build raylib reads the browser Gamepad API directly, so its
// gamepad functions (isGamepadAvailable / isGamepadButtonDown / axis movement)
// just work. The raw GLFW joystick fallback below, however, does NOT: emscripten's
// GLFW port leaves glfwJoystickIsGamepad / glfwGetJoystickHats / glfwGetJoystickGUID
// unimplemented, so calling them throws "… not implemented" the instant a pad
// button is pressed. We compile the raw path out on web and rely solely on
// raylib's mapped gamepad API there.
const is_web = builtin.target.os.tag == .emscripten;

pub const Action = enum {
    move_left,
    move_right,
    jump,
    submit,
    pause,
    restart,
};

pub const FrameInput = struct {
    move_x: f32,
    jump_pressed: bool,
    jump_down: bool,
    submit_pressed: bool,
    pause_pressed: bool,
    restart_pressed: bool,
    has_gamepad: bool,
    gamepad_name: ?[:0]const u8,
};

const ButtonBinding = struct {
    keys: []const rl.KeyboardKey,
    buttons: []const rl.GamepadButton,
};

const move_left_keys = [_]rl.KeyboardKey{ .a, .left };
const move_right_keys = [_]rl.KeyboardKey{ .d, .right };
const jump_keys = [_]rl.KeyboardKey{ .space, .w, .up };
const submit_keys = [_]rl.KeyboardKey{ .enter, .kp_enter, .e };
const pause_keys = [_]rl.KeyboardKey{ .escape, .p };
const restart_keys = [_]rl.KeyboardKey{.r};

const move_left_buttons = [_]rl.GamepadButton{.left_face_left};
const move_right_buttons = [_]rl.GamepadButton{.left_face_right};
const jump_buttons = [_]rl.GamepadButton{.right_face_down};
const submit_buttons = [_]rl.GamepadButton{.right_face_left};
const pause_buttons = [_]rl.GamepadButton{.middle_right};
const restart_buttons = [_]rl.GamepadButton{.right_face_left};
const supplemental_gamepad_mappings = @embedFile("gamecontrollerdb.txt");

var initialized = false;
var last_gamepad_state: bool = false;
var last_gamepad_index: i32 = -1;

/// Names (case-insensitive substrings) of devices that falsely register as
/// gamepads on some systems (wireless mice, keyboards, etc.).
const skipped_device_names = [_][]const u8{
    "keychron",
};

// GLFW extern declarations - available because raylib statically links GLFW.
extern fn glfwGetJoystickGUID(jid: i32) ?[*:0]const u8;
extern fn glfwJoystickIsGamepad(jid: i32) i32;
extern fn glfwGetJoystickButtons(jid: i32, count: *i32) ?[*]const u8;
extern fn glfwGetJoystickAxes(jid: i32, count: *i32) ?[*]const f32;
extern fn glfwGetJoystickHats(jid: i32, count: *i32) ?[*]const u8;

// Raw joystick state - provides a fallback input path that bypasses SDL mapping.
var raw_btn_cur = [_]u8{0} ** 32;
var raw_btn_prev = [_]u8{0} ** 32;
var raw_hat_cur: u8 = 0;
var raw_hat_prev: u8 = 0;
var raw_axis_lx: f32 = 0.0;

// True when the active gamepad has no SDL mapping and needs raw input.
var use_raw_fallback: bool = false;

// Grace period: ignore gamepad input for a few frames after (re)connection
// to prevent phantom button presses from connect/disconnect cycling.
var gamepad_connect_grace: u8 = 0;
const CONNECT_GRACE_FRAMES: u8 = 10;

// XInput / Xbox controller raw button indices (standard layout)
const RAW_A: usize = 0;
const RAW_X: usize = 2;
const RAW_START: usize = 7;
const RAW_HAT_LEFT: u8 = 8;
const RAW_HAT_RIGHT: u8 = 2;

pub fn init() void {
    if (initialized) return;
    initialized = true;

    _ = rl.setGamepadMappings(supplemental_gamepad_mappings);
}

pub fn poll() FrameInput {
    // Sample on-screen touch controls once per frame (web/tablet only; this is a
    // comptime no-op on native). Folded into the FrameInput below.
    touch.update();

    const gamepad = getActiveGamepad();

    // Update raw joystick state each frame (desktop only — the raw GLFW joystick
    // calls are unimplemented on emscripten's GLFW port, see is_web above).
    if (!is_web) {
        if (gamepad) |info| {
            updateRawJoystickState(info.index);
        } else {
            raw_btn_prev = raw_btn_cur;
            @memset(&raw_btn_cur, 0);
            raw_hat_prev = raw_hat_cur;
            raw_hat_cur = 0;
            raw_axis_lx = 0.0;
        }
    }

    var input = FrameInput{
        .move_x = readMoveAxis(gamepad),
        .jump_pressed = isActionPressed(.jump, gamepad),
        .jump_down = isActionDown(.jump, gamepad),
        .submit_pressed = isActionPressed(.submit, gamepad),
        .pause_pressed = isActionPressed(.pause, gamepad),
        .restart_pressed = isActionPressed(.restart, gamepad),
        .has_gamepad = gamepad != null,
        .gamepad_name = if (gamepad) |info| info.name else null,
    };

    // Merge on-screen touch controls (web only). The JUMP button doubles as
    // "submit" so a touch player can confirm the PR by jumping into the terminal;
    // submit is only consumed there (and on the level-complete screen), so this
    // overload is harmless elsewhere.
    if (is_web) {
        if (touch.isLeftDown()) input.move_x -= 1.0;
        if (touch.isRightDown()) input.move_x += 1.0;
        input.move_x = std.math.clamp(input.move_x, -1.0, 1.0);
        if (touch.isJumpDown()) input.jump_down = true;
        if (touch.isJumpPressed()) {
            input.jump_pressed = true;
            input.submit_pressed = true;
        }
        if (touch.isPausePressed()) input.pause_pressed = true;
    }

    return input;
}

pub fn getConnectedGamepadName() ?[:0]const u8 {
    if (getActiveGamepad()) |gamepad| {
        return gamepad.name;
    }

    return null;
}

pub fn getActionPrompt(action: Action, has_gamepad: bool) [:0]const u8 {
    return switch (action) {
        .jump => if (has_gamepad) "Space, W, Up, or A / Cross" else "Space, W, or Up",
        .submit => if (has_gamepad) "Enter, E, or X / Square" else "Enter or E",
        .pause => if (has_gamepad) "P, ESC, or Start" else "P or ESC",
        .restart => if (has_gamepad) "R or X / Square" else "R",
        .move_left, .move_right => if (has_gamepad) "A, D, arrows, d-pad, or left stick" else "A, D, or arrows",
    };
}

fn readMoveAxis(gamepad: ?GamepadInfo) f32 {
    var move_input: f32 = 0.0;

    if (isActionDown(.move_left, gamepad)) {
        move_input -= 1.0;
    }
    if (isActionDown(.move_right, gamepad)) {
        move_input += 1.0;
    }

    if (gamepad) |info| {
        if (gamepad_connect_grace == 0) {
            // Mapped gamepad axis (works with XInput / properly mapped controllers)
            var axis_value = rl.getGamepadAxisMovement(info.index, .left_x);
            if (@abs(axis_value) < config.GAMEPAD_AXIS_DEADZONE) axis_value = 0.0;
            if (@abs(axis_value) > @abs(move_input)) move_input = axis_value;

            // Raw joystick left stick X axis (fallback for unmapped controllers)
            if (use_raw_fallback) {
                var raw = raw_axis_lx;
                if (@abs(raw) < config.GAMEPAD_AXIS_DEADZONE) raw = 0.0;
                if (@abs(raw) > @abs(move_input)) move_input = raw;
            }
        }
    }

    if (move_input > 1.0) return 1.0;
    if (move_input < -1.0) return -1.0;
    return move_input;
}

fn isActionPressed(action: Action, gamepad: ?GamepadInfo) bool {
    const binding = getBinding(action);

    for (binding.keys) |key| {
        if (rl.isKeyPressed(key)) return true;
    }

    if (gamepad) |info| {
        if (gamepad_connect_grace == 0) {
            for (binding.buttons) |button| {
                if (rl.isGamepadButtonPressed(info.index, button)) return true;
            }
            if (use_raw_fallback and isRawActionPressed(action)) return true;
        }
    }

    return false;
}

fn isActionDown(action: Action, gamepad: ?GamepadInfo) bool {
    const binding = getBinding(action);

    for (binding.keys) |key| {
        if (rl.isKeyDown(key)) return true;
    }

    if (gamepad) |info| {
        if (gamepad_connect_grace == 0) {
            for (binding.buttons) |button| {
                if (rl.isGamepadButtonDown(info.index, button)) return true;
            }
            if (use_raw_fallback and isRawActionDown(action)) return true;
        }
    }

    return false;
}

fn getBinding(action: Action) ButtonBinding {
    return switch (action) {
        .move_left => .{ .keys = move_left_keys[0..], .buttons = move_left_buttons[0..] },
        .move_right => .{ .keys = move_right_keys[0..], .buttons = move_right_buttons[0..] },
        .jump => .{ .keys = jump_keys[0..], .buttons = jump_buttons[0..] },
        .submit => .{ .keys = submit_keys[0..], .buttons = submit_buttons[0..] },
        .pause => .{ .keys = pause_keys[0..], .buttons = pause_buttons[0..] },
        .restart => .{ .keys = restart_keys[0..], .buttons = restart_buttons[0..] },
    };
}

// ---------------------------------------------------------------------------
// Raw joystick input (bypasses SDL mapping for controllers with unknown GUIDs)
// ---------------------------------------------------------------------------

fn updateRawJoystickState(index: i32) void {
    raw_btn_prev = raw_btn_cur;
    raw_hat_prev = raw_hat_cur;

    var btn_count: i32 = 0;
    if (glfwGetJoystickButtons(index, &btn_count)) |buttons| {
        const n: usize = @intCast(@min(btn_count, 32));
        for (0..n) |i| raw_btn_cur[i] = buttons[i];
    } else {
        @memset(&raw_btn_cur, 0);
    }

    var hat_count: i32 = 0;
    if (glfwGetJoystickHats(index, &hat_count)) |hats| {
        if (hat_count > 0) raw_hat_cur = hats[0];
    }

    var axis_count: i32 = 0;
    if (glfwGetJoystickAxes(index, &axis_count)) |axes| {
        if (axis_count > 0) raw_axis_lx = axes[0];
    }
}

fn isRawActionPressed(action: Action) bool {
    if (getRawButton(action)) |btn| {
        if (raw_btn_cur[btn] != 0 and raw_btn_prev[btn] == 0) return true;
    }
    if (getRawHat(action)) |hat_bit| {
        if ((raw_hat_cur & hat_bit != 0) and (raw_hat_prev & hat_bit == 0)) return true;
    }
    return false;
}

fn isRawActionDown(action: Action) bool {
    if (getRawButton(action)) |btn| {
        if (raw_btn_cur[btn] != 0) return true;
    }
    if (getRawHat(action)) |hat_bit| {
        if (raw_hat_cur & hat_bit != 0) return true;
    }
    return false;
}

fn getRawButton(action: Action) ?usize {
    return switch (action) {
        .jump => RAW_A,
        .submit, .restart => RAW_X,
        .pause => RAW_START,
        .move_left, .move_right => null,
    };
}

fn getRawHat(action: Action) ?u8 {
    return switch (action) {
        .move_left => RAW_HAT_LEFT,
        .move_right => RAW_HAT_RIGHT,
        else => null,
    };
}

// ---------------------------------------------------------------------------
// Gamepad detection
// ---------------------------------------------------------------------------

const GamepadInfo = struct {
    index: i32,
    name: [:0]const u8,
};

fn getActiveGamepad() ?GamepadInfo {
    var gamepad_index: i32 = 0;
    while (gamepad_index < config.MAX_GAMEPADS) : (gamepad_index += 1) {
        if (rl.isGamepadAvailable(gamepad_index)) {
            const name = rl.getGamepadName(gamepad_index);
            if (isSkippedDevice(name)) continue;

            if (!last_gamepad_state or last_gamepad_index != gamepad_index) {
                // Determine if this controller has a working SDL mapping. On web
                // we always take the mapped path: emscripten's GLFW lacks
                // glfwJoystickIsGamepad (calling it throws), and raylib's browser
                // Gamepad API backend already provides a standard mapping.
                const has_mapping = if (is_web) true else glfwJoystickIsGamepad(gamepad_index) != 0;
                use_raw_fallback = !has_mapping;

                // Record connection state; avoid debug output in normal runs.
                last_gamepad_state = true;
                last_gamepad_index = gamepad_index;
                gamepad_connect_grace = CONNECT_GRACE_FRAMES;
            }
            // Count down grace period
            if (gamepad_connect_grace > 0) gamepad_connect_grace -= 1;
            return .{
                .index = gamepad_index,
                .name = name,
            };
        }
    }

    if (last_gamepad_state) {
        last_gamepad_state = false;
        last_gamepad_index = -1;
    }

    return null;
}

fn isSkippedDevice(name: [:0]const u8) bool {
    for (skipped_device_names) |skip| {
        if (containsIgnoreCase(name, skip)) return true;
    }
    return false;
}

fn containsIgnoreCase(haystack: [:0]const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    const end = haystack.len - needle.len + 1;
    for (0..end) |i| {
        var match = true;
        for (0..needle.len) |j| {
            const h = std.ascii.toLower(haystack[i + j]);
            const n = std.ascii.toLower(needle[j]);
            if (h != n) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

test "submit prompt includes controller guidance when available" {
    try std.testing.expectEqualStrings("Enter or E", getActionPrompt(.submit, false));
    try std.testing.expectEqualStrings("Enter, E, or X / Square", getActionPrompt(.submit, true));
}

test "pause prompt stays keyboard friendly without controller" {
    try std.testing.expectEqualStrings("P or ESC", getActionPrompt(.pause, false));
}

/// True if any keyboard key or gamepad button was pressed this frame.
/// Used by "press any button to continue" screens (e.g. credits).
pub fn isAnyInputPressed() bool {
    // getKeyPressed() returns KeyboardKey.null (0) when the queue is empty.
    if (@intFromEnum(rl.getKeyPressed()) != 0) return true;
    return isAnyGamepadButtonPressed();
}

/// True if the user produced any input this frame that a browser accepts as a
/// gesture to unlock its WebAudio context (mouse button, keyboard key, or
/// gamepad button). Used by the web audio-unlock gate
/// (PM_BrowserGameplay.md Phase 4). A mouse click is the most likely first
/// gesture on a web page, so it is checked explicitly here in addition to the
/// key/gamepad coverage from isAnyInputPressed().
pub fn isAudioUnlockGesture() bool {
    if (rl.isMouseButtonPressed(.left) or rl.isMouseButtonPressed(.right)) return true;
    if (touch.anyTapPressed()) return true;
    return isAnyInputPressed();
}

pub fn isAnyGamepadButtonPressed() bool {
    var gamepad_index: i32 = 0;
    while (gamepad_index < config.MAX_GAMEPADS) : (gamepad_index += 1) {
        if (rl.isGamepadAvailable(gamepad_index)) {
            var button: i32 = 0;
            while (button < 15) : (button += 1) {
                if (rl.isGamepadButtonPressed(gamepad_index, @enumFromInt(button))) {
                    return true;
                }
            }
        }
    }
    return false;
}

