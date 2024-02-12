const std = @import("std");
const c = @cImport({
	@cInclude("SDL2/SDL.h");
});

const RndGen = std.rand.DefaultPrng;

const WINDOW_WIDTH = 1280;
const WINDOW_HEIGHT = 720;

const TILE_SIZE_PIXELS = 32;
const NUM_COLS = 10;
const NUM_ROWS = 20;

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

	var rand = RndGen.init(@intCast(std.time.microTimestamp()));

	var state = InitGameState();
	_ = TrySpawnRandomMino(&state, &rand.random());

	mainloop: while (true) {
		var event: c.SDL_Event = undefined;
		while (c.SDL_PollEvent(&event) != 0) {
			switch (event.type) {
				c.SDL_QUIT => break :mainloop,
				else => {},
			}
		}

		// Update Game State
		{
			state.frames_until_fall -= 1;
			if (state.frames_until_fall <= 0) {
				state.frames_until_fall = 48;

				if (state.active_mino) |active_mino| {
					state.active_mino.?.pos.y += 1;
					if (active_mino.pos.y >= NUM_ROWS) {
						state.active_mino.?.pos.y = 0;
					}
				}
			}
		}


		// Draw Game State
		{
			Set_Color(renderer, 0x00000000);
			_ = c.SDL_RenderClear(renderer);

			{
				var y: c_int = 0;
				while (y < state.field.len) {
					var x: c_int = 0;
					while (x < state.field[0].len) {

						var color: u32 = @intFromEnum(Color.DARK_GREY);

						if (state.field[@intCast(y)][@intCast(x)] != -1) {
							color = @intFromEnum(Color.BLUE);
						}
						Fill_Rect(renderer, x * TILE_SIZE_PIXELS, y * TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, color);
						Draw_Rect(renderer, x * TILE_SIZE_PIXELS, y * TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
						x += 1;
					}
					y += 1;
				}
			}

			{
				if (state.active_mino) |active_mino| {
					for (Minoes[@intCast(@intFromEnum(active_mino.type))].rotations[0]) |offsets| {
						const x = active_mino.pos.x + offsets.x;
						const y = active_mino.pos.y + offsets.y;
						Fill_Rect(renderer, x * TILE_SIZE_PIXELS, y * TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.BLUE));
					}
				}
			}


			c.SDL_RenderPresent(renderer);
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

fn Set_Color(renderer: *c.SDL_Renderer, rgba: u32) callconv(.Inline) void {
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

const MinoType = enum(i8) {
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
	color: Color,
	rotations: [NUM_ROTATIONS][4]Point,
};

const Color = enum(u32) {
	CYAN 		= 0x00FFFF00,
	BLUE 		= 0x0000FF00,
	ORANGE 		= 0xFF7F0000,
	YELLOW 		= 0xFFFF0000,
	PURPLE 		= 0x80008000,
	GREEN 		= 0x00FF0000,
	RED 		= 0xFF000000,
	DARK_GREY	= 0x20202000,
	LIGHT_GREY 	= 0x40404000,
	BLACK		= 0x00000000,
};

const Minoes = [3]MinoDef{
	.{
		.type = .TYPE_I,
		.color = .CYAN,
		.rotations = [NUM_ROTATIONS][4]Point{
			[_]Point{ .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 }, .{ .x = 3, .y = 1 } },
			[_]Point{ .{ .x = 2, .y = 0 }, .{ .x = 2, .y = 1 }, .{ .x = 2, .y = 2 }, .{ .x = 2, .y = 3 } },
			[_]Point{ .{ .x = 3, .y = 2 }, .{ .x = 2, .y = 2 }, .{ .x = 1, .y = 2 }, .{ .x = 0, .y = 2 } },
			[_]Point{ .{ .x = 1, .y = 3 }, .{ .x = 1, .y = 2 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 0 } },
		},
	},
	.{
		.type = .TYPE_J,
		.color = .BLUE,
		.rotations = [NUM_ROTATIONS][4]Point{
			[_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 } },
			[_]Point{ .{ .x = 2, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 2 } },
			[_]Point{ .{ .x = 2, .y = 2 }, .{ .x = 2, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 1 } },
			[_]Point{ .{ .x = 0, .y = 2 }, .{ .x = 1, .y = 2 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 0 } },
		},
	},
	.{
		.type = .TYPE_L,
		.color = .ORANGE,
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

const GameState = struct {
	field: [NUM_ROWS][NUM_COLS]i8,
	active_mino: ?MinoInstance,
	frames_until_fall: isize,
};

fn InitGameState() GameState {
	return .{
		.field = [_][NUM_COLS]i8{ [_]i8{ -1 } ** NUM_COLS } ** NUM_ROWS,
		.active_mino = null,
		.frames_until_fall = 48,
	};
}

// Try to spawn a random new Mino at the starting location, which is centered on the top row.
// The MinoType is random but the rotation is always ROTATION_0.
fn TrySpawnRandomMino(state: *GameState, rand: *const std.rand.Random) bool {
	// const type = rand.*.uintLessThan(u8, NUM_MINO_TYPES);
	const mino_type = rand.*.uintLessThan(u8, 3);

	const active_mino: MinoInstance = .{
		.pos = .{ .x = @divFloor(NUM_COLS, 2) - 2, .y = 0 },
		.type =  @enumFromInt(mino_type),
		.rotation = .ROTATION_0,
	};

	state.*.active_mino = active_mino;
	state.*.frames_until_fall = 48;

	return true;
}
