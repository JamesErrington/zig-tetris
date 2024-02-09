const c = @cImport({
	@cInclude("SDL2/SDL.h");
});

const TILE_SIZE_PIXELS = 32;
const NUM_COLS = 12;
const NUM_ROWS = 22;

const WINDOW_WIDTH = 1280;
const WINDOW_HEIGHT = 720;

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
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
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

	var rot: usize = 0;

	mainloop: while (true) {
		var event: c.SDL_Event = undefined;
		while (c.SDL_PollEvent(&event) != 0) {
			switch (event.type) {
				c.SDL_QUIT => break :mainloop,
				else => {},
			}
		}

		// Update Game State

		// Draw Game State
		{
			Set_Color(renderer, 0x00000000);
			_ = c.SDL_RenderClear(renderer);

			var i: c_int = 0;
			while (i < 3) {
				const active: MinoInstance = .{
					.pos = .{ .x = i * 5, .y = 5 },
					.type = @enumFromInt(i),
					.rotation = @enumFromInt(rot),
				};

				const mino = Minoes[@intFromEnum(active.type)];
				for (mino.rotations[@intFromEnum(active.rotation)]) |offset| {
					Fill_Rect(
						renderer,
						(active.pos.x + offset.x) * TILE_SIZE_PIXELS,
						(active.pos.y + offset.y) * TILE_SIZE_PIXELS,
						TILE_SIZE_PIXELS,
						TILE_SIZE_PIXELS,
						@intFromEnum(mino.color),
					);
				}

				i += 1;
			}

			c.SDL_RenderPresent(renderer);

			rot = (rot + 1) % NUM_ROTATIONS;
			c.SDL_Delay(500);
		}
	}
}

fn Make_SDL_Color(rgba: u32) c.SDL_Color {
	return .{
		.r = @truncate((rgba >> (3 * 8)) & 0xFF),
		.g = @truncate((rgba >> (2 * 8)) & 0xFF),
		.b = @truncate((rgba >> (1 * 8)) & 0xFF),
		.a = @truncate((rgba >> (0 * 8)) & 0xFF),
	};
}

inline fn Set_Color(renderer: *c.SDL_Renderer, rgba: u32) void {
	const color = Make_SDL_Color(rgba);
	_ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
}

fn Draw_Rect(renderer: *c.SDL_Renderer, x: c_int, y: c_int, w: c_int, h: c_int, rgba: u32) void {
	Set_Color(renderer, rgba);

	const rect: c.SDL_Rect = .{ .x = x, .y = y, .w = w, .h = h};
	_ = c.SDL_RenderDrawRect(renderer, &rect);
}

fn Fill_Rect(renderer: *c.SDL_Renderer, x: c_int, y: c_int, w: c_int, h: c_int, rgba: u32) void {
	Set_Color(renderer, rgba);

	const rect: c.SDL_Rect = .{ .x = x, .y = y, .w = w, .h = h};
	_ = c.SDL_RenderFillRect(renderer, &rect);
}

const Rotation = enum(u8) {
	ROTATION_0,
	ROTATION_90,
	ROTATION_180,
	ROTATION_270,
	NUM_ROTATIONS,
};
const NUM_ROTATIONS = @intFromEnum(Rotation.NUM_ROTATIONS);

const MinoType = enum(u8) {
	TYPE_I,
	TYPE_J,
	TYPE_L,
	TYPE_O,
	TYPE_S,
	TYPE_T,
	TYPE_Z,
	NUM_MINO_TYPES,
};
const NUM_MINO_TYPES = @intFromEnum(MinoType.NUM_MINO_TYPES);

const Point = struct {
	x: c_int,
	y: c_int,
};

const MinoDef = struct {
	type: MinoType,
	color: MinoColor,
	rotations: [NUM_ROTATIONS][4]Point,
};

const MinoColor = enum(u32) {
	COLOR_CYAN = 0x00FFFF00,
	COLOR_BLUE = 0x0000FF00,
	COLOR_ORANGE = 0xFF7F0000,
	COLOR_YELLOW = 0xFFFF0000,
	COLOR_PURPLE = 0x80008000,
	COLOR_GREEN = 0x00FF0000,
	COLOR_RED = 0xFF000000,
};

const Minoes = [3]MinoDef{
	.{
		.type = .TYPE_I,
		.color = .COLOR_CYAN,
		.rotations = [NUM_ROTATIONS][4]Point{
			[_]Point{ .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 }, .{ .x = 3, .y = 1 } },
			[_]Point{ .{ .x = 2, .y = 0 }, .{ .x = 2, .y = 1 }, .{ .x = 2, .y = 2 }, .{ .x = 2, .y = 3 } },
			[_]Point{ .{ .x = 3, .y = 2 }, .{ .x = 2, .y = 2 }, .{ .x = 1, .y = 2 }, .{ .x = 0, .y = 2 } },
			[_]Point{ .{ .x = 1, .y = 3 }, .{ .x = 1, .y = 2 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 0 } },
		},
	},
	.{
		.type = .TYPE_J,
		.color = .COLOR_BLUE,
		.rotations = [NUM_ROTATIONS][4]Point{
			[_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 } },
			[_]Point{ .{ .x = 2, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 2 } },
			[_]Point{ .{ .x = 2, .y = 2 }, .{ .x = 2, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 1 } },
			[_]Point{ .{ .x = 0, .y = 2 }, .{ .x = 1, .y = 2 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 0 } },
		},
	},
	.{
		.type = .TYPE_L,
		.color = .COLOR_ORANGE,
		.rotations = [NUM_ROTATIONS][4]Point{
			[_]Point{ .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 }, .{ .x = 2, .y = 0 } },
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 2 }, .{ .x = 2, .y = 2 } },
			[_]Point{ .{ .x = 2, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 1 }, .{ .x = 0, .y = 2 } },
			[_]Point{ .{ .x = 1, .y = 2 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0 } },
		},
	},
};

const MinoInstance = struct {
	pos: Point,
	type: MinoType,
	rotation: Rotation,
};
