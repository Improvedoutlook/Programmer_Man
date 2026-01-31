//! Enemy module - Bug enemies that patrol and can be stomped

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const Tilemap = @import("tilemap.zig").Tilemap;
const Player = @import("player.zig").Player;
const audio = @import("audio.zig");

pub const BugState = enum {
    walking,
    dying,
    dead,
};

pub const Bug = struct {
    x: f32,
    y: f32,
    vx: f32,
    state: BugState,
    facing_right: bool,
    anim_frame: u8,
    anim_timer: f32,
    death_timer: f32,
    active: bool,

    const Self = @This();

    pub fn init(tile_x: i32, tile_y: i32, facing_right: bool) Self {
        return Self{
            .x = @as(f32, @floatFromInt(tile_x * config.TILE_SIZE)) + config.BUG_WIDTH / 2,
            .y = @as(f32, @floatFromInt(tile_y * config.TILE_SIZE)) + config.BUG_HEIGHT,
            .vx = if (facing_right) config.BUG_WALK_SPEED else -config.BUG_WALK_SPEED,
            .state = .walking,
            .facing_right = facing_right,
            .anim_frame = 0,
            .anim_timer = 0,
            .death_timer = 0,
            .active = true,
        };
    }

    pub fn update(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        if (!self.active) return;

        switch (self.state) {
            .walking => self.updateWalking(dt, tilemap),
            .dying => self.updateDying(dt),
            .dead => {},
        }

        self.updateAnimation(dt);
    }

    fn updateWalking(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        const new_x = self.x + self.vx * dt;
        const half_width = config.BUG_WIDTH / 2;

        // Check for wall collision at new position
        const hit_wall = tilemap.checkCollision(
            new_x - half_width,
            self.y - config.BUG_HEIGHT + 2,
            config.BUG_WIDTH,
            config.BUG_HEIGHT - 4,
        );

        // Check for edge (no ground ahead) - look further ahead
        const edge_check_dist: f32 = half_width + 4;
        const check_x = if (self.vx > 0) new_x + edge_check_dist else new_x - edge_check_dist;
        const has_ground_ahead = tilemap.checkCollision(check_x, self.y + 2, 2, 2);

        if (hit_wall or !has_ground_ahead) {
            // Turn around
            self.vx = -self.vx;
            self.facing_right = !self.facing_right;
        } else {
            // Move to new position
            self.x = new_x;
        }
    }

    fn updateDying(self: *Self, dt: f32) void {
        self.death_timer += dt;
        if (self.death_timer >= 0.3) {
            self.state = .dead;
            self.active = false;
        }
    }

    fn updateAnimation(self: *Self, dt: f32) void {
        self.anim_timer += dt;
        const frame_duration: f32 = if (self.state == .walking) 0.15 else 0.05;

        if (self.anim_timer >= frame_duration) {
            self.anim_timer = 0;
            self.anim_frame = (self.anim_frame + 1) % 2;
        }
    }

    pub fn stomp(self: *Self) void {
        self.state = .dying;
        self.death_timer = 0;
        self.vx = 0;
        // Play stomp sound effect (bug squish)
        audio.playSfx(.Stomp, config.SFX_VOLUME);
    }

    pub fn getRect(self: *const Self) rl.Rectangle {
        return rl.Rectangle{
            .x = self.x - config.BUG_WIDTH / 2,
            .y = self.y - config.BUG_HEIGHT,
            .width = config.BUG_WIDTH,
            .height = config.BUG_HEIGHT,
        };
    }

    pub fn render(self: *const Self) void {
        if (!self.active) return;

        const rect = self.getRect();

        // Color varies based on state
        const color: rl.Color = switch (self.state) {
            .walking => config.BUG_COLOR,
            .dying => rl.Color{ .r = 255, .g = 200, .b = 200, .a = 255 },
            .dead => rl.Color{ .r = 100, .g = 100, .b = 100, .a = 255 },
        };

        // Draw bug body
        if (self.state == .dying) {
            // Squashed appearance
            rl.drawRectangle(
                @intFromFloat(rect.x - 2),
                @intFromFloat(rect.y + rect.height - 6),
                @intFromFloat(rect.width + 4),
                6,
                color,
            );
        } else {
            // Normal bug body (oval-ish)
            rl.drawEllipse(
                @intFromFloat(self.x),
                @intFromFloat(self.y - config.BUG_HEIGHT / 2),
                config.BUG_WIDTH / 2,
                config.BUG_HEIGHT / 2 - 2,
                color,
            );

            // Legs (animated)
            const leg_offset: i32 = if (self.anim_frame == 0) 0 else 2;
            const base_x: i32 = @intFromFloat(rect.x);
            const base_y: i32 = @intFromFloat(rect.y + rect.height - 4);

            // Left legs
            rl.drawLine(base_x + 2, base_y - leg_offset, base_x, base_y + 2, color);
            rl.drawLine(base_x + 5, base_y + leg_offset, base_x + 3, base_y + 2, color);

            // Right legs
            rl.drawLine(base_x + 11, base_y - leg_offset, base_x + 13, base_y + 2, color);
            rl.drawLine(base_x + 14, base_y + leg_offset, base_x + 16, base_y + 2, color);

            // Eyes
            const eye_y: i32 = @intFromFloat(rect.y + 4);
            const eye_x1: i32 = @intFromFloat(rect.x + 4);
            const eye_x2: i32 = @intFromFloat(rect.x + 10);
            rl.drawCircle(eye_x1, eye_y, 2, rl.Color.white);
            rl.drawCircle(eye_x2, eye_y, 2, rl.Color.white);

            // Antennae
            const ant_base_y: i32 = @intFromFloat(rect.y);
            const ant_x1: i32 = @intFromFloat(rect.x + 4);
            const ant_x2: i32 = @intFromFloat(rect.x + 12);
            rl.drawLine(ant_x1, ant_base_y, ant_x1 - 2, ant_base_y - 4, color);
            rl.drawLine(ant_x2, ant_base_y, ant_x2 + 2, ant_base_y - 4, color);
        }
    }
};

pub const BugManager = struct {
    bugs: [config.MAX_BUGS]Bug,
    count: usize,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .bugs = undefined,
            .count = 0,
        };
    }

    pub fn spawn(self: *Self, tile_x: i32, tile_y: i32, facing_right: bool) void {
        if (self.count >= config.MAX_BUGS) return;

        self.bugs[self.count] = Bug.init(tile_x, tile_y, facing_right);
        self.count += 1;
    }

    pub fn update(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        for (0..self.count) |i| {
            self.bugs[i].update(dt, tilemap);
        }
    }

    pub fn checkPlayerCollision(self: *Self, player: *Player) void {
        if (player.invincible_timer > 0) return;

        const player_rect = player.getRect();

        for (0..self.count) |i| {
            var bug = &self.bugs[i];
            if (!bug.active or bug.state != .walking) continue;

            const bug_rect = bug.getRect();

            if (rl.checkCollisionRecs(player_rect, bug_rect)) {
                // Check if player is stomping (falling and hitting from above)
                const player_bottom = player_rect.y + player_rect.height;
                const bug_top = bug_rect.y;
                const is_stomping = player.vy > 0 and player_bottom <= bug_top + 8;

                if (is_stomping) {
                    // Stomp the bug!
                    // Play pounce sound (impact before bounce)
                    audio.playSfx(.Pounce, config.SFX_VOLUME * 0.8);
                    bug.stomp();
                    player.addScore(config.POINTS_PER_STOMP);
                    player.bounce();
                } else {
                    // Player takes damage
                    player.takeDamage();
                }
            }
        }
    }

    pub fn render(self: *const Self) void {
        for (0..self.count) |i| {
            self.bugs[i].render();
        }
    }

    pub fn reset(self: *Self) void {
        self.count = 0;
    }

    pub fn getActiveCount(self: *const Self) usize {
        var count: usize = 0;
        for (0..self.count) |i| {
            if (self.bugs[i].active) count += 1;
        }
        return count;
    }
};
