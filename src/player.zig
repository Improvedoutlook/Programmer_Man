//! Player module - Handles Programmer_Man character physics, movement, and rendering

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const Tilemap = @import("tilemap.zig").Tilemap;
const audio = @import("audio.zig");

const FRAME_W: f32 = 83.0; // 500px sheet / 6 columns
const FRAME_H: f32 = 100.0; // content height per frame row

// Per-row Y origins in the sprite sheet.
// The sheet has text labels ("FACING RIGHT/LEFT") between rows 0 and 1,
// so we use explicit offsets to skip that band cleanly.
const ROW_Y = [4]f32{ 15.0, 143.0, 260.0, 383.0 };

fn getSpriteRect(state: PlayerState, anim_frame: u8) rl.Rectangle {
    // Map animation index to actual sprite-sheet column.
    // Running frames 0-3 map to sheet columns 2-5 (the side-profile frames).
    const col: f32 = @floatFromInt(switch (state) {
        .running => anim_frame + 2,
        else => anim_frame,
    });
    const row: u8 = switch (state) {
        .idle => 0,
        .running => 3, // side-profile run row
        .jumping => 1,
        .falling => 1,
        .stomping => 1,
        .dead => 0,
    };
    return rl.Rectangle{
        .x = col * FRAME_W,
        .y = ROW_Y[row],
        .width = FRAME_W,
        .height = FRAME_H,
    };
}

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
    coyote_timer: f32, // NEW: Allows jumping shortly after leaving platform
    jump_buffer_timer: f32, // NEW: Remembers jump press before landing

    // Animation
    anim_frame: u8,
    anim_timer: f32,

    // Stats
    lives: i32,
    score: i32,
    health: i32,
    invincible_timer: f32,

    const Self = @This();

    pub fn init() Self {
        return Self{
            // Position player with center at spawn tile X, feet on top of spawn tile Y
            .x = @as(f32, @floatFromInt(config.SPAWN_TILE_X * config.TILE_SIZE)) + config.PLAYER_WIDTH / 2,
            .y = @as(f32, @floatFromInt(config.SPAWN_TILE_Y * config.TILE_SIZE)), // Feet at top of ground tile
            .vx = 0,
            .vy = 0,
            .state = .idle,
            .facing_right = true,
            .on_ground = false,
            .jump_requested = false,
            .jump_held = false,
            .coyote_timer = 0,
            .jump_buffer_timer = 0,
            .anim_frame = 0,
            .anim_timer = 0,
            .lives = config.INITIAL_LIVES,
            .score = 0,
            .health = 3,
            .invincible_timer = 0,
        };
    }

    pub fn respawn(self: *Self) void {
        // Position player with center at spawn tile X, feet on top of spawn tile Y
        self.x = @as(f32, @floatFromInt(config.SPAWN_TILE_X * config.TILE_SIZE)) + config.PLAYER_WIDTH / 2;
        self.y = @as(f32, @floatFromInt(config.SPAWN_TILE_Y * config.TILE_SIZE)); // Feet at top of ground tile
        self.vx = 0;
        self.vy = 0;
        self.state = .idle;
        self.on_ground = false;
        self.coyote_timer = 0;
        self.jump_buffer_timer = 0;
        self.health = 3;
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

        // Jump input - set buffer timer when jump is pressed
        if (rl.isKeyPressed(.space) or rl.isKeyPressed(.w) or rl.isKeyPressed(.up)) {
            self.jump_buffer_timer = 0.15; // Remember jump press for 0.15 seconds
        }
        self.jump_held = rl.isKeyDown(.space) or rl.isKeyDown(.w) or rl.isKeyDown(.up);
    }

    pub fn update(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        // Update invincibility
        if (self.invincible_timer > 0) {
            self.invincible_timer -= dt;
        }

        // Update timers
        if (self.jump_buffer_timer > 0) {
            self.jump_buffer_timer -= dt;
        }
        if (self.coyote_timer > 0) {
            self.coyote_timer -= dt;
        }

        // Handle jump with coyote time and input buffering
        const can_jump = self.on_ground or self.coyote_timer > 0;
        if (self.jump_buffer_timer > 0 and can_jump) {
            self.vy = -config.PLAYER_JUMP_IMPULSE;
            self.on_ground = false;
            self.state = .jumping;
            self.jump_buffer_timer = 0; // Consume the buffered jump
            self.coyote_timer = 0; // Consume coyote time
        }

        // Variable jump height - cut jump short if button released early
        if (!self.jump_held and self.vy < -config.PLAYER_JUMP_IMPULSE * 0.5) {
            self.vy = -config.PLAYER_JUMP_IMPULSE * 0.5;
        }

        // Apply gravity
        self.vy += config.PLAYER_GRAVITY * dt;

        // Clamp fall speed
        if (self.vy > config.PLAYER_MAX_FALL_SPEED) {
            self.vy = config.PLAYER_MAX_FALL_SPEED;
        }

        // Move and collide
        self.moveAndCollide(dt, tilemap);

        // Update state
        self.updateState();

        // Update animation
        self.updateAnimation(dt);

        // Check for falling off level bottom (death)
        if (self.y > tilemap.getLevelPixelHeight() + 50) {
            self.health = 0; // Instant death when falling off screen
            self.takeDamage();
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

        // Store previous ground state
        const was_on_ground = self.on_ground;

        // Vertical movement
        const new_y = self.y + self.vy * dt;

        // Check vertical collision - check slightly below player to detect ground properly
        const ground_check_y = new_y + 1; // Check 1 pixel below feet
        if (!tilemap.checkCollision(self.x - half_width, ground_check_y - config.PLAYER_HEIGHT, config.PLAYER_WIDTH, config.PLAYER_HEIGHT)) {
            self.y = new_y;
            self.on_ground = false;

            // Start coyote timer when walking off platform
            if (was_on_ground and !self.on_ground and self.vy >= 0) {
                self.coyote_timer = 0.1;
            }
        } else {
            if (self.vy > 0) {
                // Landing on ground - snap to tile grid
                const tile_y = @as(i32, @intFromFloat((ground_check_y) / @as(f32, @floatFromInt(config.TILE_SIZE))));
                self.y = @as(f32, @floatFromInt(tile_y * config.TILE_SIZE));
                self.on_ground = true;
            } else if (self.vy < 0) {
                // Hit ceiling
                self.vy = 0;
            }

            if (self.on_ground) {
                self.vy = 0;
            }
        }

        // Keep player in bounds horizontally (use level dimensions, not screen)
        if (self.x < half_width) {
            self.x = half_width;
            self.vx = 0;
        }
        const level_pixel_w = tilemap.getLevelPixelWidth();
        if (self.x > level_pixel_w - half_width) {
            self.x = level_pixel_w - half_width;
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
            .running => 0.15,
            else => 0.2,
        };

        // How many frames does this animation have?
        const frame_count: u32 = switch (self.state) {
            .running => 4, // side-profile frames (cols 2-5, remapped in getSpriteRect)
            else => 1, // idle/jump/fall: single static frame
        };

        // Clamp frame index after a state change (e.g. running→idle)
        if (self.anim_frame >= frame_count) {
            self.anim_frame = 0;
            self.anim_timer = 0;
        }

        if (self.anim_timer >= frame_duration) {
            self.anim_timer = 0;
            self.anim_frame = @intCast((@as(u32, self.anim_frame) + 1) % frame_count);
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

    pub fn takeDamage(self: *Self) void {
        // Take damage only if not invincible
        if (self.invincible_timer > 0) return;

        self.health -= 1;

        if (self.health <= 0) {
            // Out of health, lose a life
            // For development: infinite lives (comment out when ready)
            // self.lives -= 1;

            if (self.lives > 0) {
                self.respawn();
            } else {
                self.state = .dead;
            }
        } else {
            // Still have health, just give invincibility frames
            self.invincible_timer = 1.5; // 1.5 seconds of invincibility after taking damage
        }
    }

    // Keep addHealth for power-ups later
    pub fn addHealth(self: *Self) void {
        if (self.health < 3) {
            self.health += 1;
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

    pub fn render(self: *const Self, texture: rl.Texture2D) void {
        // Blinking effect when invincible
        if (self.invincible_timer > 0) {
            const blink: i32 = @as(i32, @intFromFloat(self.invincible_timer * 10)) & 1;
            if (blink == 0) return;
        }

        const rect = self.getRect();
        var src = getSpriteRect(self.state, self.anim_frame);

        // Negative width flips the sprite horizontally — standard Raylib technique
        if (!self.facing_right) {
            src.width = -src.width;
        }

        rl.drawTexturePro(
            texture,
            src, // which part of the sheet to draw
            rect, // where on screen to draw it
            .{ .x = 0, .y = 0 }, // origin point (top-left, no rotation)
            0.0, // rotation
            rl.Color.white, // white tint = draw texture as-is
        );
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

        // Health bar with git status theme
        const health_x: i32 = 10;
        const health_y: i32 = 60;

        const health_status = switch (self.health) {
            3 => "git status: ✓✓✓ All tests passing",
            2 => "git status: ✓✓⚠ Some failures",
            1 => "git status: ✓⚠⚠ Critical bugs",
            else => "git status: ✗✗✗ Build failed",
        };

        const health_color = switch (self.health) {
            3 => rl.Color.green,
            2 => rl.Color.yellow,
            1 => rl.Color.orange,
            else => rl.Color.red,
        };

        rl.drawText(health_status, health_x, health_y, 18, health_color);

        // Game over message
        if (self.state == .dead) {
            rl.drawText("GAME OVER", config.SCREEN_WIDTH / 2 - 100, config.SCREEN_HEIGHT / 2 - 20, 40, rl.Color.red);
            rl.drawText("Press R to Restart", config.SCREEN_WIDTH / 2 - 90, config.SCREEN_HEIGHT / 2 + 30, 20, config.HUD_COLOR);
        }
    }
};
