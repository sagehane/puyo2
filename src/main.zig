const std = @import("std");

const c = @import("c.zig");
const puyo = @import("puyo.zig");

const GameError = error{
    SDL,
    IMG,
    Other,
};

fn imgError() GameError {
    std.debug.print("IMG Error: {s}\n", .{c.IMG_GetError()});
    return error.IMG;
}

const puyo_size = 32;

// Some global variables
var g_renderer: *c.SDL_Renderer = undefined;
var g_window: *c.SDL_Window = undefined;
var g_puyo_texture: *c.SDL_Texture = undefined;

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
    sdl_main() catch |err| {
        switch (err) {
            error.SDL => std.debug.print("SDL Error: {s}\n", .{c.SDL_GetError()}),
            error.IMG => {},
            error.Other => {},
        }

        @panic("TODO: Think of a better message\n");
    };
    defer c.SDL_Quit();
}

/// Call the following after:
/// ```
/// defer c.SDL_Quit();
/// ```
fn sdl_main() GameError!void {
    try setup();
    defer c.SDL_DestroyWindow(g_window);
    defer c.SDL_DestroyTexture(g_puyo_texture);

    var tsumo = puyo.Tsumo{ .colour_1 = .red, .colour_2 = .blue };

    var event: c.SDL_Event = undefined;
    outer: while (true) {
        // TODO: https://lazyfoo.net/tutorials/SDL/25_capping_frame_rate/index.php
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
        _ = c.SDL_SetRenderDrawColor(g_renderer, 0x00, 0x00, 0x00, 0x00);
        _ = c.SDL_RenderClear(g_renderer);
        try initGrid(g_renderer);
        try renderTsumo(g_renderer, tsumo);
        c.SDL_RenderPresent(g_renderer);
    }
}

/// Call the following after:
/// ```
/// defer c.SDL_Quit();
/// defer c.SDL_DestroyWindow(g_window);
/// defer c.SDL_DestroyRenderer(g_renderer);
/// defer c.SDL_DestroyTexture(g_puyo_texture);
/// ```
fn setup() GameError!void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) return error.SDL;
    errdefer c.SDL_Quit();

    g_window = c.SDL_CreateWindow(
        "Puyo Puyo",
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        (2 * (8 + 3) + 1) * puyo_size,
        (1 + 13 + 3) * puyo_size,
        c.SDL_WINDOW_ALWAYS_ON_TOP & c.SDL_WINDOW_VULKAN,
    ) orelse return error.SDL;
    errdefer c.SDL_DestroyWindow(g_window);

    // TODO: Look into VSync
    g_renderer = c.SDL_CreateRenderer(g_window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC) orelse return error.SDL;
    errdefer c.SDL_DestroyRenderer(g_renderer);

    const img_flags = 0;
    if (c.IMG_Init(img_flags) & img_flags != img_flags) return imgError();
    defer c.IMG_Quit();
    g_puyo_texture = try getPuyoTexture(g_renderer);
}

/// Call the following after:
/// ```
/// defer c.SDL_DestroyTexture(g_puyo_texture);
/// ```
fn getPuyoTexture(renderer: *c.SDL_Renderer) GameError!*c.SDL_Texture {
    const tmp_surface = c.IMG_Load("resources/puyo_sozai.qoi") orelse return imgError();
    defer c.SDL_FreeSurface(tmp_surface);
    return c.SDL_CreateTextureFromSurface(renderer, tmp_surface) orelse error.SDL;
}

fn initGrid(renderer: *c.SDL_Renderer) GameError!void {
    const wall = &sprite_table[@bitCast(u7, puyo.Sprite{ .colour = .wall })];
    const background = &sprite_table[@bitCast(u7, puyo.Sprite{ .colour = .empty })];

    var y: c_int = 0;
    while (y < 12) : (y += 1) {
        if (c.SDL_RenderCopy(renderer, g_puyo_texture, wall, &tileToRect(0 + 1, y + 1, .{})) != 0) return error.SDL;

        if (c.SDL_RenderCopy(renderer, g_puyo_texture, wall, &tileToRect(7 + 1, y + 1, .{})) != 0) return error.SDL;

        var x: c_int = 0;
        while (x < 6) : (x += 1) {
            if (c.SDL_RenderCopy(renderer, g_puyo_texture, background, &tileToRect(x + 2, y + 1, .{})) != 0) return error.SDL;
        }
    }

    var x: c_int = 0;
    while (x < 8) : (x += 1) {
        if (c.SDL_RenderCopy(renderer, g_puyo_texture, wall, &tileToRect(x + 1, 12 + 1, .{})) != 0) return error.SDL;
    }
}

/// TODO: Add logic for printing with masks
/// TODO: Don't let puyos render above the grid
fn renderTsumo(renderer: *c.SDL_Renderer, tsumo: puyo.Tsumo) GameError!void {
    var x: i8 = tsumo.coord.x + 2;
    var y: i8 = tsumo.coord.y;

    if (c.SDL_RenderCopy(
        renderer,
        g_puyo_texture,
        &sprite_table[@bitCast(u7, puyo.Sprite{ .colour = tsumo.colour_1 })],
        &tileToRect(x, y, .{}),
    ) != 0) return error.SDL;

    switch (tsumo.orientation) {
        .default => y -= 1,
        .left => x -= 1,
        .reverse => y += 1,
        .right => x += 1,
    }

    if (c.SDL_RenderCopy(
        renderer,
        g_puyo_texture,
        &sprite_table[@bitCast(u7, puyo.Sprite{ .colour = tsumo.colour_2 })],
        &tileToRect(x, y, .{}),
    ) != 0) return error.SDL;
}
