//! Enemy module - Bug enemies that patrol and can be stomped

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const Tilemap = @import("tilemap.zig").Tilemap;
const AiType = @import("tilemap.zig").AiType;
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
    vy: f32,
    walk_speed: f32,
    state: BugState,
    facing_right: bool,
    anim_frame: u8,
    anim_timer: f32,
    death_timer: f32,
    active: bool,
    ai: AiType,
    jump_timer: f32,
    on_ground: bool,

    const Self = @This();

    pub fn init(tile_x: i32, tile_y: i32, facing_right: bool, walk_speed: f32, ai: AiType) Self {
        // Seed jump_timer with a pseudo-random offset based on spawn position
        const seed_val: f32 = @as(f32, @floatFromInt(@mod(tile_x * 7 + tile_y * 13, 100))) / 100.0;
        const initial_jump_timer = config.JUMPER_INTERVAL_MIN + seed_val * (config.JUMPER_INTERVAL_MAX - config.JUMPER_INTERVAL_MIN);
        return Self{
            .x = @as(f32, @floatFromInt(tile_x * config.TILE_SIZE)) + config.BUG_WIDTH / 2,
            .y = @as(f32, @floatFromInt(tile_y * config.TILE_SIZE)) + config.BUG_HEIGHT,
            .vx = if (facing_right) walk_speed else -walk_speed,
            .vy = 0,
            .walk_speed = walk_speed,
            .state = .walking,
            .facing_right = facing_right,
            .anim_frame = 0,
            .anim_timer = 0,
            .death_timer = 0,
            .active = true,
            .ai = ai,
            .jump_timer = initial_jump_timer,
            .on_ground = true,
        };
    }

    pub fn update(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        if (!self.active) return;

        switch (self.state) {
            .walking => self.updateWalking(dt, tilemap),
            .dying => self.updateDying(dt),
            .dead => {},
        }

        // Treat bugs that fall out of the level as defeated so they cannot soft-lock progression.
        if (self.active and self.y > tilemap.getLevelPixelHeight() + @as(f32, @floatFromInt(config.TILE_SIZE * 2))) {
            self.state = .dead;
            self.active = false;
            self.vx = 0;
            self.vy = 0;
            return;
        }

        self.updateAnimation(dt);
    }

    fn updateWalking(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        // Apply gravity
        self.vy += config.PLAYER_GRAVITY * dt;
        if (self.vy > config.PLAYER_MAX_FALL_SPEED) self.vy = config.PLAYER_MAX_FALL_SPEED;

        // Vertical movement / ground check
        const new_y = self.y + self.vy * dt;
        const half_width = config.BUG_WIDTH / 2;
        const ground_hit = tilemap.checkCollision(
            self.x - half_width,
            new_y,
            config.BUG_WIDTH,
            2,
        );
        if (self.vy >= 0 and ground_hit) {
            // Snap to top of tile
            const tile_y: i32 = @intFromFloat(@floor(new_y / @as(f32, @floatFromInt(config.TILE_SIZE))));
            self.y = @as(f32, @floatFromInt(tile_y * config.TILE_SIZE));
            self.vy = 0;
            self.on_ground = true;
        } else {
            self.y = new_y;
            self.on_ground = false;
        }

        // Jumper AI: attempt an intermittent jump when on ground
        if (self.ai == .jumper) {
            self.attemptJump(dt, tilemap);
        }

        // Horizontal movement
        const new_x = self.x + self.vx * dt;

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

        // Prevent walking off the level bounds
        const level_pixel_w: f32 = tilemap.getLevelPixelWidth();
        const would_leave_left = (new_x - half_width) < 0.0;
        const would_leave_right = (new_x + half_width) > level_pixel_w;

        // Only check edge if on ground (airborne jumpers should keep moving)
        const should_turn = hit_wall or (self.on_ground and !has_ground_ahead) or would_leave_left or would_leave_right;

        if (should_turn) {
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

    fn attemptJump(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        self.jump_timer -= dt;
        if (self.on_ground and self.jump_timer <= 0) {
            // Predict landing X using a simple ballistic estimate and disallow jumps
            // that would land outside the level or in a column with no solid tiles.
            const g: f32 = config.PLAYER_GRAVITY;
            const vy0: f32 = config.JUMPER_JUMP_VELOCITY; // negative (upwards)
            const total_air_time: f32 = (-2.0 * vy0) / g; // approximate time in air
            const predicted_x: f32 = self.x + self.vx * total_air_time;

            const tile_x: i32 = @intFromFloat(@floor(predicted_x / @as(f32, @floatFromInt(config.TILE_SIZE))));

            // If landing column is outside level bounds, abort jump and turn around
            if (tile_x < 0 or tile_x >= tilemap.level_width) {
                self.vx = -self.vx;
                self.facing_right = !self.facing_right;
                self.jump_timer = config.JUMPER_INTERVAL_MIN;
                return;
            }

            // Check if there's any solid tile in the target column (so we don't jump into a void)
            var has_solid: bool = false;
            var yy: i32 = 0;
            while (yy < tilemap.level_height) : (yy += 1) {
                if (tilemap.isSolid(tile_x, yy)) {
                    has_solid = true;
                    break;
                }
            }

            if (!has_solid) {
                // No landing platform; abort jump and reverse direction to avoid falling off
                self.vx = -self.vx;
                self.facing_right = !self.facing_right;
                self.jump_timer = config.JUMPER_INTERVAL_MIN;
                return;
            }

            // Safe to jump
            self.vy = config.JUMPER_JUMP_VELOCITY;
            self.on_ground = false;

            // Reset timer using a simple deterministic pseudo-random based on position
            const px: i32 = @intFromFloat(self.x);
            const py: i32 = @intFromFloat(self.y);
            const hash: f32 = @as(f32, @floatFromInt(@mod(px * 31 + py * 17, 100))) / 100.0;
            self.jump_timer = config.JUMPER_INTERVAL_MIN + hash * (config.JUMPER_INTERVAL_MAX - config.JUMPER_INTERVAL_MIN);
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
        self.vy = 0;
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

    pub fn spawn(self: *Self, tile_x: i32, tile_y: i32, facing_right: bool, walk_speed: f32, ai: AiType) void {
        if (self.count >= config.MAX_BUGS) return;

        self.bugs[self.count] = Bug.init(tile_x, tile_y, facing_right, walk_speed, ai);
        self.count += 1;
    }

    pub fn update(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        for (0..self.count) |i| {
            self.bugs[i].update(dt, tilemap);
        }
    }

    pub fn checkPlayerCollision(self: *Self, player: *Player, dt: f32) void {
        if (player.invincible_timer > 0) return;

        const player_rect = player.getRect();

        for (0..self.count) |i| {
            var bug = &self.bugs[i];
            if (!bug.active or bug.state != .walking) continue;

            const bug_rect = bug.getRect();

            if (rl.checkCollisionRecs(player_rect, bug_rect)) {
                // Check if player is stomping (falling and hitting from above).
                const player_bottom = player_rect.y + player_rect.height;
                const bug_top = bug_rect.y;
                // Swept check: at high fall speeds the player can move further than
                // the stomp window in a single frame, tunnelling past the bug's top
                // so a stomp reads as a side hit. Reconstruct the previous foot
                // position and treat it as a stomp if the feet were above the bug
                // before this frame's descent, not only if they land in the window.
                const prev_bottom = player_bottom - player.vy * dt;
                const is_stomping = player.vy > 0 and
                    (player_bottom <= bug_top + 8 or prev_bottom <= bug_top + 8);

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
