//! Zig library for evaluating OPA policies compiled to WebAssembly.
//! Provides native Zig interface for OPA WASM ABI 1.x.

const std = @import("std");
const options = @import("options");

pub const backends = struct {
    pub const backend = @import("backends/backend.zig");
    pub const wasmer = if (options.backend == .wasmer) @import("backends/wasmer.zig") else struct {};
    pub const zware = if (options.backend == .zware) @import("backends/zware.zig") else struct {};

    pub const Backend = backend.Backend;
    pub const WasmerBackend = if (options.backend == .wasmer) wasmer.WasmerBackend else void;
    pub const ZwareBackend = if (options.backend == .zware) zware.ZwareBackend else void;
};

pub const memory = struct {
    pub const manager = @import("memory/manager.zig");
    pub const MemoryManager = manager.MemoryManager;
};

pub const builtins = @import("builtins/builtins.zig");

pub const policy = @import("policy.zig");
pub const Policy = policy.Policy;

pub const instance = @import("instance.zig");
pub const Instance = instance.Instance;
pub const InstancePool = instance.InstancePool;

pub const evaluation = @import("evaluation.zig");
pub const EvaluationContext = evaluation.EvaluationContext;

pub const bundle = @import("bundle.zig");
pub const Bundle = bundle.Bundle;

pub const Backend = switch (options.backend) {
    .wasmer => backends.WasmerBackend,
    .zware => backends.ZwareBackend,
};
pub const BackendInterface = backends.Backend;
pub const WasmerBackend = backends.WasmerBackend;
pub const ZwareBackend = backends.ZwareBackend;
pub const MemoryManager = memory.MemoryManager;

test {
    std.testing.refAllDecls(@This());
}
