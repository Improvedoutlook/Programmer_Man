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
pub const TILES_X: i32 = GAME_WIDTH / TILE_SIZE; // 50 tiles
pub const TILES_Y: i32 = GAME_HEIGHT / TILE_SIZE; // 37 tiles

// Player dimensions and physics
pub const PLAYER_WIDTH: f32 = 24; // Was 14
pub const PLAYER_HEIGHT: f32 = 36; // Was 16
pub const PLAYER_RUN_SPEED: f32 = 200.0; // pixels/second
pub const PLAYER_GRAVITY: f32 = 1200.0; // pixels/second²
pub const PLAYER_JUMP_IMPULSE: f32 = 450.0; // pixels/second
pub const PLAYER_MAX_FALL_SPEED: f32 = 900.0; // pixels/second
pub const PLAYER_AIR_CONTROL: f32 = 0.6; // 60% of ground acceleration
pub const PLAYER_BOUNCE_FACTOR: f32 = 0.6; // 60% of jump impulse on stomp

// Enemy (Bug) parameters
pub const BUG_WIDTH: f32 = 16;
pub const BUG_HEIGHT: f32 = 16;
pub const BUG_WALK_SPEED: f32 = 80.0; // pixels/second (increased for visibility)
pub const MAX_BUGS: usize = 16;

// Hazard parameters
pub const MAX_SPARKS: usize = 20; // Maximum number of falling sparks

// Scoring
pub const POINTS_PER_STOMP: i32 = 100;
pub const INITIAL_LIVES: i32 = 3;

// Colors (retro hardware theme)
pub const BACKGROUND_COLOR = rl.Color{ .r = 20, .g = 30, .b = 40, .a = 255 }; // Dark PCB green-blue
pub const PLATFORM_COLOR = rl.Color{ .r = 60, .g = 90, .b = 60, .a = 255 }; // PCB substrate green
pub const PLAYER_COLOR = rl.Color{ .r = 100, .g = 180, .b = 255, .a = 255 }; // Bright blue (programmer)
pub const BUG_COLOR = rl.Color{ .r = 200, .g = 80, .b = 80, .a = 255 }; // Red bug
pub const TRACE_COLOR = rl.Color{ .r = 180, .g = 150, .b = 50, .a = 255 }; // Gold PCB traces
pub const CHIP_COLOR = rl.Color{ .r = 40, .g = 40, .b = 45, .a = 255 }; // IC chip black
pub const HUD_COLOR = rl.Color{ .r = 0, .g = 255, .b = 128, .a = 255 }; // Green terminal text

// Level dimensions
pub const LEVEL_WIDTH: i32 = TILES_X;
pub const LEVEL_HEIGHT: i32 = TILES_Y;

// Spawn point (in tile coordinates)
// Player spawns with feet on top of the ground at tile y=35
pub const SPAWN_TILE_X = 3;
pub const SPAWN_TILE_Y = 35; // Ground level tile - player will be placed on top of this

// Audio settings
pub const MUSIC_VOLUME: f32 = 0.5;
pub const SFX_VOLUME: f32 = 0.7;
