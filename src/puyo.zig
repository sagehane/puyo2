const std = @import("std");
const testing = std.testing;

pub const grid_width = 6;
pub const grid_height = 13;

const Coord = packed struct(u8) { x: u4, y: u4 };

pub const Colour = enum(u3) {
    empty,
    red,
    green,
    blue,
    yellow,
    purple,
    garbage,
    wall, // Unused in normal gameplay

    fn isColour(self: Colour) void {
        return switch (self) {
            .red | .green | .blue | .yellow | .purple => true,
            _ => false,
        };
    }
};

pub const Sprite = packed struct(u7) {
    colour: Colour,
    mask: AdjacentMask = .{},

    const AdjacentMask = packed struct(u4) {
        up: bool = false,
        down: bool = false,
        left: bool = false,
        right: bool = false,
    };

    test {
        try testing.expectEqual(0x00, @bitCast(u7, Sprite{ .colour = .empty }));
        try testing.expectEqual(0x10, @bitCast(u7, Sprite{ .colour = .red }));
        try testing.expectEqual(0x20, @bitCast(u7, Sprite{ .colour = .green }));
        try testing.expectEqual(0x20, @bitCast(u7, Sprite{ .colour = .blue }));
        try testing.expectEqual(0x30, @bitCast(u7, Sprite{ .colour = .yellow }));
        try testing.expectEqual(0x40, @bitCast(u7, Sprite{ .colour = .purple }));
        try testing.expectEqual(0x50, @bitCast(u7, Sprite{ .colour = .garbage }));
        try testing.expectEqual(0x60, @bitCast(u7, Sprite{ .colour = .wall }));
    }
};

/// TODO: Consider scrapping this and handling it on SDL's side
pub const Tsumo = packed struct(u16) {
    colour_1: Colour,
    colour_2: Colour,
    orientation: Orientation = .up,
    /// Coord of colour_1
    coord: Coord = .{ .x = 2, .y = 0 },

    const Orientation = enum(u2) {
        up = 0b00,
        left = 0b01,
        down = 0b10,
        right = 0b11,
    };

    pub fn moveLeft(self: *Tsumo) void {
        if (self.coord.x != @boolToInt(self.orientation == .left))
            self.coord.x -= 1;
    }

    pub fn moveRight(self: *Tsumo) void {
        if (self.coord.x < grid_width - (@as(u8, @boolToInt(self.orientation == .right)) + 1))
            self.coord.x += 1;
    }

    pub fn moveDown(self: *Tsumo) void {
        if (self.coord.y < grid_height - (@as(u8, @boolToInt(self.orientation == .down)) + 1))
            self.coord.y += 1;
    }

    /// TODO: Add logic for making the tsumo "pop" up depending on the board
    inline fn adjustCoord(self: *Tsumo) void {
        switch (self.orientation) {
            .left => if (self.coord.x == 0) {
                self.coord.x += 1;
            },
            .down => if (self.coord.y == grid_height - 1) {
                self.coord.y -= 1;
            },
            .right => if (self.coord.x == grid_width - 1) {
                self.coord.x -= 1;
            },
            else => {},
        }
    }

    pub fn rotateClockwise(self: *Tsumo) void {
        self.orientation = @intToEnum(Orientation, @enumToInt(self.orientation) -% 1);
        self.adjustCoord();
    }

    pub fn rotateCounterClockwise(self: *Tsumo) void {
        self.orientation = @intToEnum(Orientation, @enumToInt(self.orientation) +% 1);
        self.adjustCoord();
    }
};

pub const Puyo = struct {
    grid: [grid_height][grid_width]Sprite = [1][grid_width]Sprite{[1]Sprite{.{ .colour = .empty }} ** grid_width} ** grid_height,

    //pub fn initGrid(
    //    comptime SurfaceType: type,
    //    surface: SurfaceType,
    //    image: SurfaceType,
    //) !void {
    //    for (0..12) |y| {
    //        for (0..6) |x| {
    //            try surface.SDL_BlitSurface(image, .{ .x = x, .y = y });
    //        }
    //    }
    //}

    pub fn getSprite(self: Puyo, coord: Coord) Sprite {
        return self.grid[coord.y][coord.x];
    }
};
