const c = @cImport({
	@cInclude("SDL2/SDL.h");
	@cInclude("SDL2/SDL_ttf.h");
});

const std = @import("std");
const tetris = @import("./game.zig");

var renderer: ?*c.SDL_Renderer = null;
var font: ?*c.TTF_Font = null;

const CLEAR_COLOR = make_sdl_color(0x000000FF);

pub fn main() !void {
	if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to initialize SDL: %s", c.SDL_GetError());
		return error.SDLInitFailed;
	}
	defer c.SDL_Quit();

	const window = c.SDL_CreateWindow(
		"Tetris",
		c.SDL_WINDOWPOS_UNDEFINED,
		c.SDL_WINDOWPOS_UNDEFINED,
		tetris.WINDOW_WIDTH,
		tetris.WINDOW_HEIGHT,
		c.SDL_WINDOW_SHOWN
	) orelse {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to create window: %s", c.SDL_GetError());
		return error.SDLInitFailed;
	};
	defer c.SDL_DestroyWindow(window);

	renderer = c.SDL_CreateRenderer(
		window,
		-1,
		c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC
	) orelse {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to create renderer: %s", c.SDL_GetError());
		return error.SDLInitFailed;
	};
	defer c.SDL_DestroyRenderer(renderer);

	if (c.TTF_Init() != 0) {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to initialize TTF: %s", c.TTF_GetError());
		return error.SDLInitFailed;
	}
	defer c.TTF_Quit();

	font = c.TTF_OpenFont(tetris.FONT_NAME, tetris.FONT_SIZE) orelse {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to open font: %s", c.TTF_GetError());
		return error.SDLInitFailed;
	};
	defer c.TTF_CloseFont(font);

	tetris.Game_Init(@intCast(std.time.microTimestamp()));
	_ = tetris.Try_Spawn_Next_Mino();

	mainloop: while (true) {
		var event: c.SDL_Event = undefined;
		while (c.SDL_PollEvent(&event) != 0) {
			if (event.type == c.SDL_QUIT) {
				break :mainloop;
			}

			if (event.type == c.SDL_KEYDOWN) {
				tetris.Handle_Key_Down(event.key.keysym.sym);
			}
		}

		tetris.Update_Game_State();

		_ = c.SDL_SetRenderDrawColor(renderer, CLEAR_COLOR.r, CLEAR_COLOR.g, CLEAR_COLOR.b, CLEAR_COLOR.a);
		_ = c.SDL_RenderClear(renderer);

		tetris.Render_Game_State();

		c.SDL_RenderPresent(renderer);
	}
}

fn make_sdl_color(rgba: u32) c.SDL_Color {
	return .{
		.r = @truncate((rgba >> (3 * 8)) & 0xFF),
		.g = @truncate((rgba >> (2 * 8)) & 0xFF),
		.b = @truncate((rgba >> (1 * 8)) & 0xFF),
		.a = @truncate((rgba >> (0 * 8)) & 0xFF),
	};
}

export fn platform_draw_rect(x: i32, y: i32, width: i32, height: i32, rgba: u32) void {
	const color = make_sdl_color(rgba);
	_ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);

	const dest: c.SDL_Rect = .{ .x = x, .y = y, .w = width, .h = height };
	_ = c.SDL_RenderDrawRect(renderer, &dest);
}

export fn platform_fill_rect(x: i32, y: i32, width: i32, height: i32, rgba: u32) void {
	const color = make_sdl_color(rgba);
	_ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);

	const dest: c.SDL_Rect = .{ .x = x, .y = y, .w = width, .h = height };
	_ = c.SDL_RenderFillRect(renderer, &dest);
}

export fn platform_fill_text(x: i32, y: i32, text: [*c]const u8, rgba: u32) void {
	const color = make_sdl_color(rgba);

	const surface = c.TTF_RenderText_Blended(font, text, color) orelse {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to render text to surface: %s", c.TTF_GetError());
		return;
	};
	defer c.SDL_FreeSurface(surface);

	const texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to create texture from surface: %s", c.SDL_GetError());
		return;
	};
	defer c.SDL_DestroyTexture(texture);

	const dest: c.SDL_Rect = .{ .x = x, .y = y, .w = surface.*.w, .h = surface.*.h };
	_ = c.SDL_RenderCopy(renderer, texture, null, &dest);
}
