//! Wasmer backend implementation for the WASM runtime interface.

const std = @import("std");
const backend = @import("backend.zig");
const wasmer = @import("wasmer");
const builtins = @import("../builtins/builtins.zig");

pub const LogLevel = enum { none, err, warn, info, debug, trace };
pub const LogCallback = *const fn (LogLevel, []const u8) void;

/// Runtime context for OPA policy evaluation.
pub const OpaContext = struct {
    memory: ?*wasmer.Memory = null,
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
        if (self.memory) |mem| {
            const d = mem.toSlice();
            const uaddr: usize = @intCast(addr);
            if (uaddr < d.len) {
                var end = uaddr;
                while (end < d.len and d[end] != 0) : (end += 1) {}
                const msg = d[uaddr..end];
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

/// The Wasmer-based WASM backend.
pub const WasmerBackend = struct {
    engine: *wasmer.Engine,
    store: *wasmer.Store,
    allocator: std.mem.Allocator,
    opa_imports: ?OpaImports = null,
    opa_context: OpaContext = .{},

    pub fn setLogCallback(self: *WasmerBackend, callback: LogCallback, level: LogLevel) void {
        self.opa_context.log_callback = callback;
        self.opa_context.log_level = level;
    }

    pub fn init(allocator: std.mem.Allocator) !WasmerBackend {
        const engine = try wasmer.Engine.init();
        const store = wasmer.Store.init(engine) catch {
            engine.deinit();
            return error.StoreInit;
        };
        return .{ .engine = engine, .store = store, .allocator = allocator };
    }

    pub fn createOpaImports(self: *WasmerBackend) !void {
        self.opa_imports = try OpaImports.init(self.allocator, self.store, &self.opa_context);
    }

    pub fn deinit(self: *WasmerBackend) void {
        self.opa_context.reset();
        self.store.deinit();
        self.engine.deinit();
    }

    pub fn asBackend(self: *WasmerBackend) backend.Backend {
        return .{ .ptr = self, .vtable = &backend_vtable };
    }

    pub fn wasAborted(self: *const WasmerBackend) bool {
        return self.opa_context.aborted;
    }

    pub fn getAbortMessage(self: *const WasmerBackend) ?[]const u8 {
        return self.opa_context.abort_message;
    }

    pub fn clearAbort(self: *WasmerBackend) void {
        self.opa_context.reset();
    }

    pub fn setBuiltins(self: *WasmerBackend, builtins_ptr: *std.StringHashMapUnmanaged(u32)) void {
        self.opa_context.builtins = builtins_ptr;
    }

    pub fn setOpaFunctions(self: *WasmerBackend, malloc_fn: ?backend.Func, json_parse_fn: ?backend.Func, json_dump_fn: ?backend.Func) void {
        self.opa_context.malloc_fn = malloc_fn;
        self.opa_context.json_parse_fn = json_parse_fn;
        self.opa_context.json_dump_fn = json_dump_fn;
    }
};

const backend_vtable = backend.Backend.BackendVTable{
    .deinit = backendDeinit,
    .loadModule = backendLoadModule,
};

fn backendDeinit(ptr: *anyopaque) void {
    const self: *WasmerBackend = @ptrCast(@alignCast(ptr));
    self.deinit();
}

fn backendLoadModule(ptr: *anyopaque, wasm_bytes: []const u8) backend.Error!backend.Module {
    const self: *WasmerBackend = @ptrCast(@alignCast(ptr));
    const module = wasmer.Module.init(self.store, wasm_bytes) catch {
        return backend.Error.ModuleInit;
    };

    const module_data = self.allocator.create(ModuleData) catch {
        return backend.Error.OutOfMemory;
    };
    module_data.* = .{
        .module = module,
        .backend = self,
    };

    return .{ .ptr = module_data, .vtable = &module_vtable, .backend_ptr = @ptrCast(self) };
}

const ModuleData = struct {
    module: *wasmer.Module,
    backend: *WasmerBackend,
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

fn moduleInstantiate(ptr: *anyopaque, backend_ptr: *anyopaque, imports: backend.Imports) backend.Error!backend.Instance {
    const data: *ModuleData = @ptrCast(@alignCast(ptr));
    const wb: *WasmerBackend = @ptrCast(@alignCast(backend_ptr));
    _ = imports;

    if (wb.opa_imports == null) {
        wb.createOpaImports() catch return backend.Error.InstanceInit;
    }
    const opa = &(wb.opa_imports orelse return backend.Error.InstanceInit);
    var extern_imports = opa.asExternVec();

    const instance = wasmer.Instance.initFromImports(wb.store, data.module, &extern_imports) catch |err| {
        std.debug.print("Instance init failed: {}\n", .{err});
        return backend.Error.InstanceInit;
    };

    const instance_data = wb.allocator.create(InstanceData) catch {
        return backend.Error.OutOfMemory;
    };
    instance_data.* = .{
        .instance = instance,
        .module = data.module,
        .allocator = wb.allocator,
        .imported_memory = opa.memory,
    };

    return .{ .ptr = instance_data, .vtable = &instance_vtable, .module_ptr = data.module };
}

const InstanceData = struct {
    instance: *wasmer.Instance,
    module: *wasmer.Module,
    allocator: std.mem.Allocator,
    imported_memory: ?*wasmer.Memory = null,
};

const instance_vtable = backend.Instance.InstanceVTable{
    .deinit = instanceDeinit,
    .getFunc = instanceGetFunc,
    .getMemory = instanceGetMemory,
    .getGlobal = instanceGetGlobal,
};

fn instanceDeinit(ptr: *anyopaque) void {
    const data: *InstanceData = @ptrCast(@alignCast(ptr));
    data.instance.deinit();
    data.allocator.destroy(data);
}

fn instanceGetFunc(ptr: *anyopaque, module_ptr: *anyopaque, name: []const u8) ?backend.Func {
    const data: *InstanceData = @ptrCast(@alignCast(ptr));
    const module: *wasmer.Module = @ptrCast(@alignCast(module_ptr));
    const func = data.instance.getExportFunc(module, name) orelse return null;
    return .{ .ptr = func, .vtable = &func_vtable };
}

fn instanceGetMemory(ptr: *anyopaque, module_ptr: *anyopaque, name: []const u8) ?backend.Memory {
    const data: *InstanceData = @ptrCast(@alignCast(ptr));
    const module: *wasmer.Module = @ptrCast(@alignCast(module_ptr));

    if (std.mem.eql(u8, name, "memory")) {
        if (data.imported_memory) |mem| {
            return .{ .ptr = mem, .vtable = &memory_vtable };
        }
    }

    const mem = data.instance.getExportMem(module, name) orelse return null;
    return .{ .ptr = mem, .vtable = &memory_vtable };
}

fn instanceGetGlobal(ptr: *anyopaque, module_ptr: *anyopaque, name: []const u8) ?i32 {
    _ = ptr;
    _ = module_ptr;
    _ = name;
    return null;
}

const func_vtable = backend.Func.FuncVTable{
    .call0 = funcCall0,
    .call1 = funcCall1,
    .call2 = funcCall2,
    .call1v = funcCall1v,
    .call2v = funcCall2v,
};

fn funcCall0(ptr: *anyopaque) backend.Error!i32 {
    const func: *wasmer.Func = @ptrCast(@alignCast(ptr));
    const result = func.call(i32, .{}) catch return backend.Error.FunctionCall;
    return result;
}

fn funcCall1(ptr: *anyopaque, arg0: i32) backend.Error!i32 {
    const func: *wasmer.Func = @ptrCast(@alignCast(ptr));
    const result = func.call(i32, .{arg0}) catch return backend.Error.FunctionCall;
    return result;
}

fn funcCall2(ptr: *anyopaque, arg0: i32, arg1: i32) backend.Error!i32 {
    const func: *wasmer.Func = @ptrCast(@alignCast(ptr));
    const result = func.call(i32, .{ arg0, arg1 }) catch return backend.Error.FunctionCall;
    return result;
}

fn funcCall1v(ptr: *anyopaque, arg0: i32) backend.Error!void {
    const func: *wasmer.Func = @ptrCast(@alignCast(ptr));
    _ = func.call(void, .{arg0}) catch return backend.Error.FunctionCall;
}

fn funcCall2v(ptr: *anyopaque, arg0: i32, arg1: i32) backend.Error!void {
    const func: *wasmer.Func = @ptrCast(@alignCast(ptr));
    _ = func.call(void, .{ arg0, arg1 }) catch return backend.Error.FunctionCall;
}

const memory_vtable = backend.Memory.MemoryVTable{
    .data = memoryData,
    .size = memorySize,
    .grow = memoryGrow,
};

fn memoryData(ptr: *anyopaque) [*]u8 {
    const mem: *wasmer.Memory = @ptrCast(@alignCast(ptr));
    return @ptrCast(mem.data());
}

fn memorySize(ptr: *anyopaque) usize {
    const mem: *wasmer.Memory = @ptrCast(@alignCast(ptr));
    return mem.size();
}

fn memoryGrow(ptr: *anyopaque, pages: u32) backend.Error!void {
    const mem: *wasmer.Memory = @ptrCast(@alignCast(ptr));
    _ = mem.grow(pages) catch return backend.Error.MemoryAccess;
}

/// OPA import functions and shared memory for WASM instantiation.
const OpaImports = struct {
    opa_abort: *wasmer.Func,
    opa_builtin0: *wasmer.Func,
    opa_builtin1: *wasmer.Func,
    opa_builtin2: *wasmer.Func,
    opa_builtin3: *wasmer.Func,
    opa_builtin4: *wasmer.Func,
    memory: *wasmer.Memory,
    context: *OpaContext,
    extern_cache: [7]?*wasmer.wasm.Extern = undefined,

    pub fn init(allocator: std.mem.Allocator, store: *wasmer.Store, ctx: *OpaContext) !OpaImports {
        const wasm = wasmer.wasm;

        const mem_type = try wasm.MemoryType.init(.{ .min = 2, .max = 65536 });
        defer mem_type.deinit();
        const memory = try wasmer.Memory.init(store, mem_type);

        ctx.memory = memory;
        ctx.allocator = allocator;
        ctx.reset();

        const ctx_ptr: *anyopaque = @ptrCast(ctx);

        const abort_type = wasm.FuncType.init(&.{.i32}, &.{}) orelse return error.FuncInit;
        defer abort_type.deinit();
        const opa_abort = try wasmer.Func.initWithEnv(store, abort_type, opaAbortCallback, ctx_ptr, null);

        const builtin0_type = wasm.FuncType.init(&.{ .i32, .i32 }, &.{.i32}) orelse return error.FuncInit;
        defer builtin0_type.deinit();
        const opa_builtin0 = try wasmer.Func.initWithEnv(store, builtin0_type, opaBuiltin0Callback, ctx_ptr, null);

        const builtin1_type = wasm.FuncType.init(&.{ .i32, .i32, .i32 }, &.{.i32}) orelse return error.FuncInit;
        defer builtin1_type.deinit();
        const opa_builtin1 = try wasmer.Func.initWithEnv(store, builtin1_type, opaBuiltin1Callback, ctx_ptr, null);

        const builtin2_type = wasm.FuncType.init(&.{ .i32, .i32, .i32, .i32 }, &.{.i32}) orelse return error.FuncInit;
        defer builtin2_type.deinit();
        const opa_builtin2 = try wasmer.Func.initWithEnv(store, builtin2_type, opaBuiltin2Callback, ctx_ptr, null);

        const builtin3_type = wasm.FuncType.init(&.{ .i32, .i32, .i32, .i32, .i32 }, &.{.i32}) orelse return error.FuncInit;
        defer builtin3_type.deinit();
        const opa_builtin3 = try wasmer.Func.initWithEnv(store, builtin3_type, opaBuiltin3Callback, ctx_ptr, null);

        const builtin4_type = wasm.FuncType.init(&.{ .i32, .i32, .i32, .i32, .i32, .i32 }, &.{.i32}) orelse return error.FuncInit;
        defer builtin4_type.deinit();
        const opa_builtin4 = try wasmer.Func.initWithEnv(store, builtin4_type, opaBuiltin4Callback, ctx_ptr, null);

        return .{
            .opa_abort = opa_abort,
            .opa_builtin0 = opa_builtin0,
            .opa_builtin1 = opa_builtin1,
            .opa_builtin2 = opa_builtin2,
            .opa_builtin3 = opa_builtin3,
            .opa_builtin4 = opa_builtin4,
            .memory = memory,
            .context = ctx,
        };
    }

    pub fn asExternVec(self: *OpaImports) wasmer.wasm.ExternVec {
        self.extern_cache = .{
            self.opa_builtin0.asExtern(),
            self.opa_builtin1.asExtern(),
            self.opa_builtin2.asExtern(),
            self.opa_builtin3.asExtern(),
            self.opa_builtin4.asExtern(),
            self.opa_abort.asExtern(),
            self.memory.asExtern(),
        };
        return .{ .size = self.extern_cache.len, .data = @ptrCast(&self.extern_cache) };
    }
};

fn opaAbortCallback(env: ?*anyopaque, args: ?*const wasmer.wasm.ValVec, _: ?*wasmer.wasm.ValVec) callconv(.c) ?*wasmer.wasm.Trap {
    const ctx = getContext(env) orelse return null;
    const addr = if (args) |a| a.data[0].of.i32 else 0;
    ctx.setAbort(addr);
    return null;
}

fn opaBuiltin0Callback(env: ?*anyopaque, args: ?*const wasmer.wasm.ValVec, results: ?*wasmer.wasm.ValVec) callconv(.c) ?*wasmer.wasm.Trap {
    return dispatchBuiltin(env, args, results, 0);
}

fn opaBuiltin1Callback(env: ?*anyopaque, args: ?*const wasmer.wasm.ValVec, results: ?*wasmer.wasm.ValVec) callconv(.c) ?*wasmer.wasm.Trap {
    return dispatchBuiltin(env, args, results, 1);
}

fn opaBuiltin2Callback(env: ?*anyopaque, args: ?*const wasmer.wasm.ValVec, results: ?*wasmer.wasm.ValVec) callconv(.c) ?*wasmer.wasm.Trap {
    return dispatchBuiltin(env, args, results, 2);
}

fn opaBuiltin3Callback(env: ?*anyopaque, args: ?*const wasmer.wasm.ValVec, results: ?*wasmer.wasm.ValVec) callconv(.c) ?*wasmer.wasm.Trap {
    return dispatchBuiltin(env, args, results, 3);
}

fn opaBuiltin4Callback(env: ?*anyopaque, args: ?*const wasmer.wasm.ValVec, results: ?*wasmer.wasm.ValVec) callconv(.c) ?*wasmer.wasm.Trap {
    return dispatchBuiltin(env, args, results, 4);
}

fn getContext(env: ?*anyopaque) ?*OpaContext {
    const ptr = env orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn dispatchBuiltin(env: ?*anyopaque, args: ?*const wasmer.wasm.ValVec, results: ?*wasmer.wasm.ValVec, arg_count: u8) ?*wasmer.wasm.Trap {
    const ctx = getContext(env) orelse {
        setResultNull(results);
        return null;
    };

    const allocator = ctx.allocator orelse {
        setResultNull(results);
        return null;
    };

    const builtin_id: u32 = if (args) |a| (if (a.size > 0) @intCast(a.data[0].of.i32) else 0) else 0;

    const builtin_name = ctx.getBuiltinName(builtin_id) orelse {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "unknown builtin id: {}", .{builtin_id}) catch "unknown builtin";
        ctx.log(.err, msg);
        setResultNull(results);
        return null;
    };

    ctx.log(.trace, builtin_name);

    var json_args = std.ArrayListUnmanaged(std.json.Value){};
    defer json_args.deinit(allocator);

    if (args) |a| {
        var i: usize = 2;
        while (i < @min(a.size, 2 + arg_count)) : (i += 1) {
            const addr = a.data[i].of.i32;
            if (deserializeArg(allocator, ctx, addr)) |val| {
                json_args.append(allocator, val) catch {
                    setResultNull(results);
                    return null;
                };
            }
        }
    }

    const result_json = builtins.dispatch(allocator, builtin_name, json_args.items) catch |err| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "builtin {s} failed: {}", .{ builtin_name, err }) catch "builtin failed";
        ctx.log(.err, msg);
        setResultNull(results);
        return null;
    };
    defer allocator.free(result_json);

    const result_addr = serializeJsonString(ctx, result_json) catch {
        setResultNull(results);
        return null;
    };

    if (results) |r| {
        if (r.size > 0) {
            r.data[0] = .{ .kind = .i32, .of = .{ .i32 = result_addr } };
        }
    }
    return null;
}

fn setResultNull(results: ?*wasmer.wasm.ValVec) void {
    if (results) |r| {
        if (r.size > 0) {
            r.data[0] = .{ .kind = .i32, .of = .{ .i32 = 0 } };
        }
    }
}

fn deserializeArg(allocator: std.mem.Allocator, ctx: *OpaContext, addr: i32) ?std.json.Value {
    _ = allocator;
    const memory = ctx.memory orelse return null;
    const mem_slice = memory.toSlice();

    if (addr <= 0 or addr >= @as(i32, @intCast(mem_slice.len))) return null;

    const json_dump_fn = ctx.json_dump_fn orelse return null;
    const json_addr = json_dump_fn.call1(addr) catch return null;

    if (json_addr <= 0 or json_addr >= @as(i32, @intCast(mem_slice.len))) return null;

    const uaddr: usize = @intCast(json_addr);
    const end = std.mem.indexOfScalarPos(u8, mem_slice, uaddr, 0) orelse return null;
    const json_str = mem_slice[uaddr..end];

    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, json_str, .{}) catch return null;
    return parsed.value;
}

fn serializeJsonString(ctx: *OpaContext, json_str: []const u8) !i32 {
    const json_parse_fn = ctx.json_parse_fn orelse return error.MissingFunction;
    const memory = ctx.memory orelse return error.MissingMemory;
    const malloc_fn = ctx.malloc_fn orelse return error.MissingFunction;

    const len: i32 = @intCast(json_str.len);
    const wasm_addr = malloc_fn.call1(len + 1) catch return error.AllocationFailed;

    const mem_slice = memory.data();
    const uaddr: usize = @intCast(wasm_addr);
    @memcpy(mem_slice[uaddr .. uaddr + json_str.len], json_str);
    mem_slice[uaddr + json_str.len] = 0;

    const result_addr = json_parse_fn.call2(wasm_addr, len) catch return error.ParseFailed;
    return result_addr;
}

fn serializeResult(allocator: std.mem.Allocator, ctx: *OpaContext, value: std.json.Value) !i32 {
    const json_parse_fn = ctx.json_parse_fn orelse return error.MissingFunction;
    const memory = ctx.memory orelse return error.MissingMemory;
    const malloc_fn = ctx.malloc_fn orelse return error.MissingFunction;

    const json_str = std.json.Stringify.valueAlloc(allocator, value, .{}) catch return error.SerializationFailed;
    defer allocator.free(json_str);

    const len: i32 = @intCast(json_str.len);
    const wasm_addr = malloc_fn.call1(len + 1) catch return error.AllocationFailed;

    const mem_slice = memory.data();
    const uaddr: usize = @intCast(wasm_addr);
    @memcpy(mem_slice[uaddr .. uaddr + json_str.len], json_str);
    mem_slice[uaddr + json_str.len] = 0;

    const result_addr = json_parse_fn.call2(wasm_addr, len) catch return error.ParseFailed;
    return result_addr;
}

test "wasmer backend init" {
    var wb = try WasmerBackend.init(std.testing.allocator);
    defer wb.deinit();

    var wasm_backend = wb.asBackend();
    _ = &wasm_backend;
}

test "wasmer load and instantiate module" {
    const wasm_bytes = @embedFile("test_add_wasm");
    var wb = try WasmerBackend.init(std.testing.allocator);
    defer wb.deinit();

    var wasm_backend = wb.asBackend();
    var module = try wasm_backend.loadModule(wasm_bytes);
    defer module.deinit();

    var instance = try module.instantiate(.{});
    defer instance.deinit();

    const memory = instance.getMemory("memory");
    try std.testing.expect(memory != null);
}
