//! Server Room scene — a small single-screen sub-scene the player enters through
//! the in-level door. PM walks left/right (no gravity, no hazards), runs the
//! optimizing script (`optimize.sh`) at the room terminal, and returns to the
//! level exactly where he left it.
//!
//! The scene is deliberately self-contained: fixed-capacity, no allocation, and
//! it never reaches into the Tilemap. Its rack LEDs flicker chaotically while the
//! script has not finished, then settle into an ordered chase the instant it does
//! — the fix made visible inside the room.

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const controls = @import("controls.zig");

// --- Room layout (screen-space, no camera; the level's 800x600 framebuffer) ---
const FLOOR_Y: f32 = 500.0; // PM's feet rest on this line
const PM_MIN_X: f32 = 40.0;
const PM_MAX_X: f32 = 740.0;
const DOOR_ZONE_MAX_X: f32 = 90.0; // PM is "at the door" left of this
const TERMINAL_ZONE_MIN_X: f32 = 560.0; // PM is "at the terminal" right of this

// PM sprite draw size (front-facing idle frame, scaled up from the sheet frame).
const PM_H: f32 = 80.0;
const PM_W: f32 = PM_H * 0.83; // keep the 83:100 sheet-frame aspect

// Frames in the shared sprite sheet (see player.zig). Idle is row 0, column 0;
// the walk cycle is the side-profile row 3, columns 2..5 — the same arm-swinging
// run the player uses in the level.
const SPRITE_FRAME_W: f32 = 166.0;
const SPRITE_FRAME_H: f32 = 200.0;
const SPRITE_IDLE_Y: f32 = 30.0;
const SPRITE_RUN_Y: f32 = 766.0;
const RUN_FRAME_DURATION: f32 = 0.15; // seconds per walk frame (matches player.zig)

/// Terminal-green, matching the HUD / credits body text.
const term_green = rl.Color{ .r = 0, .g = 255, .b = 128, .a = 255 };
const term_dim = rl.Color{ .r = 0, .g = 90, .b = 50, .a = 255 };

pub const ScriptState = enum { idle, running, done };
pub const RoomEvent = enum { none, script_finished, exit_requested };

/// The scrolling output of `optimize.sh`, revealed one line at a time.
const script_lines = [_][:0]const u8{
    "$ ./optimize.sh",
    "Scanning system state.......... DEGRADED",
    "Defragmenting memory pages..... OK",
    "Reindexing interrupt table..... OK",
    "Rebalancing thread scheduler... OK",
    "Flushing corrupted caches...... OK",
    "Patching LED bus drivers....... OK",
    "Verifying system integrity..... PASS",
    "OPTIMIZATION COMPLETE",
};

/// Per-variant palette + a signature decor element. Everything else is shared.
const Palette = struct {
    wall: rl.Color,
    floor: rl.Color,
    accent: rl.Color,
};

fn paletteFor(variant: u8) Palette {
    return switch (variant) {
        0 => .{ // Motherboard — dark teal walls, green accents
            .wall = .{ .r = 18, .g = 40, .b = 42, .a = 255 },
            .floor = .{ .r = 12, .g = 26, .b = 28, .a = 255 },
            .accent = .{ .r = 60, .g = 220, .b = 130, .a = 255 },
        },
        1 => .{ // Cooling Bay — steel blue walls, cyan accents
            .wall = .{ .r = 26, .g = 40, .b = 58, .a = 255 },
            .floor = .{ .r = 16, .g = 26, .b = 40, .a = 255 },
            .accent = .{ .r = 90, .g = 210, .b = 230, .a = 255 },
        },
        2 => .{ // Core Chamber — deep maroon walls, orange accents
            .wall = .{ .r = 44, .g = 20, .b = 24, .a = 255 },
            .floor = .{ .r = 28, .g = 12, .b = 16, .a = 255 },
            .accent = .{ .r = 240, .g = 140, .b = 60, .a = 255 },
        },
        else => .{ // Silicon Ascent — slate/violet walls, ice-blue accents
            .wall = .{ .r = 34, .g = 32, .b = 52, .a = 255 },
            .floor = .{ .r = 20, .g = 18, .b = 34, .a = 255 },
            .accent = .{ .r = 150, .g = 200, .b = 240, .a = 255 },
        },
    };
}

/// Deterministic pseudo-random 0..1 (mirrors Tilemap.hashFloat so the room's
/// chaos flicker reads the same as the world's, without touching the Tilemap).
fn hashFloat(value: i32) f32 {
    const x = @as(f32, @floatFromInt(@mod(value * 73 + 19, 997)));
    return x / 997.0;
}

/// Intensity 0..1 for light `index` of an element `seed`. Chaos: independent
/// ~90 ms flicker with no pattern. Ordered: a slow synchronized chase.
fn lightSignal(time: f32, seed: i32, index: i32, chaos: bool, speed: f32) f32 {
    if (chaos) {
        const step: i32 = @intFromFloat(@floor(time / 0.09));
        return hashFloat(seed * 31 + index * 57 + step * 101);
    }
    const wave = @sin(time * speed - @as(f32, @floatFromInt(index)) * 0.9);
    return wave * 0.5 + 0.5;
}

pub const ServerRoom = struct {
    variant: u8, // = current level (0..3): selects palette + decor
    pm_x: f32, // PM's x in room space; y is fixed on the floor
    facing_right: bool,
    moving: bool, // walking this frame → play the run cycle
    anim_frame: u8, // 0..3 walk-cycle frame
    anim_timer: f32,
    script_state: ScriptState,
    script_timer: f32,
    lines_shown: usize,

    const Self = @This();

    /// PM starts just inside the left-edge door, facing into the room.
    pub fn enter(variant: u8) Self {
        return .{
            .variant = variant,
            .pm_x = 60.0,
            .facing_right = true,
            .moving = false,
            .anim_frame = 0,
            .anim_timer = 0,
            .script_state = .idle,
            .script_timer = 0,
            .lines_shown = 0,
        };
    }

    fn inDoorZone(self: *const Self) bool {
        return self.pm_x < DOOR_ZONE_MAX_X;
    }

    fn inTerminalZone(self: *const Self) bool {
        return self.pm_x >= TERMINAL_ZONE_MIN_X;
    }

    pub fn update(self: *Self, dt: f32, input: controls.FrameInput) RoomEvent {
        // Walk left/right — no gravity, no jumping, clamped to the room.
        if (input.move_x < 0) self.facing_right = false;
        if (input.move_x > 0) self.facing_right = true;
        self.pm_x += input.move_x * config.ROOM_WALK_SPEED * dt;
        if (self.pm_x < PM_MIN_X) self.pm_x = PM_MIN_X;
        if (self.pm_x > PM_MAX_X) self.pm_x = PM_MAX_X;

        // Advance the walk cycle while moving; snap back to the idle pose at rest.
        self.moving = input.move_x != 0;
        if (self.moving) {
            self.anim_timer += dt;
            if (self.anim_timer >= RUN_FRAME_DURATION) {
                self.anim_timer = 0;
                self.anim_frame = (self.anim_frame + 1) % 4;
            }
        } else {
            self.anim_frame = 0;
            self.anim_timer = 0;
        }

        // Reveal the script one line per interval; finish once past the last.
        if (self.script_state == .running) {
            self.script_timer += dt;
            if (self.script_timer >= config.SCRIPT_LINE_INTERVAL) {
                self.script_timer -= config.SCRIPT_LINE_INTERVAL;
                if (self.lines_shown < script_lines.len) {
                    self.lines_shown += 1;
                } else {
                    self.script_state = .done;
                    return .script_finished; // fired exactly once
                }
            }
        }

        // Interactions (door exit takes priority over the terminal).
        if (input.submit_pressed) {
            if (self.inDoorZone()) return .exit_requested;
            if (self.inTerminalZone() and self.script_state == .idle) {
                self.script_state = .running;
                self.script_timer = 0;
                self.lines_shown = 1; // "$ ./optimize.sh" shows immediately
            }
        }

        return .none;
    }

    pub fn render(self: *const Self, player_texture: ?rl.Texture2D, time: f32, has_gamepad: bool) void {
        const pal = paletteFor(self.variant);
        const chaos = self.script_state != .done;

        // Wall + floor fill the whole framebuffer (covers the level backdrop).
        rl.drawRectangle(0, 0, config.GAME_WIDTH, config.GAME_HEIGHT, pal.wall);
        rl.drawRectangle(0, @intFromFloat(FLOOR_Y), config.GAME_WIDTH, config.GAME_HEIGHT - @as(i32, @intFromFloat(FLOOR_Y)), pal.floor);
        rl.drawRectangle(0, @intFromFloat(FLOOR_Y), config.GAME_WIDTH, 2, pal.accent);

        self.renderDecor(pal, time, chaos);
        self.renderRacks(pal, time, chaos);
        self.renderDoor(pal);
        self.renderTerminal(pal, time);
        self.renderPM(player_texture);
        self.renderHints(has_gamepad);
    }

    /// Back-wall server racks with LED columns (chaotic flicker → ordered chase).
    fn renderRacks(self: *const Self, pal: Palette, time: f32, chaos: bool) void {
        // Variant 0 gets a third rack; the others get two (their signature decor
        // fills the extra space).
        const rack_count: i32 = if (self.variant == 0) 3 else 2;
        const spacing: i32 = 130;
        const start_x: i32 = 170;

        var r: i32 = 0;
        while (r < rack_count) : (r += 1) {
            const x = start_x + r * spacing;
            self.drawRack(x, pal, time, chaos, r * 97 + 13);
        }
    }

    fn drawRack(self: *const Self, x: i32, pal: Palette, time: f32, chaos: bool, seed: i32) void {
        _ = self;
        const w: i32 = 72;
        const top: i32 = 210;
        const bottom: i32 = @intFromFloat(FLOOR_Y);
        const h = bottom - top;

        rl.drawRectangle(x, top, w, h, rl.Color{ .r = 14, .g = 18, .b = 22, .a = 255 });
        rl.drawRectangleLines(x, top, w, h, rl.Color{ .r = pal.accent.r, .g = pal.accent.g, .b = pal.accent.b, .a = 80 });

        // Rows of small LEDs down the cabinet face.
        var row: i32 = 0;
        var ly: i32 = top + 14;
        while (ly < bottom - 14) : (ly += 18) {
            var col: i32 = 0;
            while (col < 3) : (col += 1) {
                const lx = x + 12 + col * 18;
                const sig = lightSignal(time, seed, row * 3 + col, chaos, 3.0);
                const on = sig >= 0.5;
                const c = if (on) pal.accent else term_dim;
                rl.drawRectangle(lx, ly, 8, 6, c);
            }
            row += 1;
        }
    }

    /// One signature decor element per variant, everything else shared.
    fn renderDecor(self: *const Self, pal: Palette, time: f32, chaos: bool) void {
        switch (self.variant) {
            0 => {
                // Motherboard — a hanging cable bundle draped from the ceiling.
                var i: i32 = 0;
                while (i < 5) : (i += 1) {
                    const bx: f32 = 90.0 + @as(f32, @floatFromInt(i)) * 10.0;
                    const sag: f32 = 60.0 + @as(f32, @floatFromInt(i)) * 8.0;
                    rl.drawLineEx(
                        .{ .x = bx, .y = 0 },
                        .{ .x = bx + 40, .y = sag },
                        3.0,
                        rl.Color{ .r = 40, .g = 60, .b = 70, .a = 255 },
                    );
                }
            },
            1 => {
                // Cooling Bay — two wall-mounted spinning fans.
                drawFan(430, 150, 40, time, pal.accent);
                drawFan(560, 150, 40, time, pal.accent);
            },
            2 => {
                // Core Chamber — two glowing energy-conduit columns.
                var i: i32 = 0;
                while (i < 2) : (i += 1) {
                    const cx: i32 = 430 + i * 130;
                    const glow = lightSignal(time, cx, 0, chaos, 1.5);
                    const a: u8 = @intFromFloat(90.0 + glow * 140.0);
                    rl.drawRectangle(cx, 150, 22, 350, rl.Color{ .r = 40, .g = 20, .b = 24, .a = 255 });
                    rl.drawRectangle(cx + 4, 150, 14, 350, rl.Color{ .r = pal.accent.r, .g = pal.accent.g, .b = pal.accent.b, .a = a });
                }
            },
            else => {
                // Silicon Ascent — an antenna/relay mast with a blinking beacon.
                const mx: i32 = 470;
                rl.drawRectangle(mx - 3, 120, 6, 380, rl.Color{ .r = 90, .g = 96, .b = 120, .a = 255 });
                rl.drawTriangle(
                    .{ .x = @floatFromInt(mx), .y = 90 },
                    .{ .x = @floatFromInt(mx - 22), .y = 130 },
                    .{ .x = @floatFromInt(mx + 22), .y = 130 },
                    rl.Color{ .r = 70, .g = 78, .b = 100, .a = 200 },
                );
                const beacon_on = lightSignal(time, 7, 0, chaos, 2.0) >= 0.5;
                const beacon = if (beacon_on) pal.accent else term_dim;
                rl.drawCircle(mx, 90, 5, beacon);
            },
        }
    }

    fn renderDoor(self: *const Self, pal: Palette) void {
        _ = self;
        // Left-edge doorway PM walks back through to the level.
        const x: i32 = 24;
        const y: i32 = 380;
        const w: i32 = 56;
        const h: i32 = @as(i32, @intFromFloat(FLOOR_Y)) - y;

        rl.drawRectangle(x, y, w, h, rl.Color{ .r = 30, .g = 34, .b = 40, .a = 255 });
        rl.drawRectangle(x + 6, y + 8, w - 12, h - 8, rl.Color{ .r = 16, .g = 20, .b = 26, .a = 255 });
        rl.drawRectangleLines(x, y, w, h, rl.Color{ .r = pal.accent.r, .g = pal.accent.g, .b = pal.accent.b, .a = 120 });

        const label = "EXIT";
        const size = 10;
        const lw = rl.measureText(label, size);
        rl.drawText(label, x + @divTrunc(w - lw, 2), y - 14, size, pal.accent);
    }

    fn renderTerminal(self: *const Self, pal: Palette, time: f32) void {
        // Desk + monitor at the right side of the room.
        const desk_x: i32 = 520;
        const desk_w: i32 = 250;
        rl.drawRectangle(desk_x, 470, desk_w, 30, rl.Color{ .r = 30, .g = 34, .b = 40, .a = 255 });

        const mon_x: i32 = 528;
        const mon_y: i32 = 250;
        const mon_w: i32 = 234;
        const mon_h: i32 = 210;
        rl.drawRectangle(mon_x - 4, mon_y - 4, mon_w + 8, mon_h + 8, rl.Color{ .r = 20, .g = 24, .b = 30, .a = 255 });
        rl.drawRectangle(mon_x, mon_y, mon_w, mon_h, rl.Color{ .r = 8, .g = 12, .b = 10, .a = 255 });
        rl.drawRectangleLines(mon_x, mon_y, mon_w, mon_h, rl.Color{ .r = pal.accent.r, .g = pal.accent.g, .b = pal.accent.b, .a = 90 });

        // Scrolling script output. raylib does not wrap, so pick the largest font
        // size at which even the widest line stays inside the bezel — that keeps
        // the longest line ("...DEGRADED") on screen no matter how the script text
        // is edited later.
        const inner_w = mon_w - 20; // 8px left pad + a right margin off the bezel
        var fs: i32 = 11;
        while (fs > 7 and widestScriptLine(fs) > inner_w) : (fs -= 1) {}
        const line_h = fs + 5;

        var ty: i32 = mon_y + 8;
        for (script_lines[0..self.lines_shown]) |line| {
            rl.drawText(line, mon_x + 8, ty, fs, term_green);
            ty += line_h;
        }

        // Blinking cursor while the script is running.
        if (self.script_state == .running and @sin(time * 6.0) > 0.0) {
            rl.drawText("_", mon_x + 8, ty, fs, term_green);
        }
    }

    fn renderPM(self: *const Self, player_texture: ?rl.Texture2D) void {
        const dest = rl.Rectangle{
            .x = self.pm_x - PM_W / 2.0,
            .y = FLOOR_Y - PM_H,
            .width = PM_W,
            .height = PM_H,
        };

        if (player_texture) |tex| {
            // Walking → side-profile run frame (row 3, cols 2..5); at rest → idle.
            var src = if (self.moving) rl.Rectangle{
                .x = (@as(f32, @floatFromInt(self.anim_frame)) + 2.0) * SPRITE_FRAME_W,
                .y = SPRITE_RUN_Y,
                .width = SPRITE_FRAME_W,
                .height = SPRITE_FRAME_H,
            } else rl.Rectangle{
                .x = 0,
                .y = SPRITE_IDLE_Y,
                .width = SPRITE_FRAME_W,
                .height = SPRITE_FRAME_H,
            };
            // Negative source width mirrors the sprite (same trick as player.zig).
            if (!self.facing_right) src.width = -src.width;
            rl.drawTexturePro(tex, src, dest, .{ .x = 0, .y = 0 }, 0.0, rl.Color.white);
        } else {
            rl.drawRectangleRec(dest, config.PLAYER_COLOR);
        }
    }

    fn renderHints(self: *const Self, has_gamepad: bool) void {
        const prompt = controls.getActionPrompt(.submit, has_gamepad);

        if (self.script_state == .done) {
            drawCenteredHint("System updated! Return to the level", 40);
        }

        if (self.inDoorZone()) {
            var buf: [128]u8 = undefined;
            const hint = std.fmt.bufPrintZ(&buf, "Press {s} to exit", .{prompt}) catch "Press to exit";
            drawCenteredHint(hint, 120);
        } else if (self.inTerminalZone() and self.script_state == .idle) {
            var buf: [128]u8 = undefined;
            const hint = std.fmt.bufPrintZ(&buf, "Press {s} to run optimize.sh", .{prompt}) catch "Press to run optimize.sh";
            drawCenteredHint(hint, 120);
        }
    }
};

/// Width of the widest script line at `fs`, used to size the terminal text.
fn widestScriptLine(fs: i32) i32 {
    var widest: i32 = 0;
    for (script_lines) |line| {
        const w = rl.measureText(line, fs);
        if (w > widest) widest = w;
    }
    return widest;
}

/// A local spinning-fan draw (variant 1 decor), modeled on Tilemap.drawCoolingFan.
fn drawFan(cx: i32, cy: i32, radius: i32, time: f32, accent: rl.Color) void {
    const tau = @as(f32, std.math.pi * 2.0);
    const spin = time * 4.0;
    const blade_count: i32 = 5;

    rl.drawCircle(cx, cy, @floatFromInt(radius + 4), rl.Color{ .r = 40, .g = 50, .b = 60, .a = 255 });
    rl.drawCircle(cx, cy, @floatFromInt(radius - 4), rl.Color{ .r = 14, .g = 20, .b = 26, .a = 255 });

    var blade: i32 = 0;
    while (blade < blade_count) : (blade += 1) {
        const angle = spin + (@as(f32, @floatFromInt(blade)) * tau / @as(f32, @floatFromInt(blade_count)));
        const root_r = @as(f32, @floatFromInt(radius)) * 0.18;
        const tip_r = @as(f32, @floatFromInt(radius)) * 0.78;
        const fx = @as(f32, @floatFromInt(cx));
        const fy = @as(f32, @floatFromInt(cy));
        rl.drawTriangle(
            .{ .x = fx + @cos(angle) * root_r, .y = fy + @sin(angle) * root_r },
            .{ .x = fx + @cos(angle - 0.4) * tip_r, .y = fy + @sin(angle - 0.4) * tip_r },
            .{ .x = fx + @cos(angle + 0.4) * tip_r, .y = fy + @sin(angle + 0.4) * tip_r },
            rl.Color{ .r = accent.r, .g = accent.g, .b = accent.b, .a = 180 },
        );
    }
    rl.drawCircle(cx, cy, 5, rl.Color{ .r = 170, .g = 188, .b = 204, .a = 210 });
}

/// Screen-space hint box (dark rounded background + centered text), matching the
/// in-level hint style.
fn drawCenteredHint(text: [:0]const u8, y: i32) void {
    const fs: i32 = 18;
    const tw = rl.measureText(text, fs);
    const pad: i32 = 10;
    const x = @divTrunc(config.SCREEN_WIDTH - tw, 2);

    var bg = rl.Color.black;
    bg.a = 180;
    rl.drawRectangle(x - pad, y - 5, tw + pad * 2, 30, bg);
    rl.drawText(text, x, y, fs, config.HUD_COLOR);
}
