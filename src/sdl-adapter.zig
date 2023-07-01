const std = @import("std");
const sdl = @cImport({
  @cInclude("SDL.h");
});
const chips = @import("chips-decl.zig").chips;
const IOAdapter = @import("io-adapter.zig").IOAdapter;

pub const SDLAdapter = struct {
  const Self = @This();

  window: *sdl.SDL_Window,
  texture: *sdl.SDL_Texture,
  renderer: *sdl.SDL_Renderer,
  width: usize,
  height: usize,
  tv: std.os.timeval,

  interface: IOAdapter,

  pub fn init(width: u16, height: u16) anyerror!SDLAdapter {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
      sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
      return error.SDLInitializationFailed;
    }
    errdefer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("Amstrad CPC 6128", sdl.SDL_WINDOWPOS_UNDEFINED,
      sdl.SDL_WINDOWPOS_UNDEFINED, width, height, sdl.SDL_WINDOW_OPENGL) orelse {
      sdl.SDL_Log("Unable to create window: %s", sdl.SDL_GetError());
      return error.SDLInitializationFailed;
    };
    errdefer sdl.SDL_DestroyWindow(window);

    // const surface = sdl.SDL_GetWindowSurface(window) orelse {
    //   sdl.SDL_Log("Unable to create surface: %s", sdl.SDL_GetError());
    //   return error.SDLInitializationFailed;
    // };

    const renderer = sdl.SDL_CreateRenderer(window, -1, 0) orelse {
      sdl.SDL_Log("Unable to create renderer: %s", sdl.SDL_GetError());
      return error.SDLInitializationFailed;
    };
    errdefer sdl.SDL_DestroyRenderer(renderer);

    // const texture = sdl.SDL_CreateTextureFromSurface(renderer, surface) orelse {
    //   sdl.SDL_Log("Unable to create texture: %s", sdl.SDL_GetError());
    //   return error.SDLInitializationFailed;
    // };
    // errdefer sdl.SDL_DestroyTexture(texture);
    // sdl.SDL_FreeSurface(surface);

    const texture = sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_RGBA32,
      sdl.SDL_TEXTUREACCESS_STREAMING, width, height) orelse {
      sdl.SDL_Log("Unable to create texture: %s", sdl.SDL_GetError());
      return error.SDLInitializationFailed;
    };
    errdefer sdl.SDL_DestroyTexture(texture);

    return SDLAdapter {
      .window = window,
      .texture = texture,
      .renderer = renderer,
      .width = width,
      .height = height,
      .tv = std.mem.zeroInit(std.os.timeval, .{}),

      .interface = IOAdapter {
        .handle_event_fn = handle_event,
        .display_fn = display,
        .get_timestamp = get_timestamp_millisecond,
      },
    };
  }

  fn handle_event(_: *IOAdapter, cpc: *chips.cpc_t, stopped: *bool, ctrl: *bool, shift: *bool) void {
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event) != 0) {
      switch (event.type) {
        sdl.SDL_QUIT => { stopped.* = true; },
        sdl.SDL_TEXTINPUT => {
          // If it's a character, deal with it here so that we don't have to manage
          // uppercasing and the like.
          chips.cpc_key_down(cpc, event.text.text[0]);
          chips.cpc_key_up(cpc, event.text.text[0]);
        },
        sdl.SDL_KEYDOWN, sdl.SDL_KEYUP => {
          // If it's a non-character key, deal with it individually.
          var c: u8 = 0;
          switch (event.key.keysym.sym) {
            sdl.SDLK_SPACE     => { c = 0x20; },
            sdl.SDLK_LEFT      => { c = 0x08; },
            sdl.SDLK_RIGHT     => { c = 0x09; },
            sdl.SDLK_DOWN      => { c = 0x0A; },
            sdl.SDLK_UP        => { c = 0x0B; },
            sdl.SDLK_RETURN    => { c = 0x0D; },
            sdl.SDLK_RCTRL,
            sdl.SDLK_LCTRL     => { ctrl.* = event.type == sdl.SDL_KEYDOWN; }, // What is the value of the key to inject here???
            sdl.SDLK_RSHIFT,
            sdl.SDLK_LSHIFT    => { c = 0x02; shift.* = event.type == sdl.SDL_KEYDOWN; },
            sdl.SDLK_BACKSPACE => { c = if (shift.*) 0x0C else 0x01; }, // 0x0C: clear screen
            sdl.SDLK_ESCAPE    => { c = if (shift.*) 0x13 else 0x03; }, // 0x13: break
            sdl.SDLK_F1        => { c = 0xF1; },
            sdl.SDLK_F2        => { c = 0xF2; },
            sdl.SDLK_F3        => { c = 0xF3; },
            sdl.SDLK_F4        => { c = 0xF4; },
            sdl.SDLK_F5        => { c = 0xF5; },
            sdl.SDLK_F6        => { c = 0xF6; },
            sdl.SDLK_F7        => { c = 0xF7; },
            sdl.SDLK_F8        => { c = 0xF8; },
            sdl.SDLK_F9        => { c = 0xF9; },
            sdl.SDLK_F10       => { c = 0xFA; },
            sdl.SDLK_F11       => { c = 0xFB; },
            sdl.SDLK_F12       => { c = 0xFC; },
            0x60               => {
              if (shift.* and ctrl.*) {
                // Kludge for the Vortex keyboard which sends ` when ctrl+shift+escape are pressed.
                chips.cpc_reset(cpc);
                return;
              }
            },
            else               => { c = 0; },
          }
          if (c != 0) {
            if (event.type == sdl.SDL_KEYDOWN) {
              chips.cpc_key_down(cpc, c);
            } else {
              chips.cpc_key_up(cpc, c);
            }
          }
        },
        else => {},
      }
    }
  }

  pub fn display(adapter: *IOAdapter, pixel_buffer: [*]c_uint, width: usize, height: usize) anyerror!void {
    var self = @fieldParentPtr(SDLAdapter, "interface", adapter);

    try prepareScene(self, pixel_buffer, width, height);
    try renderScene(self);
  }

  pub fn get_timestamp_millisecond(adapter: *IOAdapter) u64 {
    var self = @fieldParentPtr(SDLAdapter, "interface", adapter);

    std.os.gettimeofday(&self.tv, null);
    return @as(u64, @intCast(1000000 * self.tv.tv_sec + self.tv.tv_usec)) / 1000;
  }

  fn prepareScene(self: *Self, pixel_buffer: [*]c_uint, width: usize, height: usize) anyerror!void {
    var texture = self.texture;

    var buffer: [*c]u32 = undefined;
    var pitch: i32 = undefined;
    const res = sdl.SDL_LockTexture(texture, null, @ptrCast(&buffer), &pitch);
    if (res < 0) {
      sdl.SDL_Log("Unable to lock texture: %s", sdl.SDL_GetError());
      return error.UnableToLockTexture;
    }

    // CPC pixel sizes differ from PC pixel sizes. We apply a correction factor in height.
    const height_factor = self.height / height;
    var j: usize = 0;
    while (j < self.height) {
      var i: usize = 0;
      while (i < self.width) {
          buffer[i + j * width] = 0xFF000000 | pixel_buffer[i + j / height_factor * width];
          i += 1;
      }
      j += 1;
    }

    sdl.SDL_UnlockTexture(self.texture);
  }

  fn renderScene(self: *Self) anyerror!void {
    if (sdl.SDL_SetRenderDrawColor(self.renderer, 0x00, 0x00, 0x00, 0xFF) < 0) {
      sdl.SDL_Log("Unable to draw color: %s", sdl.SDL_GetError());
      return error.UnableToDrawColor;
    }
    if (sdl.SDL_RenderClear(self.renderer) < 0) {
      sdl.SDL_Log("Unable to clear: %s", sdl.SDL_GetError());
      return error.UnableToClear;
    }
    // blit the surface
    if (sdl.SDL_RenderCopy(self.renderer, self.texture, null, null) < 0) {
      sdl.SDL_Log("Unable to copy texture: %s", sdl.SDL_GetError());
      return;
    }
    sdl.SDL_RenderPresent(self.renderer);
  }

  fn cleanUp(self: Self) void {
    sdl.SDL_DestroyRenderer(self.renderer);
    sdl.SDL_DestroyTexture(self.texture);
    sdl.SDL_DestroyWindow(self.window);
    sdl.SDL_Quit();
  }
};
