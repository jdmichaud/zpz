// https://zig.news/david_vanderson/interfaces-in-zig-o1c
const chips = @import("chips-decl.zig").chips;

pub const IOAdapter = struct {
  handle_event_fn: fn (*IOAdapter, *chips.cpc_t, *bool, *bool, *bool) void,
  display_fn: fn (*IOAdapter, [*]c_uint, usize, usize) anyerror!void,
  get_timestamp: fn (*IOAdapter) u64,

  pub fn handle_event(adapter: *IOAdapter, cpc: *chips.cpc_t, running: *bool, ctrl: *bool, shift: *bool) void {
    adapter.handle_event_fn(adapter, cpc, running, ctrl, shift);
  }

  pub fn display(adapter: *IOAdapter, pixel_buffer: [*]c_uint, width: usize, height: usize) anyerror!void {
    try adapter.display_fn(adapter, pixel_buffer, width, height);
  }

  pub fn get_timestamp(adapter: *IOAdapter) u64 {
    try adapter.get_timestamp(adapter);
  }
};
