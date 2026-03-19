//! Tilemap module - Handles level data, collision tiles, and rendering

const std = @import("std");
const rl = @import("raylib");
const config = @import("config.zig");

pub const TileType = enum(u8) {
    empty = 0,
    solid = 1, // Platform/ground
    chip = 2, // Decorative chip (solid)
    trace = 3, // PCB trace (decorative, non-solid)
    capacitor = 4, // Decorative capacitor (solid)
    spawn = 5, // Player spawn point
    bug_spawn = 6, // Bug spawn point
};

pub const Tilemap = struct {
    tiles: [config.MAX_LEVEL_HEIGHT][config.MAX_LEVEL_WIDTH]TileType,
    level_width: i32, // Runtime level width in tiles
    level_height: i32, // Runtime level height in tiles

    const Self = @This();

    /// Create a tilemap with the given dimensions (in tiles).
    /// Dimensions are clamped to compile-time maximums.
    pub fn init(level_width: i32, level_height: i32) Self {
        const w = @min(level_width, config.MAX_LEVEL_WIDTH);
        const h = @min(level_height, config.MAX_LEVEL_HEIGHT);
        var tilemap = Self{
            .tiles = undefined,
            .level_width = w,
            .level_height = h,
        };
        // Initialize all tiles within level bounds to empty
        for (0..@intCast(h)) |y| {
            for (0..@intCast(w)) |x| {
                tilemap.tiles[y][x] = .empty;
            }
        }
        return tilemap;
    }

    /// Create a tilemap using the default dimensions from config.
    pub fn initDefault() Self {
        return init(config.DEFAULT_LEVEL_WIDTH, config.DEFAULT_LEVEL_HEIGHT);
    }

    /// Level width in pixels.
    pub fn getLevelPixelWidth(self: *const Self) f32 {
        return @floatFromInt(self.level_width * config.TILE_SIZE);
    }

    /// Level height in pixels.
    pub fn getLevelPixelHeight(self: *const Self) f32 {
        return @floatFromInt(self.level_height * config.TILE_SIZE);
    }

    pub fn setTile(self: *Self, x: i32, y: i32, tile_type: TileType) void {
        if (x >= 0 and x < self.level_width and y >= 0 and y < self.level_height) {
            self.tiles[@intCast(y)][@intCast(x)] = tile_type;
        }
    }

    pub fn getTile(self: *const Self, x: i32, y: i32) TileType {
        if (x >= 0 and x < self.level_width and y >= 0 and y < self.level_height) {
            return self.tiles[@intCast(y)][@intCast(x)];
        }
        return .empty;
    }

    pub fn isSolid(self: *const Self, x: i32, y: i32) bool {
        const tile = self.getTile(x, y);
        return switch (tile) {
            .solid, .chip, .capacitor => true,
            else => false,
        };
    }

    pub fn checkCollision(self: *const Self, px: f32, py: f32, width: f32, height: f32) bool {
        // Check all tiles that the rectangle overlaps
        const left: i32 = @intFromFloat(@floor(px / @as(f32, @floatFromInt(config.TILE_SIZE))));
        const right: i32 = @intFromFloat(@floor((px + width - 1) / @as(f32, @floatFromInt(config.TILE_SIZE))));
        const top: i32 = @intFromFloat(@floor(py / @as(f32, @floatFromInt(config.TILE_SIZE))));
        const bottom: i32 = @intFromFloat(@floor((py + height - 1) / @as(f32, @floatFromInt(config.TILE_SIZE))));

        var y = top;
        while (y <= bottom) : (y += 1) {
            var x = left;
            while (x <= right) : (x += 1) {
                if (self.isSolid(x, y)) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Render visible tiles, culling to the camera viewport.
    /// `cam_x` / `cam_y` are the top-left world-pixel coordinates of the viewport.
    pub fn render(self: *const Self, cam_x: f32, cam_y: f32) void {
        const ts: f32 = @floatFromInt(config.TILE_SIZE);
        const vw: f32 = @floatFromInt(config.GAME_WIDTH);
        const vh: f32 = @floatFromInt(config.GAME_HEIGHT);

        // Visible tile range with 1-tile padding for partially visible edges
        const col0 = @max(@as(i32, 0), @as(i32, @intFromFloat(@floor(cam_x / ts))) - 1);
        const col1 = @min(self.level_width, @as(i32, @intFromFloat(@ceil((cam_x + vw) / ts))) + 1);
        const row0 = @max(@as(i32, 0), @as(i32, @intFromFloat(@floor(cam_y / ts))) - 1);
        const row1 = @min(self.level_height, @as(i32, @intFromFloat(@ceil((cam_y + vh) / ts))) + 1);

        const start_col: usize = @intCast(col0);
        const end_col: usize = @intCast(col1);
        const start_row: usize = @intCast(row0);
        const end_row: usize = @intCast(row1);

        for (start_row..end_row) |y| {
            for (start_col..end_col) |x| {
                const tile = self.tiles[y][x];
                const px: i32 = @intCast(x * @as(usize, @intCast(config.TILE_SIZE)));
                const py: i32 = @intCast(y * @as(usize, @intCast(config.TILE_SIZE)));

                switch (tile) {
                    .solid => self.renderPlatformTile(px, py),
                    .chip => self.renderChipTile(px, py),
                    .trace => self.renderTraceTile(px, py),
                    .capacitor => self.renderCapacitorTile(px, py),
                    else => {},
                }
            }
        }
    }

    fn renderPlatformTile(_: *const Self, px: i32, py: i32) void {
        // PCB substrate green platform
        rl.drawRectangle(px, py, config.TILE_SIZE, config.TILE_SIZE, config.PLATFORM_COLOR);
        // Add some texture detail
        rl.drawRectangle(px + 1, py + 1, config.TILE_SIZE - 2, 2, rl.Color{ .r = 80, .g = 120, .b = 80, .a = 255 });
        rl.drawRectangle(px + 1, py + config.TILE_SIZE - 3, config.TILE_SIZE - 2, 2, rl.Color{ .r = 40, .g = 70, .b = 40, .a = 255 });
    }

    fn renderChipTile(_: *const Self, px: i32, py: i32) void {
        // IC chip appearance
        rl.drawRectangle(px, py, config.TILE_SIZE, config.TILE_SIZE, config.CHIP_COLOR);
        // Chip pins on sides
        rl.drawRectangle(px - 2, py + 2, 4, 2, rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 });
        rl.drawRectangle(px - 2, py + 6, 4, 2, rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 });
        rl.drawRectangle(px - 2, py + 10, 4, 2, rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 });
        rl.drawRectangle(px + config.TILE_SIZE - 2, py + 2, 4, 2, rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 });
        rl.drawRectangle(px + config.TILE_SIZE - 2, py + 6, 4, 2, rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 });
        rl.drawRectangle(px + config.TILE_SIZE - 2, py + 10, 4, 2, rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 });
        // Chip label dot
        rl.drawCircle(px + 4, py + 4, 2, rl.Color{ .r = 80, .g = 80, .b = 80, .a = 255 });
    }

    fn renderTraceTile(_: *const Self, px: i32, py: i32) void {
        // PCB trace (gold colored line)
        rl.drawRectangle(px, py + 6, config.TILE_SIZE, 4, config.TRACE_COLOR);
    }

    fn renderCapacitorTile(_: *const Self, px: i32, py: i32) void {
        // Capacitor appearance (tall cylinder)
        const cap_color = rl.Color{ .r = 50, .g = 50, .b = 180, .a = 255 };
        rl.drawRectangle(px + 4, py, 8, config.TILE_SIZE, cap_color);
        // Silver top
        rl.drawRectangle(px + 4, py, 8, 3, rl.Color{ .r = 180, .g = 180, .b = 180, .a = 255 });
        // Stripe
        rl.drawRectangle(px + 4, py + 4, 8, 2, rl.Color{ .r = 100, .g = 100, .b = 200, .a = 255 });
    }

    pub fn renderBackground(self: *const Self) void {
        // Multi-layer parallax-style background (static for MVP)
        const lw = self.level_width * config.TILE_SIZE;
        const lh = self.level_height * config.TILE_SIZE;

        // Base PCB color
        rl.drawRectangle(0, 0, lw, lh, config.BACKGROUND_COLOR);

        // Background circuit traces (decorative)
        const trace_color = rl.Color{ .r = 30, .g = 45, .b = 55, .a = 255 };

        // Horizontal traces
        var y: i32 = 50;
        while (y < lh) : (y += 80) {
            rl.drawRectangle(0, y, lw, 2, trace_color);
        }

        // Vertical traces
        var x: i32 = 100;
        while (x < lw) : (x += 120) {
            rl.drawRectangle(x, 0, 2, lh, trace_color);
        }

        // Background chips (decorative, far back)
        const chip_bg_color = rl.Color{ .r = 25, .g = 35, .b = 45, .a = 255 };
        rl.drawRectangle(50, 100, 40, 30, chip_bg_color);
        rl.drawRectangle(300, 200, 60, 40, chip_bg_color);
        rl.drawRectangle(550, 150, 50, 35, chip_bg_color);
        rl.drawRectangle(700, 300, 45, 30, chip_bg_color);

        // Via holes (small circles representing through-holes)
        const via_color = rl.Color{ .r = 40, .g = 55, .b = 65, .a = 255 };
        rl.drawCircle(120, 180, 4, via_color);
        rl.drawCircle(380, 280, 4, via_color);
        rl.drawCircle(520, 380, 4, via_color);
        rl.drawCircle(650, 120, 4, via_color);
        rl.drawCircle(200, 450, 4, via_color);
    }
};

// ---------------------------------------------------------------------------
// JSON level loading
// ---------------------------------------------------------------------------

const JsonCoord = struct { x: i32, y: i32 };
const JsonSegment = struct { x1: i32, x2: i32 };
const JsonGround = struct { y: i32, segments: []const JsonSegment };
const JsonPlatform = struct {
    x1: i32,
    x2: i32,
    y: i32,
    tile_type: []const u8,
    sparks: bool = false,
};
const JsonDecoration = struct {
    x1: i32,
    x2: i32,
    y: i32,
    tile_type: []const u8,
};
const JsonBug = struct {
    x: i32,
    y: i32,
    facing: []const u8,
    speed: f32 = 1.0,
};
const JsonLevelSchema = struct {
    name: []const u8,
    description: []const u8,
    width: i32,
    height: i32,
    spawn: JsonCoord,
    terminal: JsonCoord,
    ground: JsonGround,
    platforms: []const JsonPlatform,
    decorations: []const JsonDecoration,
    bugs: []const JsonBug,
};

pub const MAX_SPAWN_ENTRIES: usize = 32;

pub const BugSpawn = struct {
    tile_x: i32,
    tile_y: i32,
    facing_right: bool,
    speed: f32,
};

pub const SparkSpawn = struct {
    tile_x: i32,
    tile_y: i32,
};

pub const LevelData = struct {
    player_spawn_x: i32,
    player_spawn_y: i32,
    terminal_x: i32,
    terminal_y: i32,
    bug_spawns: [MAX_SPAWN_ENTRIES]BugSpawn,
    bug_count: usize,
    spark_spawns: [MAX_SPAWN_ENTRIES]SparkSpawn,
    spark_count: usize,
};

fn jsonTileType(name: []const u8) TileType {
    if (std.mem.eql(u8, name, "solid")) return .solid;
    if (std.mem.eql(u8, name, "chip")) return .chip;
    if (std.mem.eql(u8, name, "trace")) return .trace;
    if (std.mem.eql(u8, name, "capacitor")) return .capacitor;
    return .solid;
}

/// Load Level 1 from the JSON data file at runtime.
/// Populates the tilemap and returns spawn / config metadata.
pub fn loadLevel1FromJson(tilemap: *Tilemap) !LevelData {
    // Read JSON file from disk (relative to CWD / project root)
    const file = try std.fs.cwd().openFile("assets/data/level1.json", .{});
    defer file.close();
    const json_bytes = try file.readToEndAlloc(std.heap.page_allocator, 128 * 1024);
    defer std.heap.page_allocator.free(json_bytes);

    var parsed = try std.json.parseFromSlice(
        JsonLevelSchema,
        std.heap.page_allocator,
        json_bytes,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const level = parsed.value;

    // Initialise tilemap with level dimensions
    tilemap.* = Tilemap.init(level.width, level.height);

    // Ground segments
    for (level.ground.segments) |seg| {
        fillHorizontal(tilemap, seg.x1, seg.x2, level.ground.y, .solid);
    }

    // Platforms
    for (level.platforms) |p| {
        fillHorizontal(tilemap, p.x1, p.x2, p.y, jsonTileType(p.tile_type));
    }

    // Decorations
    for (level.decorations) |d| {
        fillHorizontal(tilemap, d.x1, d.x2, d.y, jsonTileType(d.tile_type));
    }

    // Build result
    var result = LevelData{
        .player_spawn_x = level.spawn.x,
        .player_spawn_y = level.spawn.y,
        .terminal_x = level.terminal.x,
        .terminal_y = level.terminal.y,
        .bug_spawns = undefined,
        .bug_count = 0,
        .spark_spawns = undefined,
        .spark_count = 0,
    };

    // Collect bug spawns
    for (level.bugs) |bug| {
        if (result.bug_count >= MAX_SPAWN_ENTRIES) break;
        result.bug_spawns[result.bug_count] = .{
            .tile_x = bug.x,
            .tile_y = bug.y,
            .facing_right = std.mem.eql(u8, bug.facing, "right"),
            .speed = bug.speed,
        };
        result.bug_count += 1;
    }

    // Collect spark spawns from platforms flagged with sparks: true.
    // Spread spawn points across wide platforms (one every ~3 tiles).
    for (level.platforms) |p| {
        if (!p.sparks) continue;
        const plat_width = p.x2 - p.x1;
        const spark_spacing: i32 = 3; // tiles between spawn points
        const num_points = @max(@as(i32, 1), @divTrunc(plat_width, spark_spacing));
        var si: i32 = 0;
        while (si < num_points) : (si += 1) {
            if (result.spark_count >= MAX_SPAWN_ENTRIES) break;
            const offset = @divTrunc(plat_width * (2 * si + 1), 2 * num_points);
            result.spark_spawns[result.spark_count] = .{
                .tile_x = p.x1 + offset,
                .tile_y = p.y + 1, // spawn at or just below platform
            };
            result.spark_count += 1;
        }
    }

    return result;
}

// ---------------------------------------------------------------------------
// Legacy / fallback level builder (hardcoded)
// ---------------------------------------------------------------------------

// Level data builder functions
pub fn createLevel1(tilemap: *Tilemap) void {
    // Hardware-themed platforming level

    // Ground floor (bottom of screen)
    const ground_y: i32 = 35; // Near bottom
    fillHorizontal(tilemap, 0, 50, ground_y, .solid);

    // Create gaps in ground
    clearHorizontal(tilemap, 15, 18, ground_y); // Gap 1
    clearHorizontal(tilemap, 28, 32, ground_y); // Gap 2
    clearHorizontal(tilemap, 42, 45, ground_y); // Gap 3

    // Platform 1 - Low left (chip style)
    fillHorizontal(tilemap, 5, 12, 30, .chip);

    // Platform 2 - Middle floating (the one you're stuck on)
    fillHorizontal(tilemap, 18, 26, 28, .solid);

    // NEW: Bridge from Platform 2 to left side
    fillHorizontal(tilemap, 14, 18, 26, .solid); // Connects to Platform 1 area

    // NEW: Step up from Platform 2 to Platform 3
    fillHorizontal(tilemap, 26, 30, 26, .solid); // Right of Platform 2

    // Platform 3 - High right
    fillHorizontal(tilemap, 30, 38, 24, .solid);

    // Platform 4 - Very high left
    fillHorizontal(tilemap, 8, 15, 20, .capacitor);

    // NEW: Connect Platform 4 to lower platforms
    fillHorizontal(tilemap, 6, 9, 23, .solid); // Step down from Platform 4

    // Platform 5 - Top right corner
    fillHorizontal(tilemap, 40, 48, 18, .chip);

    // NEW: Connect Platform 5 to Platform 3
    fillHorizontal(tilemap, 38, 41, 21, .solid); // Bridge between 3 and 5

    // Small stepping stones (keep existing)
    tilemap.setTile(14, 26, .solid);
    tilemap.setTile(15, 26, .solid);
    tilemap.setTile(27, 22, .solid);
    tilemap.setTile(28, 22, .solid);

    // Decorative traces in background (non-solid)
    fillHorizontal(tilemap, 0, 50, 15, .trace);
    fillHorizontal(tilemap, 0, 50, 10, .trace);
}

fn fillHorizontal(tilemap: *Tilemap, x1: i32, x2: i32, y: i32, tile_type: TileType) void {
    var x = x1;
    while (x < x2) : (x += 1) {
        tilemap.setTile(x, y, tile_type);
    }
}

fn clearHorizontal(tilemap: *Tilemap, x1: i32, x2: i32, y: i32) void {
    var x = x1;
    while (x < x2) : (x += 1) {
        tilemap.setTile(x, y, .empty);
    }
}
