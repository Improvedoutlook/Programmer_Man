//! Hazard module - Environmental dangers like falling sparks

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const Tilemap = @import("tilemap.zig").Tilemap;
const Player = @import("player.zig").Player;

pub const Spark = struct {
    x: f32,
    y: f32,
    vy: f32, // Vertical velocity (falling speed)
    active: bool,
    particle_timer: f32, // For visual effect

    const Self = @This();
    const FALL_SPEED: f32 = 200.0; // Pixels per second
    const WIDTH: f32 = 4.0;
    const HEIGHT: f32 = 8.0;

    pub fn init(x: f32, y: f32) Self {
        return Self{
            .x = x,
            .y = y,
            .vy = FALL_SPEED,
            .active = true,
            .particle_timer = 0,
        };
    }

    pub fn update(self: *Self, dt: f32) void {
        if (!self.active) return;

        // Fall downward
        self.y += self.vy * dt;

        // Update particle effect timer
        self.particle_timer += dt;

        // Deactivate if off screen (fell below game area)
        if (self.y > @as(f32, @floatFromInt(config.SCREEN_HEIGHT))) {
            self.active = false;
        }
    }

    pub fn getRect(self: *const Self) rl.Rectangle {
        return rl.Rectangle{
            .x = self.x - WIDTH / 2,
            .y = self.y - HEIGHT / 2,
            .width = WIDTH,
            .height = HEIGHT,
        };
    }

    pub fn render(self: *const Self) void {
        if (!self.active) return;

        // Bright electric spark color (orange-yellow)
        const spark_color = rl.Color{ .r = 255, .g = 180, .b = 0, .a = 255 };
        const glow_color = rl.Color{ .r = 255, .g = 100, .b = 0, .a = 100 };

        const rect = self.getRect();

        // Glow effect (larger, semi-transparent)
        rl.drawRectangle(
            @intFromFloat(rect.x - 2),
            @intFromFloat(rect.y - 2),
            @intFromFloat(rect.width + 4),
            @intFromFloat(rect.height + 4),
            glow_color,
        );

        // Core spark
        rl.drawRectangle(
            @intFromFloat(rect.x),
            @intFromFloat(rect.y),
            @intFromFloat(rect.width),
            @intFromFloat(rect.height),
            spark_color,
        );

        // Add some particle trails (small dots falling behind)
        const total_f: f32 = self.particle_timer * 100.0;
        const total_i: i32 = @intFromFloat(total_f);
        const rem_i: i32 = @rem(total_i, @as(i32, 10));
        const trail_offset: f32 = @floatFromInt(rem_i);
        rl.drawCircle(
            @intFromFloat(self.x),
            @intFromFloat(self.y - trail_offset),
            1.5,
            rl.Color{ .r = 255, .g = 150, .b = 50, .a = 150 },
        );
    }
};

pub const SparkManager = struct {
    sparks: [config.MAX_SPARKS]Spark,
    count: usize,
    spawn_timer: f32,
    spawn_interval: f32,
    spawn_cycle: usize, // Track which platform to spawn from next

    const Self = @This();

    // Platform positions where sparks spawn (x, y in pixels)
    const SpawnPoint = struct {
        x: f32,
        y: f32,
    };

    // Platform positions where sparks spawn (x position in pixels)
    const SPAWN_POSITIONS = [_]SpawnPoint{
        .{ .x = 20.0 * @as(f32, config.TILE_SIZE), .y = 27.0 * @as(f32, config.TILE_SIZE) }, // Platform 2
        .{ .x = 34.0 * @as(f32, config.TILE_SIZE), .y = 23.0 * @as(f32, config.TILE_SIZE) }, // Platform 3
        .{ .x = 44.0 * @as(f32, config.TILE_SIZE), .y = 17.0 * @as(f32, config.TILE_SIZE) }, // High platform
    };

    pub fn init() Self {
        return Self{
            .sparks = undefined,
            .count = 0,
            .spawn_timer = 0,
            .spawn_interval = 0.5, // Spawn every 0.5 seconds
            .spawn_cycle = 0,
        };
    }

    pub fn update(self: *Self, dt: f32) void {
        // Update existing sparks
        for (0..self.count) |i| {
            self.sparks[i].update(dt);
        }

        // Spawn new sparks periodically
        self.spawn_timer += dt;
        if (self.spawn_timer >= self.spawn_interval) {
            self.spawn_timer = 0;

            self.spawnNextSpark();
        }
    }

    fn spawnNextSpark(self: *Self) void {
        if (self.count >= config.MAX_SPARKS) {
            // Reuse inactive spark slot
            for (0..self.count) |i| {
                if (!self.sparks[i].active) {
                    const spawn_point = SPAWN_POSITIONS[self.spawn_cycle];
                    self.sparks[i] = Spark.init(spawn_point.x, spawn_point.y);

                    // Cycle to next platform
                    self.spawn_cycle = (self.spawn_cycle + 1) % SPAWN_POSITIONS.len;
                    return;
                }
            }
            return; // All slots full and active
        }

        // Get the current spawn point
        const spawn_point = SPAWN_POSITIONS[self.spawn_cycle];

        // Create spark at platform position
        self.sparks[self.count] = Spark.init(spawn_point.x, spawn_point.y);
        self.count += 1;

        // Cycle to next platform for next spawn
        self.spawn_cycle = (self.spawn_cycle + 1) % SPAWN_POSITIONS.len;
    }

    pub fn checkPlayerCollision(self: *const Self, player: *Player) void {
        if (player.invincible_timer > 0) return;

        const player_rect = player.getRect();

        for (0..self.count) |i| {
            const spark = &self.sparks[i];
            if (!spark.active) continue;

            const spark_rect = spark.getRect();

            if (rl.checkCollisionRecs(player_rect, spark_rect)) {
                // Player hit by spark - takes damage
                player.takeDamage();
                // We don't deactivate the spark - it continues falling
            }
        }
    }

    pub fn render(self: *const Self) void {
        var active_count: usize = 0;
        for (0..self.count) |i| {
            if (self.sparks[i].active) {
                active_count += 1;
                self.sparks[i].render();
            }
        }
    }

    pub fn reset(self: *Self) void {
        self.count = 0;
        self.spawn_timer = 0;
        self.spawn_cycle = 0;
    }
};
