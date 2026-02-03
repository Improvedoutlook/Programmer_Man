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

pub const Background = struct {
    particles: [64]Particle,
    particle_count: usize,
    circuit_traces: [12]CircuitTrace,
    time: f32,
    rng: std.rand.DefaultPrng,

    const Self = @This();

    pub fn init() Self {
        const rng = std.rand.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
        var self = Self{
            .particles = undefined,
            .particle_count = 0,
            .circuit_traces = undefined,
            .time = 0,
            .rng = rng,
        };

        // Initialize circuit traces (horizontal and vertical lines across screen)
        self.circuit_traces[0] = .{ .x1 = 50, .y1 = 100, .x2 = 750, .y2 = 100, .pulse_offset = 0, .is_horizontal = true };
        self.circuit_traces[1] = .{ .x1 = 50, .y1 = 200, .x2 = 750, .y2 = 200, .pulse_offset = 0.5, .is_horizontal = true };
        self.circuit_traces[2] = .{ .x1 = 50, .y1 = 300, .x2 = 750, .y2 = 300, .pulse_offset = 1.0, .is_horizontal = true };
        self.circuit_traces[3] = .{ .x1 = 50, .y1 = 500, .x2 = 750, .y2 = 500, .pulse_offset = 1.5, .is_horizontal = true };

        self.circuit_traces[4] = .{ .x1 = 150, .y1 = 50, .x2 = 150, .y2 = 550, .pulse_offset = 0.25, .is_horizontal = false };
        self.circuit_traces[5] = .{ .x1 = 300, .y1 = 50, .x2 = 300, .y2 = 550, .pulse_offset = 0.75, .is_horizontal = false };
        self.circuit_traces[6] = .{ .x1 = 450, .y1 = 50, .x2 = 450, .y2 = 550, .pulse_offset = 1.25, .is_horizontal = false };
        self.circuit_traces[7] = .{ .x1 = 600, .y1 = 50, .x2 = 600, .y2 = 550, .pulse_offset = 1.75, .is_horizontal = false };

        // Some angled traces for variety
        self.circuit_traces[8] = .{ .x1 = 100, .y1 = 150, .x2 = 200, .y2 = 250, .pulse_offset = 0.3, .is_horizontal = false };
        self.circuit_traces[9] = .{ .x1 = 400, .y1 = 400, .x2 = 500, .y2 = 300, .pulse_offset = 0.8, .is_horizontal = false };
        self.circuit_traces[10] = .{ .x1 = 600, .y1 = 150, .x2 = 700, .y2 = 250, .pulse_offset = 1.3, .is_horizontal = false };
        self.circuit_traces[11] = .{ .x1 = 200, .y1 = 450, .x2 = 350, .y2 = 500, .pulse_offset = 1.8, .is_horizontal = false };

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

    pub fn render(self: *const Self) void {
        // Draw subtle grid pattern
        const grid_alpha: u8 = 15;
        var x: i32 = 0;
        while (x < config.SCREEN_WIDTH) : (x += config.TILE_SIZE * 2) {
            rl.drawLine(x, 0, x, config.SCREEN_HEIGHT, rl.Color{ .r = 40, .g = 60, .b = 80, .a = grid_alpha });
        }
        var y: i32 = 0;
        while (y < config.SCREEN_HEIGHT) : (y += config.TILE_SIZE * 2) {
            rl.drawLine(0, y, config.SCREEN_WIDTH, y, rl.Color{ .r = 40, .g = 60, .b = 80, .a = grid_alpha });
        }

        // Draw circuit traces with pulsing effect
        for (self.circuit_traces) |trace| {
            const pulse = @sin(self.time * 2.0 + trace.pulse_offset * 3.14159);
            const brightness: u8 = @intFromFloat(80.0 + pulse * 40.0);
            const trace_color = rl.Color{ .r = brightness, .g = brightness + 30, .b = brightness + 50, .a = 120 };

            // Main trace line
            rl.drawLine(trace.x1, trace.y1, trace.x2, trace.y2, trace_color);

            // Draw pulsing "data packet" moving along trace
            const packet_pos = @mod(self.time * 0.3 + trace.pulse_offset, 1.0);
            const packet_x: i32 = @intFromFloat(@as(f32, @floatFromInt(trace.x1)) + packet_pos * @as(f32, @floatFromInt(trace.x2 - trace.x1)));
            const packet_y: i32 = @intFromFloat(@as(f32, @floatFromInt(trace.y1)) + packet_pos * @as(f32, @floatFromInt(trace.y2 - trace.y1)));

            const glow_color = rl.Color{ .r = 100, .g = 220, .b = 255, .a = 200 };
            rl.drawCircle(packet_x, packet_y, 3, glow_color);
            rl.drawCircle(packet_x, packet_y, 2, rl.Color.white);
        }

        // Draw connection nodes at trace intersections
        for (self.circuit_traces, 0..) |trace1, i| {
            for (self.circuit_traces[i + 1 ..], i + 1..) |trace2, j| {
                // Simple intersection detection (only for perpendicular lines)
                if (trace1.is_horizontal != trace2.is_horizontal) {
                    const node_pulse = @sin(self.time * 3.0 + @as(f32, @floatFromInt(i + j)));
                    const node_alpha: u8 = @intFromFloat(150.0 + node_pulse * 50.0);

                    if (trace1.is_horizontal) {
                        if (trace2.x1 >= trace1.x1 and trace2.x1 <= trace1.x2 and
                            trace1.y1 >= trace2.y1 and trace1.y1 <= trace2.y2)
                        {
                            const node_color = rl.Color{ .r = 255, .g = 200, .b = 100, .a = node_alpha };
                            rl.drawCircle(trace2.x1, trace1.y1, 4, node_color);
                            rl.drawCircle(trace2.x1, trace1.y1, 2, rl.Color{ .r = 255, .g = 255, .b = 200, .a = 255 });
                        }
                    }
                }
            }
        }

        // Draw particles (electrical sparks/data)
        for (self.particles[0..self.particle_count]) |particle| {
            const alpha_factor = particle.life / particle.max_life;
            const alpha: u8 = @intFromFloat(alpha_factor * 255.0);
            const color = rl.Color{ .r = particle.color.r, .g = particle.color.g, .b = particle.color.b, .a = alpha };

            const size: f32 = 2.0 + (1.0 - alpha_factor) * 2.0;
            rl.drawCircleV(rl.Vector2{ .x = particle.x, .y = particle.y }, size, color);

            // Glow effect
            rl.drawCircleV(rl.Vector2{ .x = particle.x, .y = particle.y }, size + 1, rl.Color{ .r = color.r, .g = color.g, .b = color.b, .a = alpha / 2 });
        }
    }
};
