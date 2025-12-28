//! Common types and helpers for OPA builtin implementations.
const std = @import("std");

/// Errors that can occur during builtin execution.
pub const BuiltinError = error{
    InvalidArguments,
    TypeMismatch,
    AllocationFailed,
    UnknownBuiltin,
    SerializationFailed,
};

/// Wrapper for accessing builtin arguments with type checking.
pub const Args = struct {
    values: []const std.json.Value,

    pub fn init(values: []const std.json.Value) Args {
        return .{ .values = values };
    }

    pub fn get(self: Args, idx: usize) BuiltinError!std.json.Value {
        if (idx >= self.values.len) return error.InvalidArguments;
        return self.values[idx];
    }

    pub fn getString(self: Args, idx: usize) BuiltinError![]const u8 {
        const v = try self.get(idx);
        if (v != .string) return error.TypeMismatch;
        return v.string;
    }

    pub fn getInt(self: Args, idx: usize) BuiltinError!i64 {
        const v = try self.get(idx);
        return switch (v) {
            .integer => |n| n,
            .float => |f| @intFromFloat(f),
            else => error.TypeMismatch,
        };
    }

    pub fn getNumber(self: Args, idx: usize) BuiltinError!f64 {
        const v = try self.get(idx);
        return switch (v) {
            .integer => |n| @floatFromInt(n),
            .float => |f| f,
            else => error.TypeMismatch,
        };
    }

    pub fn getArray(self: Args, idx: usize) BuiltinError![]const std.json.Value {
        const v = try self.get(idx);
        if (v != .array) return error.TypeMismatch;
        return v.array.items;
    }

    pub fn getObject(self: Args, idx: usize) BuiltinError!std.json.ObjectMap {
        const v = try self.get(idx);
        if (v != .object) return error.TypeMismatch;
        return v.object;
    }
};

pub fn makeBool(b: bool) std.json.Value {
    return .{ .bool = b };
}

pub fn makeString(s: []const u8) std.json.Value {
    return .{ .string = s };
}

pub fn makeNumber(n: f64) std.json.Value {
    const min_i64: f64 = @floatFromInt(std.math.minInt(i64));
    const max_i64: f64 = 9223372036854775000.0;
    if (@floor(n) == n and n >= min_i64 and n <= max_i64) {
        return .{ .integer = @intFromFloat(n) };
    }
    return .{ .float = n };
}

pub fn makeNull() std.json.Value {
    return .null;
}

/// Serializes a JSON value to a string.
pub fn jsonStringify(allocator: std.mem.Allocator, value: std.json.Value) BuiltinError![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{}) catch return error.SerializationFailed;
}

/// Deep equality comparison for JSON values.
pub fn jsonEqual(a: std.json.Value, b: std.json.Value) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;
    return switch (a) {
        .null => true,
        .bool => |av| av == b.bool,
        .integer => |av| av == b.integer,
        .float => |av| av == b.float,
        .string => |av| std.mem.eql(u8, av, b.string),
        .array => |av| {
            if (av.items.len != b.array.items.len) return false;
            for (av.items, b.array.items) |ai, bi| {
                if (!jsonEqual(ai, bi)) return false;
            }
            return true;
        },
        .object => false,
        .number_string => |av| std.mem.eql(u8, av, b.number_string),
    };
}
