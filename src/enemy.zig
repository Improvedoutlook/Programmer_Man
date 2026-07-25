//! Enemy module - Bug enemies that patrol and can be stomped.
//!
//! Two species share this module:
//!   * `.bug`    — the classic red bug. One stomp, 100 points.
//!   * `.beetle` — the green armored beetle from the title art. Two stomps
//!                 (the first only cracks its shell), 200 points, and a per
//!                 instance behaviour picked in the level JSON: patrol, a
//!                 much higher jump than a red bug, or a charge.

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");
const Tilemap = @import("tilemap.zig").Tilemap;
const AiType = @import("tilemap.zig").AiType;
const BugKind = @import("tilemap.zig").BugKind;
const Player = @import("player.zig").Player;
const audio = @import("audio.zig");

pub const BugState = enum {
    walking,
    /// Beetle only: flipped onto its back after its armor cracks. It cannot
    /// hurt the player and cannot be stomped again until it rights itself.
    stunned,
    dying,
    dead,
};

/// Phases of the charger AI. A charger patrols until the player enters its
/// sight line, rears up as a visible warning, dashes, then recovers.
pub const ChargePhase = enum {
    idle,
    telegraph,
    charging,
    cooldown,
};

/// What a single stomp did to an enemy.
pub const StompResult = enum {
    /// Armor absorbed the blow — the enemy is stunned but still alive.
    cracked,
    /// The enemy was destroyed.
    destroyed,
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
    kind: BugKind,
    jump_timer: f32,
    on_ground: bool,
    /// Remaining stomps needed to destroy this enemy.
    hp: i32,
    /// Beetle whose shell has already been broken: faster, and visibly damaged.
    armor_cracked: bool,
    stun_timer: f32,
    hit_flash_timer: f32,
    charge_phase: ChargePhase,
    charge_timer: f32,

    const Self = @This();

    pub fn init(tile_x: i32, tile_y: i32, facing_right: bool, walk_speed: f32, ai: AiType, kind: BugKind) Self {
        // Seed jump_timer with a pseudo-random offset based on spawn position
        const seed_val: f32 = @as(f32, @floatFromInt(@mod(tile_x * 7 + tile_y * 13, 100))) / 100.0;
        const interval_min = jumpIntervalMin(kind);
        const interval_max = jumpIntervalMax(kind);
        const initial_jump_timer = interval_min + seed_val * (interval_max - interval_min);
        return Self{
            .x = @as(f32, @floatFromInt(tile_x * config.TILE_SIZE)) + bugWidth(kind) / 2,
            // Feet rest on the bottom edge of the spawn tile regardless of how
            // tall the species is — a beetle is taller than a red bug.
            .y = @as(f32, @floatFromInt((tile_y + 1) * config.TILE_SIZE)),
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
            .kind = kind,
            .jump_timer = initial_jump_timer,
            .on_ground = true,
            .hp = switch (kind) {
                .bug => 1,
                .beetle => config.BEETLE_HITS_TO_KILL,
            },
            .armor_cracked = false,
            .stun_timer = 0,
            .hit_flash_timer = 0,
            .charge_phase = .idle,
            .charge_timer = 0,
        };
    }

    // ------------------------------------------------------------------
    // Per-species constants
    // ------------------------------------------------------------------

    fn bugWidth(kind: BugKind) f32 {
        return switch (kind) {
            .bug => config.BUG_WIDTH,
            .beetle => config.BEETLE_WIDTH,
        };
    }

    fn bugHeight(kind: BugKind) f32 {
        return switch (kind) {
            .bug => config.BUG_HEIGHT,
            .beetle => config.BEETLE_HEIGHT,
        };
    }

    fn jumpIntervalMin(kind: BugKind) f32 {
        return switch (kind) {
            .bug => config.JUMPER_INTERVAL_MIN,
            .beetle => config.BEETLE_JUMP_INTERVAL_MIN,
        };
    }

    fn jumpIntervalMax(kind: BugKind) f32 {
        return switch (kind) {
            .bug => config.JUMPER_INTERVAL_MAX,
            .beetle => config.BEETLE_JUMP_INTERVAL_MAX,
        };
    }

    fn jumpVelocity(self: *const Self) f32 {
        return switch (self.kind) {
            .bug => config.JUMPER_JUMP_VELOCITY,
            .beetle => config.BEETLE_JUMP_VELOCITY,
        };
    }

    pub fn width(self: *const Self) f32 {
        return bugWidth(self.kind);
    }

    pub fn height(self: *const Self) f32 {
        return bugHeight(self.kind);
    }

    /// Score awarded for destroying this enemy (before any power-stomp bonus).
    pub fn pointValue(self: *const Self) i32 {
        return switch (self.kind) {
            .bug => config.POINTS_PER_STOMP,
            .beetle => config.POINTS_PER_BEETLE,
        };
    }

    /// Patrol speed for this frame. A beetle that has already lost its shell
    /// stops lumbering and moves noticeably faster.
    fn patrolSpeed(self: *const Self) f32 {
        if (self.armor_cracked) return self.walk_speed * config.BEETLE_CRACKED_SPEED_MULT;
        return self.walk_speed;
    }

    fn setSpeed(self: *Self, speed: f32) void {
        self.vx = if (self.facing_right) speed else -speed;
    }

    fn turnAround(self: *Self) void {
        self.facing_right = !self.facing_right;
        self.vx = -self.vx;
    }

    // ------------------------------------------------------------------
    // Update
    // ------------------------------------------------------------------

    pub fn update(self: *Self, dt: f32, tilemap: *const Tilemap, player_x: f32, player_y: f32) void {
        if (!self.active) return;

        if (self.hit_flash_timer > 0) self.hit_flash_timer -= dt;

        switch (self.state) {
            .walking => self.updateWalking(dt, tilemap, player_x, player_y),
            .stunned => self.updateStunned(dt, tilemap),
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

    /// Gravity, falling, and landing. Shared by the walking and stunned states
    /// so a beetle knocked onto its back mid-air still drops to the floor.
    fn applyGravity(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        self.vy += config.PLAYER_GRAVITY * dt;
        if (self.vy > config.PLAYER_MAX_FALL_SPEED) self.vy = config.PLAYER_MAX_FALL_SPEED;

        const new_y = self.y + self.vy * dt;
        const half_width = self.width() / 2;
        const ground_hit = tilemap.checkCollision(
            self.x - half_width,
            new_y,
            self.width(),
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
    }

    fn updateWalking(self: *Self, dt: f32, tilemap: *const Tilemap, player_x: f32, player_y: f32) void {
        self.applyGravity(dt, tilemap);

        switch (self.ai) {
            // Jumper AI: attempt an intermittent jump when on ground
            .jumper => {
                self.setSpeed(self.patrolSpeed());
                self.attemptJump(dt, tilemap);
            },
            // Charger AI owns vx while winding up and dashing.
            .charger => self.updateCharge(dt, player_x, player_y),
            .walker => self.setSpeed(self.patrolSpeed()),
        }

        // Horizontal movement
        const new_x = self.x + self.vx * dt;
        const half_width = self.width() / 2;

        // Check for wall collision at new position
        const hit_wall = tilemap.checkCollision(
            new_x - half_width,
            self.y - self.height() + 2,
            self.width(),
            self.height() - 4,
        );

        // Check for edge (no ground ahead) - look further ahead. Use the facing
        // direction rather than the sign of vx: a charger stands still while it
        // rears up, and a zero vx must not be read as "looking left".
        const edge_check_dist: f32 = half_width + 4;
        const check_x = if (self.facing_right) new_x + edge_check_dist else new_x - edge_check_dist;
        const has_ground_ahead = tilemap.checkCollision(check_x, self.y + 2, 2, 2);

        // Prevent walking off the level bounds
        const level_pixel_w: f32 = tilemap.getLevelPixelWidth();
        const would_leave_left = (new_x - half_width) < 0.0;
        const would_leave_right = (new_x + half_width) > level_pixel_w;

        // Only check edge if on ground (airborne jumpers should keep moving).
        // A stationary enemy cannot walk into anything, so it never turns.
        const should_turn = self.vx != 0 and
            (hit_wall or (self.on_ground and !has_ground_ahead) or would_leave_left or would_leave_right);

        if (should_turn) {
            // A charge that runs into a wall or a ledge ends there — the beetle
            // slams to a stop and has to wind up again.
            if (self.charge_phase == .charging) self.endCharge();
            self.turnAround();
        } else {
            // Move to new position
            self.x = new_x;
        }
    }

    /// Beetle on its back: it slides to a halt, then rights itself and resumes
    /// patrolling — faster now that its shell is gone.
    fn updateStunned(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        self.applyGravity(dt, tilemap);
        self.vx = 0;

        self.stun_timer -= dt;
        if (self.stun_timer <= 0) {
            self.state = .walking;
            if (self.ai == .charger) {
                // Give the player a moment to escape before it can wind up again.
                self.charge_phase = .cooldown;
                self.charge_timer = config.CHARGE_COOLDOWN;
            }
            self.setSpeed(self.patrolSpeed());
        }
    }

    fn updateDying(self: *Self, dt: f32) void {
        self.death_timer += dt;
        if (self.death_timer >= 0.3) {
            self.state = .dead;
            self.active = false;
        }
    }

    // ------------------------------------------------------------------
    // Charger AI
    // ------------------------------------------------------------------

    /// True when the player is close enough, on roughly the same floor, and in
    /// front of this enemy. No wall raycast — the range is short enough that a
    /// false positive through a thin wall reads as the beetle hearing you.
    fn playerInSights(self: *const Self, player_x: f32, player_y: f32) bool {
        const dx = player_x - self.x;
        if (@abs(dx) > config.CHARGE_DETECT_RANGE) return false;
        // Both y values are feet positions, so this keeps the check to enemies
        // and players standing on the same platform.
        if (@abs(player_y - self.y) > config.CHARGE_DETECT_VERTICAL) return false;
        return if (self.facing_right) dx > 0 else dx < 0;
    }

    fn playerBehind(self: *const Self, player_x: f32, player_y: f32) bool {
        const dx = player_x - self.x;
        if (@abs(dx) > config.CHARGE_DETECT_RANGE) return false;
        if (@abs(player_y - self.y) > config.CHARGE_DETECT_VERTICAL) return false;
        return if (self.facing_right) dx < 0 else dx > 0;
    }

    fn updateCharge(self: *Self, dt: f32, player_x: f32, player_y: f32) void {
        switch (self.charge_phase) {
            .idle => {
                self.setSpeed(self.patrolSpeed());
                if (!self.on_ground) return;
                if (self.playerInSights(player_x, player_y)) {
                    // Rear up in place — the player's window to get clear.
                    self.charge_phase = .telegraph;
                    self.charge_timer = config.CHARGE_TELEGRAPH_TIME;
                    self.vx = 0;
                } else if (self.playerBehind(player_x, player_y)) {
                    // Heard something behind it: spin round to look.
                    self.turnAround();
                }
            },
            .telegraph => {
                self.vx = 0;
                self.charge_timer -= dt;
                if (self.charge_timer <= 0) {
                    self.charge_phase = .charging;
                    self.charge_timer = config.CHARGE_DURATION;
                    self.setSpeed(self.patrolSpeed() * config.CHARGE_SPEED_MULT);
                }
            },
            .charging => {
                self.setSpeed(self.patrolSpeed() * config.CHARGE_SPEED_MULT);
                self.charge_timer -= dt;
                if (self.charge_timer <= 0) self.endCharge();
            },
            .cooldown => {
                self.setSpeed(self.patrolSpeed());
                self.charge_timer -= dt;
                if (self.charge_timer <= 0) self.charge_phase = .idle;
            },
        }
    }

    fn endCharge(self: *Self) void {
        self.charge_phase = .cooldown;
        self.charge_timer = config.CHARGE_COOLDOWN;
        self.setSpeed(self.patrolSpeed());
    }

    fn attemptJump(self: *Self, dt: f32, tilemap: *const Tilemap) void {
        self.jump_timer -= dt;
        if (self.on_ground and self.jump_timer <= 0) {
            // Predict landing X using a simple ballistic estimate and disallow jumps
            // that would land outside the level or in a column with no solid tiles.
            const g: f32 = config.PLAYER_GRAVITY;
            const vy0: f32 = self.jumpVelocity(); // negative (upwards)
            const total_air_time: f32 = (-2.0 * vy0) / g; // approximate time in air
            const predicted_x: f32 = self.x + self.vx * total_air_time;

            const tile_x: i32 = @intFromFloat(@floor(predicted_x / @as(f32, @floatFromInt(config.TILE_SIZE))));

            const interval_min = jumpIntervalMin(self.kind);
            const interval_max = jumpIntervalMax(self.kind);

            // If landing column is outside level bounds, abort jump and turn around
            if (tile_x < 0 or tile_x >= tilemap.level_width) {
                self.turnAround();
                self.jump_timer = interval_min;
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
                self.turnAround();
                self.jump_timer = interval_min;
                return;
            }

            // Safe to jump
            self.vy = vy0;
            self.on_ground = false;

            // Reset timer using a simple deterministic pseudo-random based on position
            const px: i32 = @intFromFloat(self.x);
            const py: i32 = @intFromFloat(self.y);
            const hash: f32 = @as(f32, @floatFromInt(@mod(px * 31 + py * 17, 100))) / 100.0;
            self.jump_timer = interval_min + hash * (interval_max - interval_min);
        }
    }

    fn updateAnimation(self: *Self, dt: f32) void {
        self.anim_timer += dt;
        const frame_duration: f32 = switch (self.state) {
            // Legs scrabble faster during a dash and while flipped over.
            .walking => if (self.charge_phase == .charging) 0.06 else 0.15,
            .stunned => 0.08,
            else => 0.05,
        };

        if (self.anim_timer >= frame_duration) {
            self.anim_timer = 0;
            self.anim_frame = (self.anim_frame + 1) % 2;
        }
    }

    /// Apply one stomp of damage. `power` marks a high-speed power stomp, which
    /// shatters beetle armor outright instead of merely cracking it, and skips
    /// the normal squish SFX because the caller plays its own stronger POW.
    ///
    /// Returns whether the enemy died or only lost its shell.
    pub fn stomp(self: *Self, power: bool) StompResult {
        // A power stomp always finishes the job, however much armor is left.
        self.hp -= if (power) self.hp else 1;

        if (self.hp > 0) {
            // Shell cracked: the beetle flips onto its back, helpless for a
            // moment, then rights itself and comes back faster.
            self.state = .stunned;
            self.stun_timer = config.BEETLE_STUN_DURATION;
            self.hit_flash_timer = config.BEETLE_HIT_FLASH_TIME;
            self.armor_cracked = true;
            self.charge_phase = .idle;
            self.charge_timer = 0;
            self.vx = 0;
            audio.playSfx(.Stomp, config.SFX_VOLUME);
            return .cracked;
        }

        self.state = .dying;
        self.death_timer = 0;
        self.vx = 0;
        self.vy = 0;
        if (!power) {
            // Play stomp sound effect (bug squish)
            audio.playSfx(.Stomp, config.SFX_VOLUME);
        }
        return .destroyed;
    }

    pub fn getRect(self: *const Self) rl.Rectangle {
        return rl.Rectangle{
            .x = self.x - self.width() / 2,
            .y = self.y - self.height(),
            .width = self.width(),
            .height = self.height(),
        };
    }

    pub fn render(self: *const Self) void {
        if (!self.active) return;

        switch (self.kind) {
            .bug => self.renderBug(),
            .beetle => self.renderBeetle(),
        }
    }

    fn renderBug(self: *const Self) void {
        const rect = self.getRect();

        // Color varies based on state
        const color: rl.Color = switch (self.state) {
            .walking, .stunned => config.BUG_COLOR,
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

    /// The green beetle: a domed carapace with a rhino horn, split elytra, and
    /// damage state written straight onto the shell so the player can always
    /// tell at a glance how many stomps are left.
    fn renderBeetle(self: *const Self) void {
        const rect = self.getRect();

        if (self.state == .dying) {
            // Squashed shell — flatter and wider than a red bug's.
            const squash = rl.Color{ .r = 170, .g = 230, .b = 150, .a = 255 };
            rl.drawRectangle(
                @intFromFloat(rect.x - 3),
                @intFromFloat(rect.y + rect.height - 7),
                @intFromFloat(rect.width + 6),
                7,
                squash,
            );
            return;
        }

        // A rearing charger shudders in place; the shake is the tell that a dash
        // is coming, so it has to be visible without being subtle-only.
        const shake: f32 = if (self.charge_phase == .telegraph and self.anim_frame == 1) 1.0 else 0.0;
        const cx: f32 = self.x + shake;
        const cy: f32 = self.y - self.height() / 2;

        var body = if (self.armor_cracked) config.BEETLE_CRACKED_COLOR else config.BEETLE_COLOR;
        var shell = if (self.armor_cracked) config.BEETLE_CRACKED_COLOR else config.BEETLE_SHELL_COLOR;
        if (self.hit_flash_timer > 0) {
            body = rl.Color.white;
            shell = rl.Color.white;
        }

        const dir: f32 = if (self.facing_right) 1.0 else -1.0;

        // Speed streaks trailing a dashing beetle.
        if (self.charge_phase == .charging) {
            const trail = rl.Color{ .r = 200, .g = 255, .b = 190, .a = 140 };
            var i: i32 = 0;
            while (i < 3) : (i += 1) {
                const off: f32 = @floatFromInt(6 + i * 5);
                const ty: i32 = @intFromFloat(cy - 4 + @as(f32, @floatFromInt(i * 5)));
                rl.drawLine(
                    @intFromFloat(cx - dir * off),
                    ty,
                    @intFromFloat(cx - dir * (off + 6)),
                    ty,
                    trail,
                );
            }
        }

        if (self.state == .stunned) {
            // Flipped onto its back: flattened dome, pale underside, legs waving
            // in the air. Reads instantly as "wait, it isn't dead yet".
            const belly = rl.Color{ .r = 190, .g = 220, .b = 150, .a = 255 };
            rl.drawEllipse(
                @intFromFloat(self.x),
                @intFromFloat(self.y - 4),
                self.width() / 2,
                4,
                body,
            );
            rl.drawEllipse(
                @intFromFloat(self.x),
                @intFromFloat(self.y - 5),
                self.width() / 2 - 4,
                3,
                belly,
            );
            const wave: i32 = if (self.anim_frame == 0) -3 else -6;
            const lx: i32 = @intFromFloat(rect.x + 3);
            const rx: i32 = @intFromFloat(rect.x + rect.width - 3);
            const ly: i32 = @intFromFloat(self.y - 8);
            rl.drawLine(lx, ly, lx - 3, ly + wave, body);
            rl.drawLine(lx + 4, ly, lx + 2, ly + wave - 2, body);
            rl.drawLine(rx, ly, rx + 3, ly + wave, body);
            rl.drawLine(rx - 4, ly, rx - 2, ly + wave - 2, body);
            return;
        }

        // Legs (animated) — drawn behind the shell.
        const leg_offset: i32 = if (self.anim_frame == 0) 0 else 2;
        const base_x: i32 = @intFromFloat(rect.x + shake);
        const base_y: i32 = @intFromFloat(rect.y + rect.height - 4);
        const w: i32 = @intFromFloat(rect.width);
        rl.drawLine(base_x + 3, base_y - leg_offset, base_x, base_y + 3, body);
        rl.drawLine(base_x + 7, base_y + leg_offset, base_x + 4, base_y + 3, body);
        rl.drawLine(base_x + w - 3, base_y - leg_offset, base_x + w, base_y + 3, body);
        rl.drawLine(base_x + w - 7, base_y + leg_offset, base_x + w - 4, base_y + 3, body);

        // Carapace: a dark dome with a brighter elytra plate on top.
        rl.drawEllipse(
            @intFromFloat(cx),
            @intFromFloat(cy + 1),
            self.width() / 2,
            self.height() / 2 - 1,
            body,
        );
        rl.drawEllipse(
            @intFromFloat(cx),
            @intFromFloat(cy),
            self.width() / 2 - 2,
            self.height() / 2 - 4,
            shell,
        );

        // Elytra split down the middle of the back.
        rl.drawLine(
            @intFromFloat(cx),
            @intFromFloat(cy - self.height() / 2 + 4),
            @intFromFloat(cx),
            @intFromFloat(cy + self.height() / 2 - 2),
            body,
        );

        // Cracks appear once the armor is broken — the "one stomp left" tell.
        if (self.armor_cracked) {
            const crack = rl.Color{ .r = 40, .g = 60, .b = 30, .a = 255 };
            const jx: i32 = @intFromFloat(cx);
            const jy: i32 = @intFromFloat(cy);
            rl.drawLine(jx - 6, jy - 4, jx - 2, jy, crack);
            rl.drawLine(jx - 2, jy, jx - 5, jy + 3, crack);
            rl.drawLine(jx + 2, jy - 5, jx + 5, jy - 1, crack);
            rl.drawLine(jx + 5, jy - 1, jx + 3, jy + 4, crack);
        }

        // Rhino horn, sweeping forward from the head.
        const head_x: f32 = cx + dir * (self.width() / 2 - 3);
        const horn_tip_x: f32 = cx + dir * (self.width() / 2 + 5);
        const horn_y: f32 = cy - self.height() / 2 + 3;
        rl.drawLine(
            @intFromFloat(head_x),
            @intFromFloat(horn_y + 3),
            @intFromFloat(horn_tip_x),
            @intFromFloat(horn_y - 3),
            shell,
        );
        rl.drawLine(
            @intFromFloat(head_x),
            @intFromFloat(horn_y + 4),
            @intFromFloat(horn_tip_x),
            @intFromFloat(horn_y - 2),
            body,
        );

        // Eyes — red while it is winding up to charge, so the tell is unmissable.
        const eye_color = if (self.charge_phase == .telegraph or self.charge_phase == .charging)
            rl.Color{ .r = 255, .g = 70, .b = 70, .a = 255 }
        else
            rl.Color.white;
        const eye_y: i32 = @intFromFloat(cy - 3);
        rl.drawCircle(@intFromFloat(cx + dir * 3), eye_y, 2, eye_color);
        rl.drawCircle(@intFromFloat(cx + dir * 7), eye_y, 2, eye_color);
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

    pub fn spawn(self: *Self, tile_x: i32, tile_y: i32, facing_right: bool, walk_speed: f32, ai: AiType, kind: BugKind) void {
        if (self.count >= config.MAX_BUGS) return;

        self.bugs[self.count] = Bug.init(tile_x, tile_y, facing_right, walk_speed, ai, kind);
        self.count += 1;
    }

    pub fn update(self: *Self, dt: f32, tilemap: *const Tilemap, player_x: f32, player_y: f32) void {
        for (0..self.count) |i| {
            self.bugs[i].update(dt, tilemap, player_x, player_y);
        }
    }

    /// Resolve player/bug overlaps for this frame. Returns true if the player
    /// pulled off a *power stomp* (smashing a bug while falling fast, e.g. from a
    /// big jump off a high platform) so the caller can trigger a screen shake.
    pub fn checkPlayerCollision(self: *Self, player: *Player, dt: f32) bool {
        if (player.invincible_timer > 0) return false;

        var power_stomped = false;
        var any_stomp = false;
        var took_damage = false;
        const player_rect = player.getRect();

        // Snapshot the fall velocity and foot position once, before resolving any
        // bug. player.bounce() flips vy upward, so if we read player.vy inside the
        // loop, a second bug clustered at the same spot would see the post-bounce
        // (upward) velocity and misread the stomp as a side hit — squashing one bug
        // but taking damage from its neighbour. Deciding every bug against the
        // start-of-frame descent keeps a multi-bug stomp a clean multi-stomp.
        const fall_vy = player.vy;
        const player_bottom = player_rect.y + player_rect.height;
        // Swept check: at high fall speeds the player can move further than the
        // stomp window in a single frame, tunnelling past the bug's top so a stomp
        // reads as a side hit. Reconstruct the previous foot position and treat it
        // as a stomp if the feet were above the bug before this frame's descent,
        // not only if they land in the window.
        const prev_bottom = player_bottom - fall_vy * dt;

        for (0..self.count) |i| {
            var bug = &self.bugs[i];
            // A stunned beetle is inert: it cannot be re-stomped while on its
            // back and it cannot hurt the player either.
            if (!bug.active or bug.state != .walking) continue;

            const bug_rect = bug.getRect();
            if (!rl.checkCollisionRecs(player_rect, bug_rect)) continue;

            // Check if player is stomping (falling and hitting from above).
            const bug_top = bug_rect.y;
            const is_stomping = fall_vy > 0 and
                (player_bottom <= bug_top + 8 or prev_bottom <= bug_top + 8);

            if (is_stomping) {
                // A power stomp lands at high fall speed — the reward for a
                // well-timed big jump. It plays a stronger POW, awards double
                // points, shatters beetle armor in one blow, and signals the
                // caller to shake the screen.
                const is_power = fall_vy >= config.POWER_STOMP_MIN_FALL_SPEED;

                if (is_power) {
                    audio.playPowStomp(config.POWER_STOMP_VOLUME);
                } else {
                    // Normal stomp: play pounce sound (impact before bounce).
                    audio.playSfx(.Pounce, config.SFX_VOLUME * 0.8);
                }

                switch (bug.stomp(is_power)) {
                    .destroyed => {
                        const points = bug.pointValue() *
                            @as(i32, if (is_power) config.POWER_STOMP_MULTIPLIER else 1);
                        player.addScore(points);
                        if (is_power) power_stomped = true;
                    },
                    // Cracking a shell scores nothing — the points ride on
                    // finishing the beetle off.
                    .cracked => {},
                }
                any_stomp = true;
            } else {
                took_damage = true;
            }
        }

        // Apply the frame's outcome once, after every overlapping bug is resolved.
        // A single bounce covers a multi-bug stomp, and landing on top of any bug
        // this frame shields the player from a same-frame side hit by another bug
        // clustered at the same spot — you get every kill instead of a stray point
        // of damage.
        if (any_stomp) {
            player.bounce();
        } else if (took_damage) {
            player.takeDamage();
        }

        return power_stomped;
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
