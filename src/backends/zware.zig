//! zware backend implementation for the WASM runtime interface.

const std = @import("std");
const backend = @import("backend.zig");
const zware = @import("zware");
const builtins = @import("../builtins/builtins.zig");

pub const LogLevel = enum { none, err, warn, info, debug, trace };
pub const LogCallback = *const fn (LogLevel, []const u8) void;

/// Runtime context for OPA policy evaluation.
pub const OpaContext = struct {
    store: ?*zware.Store = null,
    builtins: ?*std.StringHashMapUnmanaged(u32) = null,
    aborted: bool = false,
    abort_message: ?[]const u8 = null,
    allocator: ?std.mem.Allocator = null,
    json_dump_fn: ?backend.Func = null,
    json_parse_fn: ?backend.Func = null,
    malloc_fn: ?backend.Func = null,
    log_callback: ?LogCallback = null,
    log_level: LogLevel = .none,

    pub fn log(self: *const OpaContext, level: LogLevel, msg: []const u8) void {
        if (@intFromEnum(level) <= @intFromEnum(self.log_level)) {
            if (self.log_callback) |cb| cb(level, msg);
        }
    }

    pub fn getBuiltinName(self: *const OpaContext, id: u32) ?[]const u8 {
        const map = self.builtins orelse return null;
        var it = map.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == id) return entry.key_ptr.*;
        }
        return null;
    }

    pub fn reset(self: *OpaContext) void {
        self.aborted = false;
        if (self.abort_message) |msg| {
            if (self.allocator) |alloc| {
                alloc.free(msg);
            }
        }
        self.abort_message = null;
    }

    pub fn setAbort(self: *OpaContext, addr: i32) void {
        self.aborted = true;
        if (self.store) |store| {
            const mem = store.memory(0) catch return;
            const mem_slice = mem.memory();
            const uaddr: usize = @intCast(addr);
            if (uaddr < mem_slice.len) {
                var end = uaddr;
                while (end < mem_slice.len and mem_slice[end] != 0) : (end += 1) {}
                const msg = mem_slice[uaddr..end];
                if (self.allocator) |alloc| {
                    if (self.abort_message) |old_msg| {
                        alloc.free(old_msg);
                    }
                    self.abort_message = alloc.dupe(u8, msg) catch null;
                }
            }
        }
    }
};

threadlocal var g_opa_context: ?*OpaContext = null;

/// The zware-based WASM backend.
pub const ZwareBackend = struct {
    allocator: std.mem.Allocator,
    store: *zware.Store, // Heap-allocated to avoid stack corruption during deep WASM execution
    opa_context: OpaContext = .{},
    imports_registered: bool = false,

    pub fn setLogCallback(self: *ZwareBackend, callback: LogCallback, level: LogLevel) void {
        self.opa_context.log_callback = callback;
        self.opa_context.log_level = level;
    }

    pub fn init(allocator: std.mem.Allocator) !ZwareBackend {
        const store = try allocator.create(zware.Store);
        store.* = zware.Store.init(allocator);
        return .{
            .allocator = allocator,
            .store = store,
        };
    }

    pub fn deinit(self: *ZwareBackend) void {
        self.opa_context.reset();
        self.store.deinit();
        self.allocator.destroy(self.store);
    }

    pub fn asBackend(self: *ZwareBackend) backend.Backend {
        return .{ .ptr = self, .vtable = &backend_vtable };
    }

    pub fn wasAborted(self: *const ZwareBackend) bool {
        return self.opa_context.aborted;
    }

    pub fn getAbortMessage(self: *const ZwareBackend) ?[]const u8 {
        return self.opa_context.abort_message;
    }

    pub fn clearAbort(self: *ZwareBackend) void {
        self.opa_context.reset();
    }

    pub fn setBuiltins(self: *ZwareBackend, builtins_ptr: *std.StringHashMapUnmanaged(u32)) void {
        self.opa_context.builtins = builtins_ptr;
    }

    pub fn setOpaFunctions(
        self: *ZwareBackend,
        malloc_fn: ?backend.Func,
        json_parse_fn: ?backend.Func,
        json_dump_fn: ?backend.Func,
    ) void {
        self.opa_context.malloc_fn = malloc_fn;
        self.opa_context.json_parse_fn = json_parse_fn;
        self.opa_context.json_dump_fn = json_dump_fn;
    }

    pub fn registerOpaImports(self: *ZwareBackend) !void {
        if (self.imports_registered) return;

        self.opa_context.store = self.store;
        self.opa_context.allocator = self.allocator;

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
};

const backend_vtable = backend.Backend.BackendVTable{
    .deinit = backendDeinit,
    .loadModule = backendLoadModule,
};

fn backendDeinit(ptr: *anyopaque) void {
    const self: *ZwareBackend = @ptrCast(@alignCast(ptr));
    self.deinit();
}

fn backendLoadModule(ptr: *anyopaque, wasm_bytes: []const u8) backend.Error!backend.Module {
    const self: *ZwareBackend = @ptrCast(@alignCast(ptr));

    self.registerOpaImports() catch return backend.Error.InstanceInit;

    var module = zware.Module.init(self.allocator, wasm_bytes);
    module.decode() catch {
        module.deinit();
        return backend.Error.ModuleValidation;
    };

    const module_data = self.allocator.create(ModuleData) catch {
        module.deinit();
        return backend.Error.OutOfMemory;
    };
    module_data.* = .{
        .module = module,
        .backend = self,
    };

    return .{
        .ptr = module_data,
        .vtable = &module_vtable,
        .backend_ptr = @ptrCast(self),
    };
}

const ModuleData = struct {
    module: zware.Module,
    backend: *ZwareBackend,
};

const module_vtable = backend.Module.ModuleVTable{
    .deinit = moduleDeinit,
    .instantiate = moduleInstantiate,
};

fn moduleDeinit(ptr: *anyopaque) void {
    const data: *ModuleData = @ptrCast(@alignCast(ptr));
    data.module.deinit();
    data.backend.allocator.destroy(data);
}

fn moduleInstantiate(
    ptr: *anyopaque,
    backend_ptr: *anyopaque,
    imports: backend.Imports,
) backend.Error!backend.Instance {
    const data: *ModuleData = @ptrCast(@alignCast(ptr));
    const zb: *ZwareBackend = @ptrCast(@alignCast(backend_ptr));
    _ = imports;

    g_opa_context = &zb.opa_context;

    const instance_data = zb.allocator.create(InstanceData) catch {
        return backend.Error.OutOfMemory;
    };
    instance_data.* = .{
        .instance = zware.Instance.init(zb.allocator, zb.store, data.module),
        .module = data,
        .backend = zb,
        .allocator = zb.allocator,
        .func_allocations = .{},
        .memory_allocations = .{},
    };

    instance_data.instance.instantiate() catch |err| {
        std.debug.print("zware instantiate error: {}\n", .{err});
        instance_data.instance.deinit();
        zb.allocator.destroy(instance_data);
        return backend.Error.InstanceInit;
    };

    return .{
        .ptr = instance_data,
        .vtable = &instance_vtable,
        .module_ptr = ptr,
    };
}

const InstanceData = struct {
    instance: zware.Instance,
    module: *ModuleData,
    backend: *ZwareBackend,
    allocator: std.mem.Allocator,
    func_allocations: std.ArrayList(*FuncData),
    memory_allocations: std.ArrayList(*MemoryData),
};

const instance_vtable = backend.Instance.InstanceVTable{
    .deinit = instanceDeinit,
    .getFunc = instanceGetFunc,
    .getMemory = instanceGetMemory,
    .getGlobal = instanceGetGlobal,
};

fn instanceDeinit(ptr: *anyopaque) void {
    const data: *InstanceData = @ptrCast(@alignCast(ptr));
    for (data.func_allocations.items) |func_data| {
        data.allocator.free(func_data.export_name);
        data.allocator.destroy(func_data);
    }
    data.func_allocations.deinit(data.allocator);
    for (data.memory_allocations.items) |mem_data| {
        data.allocator.destroy(mem_data);
    }
    data.memory_allocations.deinit(data.allocator);
    data.instance.deinit();
    data.allocator.destroy(data);
}

fn instanceGetFunc(ptr: *anyopaque, module_ptr: *anyopaque, name: []const u8) ?backend.Func {
    const data: *InstanceData = @ptrCast(@alignCast(ptr));
    _ = module_ptr;

    _ = data.module.module.getExport(.Func, name) catch return null;

    const name_copy = data.allocator.dupe(u8, name) catch return null;
    const func_data = data.allocator.create(FuncData) catch {
        data.allocator.free(name_copy);
        return null;
    };
    func_data.* = .{
        .instance = &data.instance,
        .export_name = name_copy,
    };
    data.func_allocations.append(data.allocator, func_data) catch {
        data.allocator.free(name_copy);
        data.allocator.destroy(func_data);
        return null;
    };

    return .{ .ptr = func_data, .vtable = &func_vtable };
}

fn instanceGetMemory(ptr: *anyopaque, module_ptr: *anyopaque, name: []const u8) ?backend.Memory {
    const data: *InstanceData = @ptrCast(@alignCast(ptr));
    _ = module_ptr;
    _ = name;

    const mem = data.backend.store.memory(0) catch return null;

    const mem_data = data.allocator.create(MemoryData) catch return null;
    mem_data.* = .{
        .memory = mem,
        .store = data.backend.store,
    };
    data.memory_allocations.append(data.allocator, mem_data) catch {
        data.allocator.destroy(mem_data);
        return null;
    };

    return .{ .ptr = mem_data, .vtable = &memory_vtable };
}

fn instanceGetGlobal(ptr: *anyopaque, module_ptr: *anyopaque, name: []const u8) ?i32 {
    const data: *InstanceData = @ptrCast(@alignCast(ptr));
    _ = module_ptr;

    const global_idx = data.module.module.getExport(.Global, name) catch return null;
    const global = data.backend.store.global(@intCast(global_idx)) catch return null;
    return @bitCast(@as(u32, @truncate(global.value)));
}

const FuncData = struct {
    instance: *zware.Instance,
    export_name: []const u8,
};

const func_vtable = backend.Func.FuncVTable{
    .call0 = funcCall0,
    .call1 = funcCall1,
    .call2 = funcCall2,
    .call1v = funcCall1v,
    .call2v = funcCall2v,
};

fn funcCall0(ptr: *anyopaque) backend.Error!i32 {
    const data: *FuncData = @ptrCast(@alignCast(ptr));
    var in = [_]u64{};
    var out = [_]u64{0};
    data.instance.invoke(data.export_name, &in, &out, .{}) catch return backend.Error.FunctionCall;
    return @bitCast(@as(u32, @truncate(out[0])));
}

fn funcCall1(ptr: *anyopaque, arg0: i32) backend.Error!i32 {
    const data: *FuncData = @ptrCast(@alignCast(ptr));
    var in = [_]u64{@as(u64, @bitCast(@as(i64, arg0)))};
    var out = [_]u64{0};
    data.instance.invoke(data.export_name, &in, &out, .{}) catch return backend.Error.FunctionCall;
    return @bitCast(@as(u32, @truncate(out[0])));
}

fn funcCall2(ptr: *anyopaque, arg0: i32, arg1: i32) backend.Error!i32 {
    const data: *FuncData = @ptrCast(@alignCast(ptr));
    var in = [_]u64{
        @as(u64, @bitCast(@as(i64, arg0))),
        @as(u64, @bitCast(@as(i64, arg1))),
    };
    var out = [_]u64{0};
    data.instance.invoke(data.export_name, &in, &out, .{}) catch return backend.Error.FunctionCall;
    return @bitCast(@as(u32, @truncate(out[0])));
}

fn funcCall1v(ptr: *anyopaque, arg0: i32) backend.Error!void {
    const data: *FuncData = @ptrCast(@alignCast(ptr));
    var in = [_]u64{@as(u64, @bitCast(@as(i64, arg0)))};
    var out = [_]u64{};
    data.instance.invoke(data.export_name, &in, &out, .{}) catch return backend.Error.FunctionCall;
}

fn funcCall2v(ptr: *anyopaque, arg0: i32, arg1: i32) backend.Error!void {
    const data: *FuncData = @ptrCast(@alignCast(ptr));
    var in = [_]u64{
        @as(u64, @bitCast(@as(i64, arg0))),
        @as(u64, @bitCast(@as(i64, arg1))),
    };
    var out = [_]u64{};
    data.instance.invoke(data.export_name, &in, &out, .{}) catch return backend.Error.FunctionCall;
}

const MemoryData = struct {
    memory: *zware.Memory,
    store: *zware.Store,
};

const memory_vtable = backend.Memory.MemoryVTable{
    .data = memoryData,
    .size = memorySize,
    .grow = memoryGrow,
};

fn memoryData(ptr: *anyopaque) [*]u8 {
    const data: *MemoryData = @ptrCast(@alignCast(ptr));
    return data.memory.memory().ptr;
}

fn memorySize(ptr: *anyopaque) usize {
    const data: *MemoryData = @ptrCast(@alignCast(ptr));
    return data.memory.memory().len;
}

fn memoryGrow(ptr: *anyopaque, pages: u32) backend.Error!void {
    const data: *MemoryData = @ptrCast(@alignCast(ptr));
    _ = data.memory.grow(pages) catch return backend.Error.MemoryAccess;
}

fn opaAbortHandler(vm: *zware.VirtualMachine, _: usize) zware.WasmError!void {
    const ctx = g_opa_context orelse return;
    const addr = vm.popOperand(i32);
    ctx.setAbort(addr);
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
    const allocator = ctx.allocator orelse return 0;

    var raw_args: [6]i32 = undefined;
    var i: usize = 0;
    const total_args: usize = 2 + arg_count;
    while (i < total_args) : (i += 1) {
        raw_args[total_args - 1 - i] = vm.popOperand(i32);
    }

    const builtin_id: u32 = @intCast(raw_args[0]);

    const builtin_name = ctx.getBuiltinName(builtin_id) orelse {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "unknown builtin id: {}", .{builtin_id}) catch "unknown builtin";
        ctx.log(.err, msg);
        return 0;
    };

    ctx.log(.trace, builtin_name);

    var json_args = std.ArrayListUnmanaged(std.json.Value){};
    defer json_args.deinit(allocator);

    i = 0;
    while (i < arg_count) : (i += 1) {
        const addr = raw_args[2 + i];
        if (deserializeArg(allocator, ctx, addr)) |val| {
            json_args.append(allocator, val) catch return 0;
        }
    }

    const result_json = builtins.dispatch(allocator, builtin_name, json_args.items) catch |err| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "builtin {s} failed: {}", .{ builtin_name, err }) catch "builtin failed";
        ctx.log(.err, msg);
        return 0;
    };
    defer allocator.free(result_json);

    const result_addr = serializeJsonString(ctx, result_json) catch return 0;
    return result_addr;
}

fn deserializeArg(allocator: std.mem.Allocator, ctx: *OpaContext, addr: i32) ?std.json.Value {
    _ = allocator;
    const store = ctx.store orelse return null;
    const mem = store.memory(0) catch return null;
    const mem_slice = mem.memory();

    if (addr <= 0 or addr >= @as(i32, @intCast(mem_slice.len))) return null;

    const json_dump_fn = ctx.json_dump_fn orelse return null;
    const json_addr = json_dump_fn.call1(addr) catch return null;

    if (json_addr <= 0 or json_addr >= @as(i32, @intCast(mem_slice.len))) return null;

    const uaddr: usize = @intCast(json_addr);
    const end = std.mem.indexOfScalarPos(u8, mem_slice, uaddr, 0) orelse return null;
    const json_str = mem_slice[uaddr..end];

    const parsed = std.json.parseFromSlice(
        std.json.Value,
        std.heap.page_allocator,
        json_str,
        .{},
    ) catch return null;
    return parsed.value;
}

fn serializeJsonString(ctx: *OpaContext, json_str: []const u8) !i32 {
    const json_parse_fn = ctx.json_parse_fn orelse return error.MissingFunction;
    const store = ctx.store orelse return error.MissingStore;
    const malloc_fn = ctx.malloc_fn orelse return error.MissingFunction;

    const len: i32 = @intCast(json_str.len);
    const wasm_addr = malloc_fn.call1(len + 1) catch return error.AllocationFailed;

    const mem = store.memory(0) catch return error.MemoryAccess;
    const mem_slice = mem.memory();
    const uaddr: usize = @intCast(wasm_addr);
    @memcpy(mem_slice[uaddr .. uaddr + json_str.len], json_str);
    mem_slice[uaddr + json_str.len] = 0;

    const result_addr = json_parse_fn.call2(wasm_addr, len) catch return error.ParseFailed;
    return result_addr;
}

test "zware backend init" {
    var zb = try ZwareBackend.init(std.testing.allocator);
    defer zb.deinit();

    var wasm_backend = zb.asBackend();
    _ = &wasm_backend;
}
