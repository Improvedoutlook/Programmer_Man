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

pub const BackgroundTheme = enum {
    motherboard,
    cooling_bay,
    core_chamber,
    silicon_ascent, // Level 4 — vertical hardware climb
};

pub const Tilemap = struct {
    tiles: [config.MAX_LEVEL_HEIGHT][config.MAX_LEVEL_WIDTH]TileType,
    level_width: i32, // Runtime level width in tiles
    level_height: i32, // Runtime level height in tiles
    background_theme: BackgroundTheme,
    background_time: f32,

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
            .background_theme = .motherboard,
            .background_time = 0.0,
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

    pub fn setBackgroundTheme(self: *Self, theme: BackgroundTheme) void {
        self.background_theme = theme;
        self.background_time = 0.0;
    }

    pub fn updateBackground(self: *Self, dt: f32) void {
        self.background_time += dt;
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
        const lw = self.level_width * config.TILE_SIZE;
        const lh = self.level_height * config.TILE_SIZE;

        switch (self.background_theme) {
            .motherboard => self.renderMotherboardBackground(lw, lh),
            .cooling_bay => self.renderCoolingBayBackground(lw, lh),
            .core_chamber => self.renderCoreChamberBackground(lw, lh),
            .silicon_ascent => self.renderSiliconAscentBackground(lw, lh),
        }
    }

    fn renderMotherboardBackground(self: *const Self, lw: i32, lh: i32) void {
        const base_color = rl.Color{ .r = 15, .g = 32, .b = 36, .a = 255 };
        const trace_color = rl.Color{ .r = 32, .g = 68, .b = 72, .a = 255 };
        const node_color = rl.Color{ .r = 78, .g = 162, .b = 148, .a = 150 };
        const module_color = rl.Color{ .r = 28, .g = 46, .b = 54, .a = 190 };
        const accent_color = rl.Color{ .r = 92, .g = 212, .b = 170, .a = 220 };

        rl.drawRectangle(0, 0, lw, lh, base_color);
        self.drawCircuitMesh(lw, lh, 72, 112, trace_color, node_color);

        var bus_y: i32 = 68;
        while (bus_y < lh - 24) : (bus_y += 92) {
            self.drawDataBus(0, bus_y, lw, 8, 0.35 + @as(f32, @floatFromInt(bus_y)) * 0.013, rl.Color{ .r = 34, .g = 88, .b = 82, .a = 180 }, accent_color);
        }

        var module_x: i32 = 90;
        var module_index: i32 = 0;
        while (module_x < lw) : (module_x += 320) {
            const module_y = 88 + @mod(module_index, @as(i32, 3)) * 104;
            self.drawBoardModule(
                module_x,
                module_y,
                96,
                48,
                if (@mod(module_index, @as(i32, 2)) == 0) "I/O" else "RAM",
                module_color,
                accent_color,
                @as(f32, @floatFromInt(module_index)) * 0.8,
            );
            self.drawCoolingFan(
                module_x + 156,
                module_y + 24,
                27,
                5,
                2.8 + @as(f32, @floatFromInt(module_index)) * 0.4,
                rl.Color{ .r = 38, .g = 64, .b = 72, .a = 170 },
                rl.Color{ .r = 116, .g = 188, .b = 198, .a = 120 },
            );
            module_index += 1;
        }

        var chipset_x: i32 = 220;
        while (chipset_x < lw) : (chipset_x += 460) {
            self.drawProcessorSocket(
                chipset_x,
                228,
                140,
                88,
                "CHIPSET",
                rl.Color{ .r = 28, .g = 52, .b = 58, .a = 210 },
                rl.Color{ .r = 52, .g = 96, .b = 104, .a = 255 },
                rl.Color{ .r = 102, .g = 230, .b = 178, .a = 255 },
                0.5 + @as(f32, @floatFromInt(chipset_x)) * 0.01,
            );
        }
    }

    fn renderCoolingBayBackground(self: *const Self, lw: i32, lh: i32) void {
        const base_color = rl.Color{ .r = 14, .g = 24, .b = 36, .a = 255 };
        const vent_color = rl.Color{ .r = 34, .g = 52, .b = 72, .a = 200 };
        const slat_color = rl.Color{ .r = 74, .g = 110, .b = 146, .a = 120 };
        const light_off = rl.Color{ .r = 42, .g = 64, .b = 84, .a = 180 };
        const light_on = rl.Color{ .r = 88, .g = 216, .b = 255, .a = 240 };
        const gpu_body = rl.Color{ .r = 26, .g = 36, .b = 52, .a = 210 };

        rl.drawRectangle(0, 0, lw, lh, base_color);
        self.drawCircuitMesh(lw, lh, 104, 160, rl.Color{ .r = 24, .g = 38, .b = 54, .a = 255 }, rl.Color{ .r = 76, .g = 126, .b = 170, .a = 90 });

        var bay_x: i32 = 56;
        var bay_index: i32 = 0;
        while (bay_x < lw) : (bay_x += 256) {
            self.drawVentColumn(bay_x, 56, 98, lh - 112, vent_color, slat_color);
            self.drawCoolingFan(
                bay_x + 49,
                142,
                34,
                6,
                -4.2 - @as(f32, @floatFromInt(bay_index)) * 0.35,
                rl.Color{ .r = 42, .g = 66, .b = 88, .a = 190 },
                rl.Color{ .r = 138, .g = 190, .b = 228, .a = 140 },
            );
            self.drawCoolingFan(
                bay_x + 49,
                318,
                30,
                5,
                3.4 + @as(f32, @floatFromInt(bay_index)) * 0.25,
                rl.Color{ .r = 40, .g = 58, .b = 80, .a = 180 },
                rl.Color{ .r = 112, .g = 170, .b = 210, .a = 120 },
            );

            self.drawBoardModule(
                bay_x + 118,
                108 + @mod(bay_index, @as(i32, 2)) * 132,
                122,
                38,
                "GPU",
                gpu_body,
                light_on,
                1.1 + @as(f32, @floatFromInt(bay_index)) * 0.7,
            );
            self.drawLightStrip(bay_x + 126, 158 + @mod(bay_index, @as(i32, 2)) * 132, 8, 12, light_off, light_on, 0.5 + @as(f32, @floatFromInt(bay_index)));
            rl.drawRectangle(bay_x + 118, 176 + @mod(bay_index, @as(i32, 2)) * 132, 136, 4, rl.Color{ .r = 84, .g = 128, .b = 170, .a = 120 });
            rl.drawRectangle(bay_x + 118, 186 + @mod(bay_index, @as(i32, 2)) * 132, 148, 3, rl.Color{ .r = 64, .g = 102, .b = 146, .a = 100 });
            self.drawDataBus(bay_x + 106, 86, 150, 6, 0.25 + @as(f32, @floatFromInt(bay_index)) * 0.5, rl.Color{ .r = 36, .g = 74, .b = 104, .a = 160 }, light_on);
            self.drawDataBus(bay_x + 102, 388, 164, 6, 0.85 + @as(f32, @floatFromInt(bay_index)) * 0.45, rl.Color{ .r = 28, .g = 62, .b = 90, .a = 160 }, light_on);
            bay_index += 1;
        }
    }

    fn renderCoreChamberBackground(self: *const Self, lw: i32, lh: i32) void {
        const base_color = rl.Color{ .r = 22, .g = 14, .b = 24, .a = 255 };
        const trace_color = rl.Color{ .r = 70, .g = 34, .b = 56, .a = 220 };
        const node_color = rl.Color{ .r = 255, .g = 148, .b = 88, .a = 110 };
        const cpu_energy = rl.Color{ .r = 255, .g = 120, .b = 92, .a = 255 };
        const gpu_energy = rl.Color{ .r = 98, .g = 214, .b = 255, .a = 255 };

        rl.drawRectangle(0, 0, lw, lh, base_color);
        self.drawCircuitMesh(lw, lh, 88, 144, trace_color, node_color);

        var beam_x: i32 = 52;
        while (beam_x < lw) : (beam_x += 172) {
            const beam_alpha: u8 = @intFromFloat(30.0 + (@sin(self.background_time * 2.0 + @as(f32, @floatFromInt(beam_x)) * 0.02) + 1.0) * 22.0);
            rl.drawRectangle(beam_x, 0, 10, lh, rl.Color{ .r = 78, .g = 34, .b = 64, .a = beam_alpha });
            rl.drawRectangle(beam_x + 3, 0, 4, lh, rl.Color{ .r = 255, .g = 136, .b = 102, .a = beam_alpha + 20 });
        }

        var core_x: i32 = 64;
        var core_index: i32 = 0;
        while (core_x < lw) : (core_x += 332) {
            const upper_y = 74 + @mod(core_index, @as(i32, 2)) * 24;
            const lower_y = 276 - @mod(core_index, @as(i32, 2)) * 18;

            self.drawProcessorSocket(
                core_x,
                upper_y,
                132,
                84,
                "CPU",
                rl.Color{ .r = 46, .g = 24, .b = 34, .a = 220 },
                rl.Color{ .r = 88, .g = 34, .b = 52, .a = 255 },
                cpu_energy,
                0.4 + @as(f32, @floatFromInt(core_index)) * 0.7,
            );
            self.drawProcessorSocket(
                core_x + 148,
                lower_y,
                144,
                92,
                "GPU",
                rl.Color{ .r = 26, .g = 26, .b = 42, .a = 220 },
                rl.Color{ .r = 34, .g = 56, .b = 86, .a = 255 },
                gpu_energy,
                1.2 + @as(f32, @floatFromInt(core_index)) * 0.8,
            );
            self.drawCoolingFan(
                core_x + 292,
                upper_y + 42,
                23,
                6,
                5.0 + @as(f32, @floatFromInt(core_index)) * 0.4,
                rl.Color{ .r = 70, .g = 36, .b = 48, .a = 190 },
                rl.Color{ .r = 255, .g = 164, .b = 116, .a = 120 },
            );
            self.drawDataBus(core_x - 14, upper_y + 106, 318, 8, 0.7 + @as(f32, @floatFromInt(core_index)) * 0.4, rl.Color{ .r = 78, .g = 40, .b = 58, .a = 170 }, cpu_energy);
            self.drawDataBus(core_x - 22, lower_y - 20, 326, 8, 1.3 + @as(f32, @floatFromInt(core_index)) * 0.4, rl.Color{ .r = 34, .g = 66, .b = 92, .a = 170 }, gpu_energy);
            core_index += 1;
        }
    }

    fn drawCircuitMesh(_: *const Self, lw: i32, lh: i32, horizontal_step: i32, vertical_step: i32, trace_color: rl.Color, node_color: rl.Color) void {
        var y: i32 = 36;
        while (y < lh) : (y += horizontal_step) {
            rl.drawRectangle(0, y, lw, 2, trace_color);
        }

        var x: i32 = 56;
        while (x < lw) : (x += vertical_step) {
            rl.drawRectangle(x, 0, 2, lh, trace_color);
        }

        var node_y: i32 = 36;
        while (node_y < lh) : (node_y += horizontal_step) {
            var node_x: i32 = 56;
            while (node_x < lw) : (node_x += vertical_step) {
                rl.drawCircle(node_x, node_y, 3, node_color);
            }
        }
    }

    fn drawDataBus(self: *const Self, x: i32, y: i32, width: i32, thickness: i32, phase: f32, base_color: rl.Color, pulse_color: rl.Color) void {
        const bus_seed = self.hashFloat(x * 31 + y * 17 + width * 13 + @as(i32, @intFromFloat(phase * 100.0)));
        const pulse_width: i32 = 42 + @as(i32, @intFromFloat(bus_seed * 24.0));
        const travel_span = width + pulse_width + 96;
        const progress = @mod(self.background_time * 110.0 + phase * 90.0, @as(f32, @floatFromInt(travel_span)));
        const pulse_x = x + @as(i32, @intFromFloat(progress)) - pulse_width;

        rl.drawRectangle(x, y, width, thickness, base_color);

        var packet_index: i32 = 0;
        while (packet_index < 4) : (packet_index += 1) {
            const packet_seed = self.hashFloat(x * 19 + y * 23 + width * 5 + packet_index * 97 + @as(i32, @intFromFloat(phase * 140.0)));
            const packet_width: i32 = 10 + @as(i32, @intFromFloat(packet_seed * 18.0));
            const packet_gap: i32 = 24 + @as(i32, @intFromFloat(packet_seed * 36.0));
            const packet_offset = packet_index * (packet_gap + 18) + @as(i32, @intFromFloat(packet_seed * 30.0));
            const packet_x = pulse_x - packet_offset;
            const glow = 0.65 + 0.35 * (@sin(self.background_time * 4.8 + phase * 2.0 + @as(f32, @floatFromInt(packet_index)) * 1.1) * 0.5 + 0.5);
            const packet_alpha: u8 = @intFromFloat(110.0 + glow * 120.0);

            rl.drawRectangle(packet_x, y - 1, packet_width, thickness + 2, rl.Color{
                .r = pulse_color.r,
                .g = pulse_color.g,
                .b = pulse_color.b,
                .a = packet_alpha,
            });
        }

        var node_x: i32 = x + 14;
        var node_index: i32 = 0;
        while (node_x < x + width) {
            const node_seed = self.hashFloat(x * 11 + y * 29 + width * 7 + node_index * 53);
            const node_height = thickness + 3 + @as(i32, @intFromFloat(node_seed * 3.0));
            const node_alpha: u8 = @intFromFloat(80.0 + node_seed * 50.0);
            rl.drawRectangle(node_x, y - @divTrunc(node_height - thickness, 2), 5, node_height, rl.Color{
                .r = pulse_color.r,
                .g = pulse_color.g,
                .b = pulse_color.b,
                .a = node_alpha,
            });

            node_x += 24 + @as(i32, @intFromFloat(node_seed * 34.0));
            node_index += 1;
        }
    }

    fn hashFloat(_: *const Self, value: i32) f32 {
        const x = @as(f32, @floatFromInt(@mod(value * 73 + 19, 997)));
        return x / 997.0;
    }

    fn drawCoolingFan(self: *const Self, cx: i32, cy: i32, radius: i32, blade_count: i32, spin_speed: f32, housing_color: rl.Color, blade_color: rl.Color) void {
        const outer_radius = radius + 8;
        const tau = @as(f32, std.math.pi * 2.0);
        const spin = self.background_time * spin_speed;

        rl.drawCircle(cx, cy, @floatFromInt(outer_radius), rl.Color{ .r = housing_color.r, .g = housing_color.g, .b = housing_color.b, .a = 70 });
        rl.drawCircle(cx, cy, @floatFromInt(radius + 3), housing_color);
        rl.drawCircle(cx, cy, @floatFromInt(radius - 5), rl.Color{ .r = 16, .g = 22, .b = 30, .a = 220 });

        var blade: i32 = 0;
        while (blade < blade_count) : (blade += 1) {
            const angle = spin + (@as(f32, @floatFromInt(blade)) * tau / @as(f32, @floatFromInt(blade_count)));
            const left_angle = angle - 0.4;
            const right_angle = angle + 0.4;
            const root_radius = @as(f32, @floatFromInt(radius)) * 0.18;
            const tip_radius = @as(f32, @floatFromInt(radius)) * 0.78;
            const center_x = @as(f32, @floatFromInt(cx));
            const center_y = @as(f32, @floatFromInt(cy));

            rl.drawTriangle(
                .{ .x = center_x + @cos(angle) * root_radius, .y = center_y + @sin(angle) * root_radius },
                .{ .x = center_x + @cos(left_angle) * tip_radius, .y = center_y + @sin(left_angle) * tip_radius },
                .{ .x = center_x + @cos(right_angle) * tip_radius, .y = center_y + @sin(right_angle) * tip_radius },
                blade_color,
            );
        }

        rl.drawCircle(cx, cy, 7, rl.Color{ .r = 170, .g = 188, .b = 204, .a = 210 });
        rl.drawRectangle(cx - outer_radius, cy - 1, outer_radius * 2, 2, rl.Color{ .r = 190, .g = 210, .b = 222, .a = 70 });
        rl.drawRectangle(cx - 1, cy - outer_radius, 2, outer_radius * 2, rl.Color{ .r = 190, .g = 210, .b = 222, .a = 70 });
    }

    fn drawVentColumn(_: *const Self, x: i32, y: i32, width: i32, height: i32, panel_color: rl.Color, slat_color: rl.Color) void {
        rl.drawRectangle(x, y, width, height, panel_color);
        rl.drawRectangleLines(x, y, width, height, rl.Color{ .r = 90, .g = 124, .b = 152, .a = 120 });

        var slat_y: i32 = y + 12;
        while (slat_y < y + height - 8) : (slat_y += 10) {
            rl.drawRectangle(x + 8, slat_y, width - 16, 3, slat_color);
        }
    }

    fn drawBoardModule(self: *const Self, x: i32, y: i32, width: i32, height: i32, label: [:0]const u8, body_color: rl.Color, accent_color: rl.Color, phase: f32) void {
        rl.drawRectangle(x, y, width, height, body_color);
        rl.drawRectangleLines(x, y, width, height, rl.Color{ .r = accent_color.r, .g = accent_color.g, .b = accent_color.b, .a = 90 });
        rl.drawText(label, x + 10, y + 8, 10, accent_color);

        var pin_x: i32 = x + 6;
        while (pin_x < x + width - 4) : (pin_x += 14) {
            rl.drawRectangle(pin_x, y - 3, 6, 3, rl.Color{ .r = 156, .g = 144, .b = 90, .a = 180 });
            rl.drawRectangle(pin_x, y + height, 6, 3, rl.Color{ .r = 156, .g = 144, .b = 90, .a = 180 });
        }

        var led: i32 = 0;
        while (led < 4) : (led += 1) {
            const led_on = @sin(self.background_time * 3.2 + phase + @as(f32, @floatFromInt(led)) * 0.8) > 0.0;
            const led_color = if (led_on)
                accent_color
            else
                rl.Color{ .r = 42, .g = 56, .b = 64, .a = 200 };
            rl.drawCircle(x + 14 + led * 14, y + height - 10, 3, led_color);
        }
    }

    fn drawProcessorSocket(self: *const Self, x: i32, y: i32, width: i32, height: i32, label: [:0]const u8, socket_color: rl.Color, core_color: rl.Color, energy_color: rl.Color, phase: f32) void {
        rl.drawRectangle(x, y, width, height, socket_color);
        rl.drawRectangleLines(x, y, width, height, rl.Color{ .r = energy_color.r, .g = energy_color.g, .b = energy_color.b, .a = 110 });
        rl.drawRectangle(x + 10, y + 10, width - 20, height - 20, core_color);
        rl.drawRectangleLines(x + 10, y + 10, width - 20, height - 20, rl.Color{ .r = 220, .g = 220, .b = 230, .a = 60 });
        rl.drawText(label, x + 12, y + height - 18, 10, energy_color);

        var pin_x: i32 = x + 10;
        while (pin_x < x + width - 6) : (pin_x += 14) {
            rl.drawRectangle(pin_x, y - 4, 6, 4, rl.Color{ .r = 168, .g = 158, .b = 96, .a = 180 });
            rl.drawRectangle(pin_x, y + height, 6, 4, rl.Color{ .r = 168, .g = 158, .b = 96, .a = 180 });
        }

        var pin_y: i32 = y + 12;
        while (pin_y < y + height - 8) : (pin_y += 14) {
            rl.drawRectangle(x - 4, pin_y, 4, 6, rl.Color{ .r = 168, .g = 158, .b = 96, .a = 180 });
            rl.drawRectangle(x + width, pin_y, 4, 6, rl.Color{ .r = 168, .g = 158, .b = 96, .a = 180 });
        }

        const cell_gap: i32 = 6;
        const cell_width = @divTrunc(width - 34, 2);
        const cell_height = @divTrunc(height - 38, 2);
        var row: i32 = 0;
        while (row < 2) : (row += 1) {
            var col: i32 = 0;
            while (col < 2) : (col += 1) {
                const cell_x = x + 16 + col * (cell_width + cell_gap);
                const cell_y = y + 16 + row * (cell_height + cell_gap);
                const pulse = 0.45 + 0.55 * (@sin(self.background_time * 2.8 + phase + @as(f32, @floatFromInt(row * 2 + col)) * 0.9) * 0.5 + 0.5);
                const glow_alpha: u8 = @intFromFloat(70.0 + pulse * 120.0);
                rl.drawRectangle(cell_x, cell_y, cell_width, cell_height, rl.Color{ .r = core_color.r, .g = core_color.g, .b = core_color.b, .a = 230 });
                rl.drawRectangle(cell_x + 4, cell_y + 4, cell_width - 8, cell_height - 8, rl.Color{
                    .r = energy_color.r,
                    .g = energy_color.g,
                    .b = energy_color.b,
                    .a = glow_alpha,
                });
            }
        }
    }

    fn drawLightStrip(self: *const Self, x: i32, y: i32, count: i32, spacing: i32, off_color: rl.Color, on_color: rl.Color, phase: f32) void {
        var light: i32 = 0;
        while (light < count) : (light += 1) {
            const active = @sin(self.background_time * 4.0 + phase + @as(f32, @floatFromInt(light)) * 0.55) > -0.1;
            const color = if (active) on_color else off_color;
            rl.drawRectangle(x + light * spacing, y, 8, 4, color);
        }
    }

    fn renderSiliconAscentBackground(self: *const Self, lw: i32, lh: i32) void {
        const base_color = rl.Color{ .r = 12, .g = 18, .b = 30, .a = 255 };
        const trace_color = rl.Color{ .r = 20, .g = 38, .b = 62, .a = 255 };
        const node_color = rl.Color{ .r = 54, .g = 132, .b = 210, .a = 100 };
        const accent_color = rl.Color{ .r = 70, .g = 194, .b = 255, .a = 255 };
        const ram_body_color = rl.Color{ .r = 22, .g = 38, .b = 62, .a = 210 };

        rl.drawRectangle(0, 0, lw, lh, base_color);

        // Circuit mesh — tighter horizontal spacing than other themes to sell height
        self.drawCircuitMesh(lw, lh, 120, 80, trace_color, node_color);

        // Heatsink fin columns: groups of 4 tall thin fins spanning the full level height
        var fin_x: i32 = 20;
        while (fin_x < lw) : (fin_x += 116) {
            const col_i = @divTrunc(fin_x - 20, 116);
            var fin: i32 = 0;
            while (fin < 4) : (fin += 1) {
                const fx = fin_x + fin * 7;
                const alpha: u8 = @intFromFloat(
                    80.0 + (@sin(self.background_time * 1.2 +
                        @as(f32, @floatFromInt(col_i)) * 0.9 +
                        @as(f32, @floatFromInt(fin)) * 0.45) * 0.5 + 0.5) * 68.0,
                );
                rl.drawRectangle(fx, 0, 4, lh, rl.Color{ .r = 36, .g = 56, .b = 90, .a = alpha });
            }
        }

        // Horizontal data buses repeating up the full level height
        var bus_y: i32 = 60;
        while (bus_y < lh) : (bus_y += 180) {
            const phase: f32 = 0.2 + @as(f32, @floatFromInt(bus_y)) * 0.005;
            self.drawDataBus(0, bus_y, lw, 6, phase,
                rl.Color{ .r = 28, .g = 58, .b = 94, .a = 155 }, accent_color);
        }

        // RAM sticks and cooling fans, tiling vertically across the full level height
        var tile_y: i32 = 0;
        while (tile_y < lh) : (tile_y += 400) {
            const ti = @divTrunc(tile_y, 400);
            var col_x: i32 = 44 + @mod(ti, @as(i32, 2)) * 56;
            while (col_x < lw) : (col_x += 220) {
                const ci = @divTrunc(col_x - 44 - @mod(ti, @as(i32, 2)) * 56, 220);
                const sy = tile_y + 24 + @mod(ci, @as(i32, 3)) * 72;
                const phase: f32 = @as(f32, @floatFromInt(ti)) * 0.7 + @as(f32, @floatFromInt(ci)) * 1.4;

                self.drawRamStick(col_x, sy, 18, 86, ram_body_color, accent_color, phase);
                if (col_x + 24 < lw) {
                    self.drawRamStick(col_x + 24, sy + 40, 18, 86, ram_body_color, accent_color, phase + 0.65);
                }

                if (col_x + 108 < lw and sy + 120 < lh) {
                    self.drawCoolingFan(
                        col_x + 108,
                        sy + 80,
                        20, 6,
                        -2.5 - @as(f32, @floatFromInt(ci + ti)) * 0.4,
                        rl.Color{ .r = 26, .g = 44, .b = 72, .a = 180 },
                        rl.Color{ .r = 88, .g = 180, .b = 242, .a = 128 },
                    );
                }
            }
        }

        // Board modules with DDR5 label, tiling vertically
        var mod_y: i32 = 80;
        while (mod_y < lh) : (mod_y += 340) {
            const mi = @divTrunc(mod_y - 80, 340);
            const mod_start_x = 110 + @mod(mi, @as(i32, 2)) * 44;
            var mod_x: i32 = mod_start_x;
            while (mod_x < lw - 88) : (mod_x += 268) {
                const mxi = @divTrunc(mod_x - mod_start_x, 268);
                self.drawBoardModule(
                    mod_x, mod_y + @mod(mxi, @as(i32, 2)) * 48,
                    92, 38, "DDR5",
                    ram_body_color,
                    accent_color,
                    @as(f32, @floatFromInt(mi)) * 0.9 + @as(f32, @floatFromInt(mxi)) * 1.5,
                );
            }
        }

        // Processor sockets near the summit (low y values = top of the climb)
        var sock_x: i32 = 72;
        while (sock_x < lw) : (sock_x += 368) {
            const si = @divTrunc(sock_x - 72, 368);
            self.drawProcessorSocket(
                sock_x,
                44 + @mod(si, @as(i32, 2)) * 52,
                130, 82, "SoC",
                rl.Color{ .r = 18, .g = 32, .b = 54, .a = 220 },
                rl.Color{ .r = 36, .g = 70, .b = 114, .a = 255 },
                accent_color,
                0.45 + @as(f32, @floatFromInt(si)) * 0.85,
            );
        }
    }

    // Vertical RAM stick module — signature element of the Silicon Ascent theme.
    fn drawRamStick(self: *const Self, x: i32, y: i32, width: i32, height: i32, body_color: rl.Color, accent_color: rl.Color, phase: f32) void {
        rl.drawRectangle(x, y, width, height, body_color);
        rl.drawRectangleLines(x, y, width, height, rl.Color{
            .r = accent_color.r, .g = accent_color.g, .b = accent_color.b, .a = 52,
        });
        // Gold edge connector fingers at bottom
        var fx: i32 = x + 2;
        while (fx < x + width - 2) : (fx += 5) {
            rl.drawRectangle(fx, y + height - 6, 3, 6, rl.Color{ .r = 166, .g = 146, .b = 72, .a = 200 });
        }
        // Key notch cut-out
        rl.drawRectangle(
            x + @divTrunc(width, 2) - 2, y + height - 8, 4, 8,
            rl.Color{ .r = 12, .g = 18, .b = 30, .a = 255 },
        );
        // Pulsing indicator on face
        const pulse: u8 = @intFromFloat(
            70.0 + (@sin(self.background_time * 2.8 + phase) * 0.5 + 0.5) * 95.0,
        );
        rl.drawCircle(
            x + @divTrunc(width, 2), y + 18, 3,
            rl.Color{ .r = accent_color.r, .g = accent_color.g, .b = accent_color.b, .a = pulse },
        );
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
    ai: []const u8 = "walker",
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

pub const AiType = enum {
    walker,
    jumper,
};

pub const BugSpawn = struct {
    tile_x: i32,
    tile_y: i32,
    facing_right: bool,
    speed: f32,
    ai: AiType = .walker,
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

/// Load any level from a JSON data file at runtime.
/// Populates the tilemap and returns spawn / config metadata.
pub fn loadLevelFromJson(tilemap: *Tilemap, path: []const u8) !LevelData {
    // Read JSON file from disk (relative to CWD / project root)
    const file = try std.fs.cwd().openFile(path, .{});
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
            .ai = if (std.mem.eql(u8, bug.ai, "jumper")) .jumper else .walker,
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

/// Load Level 1 from the JSON data file at runtime (backward-compatible wrapper).
pub fn loadLevel1FromJson(tilemap: *Tilemap) !LevelData {
    return loadLevelFromJson(tilemap, "assets/data/level1.json");
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
