//! Moving platform module — solid platforms that travel along a fixed path
//! (ping-pong along one axis) and are intended to carry the player when ridden.
//!
//! Phase 3: data + movement + rendering only. Player collision / carry is added
//! in Phase 4 via `MovingPlatformManager.resolvePlayer`.

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const tilemap = @import("tilemap.zig");
const Player = @import("player.zig").Player;
const TileType = tilemap.TileType;
const MovingPlatformSpawn = tilemap.MovingPlatformSpawn;
const MAX_MOVING_PLATFORMS = tilemap.MAX_MOVING_PLATFORMS;

pub const MovingPlatform = struct {
    // All in pixels.
    x: f32,
    y: f32,
    width: f32,
    height: f32, // = TILE_SIZE
    tile_type: TileType,
    vertical: bool,
    min_pos: f32, // along travel axis
    max_pos: f32,
    speed: f32, // px/s
    dir: f32, // +1 / -1
    dx: f32, // delta moved this frame (for carrying the player in Phase 4)
    dy: f32,
    active: bool,

    const Self = @This();

    pub fn update(self: *Self, dt: f32) void {
        if (!self.active) return;

        const prev_x = self.x;
        const prev_y = self.y;
        if (self.vertical) {
            self.y += self.speed * self.dir * dt;
            if (self.y < self.min_pos) {
                self.y = self.min_pos;
                self.dir = 1;
            }
            if (self.y > self.max_pos) {
                self.y = self.max_pos;
                self.dir = -1;
            }
        } else {
            self.x += self.speed * self.dir * dt;
            if (self.x < self.min_pos) {
                self.x = self.min_pos;
                self.dir = 1;
            }
            if (self.x > self.max_pos) {
                self.x = self.max_pos;
                self.dir = -1;
            }
        }
        self.dx = self.x - prev_x;
        self.dy = self.y - prev_y;
    }

    pub fn getRect(self: *const Self) rl.Rectangle {
        return rl.Rectangle{
            .x = self.x,
            .y = self.y,
            .width = self.width,
            .height = self.height,
        };
    }

    /// Base fill color for the platform body, tinted by the visual tile_type so
    /// authors can vary the look while platforms stay readable as "moving".
    fn fillColor(self: *const Self) rl.Color {
        return switch (self.tile_type) {
            .chip => rl.Color{ .r = 40, .g = 52, .b = 70, .a = 255 },
            .capacitor => rl.Color{ .r = 44, .g = 40, .b = 80, .a = 255 },
            else => rl.Color{ .r = 46, .g = 70, .b = 92, .a = 255 }, // solid (default)
        };
    }

    pub fn render(self: *const Self) void {
        if (!self.active) return;

        const ts = config.TILE_SIZE;
        const px: i32 = @intFromFloat(self.x);
        const py: i32 = @intFromFloat(self.y);
        const w: i32 = @intFromFloat(self.width);
        const h: i32 = @intFromFloat(self.height);

        const body = self.fillColor();
        rl.drawRectangle(px, py, w, h, body);

        // Per-tile seams so the platform reads at the same scale as static tiles.
        const tile_count: i32 = @divTrunc(w, ts);
        var seam: i32 = 1;
        while (seam < tile_count) : (seam += 1) {
            const sx = px + seam * ts;
            rl.drawRectangle(sx, py, 1, h, rl.Color{ .r = 18, .g = 26, .b = 36, .a = 180 });
        }

        // Animated bright top edge — the main "this moves" cue.
        const t: f32 = @floatCast(rl.getTime());
        const pulse: u8 = @intFromFloat(140.0 + (@sin(t * 5.0) * 0.5 + 0.5) * 115.0);
        const edge = rl.Color{ .r = 90, .g = 210, .b = 255, .a = pulse };
        rl.drawRectangle(px, py, w, 2, edge);
        rl.drawRectangle(px, py + h - 2, w, 2, rl.Color{ .r = 30, .g = 90, .b = 130, .a = 200 });
        rl.drawRectangleLines(px, py, w, h, rl.Color{ .r = 110, .g = 200, .b = 240, .a = 90 });

        // Directional chevrons scrolling along the travel axis to show motion.
        const chev_color = rl.Color{ .r = 150, .g = 230, .b = 255, .a = 200 };
        const cx = @as(f32, @floatFromInt(px)) + self.width / 2.0;
        const cy = @as(f32, @floatFromInt(py)) + self.height / 2.0;
        const wobble = @sin(t * 4.0) * 3.0;
        if (self.vertical) {
            // Point in the current travel direction (up = -1, down = +1).
            const tip_y = cy + self.dir * (5.0 + wobble);
            const base_y = cy - self.dir * 4.0;
            rl.drawTriangle(
                .{ .x = cx, .y = tip_y },
                .{ .x = cx - 6, .y = base_y },
                .{ .x = cx + 6, .y = base_y },
                chev_color,
            );
        } else {
            const tip_x = cx + self.dir * (6.0 + wobble);
            const base_x = cx - self.dir * 5.0;
            rl.drawTriangle(
                .{ .x = tip_x, .y = cy },
                .{ .x = base_x, .y = cy - 5 },
                .{ .x = base_x, .y = cy + 5 },
                chev_color,
            );
        }
    }
};

pub const MovingPlatformManager = struct {
    platforms: [MAX_MOVING_PLATFORMS]MovingPlatform,
    count: usize,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .platforms = undefined,
            .count = 0,
        };
    }

    pub fn reset(self: *Self) void {
        self.count = 0;
    }

    /// Create a platform from a spawn descriptor (tile coordinates → pixels),
    /// applying the starting phase offset so platforms desync.
    pub fn spawn(self: *Self, sp: MovingPlatformSpawn) void {
        if (self.count >= MAX_MOVING_PLATFORMS) return;

        const ts: f32 = @floatFromInt(config.TILE_SIZE);
        const start_x = @as(f32, @floatFromInt(sp.tile_x)) * ts;
        const start_y = @as(f32, @floatFromInt(sp.tile_y)) * ts;
        const travel = @as(f32, @floatFromInt(sp.distance_tiles)) * ts;
        const phase = std.math.clamp(sp.phase, 0.0, 1.0);

        var p = MovingPlatform{
            .x = start_x,
            .y = start_y,
            .width = @as(f32, @floatFromInt(sp.width_tiles)) * ts,
            .height = ts,
            .tile_type = sp.tile_type,
            .vertical = sp.vertical,
            .min_pos = 0,
            .max_pos = 0,
            .speed = sp.speed_tiles * ts,
            .dir = 1,
            .dx = 0,
            .dy = 0,
            .active = true,
        };

        if (sp.vertical) {
            p.min_pos = start_y;
            p.max_pos = start_y + travel;
            p.y = start_y + phase * travel;
        } else {
            p.min_pos = start_x;
            p.max_pos = start_x + travel;
            p.x = start_x + phase * travel;
        }

        self.platforms[self.count] = p;
        self.count += 1;
    }

    pub fn update(self: *Self, dt: f32) void {
        for (0..self.count) |i| {
            self.platforms[i].update(dt);
        }
    }

    pub fn render(self: *const Self) void {
        for (0..self.count) |i| {
            self.platforms[i].render();
        }
    }

    /// Resolve the player against all moving platforms after tile physics have run.
    /// Lands the player on top of any platform they're falling onto and carries them
    /// by that platform's per-frame delta (top-ride one-way collision).
    ///
    /// `player.y` is the feet position (center-bottom); `getRect` returns the
    /// top-left, so `rect.y + rect.height == player.y`.
    pub fn resolvePlayer(self: *Self, player: *Player) void {
        const half_width = config.PLAYER_WIDTH / 2.0;

        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            const p = &self.platforms[i];
            if (!p.active) continue;

            const pr = player.getRect(); // player AABB (top-left + size)
            const feet = pr.y + pr.height; // player's bottom edge (== player.y)
            const plat = p.getRect();

            const horizontally_overlapping =
                pr.x < plat.x + plat.width and pr.x + pr.width > plat.x;

            // Landing/standing tolerance: feet within a small band of the platform
            // top, and the player is moving downward (or resting).
            const landing = horizontally_overlapping and
                player.vy >= 0 and
                feet >= plat.y - 6 and feet <= plat.y + 8;

            if (landing) {
                // Snap feet to platform top (player.y is the feet position).
                player.y = plat.y;
                player.vy = 0;
                player.on_ground = true;
                // Carry: move with the platform this frame.
                player.x += p.dx;
                player.y += p.dy;
            }
        }

        // Re-clamp to the level's left edge in case a horizontal carry pushed the
        // player past it (right edge is handled by the platform travel authoring).
        if (player.x < half_width) {
            player.x = half_width;
        }
    }
};
