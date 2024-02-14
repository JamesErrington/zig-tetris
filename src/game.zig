extern fn platform_draw_rect(x: i32, y: i32, width: i32, height: i32, rgba: u32) void;
extern fn platform_fill_rect(x: i32, y: i32, width: i32, height: i32, rgba: u32) void;
extern fn platform_fill_text(x: i32, y: i32, text: [*c]const u8, rgba: u32) void;

const std = @import("std");

const RndGen = std.rand.DefaultPrng;

const NUM_COLS = 10;
const NUM_ROWS = 20;
const FRAMES_PER_DROP = 30;

const TILE_SIZE_PIXELS = 32;
const WINDOW_X_PADDING = 20;
const WINDOW_Y_PADDING = 20;
const FIELD_WIDTH_PIXELS = TILE_SIZE_PIXELS * NUM_COLS;
const FIELD_HEIGHT_PIXELS = TILE_SIZE_PIXELS * NUM_ROWS;
pub const WINDOW_WIDTH = 2 * (FIELD_WIDTH_PIXELS + WINDOW_X_PADDING);
pub const WINDOW_HEIGHT = FIELD_HEIGHT_PIXELS + (2 * WINDOW_Y_PADDING);
const FIELD_X_OFFSET = WINDOW_X_PADDING;
const FIELD_Y_OFFSET = WINDOW_Y_PADDING;
const NEXT_MINO_X_OFFSET = (3 * WINDOW_WIDTH / 4) - (2 * TILE_SIZE_PIXELS);
const NEXT_MINO_Y_OFFSET = (WINDOW_HEIGHT / 2) - TILE_SIZE_PIXELS;
const GAME_START_TEXT_X_OFFSET = (3 * WINDOW_WIDTH / 4) - 130;
const GAME_START_TEXT_Y_OFFSET = 50;

pub const FONT_NAME = "OpenSans-Regular.ttf";
pub const FONT_SIZE = 28;

var rand = RndGen.init(0);
var app_state = AppState.GAME_NOT_STARTED;
var game_state = init_game_state();
var score_buffer = std.mem.zeroes([128]u8);

pub fn Game_Init(seed: u64) callconv(.C) void {
	rand.seed(seed);
	app_state = AppState.GAME_NOT_STARTED;
	game_state = init_game_state();
	game_state.next_mino = random_mino();
	score_buffer = std.mem.zeroes([128]u8);
}

pub fn Try_Spawn_Next_Mino() callconv(.C) bool {
	var active_mino: MinoInstance = game_state.next_mino;
	active_mino.pos = .{ .x = @divFloor(NUM_COLS, 2) - 2, .y = 0 };

	if (check_collision(&active_mino)) {
		return false;
	}

	game_state.active_mino = active_mino;
	game_state.frames_until_drop = FRAMES_PER_DROP;
	game_state.next_mino = random_mino();

	return true;
}

pub fn Handle_Key_Down(key: i32) callconv(.C) void {
	switch (app_state) {
		.GAME_NOT_STARTED, .GAME_OVER => {
			if (key == @intFromEnum(Key.SPACE)) {
				game_state = init_game_state();
				game_state.next_mino = random_mino();
				_ = Try_Spawn_Next_Mino();
				app_state = .GAME_PLAYING;
			}
		},
		.GAME_PLAYING => {
			var future_mino = game_state.active_mino;
			switch (key) {
				@intFromEnum(Key.UP) => future_mino.rotation = next_rotation(game_state.active_mino.rotation),
				@intFromEnum(Key.DOWN) => future_mino.pos.y += 1,
				@intFromEnum(Key.LEFT) => future_mino.pos.x -= 1,
				@intFromEnum(Key.RIGHT) => future_mino.pos.x += 1,
				else => {},
			}

			if (!check_collision(&future_mino)) {
				game_state.active_mino = future_mino;
			}
		}
	}
}

pub fn Update_Game_State() callconv(.C) void {
	if (app_state != .GAME_PLAYING) return;

	game_state.frames_until_drop -= 1;
	if (game_state.frames_until_drop > 0) return;

	var future_mino = game_state.active_mino;
	future_mino.pos.y += 1;

	if (check_collision(&future_mino)) {
		add_active_mino_to_field();

		const valid_spawn = Try_Spawn_Next_Mino();
		if (!valid_spawn) {
			app_state = .GAME_OVER;
		}
	} else {
		game_state.active_mino.pos.y = future_mino.pos.y;
	}

	game_state.frames_until_drop = FRAMES_PER_DROP;
}

pub fn Render_Game_State() callconv(.C) void {
	{ // Draw background
		var y: c_int = 0;
		while (y < NUM_ROWS) : (y += 1) {
			var x: c_int = 0;
			while (x < NUM_COLS) : (x += 1) {
				const tile_value = game_state.field[@intCast(y)][@intCast(x)];
				const color = if (tile_value == EMPTY_SPACE) @intFromEnum(Color.DARK_GREY) else mino_color(tile_value);

				const dx = FIELD_X_OFFSET + x * TILE_SIZE_PIXELS;
				const dy = FIELD_Y_OFFSET + y * TILE_SIZE_PIXELS;

				platform_fill_rect(dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, color);
				platform_draw_rect(dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
			}
		}
	}

	{ // Draw score text
		const buffer = std.fmt.bufPrintZ(&score_buffer, "Cleared: {}", .{game_state.lines_cleared}) catch "Cleared: ?";

		const c_string: [*c]const u8 = @ptrCast(buffer);
		platform_fill_text(GAME_START_TEXT_X_OFFSET, GAME_START_TEXT_Y_OFFSET, c_string, @intFromEnum(Color.WHITE));
	}

	switch (app_state) {
		.GAME_PLAYING => {
			{ // Draw active mino
				const active_mino = game_state.active_mino;
				for (Minoes[@intCast(@intFromEnum(active_mino.type))].rotations[@intFromEnum(active_mino.rotation)]) |offsets| {
					const x = active_mino.pos.x + offsets.x;
					const y = active_mino.pos.y + offsets.y;

					const dx = FIELD_X_OFFSET + x * TILE_SIZE_PIXELS;
					const dy = FIELD_Y_OFFSET + y * TILE_SIZE_PIXELS;

					const color = mino_color(@intFromEnum(active_mino.type));
					platform_fill_rect(dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, color);
					platform_draw_rect(dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
				}
			}

			{ // Draw next mino
				const next_mino = game_state.next_mino;
				for (Minoes[@intCast(@intFromEnum(next_mino.type))].rotations[@intFromEnum(next_mino.rotation)]) |offsets| {
					const x = next_mino.pos.x + offsets.x;
					const y = next_mino.pos.y + offsets.y;

					const dx = NEXT_MINO_X_OFFSET + x * TILE_SIZE_PIXELS;
					const dy = NEXT_MINO_Y_OFFSET + y * TILE_SIZE_PIXELS;

					const color = mino_color(@intFromEnum(next_mino.type));
					platform_fill_rect(dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, color);
					platform_draw_rect(dx, dy, TILE_SIZE_PIXELS, TILE_SIZE_PIXELS, @intFromEnum(Color.LIGHT_GREY));
				}
			}
		},
		else => {
			platform_fill_text(GAME_START_TEXT_X_OFFSET, GAME_START_TEXT_Y_OFFSET * 2, "Press SPACE to start", @intFromEnum(Color.WHITE));
		}
	}
}

comptime {
	@export(Game_Init, .{ .name = "Game_Init" });
	@export(Try_Spawn_Next_Mino, .{ .name = "Try_Spawn_Next_Mino" });
	@export(Handle_Key_Down, .{ .name = "Handle_Key_Down" });
	@export(Update_Game_State, .{ .name = "Update_Game_State" });
	@export(Render_Game_State, .{ .name = "Render_Game_State" });
}

fn init_game_state() GameState {
	return .{
		.field = [_][NUM_COLS]MinoTypeTag{ [_]MinoTypeTag{ EMPTY_SPACE } ** NUM_COLS } ** NUM_ROWS,
		.active_mino = .{
			.pos = .{ .x = 0, .y = 0 },
			.type = .TYPE_I,
			.rotation = .ROTATION_0,
		},
		.next_mino  = .{
			.pos = .{ .x = 0, .y = 0 },
			.type = .TYPE_I,
			.rotation = .ROTATION_0,
		},
		.frames_until_drop = FRAMES_PER_DROP,
		.lines_cleared = 0,
	};
}

fn random_mino() MinoInstance {
	const mino_type = rand.random().uintLessThan(u8, NUM_MINO_TYPES);

	return .{
		.pos = .{ .x = 0, .y = 0 },
		.type =  @enumFromInt(mino_type),
		.rotation = .ROTATION_0,
	};
}

fn check_collision(mino: *const MinoInstance) bool {
	for (Minoes[@intCast(@intFromEnum(mino.type))].rotations[@intFromEnum(mino.rotation)]) |offsets| {
		const x = mino.pos.x + offsets.x;
		const y = mino.pos.y + offsets.y;

		if ((x < 0) or (x >= NUM_COLS) or (y < 0) or (y >= NUM_ROWS) or (game_state.field[@intCast(y)][@intCast(x)] != EMPTY_SPACE)) {
			return true;
		}
	}

	return false;
}

fn add_active_mino_to_field() void {
	const active_mino = game_state.active_mino;
	for (Minoes[@intCast(@intFromEnum(active_mino.type))].rotations[@intFromEnum(active_mino.rotation)]) |offsets| {
		const x = active_mino.pos.x + offsets.x;
		const y = active_mino.pos.y + offsets.y;

		game_state.field[@intCast(y)][@intCast(x)] = @intFromEnum(active_mino.type);
	}

	// Clear the full rows
	var n_cleared: usize = 0;
	var y: usize = 0;
	while (y < NUM_ROWS) : (y += 1) {
		var is_full = true;

		var x: usize = 0;
		while (x < NUM_COLS) : (x += 1) {
			if (game_state.field[y][x] == EMPTY_SPACE) {
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
				while (xx < NUM_COLS) : (xx += 1) {
					game_state.field[yy][xx] = game_state.field[yy - 1][xx];
				}
			}
		}
	}

	game_state.lines_cleared += n_cleared;
}

const AppState = enum {
	GAME_NOT_STARTED,
	GAME_PLAYING,
	GAME_OVER,
};

const GameState = struct {
	field: [NUM_ROWS][NUM_COLS]MinoTypeTag,
	active_mino: MinoInstance,
	next_mino: MinoInstance,
	frames_until_drop: isize,
	lines_cleared: usize,
};

const Point = struct {
	x: c_int,
	y: c_int,
};

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

const MinoInstance = struct {
	pos: Point,
	type: MinoType,
	rotation: Rotation,
};

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

const Color = enum(u32) {
	CYAN 		= 0x00FFFFFF,
	BLUE 		= 0x0000FFFF,
	ORANGE 		= 0xFF7F00FF,
	YELLOW 		= 0xFFFF00FF,
	PURPLE 		= 0x800080FF,
	GREEN 		= 0x00FF00FF,
	RED 		= 0xFF0000FF,
	DARK_GREY	= 0x202020FF,
	LIGHT_GREY 	= 0x404040FF,
	BLACK		= 0x000000FF,
	WHITE		= 0xFFFFFFFF,
};

const MinoDef = struct {
	type: MinoType,
	color: Color,
	rotations: [NUM_ROTATIONS][4]Point,
};

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

fn mino_color(mino_type: MinoTypeTag) callconv(.Inline) u32 {
	return @intFromEnum(Minoes[@intCast(mino_type)].color);
}

const Key = enum(i32) {
	SPACE = 32,
	RIGHT = 1073741903,
	LEFT = 1073741904,
	DOWN = 1073741905,
	UP = 1073741906,
};
