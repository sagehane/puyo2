const std = @import("std");

const c = @import("c.zig");
const puyo = @import("puyo.zig");

const GameError = error{
    C,
    Other,
};

fn imgError() GameError {
    std.debug.print("IMG Error: {s}\n", .{c.IMG_GetError()});
    return error.C;
}

fn sdlError() GameError {
    std.debug.print("SDL Error: {s}\n", .{c.SDL_GetError()});
    return error.C;
}

const puyo_size = 32;

const Coord = packed struct(u64) {
    x: i32 = 0,
    y: i32 = 0,
};

const Game = struct {
    puyo_texture: *c.SDL_Texture,
    renderer: *c.SDL_Renderer,
    window: *c.SDL_Window,

    fn init() GameError!Game {
        var game: Game = undefined;

        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) return sdlError();
        errdefer c.SDL_Quit();

        game.window = c.SDL_CreateWindow(
            "Puyo Puyo",
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            (2 * (8 + 3) + 1) * puyo_size,
            (1 + 13 + 3) * puyo_size,
            c.SDL_WINDOW_ALWAYS_ON_TOP & c.SDL_WINDOW_VULKAN,
        ) orelse return sdlError();
        errdefer c.SDL_DestroyWindow(game.window);

        // TODO: Look into VSync
        game.renderer = c.SDL_CreateRenderer(game.window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC) orelse return sdlError();
        errdefer c.SDL_DestroyRenderer(game.renderer);

        const img_flags = 0;
        if (c.IMG_Init(img_flags) & img_flags != img_flags) return imgError();
        defer c.IMG_Quit();
        game.puyo_texture = try getPuyoTexture(game.renderer);

        return game;
    }

    fn deinit(self: Game) void {
        c.SDL_DestroyTexture(self.puyo_texture);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    fn renderGrid(self: Game, coord: Coord) GameError!void {
        const w = puyo.grid_width;
        const h = puyo.grid_height - 1;
        const wall = &sprite_table[@bitCast(u7, puyo.Sprite{ .colour = .wall })];
        const background = &sprite_table[@bitCast(u7, puyo.Sprite{ .colour = .empty })];

        var y: c_int = coord.y;
        while (y < coord.y + h) : (y += 1) {
            if (c.SDL_RenderCopy(self.renderer, self.puyo_texture, wall, &tileToRect(coord.x, y, .{})) != 0) return sdlError();

            if (c.SDL_RenderCopy(self.renderer, self.puyo_texture, wall, &tileToRect(coord.x + 7, y, .{})) != 0) return sdlError();

            var x: c_int = coord.x;
            while (x < coord.x + w) : (x += 1) {
                if (c.SDL_RenderCopy(self.renderer, self.puyo_texture, background, &tileToRect(x + 1, y, .{})) != 0) return sdlError();
            }
        }

        var x: c_int = coord.x;
        while (x < coord.x + w + 2) : (x += 1) {
            if (c.SDL_RenderCopy(self.renderer, self.puyo_texture, wall, &tileToRect(x, coord.y + h, .{})) != 0) return sdlError();
        }
    }

    /// TODO: Add logic for printing with masks
    /// TODO: Don't let puyos render above the grid
    fn renderTsumo(self: Game, tsumo: puyo.Tsumo, coord: Coord) GameError!void {
        var x: i32 = tsumo.coord.x + coord.x + 1;
        var y: i32 = tsumo.coord.y + coord.y - 1;

        if (c.SDL_RenderCopy(
            self.renderer,
            self.puyo_texture,
            &sprite_table[@bitCast(u7, puyo.Sprite{ .colour = tsumo.colour_1 })],
            &tileToRect(x, y, .{}),
        ) != 0) return sdlError();

        switch (tsumo.orientation) {
            .up => y -= 1,
            .left => x -= 1,
            .down => y += 1,
            .right => x += 1,
        }

        if (c.SDL_RenderCopy(
            self.renderer,
            self.puyo_texture,
            &sprite_table[@bitCast(u7, puyo.Sprite{ .colour = tsumo.colour_2 })],
            &tileToRect(x, y, .{}),
        ) != 0) return sdlError();
    }
};

inline fn tileToRect(
    x: c_int,
    y: c_int,
    offset: struct { x: c_int = 0, y: c_int = 0 },
) c.SDL_Rect {
    return .{
        .x = x * puyo_size + offset.x,
        .y = y * puyo_size + offset.y,
        .w = puyo_size,
        .h = puyo_size,
    };
}

const sprite_table = blk: {
    var table: [8 * 16]c.SDL_Rect = undefined;

    // The last index is an empty background
    table[std.math.maxInt(u7)] = tileToRect(5, 15, .{});

    table[0] = tileToRect(5, 1, .{});
    table[7] = tileToRect(5, 0, .{});

    for (1..7) |colour| {
        for (0..16) |mask| {
            table[mask * 8 + colour] = tileToRect(colour - 1, mask, .{});
        }
    }

    break :blk table;
};

test {
    // To run nested container tests, either, call `refAllDecls` which will
    // reference all declarations located in the given argument.
    // `@This()` is a builtin function that returns the innermost container it is called from.
    // In this example, the innermost container is this file (implicitly a struct).
    std.testing.refAllDecls(@This());

    _ = puyo;
}

pub fn main() void {
    sdl_main() catch {
        @panic("TODO: Think of a better message\n");
    };
}

fn sdl_main() GameError!void {
    var game = try Game.init();
    defer game.deinit();

    var tsumo = puyo.Tsumo{ .colour_1 = .red, .colour_2 = .blue };

    var event: c.SDL_Event = undefined;
    outer: while (true) {
        // TODO: https://lazyfoo.net/tutorials/SDL/25_capping_frame_rate/index.php
        // or https://www.gafferongames.com/post/fix_your_timestep/
        c.SDL_Delay(1000 / 60);

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => break :outer,
                else => {},
            }
        }

        const keymod = c.SDL_GetModState();
        const key_states = c.SDL_GetKeyboardState(null);

        // TODO: The screen should close only if Q was pressed this frame
        // TODO: Basically, compare with the previous keyboard state
        if (keymod & c.KMOD_CTRL != 0 and key_states[c.SDL_SCANCODE_Q] != 0)
            break :outer;

        // TODO: Slow down movement and handle cases when both keys are held simultaneously
        if (key_states[c.SDL_SCANCODE_A] != 0) {
            tsumo.moveLeft();
        }
        if (key_states[c.SDL_SCANCODE_D] != 0) {
            tsumo.moveRight();
        }
        if (key_states[c.SDL_SCANCODE_O] != 0) {
            tsumo.rotateCounterClockwise();
        }
        if (key_states[c.SDL_SCANCODE_P] != 0) {
            tsumo.rotateClockwise();
        }
        if (key_states[c.SDL_SCANCODE_S] != 0) {
            tsumo.moveDown();
        }

        // TODO: Make a separate texture/window/whatever for the grid
        // TODO: Check docs
        _ = c.SDL_SetRenderDrawColor(game.renderer, 0x00, 0x00, 0x00, 0x00);
        _ = c.SDL_RenderClear(game.renderer);
        try game.renderGrid(.{ .x = 1, .y = 1 });
        try game.renderTsumo(tsumo, .{ .x = 1, .y = 1 });
        c.SDL_RenderPresent(game.renderer);
    }
}

/// Call the following after:
/// ```
/// defer c.SDL_DestroyTexture(g_puyo_texture);
/// ```
fn getPuyoTexture(renderer: *c.SDL_Renderer) GameError!*c.SDL_Texture {
    const tmp_surface = c.IMG_Load("resources/puyo_sozai.qoi") orelse return imgError();
    defer c.SDL_FreeSurface(tmp_surface);
    return c.SDL_CreateTextureFromSurface(renderer, tmp_surface) orelse sdlError();
}
