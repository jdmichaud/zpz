const std = @import("std");
const Emulator = @import("zpz.zig").Emulator;
const foo = @import("zpz.zig").foo;
const chips = @import("chips-decl.zig").chips;

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = general_purpose_allocator.allocator();
// const allocator = std.heap.c_allocator;

extern fn display(ptr: [*]c_uint) void;
extern fn addString(ptr: [*]const u8, size: usize) void;
extern fn printString() void;
extern fn writeConsoleBuffer(ptr: [*]const u8, size: usize) void;
extern fn printConsoleBuffer() void;

pub fn log(
  comptime _: std.log.Level,
  comptime _: @Type(.EnumLiteral),
  comptime _: []const u8,
  _: anytype,
) void {}


const SpecialKey = enum(u8) {
  Delete = 8,
  Tab = 9,
  Enter = 13,
  Alt = 18,
  Shift = 16,
  Control = 17,
  Escape = 27,
  PageUp = 33,
  PageDown = 34,
  End = 35,
  Home = 36,
  ArrowLeft = 37,
  ArrowUp = 38,
  ArrowRight = 39,
  ArrowDown = 40,
  // Delete = 46,
  OS = 91,
  F1 = 112,
  F2 = 113,
  F3 = 114,
  F4 = 115,
  F5 = 116,
  F6 = 117,
  F7 = 118,
  F8 = 119,
  F9 = 120,
  F10 = 121,
  F11 = 122,
  F12 = 123,
};

const Event = union(enum) {
  CharKey: u8,
  KeyDown: SpecialKey,
  KeyUp: SpecialKey,
};

var events = std.fifo.LinearFifo(Event, .Dynamic).init(allocator);

export fn input_char(char: u8) void {
  const event = Event { .CharKey = char };
  events.writeItem(event) catch |err| {
    Console.log("error: input_char: {}", .{ err });
    unreachable();
  };
}

export fn keydown(keycode: u8) void {
  if (keycode != 0) {
    const event = Event { .KeyDown = @intToEnum(SpecialKey, keycode) };
    events.writeItem(event) catch |err| {
      Console.log("error: input_char: {}", .{ err });
      unreachable();
    };
  }
}

export fn keyup(keycode: u8) void {
  if (keycode != 0) {
    const event = Event { .KeyUp = @intToEnum(SpecialKey, keycode) };
    events.writeItem(event) catch |err| {
      Console.log("error: input_char: {}", .{ err });
      unreachable();
    };
  }
}

var emulator: Emulator = undefined;
export fn new_emulator() *Emulator {
  emulator = Emulator.new(allocator) catch |err| {
    Console.log("error: Emulator.new: {}", .{ err });
    unreachable();
  };
  emulator.init();
  return &emulator;
}

fn handle_event(cpc: *chips.cpc_t, ctrl: *bool, shift: *bool) void {
  while (events.readItem()) |event| {
    switch (event) {
      Event.CharKey => |c| {
        // If it's a character, deal with it here so that we don't have to manage
        // uppercasing and the like.
        chips.cpc_key_down(cpc, c);
        chips.cpc_key_up(cpc, c);
      },
      Event.KeyDown, Event.KeyUp => |k| {
        // If it's a non-character key, deal with it individually.
        var c: u8 = 0;
        switch (k) {
          // Space          => { c = 0x20; },
          SpecialKey.ArrowLeft      => { c = 0x08; },
          SpecialKey.ArrowRight     => { c = 0x09; },
          SpecialKey.ArrowDown      => { c = 0x0A; },
          SpecialKey.ArrowUp        => { c = 0x0B; },
          SpecialKey.Enter          => { c = 0x0D; },
          SpecialKey.Control        => { ctrl.* = event == Event.KeyDown; },
          SpecialKey.Shift          => { c = 0x02; shift.* = event == Event.KeyDown; },
          SpecialKey.Delete         => { c = if (shift.*) 0x0C else 0x01; }, // 0x0C: clear screen
          SpecialKey.Escape         => { c = if (shift.*) 0x13 else 0x03; }, // 0x13: break
          SpecialKey.F1             => { c = 0xF1; },
          SpecialKey.F2             => { c = 0xF2; },
          SpecialKey.F3             => { c = 0xF3; },
          SpecialKey.F4             => { c = 0xF4; },
          SpecialKey.F5             => { c = 0xF5; },
          SpecialKey.F6             => { c = 0xF6; },
          SpecialKey.F7             => { c = 0xF7; },
          SpecialKey.F8             => { c = 0xF8; },
          SpecialKey.F9             => { c = 0xF9; },
          SpecialKey.F10            => { c = 0xFA; },
          SpecialKey.F11            => { c = 0xFB; },
          SpecialKey.F12            => { c = 0xFC; },
          // Ctrl+Shift+Delete combination not possible in the Browser
          // 0x60           => {
          //   if (shift.* and ctrl.*) {
          //     // Kludge for the Vortex keyboard which sends ` when ctrl+shift+escape are pressed.
          //     chips.cpc_reset(cpc);
          //     return;
          //   }
          // },
          else           => { c = 0; },
        }
        if (c != 0) {
          if (event == Event.KeyDown) {
            chips.cpc_key_down(cpc, c);
          } else {
            chips.cpc_key_up(cpc, c);
          }
        }
      },
    }
  }
}

export fn tick(frame_time: u16) void {
  handle_event(&emulator.cpc, &emulator.ctrl, &emulator.shift);
  _ = chips.cpc_exec(&emulator.cpc, frame_time * 1000); // This in CPC micro-seconds

  display(emulator.pixel_buffer);
}

// https://github.com/daneelsan/zig-wasm-logger/blob/master/JS.zig
pub const Console = struct {
  pub const Logger = struct {
    pub const Error = error{};
    pub const Writer = std.io.Writer(void, Error, write);

    fn write(_: void, bytes: []const u8) Error!usize {
      // This function can be called with only part of the string formatted,
      // that's why we need to first acculmulate the string and then flush
      // it later with printString.
      addString(bytes.ptr, bytes.len);
      return bytes.len;
    }
  };

  const logger = Logger.Writer{ .context = {} };
  pub fn log(comptime format: []const u8, args: anytype) void {
    logger.print(format, args) catch return;
    printString();
  }
};
