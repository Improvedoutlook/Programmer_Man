//background.zig
//! Background rendering module - Computer/circuit themed with electrical effects

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");

/// Particle representing electrical activity
const Particle = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: f32,
    max_life: f32,
    color: rl.Color,
};

/// Circuit trace for animated pathways
const CircuitTrace = struct {
    x1: i32,
    y1: i32,
    x2: i32,
    y2: i32,
    pulse_offset: f32,
    is_horizontal: bool,
};

/// Decorative IC chip with blinking activity LED
const ChipElement = struct {
    x: i32, // background-world x position
    y: i32,
    width: i32,
    height: i32,
    pins_per_side: i32,
    phase: f32, // LED blink phase offset
    label_char: u8, // single char stamped on chip body
};

pub const Background = struct {
    particles: [64]Particle,
    particle_count: usize,
    circuit_traces: [16]CircuitTrace,
    chips: [config.BG_CHIP_COUNT]ChipElement,
    time: f32,
    rng: std.rand.DefaultPrng,

    const Self = @This();

    pub fn init() Self {
        const rng = std.rand.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
        var self = Self{
            .particles = undefined,
            .particle_count = 0,
            .circuit_traces = undefined,
            .chips = undefined,
            .time = 0,
            .rng = rng,
        };

        // Initialize circuit traces (horizontal and vertical lines across screen)
        self.circuit_traces[0] = .{ .x1 = 50, .y1 = 100, .x2 = 1150, .y2 = 100, .pulse_offset = 0, .is_horizontal = true };
        self.circuit_traces[1] = .{ .x1 = 50, .y1 = 200, .x2 = 1150, .y2 = 200, .pulse_offset = 0.5, .is_horizontal = true };
        self.circuit_traces[2] = .{ .x1 = 50, .y1 = 300, .x2 = 1150, .y2 = 300, .pulse_offset = 1.0, .is_horizontal = true };
        self.circuit_traces[3] = .{ .x1 = 50, .y1 = 500, .x2 = 1150, .y2 = 500, .pulse_offset = 1.5, .is_horizontal = true };

        self.circuit_traces[4] = .{ .x1 = 150, .y1 = 50, .x2 = 150, .y2 = 550, .pulse_offset = 0.25, .is_horizontal = false };
        self.circuit_traces[5] = .{ .x1 = 300, .y1 = 50, .x2 = 300, .y2 = 550, .pulse_offset = 0.75, .is_horizontal = false };
        self.circuit_traces[6] = .{ .x1 = 450, .y1 = 50, .x2 = 450, .y2 = 550, .pulse_offset = 1.25, .is_horizontal = false };
        self.circuit_traces[7] = .{ .x1 = 600, .y1 = 50, .x2 = 600, .y2 = 550, .pulse_offset = 1.75, .is_horizontal = false };

        // Some angled traces for variety
        self.circuit_traces[8] = .{ .x1 = 100, .y1 = 150, .x2 = 200, .y2 = 250, .pulse_offset = 0.3, .is_horizontal = false };
        self.circuit_traces[9] = .{ .x1 = 400, .y1 = 400, .x2 = 500, .y2 = 300, .pulse_offset = 0.8, .is_horizontal = false };
        self.circuit_traces[10] = .{ .x1 = 600, .y1 = 150, .x2 = 700, .y2 = 250, .pulse_offset = 1.3, .is_horizontal = false };
        self.circuit_traces[11] = .{ .x1 = 200, .y1 = 450, .x2 = 350, .y2 = 500, .pulse_offset = 1.8, .is_horizontal = false };

        // Extended traces for parallax scrolling coverage
        self.circuit_traces[12] = .{ .x1 = 750, .y1 = 50, .x2 = 750, .y2 = 550, .pulse_offset = 2.0, .is_horizontal = false };
        self.circuit_traces[13] = .{ .x1 = 900, .y1 = 50, .x2 = 900, .y2 = 550, .pulse_offset = 2.25, .is_horizontal = false };
        self.circuit_traces[14] = .{ .x1 = 800, .y1 = 100, .x2 = 950, .y2 = 200, .pulse_offset = 2.5, .is_horizontal = false };
        self.circuit_traces[15] = .{ .x1 = 950, .y1 = 350, .x2 = 1100, .y2 = 450, .pulse_offset = 2.75, .is_horizontal = false };

        // Initialise decorative IC chips — spread across background, below HUD zone (y >= 150)
        const chip_data = [config.BG_CHIP_COUNT]struct { x: i32, y: i32, w: i32, h: i32, pins: i32, phase: f32, label: u8 }{
            .{ .x = 80, .y = 180, .w = 56, .h = 28, .pins = 4, .phase = 0.0, .label = 'U' },
            .{ .x = 320, .y = 350, .w = 48, .h = 24, .pins = 3, .phase = 0.8, .label = 'A' },
            .{ .x = 530, .y = 220, .w = 60, .h = 30, .pins = 5, .phase = 1.6, .label = 'Z' },
            .{ .x = 700, .y = 420, .w = 50, .h = 26, .pins = 4, .phase = 2.4, .label = 'M' },
            .{ .x = 900, .y = 170, .w = 52, .h = 28, .pins = 4, .phase = 3.2, .label = 'C' },
            .{ .x = 1050, .y = 310, .w = 44, .h = 22, .pins = 3, .phase = 4.0, .label = 'R' },
            .{ .x = 180, .y = 470, .w = 58, .h = 30, .pins = 5, .phase = 4.8, .label = 'D' },
            .{ .x = 620, .y = 500, .w = 46, .h = 24, .pins = 3, .phase = 5.6, .label = 'X' },
        };
        for (chip_data, 0..) |cd, idx| {
            self.chips[idx] = .{
                .x = cd.x,
                .y = cd.y,
                .width = cd.w,
                .height = cd.h,
                .pins_per_side = cd.pins,
                .phase = cd.phase,
                .label_char = cd.label,
            };
        }

        return self;
    }

    pub fn update(self: *Self, dt: f32) void {
        self.time += dt;

        // Update existing particles
        var i: usize = 0;
        while (i < self.particle_count) {
            self.particles[i].x += self.particles[i].vx * dt;
            self.particles[i].y += self.particles[i].vy * dt;
            self.particles[i].life -= dt;

            if (self.particles[i].life <= 0) {
                // Remove dead particle by swapping with last
                self.particles[i] = self.particles[self.particle_count - 1];
                self.particle_count -= 1;
            } else {
                i += 1;
            }
        }

        // Spawn new particles along circuit traces occasionally
        if (self.rng.random().float(f32) < 0.1 and self.particle_count < self.particles.len) {
            const trace_idx = self.rng.random().intRangeAtMost(usize, 0, self.circuit_traces.len - 1);
            const trace = self.circuit_traces[trace_idx];

            const t = self.rng.random().float(f32);
            const spawn_x = @as(f32, @floatFromInt(trace.x1)) + t * @as(f32, @floatFromInt(trace.x2 - trace.x1));
            const spawn_y = @as(f32, @floatFromInt(trace.y1)) + t * @as(f32, @floatFromInt(trace.y2 - trace.y1));

            // Calculate direction along trace
            const dx = @as(f32, @floatFromInt(trace.x2 - trace.x1));
            const dy = @as(f32, @floatFromInt(trace.y2 - trace.y1));
            const len = @sqrt(dx * dx + dy * dy);

            self.particles[self.particle_count] = .{
                .x = spawn_x,
                .y = spawn_y,
                .vx = (dx / len) * 100.0, // Move along trace
                .vy = (dy / len) * 100.0,
                .life = 1.0 + self.rng.random().float(f32) * 2.0,
                .max_life = 3.0,
                .color = rl.Color{ .r = 100, .g = 200, .b = 255, .a = 255 },
            };
            self.particle_count += 1;
        }
    }

    pub fn render(self: *const Self, camera_x: f32) void {
        // Parallax offset — background scrolls slower than the world
        const parallax_x = camera_x * config.BG_PARALLAX_FACTOR;
        const shift_i: i32 = @intFromFloat(@round(parallax_x));

        // Draw subtle grid pattern (wraps seamlessly with parallax)
        const grid_alpha: u8 = 15;
        const grid_color = rl.Color{ .r = 40, .g = 60, .b = 80, .a = grid_alpha };
        const grid_step: i32 = config.TILE_SIZE * 2;
        const grid_step_f: f32 = @floatFromInt(grid_step);
        const grid_off: i32 = @intFromFloat(@mod(parallax_x, grid_step_f));

        // Vertical grid lines (wrap with parallax)
        var gx: i32 = -grid_off;
        while (gx < config.SCREEN_WIDTH + grid_step) : (gx += grid_step) {
            rl.drawLine(gx, 0, gx, config.SCREEN_HEIGHT, grid_color);
        }
        // Horizontal grid lines (no vertical parallax)
        var gy: i32 = 0;
        while (gy < config.SCREEN_HEIGHT) : (gy += grid_step) {
            rl.drawLine(0, gy, config.SCREEN_WIDTH, gy, grid_color);
        }

        // Draw circuit traces with pulsing effect (shifted by parallax)
        for (self.circuit_traces) |trace| {
            const pulse = @sin(self.time * 2.0 + trace.pulse_offset * 3.14159);
            const brightness: u8 = @intFromFloat(80.0 + pulse * 40.0);
            const trace_color = rl.Color{ .r = brightness, .g = brightness + 30, .b = brightness + 50, .a = 120 };

            // Main trace line (parallax-shifted x)
            const x1 = trace.x1 - shift_i;
            const x2 = trace.x2 - shift_i;
            rl.drawLine(x1, trace.y1, x2, trace.y2, trace_color);

            // Draw pulsing "data packet" moving along trace
            const packet_pos = @mod(self.time * 0.3 + trace.pulse_offset, 1.0);
            const packet_x_world: i32 = @intFromFloat(@as(f32, @floatFromInt(trace.x1)) + packet_pos * @as(f32, @floatFromInt(trace.x2 - trace.x1)));
            const packet_x = packet_x_world - shift_i;
            const packet_y: i32 = @intFromFloat(@as(f32, @floatFromInt(trace.y1)) + packet_pos * @as(f32, @floatFromInt(trace.y2 - trace.y1)));

            const glow_color = rl.Color{ .r = 100, .g = 220, .b = 255, .a = 200 };
            rl.drawCircle(packet_x, packet_y, 3, glow_color);
            rl.drawCircle(packet_x, packet_y, 2, rl.Color.white);
        }

        // Draw connection nodes at trace intersections (parallax-shifted)
        for (self.circuit_traces, 0..) |trace1, i| {
            for (self.circuit_traces[i + 1 ..], i + 1..) |trace2, j| {
                if (trace1.is_horizontal != trace2.is_horizontal) {
                    const node_pulse = @sin(self.time * 3.0 + @as(f32, @floatFromInt(i + j)));
                    const node_alpha: u8 = @intFromFloat(150.0 + node_pulse * 50.0);

                    if (trace1.is_horizontal) {
                        if (trace2.x1 >= trace1.x1 and trace2.x1 <= trace1.x2 and
                            trace1.y1 >= trace2.y1 and trace1.y1 <= trace2.y2)
                        {
                            const node_color = rl.Color{ .r = 255, .g = 200, .b = 100, .a = node_alpha };
                            const node_x = trace2.x1 - shift_i;
                            rl.drawCircle(node_x, trace1.y1, 4, node_color);
                            rl.drawCircle(node_x, trace1.y1, 2, rl.Color{ .r = 255, .g = 255, .b = 200, .a = 255 });
                        }
                    }
                }
            }
        }

        // === Animated IC chips — mid-layer parallax (closer than traces) ===
        const chip_parallax_x = camera_x * config.BG_CHIP_PARALLAX_FACTOR;
        const chip_shift: i32 = @intFromFloat(@round(chip_parallax_x));

        for (self.chips) |chip| {
            const cx = chip.x - chip_shift;
            const cy = chip.y;

            // Skip if fully off-screen
            if (cx + chip.width < 0 or cx > config.SCREEN_WIDTH) continue;

            // --- Chip body (dark IC package) ---
            const body_color = rl.Color{ .r = 35, .g = 35, .b = 40, .a = 180 };
            rl.drawRectangle(cx, cy, chip.width, chip.height, body_color);

            // --- Pin legs along top and bottom edges ---
            const pin_color = rl.Color{ .r = 160, .g = 140, .b = 60, .a = 180 }; // gold pins
            const pin_w: i32 = 4;
            const pin_h: i32 = 3;
            const usable_w = chip.width - 8; // inset from edges
            const pin_spacing: i32 = if (chip.pins_per_side > 1)
                @divTrunc(usable_w, chip.pins_per_side - 1)
            else
                0;

            var p: i32 = 0;
            while (p < chip.pins_per_side) : (p += 1) {
                const px_off = 4 + p * pin_spacing;
                // Top pins (extend upward)
                rl.drawRectangle(cx + px_off, cy - pin_h, pin_w, pin_h, pin_color);
                // Bottom pins (extend downward)
                rl.drawRectangle(cx + px_off, cy + chip.height, pin_w, pin_h, pin_color);
            }

            // --- Orientation notch (semicircle indent on left edge) ---
            const notch_y = cy + @divTrunc(chip.height, 2);
            rl.drawCircle(cx, notch_y, 3, rl.Color{ .r = 50, .g = 50, .b = 55, .a = 180 });

            // --- Label text (single char stamped on body) ---
            const label_buf = [2]u8{ chip.label_char, 0 };
            const label_x = cx + @divTrunc(chip.width, 2) - 4;
            const label_y = cy + @divTrunc(chip.height, 2) - 5;
            rl.drawText(@ptrCast(&label_buf), label_x, label_y, 10, rl.Color{ .r = 120, .g = 120, .b = 130, .a = 150 });

            // --- Activity LED (blinking green/red dot, top-right corner) ---
            const led_pulse = @sin(self.time * 3.5 + chip.phase);
            const led_on = led_pulse > 0.0;
            const led_color = if (led_on)
                rl.Color{ .r = 50, .g = 220, .b = 80, .a = 200 } // green ON
            else
                rl.Color{ .r = 60, .g = 40, .b = 40, .a = 140 }; // dim OFF
            const led_x = cx + chip.width - 7;
            const led_y = cy + 5;
            rl.drawCircle(led_x, led_y, 2, led_color);

            // Glow halo when LED is on
            if (led_on) {
                const glow_a: u8 = @intFromFloat(60.0 + led_pulse * 40.0);
                rl.drawCircle(led_x, led_y, 5, rl.Color{ .r = 50, .g = 220, .b = 80, .a = glow_a });
            }

            // --- Subtle border highlight ---
            rl.drawRectangleLines(cx, cy, chip.width, chip.height, rl.Color{ .r = 60, .g = 60, .b = 70, .a = 120 });
        }

        // Draw particles (electrical sparks/data, parallax-shifted)
        for (self.particles[0..self.particle_count]) |particle| {
            const alpha_factor = particle.life / particle.max_life;
            const alpha: u8 = @intFromFloat(alpha_factor * 255.0);
            const color = rl.Color{ .r = particle.color.r, .g = particle.color.g, .b = particle.color.b, .a = alpha };

            const size: f32 = 2.0 + (1.0 - alpha_factor) * 2.0;
            const px = particle.x - parallax_x;
            rl.drawCircleV(rl.Vector2{ .x = px, .y = particle.y }, size, color);

            // Glow effect
            rl.drawCircleV(rl.Vector2{ .x = px, .y = particle.y }, size + 1, rl.Color{ .r = color.r, .g = color.g, .b = color.b, .a = alpha / 2 });
        }
    }
};
