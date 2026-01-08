//! Evaluation context for reusable policy evaluation.
//! Manages per-evaluation state with efficient memory reuse via heap reset.

const std = @import("std");
const backend = @import("backends/backend.zig");
const MemoryManager = @import("memory/manager.zig").MemoryManager;
const Instance = @import("instance.zig").Instance;

/// Reusable evaluation context that manages per-eval state.
pub const EvaluationContext = struct {
    const Self = @This();

    instance: *Instance,
    ctx_addr: u32,
    saved_heap_ptr: u32,
    allocator: std.mem.Allocator,

    pub const Error = error{
        ContextCreationFailed,
        InputSerializationFailed,
        EntrypointNotFound,
        EvaluationFailed,
        ResultNotAvailable,
        PolicyAborted,
    } || MemoryManager.Error || std.mem.Allocator.Error || backend.Error;

    /// Create a new evaluation context from an instance.
    pub fn init(allocator: std.mem.Allocator, instance: *Instance) Error!Self {
        // Create OPA eval context
        const ctx_new = instance.wasm_instance.getFunc("opa_eval_ctx_new") orelse
            return Error.ContextCreationFailed;

        const ctx_addr: u32 = @bitCast(try ctx_new.call0());

        // Save heap state for reset between evals
        const saved_heap_ptr = try instance.memory_manager.saveHeapState();

        return Self{
            .instance = instance,
            .ctx_addr = ctx_addr,
            .saved_heap_ptr = saved_heap_ptr,
            .allocator = allocator,
        };
    }

    /// Set input document from a Zig value (serialized to JSON).
    pub fn setInput(self: *Self, input: anytype) Error!void {
        const json = std.json.stringifyAlloc(self.allocator, input, .{}) catch
            return Error.InputSerializationFailed;
        defer self.allocator.free(json);

        try self.setInputJson(json);
    }

    /// Set input document from raw JSON string.
    pub fn setInputJson(self: *Self, json: []const u8) Error!void {
        const value_addr = try self.instance.memory_manager.writeAndParseJson(json);

        const set_input = self.instance.wasm_instance.getFunc("opa_eval_ctx_set_input") orelse
            return Error.ContextCreationFailed;

        try set_input.call2v(@bitCast(self.ctx_addr), @bitCast(value_addr));
    }

    /// Set entrypoint by name.
    pub fn setEntrypoint(self: *Self, name: []const u8) Error!void {
        const id = self.instance.policy.entrypoints.get(name) orelse
            return Error.EntrypointNotFound;
        try self.setEntrypointId(id);
    }

    /// Set entrypoint by ID.
    pub fn setEntrypointId(self: *Self, id: u32) Error!void {
        const set_ep = self.instance.wasm_instance.getFunc("opa_eval_ctx_set_entrypoint") orelse
            return Error.ContextCreationFailed;

        try set_ep.call2v(@bitCast(self.ctx_addr), @bitCast(id));
    }

    /// Execute the evaluation.
    pub fn eval(self: *Self) Error!void {
        const eval_fn = self.instance.wasm_instance.getFunc("eval") orelse
            return Error.EvaluationFailed;

        const result = eval_fn.call1(@bitCast(self.ctx_addr)) catch {
            if (self.instance.wasAborted()) {
                return Error.PolicyAborted;
            }
            return Error.EvaluationFailed;
        };

        if (self.instance.wasAborted()) {
            return Error.PolicyAborted;
        }

        if (result != 0) {
            return Error.EvaluationFailed;
        }
    }

    /// Get the abort message if policy aborted.
    pub fn getAbortMessage(self: *Self) ?[]const u8 {
        return self.instance.getAbortMessage();
    }

    /// Get result as raw JSON string.
    pub fn getResultJson(self: *Self) Error![]const u8 {
        const get_result = self.instance.wasm_instance.getFunc("opa_eval_ctx_get_result") orelse
            return Error.ResultNotAvailable;

        const result_addr: u32 = @bitCast(try get_result.call1(@bitCast(self.ctx_addr)));
        if (result_addr == 0) {
            return Error.ResultNotAvailable;
        }

        return self.instance.memory_manager.dumpToJson(result_addr);
    }

    /// Get result parsed into a Zig type.
    pub fn getResult(self: *Self, comptime T: type) Error!std.json.Parsed(T) {
        const json = try self.getResultJson();
        defer self.allocator.free(json);

        return std.json.parseFromSlice(T, self.allocator, json, .{}) catch
            return Error.ResultNotAvailable;
    }

    /// Reset context for reuse (restores heap to saved state).
    pub fn reset(self: *Self) void {
        self.instance.memory_manager.restoreHeapState(self.saved_heap_ptr);
    }

    /// Full evaluation cycle: set input, eval, get result, reset.
    pub fn evaluate(self: *Self, entrypoint: []const u8, input: anytype) Error![]const u8 {
        try self.setEntrypoint(entrypoint);
        try self.setInput(input);
        try self.eval();
        const result = try self.getResultJson();
        self.reset();
        return result;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

test "evaluation context creation" {
    const testing = std.testing;
    const Policy = @import("policy.zig").Policy;
    const Inst = @import("instance.zig").Instance;
    const options = @import("options");
    const BackendImpl = switch (options.backend) {
        .wasmer => @import("backends/wasmer.zig").WasmerBackend,
        .zware => @import("backends/zware.zig").ZwareBackend,
    };

    const wasm_bytes = @embedFile("test_example_wasm");
    var wasm_backend = try BackendImpl.init(testing.allocator);
    defer wasm_backend.deinit();

    var b = wasm_backend.asBackend();
    var policy = try Policy.load(testing.allocator, &b, wasm_bytes);
    defer policy.deinit();

    var instance = try Inst.create(testing.allocator, &policy);
    defer instance.deinit();

    var ctx = try EvaluationContext.init(testing.allocator, &instance);
    defer ctx.deinit();

    try testing.expect(ctx.ctx_addr != 0);
    try testing.expect(ctx.saved_heap_ptr != 0);
}
