//! Freestanding backend for wasm32-freestanding target using zware.

const std = @import("std");
const zware = @import("zware");
const builtins = @import("../builtins/builtins.zig");

pub const OpaContext = struct {
    backend: *FreestandingBackend,
    instance: *Instance,
    builtins: *std.StringHashMapUnmanaged(u32),
    allocator: std.mem.Allocator,
    aborted: bool = false,
    abort_message: ?[]const u8 = null,

    pub fn getBuiltinName(self: *const OpaContext, id: u32) ?[]const u8 {
        var it = self.builtins.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == id) return entry.key_ptr.*;
        }
        return null;
    }

    pub fn setAbort(self: *OpaContext, msg: []const u8) void {
        self.aborted = true;
        self.abort_message = msg;
    }

    pub fn wasAborted(self: *const OpaContext) bool {
        return self.aborted;
    }

    pub fn getAbortMessage(self: *const OpaContext) ?[]const u8 {
        return self.abort_message;
    }

    pub fn reset(self: *OpaContext) void {
        self.aborted = false;
        self.abort_message = null;
    }
};

var g_opa_context: ?*OpaContext = null;

pub const FreestandingBackend = struct {
    allocator: std.mem.Allocator,
    store: *zware.Store,
    builtins_map: ?*std.StringHashMapUnmanaged(u32) = null,
    imports_registered: bool = false,

    pub fn init(allocator: std.mem.Allocator) !FreestandingBackend {
        const store = try allocator.create(zware.Store);
        store.* = zware.Store.init(allocator);
        return .{
            .allocator = allocator,
            .store = store,
        };
    }

    pub fn deinit(self: *FreestandingBackend) void {
        if (g_opa_context != null) {
            g_opa_context = null;
        }
        self.store.deinit();
        self.allocator.destroy(self.store);
    }

    pub fn setBuiltins(self: *FreestandingBackend, map: *std.StringHashMapUnmanaged(u32)) void {
        self.builtins_map = map;
    }

    pub fn registerOpaImports(self: *FreestandingBackend) !void {
        if (self.imports_registered) return;

        try self.store.exposeMemory("env", "memory", 2, 65536);

        try self.store.exposeHostFunction(
            "env",
            "opa_abort",
            opaAbortHandler,
            0,
            &[_]zware.ValType{.I32},
            &[_]zware.ValType{},
        );

        try self.store.exposeHostFunction(
            "env",
            "opa_builtin0",
            opaBuiltin0Handler,
            0,
            &[_]zware.ValType{ .I32, .I32 },
            &[_]zware.ValType{.I32},
        );

        try self.store.exposeHostFunction(
            "env",
            "opa_builtin1",
            opaBuiltin1Handler,
            0,
            &[_]zware.ValType{ .I32, .I32, .I32 },
            &[_]zware.ValType{.I32},
        );

        try self.store.exposeHostFunction(
            "env",
            "opa_builtin2",
            opaBuiltin2Handler,
            0,
            &[_]zware.ValType{ .I32, .I32, .I32, .I32 },
            &[_]zware.ValType{.I32},
        );

        try self.store.exposeHostFunction(
            "env",
            "opa_builtin3",
            opaBuiltin3Handler,
            0,
            &[_]zware.ValType{ .I32, .I32, .I32, .I32, .I32 },
            &[_]zware.ValType{.I32},
        );

        try self.store.exposeHostFunction(
            "env",
            "opa_builtin4",
            opaBuiltin4Handler,
            0,
            &[_]zware.ValType{ .I32, .I32, .I32, .I32, .I32, .I32 },
            &[_]zware.ValType{.I32},
        );

        self.imports_registered = true;
    }

    pub fn loadModule(self: *FreestandingBackend, wasm_bytes: []const u8) !Module {
        try self.registerOpaImports();

        var module = zware.Module.init(self.allocator, wasm_bytes);
        module.decode() catch {
            module.deinit();
            return error.ModuleDecodeFailed;
        };
        return .{ .inner = module, .backend = self };
    }
};

pub const Module = struct {
    inner: zware.Module,
    backend: *FreestandingBackend,

    pub fn deinit(self: *Module) void {
        self.inner.deinit();
    }

    pub fn instantiate(self: *Module) !Instance {
        const instance = try self.backend.allocator.create(zware.Instance);
        instance.* = zware.Instance.init(self.backend.allocator, self.backend.store, self.inner);

        instance.instantiate() catch {
            instance.deinit();
            self.backend.allocator.destroy(instance);
            return error.InstantiateFailed;
        };

        return .{
            .inner = instance,
            .backend = self.backend,
        };
    }
};

pub const Instance = struct {
    inner: *zware.Instance,
    backend: *FreestandingBackend,

    pub fn deinit(self: *Instance) void {
        self.inner.deinit();
        self.backend.allocator.destroy(self.inner);
    }

    pub fn invoke(self: *Instance, name: []const u8, in_args: []u64, out_args: []u64) !void {
        self.inner.invoke(name, in_args, out_args, .{}) catch {
            return error.InvokeFailed;
        };
    }

    pub fn getMemory(self: *Instance) !Memory {
        if (self.inner.memaddrs.items.len == 0) return error.MemoryNotFound;
        const memaddr = self.inner.memaddrs.items[0];
        const mem = self.backend.store.memory(memaddr) catch return error.MemoryNotFound;
        return .{ .inner = mem };
    }
};

pub const Memory = struct {
    inner: *zware.Memory,

    pub fn read(self: *const Memory, addr: u32, len: u32) ![]const u8 {
        const slice = self.inner.memory();
        const uaddr: usize = @intCast(addr);
        const ulen: usize = @intCast(len);
        if (uaddr + ulen > slice.len) return error.OutOfBounds;
        return slice[uaddr .. uaddr + ulen];
    }

    pub fn write(self: *Memory, addr: u32, data: []const u8) !void {
        const slice = self.inner.memory();
        const uaddr: usize = @intCast(addr);
        if (uaddr + data.len > slice.len) return error.OutOfBounds;
        @memcpy(slice[uaddr .. uaddr + data.len], data);
    }

    pub fn readCString(self: *const Memory, addr: u32) ![]const u8 {
        const slice = self.inner.memory();
        const uaddr: usize = @intCast(addr);
        if (uaddr >= slice.len) return error.OutOfBounds;
        const end = std.mem.indexOfScalarPos(u8, slice, uaddr, 0) orelse slice.len;
        return slice[uaddr..end];
    }

    pub fn size(self: *const Memory) usize {
        return self.inner.memory().len;
    }
};

fn opaAbortHandler(vm: *zware.VirtualMachine, _: usize) zware.WasmError!void {
    const ctx = g_opa_context orelse return;
    const addr = vm.popOperand(i32);
    const mem = ctx.instance.getMemory() catch return;
    const msg = mem.readCString(@bitCast(addr)) catch return;
    ctx.setAbort(msg);
}

fn opaBuiltin0Handler(vm: *zware.VirtualMachine, _: usize) zware.WasmError!void {
    const result = dispatchBuiltin(vm, 0);
    try vm.pushOperand(i32, result);
}

fn opaBuiltin1Handler(vm: *zware.VirtualMachine, _: usize) zware.WasmError!void {
    const result = dispatchBuiltin(vm, 1);
    try vm.pushOperand(i32, result);
}

fn opaBuiltin2Handler(vm: *zware.VirtualMachine, _: usize) zware.WasmError!void {
    const result = dispatchBuiltin(vm, 2);
    try vm.pushOperand(i32, result);
}

fn opaBuiltin3Handler(vm: *zware.VirtualMachine, _: usize) zware.WasmError!void {
    const result = dispatchBuiltin(vm, 3);
    try vm.pushOperand(i32, result);
}

fn opaBuiltin4Handler(vm: *zware.VirtualMachine, _: usize) zware.WasmError!void {
    const result = dispatchBuiltin(vm, 4);
    try vm.pushOperand(i32, result);
}

fn dispatchBuiltin(vm: *zware.VirtualMachine, arg_count: u8) i32 {
    const ctx = g_opa_context orelse return 0;

    var raw_args: [6]i32 = undefined;
    var i: usize = 0;
    const total_args: usize = 2 + arg_count;
    while (i < total_args) : (i += 1) {
        raw_args[total_args - 1 - i] = vm.popOperand(i32);
    }

    const builtin_id: u32 = @bitCast(raw_args[0]);
    const builtin_name = ctx.getBuiltinName(builtin_id) orelse return 0;

    var json_args = std.ArrayListUnmanaged(std.json.Value){};
    defer json_args.deinit(ctx.allocator);

    i = 0;
    while (i < arg_count) : (i += 1) {
        const addr = raw_args[2 + i];
        if (addr != 0) {
            if (deserializeArg(ctx, addr)) |val| {
                json_args.append(ctx.allocator, val) catch return 0;
            }
        }
    }

    const result_json = builtins.dispatch(ctx.allocator, builtin_name, json_args.items) catch return 0;
    defer ctx.allocator.free(result_json);

    return serializeResult(ctx, result_json) catch return 0;
}

fn deserializeArg(ctx: *OpaContext, addr: i32) ?std.json.Value {
    const mem = ctx.instance.getMemory() catch return null;
    const mem_slice = mem.inner.memory();

    if (addr <= 0 or addr >= @as(i32, @intCast(mem_slice.len))) return null;

    var in_args = [_]u64{@as(u32, @bitCast(addr))};
    var out_args = [_]u64{0};
    ctx.instance.invoke("opa_json_dump", &in_args, &out_args) catch return null;

    const json_addr: i32 = @bitCast(@as(u32, @truncate(out_args[0])));
    if (json_addr <= 0 or json_addr >= @as(i32, @intCast(mem_slice.len))) return null;

    const uaddr: usize = @intCast(json_addr);
    const end = std.mem.indexOfScalarPos(u8, mem_slice, uaddr, 0) orelse return null;
    const json_str = mem_slice[uaddr..end];

    return std.json.parseFromSliceLeaky(std.json.Value, ctx.allocator, json_str, .{}) catch null;
}

fn serializeResult(ctx: *OpaContext, json_str: []const u8) !i32 {
    const len: i32 = @intCast(json_str.len);

    var malloc_args = [_]u64{@as(u32, @intCast(len + 1))};
    var malloc_out = [_]u64{0};
    try ctx.instance.invoke("opa_malloc", &malloc_args, &malloc_out);

    const wasm_addr: u32 = @truncate(malloc_out[0]);
    var mem = try ctx.instance.getMemory();
    try mem.write(wasm_addr, json_str);

    const mem_slice = mem.inner.memory();
    mem_slice[wasm_addr + json_str.len] = 0;

    var parse_args = [_]u64{ wasm_addr, @as(u32, @intCast(len)) };
    var parse_out = [_]u64{0};
    try ctx.instance.invoke("opa_json_parse", &parse_args, &parse_out);

    const result: i32 = @bitCast(@as(u32, @truncate(parse_out[0])));
    if (result == 0) return error.JsonParseFailed;
    return result;
}

pub fn setContext(ctx: *OpaContext) void {
    g_opa_context = ctx;
}

pub fn clearContext() void {
    g_opa_context = null;
}
