const std = @import("std");

const Platform = enum {
	sdl,
	wasm,
	all,
};

pub fn build(b: *std.Build) void {
	const platform = b.option(Platform, "platform", "platform to build for") orelse .all;

	if (platform == .sdl or platform == .all) {
		const target = b.standardTargetOptions(.{});
		const optimize = b.standardOptimizeOption(.{});

		const exe = b.addExecutable(.{
			.name = "tetris",
			.root_source_file = .{ .path = "src/sdl.zig" },
			.target = target,
			.optimize = optimize,
		});

		exe.linkSystemLibrary("SDL2");
		exe.linkSystemLibrary("SDL2_ttf");
	    exe.linkLibC();

		b.installArtifact(exe);

		const run_cmd = b.addRunArtifact(exe);
		run_cmd.step.dependOn(b.getInstallStep());
		if (b.args) |args| {
			run_cmd.addArgs(args);
		}

		const run_step = b.step("run", "Run the app");
		run_step.dependOn(&run_cmd.step);
	}

	if (platform == .wasm or platform == .all) {
		const lib = b.addSharedLibrary(.{
			.name = "game",
			.root_source_file = .{ .path = "src/game.zig" },
			.target = .{
				.cpu_arch = .wasm32,
				.os_tag = .freestanding,
			},
			.optimize = .ReleaseSmall,
		});

		lib.rdynamic = true;

		b.installArtifact(lib);
	}
}
