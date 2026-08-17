// An std.mem.Allocator whose backing memory comes from the JS environment
// rather than from the wasm module itself.
//
// std.heap.wasm_allocator services allocations by issuing the memory.grow
// instruction (@wasmMemoryGrow) and managing the resulting pages internally, so
// nothing is ever imported and the environment never learns that an allocation
// happened. Here the two primitives are declared extern instead, which makes
// them show up as env.malloc/env.free in the module's import section and puts
// the environment in charge of the heap.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

// wasm32-freestanding has no libc, so these resolve to imports rather than to
// any real malloc. The names are what JS must provide in the env object.
const js = struct {
    extern fn malloc(size: usize) ?[*]u8;
    extern fn free(ptr: ?[*]u8) void;
};

// Alignment the JS malloc promises on the pointers it returns. It has to be
// agreed on out of band: the C signature has nowhere to express it.
pub const malloc_alignment = 16;

// Stateless, so there is no context to point at, just like std.heap.raw_c_allocator.
pub const js_allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &vtable,
};

const vtable: Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

fn alloc(_: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
    // malloc takes no alignment argument, so anything stricter than what it
    // guarantees has to be refused. Returning null surfaces as error.OutOfMemory
    // instead of quietly handing back a misaligned pointer.
    if (alignment.toByteUnits() > malloc_alignment) return null;
    return js.malloc(len);
}

fn resize(_: *anyopaque, memory: []u8, _: Alignment, new_len: usize, _: usize) bool {
    // A block cannot grow in place without a realloc on the other side, but
    // shrinking always succeeds: the tail is simply never used again.
    return new_len <= memory.len;
}

fn remap(_: *anyopaque, memory: []u8, _: Alignment, new_len: usize, _: usize) ?[*]u8 {
    // null tells the caller to fall back to alloc + copy + free, which is the
    // best that can be done without a realloc import.
    return if (new_len <= memory.len) memory.ptr else null;
}

fn free(_: *anyopaque, memory: []u8, _: Alignment, _: usize) void {
    js.free(memory.ptr);
}
