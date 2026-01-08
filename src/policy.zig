//! OPA Policy Loader and Manager.

const std = @import("std");
const backend = @import("backends/backend.zig");

pub const Policy = @This();
const Self = Policy;

/// OPA ABI version from WASM globals.
pub const AbiVersion = struct {
    major: u32,
    minor: u32,

    pub fn isCompatible(self: AbiVersion) bool {
        return self.major == 1 and self.minor <= 3;
    }

    pub fn format(
        self: AbiVersion,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{d}.{d}", .{ self.major, self.minor });
    }
};

pub const LoadError = error{
    InvalidModule,
    UnsupportedAbiVersion,
    MissingExport,
    BackendError,
} || std.mem.Allocator.Error;

allocator: std.mem.Allocator,
module: backend.Module,
abi_version: AbiVersion,
entrypoints: std.StringHashMapUnmanaged(u32),
required_builtins: std.StringHashMapUnmanaged(u32),

/// Load a policy from WASM bytes.
pub fn load(
    allocator: std.mem.Allocator,
    wasm_backend: *backend.Backend,
    wasm_bytes: []const u8,
) LoadError!Self {
    const module = wasm_backend.loadModule(wasm_bytes) catch return error.InvalidModule;
    errdefer module.deinit();

    return Self{
        .allocator = allocator,
        .module = module,
        .abi_version = .{ .major = 1, .minor = 0 },
        .entrypoints = .{},
        .required_builtins = .{},
    };
}

/// Check if an entrypoint exists.
pub fn hasEntrypoint(self: *const Self, name: []const u8) bool {
    return self.entrypoints.contains(name);
}

/// Get entrypoint ID by name.
pub fn getEntrypointId(self: *const Self, name: []const u8) ?u32 {
    return self.entrypoints.get(name);
}

/// Get all entrypoint names.
pub fn getEntrypoints(self: *const Self, allocator: std.mem.Allocator) ![]const []const u8 {
    var names = std.ArrayList([]const u8).init(allocator);
    var iter = self.entrypoints.keyIterator();
    while (iter.next()) |key| {
        try names.append(key.*);
    }
    return names.toOwnedSlice();
}

/// Validation result for policy requirements.
pub const ValidationResult = struct {
    valid: bool,
    missing_builtins: []const []const u8,
    unsupported_builtins: []const []const u8,

    pub fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void {
        allocator.free(self.missing_builtins);
        allocator.free(self.unsupported_builtins);
    }
};

/// Validate that all required builtins are implemented.
pub fn validate(self: *const Self, allocator: std.mem.Allocator) !ValidationResult {
    const builtins = @import("builtins/builtins.zig");

    var missing = std.ArrayList([]const u8).init(allocator);
    var unsupported = std.ArrayList([]const u8).init(allocator);

    var iter = self.required_builtins.keyIterator();
    while (iter.next()) |key| {
        const name = key.*;
        if (!builtins.isImplemented(name)) {
            try unsupported.append(name);
        }
    }

    return .{
        .valid = unsupported.items.len == 0 and missing.items.len == 0,
        .missing_builtins = try missing.toOwnedSlice(),
        .unsupported_builtins = try unsupported.toOwnedSlice(),
    };
}

pub fn deinit(self: *Self) void {
    freeStringMap(self.allocator, &self.entrypoints);
    freeStringMap(self.allocator, &self.required_builtins);
    self.module.deinit();
}

fn freeStringMap(allocator: std.mem.Allocator, map: *std.StringHashMapUnmanaged(u32)) void {
    var iter = map.keyIterator();
    while (iter.next()) |key| {
        allocator.free(key.*);
    }
    map.deinit(allocator);
}

test "policy load minimal wasm" {
    const testing = std.testing;
    const options = @import("options");
    const BackendImpl = switch (options.backend) {
        .wasmer => @import("backends/wasmer.zig").WasmerBackend,
        .zware => @import("backends/zware.zig").ZwareBackend,
    };

    const test_wasm = @embedFile("test_add_wasm");

    var wasm_backend = BackendImpl.init(testing.allocator) catch |err| {
        std.debug.print("Backend init failed: {}\n", .{err});
        return err;
    };
    defer wasm_backend.deinit();

    var b = wasm_backend.asBackend();
    var p = try Self.load(testing.allocator, &b, test_wasm);
    defer p.deinit();

    try testing.expect(p.abi_version.major == 1);
}
