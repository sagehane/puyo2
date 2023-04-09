pub const Data = struct {
    const grid_width = 6;
    const grid_height = 13;

    grid: [grid_height][grid_width]Colour,

    const Colour = enum(u3) {
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

    const AdjacentMask = packed struct(u4) {
        up: bool = false,
        down: bool = false,
        left: bool = false,
        right: bool = false,
    };

    pub const Sprite = packed struct(u7) {
        colour: Colour,
        mask: AdjacentMask = .{},
    };

    pub fn initGrid(
        comptime SurfaceType: type,
        surface: SurfaceType,
        image: SurfaceType,
    ) !void {
        for (0..12) |y| {
            for (0..6) |x| {
                try surface.SDL_BlitSurface(image, .{ .x = x, .y = y });
            }
        }
    }
};
