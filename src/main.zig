const std = @import("std");
const c = @cImport({
	@cInclude("SDL2/SDL.h");
	@cInclude("SDL2/SDL_ttf.h");
});

const assert = std.debug.assert;
const allocator = std.heap.c_allocator;
const RndGen = std.rand.DefaultPrng;

const TILE_SIZE_PIXELS = 32;
const NUM_COLS = 10;
const NUM_ROWS = 20;

const WINDOW_X_PADDING = 20;
const WINDOW_Y_PADDING = 20;
const FIELD_WIDTH_PIXELS = TILE_SIZE_PIXELS * NUM_COLS;
const FIELD_HEIGHT_PIXELS = TILE_SIZE_PIXELS * NUM_ROWS;

const WINDOW_WIDTH = 2 * (FIELD_WIDTH_PIXELS + WINDOW_X_PADDING);
const WINDOW_HEIGHT = FIELD_HEIGHT_PIXELS + (2 * WINDOW_Y_PADDING);

const FIELD_X_OFFSET = WINDOW_X_PADDING;
const FIELD_Y_OFFSET = WINDOW_Y_PADDING;

const NEXT_MINO_X_OFFSET = (3 * WINDOW_WIDTH / 4) - (2 * TILE_SIZE_PIXELS);
const NEXT_MINO_Y_OFFSET = (WINDOW_HEIGHT / 2) - TILE_SIZE_PIXELS;

const GAME_START_TEXT_X_OFFSET = (3 * WINDOW_WIDTH / 4) - 130;
const GAME_START_TEXT_Y_OFFSET = 50;

const FONT_NAME = "OpenSans-Regular.ttf";
const FONT_SIZE = 28;

const FRAMES_PER_DROP = 30;

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
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		c.SDL_WINDOW_SHOWN
	) orelse {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to create window: %s", c.SDL_GetError());
		return error.SDLInitFailed;
	};
	defer c.SDL_DestroyWindow(window);

	const renderer = c.SDL_CreateRenderer(
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

	const font = c.TTF_OpenFont(FONT_NAME, FONT_SIZE) orelse {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to open font: %s", c.TTF_GetError());
		return error.SDLInitFailed;
	};
	defer c.TTF_CloseFont(font);

	var rand = RndGen.init(@intCast(std.time.microTimestamp()));

	var app_state: AppState = .GAME_NOT_STARTED;

	var state = init_game_state(&rand.random());
	_ = try_spawn_next_mino(&state, &rand.random());

	mainloop: while (true) {
		var event: c.SDL_Event = undefined;
		while (c.SDL_PollEvent(&event) != 0) {
			if (event.type == c.SDL_QUIT) {
				break :mainloop;
			}

			if (app_state == .GAME_NOT_STARTED or app_state == .GAME_OVER) {
				if (event.type == c.SDL_KEYDOWN) {
					switch (event.key.keysym.sym) {
						c.SDLK_SPACE => {
							state = init_game_state(&rand.random());
							_ = try_spawn_next_mino(&state, &rand.random());
							app_state = .GAME_PLAYING;
						},
						else => {},
					}
				}
			}

			if (app_state == .GAME_PLAYING) {
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
		}

		// Update Game State
		{
			if (app_state == .GAME_PLAYING) {
				state.frames_until_drop -= 1;
				if (state.frames_until_drop <= 0) {
				state.frames_until_drop = FRAMES_PER_DROP;

					var future_mino = state.active_mino;
					future_mino.pos.y += 1;

					if (check_collision(&state, &future_mino)) {
						add_active_mino_to_field(&state);

						const valid_spawn = try_spawn_next_mino(&state, &rand.random());
						if (!valid_spawn) {
							app_state = .GAME_OVER;
							std.debug.print("FINISHED! You scored {}\n", .{state.lines_cleared});
						}
					} else {
						state.active_mino.pos.y = future_mino.pos.y;
					}
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

						const tile_value = state.field[@intCast(y)][@intCast(x)];
						if (tile_value != EMPTY_SPACE) {
							color = mino_color(tile_value);
						}

						const dx = FIELD_X_OFFSET + x * TILE_SIZE_PIXELS;
						const dy = FIELD_Y_OFFSET + y * TILE_SIZE_PIXELS;

						Fill_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, color);
						Draw_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
					}
				}
			}

			if (app_state == .GAME_NOT_STARTED or app_state == .GAME_OVER) {
				{
					try Draw_Text(renderer, GAME_START_TEXT_X_OFFSET, GAME_START_TEXT_Y_OFFSET, "Press SPACE to start", font, @intFromEnum(Color.WHITE));
				}
			}

			if (app_state == .GAME_PLAYING) {
				{ // Active mino
					const active_mino = state.active_mino;
					for (Minoes[@intCast(@intFromEnum(active_mino.type))].rotations[@intFromEnum(active_mino.rotation)]) |offsets| {
						const x = active_mino.pos.x + offsets.x;
						const y = active_mino.pos.y + offsets.y;

						const dx = FIELD_X_OFFSET + x * TILE_SIZE_PIXELS;
						const dy = FIELD_Y_OFFSET + y * TILE_SIZE_PIXELS;

						const color = mino_color(@intFromEnum(active_mino.type));
						Fill_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, color);
						Draw_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
					}
				}

				{ // Next mino
					const next_mino = state.next_mino;
					for (Minoes[@intCast(@intFromEnum(next_mino.type))].rotations[@intFromEnum(next_mino.rotation)]) |offsets| {
						const x = next_mino.pos.x + offsets.x;
						const y = next_mino.pos.y + offsets.y;

						const dx = NEXT_MINO_X_OFFSET + x * TILE_SIZE_PIXELS;
						const dy = NEXT_MINO_Y_OFFSET + y * TILE_SIZE_PIXELS;

						const color = mino_color(@intFromEnum(next_mino.type));
						Fill_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, color);
						Draw_Rect(renderer, dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
					}

				}

				{ // Text
					const score_string = try std.fmt.allocPrintZ(allocator, "Lines Cleared: {}", .{state.lines_cleared});
					defer allocator.free(score_string);

					const c_string: [*c]const u8 = @ptrCast(score_string);
					try Draw_Text(renderer, GAME_START_TEXT_X_OFFSET, 50, c_string, font, @intFromEnum(Color.WHITE));
				}
			}

			if (app_state == .GAME_OVER) {
				{
					const score_string = try std.fmt.allocPrintZ(allocator, "Final score: {}", .{state.lines_cleared});
					defer allocator.free(score_string);

					const c_string: [*c]const u8 = @ptrCast(score_string);
					try Draw_Text(renderer, GAME_START_TEXT_X_OFFSET, 2 * GAME_START_TEXT_Y_OFFSET, c_string, font, @intFromEnum(Color.WHITE));
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

	const dest: c.SDL_Rect = .{ .x = x, .y = y, .w = w, .h = h};
	_ = c.SDL_RenderDrawRect(renderer, &dest);
}

fn Fill_Rect(renderer: *c.SDL_Renderer, x: c_int, y: c_int, w: c_int, h: c_int, rgba: u32) void {
	Set_Color(renderer, rgba);

	const dest: c.SDL_Rect = .{ .x = x, .y = y, .w = w, .h = h};
	_ = c.SDL_RenderFillRect(renderer, &dest);
}

fn Draw_Text(renderer: *c.SDL_Renderer, x: c_int, y: c_int, text: [*c]const u8, font: *c.TTF_Font, rgba: u32) !void {
	const color = Make_SDL_Color(rgba);

	const surface = c.TTF_RenderText_Blended(font, text, color) orelse {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to render text to surface: %s", c.TTF_GetError());
		return error.SDLRenderFailed;
	};
	defer c.SDL_FreeSurface(surface);

	const texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse {
		c.SDL_LogError(c.SDL_LOG_CATEGORY_ERROR, "Unable to create texture from surface: %s", c.SDL_GetError());
		return error.SDLRenderFailed;
	};
	defer c.SDL_DestroyTexture(texture);

	const dest: c.SDL_Rect = .{ .x = x, .y = y, .w = surface.*.w, .h = surface.*.h };
	_ = c.SDL_RenderCopy(renderer, texture, null, &dest);
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
	WHITE		= 0xFFFFFF00,
};

fn mino_color(mino_type: MinoTypeTag) callconv(.Inline) u32 {
	return @intFromEnum(Minoes[@intCast(mino_type)].color);
}

const Minoes = [NUM_MINO_TYPES]MinoDef{
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
	.{
		.type = .TYPE_O,
		.color = .YELLOW,
		.rotations = [NUM_ROTATIONS][4]Point{
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 } },
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 } },
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 } },
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 } },
		},
	},
	.{
		.type = .TYPE_S,
		.color = .GREEN,
		.rotations = [NUM_ROTATIONS][4]Point{
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 } },
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 }, .{ .x = 2, .y = 2 } },
			[_]Point{ .{ .x = 0, .y = 2 }, .{ .x = 1, .y = 2 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 } },
			[_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 2 } },
		},
	},
	.{
		.type = .TYPE_T,
		.color = .PURPLE,
		.rotations = [NUM_ROTATIONS][4]Point{
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 } },
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 }, .{ .x = 1, .y = 2 } },
			[_]Point{ .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 }, .{ .x = 1, .y = 2 } },
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 2 } },
		},
	},
	.{
		.type = .TYPE_Z,
		.color = .RED,
		.rotations = [NUM_ROTATIONS][4]Point{
			[_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 } },
			[_]Point{ .{ .x = 2, .y = 0 }, .{ .x = 2, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 2 } },
			[_]Point{ .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 2 }, .{ .x = 2, .y = 2 } },
			[_]Point{ .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 1 }, .{ .x = 0, .y = 2 } },
		},
	},
};

const AppState = enum {
	GAME_NOT_STARTED,
	GAME_PLAYING,
	GAME_OVER,
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
	const mino_type = rand.*.uintLessThan(u8, NUM_MINO_TYPES);

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
