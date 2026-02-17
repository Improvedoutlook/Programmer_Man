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

    pub fn update(self: *Self, dt: f32, level_pixel_height: f32) void {
        if (!self.active) return;

        // Fall downward
        self.y += self.vy * dt;

        // Update particle effect timer
        self.particle_timer += dt;

        // Deactivate if below level bounds
        if (self.y > level_pixel_height) {
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
    pub const MAX_SPAWN_POINTS: usize = 32;

    pub const SpawnPoint = struct {
        x: f32,
        y: f32,
    };

    const Self = @This();

    sparks: [config.MAX_SPARKS]Spark,
    count: usize,
    spawn_timer: f32,
    spawn_interval: f32,
    spawn_cycle: usize, // Track which platform to spawn from next
    spawn_positions: [MAX_SPAWN_POINTS]SpawnPoint,
    spawn_point_count: usize,
    level_pixel_height: f32, // World height in pixels — used for spark deactivation

    pub fn init() Self {
        return Self{
            .sparks = undefined,
            .count = 0,
            .spawn_timer = 0,
            .spawn_interval = 0.5,
            .spawn_cycle = 0,
            .spawn_positions = undefined,
            .spawn_point_count = 0,
            .level_pixel_height = @floatFromInt(config.SCREEN_HEIGHT),
        };
    }

    /// Register a world-pixel position where sparks should rain from.
    pub fn addSpawnPoint(self: *Self, x: f32, y: f32) void {
        if (self.spawn_point_count < MAX_SPAWN_POINTS) {
            self.spawn_positions[self.spawn_point_count] = .{ .x = x, .y = y };
            self.spawn_point_count += 1;
        }
    }

    pub fn update(self: *Self, dt: f32) void {
        // Update existing sparks
        for (0..self.count) |i| {
            self.sparks[i].update(dt, self.level_pixel_height);
        }

        // Spawn new sparks periodically
        self.spawn_timer += dt;
        if (self.spawn_timer >= self.spawn_interval) {
            self.spawn_timer = 0;

            self.spawnNextSpark();
        }
    }

    fn spawnNextSpark(self: *Self) void {
        if (self.spawn_point_count == 0) return; // No spawn points configured

        if (self.count >= config.MAX_SPARKS) {
            // Reuse inactive spark slot
            for (0..self.count) |i| {
                if (!self.sparks[i].active) {
                    const spawn_point = self.spawn_positions[self.spawn_cycle];
                    self.sparks[i] = Spark.init(spawn_point.x, spawn_point.y);
                    self.spawn_cycle = (self.spawn_cycle + 1) % self.spawn_point_count;
                    return;
                }
            }
            return; // All slots full and active
        }

        const spawn_point = self.spawn_positions[self.spawn_cycle];
        self.sparks[self.count] = Spark.init(spawn_point.x, spawn_point.y);
        self.count += 1;
        self.spawn_cycle = (self.spawn_cycle + 1) % self.spawn_point_count;
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
        self.spawn_point_count = 0;
        self.level_pixel_height = @floatFromInt(config.SCREEN_HEIGHT);
    }
};
