const std = @import("std");

pub fn setup_wasm(b: *std.build.Builder) void {
    // const exe = b.addExecutable("zpz6128", "src/zpz-wasm.zig");

    // exe.setTarget("wasm32");
    // exe.addIncludePath("../chips/");
    // exe.addCSourceFiles(&.{"src/chips-impl.c"}, &.{});
    // exe.linkSystemLibrary("c");
    // exe.install();

    const mode = b.standardReleaseOptions();
    const lib = b.addSharedLibrary("zpz6128", "src/zpz-wasm.zig", .unversioned);

    lib.setBuildMode(mode);
    lib.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    lib.addIncludePath("../chips/");
    lib.addCSourceFiles(&.{"src/chips-impl.c"}, &.{});
    lib.linkLibC(); // better than linkSystemLibrary("c") for cross-compilation
    lib.import_memory = true;
    lib.stack_size = 32 * 1024 * 1024;
    lib.use_stage1 = true; // stage2 not ready
    // lib.initial_memory = 65536;
    // lib.max_memory = 65536;
    // lib.stack_size = 14752;
    // lib.export_symbol_names = &[_][]const u8{ "add" };

    const wasm_step = b.step("wasm", "Compile the wasm library");
    wasm_step.dependOn(&b.addInstallArtifact(lib).step);
}

pub fn build(b: *std.build.Builder) void {

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zpz6128", "src/zpz-native.zig");

    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addIncludePath("../chips/");
    exe.addCSourceFiles(&.{"src/chips-impl.c"}, &.{});
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("c");
    exe.install();
    exe.use_stage1 = true; // stage2 not ready

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);

    setup_wasm(b);
}
