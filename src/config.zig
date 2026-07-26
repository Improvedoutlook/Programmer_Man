//! Game configuration constants for Programmer_Man

const rl = @import("raylib");

// Internal game resolution (fixed for consistent gameplay)
pub const GAME_WIDTH: i32 = 800;
pub const GAME_HEIGHT: i32 = 600;

// Window settings (can be resized)
pub const INITIAL_WINDOW_WIDTH: i32 = 800;
pub const INITIAL_WINDOW_HEIGHT: i32 = 600;
pub const MIN_WINDOW_WIDTH: i32 = 400;
pub const MIN_WINDOW_HEIGHT: i32 = 300;
pub const WINDOW_RESIZABLE: bool = true;

// For backward compatibility, keep SCREEN_WIDTH/HEIGHT pointing to game resolution
pub const SCREEN_WIDTH: i32 = GAME_WIDTH;
pub const SCREEN_HEIGHT: i32 = GAME_HEIGHT;

// Tile dimensions
pub const TILE_SIZE: i32 = 16;
pub const TILES_X: i32 = GAME_WIDTH / TILE_SIZE; // 50 tiles (visible on screen)
pub const TILES_Y: i32 = GAME_HEIGHT / TILE_SIZE; // 37 tiles (visible on screen)

// Player dimensions and physics
pub const PLAYER_WIDTH: f32 = 24; // Was 14
pub const PLAYER_HEIGHT: f32 = 36; // Was 16
pub const PLAYER_WALK_SPEED: f32 = 200.0; // pixels/second — default pace
pub const PLAYER_GRAVITY: f32 = 1200.0; // pixels/second²
pub const PLAYER_JUMP_IMPULSE: f32 = 450.0; // pixels/second
pub const PLAYER_MAX_FALL_SPEED: f32 = 900.0; // pixels/second
pub const PLAYER_AIR_CONTROL: f32 = 0.6; // 60% of ground acceleration
pub const PLAYER_BOUNCE_FACTOR: f32 = 0.6; // 60% of jump impulse on stomp
pub const GAMEPAD_AXIS_DEADZONE: f32 = 0.25;
pub const MAX_GAMEPADS: i32 = 4;

// Run modifier — hold the run button (Shift / X / Square) with a direction.
// Walk speed is deliberately the old PLAYER_RUN_SPEED value, so every jump the
// existing levels were tuned around still clears exactly as it always did;
// running is purely additive on top.
pub const PLAYER_RUN_SPEED: f32 = 330.0; // pixels/second — 1.65x a walk
// Taller jump when taking off at a run. Apex height goes as the square of the
// impulse, so 1.12x of 450 lifts the apex from ~84px to ~106px — a touch over
// one extra tile, enough to feel earned without trivialising a climb.
pub const PLAYER_RUN_JUMP_MULTIPLIER: f32 = 1.12;
pub const PLAYER_WALK_FRAME_TIME: f32 = 0.16; // seconds per walk-cycle frame
pub const PLAYER_RUN_FRAME_TIME: f32 = 0.10; // faster legs to match the faster body

// Enemy (Bug) parameters
pub const BUG_WIDTH: f32 = 16;
pub const BUG_HEIGHT: f32 = 16;
pub const BUG_WALK_SPEED: f32 = 80.0; // pixels/second (increased for visibility)
pub const MAX_BUGS: usize = 48;

// Beetle (green armored bug) — the tougher cousin of the red bug, inspired by
// the green rhino beetle on the title art. It takes two stomps: the first only
// cracks its shell, flipping it onto its back before it rights itself and comes
// back faster and angrier.
pub const BEETLE_WIDTH: f32 = 20;
pub const BEETLE_HEIGHT: f32 = 18;
pub const BEETLE_WALK_SPEED: f32 = 55.0; // slower patrol than a red bug — it's heavy
pub const BEETLE_HITS_TO_KILL: i32 = 2;
pub const BEETLE_CRACKED_SPEED_MULT: f32 = 1.7; // speed-up once the shell is cracked
pub const BEETLE_STUN_DURATION: f32 = 0.7; // seconds on its back after the first stomp
pub const BEETLE_HIT_FLASH_TIME: f32 = 0.25; // white flash on an armor hit

// Beetles jump noticeably higher and more often than red-bug jumpers.
pub const BEETLE_JUMP_VELOCITY: f32 = -400.0; // vs JUMPER_JUMP_VELOCITY (-250)
pub const BEETLE_JUMP_INTERVAL_MIN: f32 = 0.8;
pub const BEETLE_JUMP_INTERVAL_MAX: f32 = 2.0;

// Charger AI — the beetle's third behaviour. It patrols slowly until the player
// steps into its sight line on the same floor, rears up as a telegraph, then
// dashes. Slamming into a wall or a ledge ends the dash early.
pub const CHARGE_DETECT_RANGE: f32 = 176.0; // pixels ahead (11 tiles)
pub const CHARGE_DETECT_VERTICAL: f32 = 20.0; // feet must be within this many px
pub const CHARGE_TELEGRAPH_TIME: f32 = 0.45; // rear-up wind-up before the dash
pub const CHARGE_SPEED_MULT: f32 = 3.0; // dash speed vs patrol speed
pub const CHARGE_DURATION: f32 = 1.1; // max seconds of dashing
pub const CHARGE_COOLDOWN: f32 = 1.3; // recovery before it can charge again

// Hazard parameters
pub const MAX_SPARKS: usize = 64; // Maximum number of falling sparks

// Scoring
pub const POINTS_PER_STOMP: i32 = 100;
pub const POINTS_PER_BEETLE: i32 = 200; // awarded only on the killing blow
pub const INITIAL_LIVES: i32 = 3;

// Power stomp — reward for smashing a bug at high fall speed (a well-timed big
// jump from a high platform). Landing on a bug while falling at or above this
// speed triggers a stronger POW sound, a screen shake, and double points.
pub const POWER_STOMP_MIN_FALL_SPEED: f32 = 600.0; // pixels/second (downward vy)
pub const POWER_STOMP_MULTIPLIER: i32 = 2; // points multiplier on a power stomp
pub const POWER_STOMP_VOLUME: f32 = 1.0; // louder than the normal stomp SFX

// Screen shake (used by the power stomp for a satisfying impact)
pub const SCREEN_SHAKE_DURATION: f32 = 0.35; // seconds the shake lasts
pub const SCREEN_SHAKE_MAGNITUDE: f32 = 7.0; // peak camera offset in pixels

// Colors (retro hardware theme)
pub const BACKGROUND_COLOR = rl.Color{ .r = 20, .g = 30, .b = 40, .a = 255 }; // Dark PCB green-blue
pub const PLATFORM_COLOR = rl.Color{ .r = 60, .g = 90, .b = 60, .a = 255 }; // PCB substrate green
pub const PLAYER_COLOR = rl.Color{ .r = 100, .g = 180, .b = 255, .a = 255 }; // Bright blue (programmer)
pub const BUG_COLOR = rl.Color{ .r = 200, .g = 80, .b = 80, .a = 255 }; // Red bug
pub const BEETLE_COLOR = rl.Color{ .r = 60, .g = 170, .b = 75, .a = 255 }; // Green beetle carapace
pub const BEETLE_SHELL_COLOR = rl.Color{ .r = 110, .g = 225, .b = 110, .a = 255 }; // Elytra highlight
pub const BEETLE_CRACKED_COLOR = rl.Color{ .r = 150, .g = 190, .b = 70, .a = 255 }; // Damaged shell
pub const TRACE_COLOR = rl.Color{ .r = 180, .g = 150, .b = 50, .a = 255 }; // Gold PCB traces
pub const CHIP_COLOR = rl.Color{ .r = 40, .g = 40, .b = 45, .a = 255 }; // IC chip black
pub const HUD_COLOR = rl.Color{ .r = 0, .g = 255, .b = 128, .a = 255 }; // Green terminal text

// Background parallax
pub const BG_PARALLAX_FACTOR: f32 = 0.15; // Far background scrolls at 15% of camera speed
pub const BG_CHIP_PARALLAX_FACTOR: f32 = 0.25; // Mid-layer IC chips scroll at 25% (closer than traces)
pub const BG_CHIP_COUNT: usize = 8; // Number of decorative IC chips in background

// Level dimensions — compile-time maximums for array sizing
pub const MAX_LEVEL_WIDTH: i32 = 200; // Max tiles wide (3200 px)
pub const MAX_LEVEL_HEIGHT: i32 = 160; // Max tiles tall (2560 px) — supports tall vertical levels

// Default level dimensions (used when no level data specifies otherwise)
pub const DEFAULT_LEVEL_WIDTH: i32 = TILES_X; // 50 tiles — same as screen
pub const DEFAULT_LEVEL_HEIGHT: i32 = TILES_Y; // 37 tiles — same as screen

// Spawn point (in tile coordinates)
// Player spawns with feet on top of the ground at tile y=35
pub const SPAWN_TILE_X = 3;
pub const SPAWN_TILE_Y = 35; // Ground level tile - player will be placed on top of this

// Jumper enemy AI
pub const JUMPER_INTERVAL_MIN: f32 = 1.0; // seconds between jumps (minimum)
pub const JUMPER_INTERVAL_MAX: f32 = 3.0; // seconds between jumps (maximum)
pub const JUMPER_JUMP_VELOCITY: f32 = -250.0; // pixels/second (negative = upward)

// Audio settings
pub const MUSIC_VOLUME: f32 = 0.5;
pub const SFX_VOLUME: f32 = 0.7;

// Credits screen
pub const CREDITS_SCROLL_SPEED: f32 = 20.0; // pixels/second — slow, chill, reflective pace

// Server Room scene
pub const ROOM_WALK_SPEED: f32 = 160.0; // pixels/second — PM's stroll inside the room
pub const SCRIPT_LINE_INTERVAL: f32 = 0.45; // seconds between optimize.sh output lines
pub const OPTIMIZE_BONUS: i32 = 500; // score awarded for running the optimizing script
