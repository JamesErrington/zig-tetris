const c = @cImport({
	@cInclude("SDL2/SDL.h");
});

pub fn main() !void {
	if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
		c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
		return error.SDLInitFailed;
	}
	defer c.SDL_Quit();

	const window = c.SDL_CreateWindow(
		"Tetris",
		c.SDL_WINDOWPOS_UNDEFINED,
		c.SDL_WINDOWPOS_UNDEFINED,
		600,
		400,
		c.SDL_WINDOW_SHOWN
	) orelse {
		c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
		return error.SDLInitFailed;
	};
	defer c.SDL_DestroyWindow(window);

	const renderer = c.SDL_CreateRenderer(
		window,
		-1,
		c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC
	) orelse {
		c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
		return error.SDLInitFailed;
	};
	defer c.SDL_DestroyRenderer(renderer);

	mainloop: while (true) {
		var event: c.SDL_Event = undefined;
		while (c.SDL_PollEvent(&event) != 0) {
			switch (event.type) {
				c.SDL_QUIT => break :mainloop,
				else => {},
			}
		}

		_ = c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff);
        _ = c.SDL_RenderClear(renderer);

		_ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0xFF);
		const rect: c.SDL_Rect = .{ .x = 10, .y = 10, .w = 100, .h = 100 };
		_ = c.SDL_RenderDrawRect(renderer, &rect);

		c.SDL_RenderPresent(renderer);
	}
}
