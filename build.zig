const std = @import("std");

pub fn setup_wasm(b: *std.Build, optimize: std.builtin.Mode) void {
    const lib = b.addExecutable(.{
        .name = "zpz6128",
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .optimize = optimize,
        .target = b.resolveTargetQuery(.{
          .cpu_arch = .wasm32,
          .os_tag = .freestanding,
        }),
        .root_source_file = .{ .path = "src/zpz-wasm.zig" },
    });
    lib.entry = .disabled;
    lib.addIncludePath(.{ .path = "./chips/" });
    lib.addCSourceFiles(.{ .files = &.{"src/chips-impl.c"} });
    // We need the libc because of the use of #include <string> memset in `chips`
    lib.linkLibC(); // better than linkSystemLibrary("c") for cross-compilation
    lib.import_memory = true;
    lib.stack_size = 32 * 1024 * 1024;
    // lib.use_stage1 = true; // stage2 not ready
    // lib.initial_memory = 65536;
    // lib.max_memory = 65536;
    // lib.stack_size = 14752;
    // lib.export_symbol_names = &[_][]const u8{ "add" };
    lib.rdynamic = true;
    // So we don't need to define like __stack_chk_guard and __stack_chk_fail
    // lib.stack_protector = false;

    const wasm_step = b.step("wasm", "Compile the wasm library");
    wasm_step.dependOn(&b.addInstallArtifact(lib, .{}).step);
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zpz6128",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/zpz-native.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .path = "./chips/" });
    exe.addCSourceFiles(.{ .files = &.{"src/chips-impl.c"} });
    exe.linkSystemLibrary("SDL2");
    exe.linkLibC(); // better than linkSystemLibrary("c") for cross-compilation
    // Some fairly large structs (cpc_t) are statically initialized.
    exe.stack_size = 32 * 1024 * 1024;

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/zpz-native.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    setup_wasm(b, optimize);
}
