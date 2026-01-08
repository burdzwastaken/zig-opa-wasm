//! WASM exports for zig-opa-wasm freestanding module.

const std = @import("std");
const freestanding = @import("backends/freestanding.zig");
const FreestandingBackend = freestanding.FreestandingBackend;
const Module = freestanding.Module;
const Instance = freestanding.Instance;
const OpaContext = freestanding.OpaContext;

var heap_buffer: [16 * 1024 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&heap_buffer);
const allocator = fba.allocator();

var io_buffer: [4 * 1024 * 1024]u8 = undefined;
var result_buffer: [1 * 1024 * 1024]u8 = undefined;
var result_len: u32 = 0;

const PolicyInstance = struct {
    name: []const u8,
    backend: FreestandingBackend,
    module: Module,
    instance: Instance,
    builtins_map: std.StringHashMapUnmanaged(u32),
    entrypoints: std.StringHashMapUnmanaged(u32),
    data_addr: i32 = 0,
    base_heap_ptr: i32 = 0,

    const Self = @This();

    fn create(name: []const u8, wasm_bytes: []const u8) !*Self {
        const name_copy = try allocator.dupe(u8, name);
        errdefer allocator.free(name_copy);

        var backend = try FreestandingBackend.init(allocator);
        errdefer backend.deinit();

        var module = try backend.loadModule(wasm_bytes);
        errdefer module.deinit();

        var instance = try module.instantiate();
        errdefer instance.deinit();

        const policy = try allocator.create(Self);
        policy.* = .{
            .name = name_copy,
            .backend = backend,
            .module = module,
            .instance = instance,
            .builtins_map = .{},
            .entrypoints = .{},
        };

        policy.parseMetadata() catch {};
        policy.base_heap_ptr = policy.callFunc0("opa_heap_ptr_get") catch 0;

        return policy;
    }

    fn parseMetadata(self: *Self) !void {
        try self.parseJsonMap("builtins", &self.builtins_map);
        try self.parseJsonMap("entrypoints", &self.entrypoints);
    }

    fn parseJsonMap(self: *Self, func_name: []const u8, map: *std.StringHashMapUnmanaged(u32)) !void {
        const value_addr = self.callFunc0(func_name) catch return;
        if (value_addr == 0) return;

        const json_str = self.dumpJson(value_addr) catch return;
        defer allocator.free(json_str);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch return;
        defer parsed.deinit();

        if (parsed.value != .object) return;

        var iter = parsed.value.object.iterator();
        while (iter.next()) |entry| {
            const key = allocator.dupe(u8, entry.key_ptr.*) catch continue;
            const id: u32 = switch (entry.value_ptr.*) {
                .integer => |i| @intCast(i),
                else => {
                    allocator.free(key);
                    continue;
                },
            };
            map.put(allocator, key, id) catch {
                allocator.free(key);
            };
        }
    }

    fn setData(self: *Self, data_json: []const u8) !void {
        self.data_addr = try self.writeAndParseJson(data_json);
        self.base_heap_ptr = try self.callFunc0("opa_heap_ptr_get");
    }

    fn evaluate(self: *Self, entrypoint: []const u8, input_json: []const u8) ![]const u8 {
        const entrypoint_id = self.entrypoints.get(entrypoint) orelse return error.UnknownEntrypoint;

        var ctx = OpaContext{
            .backend = &self.backend,
            .instance = &self.instance,
            .builtins = &self.builtins_map,
            .allocator = allocator,
        };
        freestanding.setContext(&ctx);
        defer freestanding.clearContext();

        // Reset heap pointer to base for clean evaluation
        if (self.base_heap_ptr != 0) {
            self.callFunc1v("opa_heap_ptr_set", self.base_heap_ptr) catch {};
        }

        const ctx_addr = self.callFunc0("opa_eval_ctx_new") catch return error.EvalCtxNewFailed;
        const input_addr = self.writeAndParseJson(input_json) catch return error.InputParseFailed;

        self.callFunc2v("opa_eval_ctx_set_input", ctx_addr, input_addr) catch return error.SetInputFailed;

        if (self.data_addr != 0) {
            self.callFunc2v("opa_eval_ctx_set_data", ctx_addr, self.data_addr) catch return error.SetDataFailed;
        }

        self.callFunc2v("opa_eval_ctx_set_entrypoint", ctx_addr, @intCast(entrypoint_id)) catch return error.SetEntrypointFailed;

        _ = self.callFunc1("eval", ctx_addr) catch return error.EvalFailed;

        if (ctx.wasAborted()) {
            if (ctx.getAbortMessage()) |msg| {
                writeError(msg);
            }
            return error.PolicyAborted;
        }

        const result_addr = self.callFunc1("opa_eval_ctx_get_result", ctx_addr) catch return error.GetResultFailed;
        return self.dumpJson(result_addr);
    }

    fn callFunc0(self: *Self, name: []const u8) !i32 {
        var out_args = [_]u64{0};
        self.instance.invoke(name, &.{}, &out_args) catch return error.InvokeFailed;
        return @bitCast(@as(u32, @truncate(out_args[0])));
    }

    fn callFunc1(self: *Self, name: []const u8, arg0: i32) !i32 {
        const in_args = [_]u64{@as(u32, @bitCast(arg0))};
        var out_args = [_]u64{0};
        self.instance.invoke(name, @constCast(&in_args), &out_args) catch return error.InvokeFailed;
        return @bitCast(@as(u32, @truncate(out_args[0])));
    }

    fn callFunc1v(self: *Self, name: []const u8, arg0: i32) !void {
        const in_args = [_]u64{@as(u32, @bitCast(arg0))};
        const out_args: []u64 = &.{};
        self.instance.invoke(name, @constCast(&in_args), @constCast(out_args)) catch return error.InvokeFailed;
    }

    fn callFunc2(self: *Self, name: []const u8, arg0: i32, arg1: i32) !i32 {
        const in_args = [_]u64{ @as(u32, @bitCast(arg0)), @as(u32, @bitCast(arg1)) };
        var out_args = [_]u64{0};
        self.instance.invoke(name, @constCast(&in_args), &out_args) catch return error.InvokeFailed;
        return @bitCast(@as(u32, @truncate(out_args[0])));
    }

    fn callFunc2v(self: *Self, name: []const u8, arg0: i32, arg1: i32) !void {
        const in_args = [_]u64{ @as(u32, @bitCast(arg0)), @as(u32, @bitCast(arg1)) };
        const out_args: []u64 = &.{};
        self.instance.invoke(name, @constCast(&in_args), @constCast(out_args)) catch return error.InvokeFailed;
    }

    fn writeAndParseJson(self: *Self, json: []const u8) !i32 {
        const addr = try self.callFunc1("opa_malloc", @intCast(json.len));
        var mem = try self.instance.getMemory();
        try mem.write(@bitCast(addr), json);

        var in_args = [_]u64{ @as(u32, @bitCast(addr)), json.len };
        var out_args = [_]u64{0};
        try self.instance.invoke("opa_json_parse", &in_args, &out_args);

        const result: i32 = @bitCast(@as(u32, @truncate(out_args[0])));
        if (result == 0) return error.JsonParseFailed;
        return result;
    }

    fn dumpJson(self: *Self, value_addr: i32) ![]const u8 {
        var in_args = [_]u64{@as(u32, @bitCast(value_addr))};
        var out_args = [_]u64{0};
        try self.instance.invoke("opa_json_dump", &in_args, &out_args);

        const str_addr: u32 = @truncate(out_args[0]);
        if (str_addr == 0) return error.JsonDumpFailed;

        const mem = try self.instance.getMemory();
        const json_str = try mem.readCString(str_addr);
        return allocator.dupe(u8, json_str);
    }

    fn deinit(self: *Self) void {
        freeStringMap(&self.builtins_map);
        freeStringMap(&self.entrypoints);
        self.instance.deinit();
        self.module.deinit();
        self.backend.deinit();
        allocator.free(self.name);
        allocator.destroy(self);
    }
};

fn freeStringMap(map: *std.StringHashMapUnmanaged(u32)) void {
    var iter = map.keyIterator();
    while (iter.next()) |key| {
        allocator.free(key.*);
    }
    map.deinit(allocator);
}

var policies: std.StringHashMapUnmanaged(*PolicyInstance) = .{};
var initialized: bool = false;

fn writeError(msg: []const u8) void {
    const len = @min(msg.len, result_buffer.len - 1);
    @memcpy(result_buffer[0..len], msg[0..len]);
    result_buffer[len] = 0;
    result_len = @intCast(len);
}

fn writeResult(data: []const u8) void {
    const len = @min(data.len, result_buffer.len);
    @memcpy(result_buffer[0..len], data[0..len]);
    result_len = @intCast(len);
}

fn logError(msg: []const u8, err: anyerror) void {
    var buf: [256]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "{s}: {}", .{ msg, err }) catch msg;
    writeError(formatted);
}

export fn init() i32 {
    if (initialized) return 0;
    policies = .{};
    initialized = true;
    result_len = 0;
    return 0;
}

export fn loadPolicy(name_ptr: u32, name_len: u32, wasm_ptr: u32, wasm_len: u32) i32 {
    if (!initialized) {
        writeError("not initialized");
        return -1;
    }
    if (name_ptr + name_len > io_buffer.len or wasm_ptr + wasm_len > io_buffer.len) {
        writeError("buffer overflow");
        return -2;
    }

    const name = io_buffer[name_ptr .. name_ptr + name_len];
    const wasm_bytes = io_buffer[wasm_ptr .. wasm_ptr + wasm_len];

    if (policies.get(name) != null) {
        writeError("policy already loaded");
        return -3;
    }

    const policy = PolicyInstance.create(name, wasm_bytes) catch |err| {
        logError("failed to create policy", err);
        return -4;
    };

    const name_copy = allocator.dupe(u8, name) catch {
        policy.deinit();
        writeError("out of memory");
        return -5;
    };

    policies.put(allocator, name_copy, policy) catch {
        allocator.free(name_copy);
        policy.deinit();
        writeError("out of memory");
        return -5;
    };

    result_len = 0;
    return 0;
}

export fn unloadPolicy(name_ptr: u32, name_len: u32) i32 {
    if (!initialized) {
        writeError("not initialized");
        return -1;
    }
    if (name_ptr + name_len > io_buffer.len) {
        writeError("buffer overflow");
        return -2;
    }

    const name = io_buffer[name_ptr .. name_ptr + name_len];
    const kv = policies.fetchRemove(name) orelse {
        writeError("policy not found");
        return -3;
    };

    kv.value.deinit();
    allocator.free(kv.key);
    result_len = 0;
    return 0;
}

export fn setData(name_ptr: u32, name_len: u32, data_ptr: u32, data_len: u32) i32 {
    if (!initialized) {
        writeError("not initialized");
        return -1;
    }
    if (name_ptr + name_len > io_buffer.len or data_ptr + data_len > io_buffer.len) {
        writeError("buffer overflow");
        return -2;
    }

    const name = io_buffer[name_ptr .. name_ptr + name_len];
    const data_json = io_buffer[data_ptr .. data_ptr + data_len];

    const policy = policies.get(name) orelse {
        writeError("policy not found");
        return -3;
    };

    policy.setData(data_json) catch |err| {
        logError("failed to set data", err);
        return -4;
    };

    result_len = 0;
    return 0;
}

export fn evaluate(name_ptr: u32, name_len: u32, entrypoint_ptr: u32, entrypoint_len: u32, input_ptr: u32, input_len: u32) i32 {
    if (!initialized) {
        writeError("not initialized");
        return -1;
    }
    if (name_ptr + name_len > io_buffer.len or entrypoint_ptr + entrypoint_len > io_buffer.len or input_ptr + input_len > io_buffer.len) {
        writeError("buffer overflow");
        return -2;
    }

    const name = io_buffer[name_ptr .. name_ptr + name_len];
    const entrypoint = io_buffer[entrypoint_ptr .. entrypoint_ptr + entrypoint_len];
    const input_json = io_buffer[input_ptr .. input_ptr + input_len];

    const policy = policies.get(name) orelse {
        writeError("policy not found");
        return -3;
    };

    const result = policy.evaluate(entrypoint, input_json) catch |err| {
        logError("evaluation failed", err);
        return -4;
    };
    defer allocator.free(result);

    writeResult(result);
    return @intCast(result_len);
}

export fn getLoadedPolicies() i32 {
    if (!initialized) {
        writeError("not initialized");
        return -1;
    }

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    buf.append(allocator, '[') catch return -2;
    var first = true;
    var iter = policies.keyIterator();
    while (iter.next()) |key| {
        if (!first) buf.append(allocator, ',') catch continue;
        first = false;
        buf.append(allocator, '"') catch continue;
        buf.appendSlice(allocator, key.*) catch continue;
        buf.append(allocator, '"') catch continue;
    }
    buf.append(allocator, ']') catch return -2;

    writeResult(buf.items);
    return @intCast(result_len);
}

export fn getEntrypoints(name_ptr: u32, name_len: u32) i32 {
    if (!initialized) {
        writeError("not initialized");
        return -1;
    }
    if (name_ptr + name_len > io_buffer.len) {
        writeError("buffer overflow");
        return -2;
    }

    const name = io_buffer[name_ptr .. name_ptr + name_len];
    const policy = policies.get(name) orelse {
        writeError("policy not found");
        return -3;
    };

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    buf.append(allocator, '[') catch return -4;
    var first = true;
    var ep_iter = policy.entrypoints.keyIterator();
    while (ep_iter.next()) |key| {
        if (!first) buf.append(allocator, ',') catch continue;
        first = false;
        buf.append(allocator, '"') catch continue;
        buf.appendSlice(allocator, key.*) catch continue;
        buf.append(allocator, '"') catch continue;
    }
    buf.append(allocator, ']') catch return -4;

    writeResult(buf.items);
    return @intCast(result_len);
}

export fn getIOBuffer() [*]u8 {
    return &io_buffer;
}

export fn getIOBufferSize() u32 {
    return io_buffer.len;
}

export fn getResultBuffer() [*]u8 {
    return &result_buffer;
}

export fn getResultLen() u32 {
    return result_len;
}

export fn reset() void {
    var iter = policies.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.*.deinit();
        allocator.free(entry.key_ptr.*);
    }
    policies.deinit(allocator);
    policies = .{};
    fba.reset();
    result_len = 0;
}

export fn deinit() void {
    reset();
    initialized = false;
}
