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
    tiles: [config.LEVEL_HEIGHT][config.LEVEL_WIDTH]TileType,

    const Self = @This();

    pub fn init() Self {
        var tilemap = Self{
            .tiles = undefined,
        };
        // Initialize all tiles to empty
        for (0..@intCast(config.LEVEL_HEIGHT)) |y| {
            for (0..@intCast(config.LEVEL_WIDTH)) |x| {
                tilemap.tiles[y][x] = .empty;
            }
        }
        return tilemap;
    }

    pub fn setTile(self: *Self, x: i32, y: i32, tile_type: TileType) void {
        if (x >= 0 and x < config.LEVEL_WIDTH and y >= 0 and y < config.LEVEL_HEIGHT) {
            self.tiles[@intCast(y)][@intCast(x)] = tile_type;
        }
    }

    pub fn getTile(self: *const Self, x: i32, y: i32) TileType {
        if (x >= 0 and x < config.LEVEL_WIDTH and y >= 0 and y < config.LEVEL_HEIGHT) {
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

    pub fn render(self: *const Self) void {
        for (0..@intCast(config.LEVEL_HEIGHT)) |y| {
            for (0..@intCast(config.LEVEL_WIDTH)) |x| {
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

    pub fn renderBackground(_: *const Self) void {
        // Multi-layer parallax-style background (static for MVP)

        // Base PCB color
        rl.drawRectangle(0, 0, config.SCREEN_WIDTH, config.SCREEN_HEIGHT, config.BACKGROUND_COLOR);

        // Background circuit traces (decorative)
        const trace_color = rl.Color{ .r = 30, .g = 45, .b = 55, .a = 255 };

        // Horizontal traces
        var y: i32 = 50;
        while (y < config.SCREEN_HEIGHT) : (y += 80) {
            rl.drawRectangle(0, y, config.SCREEN_WIDTH, 2, trace_color);
        }

        // Vertical traces
        var x: i32 = 100;
        while (x < config.SCREEN_WIDTH) : (x += 120) {
            rl.drawRectangle(x, 0, 2, config.SCREEN_HEIGHT, trace_color);
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

    // Platform 2 - Middle floating
    fillHorizontal(tilemap, 18, 26, 28, .solid);

    // Platform 3 - High right
    fillHorizontal(tilemap, 30, 38, 24, .solid);

    // Platform 4 - Very high left
    fillHorizontal(tilemap, 8, 15, 20, .capacitor);

    // Platform 5 - Top right corner
    fillHorizontal(tilemap, 40, 48, 18, .chip);

    // Small stepping stones
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
