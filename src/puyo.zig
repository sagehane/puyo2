const std = @import("std");
const testing = std.testing;

pub const grid_width = 6;
pub const grid_height = 13;

pub const Coord = packed struct(u8) {
    x: u4,
    y: u4,

    const cross_coord = Coord{ .x = 3, .y = 0 };
};

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
        try testing.expectEqual(0x00, @bitCast(Sprite{ .colour = .empty }));
        try testing.expectEqual(0x01, @bitCast(Sprite{ .colour = .red }));
        try testing.expectEqual(0x02, @bitCast(Sprite{ .colour = .green }));
        try testing.expectEqual(0x03, @bitCast(Sprite{ .colour = .blue }));
        try testing.expectEqual(0x04, @bitCast(Sprite{ .colour = .yellow }));
        try testing.expectEqual(0x05, @bitCast(Sprite{ .colour = .purple }));
        try testing.expectEqual(0x06, @bitCast(Sprite{ .colour = .garbage }));
        try testing.expectEqual(0x07, @bitCast(Sprite{ .colour = .wall }));
    }
};

/// TODO: Consider scrapping this and handling it on SDL's side
pub const Tsumo = packed struct(u16) {
    colour_1: Colour,
    colour_2: Colour,
    orientation: Orientation = .up,
    /// Coord of colour_1
    coord: Coord = Coord.cross_coord,

    const Orientation = enum(u2) {
        up = 0b00,
        left = 0b01,
        down = 0b10,
        right = 0b11,
    };

    pub fn getCoords(self: Tsumo, coords: *[2]Coord) usize {
        coords.* = [1]Coord{self.coord} ** 2;

        switch (self.orientation) {
            .up => coords[1].y -%= 1,
            .left => coords[1].x -= 1,
            .down => coords[1].y += 1,
            .right => coords[1].x += 1,
        }

        return @as(usize, ~@intFromBool(self.coord.y == 0 and self.orientation == .up)) + 1;
    }

    // TODO: Check the board to see if moving is possible
    pub fn moveLeft(self: *Tsumo) void {
        if (self.coord.x != @intFromBool(self.orientation == .left))
            self.coord.x -= 1;
    }

    pub fn moveRight(self: *Tsumo) void {
        if (self.coord.x < grid_width - (@as(u8, @intFromBool(self.orientation == .right)) + 1))
            self.coord.x += 1;
    }

    pub fn moveDown(self: *Tsumo) void {
        if (self.coord.y < grid_height - (@as(u8, @intFromBool(self.orientation == .down)) + 1))
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
        self.orientation = @enumFromInt(@intFromEnum(self.orientation) -% 1);
        self.adjustCoord();
    }

    pub fn rotateCounterClockwise(self: *Tsumo) void {
        self.orientation = @enumFromInt(@intFromEnum(self.orientation) +% 1);
        self.adjustCoord();
    }
};

pub const Puyo = struct {
    grid: [grid_height][grid_width]Sprite = [1][grid_width]Sprite{[1]Sprite{.{ .colour = .empty }} ** grid_width} ** grid_height,

    pub inline fn getSprite(self: Puyo, coord: Coord) Sprite {
        return self.grid[coord.y][coord.x];
    }

    pub inline fn getSpritePtr(self: *Puyo, coord: Coord) *Sprite {
        return &self.grid[coord.y][coord.x];
    }

    inline fn isBottom(self: Puyo, coord: Coord) bool {
        var below = coord;
        below.y +%= 1;

        return coord.y == grid_height - 1 or self.getSprite(below).colour != .empty;
    }

    inline fn getBottom(self: Puyo, coord: Coord) Coord {
        var tmp_coord = coord;
        while (!self.isBottom(tmp_coord))
            tmp_coord.y += 1;

        return tmp_coord;
    }

    pub fn tsumoIsAtBottom(self: Puyo, tsumo: Tsumo) bool {
        var coords: [2]Coord = undefined;
        var len = tsumo.getCoords(&coords);

        for (coords[0..len]) |coord| {
            if (self.isBottom(coord))
                return true;
        }

        return false;
    }

    /// Returns `false` if the game ended
    pub fn placeTsumo(self: *Puyo, tsumo: Tsumo) bool {
        var coords: [2]Coord = undefined;
        var len = tsumo.getCoords(&coords);

        if (tsumo.orientation == .up or tsumo.orientation == .down) {
            for (coords[0..len], ([2]Colour{ tsumo.colour_1, tsumo.colour_2 })[0..len]) |*coord, colour| {
                self.getSpritePtr(coord.*).* = .{ .colour = colour };
            }
        } else {
            for (coords[0..len], ([2]Colour{ tsumo.colour_1, tsumo.colour_2 })[0..len]) |*coord, colour| {
                self.getSpritePtr(self.getBottom(coord.*)).* = .{ .colour = colour };
            }
        }

        return self.getSprite(Coord.cross_coord).colour == .empty;
    }
};
