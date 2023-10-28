// This file is a chimera between 2 github projects:
// https://github.com/floooh/pacman.zig/
// https://github.com/ryupold/examples-raylib.zig/
//
// I used floooh's project to get an idea of the general process for compiling to wasm.
// The arguments for the emcc linking for raylib was copied from ryupold's examples.

const std = @import("std");
const raylib_build = @import("lib/raylib/src/build.zig");

// shorthands, copied from pacman
const fs = std.fs;
const Builder = std.build.Builder;
const CompileStep = std.build.CompileStep;
const CrossTarget = std.zig.CrossTarget;
const OptimizeMode = std.builtin.OptimizeMode;
const builtin = @import("builtin");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.getCpu().arch != .wasm32) {
        buildNative(b, target, optimize) catch unreachable;
    } else {
        buildWasm(b, target, optimize) catch |err| {
            std.log.err("{}", .{err});
        };
    }
}

fn buildNative(b: *Builder, target: CrossTarget, optimize: OptimizeMode) !void {
    const raylib = raylib_build.addRaylib(b, target, optimize, .{});

    const exe = b.addExecutable(.{
        .name = "243",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(raylib);
    b.installArtifact(exe);

    //shell run step
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn buildWasm(b: *Builder, target: CrossTarget, optimize: OptimizeMode) !void {
    if (b.sysroot == null) {
        std.log.err("Usage: 'zig build [run] -Dtarget=wasm32-freestanding --sysroot [path/to/emsdk]/upstream/emscripten'", .{});
        return error.SysRootExpected;
    }
    if (target.os_tag != .freestanding) {
        std.log.err("Usage: 'zig build [run] -Dtarget=wasm32-freestanding --sysroot [path/to/emsdk]/upstream/emscripten'", .{});
        return error.SysRootExpected;
    }

    // derive the emcc and emrun paths from the provided sysroot:
    const emcc_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, "emcc" });
    defer b.allocator.free(emcc_path);
    const emrun_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, "emrun" });
    defer b.allocator.free(emrun_path);

    // the sysroot/include path must be provided separately for the C compilation step
    const include_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, "cache/sysroot/include" });
    defer b.allocator.free(include_path);

    // sokol must be built with wasm32-emscripten so that the EM_JS magic works
    var wasm32_emscripten_target = target;
    wasm32_emscripten_target.os_tag = .emscripten;
    const libRaylib = raylib_build.addRaylib(b, wasm32_emscripten_target, optimize, .{});

    // the game code can be compiled either with wasm32-freestanding or wasm32-emscripten
    const libgame = b.addStaticLibrary(.{
        .name = "game",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/main.zig" },
    });
    const install_libraylib = b.addInstallArtifact(libRaylib, .{});
    libgame.addIncludePath(.{ .path = "lib/raylib/src" });
    const install_libgame = b.addInstallArtifact(libgame, .{});

    // call the emcc linker step as a 'system command' zig build step which
    // depends on the libsokol and libgame build steps
    try fs.cwd().makePath("zig-out/web");
    const emcc = b.addSystemCommand(&.{
        emcc_path,
        "-Os",
        "--closure",
        "1",
        "src/emscripten/entry.c",
        "-ozig-out/web/game.html",
        "--shell-file",
        "src/emscripten/shell.html",
        "-Lzig-out/lib/",
        "-lgame",
        "-lraylib",
        //		"-sNO_FILESYSTEM=1",
        //		"-sMALLOC='emmalloc'",
        //		"-sASSERTIONS=0",
        //		"-sUSE_WEBGL2=1",
        //		"-sUSE_GLFW=3",
        //		"-sEXPORTED_FUNCTIONS=['_malloc','_free','_main']",
        //	});
        //
        //	const emcc = b.addSystemCommand(&.{
        "-DPLATFORM_WEB",
        "-DRAYGUI_IMPLEMENTATION",
        "-sUSE_GLFW=3",
        "-sWASM=1",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sWASM_MEM_MAX=512MB", //going higher than that seems not to work on iOS browsers ¯\_(ツ)_/¯
        "-sTOTAL_MEMORY=512MB",
        "-sABORTING_MALLOC=0",
        "-sASYNCIFY",
        "-sFORCE_FILESYSTEM=1",
        "-sASSERTIONS=1",
        "--memory-init-file",
        "0",
        "--source-map-base",
        "-O1",
        "-Os",
        // "-sLLD_REPORT_UNDEFINED",
        "-sERROR_ON_UNDEFINED_SYMBOLS=0",

        // optimizations
        "-O1",
        "-Os",

        "-sEXPORTED_FUNCTIONS=['_malloc','_free','_main', '_emsc_main']",
        "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap",
    });

    emcc.step.dependOn(&install_libraylib.step);
    emcc.step.dependOn(&install_libgame.step);

    // get the emcc step to run on 'zig build'
    b.getInstallStep().dependOn(&emcc.step);

    // a seperate run step using emrun
    const emrun = b.addSystemCommand(&.{ emrun_path, "zig-out/web/game.html" });
    emrun.step.dependOn(&emcc.step);
    b.step("run", "Run pacman").dependOn(&emrun.step);
}
