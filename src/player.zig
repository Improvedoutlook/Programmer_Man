//! Player module - Handles Programmer_Man character physics, movement, and rendering

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const Tilemap = @import("tilemap.zig").Tilemap;

pub const PlayerState = enum {
    idle,
    running,
    jumping,
    falling,
    stomping,
    dead,
};

pub const Player = struct {
    // Position (center-bottom of player)
    x: f32,
    y: f32,

    // Velocity
    vx: f32,
    vy: f32,

    // State
    state: PlayerState,
    facing_right: bool,
    on_ground: bool,
    jump_requested: bool,
    jump_held: bool,

    // Animation
    anim_frame: u8,
    anim_timer: f32,

    // Stats
    lives: i32,
    score: i32,
    invincible_timer: f32,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .x = @as(f32, @floatFromInt(config.SPAWN_TILE_X * config.TILE_SIZE)) + config.PLAYER_WIDTH / 2,
            .y = @as(f32, @floatFromInt(config.SPAWN_TILE_Y * config.TILE_SIZE)) + config.PLAYER_HEIGHT,
            .vx = 0,
            .vy = 0,
            .state = .idle,
            .facing_right = true,
            .on_ground = false,
            .jump_requested = false,
            .jump_held = false,
            .anim_frame = 0,
            .anim_timer = 0,
            .lives = config.INITIAL_LIVES,
            .score = 0,
            .invincible_timer = 0,
        };
    }

    pub fn respawn(self: *Self) void {
        self.x = @as(f32, @floatFromInt(config.SPAWN_TILE_X * config.TILE_SIZE)) + config.PLAYER_WIDTH / 2;
        self.y = @as(f32, @floatFromInt(config.SPAWN_TILE_Y * config.TILE_SIZE)) + config.PLAYER_HEIGHT;
        self.vx = 0;
        self.vy = 0;
        self.state = .idle;
        self.on_ground = false;
        self.invincible_timer = 2.0; // Brief invincibility after respawn
    }

    pub fn handleInput(self: *Self) void {
        // Horizontal movement
        var move_input: f32 = 0;

        if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) {
            move_input -= 1;
            self.facing_right = false;
        }
        if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) {
            move_input += 1;
            self.facing_right = true;
        }

        // Apply acceleration based on ground/air state
        const accel_factor = if (self.on_ground) 1.0 else config.PLAYER_AIR_CONTROL;
        self.vx = move_input * config.PLAYER_RUN_SPEED * accel_factor;

        // Jump input
        if (rl.isKeyPressed(.space) or rl.isKeyPressed(.w) or rl.isKeyPressed(.up)) {
            self.jump_requested = true;
        }
        self.jump_held = rl.isKeyDown(.space) or rl.isKeyDown(.w) or rl.isKeyDown(.up);
    }

    pub fn update(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        // Update invincibility
        if (self.invincible_timer > 0) {
            self.invincible_timer -= dt;
        }

        // Handle jump
        if (self.jump_requested and self.on_ground) {
            self.vy = -config.PLAYER_JUMP_IMPULSE;
            self.on_ground = false;
            self.state = .jumping;
        }
        self.jump_requested = false;

        // Variable jump height - cut jump short if button released early
        if (!self.jump_held and self.vy < -config.PLAYER_JUMP_IMPULSE * 0.5) {
            self.vy = -config.PLAYER_JUMP_IMPULSE * 0.5;
        }

        // Apply gravity
        self.vy += config.PLAYER_GRAVITY * dt;
        if (self.vy > config.PLAYER_MAX_FALL_SPEED) {
            self.vy = config.PLAYER_MAX_FALL_SPEED;
        }

        // Move and collide
        self.moveAndCollide(dt, tilemap);

        // Update state
        self.updateState();

        // Update animation
        self.updateAnimation(dt);

        // Check for falling off screen (death)
        if (self.y > @as(f32, @floatFromInt(config.SCREEN_HEIGHT + 50))) {
            self.die();
        }
    }

    fn moveAndCollide(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        // Horizontal movement
        const new_x = self.x + self.vx * dt;
        const half_width = config.PLAYER_WIDTH / 2;

        // Check horizontal collision
        if (!tilemap.checkCollision(new_x - half_width, self.y - config.PLAYER_HEIGHT, config.PLAYER_WIDTH, config.PLAYER_HEIGHT)) {
            self.x = new_x;
        } else {
            // Slide against wall
            self.vx = 0;
        }

        // Vertical movement
        const new_y = self.y + self.vy * dt;

        // Check vertical collision
        if (!tilemap.checkCollision(self.x - half_width, new_y - config.PLAYER_HEIGHT, config.PLAYER_WIDTH, config.PLAYER_HEIGHT)) {
            self.y = new_y;
            self.on_ground = false;
        } else {
            if (self.vy > 0) {
                // Landing on ground
                self.on_ground = true;
                // Snap to tile
                const tile_y = @as(i32, @intFromFloat(new_y / @as(f32, @floatFromInt(config.TILE_SIZE))));
                self.y = @as(f32, @floatFromInt(tile_y * config.TILE_SIZE));
            }
            self.vy = 0;
        }

        // Keep player in bounds horizontally
        if (self.x < half_width) {
            self.x = half_width;
            self.vx = 0;
        }
        if (self.x > @as(f32, @floatFromInt(config.SCREEN_WIDTH)) - half_width) {
            self.x = @as(f32, @floatFromInt(config.SCREEN_WIDTH)) - half_width;
            self.vx = 0;
        }
    }

    fn updateState(self: *Self) void {
        if (self.state == .dead) return;

        if (!self.on_ground) {
            if (self.vy < 0) {
                self.state = .jumping;
            } else {
                self.state = .falling;
            }
        } else {
            if (@abs(self.vx) > 10) {
                self.state = .running;
            } else {
                self.state = .idle;
            }
        }
    }

    fn updateAnimation(self: *Self, dt: f32) void {
        self.anim_timer += dt;

        const frame_duration: f32 = switch (self.state) {
            .running => 0.1,
            else => 0.2,
        };

        if (self.anim_timer >= frame_duration) {
            self.anim_timer = 0;
            self.anim_frame = @as(u8, @intCast((@as(u32, self.anim_frame) + 1) % 3));
        }
    }

    pub fn bounce(self: *Self) void {
        // Called when stomping an enemy - gives a small bounce
        self.vy = -config.PLAYER_JUMP_IMPULSE * config.PLAYER_BOUNCE_FACTOR;
        self.on_ground = false;
        self.state = .stomping;
    }

    pub fn addScore(self: *Self, points: i32) void {
        self.score += points;
    }

    pub fn die(self: *Self) void {
        self.lives -= 1;
        if (self.lives > 0) {
            self.respawn();
        } else {
            self.state = .dead;
        }
    }

    pub fn getRect(self: *const Self) rl.Rectangle {
        return rl.Rectangle{
            .x = self.x - config.PLAYER_WIDTH / 2,
            .y = self.y - config.PLAYER_HEIGHT,
            .width = config.PLAYER_WIDTH,
            .height = config.PLAYER_HEIGHT,
        };
    }

    pub fn render(self: *const Self) void {
        // Blinking effect when invincible
        if (self.invincible_timer > 0) {
            const blink: i32 = @as(i32, @intFromFloat(self.invincible_timer * 10)) & 1;
            if (blink == 0) return;
        }

        const rect = self.getRect();
        const center_x: i32 = @intFromFloat(rect.x + config.PLAYER_WIDTH / 2);
        const bottom_y: i32 = @intFromFloat(rect.y + config.PLAYER_HEIGHT);

        // Body colors
        const suit_color = config.PLAYER_COLOR;
        const skin_color = rl.Color{ .r = 255, .g = 220, .b = 177, .a = 255 };
        const dark_blue = rl.Color{ .r = 50, .g = 90, .b = 130, .a = 255 };

        // LEGS (3 pixels wide each, 10 tall)
        const leg_y: i32 = bottom_y - 10;
        rl.drawRectangle(center_x - 5, leg_y, 3, 10, suit_color); // Left leg
        rl.drawRectangle(center_x + 2, leg_y, 3, 10, suit_color); // Right leg

        // TORSO (10 pixels wide, 8 pixels tall)
        const torso_y: i32 = bottom_y - 18;
        rl.drawRectangle(center_x - 5, torso_y, 10, 8, suit_color);

        // Belt line
        rl.drawRectangle(center_x - 5, torso_y + 6, 10, 2, rl.Color.yellow);

        // Chest emblem - "P" for Programmer (bigger)
        rl.drawRectangle(center_x - 2, torso_y + 2, 4, 4, rl.Color.white);
        rl.drawRectangle(center_x - 1, torso_y + 2, 2, 1, suit_color); // Top of P
        rl.drawRectangle(center_x, torso_y + 4, 1, 2, suit_color); // Gap in P

        // ARMS (3 pixels wide, 6 tall)
        const arm_offset: i32 = if (self.state == .running) 2 else 0;
        const arm_y: i32 = torso_y + 2;
        rl.drawRectangle(center_x - 8, arm_y + arm_offset, 3, 6, suit_color); // Left arm
        rl.drawRectangle(center_x + 5, arm_y - arm_offset, 3, 6, suit_color); // Right arm

        // HEAD (6x6 pixel square)
        const head_y: i32 = torso_y - 6;
        rl.drawRectangle(center_x - 3, head_y, 6, 6, skin_color);

        // MASK (superhero mask across eyes)
        rl.drawRectangle(center_x - 3, head_y + 2, 6, 2, dark_blue);

        // EYES (2 white pixels each in the mask)
        const eye_left_x: i32 = if (self.facing_right) center_x - 2 else center_x - 3;
        const eye_right_x: i32 = if (self.facing_right) center_x + 1 else center_x;
        rl.drawPixel(eye_left_x, head_y + 3, rl.Color.white);
        rl.drawPixel(eye_right_x, head_y + 3, rl.Color.white);

        // HAIR on top (2 pixels tall)
        rl.drawRectangle(center_x - 3, head_y, 6, 2, rl.Color{ .r = 80, .g = 60, .b = 40, .a = 255 });
    }

    pub fn renderHUD(self: *const Self) void {
        // Score
        var score_buf: [64]u8 = undefined;
        const score_text = std.fmt.bufPrintZ(&score_buf, "SCORE: {d}", .{self.score}) catch "SCORE: ???";
        rl.drawText(score_text, 10, 10, 20, config.HUD_COLOR);

        // Lives
        var lives_buf: [64]u8 = undefined;
        const lives_text = std.fmt.bufPrintZ(&lives_buf, "LIVES: {d}", .{self.lives}) catch "LIVES: ???";
        rl.drawText(lives_text, 10, 35, 20, config.HUD_COLOR);

        // Game over message
        if (self.state == .dead) {
            rl.drawText("GAME OVER", config.SCREEN_WIDTH / 2 - 100, config.SCREEN_HEIGHT / 2 - 20, 40, rl.Color.red);
            rl.drawText("Press R to Restart", config.SCREEN_WIDTH / 2 - 90, config.SCREEN_HEIGHT / 2 + 30, 20, config.HUD_COLOR);
        }
    }
};
