//! OPA string manipulation builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn concat(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const delimiter = try a.getString(0);
    const arr = try a.getArray(1);

    var total_len: usize = 0;
    for (arr, 0..) |item, i| {
        if (item != .string) return error.TypeMismatch;
        total_len += item.string.len;
        if (i > 0) total_len += delimiter.len;
    }

    const result = allocator.alloc(u8, total_len) catch return error.AllocationFailed;
    var pos: usize = 0;
    for (arr, 0..) |item, i| {
        if (i > 0) {
            @memcpy(result[pos .. pos + delimiter.len], delimiter);
            pos += delimiter.len;
        }
        @memcpy(result[pos .. pos + item.string.len], item.string);
        pos += item.string.len;
    }
    return .{ .string = result };
}

pub fn contains(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const haystack = try a.getString(0);
    const needle = try a.getString(1);
    return common.makeBool(std.mem.indexOf(u8, haystack, needle) != null);
}

pub fn startswith(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const prefix = try a.getString(1);
    return common.makeBool(std.mem.startsWith(u8, s, prefix));
}

pub fn endswith(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const suffix = try a.getString(1);
    return common.makeBool(std.mem.endsWith(u8, s, suffix));
}

pub fn lower(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    return .{ .string = std.ascii.allocLowerString(allocator, s) catch return error.AllocationFailed };
}

pub fn upper(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    return .{ .string = std.ascii.allocUpperString(allocator, s) catch return error.AllocationFailed };
}

pub fn trim(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const cutset = try a.getString(1);
    const result = std.mem.trim(u8, s, cutset);
    const dup = allocator.dupe(u8, result) catch return error.AllocationFailed;
    return .{ .string = dup };
}

pub fn trim_left(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const cutset = try a.getString(1);
    const result = std.mem.trimLeft(u8, s, cutset);
    const dup = allocator.dupe(u8, result) catch return error.AllocationFailed;
    return .{ .string = dup };
}

pub fn trim_right(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const cutset = try a.getString(1);
    const result = std.mem.trimRight(u8, s, cutset);
    const dup = allocator.dupe(u8, result) catch return error.AllocationFailed;
    return .{ .string = dup };
}

pub fn trim_prefix(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const prefix = try a.getString(1);
    const result = if (std.mem.startsWith(u8, s, prefix)) s[prefix.len..] else s;
    const dup = allocator.dupe(u8, result) catch return error.AllocationFailed;
    return .{ .string = dup };
}

pub fn trim_suffix(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const suffix = try a.getString(1);
    const result = if (std.mem.endsWith(u8, s, suffix)) s[0 .. s.len - suffix.len] else s;
    const dup = allocator.dupe(u8, result) catch return error.AllocationFailed;
    return .{ .string = dup };
}

pub fn trim_space(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const result = std.mem.trim(u8, s, " \t\n\r");
    const dup = allocator.dupe(u8, result) catch return error.AllocationFailed;
    return .{ .string = dup };
}

pub fn split(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const delimiter = try a.getString(1);

    var arr = std.json.Array.init(allocator);
    var iter = std.mem.splitSequence(u8, s, delimiter);
    while (iter.next()) |part| {
        const dup = allocator.dupe(u8, part) catch return error.AllocationFailed;
        arr.append(.{ .string = dup }) catch return error.AllocationFailed;
    }
    return .{ .array = arr };
}

pub fn replace(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const old = try a.getString(1);
    const new = try a.getString(2);

    if (old.len == 0) {
        const dup = allocator.dupe(u8, s) catch return error.AllocationFailed;
        return .{ .string = dup };
    }

    const occurrences = std.mem.count(u8, s, old);
    const new_len = s.len + occurrences * (new.len -| old.len);
    const result = allocator.alloc(u8, new_len) catch return error.AllocationFailed;

    _ = std.mem.replace(u8, s, old, new, result);
    return .{ .string = result };
}

pub fn indexof(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const haystack = try a.getString(0);
    const needle = try a.getString(1);
    const idx = std.mem.indexOf(u8, haystack, needle);
    return common.makeNumber(if (idx) |i| @as(f64, @floatFromInt(i)) else -1);
}

pub fn indexof_n(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const haystack = try a.getString(0);
    const needle = try a.getString(1);

    var arr = std.json.Array.init(allocator);
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, pos, needle)) |idx| {
        arr.append(.{ .integer = @intCast(idx) }) catch return error.AllocationFailed;
        pos = idx + 1;
    }
    return .{ .array = arr };
}

pub fn substring(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const s = try a.getString(0);
    const offset = try a.getInt(1);
    const length = try a.getInt(2);

    const start: usize = if (offset < 0) 0 else @min(@as(usize, @intCast(offset)), s.len);
    const len: usize = if (length < 0) s.len - start else @min(@as(usize, @intCast(length)), s.len - start);

    const result = allocator.dupe(u8, s[start .. start + len]) catch return error.AllocationFailed;
    return .{ .string = result };
}

pub fn reverse(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    const reversed = allocator.alloc(u8, input.len) catch return error.AllocationFailed;
    for (input, 0..) |c, i| {
        reversed[input.len - 1 - i] = c;
    }
    return .{ .string = reversed };
}

pub fn sprintf(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const format = try a.getString(0);
    const args_array = try a.getArray(1);

    var result = std.ArrayListUnmanaged(u8){};
    var arg_idx: usize = 0;
    var i: usize = 0;

    while (i < format.len) {
        if (format[i] == '%' and i + 1 < format.len) {
            const spec = format[i + 1];
            switch (spec) {
                '%' => {
                    result.append(allocator, '%') catch return error.AllocationFailed;
                    i += 2;
                },
                's' => {
                    if (arg_idx >= args_array.len) return error.InvalidArguments;
                    const arg = args_array[arg_idx];
                    if (arg == .string) {
                        result.appendSlice(allocator, arg.string) catch return error.AllocationFailed;
                    }
                    arg_idx += 1;
                    i += 2;
                },
                'd' => {
                    if (arg_idx >= args_array.len) return error.InvalidArguments;
                    const arg = args_array[arg_idx];
                    var buf: [32]u8 = undefined;
                    const num_str = switch (arg) {
                        .integer => |n| std.fmt.bufPrint(&buf, "{d}", .{n}) catch return error.AllocationFailed,
                        .float => |f| std.fmt.bufPrint(&buf, "{d:.0}", .{f}) catch return error.AllocationFailed,
                        else => return error.TypeMismatch,
                    };
                    result.appendSlice(allocator, num_str) catch return error.AllocationFailed;
                    arg_idx += 1;
                    i += 2;
                },
                'f' => {
                    if (arg_idx >= args_array.len) return error.InvalidArguments;
                    const arg = args_array[arg_idx];
                    var buf: [64]u8 = undefined;
                    const num_str = switch (arg) {
                        .integer => |n| std.fmt.bufPrint(&buf, "{d}.000000", .{n}) catch return error.AllocationFailed,
                        .float => |f| std.fmt.bufPrint(&buf, "{d:.6}", .{f}) catch return error.AllocationFailed,
                        else => return error.TypeMismatch,
                    };
                    result.appendSlice(allocator, num_str) catch return error.AllocationFailed;
                    arg_idx += 1;
                    i += 2;
                },
                'x', 'X' => {
                    if (arg_idx >= args_array.len) return error.InvalidArguments;
                    const arg = args_array[arg_idx];
                    var buf: [32]u8 = undefined;
                    const num_str = switch (arg) {
                        .integer => |n| if (spec == 'X')
                            std.fmt.bufPrint(&buf, "{X}", .{@as(u64, @bitCast(n))}) catch return error.AllocationFailed
                        else
                            std.fmt.bufPrint(&buf, "{x}", .{@as(u64, @bitCast(n))}) catch return error.AllocationFailed,
                        .float => |f| if (spec == 'X')
                            std.fmt.bufPrint(&buf, "{X}", .{@as(u64, @bitCast(@as(i64, @intFromFloat(f))))}) catch return error.AllocationFailed
                        else
                            std.fmt.bufPrint(&buf, "{x}", .{@as(u64, @bitCast(@as(i64, @intFromFloat(f))))}) catch return error.AllocationFailed,
                        else => return error.TypeMismatch,
                    };
                    result.appendSlice(allocator, num_str) catch return error.AllocationFailed;
                    arg_idx += 1;
                    i += 2;
                },
                'o' => {
                    if (arg_idx >= args_array.len) return error.InvalidArguments;
                    const arg = args_array[arg_idx];
                    var buf: [32]u8 = undefined;
                    const num_str = switch (arg) {
                        .integer => |n| std.fmt.bufPrint(&buf, "{o}", .{@as(u64, @bitCast(n))}) catch return error.AllocationFailed,
                        .float => |f| std.fmt.bufPrint(&buf, "{o}", .{@as(u64, @bitCast(@as(i64, @intFromFloat(f))))}) catch return error.AllocationFailed,
                        else => return error.TypeMismatch,
                    };
                    result.appendSlice(allocator, num_str) catch return error.AllocationFailed;
                    arg_idx += 1;
                    i += 2;
                },
                'b' => {
                    if (arg_idx >= args_array.len) return error.InvalidArguments;
                    const arg = args_array[arg_idx];
                    var buf: [128]u8 = undefined;
                    const num_str = switch (arg) {
                        .integer => |n| std.fmt.bufPrint(&buf, "{b}", .{@as(u64, @bitCast(n))}) catch return error.AllocationFailed,
                        .float => |f| std.fmt.bufPrint(&buf, "{b}", .{@as(u64, @bitCast(@as(i64, @intFromFloat(f))))}) catch return error.AllocationFailed,
                        else => return error.TypeMismatch,
                    };
                    result.appendSlice(allocator, num_str) catch return error.AllocationFailed;
                    arg_idx += 1;
                    i += 2;
                },
                'e', 'E' => {
                    if (arg_idx >= args_array.len) return error.InvalidArguments;
                    const arg = args_array[arg_idx];
                    var buf: [64]u8 = undefined;
                    const num_str = switch (arg) {
                        .integer => |n| std.fmt.bufPrint(&buf, "{e}", .{@as(f64, @floatFromInt(n))}) catch return error.AllocationFailed,
                        .float => |f| std.fmt.bufPrint(&buf, "{e}", .{f}) catch return error.AllocationFailed,
                        else => return error.TypeMismatch,
                    };
                    result.appendSlice(allocator, num_str) catch return error.AllocationFailed;
                    arg_idx += 1;
                    i += 2;
                },
                'g', 'G' => {
                    if (arg_idx >= args_array.len) return error.InvalidArguments;
                    const arg = args_array[arg_idx];
                    var buf: [64]u8 = undefined;
                    const num_str = switch (arg) {
                        .integer => |n| std.fmt.bufPrint(&buf, "{d}", .{n}) catch return error.AllocationFailed,
                        .float => |f| std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.AllocationFailed,
                        else => return error.TypeMismatch,
                    };
                    result.appendSlice(allocator, num_str) catch return error.AllocationFailed;
                    arg_idx += 1;
                    i += 2;
                },
                'v', 't' => {
                    if (arg_idx >= args_array.len) return error.InvalidArguments;
                    const arg = args_array[arg_idx];
                    const json_str = std.json.Stringify.valueAlloc(allocator, arg, .{}) catch return error.AllocationFailed;
                    defer allocator.free(json_str);
                    result.appendSlice(allocator, json_str) catch return error.AllocationFailed;
                    arg_idx += 1;
                    i += 2;
                },
                else => {
                    result.append(allocator, format[i]) catch return error.AllocationFailed;
                    i += 1;
                },
            }
        } else {
            result.append(allocator, format[i]) catch return error.AllocationFailed;
            i += 1;
        }
    }

    return .{ .string = result.toOwnedSlice(allocator) catch return error.AllocationFailed };
}

pub fn replace_n(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const patterns = try a.getObject(0);
    const input = try a.getString(1);

    var result = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    outer: while (i < input.len) {
        var iter = patterns.iterator();
        while (iter.next()) |entry| {
            const pattern = entry.key_ptr.*;
            if (i + pattern.len <= input.len and std.mem.eql(u8, input[i .. i + pattern.len], pattern)) {
                if (entry.value_ptr.* == .string) {
                    result.appendSlice(allocator, entry.value_ptr.string) catch return error.AllocationFailed;
                }
                i += pattern.len;
                continue :outer;
            }
        }
        result.append(allocator, input[i]) catch return error.AllocationFailed;
        i += 1;
    }
    return .{ .string = result.toOwnedSlice(allocator) catch return error.AllocationFailed };
}

test "strings.concat" {
    const allocator = std.testing.allocator;
    var args = [_]std.json.Value{ .{ .string = ", " }, .{ .array = std.json.Array.init(allocator) } };
    defer args[1].array.deinit();
    try args[1].array.append(.{ .string = "a" });
    try args[1].array.append(.{ .string = "b" });
    try args[1].array.append(.{ .string = "c" });
    const result = try concat(allocator, Args.init(&args));
    defer allocator.free(result.string);
    try std.testing.expectEqualStrings("a, b, c", result.string);
}

test "strings.contains" {
    var args = [_]std.json.Value{ .{ .string = "hello world" }, .{ .string = "world" } };
    const result = try contains(std.testing.allocator, Args.init(&args));
    try std.testing.expect(result.bool == true);
}

test "strings.startswith" {
    var args = [_]std.json.Value{ .{ .string = "hello world" }, .{ .string = "hello" } };
    const result = try startswith(std.testing.allocator, Args.init(&args));
    try std.testing.expect(result.bool == true);
}

test "strings.endswith" {
    var args = [_]std.json.Value{ .{ .string = "hello world" }, .{ .string = "world" } };
    const result = try endswith(std.testing.allocator, Args.init(&args));
    try std.testing.expect(result.bool == true);
}

test "strings.lower" {
    const allocator = std.testing.allocator;
    var args = [_]std.json.Value{.{ .string = "HELLO" }};
    const result = try lower(allocator, Args.init(&args));
    defer allocator.free(result.string);
    try std.testing.expectEqualStrings("hello", result.string);
}

test "strings.upper" {
    const allocator = std.testing.allocator;
    var args = [_]std.json.Value{.{ .string = "hello" }};
    const result = try upper(allocator, Args.init(&args));
    defer allocator.free(result.string);
    try std.testing.expectEqualStrings("HELLO", result.string);
}

test "strings.split" {
    const allocator = std.testing.allocator;
    var args = [_]std.json.Value{ .{ .string = "a,b,c" }, .{ .string = "," } };
    const result = try split(allocator, Args.init(&args));
    defer {
        for (result.array.items) |item| allocator.free(item.string);
        result.array.deinit();
    }
    try std.testing.expectEqual(@as(usize, 3), result.array.items.len);
}

test "strings.indexof" {
    var args = [_]std.json.Value{ .{ .string = "hello" }, .{ .string = "l" } };
    const result = try indexof(std.testing.allocator, Args.init(&args));
    try std.testing.expectEqual(@as(i64, 2), result.integer);
}

test "strings.indexof not found" {
    var args = [_]std.json.Value{ .{ .string = "hello" }, .{ .string = "x" } };
    const result = try indexof(std.testing.allocator, Args.init(&args));
    try std.testing.expectEqual(@as(i64, -1), result.integer);
}

test "strings.substring" {
    const allocator = std.testing.allocator;
    var args = [_]std.json.Value{ .{ .string = "hello world" }, .{ .integer = 6 }, .{ .integer = 5 } };
    const result = try substring(allocator, Args.init(&args));
    defer allocator.free(result.string);
    try std.testing.expectEqualStrings("world", result.string);
}

test "strings.reverse" {
    const allocator = std.testing.allocator;
    var args = [_]std.json.Value{.{ .string = "hello" }};
    const result = try reverse(allocator, Args.init(&args));
    defer allocator.free(result.string);
    try std.testing.expectEqualStrings("olleh", result.string);
}

test "strings.sprintf with string" {
    const allocator = std.testing.allocator;
    var arr = std.json.Array.init(allocator);
    defer arr.deinit();
    try arr.append(.{ .string = "world" });
    var args = [_]std.json.Value{ .{ .string = "Hello, %s!" }, .{ .array = arr } };
    const result = try sprintf(allocator, Args.init(&args));
    defer allocator.free(result.string);
    try std.testing.expectEqualStrings("Hello, world!", result.string);
}

test "strings.sprintf with integer" {
    const allocator = std.testing.allocator;
    var arr = std.json.Array.init(allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 42 });
    var args = [_]std.json.Value{ .{ .string = "Value: %d" }, .{ .array = arr } };
    const result = try sprintf(allocator, Args.init(&args));
    defer allocator.free(result.string);
    try std.testing.expectEqualStrings("Value: 42", result.string);
}

fn anyMatch(s: []const u8, patterns: []const std.json.Value, comptime is_prefix: bool) BuiltinError!std.json.Value {
    for (patterns) |item| {
        if (item != .string) return error.TypeMismatch;
        const matches = if (is_prefix) std.mem.startsWith(u8, s, item.string) else std.mem.endsWith(u8, s, item.string);
        if (matches) return common.makeBool(true);
    }
    return common.makeBool(false);
}

pub fn any_prefix_match(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    return anyMatch(try a.getString(0), try a.getSetOrArray(1), true);
}

pub fn any_suffix_match(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    return anyMatch(try a.getString(0), try a.getSetOrArray(1), false);
}

test "strings.any_prefix_match - match found" {
    const allocator = std.testing.allocator;
    var prefixes = std.json.Array.init(allocator);
    defer prefixes.deinit();
    try prefixes.append(.{ .string = "foo" });
    try prefixes.append(.{ .string = "bar" });
    var args = [_]std.json.Value{ .{ .string = "foobar" }, .{ .array = prefixes } };
    const result = try any_prefix_match(allocator, Args.init(&args));
    try std.testing.expect(result.bool == true);
}

test "strings.any_prefix_match - no match" {
    const allocator = std.testing.allocator;
    var prefixes = std.json.Array.init(allocator);
    defer prefixes.deinit();
    try prefixes.append(.{ .string = "baz" });
    try prefixes.append(.{ .string = "qux" });
    var args = [_]std.json.Value{ .{ .string = "foobar" }, .{ .array = prefixes } };
    const result = try any_prefix_match(allocator, Args.init(&args));
    try std.testing.expect(result.bool == false);
}

test "strings.any_suffix_match - match found" {
    const allocator = std.testing.allocator;
    var suffixes = std.json.Array.init(allocator);
    defer suffixes.deinit();
    try suffixes.append(.{ .string = "foo" });
    try suffixes.append(.{ .string = "bar" });
    var args = [_]std.json.Value{ .{ .string = "foobar" }, .{ .array = suffixes } };
    const result = try any_suffix_match(allocator, Args.init(&args));
    try std.testing.expect(result.bool == true);
}

test "strings.any_suffix_match - no match" {
    const allocator = std.testing.allocator;
    var suffixes = std.json.Array.init(allocator);
    defer suffixes.deinit();
    try suffixes.append(.{ .string = "baz" });
    try suffixes.append(.{ .string = "qux" });
    var args = [_]std.json.Value{ .{ .string = "foobar" }, .{ .array = suffixes } };
    const result = try any_suffix_match(allocator, Args.init(&args));
    try std.testing.expect(result.bool == false);
}

pub fn count(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const haystack = try a.getString(0);
    const needle = try a.getString(1);
    if (needle.len == 0) return common.makeNumber(0);
    const n = std.mem.count(u8, haystack, needle);
    return common.makeNumber(@floatFromInt(n));
}

test "strings.count" {
    var args = [_]std.json.Value{ .{ .string = "abcabc" }, .{ .string = "abc" } };
    const result = try count(std.testing.allocator, Args.init(&args));
    try std.testing.expectEqual(@as(i64, 2), result.integer);
}

test "strings.count - no match" {
    var args = [_]std.json.Value{ .{ .string = "hello" }, .{ .string = "xyz" } };
    const result = try count(std.testing.allocator, Args.init(&args));
    try std.testing.expectEqual(@as(i64, 0), result.integer);
}

test "strings.count - empty needle" {
    var args = [_]std.json.Value{ .{ .string = "hello" }, .{ .string = "" } };
    const result = try count(std.testing.allocator, Args.init(&args));
    try std.testing.expectEqual(@as(i64, 0), result.integer);
}

pub fn render_template(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const template = try a.getString(0);
    const vars = try a.getObject(1);

    var result = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;

    while (i < template.len) {
        if (template[i] == '{' and i + 1 < template.len and template[i + 1] == '{') {
            if (std.mem.indexOfPos(u8, template, i + 2, "}}")) |end| {
                const key = template[i + 2 .. end];
                if (vars.get(key)) |val| {
                    if (val == .string) {
                        result.appendSlice(allocator, val.string) catch return error.AllocationFailed;
                    } else {
                        const json_str = std.json.Stringify.valueAlloc(allocator, val, .{}) catch return error.AllocationFailed;
                        result.appendSlice(allocator, json_str) catch return error.AllocationFailed;
                    }
                }
                i = end + 2;
                continue;
            }
        }
        result.append(allocator, template[i]) catch return error.AllocationFailed;
        i += 1;
    }

    return .{ .string = result.toOwnedSlice(allocator) catch return error.AllocationFailed };
}

test "strings.render_template" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var vars = std.json.ObjectMap.init(alloc);
    try vars.put("name", .{ .string = "world" });

    var args = [_]std.json.Value{ .{ .string = "Hello, {{name}}!" }, .{ .object = vars } };
    const result = try render_template(alloc, Args.init(&args));
    try std.testing.expectEqualStrings("Hello, world!", result.string);
}
