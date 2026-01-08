//! OPA WASM instance management.

const std = @import("std");
const backend = @import("backends/backend.zig");
const options = @import("options");
const Policy = @import("policy.zig").Policy;
const MemoryManager = @import("memory/manager.zig").MemoryManager;

const BackendImpl = switch (options.backend) {
    .wasmer => @import("backends/wasmer.zig").WasmerBackend,
    .zware => @import("backends/zware.zig").ZwareBackend,
    .freestanding => @import("backends/freestanding.zig").FreestandingBackend,
};
const LogLevel = switch (options.backend) {
    .wasmer => @import("backends/wasmer.zig").LogLevel,
    .zware => @import("backends/zware.zig").LogLevel,
    .freestanding => @import("backends/freestanding.zig").LogLevel,
};

/// A live OPA WASM instance ready for policy evaluation.
pub const Instance = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    policy: *const Policy,
    wasm_instance: backend.Instance,
    memory: backend.Memory,
    memory_manager: MemoryManager,
    builtins: std.StringHashMapUnmanaged(u32) = .{},
    entrypoints: std.StringHashMapUnmanaged(u32) = .{},
    data_addr: ?u32 = null,
    data_heap_ptr: ?u32 = null,

    pub const CreateError = error{
        InstantiationFailed,
        MemoryNotFound,
        MissingExport,
        OutOfMemory,
    };

    /// Creates a new instance from a compiled policy.
    pub fn create(allocator: std.mem.Allocator, policy: *const Policy) CreateError!Self {
        const wasm_instance = policy.module.instantiate(.{}) catch return error.InstantiationFailed;
        const memory = wasm_instance.getMemory("memory") orelse return error.MemoryNotFound;

        var memory_manager = MemoryManager.init(allocator, memory);
        memory_manager.cacheOpsFunctions(wasm_instance);

        var self = Self{
            .allocator = allocator,
            .policy = policy,
            .wasm_instance = wasm_instance,
            .memory = memory,
            .memory_manager = memory_manager,
        };

        try self.parseMetadata();
        return self;
    }

    fn parseMetadata(self: *Self) CreateError!void {
        try self.parseJsonMap("builtins", &self.builtins);
        try self.parseJsonMap("entrypoints", &self.entrypoints);
    }

    fn parseJsonMap(self: *Self, func_name: []const u8, map: *std.StringHashMapUnmanaged(u32)) CreateError!void {
        const func = self.wasm_instance.getFunc(func_name) orelse return;
        const opa_json_dump = self.wasm_instance.getFunc("opa_json_dump") orelse return;

        const value_addr: u32 = @bitCast(func.call0() catch return error.InstantiationFailed);
        if (value_addr == 0) return;

        const json_str_addr: u32 = @bitCast(opa_json_dump.call1(@bitCast(value_addr)) catch return error.InstantiationFailed);
        if (json_str_addr == 0) return;

        const json_str = self.memory_manager.readCString(json_str_addr) catch return error.InstantiationFailed;

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{}) catch return error.InstantiationFailed;
        defer parsed.deinit();

        if (parsed.value != .object) return;

        var iter = parsed.value.object.iterator();
        while (iter.next()) |entry| {
            const name = self.allocator.dupe(u8, entry.key_ptr.*) catch return error.OutOfMemory;
            const id: u32 = switch (entry.value_ptr.*) {
                .integer => |i| @intCast(i),
                else => continue,
            };
            map.put(self.allocator, name, id) catch return error.OutOfMemory;
        }
    }

    pub fn deinit(self: *Self) void {
        freeStringMap(self.allocator, &self.builtins);
        freeStringMap(self.allocator, &self.entrypoints);
        self.wasm_instance.deinit();
    }

    fn freeStringMap(allocator: std.mem.Allocator, map: *std.StringHashMapUnmanaged(u32)) void {
        var iter = map.keyIterator();
        while (iter.next()) |key| {
            allocator.free(key.*);
        }
        map.deinit(allocator);
    }

    /// Sets the base data document (persists across evaluations).
    pub fn setData(self: *Self, data_json: []const u8) !void {
        if (self.data_heap_ptr) |ptr| {
            try self.memory_manager.restoreHeapState(ptr);
        }

        const data_addr = try self.memory_manager.writeAndParseJson(data_json);
        self.data_addr = data_addr;
        self.data_heap_ptr = try self.memory_manager.saveHeapState();
    }

    /// Sets the base data document from a Zig value (serializes to JSON).
    pub fn setDataValue(self: *Self, value: anytype) !void {
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        try std.json.stringify(value, .{}, buf.writer());
        try self.setData(buf.items);
    }

    /// Evaluates a policy entrypoint with the given JSON input.
    /// Returns the result as a JSON string owned by the caller.
    pub fn evaluate(self: *Self, entrypoint: []const u8, input_json: []const u8) ![]const u8 {
        const entrypoint_id = self.entrypoints.get(entrypoint) orelse {
            self.log(.err, "unknown entrypoint: {s}", .{entrypoint});
            return error.UnknownEntrypoint;
        };
        self.log(.debug, "eval {s} (id={})", .{ entrypoint, entrypoint_id });
        return self.evaluateById(entrypoint_id, input_json);
    }

    fn log(self: *Self, level: LogLevel, comptime fmt: []const u8, args: anytype) void {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.getBackend().opa_context.log(level, msg);
    }

    /// Looks up a builtin function name by its numeric ID.
    pub fn getBuiltinName(self: *const Self, id: u32) ?[]const u8 {
        var iter = self.builtins.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* == id) return entry.key_ptr.*;
        }
        return null;
    }

    /// Evaluates a policy by entrypoint ID with the given JSON input.
    pub fn evaluateById(self: *Self, entrypoint_id: u32, input_json: []const u8) ![]const u8 {
        const backend_impl = self.getBackend();
        backend_impl.setBuiltins(&self.builtins);
        backend_impl.setOpaFunctions(
            self.memory_manager.opa_malloc_fn,
            self.memory_manager.opa_json_parse_fn,
            self.memory_manager.opa_json_dump_fn,
        );

        const saved_heap = self.data_heap_ptr orelse try self.memory_manager.saveHeapState();
        defer self.memory_manager.restoreHeapState(saved_heap) catch {};

        const opa_eval_ctx_new = self.wasm_instance.getFunc("opa_eval_ctx_new") orelse return error.MissingExport;
        const opa_eval_ctx_set_input = self.wasm_instance.getFunc("opa_eval_ctx_set_input") orelse return error.MissingExport;
        const opa_eval_ctx_set_data = self.wasm_instance.getFunc("opa_eval_ctx_set_data") orelse return error.MissingExport;
        const opa_eval_ctx_set_entrypoint = self.wasm_instance.getFunc("opa_eval_ctx_set_entrypoint") orelse return error.MissingExport;
        const opa_eval_ctx_get_result = self.wasm_instance.getFunc("opa_eval_ctx_get_result") orelse return error.MissingExport;
        const eval_fn = self.wasm_instance.getFunc("eval") orelse return error.MissingExport;

        const ctx_addr = opa_eval_ctx_new.call0() catch return error.EvalFailed;
        const input_addr = try self.memory_manager.writeAndParseJson(input_json);
        opa_eval_ctx_set_input.call2v(@bitCast(ctx_addr), @bitCast(input_addr)) catch return error.EvalFailed;

        if (self.data_addr) |data| {
            opa_eval_ctx_set_data.call2v(@bitCast(ctx_addr), @bitCast(data)) catch return error.EvalFailed;
        }

        opa_eval_ctx_set_entrypoint.call2v(@bitCast(ctx_addr), @bitCast(entrypoint_id)) catch return error.EvalFailed;
        _ = eval_fn.call1(@bitCast(ctx_addr)) catch return error.EvalFailed;

        const result_addr: u32 = @bitCast(opa_eval_ctx_get_result.call1(@bitCast(ctx_addr)) catch return error.EvalFailed);
        return self.memory_manager.dumpToJson(result_addr);
    }

    /// Evaluates a policy with a Zig value as input and parses the result into a Zig type.
    pub fn evaluateTyped(self: *Self, comptime Result: type, entrypoint: []const u8, input: anytype) !Result {
        const input_json = try self.serializeArg(input);
        defer self.allocator.free(input_json);
        const result_json = try self.evaluate(entrypoint, input_json);
        defer self.allocator.free(result_json);
        return self.deserializeResult(Result, result_json);
    }

    /// Serializes a Zig value to JSON for use as input.
    pub fn serializeArg(self: *Self, value: anytype) ![]const u8 {
        return std.json.Stringify.valueAlloc(self.allocator, value, .{});
    }

    /// Deserializes a JSON string into a Zig type.
    pub fn deserializeResult(self: *Self, comptime T: type, json: []const u8) !T {
        const parsed = try std.json.parseFromSlice(T, self.allocator, json, .{});
        defer parsed.deinit();
        return parsed.value;
    }

    pub const Error = error{
        UnknownEntrypoint,
        MissingExport,
        EvalFailed,
        OutOfMemory,
        WriteError,
        JsonParseError,
    } || MemoryManager.Error;

    pub fn wasAborted(self: *Self) bool {
        return self.getBackend().wasAborted();
    }

    pub fn getAbortMessage(self: *Self) ?[]const u8 {
        return self.getBackend().getAbortMessage();
    }

    pub fn clearAbort(self: *Self) void {
        self.getBackend().clearAbort();
    }

    fn getBackend(self: *Self) *BackendImpl {
        return @ptrCast(@alignCast(self.policy.module.backend_ptr));
    }
};

/// Thread-safe pool of reusable instances for high-throughput scenarios.
pub const InstancePool = struct {
    const Self = @This();

    policy: *const Policy,
    allocator: std.mem.Allocator,
    available: std.ArrayList(*Instance),
    mutex: std.Thread.Mutex,
    max_size: usize,

    pub fn init(allocator: std.mem.Allocator, policy: *const Policy, max_size: usize) Self {
        return .{
            .policy = policy,
            .allocator = allocator,
            .available = .empty,
            .mutex = .{},
            .max_size = max_size,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.available.items) |inst| {
            inst.deinit();
            self.allocator.destroy(inst);
        }
        self.available.deinit(self.allocator);
    }

    /// Acquire an instance from the pool or create a new one if empty.
    pub fn acquire(self: *Self) !*Instance {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.available.pop()) |inst| {
            return inst;
        }

        const inst = try self.allocator.create(Instance);
        inst.* = try Instance.create(self.allocator, self.policy);
        return inst;
    }

    /// Release an instance back to the pool for reuse.
    pub fn release(self: *Self, inst: *Instance) void {
        if (inst.data_heap_ptr) |ptr| {
            inst.memory_manager.setHeapPtr(ptr) catch {};
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.available.items.len < self.max_size) {
            self.available.append(self.allocator, inst) catch {
                inst.deinit();
                self.allocator.destroy(inst);
            };
        } else {
            inst.deinit();
            self.allocator.destroy(inst);
        }
    }
};

const testing = std.testing;

test "instantiate OPA policy module" {
    if (options.backend == .freestanding) return;
    const wasm_bytes = @embedFile("test_example_wasm");
    var wasm_backend = try BackendImpl.init(testing.allocator);
    defer wasm_backend.deinit();

    var b = wasm_backend.asBackend();
    var policy = try Policy.load(testing.allocator, &b, wasm_bytes);
    defer policy.deinit();

    var inst = try Instance.create(testing.allocator, &policy);
    defer inst.deinit();

    try testing.expect(inst.entrypoints.count() > 0);
}

test "evaluate policy - admin allowed" {
    if (options.backend == .freestanding) return;
    const wasm_bytes = @embedFile("test_example_wasm");
    var wasm_backend = try BackendImpl.init(testing.allocator);
    defer wasm_backend.deinit();

    var b = wasm_backend.asBackend();
    var policy = try Policy.load(testing.allocator, &b, wasm_bytes);
    defer policy.deinit();

    var inst = try Instance.create(testing.allocator, &policy);
    defer inst.deinit();

    const result = try inst.evaluate("example/allow", "{\"user\": \"admin\"}");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("[{\"result\":true}]", result);
}

test "evaluate policy - guest denied" {
    if (options.backend == .freestanding) return;
    const wasm_bytes = @embedFile("test_example_wasm");
    var wasm_backend = try BackendImpl.init(testing.allocator);
    defer wasm_backend.deinit();

    var b = wasm_backend.asBackend();
    var policy = try Policy.load(testing.allocator, &b, wasm_bytes);
    defer policy.deinit();

    var inst = try Instance.create(testing.allocator, &policy);
    defer inst.deinit();

    const result = try inst.evaluate("example/allow", "{\"user\": \"guest\"}");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("[{\"result\":false}]", result);
}

test "policy with builtins - sprintf" {
    if (options.backend == .freestanding) return;
    const wasm_bytes = @embedFile("test_builtin_wasm");
    var wasm_backend = try BackendImpl.init(testing.allocator);
    defer wasm_backend.deinit();

    var b = wasm_backend.asBackend();
    var policy = try Policy.load(testing.allocator, &b, wasm_bytes);
    defer policy.deinit();

    var inst = try Instance.create(testing.allocator, &policy);
    defer inst.deinit();

    try testing.expect(inst.builtins.count() > 0);

    const result = inst.evaluate("builtin_test/allow", "{\"name\": \"alice\", \"role\": \"admin\", \"email\": \"alice@example.com\", \"roles\": [\"admin\", \"user\"], \"first_name\": \"Alice\", \"last_name\": \"Smith\"}");

    if (result) |res| {
        defer testing.allocator.free(res);
        try testing.expectEqualStrings("[{\"result\":true}]", res);
    } else |err| {
        if (inst.wasAborted()) {
            std.debug.print("Policy aborted: {s}\n", .{inst.getAbortMessage() orelse "unknown"});
        }
        return err;
    }
}

test "instance pool acquire and release" {
    if (options.backend == .freestanding) return;
    const wasm_bytes = @embedFile("test_example_wasm");
    var wasm_backend = try BackendImpl.init(testing.allocator);
    defer wasm_backend.deinit();

    var b = wasm_backend.asBackend();
    var policy = try Policy.load(testing.allocator, &b, wasm_bytes);
    defer policy.deinit();

    var pool = InstancePool.init(testing.allocator, &policy, 2);
    defer pool.deinit();

    const inst1 = try pool.acquire();
    const inst2 = try pool.acquire();

    try testing.expect(inst1 != inst2);

    pool.release(inst1);
    const inst3 = try pool.acquire();
    try testing.expect(inst1 == inst3);

    pool.release(inst2);
    pool.release(inst3);
}

// Regression test: OpaContext must have builtins and WASM functions connected for custom builtins to work.
test "builtins are connected to backend context" {
    if (options.backend == .freestanding) return;
    const wasm_bytes = @embedFile("test_builtin_wasm");
    var wasm_backend = try BackendImpl.init(testing.allocator);
    defer wasm_backend.deinit();

    var b = wasm_backend.asBackend();
    var policy = try Policy.load(testing.allocator, &b, wasm_bytes);
    defer policy.deinit();

    var inst = try Instance.create(testing.allocator, &policy);
    defer inst.deinit();

    try testing.expect(inst.builtins.count() > 0);

    const result = inst.evaluate("builtin_test/allow", "{}");
    if (result) |res| {
        defer testing.allocator.free(res);
        try testing.expect(res.len > 0);
    } else |_| {}

    try testing.expect(wasm_backend.opa_context.builtins != null);
    try testing.expect(wasm_backend.opa_context.json_dump_fn != null);
    try testing.expect(wasm_backend.opa_context.json_parse_fn != null);
    try testing.expect(wasm_backend.opa_context.malloc_fn != null);
}
