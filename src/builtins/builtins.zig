//! OPA builtin function registry and dispatch.
const std = @import("std");
const json = std.json;

/// Check if a builtin is implemented.
pub fn isImplemented(name: []const u8) bool {
    return builtin_map.has(name);
}

pub const common = @import("common.zig");
pub const strings = @import("strings.zig");
pub const numbers = @import("numbers.zig");
pub const arrays = @import("arrays.zig");
pub const objects = @import("objects.zig");
pub const types = @import("types.zig");
pub const encoding = @import("encoding.zig");
pub const crypto = @import("crypto.zig");
pub const json_builtins = @import("json_builtins.zig");
pub const time = @import("time.zig");
pub const opa = @import("opa.zig");
pub const regex = @import("regex.zig");
pub const net = @import("net.zig");
pub const semver = @import("semver.zig");
pub const glob = @import("glob.zig");
pub const yaml = @import("yaml.zig");
pub const uuid = @import("uuid.zig");
pub const units = @import("units.zig");

pub const BuiltinError = common.BuiltinError;
pub const Args = common.Args;

pub const BuiltinFn = *const fn (std.mem.Allocator, Args) BuiltinError!std.json.Value;

const builtin_map = std.StaticStringMap(BuiltinFn).initComptime(.{
    .{ "sprintf", strings.sprintf },
    .{ "concat", strings.concat },
    .{ "indexof", strings.indexof },
    .{ "indexof_n", strings.indexof_n },
    .{ "contains", strings.contains },
    .{ "startswith", strings.startswith },
    .{ "endswith", strings.endswith },
    .{ "lower", strings.lower },
    .{ "upper", strings.upper },
    .{ "trim", strings.trim },
    .{ "trim_left", strings.trim_left },
    .{ "trim_right", strings.trim_right },
    .{ "trim_prefix", strings.trim_prefix },
    .{ "trim_suffix", strings.trim_suffix },
    .{ "trim_space", strings.trim_space },
    .{ "replace", strings.replace },
    .{ "split", strings.split },
    .{ "substring", strings.substring },
    .{ "strings.reverse", strings.reverse },
    .{ "strings.replace_n", strings.replace_n },
    .{ "abs", numbers.abs },
    .{ "round", numbers.round },
    .{ "ceil", numbers.ceil },
    .{ "floor", numbers.floor },
    .{ "numbers.range", numbers.numbersRange },
    .{ "sum", numbers.sum },
    .{ "product", numbers.product },
    .{ "max", numbers.max },
    .{ "min", numbers.min },
    .{ "format_int", numbers.formatInt },
    .{ "array.concat", arrays.concat },
    .{ "array.slice", arrays.slice },
    .{ "array.reverse", arrays.reverse },
    .{ "sort", arrays.sort },
    .{ "count", arrays.count },
    .{ "intersection", arrays.intersection },
    .{ "union", arrays.setUnion },
    .{ "object.get", objects.get },
    .{ "object.keys", objects.keys },
    .{ "object.remove", objects.remove },
    .{ "object.union_n", objects.unionN },
    .{ "type_name", types.typeName },
    .{ "is_string", types.isString },
    .{ "is_number", types.isNumber },
    .{ "is_boolean", types.isBoolean },
    .{ "is_array", types.isArray },
    .{ "is_object", types.isObject },
    .{ "is_null", types.isNull },
    .{ "is_set", types.isSet },
    .{ "base64.encode", encoding.base64Encode },
    .{ "base64.decode", encoding.base64Decode },
    .{ "base64url.encode", encoding.base64UrlEncode },
    .{ "base64url.encode_no_pad", encoding.base64UrlEncodeNoPad },
    .{ "base64url.decode", encoding.base64UrlDecode },
    .{ "hex.encode", encoding.hexEncode },
    .{ "hex.decode", encoding.hexDecode },
    .{ "urlquery.encode", encoding.urlQueryEncode },
    .{ "urlquery.decode", encoding.urlQueryDecode },
    .{ "crypto.md5", crypto.md5 },
    .{ "crypto.sha1", crypto.sha1 },
    .{ "crypto.sha256", crypto.sha256 },
    .{ "json.is_valid", json_builtins.jsonIsValid },
    .{ "json.marshal", json_builtins.jsonMarshal },
    .{ "json.unmarshal", json_builtins.jsonUnmarshal },
    .{ "time.now_ns", time.nowNs },
    .{ "trace", opa.trace },
    .{ "opa.runtime", opa.runtime },
    .{ "rand.intn", opa.randIntn },
    .{ "regex.match", regex.match },
    .{ "regex.find_n", regex.findN },
    .{ "regex.split", regex.split },
    .{ "regex.replace", regex.replace },
    .{ "regex.find_all_string_submatch_n", regex.findAllStringSubmatchN },
    .{ "net.cidr_contains", net.cidrContains },
    .{ "net.cidr_contains_matches", net.cidrContainsMatches },
    .{ "net.cidr_expand", net.cidrExpand },
    .{ "net.cidr_merge", net.cidrMerge },
    .{ "semver.compare", semver.compare },
    .{ "semver.is_valid", semver.isValid },
    .{ "glob.quote_meta", glob.quoteMeta },
    .{ "time.parse_ns", time.parseNs },
    .{ "time.parse_rfc3339_ns", time.parseRfc3339Ns },
    .{ "time.parse_duration_ns", time.parseDurationNs },
    .{ "time.date", time.date },
    .{ "time.clock", time.clock },
    .{ "time.weekday", time.weekday },
    .{ "time.add_date", time.addDate },
    .{ "time.diff", time.diff },
    .{ "yaml.is_valid", yaml.isValid },
    .{ "yaml.marshal", yaml.marshal },
    .{ "yaml.unmarshal", yaml.unmarshal },
    .{ "uuid.rfc4122", uuid.rfc4122 },
    .{ "units.parse", units.parse },
    .{ "units.parse_bytes", units.parseBytes },
    // builtins for OPA compliance suite
    .{ "custom_builtin_test", testBuiltinCustom },
    .{ "custom_builtin_test_impure", testBuiltinImpure },
    .{ "custom_builtin_test_memoization", testBuiltinMemoization },
});

fn testBuiltinCustom(_: std.mem.Allocator, args: Args) BuiltinError!json.Value {
    const a = try args.get(0);
    if (a != .integer) return BuiltinError.TypeMismatch;
    return .{ .integer = a.integer + 1 };
}

fn testBuiltinImpure(_: std.mem.Allocator, _: Args) BuiltinError!json.Value {
    return .{ .string = "foo" };
}

var memoization_called: bool = false;

fn testBuiltinMemoization(_: std.mem.Allocator, _: Args) BuiltinError!json.Value {
    if (memoization_called) return BuiltinError.InvalidArguments;
    memoization_called = true;
    return .{ .integer = 100 };
}

/// Dispatches a builtin call by name returning the JSON-serialized result.
pub fn dispatch(allocator: std.mem.Allocator, name: []const u8, args: []const json.Value) BuiltinError![]const u8 {
    const builtin_fn = builtin_map.get(name) orelse return BuiltinError.UnknownBuiltin;
    const result = try builtin_fn(allocator, Args.init(args));
    return common.jsonStringify(allocator, result);
}

test "unknown builtin returns error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = dispatch(arena.allocator(), "nonexistent.builtin", &[_]json.Value{});
    try std.testing.expectError(BuiltinError.UnknownBuiltin, result);
}

test {
    std.testing.refAllDecls(@This());
}
