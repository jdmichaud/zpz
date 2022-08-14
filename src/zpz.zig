const std = @import("std");
const chips = @import("chips-decl.zig").chips;
const roms = @import("cpc-roms.zig");

pub const Emulator = struct {
  const Self = @This();

  cpc: chips.cpc_t,
  cpc_desc: chips.cpc_desc_t,
  stopped: bool,
  ctrl: bool,
  shift: bool,
  pixel_buffer_size: usize,
  pixel_buffer: [*]c_uint,

  // pub fn new() anyerror!Emulator {
  pub fn new(allocator: std.mem.Allocator) anyerror!Emulator {
    // Embed rom with the tool for now.
    var os: chips.cpc_rom_image_t = .{
      .ptr = @ptrCast(*const anyopaque, &roms.dump_cpc6128_os_bin),
      .size = roms.dump_cpc6128_os_bin.len,
    };
    var basic: chips.cpc_rom_image_t = .{
      .ptr = @ptrCast(*const anyopaque, &roms.dump_cpc6128_basic_bin),
      .size = roms.dump_cpc6128_basic_bin.len,
    };
    var amsdos: chips.cpc_rom_image_t = .{
      .ptr = @ptrCast(*const anyopaque, &roms.dump_cpc6128_amsdos_bin),
      .size = roms.dump_cpc6128_amsdos_bin.len,
    };

    var stopped: bool = false;
    const pixel_buffer_size: usize = chips.AM40010_DBG_DISPLAY_WIDTH * chips.AM40010_DBG_DISPLAY_HEIGHT * 4;
    var pixel_buffer: [*]c_uint = @ptrCast([*]c_uint, try allocator.alloc(c_uint, pixel_buffer_size));

    return Emulator {
      .cpc = std.mem.zeroInit(chips.cpc_t, .{}),
      .cpc_desc = .{
        .type = chips.CPC_TYPE_6128,
        .joystick_type = chips.CPC_JOYSTICK_NONE,
        .debug = .{
          .callback = .{
            // .func = debug,
            .func = null,
            .user_data = null,
          },
          .stopped = &stopped,
        },
        .pixel_buffer = .{
          .ptr = pixel_buffer,
          .size = pixel_buffer_size,
        },
        // No audio
        .audio = .{
          .callback = .{
            .func = null,
            .user_data = null,
          },
          .num_samples = 0,
          .sample_rate = 0,
          .volume = 0,
        },
        .roms = .{
          .cpc6128 = .{
            .os = os,
            .basic = basic,
            .amsdos = amsdos,
          },
          .cpc464 = .{
            .os = os,
            .basic = basic,
          },
          .kcc = .{
            .os = os,
            .basic = basic,
          },
        },
      },
      .stopped = stopped,
      .ctrl = false,
      .shift = false,
      .pixel_buffer = pixel_buffer,
      .pixel_buffer_size = pixel_buffer_size,
    };
  }


  pub fn init(self: *Self) void {
    chips.cpc_init(&self.cpc, &self.cpc_desc);
  }
};
