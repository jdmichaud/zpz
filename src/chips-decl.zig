pub const chips = @cImport({
  // @cDefine("CHIPS_IMPL", {});
  @cInclude("chips/z80.h");
  @cInclude("chips/ay38910.h");
  @cInclude("chips/i8255.h");
  @cInclude("chips/mc6845.h");
  @cInclude("chips/am40010.h");
  @cInclude("chips/upd765.h");
  @cInclude("chips/mem.h");
  @cInclude("chips/kbd.h");
  @cInclude("chips/clk.h");
  @cInclude("chips/fdd.h");
  @cInclude("chips/fdd_cpc.h");

  @cInclude("systems/cpc.h");
});
