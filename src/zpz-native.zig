// https://github.com/floooh/chips
// ./zpz6128 CPC6128_System_Disks_\(FR\)/6128FR_4.DSK Turbo\ Pascal\ 3.00A/Turbo\ Pascal\ 3.00A\ \(Face\ A\)\ \(1985\).dsk

const builtin = @import("builtin");
const std = @import("std");
const sdl = @cImport({
  @cInclude("SDL.h");
});
const chips = @import("chips-decl.zig").chips;
const Emulator = @import("zpz.zig").Emulator;

// if (builtin.cpu.arch == .wasm32) {
//   @compileError("error: no adapter for web assembly yet.");
// } else
const SDLAdapter = @import("sdl-adapter.zig").SDLAdapter;

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub fn cpc_insert_disc(cpc: *chips.cpc_t, drive: u8, pathname: []const u8) !void {
  var file = try std.fs.cwd().openFile(pathname, .{});
  defer file.close();

  const size = try file.getEndPos();
  const buffer = try std.posix.mmap(
    null,
    size,
    std.posix.PROT.READ,
    .{ .TYPE = .SHARED },
    file.handle,
    0,
  );
  errdefer std.posix.munmap(buffer);

  if (!chips.cpc_insert_disc_in_drive(cpc, drive, buffer.ptr, @as(i32, @intCast(size)))) {
    return error.InsertDiscFailed;
  }
}

pub fn load_cpc_rom_image(pathname: []const u8, rom_image: *chips.cpc_rom_image_t) !void {
  var file = try std.fs.cwd().openFile(pathname, .{});
  defer file.close();

  rom_image.size = try file.getEndPos();
  const buffer = try std.c.mmap(
    null,
    rom_image.size,
    std.os.PROT.READ,
    std.os.MAP.SHARED,
    file.handle,
    0,
  );
  errdefer std.c.munmap(buffer);
  rom_image.ptr = buffer.ptr;
}

// pub fn debug(_: ?*anyopaque, pins: u64) callconv(.C) void {
//   std.debug.print("0x{b:0<64}\n", .{ pins });
// }

pub fn main() anyerror!void {

  var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
  const allocator = general_purpose_allocator.allocator();

  const args = try std.process.argsAlloc(allocator);
  defer std.process.argsFree(allocator, args);

  if (args.len != 1 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))) {
    try stdout.print("{s} is an Amstrad CPC 6128 emulator based on https://github.com/floooh/chips\n\n", .{ args[0] });
    try stdout.print("usage:\n", .{});
    try stdout.print("    {s}                   - Launch the emulator\n", .{ args[0] });
    try stdout.print("    {s} cpm.dsk turbo.sdk - Launch the emulator with two disks (one in drive A and the other in drive B)\n", .{ args[0] });
    return;
  }

  // If ROMS were to be provided through the CLI args
  // if (args.len != 4) {
  //   try stderr.print("error: cpc6128 expects 3 arguments. {} given\n", .{ args.len });
  //   try stderr.print("usage: {s} 6128os.rom 6128basic.rom 6128amsdos.rom\n", .{ args[0] });
  //   return error.InvalidArgs;
  // }

  // var os: chips.cpc_rom_image_t = .{ .ptr = null, .size = 0 };
  // try load_cpc_rom_image(args[1], &os);
  // var basic: chips.cpc_rom_image_t = .{ .ptr = null, .size = 0 };
  // try load_cpc_rom_image(args[2], &basic);
  // var amsdos: chips.cpc_rom_image_t = .{ .ptr = null, .size = 0 };
  // try load_cpc_rom_image(args[3], &amsdos);

  var emulator = try Emulator.new(allocator);
  emulator.init();

  if (args.len > 1) {
    try stdout.print("Drive A: {s}\n", .{ args[1] });
    try cpc_insert_disc(&emulator.cpc, 0, args[1]);
  }
  if (args.len > 2) {
    try stdout.print("Drive B: {s}\n", .{ args[2] });
    try cpc_insert_disc(&emulator.cpc, 1, args[2]);
  }

  var adapter = try SDLAdapter.init(chips.AM40010_DISPLAY_WIDTH, chips.AM40010_DISPLAY_HEIGHT * 2);
  // defer gfx.cleanUp(sdl_subsystem);

  const frame_time: usize = 16;

  while (!emulator.stopped) {
    const then: usize = adapter.interface.get_timestamp_fn(&adapter.interface);
    adapter.interface.handle_event(&emulator.cpc, &emulator.stopped, &emulator.ctrl, &emulator.shift);
    _ = chips.cpc_exec(&emulator.cpc, frame_time * 1000); // This in CPC micro-seconds

    try adapter.interface.display(emulator.pixel_buffer, chips.AM40010_DISPLAY_WIDTH, chips.AM40010_DISPLAY_HEIGHT);

    // The micro seconds parameter provided to cpc_exec is in CPC time.
    // 16ms in CPC time is, of course, way quicker than in real time.
    // So we need to wait a little.
    const now = adapter.interface.get_timestamp_fn(&adapter.interface);
    const delay: usize = frame_time - @min(now - then, frame_time);
    if (delay > 0) {
      std.time.sleep(delay * 1000000); // in nanoseconds
    } else {
      try stderr.print("warning: frame too slow!\n", .{});
    }
  }

  // const file = try std.fs.cwd().createFile("ram.dump", .{ .read = true });
  // defer file.close();
  // // const toto: *const[4]u8 = &[4]u8{ 't', 'o', 't', 'o' };
  // for (cpc.ram) |ram| {
  //   _ = try file.writeAll(&ram);
  // }
  // try stdout.print("ram dumped to ram.dump\n", .{});
}
