const std = @import("std");
const zware = @import("zware");

var buffer: [8 * 1024 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();

var io_buffer: [2 * 1024 * 1024]u8 = undefined;

var store: ?zware.Store = null;
var current_module: ?zware.Module = null;
var instance: ?zware.Instance = null;

export fn getIOBuffer() [*]u8 {
    return &io_buffer;
}

export fn getIOBufferSize() u32 {
    return io_buffer.len;
}

export fn init() i32 {
    store = zware.Store.init(allocator);
    return 0;
}

export fn loadModule(wasm_len: u32) i32 {
    var s = store orelse return -1;
    const wasm_bytes = io_buffer[0..wasm_len];

    current_module = zware.Module.init(allocator, wasm_bytes);
    var mod = &(current_module orelse return -3);
    mod.decode() catch return -3;

    instance = zware.Instance.init(allocator, &s, mod.*);
    var inst = &(instance orelse return -6);
    inst.instantiate() catch return -6;
    return 0;
}

export fn callFunc(name_offset: u32, name_len: u32, arg: i32) i32 {
    var inst = &(instance orelse return -6);
    const name = io_buffer[name_offset..][0..name_len];

    var in = [_]u64{@bitCast(@as(i64, arg))};
    var out = [_]u64{0};
    inst.invoke(name, &in, &out, .{}) catch return -6;
    return @truncate(@as(i64, @bitCast(out[0])));
}

export fn reset() void {
    instance = null;
    current_module = null;
    fba.reset();
}

export fn deinit() void {
    reset();
    store = null;
}
