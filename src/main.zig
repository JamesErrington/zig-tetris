const std = @import("std");
const c = @cImport({
	@cInclude("SDL2/SDL.h");
});

const assert = std.debug.assert;
const RndGen = std.rand.DefaultPrng;

const WINDOW_WIDTH = 1280;
const WINDOW_HEIGHT = 720;

const TILE_SIZE_PIXELS = 32;
const NUM_COLS = 10;
const NUM_ROWS = 20;

const FIELD_WIDTH_PIXELS = TILE_SIZE_PIXELS * NUM_COLS;
const FIELD_HEIGHT_PIXELS = TILE_SIZE_PIXELS * NUM_ROWS;
const FIELD_X_OFFSET = (WINDOW_WIDTH / 2) - (FIELD_WIDTH_PIXELS / 2);
const FIELD_Y_OFFSET = WINDOW_HEIGHT - FIELD_HEIGHT_PIXELS;

comptime {
	assert(FIELD_X_OFFSET > 0 and FIELD_X_OFFSET < WINDOW_WIDTH);
	assert(FIELD_Y_OFFSET > 0 and FIELD_Y_OFFSET < WINDOW_HEIGHT);
}

const FRAMES_PER_DROP = 30;

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

	var state = init_game_state(&rand.random());
	_ = try_spawn_next_mino(&state, &rand.random());

	mainloop: while (true) {
		var event: c.SDL_Event = undefined;
		while (c.SDL_PollEvent(&event) != 0) {
			if (event.type == c.SDL_QUIT) {
				break :mainloop;
			}

			if (event.type == c.SDL_KEYDOWN) {
				switch (event.key.keysym.sym) {
					c.SDLK_UP => {
						state.active_mino.rotation = next_rotation(state.active_mino.rotation);
					},
					c.SDLK_DOWN => {
						var future_mino = state.active_mino;
						future_mino.pos.y += 1;

						if (!check_collision(&state, &future_mino)) {
							state.active_mino.pos = future_mino.pos;
						}
					},
					c.SDLK_LEFT => {
						var future_mino = state.active_mino;
						future_mino.pos.x -= 1;

						if (!check_collision(&state, &future_mino)) {
							state.active_mino.pos = future_mino.pos;
						}
					},
					c.SDLK_RIGHT => {
						var future_mino = state.active_mino;
						future_mino.pos.x += 1;

						if (!check_collision(&state, &future_mino)) {
							state.active_mino.pos = future_mino.pos;
						}
					},
					else => {},
				}
			}
		}

		// Update Game State
		{
			state.frames_until_drop -= 1;
			if (state.frames_until_drop <= 0) {
			state.frames_until_drop = FRAMES_PER_DROP;

				var future_mino = state.active_mino;
				future_mino.pos.y += 1;

				if (check_collision(&state, &future_mino)) {
					add_active_mino_to_field(&state);

					const valid_spawn = try_spawn_next_mino(&state, &rand.random());
					if (!valid_spawn) {
						std.debug.print("FINISHED! You scored {}\n", .{state.lines_cleared});
					}
				} else {
					state.active_mino.pos.y = future_mino.pos.y;
				}
			}
		}


		// Draw Game State
		{
			Set_Color(renderer, 0x00000000);
			_ = c.SDL_RenderClear(renderer);

			{ // Static field
				var y: c_int = 0;
				while (y < state.field.len) : (y += 1) {
					var x: c_int = 0;
					while (x < state.field[0].len) : (x += 1) {

						var color: u32 = @intFromEnum(Color.DARK_GREY);

						if (state.field[@intCast(y)][@intCast(x)] != EMPTY_SPACE) {
							color = @intFromEnum(Color.BLUE);
						}

						const dx = FIELD_X_OFFSET + x * TILE_SIZE_PIXELS;
						const dy = FIELD_Y_OFFSET + y * TILE_SIZE_PIXELS;

						Fill_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, color);
						Draw_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
					}
				}
			}

			{ // Active mino
				const active_mino = state.active_mino;
				for (Minoes[@intCast(@intFromEnum(active_mino.type))].rotations[@intFromEnum(active_mino.rotation)]) |offsets| {
					const x = active_mino.pos.x + offsets.x;
					const y = active_mino.pos.y + offsets.y;

					const dx = FIELD_X_OFFSET + x * TILE_SIZE_PIXELS;
					const dy = FIELD_Y_OFFSET + y * TILE_SIZE_PIXELS;
					Fill_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.BLUE));
					Draw_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
				}
			}

			{ // Next mino
				const next_mino = state.next_mino;
				const x_offset = (WINDOW_WIDTH / 2) + FIELD_WIDTH_PIXELS;
				const y_offset = (WINDOW_HEIGHT / 2);

				for (Minoes[@intCast(@intFromEnum(next_mino.type))].rotations[@intFromEnum(next_mino.rotation)]) |offsets| {
					const x = next_mino.pos.x + offsets.x;
					const y = next_mino.pos.y + offsets.y;

					const dx = x_offset + x * TILE_SIZE_PIXELS;
					const dy = y_offset + y * TILE_SIZE_PIXELS;
					Fill_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.BLUE));
					Draw_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
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
};
const NUM_ROTATIONS = @typeInfo(Rotation).Enum.fields.len;

fn next_rotation(rot: Rotation) callconv(.Inline) Rotation {
	return @enumFromInt((@intFromEnum(rot) + 1) % NUM_ROTATIONS);
}

const MinoTypeTag = i8;
const MinoType = enum(MinoTypeTag) {
	TYPE_I,
	TYPE_J,
	TYPE_L,
	TYPE_O,
	TYPE_S,
	TYPE_T,
	TYPE_Z,
};
const NUM_MINO_TYPES = @typeInfo(MinoType).Enum.fields.len;
const EMPTY_SPACE: MinoTypeTag = -1;

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

const GameInput = enum {
	ROTATE,
	MOVE_LEFT,
	MOVE_RIGHT,
};

const MinoInstance = struct {
	pos: Point,
	type: MinoType,
	rotation: Rotation,
};

const GameState = struct {
	field: [NUM_ROWS][NUM_COLS]MinoTypeTag,
	active_mino: MinoInstance,
	next_mino: MinoInstance,
	frames_until_drop: isize,
	lines_cleared: usize,
};

fn init_game_state(rand: *const std.rand.Random) GameState {
	return .{
		.field = [_][NUM_COLS]MinoTypeTag{ [_]MinoTypeTag{ EMPTY_SPACE } ** NUM_COLS } ** NUM_ROWS,
		.active_mino = .{
			.pos = .{ .x = 0, .y = 0 },
			.type = .TYPE_I,
			.rotation = .ROTATION_0,
		},
		.next_mino = random_mino(rand),
		.frames_until_drop = FRAMES_PER_DROP,
		.lines_cleared = 0,
	};
}

fn random_mino(rand: *const std.rand.Random) MinoInstance {
	// const type = rand.*.uintLessThan(u8, NUM_MINO_TYPES);
	const mino_type = rand.*.uintLessThan(u8, 3);

	return .{
		.pos = .{ .x = 0, .y = 0 },
		.type =  @enumFromInt(mino_type),
		.rotation = .ROTATION_0,
	};
}

fn try_spawn_next_mino(state: *GameState, rand: *const std.rand.Random) bool {
	var active_mino: MinoInstance = state.*.next_mino;
	active_mino.pos = .{ .x = @divFloor(NUM_COLS, 2) - 2, .y = 0 };

	if (check_collision(state, &active_mino)) {
		return false;
	}

	state.*.active_mino = active_mino;
	state.*.frames_until_drop = FRAMES_PER_DROP;

	state.*.next_mino = random_mino(rand);

	return true;
}

fn check_collision(state: *const GameState, mino: *const MinoInstance) bool {
	for (Minoes[@intCast(@intFromEnum(mino.type))].rotations[@intFromEnum(mino.rotation)]) |offsets| {
		const x = mino.pos.x + offsets.x;
		const y = mino.pos.y + offsets.y;

		if ((x < 0) or (x >= NUM_COLS) or (y < 0) or (y >= NUM_ROWS) or (state.*.field[@intCast(y)][@intCast(x)] != EMPTY_SPACE)) {
			return true;
		}
	}

	return false;
}

fn add_active_mino_to_field(state: *GameState) void {
	const active_mino = state.active_mino;
	for (Minoes[@intCast(@intFromEnum(active_mino.type))].rotations[@intFromEnum(active_mino.rotation)]) |offsets| {
		const x = active_mino.pos.x + offsets.x;
		const y = active_mino.pos.y + offsets.y;

		state.*.field[@intCast(y)][@intCast(x)] = @intFromEnum(active_mino.type);
	}

	// Clear the full rows
	var n_cleared: usize = 0;
	var y: usize = 0;
	while (y < state.field.len) : (y += 1) {
		var is_full = true;

		var x: usize = 0;
		while (x < state.field[0].len) : (x += 1) {
			if (state.field[y][x] == EMPTY_SPACE) {
				is_full = false;
				break;
			}
		}

		// We need to drop the blocks above down
		if (is_full) {
			n_cleared += 1;
			var yy: usize = y;
			while (yy > 0) : (yy -= 1) {
				var xx: usize = 0;
				while (xx < state.field[0].len) : (xx += 1) {
					state.field[yy][xx] = state.field[yy - 1][xx];
				}
			}
		}
	}

	state.lines_cleared += n_cleared;
}
