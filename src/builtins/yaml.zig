//! OPA YAML parsing and serialization builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;
const yaml = @import("yaml");

pub fn isValid(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const str = try args.getString(0);
    var doc = yaml.Yaml{ .source = str };
    defer doc.deinit(allocator);
    doc.load(allocator) catch return .{ .bool = false };
    return .{ .bool = true };
}

pub fn unmarshal(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const str = try args.getString(0);
    var doc = yaml.Yaml{ .source = str };
    defer doc.deinit(allocator);
    doc.load(allocator) catch return error.InvalidArguments;
    if (doc.docs.items.len == 0) return error.InvalidArguments;
    return yamlToJson(allocator, doc.docs.items[0]) catch return error.InvalidArguments;
}

pub fn marshal(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const val = try args.get(0);
    const yaml_str = jsonToYaml(allocator, val, 0) catch return error.AllocationFailed;
    return .{ .string = yaml_str };
}

fn yamlToJson(allocator: std.mem.Allocator, value: yaml.Yaml.Value) !std.json.Value {
    return switch (value) {
        .boolean => |b| .{ .bool = b },
        .scalar => |s| blk: {
            if (std.mem.eql(u8, s, "true")) break :blk .{ .bool = true };
            if (std.mem.eql(u8, s, "false")) break :blk .{ .bool = false };
            if (std.mem.eql(u8, s, "null") or std.mem.eql(u8, s, "~")) break :blk .null;
            if (std.fmt.parseInt(i64, s, 10)) |i| break :blk .{ .integer = i } else |_| {}
            if (std.fmt.parseFloat(f64, s)) |f| break :blk .{ .float = f } else |_| {}
            break :blk .{ .string = s };
        },
        .list => |list| blk: {
            var arr = std.json.Array.init(allocator);
            for (list) |item| {
                try arr.append(try yamlToJson(allocator, item));
            }
            break :blk .{ .array = arr };
        },
        .map => |map| blk: {
            var obj = std.json.ObjectMap.init(allocator);
            const keys = map.keys();
            const values = map.values();
            for (keys, values) |key, val| {
                try obj.put(key, try yamlToJson(allocator, val));
            }
            break :blk .{ .object = obj };
        },
        .empty => .null,
    };
}

fn jsonToYaml(allocator: std.mem.Allocator, val: std.json.Value, indent: usize) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    try writeYamlValue(allocator, &buf, val, indent);
    return buf.toOwnedSlice(allocator);
}

fn writeYamlValue(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), val: std.json.Value, indent: usize) !void {
    switch (val) {
        .null => try buf.appendSlice(allocator, "null"),
        .bool => |b| try buf.appendSlice(allocator, if (b) "true" else "false"),
        .integer => |i| {
            var num_buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&num_buf, "{d}", .{i}) catch return;
            try buf.appendSlice(allocator, s);
        },
        .float => |f| {
            var num_buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&num_buf, "{d}", .{f}) catch return;
            try buf.appendSlice(allocator, s);
        },
        .string => |s| {
            if (needsQuoting(s)) {
                try buf.append(allocator, '"');
                try buf.appendSlice(allocator, s);
                try buf.append(allocator, '"');
            } else {
                try buf.appendSlice(allocator, s);
            }
        },
        .array => |arr| {
            if (arr.items.len == 0) {
                try buf.appendSlice(allocator, "[]");
            } else {
                for (arr.items, 0..) |item, i| {
                    if (i > 0) try buf.appendSlice(allocator, "\n");
                    try buf.appendNTimes(allocator, ' ', indent);
                    try buf.appendSlice(allocator, "- ");
                    try writeYamlValue(allocator, buf, item, indent + 2);
                }
            }
        },
        .object => |obj| {
            if (obj.count() == 0) {
                try buf.appendSlice(allocator, "{}");
            } else {
                var first = true;
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    if (!first) try buf.appendSlice(allocator, "\n");
                    first = false;
                    try buf.appendNTimes(allocator, ' ', indent);
                    try buf.appendSlice(allocator, entry.key_ptr.*);
                    try buf.appendSlice(allocator, ": ");
                    try writeYamlValue(allocator, buf, entry.value_ptr.*, indent + 2);
                }
            }
        },
        .number_string => |s| try buf.appendSlice(allocator, s),
    }
}

fn needsQuoting(s: []const u8) bool {
    if (s.len == 0) return true;
    if (std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "false") or
        std.mem.eql(u8, s, "null") or std.mem.eql(u8, s, "~")) return true;
    for (s) |c| {
        if (c == ':' or c == '#' or c == '\n' or c == '"' or c == '\'') return true;
    }
    return false;
}

test "yaml.is_valid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var result = try isValid(arena.allocator(), Args.init(&.{.{ .string = "key: value" }}));
    try std.testing.expect(result.bool);

    result = try isValid(arena.allocator(), Args.init(&.{.{ .string = "key: [1, 2, 3]" }}));
    try std.testing.expect(result.bool);
}
