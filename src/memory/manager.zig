//! OPA WASM memory and heap management.

const std = @import("std");
const backend = @import("../backends/backend.zig");

/// MemoryManager handles OPAs linear memory and heap management.
pub const MemoryManager = struct {
    const Self = @This();

    pub const Error = error{
        AllocationFailed,
        JsonParseFailed,
        JsonDumpFailed,
        FunctionNotCached,
        MissingOpaFunction,
    };

    memory: backend.Memory,
    allocator: std.mem.Allocator,

    // Cached OPA function references.
    opa_malloc_fn: ?backend.Func = null,
    opa_free_fn: ?backend.Func = null,
    opa_heap_ptr_get_fn: ?backend.Func = null,
    opa_heap_ptr_set_fn: ?backend.Func = null,
    opa_json_parse_fn: ?backend.Func = null,
    opa_json_dump_fn: ?backend.Func = null,

    pub fn init(allocator: std.mem.Allocator, memory: backend.Memory) Self {
        return .{
            .memory = memory,
            .allocator = allocator,
        };
    }

    /// Cache OPA function references from instance exports.
    pub fn cacheOpsFunctions(self: *Self, instance: backend.Instance) void {
        self.opa_malloc_fn = instance.getFunc("opa_malloc");
        self.opa_free_fn = instance.getFunc("opa_free");
        self.opa_heap_ptr_get_fn = instance.getFunc("opa_heap_ptr_get");
        self.opa_heap_ptr_set_fn = instance.getFunc("opa_heap_ptr_set");
        self.opa_json_parse_fn = instance.getFunc("opa_json_parse");
        self.opa_json_dump_fn = instance.getFunc("opa_json_dump");
    }

    /// Allocate memory in WASM heap using opa_malloc.
    pub fn alloc(self: *Self, num_bytes: u32) !u32 {
        const func = self.opa_malloc_fn orelse return error.MissingOpaFunction;
        const result = try func.call1(@as(i32, @bitCast(num_bytes)));
        return @bitCast(result);
    }

    /// Free memory in WASM heap using opa_free.
    pub fn free(self: *Self, addr: u32) !void {
        const func = self.opa_free_fn orelse return error.MissingOpaFunction;
        _ = try func.call1(@as(i32, @bitCast(addr)));
    }

    /// Get current heap pointer.
    pub fn getHeapPtr(self: *Self) !u32 {
        const func = self.opa_heap_ptr_get_fn orelse return error.MissingOpaFunction;
        const result = try func.call0();
        return @bitCast(result);
    }

    /// Set heap pointer (for resetting state between evaluations).
    pub fn setHeapPtr(self: *Self, ptr: u32) !void {
        const func = self.opa_heap_ptr_set_fn orelse return error.MissingOpaFunction;
        try func.call1v(@as(i32, @bitCast(ptr)));
    }

    /// Save current heap state for later restoration.
    pub fn saveHeapState(self: *Self) !u32 {
        return self.getHeapPtr();
    }

    /// Restore heap state (resets allocations made since save).
    pub fn restoreHeapState(self: *Self, saved_ptr: u32) !void {
        return self.setHeapPtr(saved_ptr);
    }

    /// Write bytes to WASM memory at given address.
    pub fn write(self: *Self, addr: u32, bytes: []const u8) !void {
        return self.memory.write(addr, bytes);
    }

    /// Read bytes from WASM memory.
    pub fn read(self: *Self, addr: u32, len: u32) ![]const u8 {
        return self.memory.read(addr, len);
    }

    /// Read a null-terminated string from WASM memory.
    pub fn readCString(self: *Self, addr: u32) ![]const u8 {
        return self.memory.readCString(addr);
    }

    /// Write JSON string to WASM memory, allocate space and parse it using opa_json_parse
    /// Returns the OPA value address.
    pub fn writeAndParseJson(self: *Self, json: []const u8) !u32 {
        const json_parse = self.opa_json_parse_fn orelse return error.MissingOpaFunction;

        const addr = try self.alloc(@intCast(json.len));
        try self.write(addr, json);

        const result = try json_parse.call2(@as(i32, @bitCast(addr)), @as(i32, @intCast(json.len)));
        return @bitCast(result);
    }

    /// Dump OPA value to JSON string
    /// Returns allocated slice that caller must free.
    pub fn dumpToJson(self: *Self, value_addr: u32) ![]const u8 {
        const json_dump = self.opa_json_dump_fn orelse return error.MissingOpaFunction;

        const str_addr: u32 = @bitCast(try json_dump.call1(@as(i32, @bitCast(value_addr))));
        const json_slice = try self.readCString(str_addr);

        return self.allocator.dupe(u8, json_slice);
    }

    /// Serialize a Zig value to JSON, write to WASM and parse.
    pub fn writeValue(self: *Self, value: anytype) !u32 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try std.json.stringify(value, .{}, buffer.writer());
        return self.writeAndParseJson(buffer.items);
    }

    /// Read OPA value and deserialize to Zig type.
    pub fn readValue(self: *Self, comptime T: type, value_addr: u32) !std.json.Parsed(T) {
        const json = try self.dumpToJson(value_addr);
        defer self.allocator.free(json);

        return std.json.parseFromSlice(T, self.allocator, json, .{});
    }

    /// Grow memory by specified number of pages (64KB each).
    pub fn grow(self: *Self, pages: u32) !void {
        return self.memory.grow(pages);
    }

    /// Get total memory size in bytes.
    pub fn size(self: *Self) usize {
        return self.memory.size();
    }
};

test "memory manager init" {
    const allocator = std.testing.allocator;

    const manager = MemoryManager.init(allocator, undefined);
    _ = manager;
}
