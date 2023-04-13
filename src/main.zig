const std = @import("std");

const c = @import("c.zig");
const puyo = @import("puyo.zig");

test {
    std.testing.refAllDecls(puyo);
}

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
    puyo: puyo.Puyo = .{},
    puyo_texture: *c.SDL_Texture,
    renderer: *c.SDL_Renderer,
    window: *c.SDL_Window,

    fn init() GameError!Game {
        var game: Game = undefined;
        game.puyo = .{};

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
        const wall = &spriteToRect(puyo.Sprite{ .colour = .wall });
        const background = &spriteToRect(puyo.Sprite{ .colour = .empty });

        var y: i32 = 0;
        while (y < puyo.grid_height - 1) : (y += 1) {
            const y_offset = y + coord.y;
            if (c.SDL_RenderCopy(self.renderer, self.puyo_texture, wall, &tileToRect(coord.x, y_offset, .{})) != 0) return sdlError();

            if (c.SDL_RenderCopy(self.renderer, self.puyo_texture, wall, &tileToRect(coord.x + 7, y_offset, .{})) != 0) return sdlError();

            var x: i32 = 0;
            while (x < puyo.grid_width) : (x += 1) {
                const rect = &tileToRect(x + coord.x + 1, y_offset, .{});
                if (c.SDL_RenderCopy(self.renderer, self.puyo_texture, background, rect) != 0) return sdlError();

                const sprite = self.puyo.getSprite(.{ .x = @intCast(u4, x), .y = @intCast(u4, y) });
                if (c.SDL_RenderCopy(self.renderer, self.puyo_texture, &spriteToRect(sprite), rect) != 0) return sdlError();
            }
        }

        var x: c_int = coord.x;
        while (x < coord.x + puyo.grid_width + 2) : (x += 1) {
            if (c.SDL_RenderCopy(self.renderer, self.puyo_texture, wall, &tileToRect(x, coord.y + puyo.grid_height - 1, .{})) != 0) return sdlError();
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
            &spriteToRect(puyo.Sprite{ .colour = tsumo.colour_1 }),
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
            &spriteToRect(puyo.Sprite{ .colour = tsumo.colour_2 }),
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

inline fn spriteToRect(sprite: puyo.Sprite) c.SDL_Rect {
    return sprite_table[@bitCast(u7, sprite)];
}

const sprite_table = blk: {
    const w = 0x08;
    const h = 0x10;
    var table: [w * h]c.SDL_Rect = undefined;

    // The last index is an empty background
    table[std.math.maxInt(u7)] = tileToRect(5, 15, .{});

    table[0] = tileToRect(5, 1, .{});
    table[7] = tileToRect(5, 0, .{});

    for (1..7) |colour| {
        for (0..h) |mask| {
            table[mask * w + colour] = tileToRect(colour - 1, mask, .{});
        }
    }

    break :blk table;
};

pub fn main() void {
    sdl_main() catch {
        @panic("TODO: Think of a better message\n");
    };
}

fn sdl_main() GameError!void {
    var game = try Game.init();
    defer game.deinit();

    var tsumo = puyo.Tsumo{ .colour_1 = .red, .colour_2 = .blue };

    // Held keys of the previous frame
    var prev_key_mask: u8 = 0;
    // TODO: Consider putting this logic in `puyo.zig`
    var move_cooldowns: [3]u8 = .{ 0, 0, 0 };
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

        // Currently held keys
        const key_mask =
            key_states[c.SDL_SCANCODE_Q] |
            key_states[c.SDL_SCANCODE_A] << 1 |
            key_states[c.SDL_SCANCODE_S] << 2 |
            key_states[c.SDL_SCANCODE_D] << 3 |
            key_states[c.SDL_SCANCODE_O] << 4 |
            key_states[c.SDL_SCANCODE_P] << 5;
        defer prev_key_mask = key_mask;

        // Keys held for the first time
        const new_key_mask = key_mask & ~prev_key_mask;

        // TODO: The screen should close only if Q was pressed this frame
        // TODO: Basically, compare with the previous keyboard state
        if (keymod & c.KMOD_CTRL != 0 and new_key_mask & 1 != 0)
            break :outer;

        // TODO: Consider if it should be legal to press both O and P
        if (new_key_mask & 1 << 4 != 0) {
            tsumo.rotateCounterClockwise();
        }
        if (new_key_mask & 1 << 5 != 0) {
            tsumo.rotateClockwise();
        }

        // TODO: Consider making the movement an animation
        if (move_cooldowns[0] != 0)
            move_cooldowns[0] -= 1
        else if (key_mask & 0b1010 == 0b0010) {
            move_cooldowns[0] = 6;
            tsumo.moveLeft();
        }

        if (move_cooldowns[1] != 0)
            move_cooldowns[1] -= 1
        else if (key_mask & 0b1010 == 0b1000) {
            move_cooldowns[1] = 6;
            tsumo.moveRight();
        }

        if (move_cooldowns[2] != 0)
            move_cooldowns[2] -= 1
        else if (key_mask & 1 << 2 != 0) {
            move_cooldowns[2] = 6;
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
