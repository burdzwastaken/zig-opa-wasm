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
pub const bits = @import("bits.zig");
pub const graph = @import("graph.zig");

pub const BuiltinError = common.BuiltinError;
pub const Args = common.Args;

pub const BuiltinFn = *const fn (std.mem.Allocator, Args) BuiltinError!std.json.Value;

const builtin_map = std.StaticStringMap(BuiltinFn).initComptime(.{
    .{ "abs", numbers.abs },
    .{ "array.concat", arrays.concat },
    .{ "array.reverse", arrays.reverse },
    .{ "array.slice", arrays.slice },
    .{ "base64.decode", encoding.base64Decode },
    .{ "base64.encode", encoding.base64Encode },
    .{ "base64.is_valid", encoding.base64IsValid },
    .{ "base64url.decode", encoding.base64UrlDecode },
    .{ "base64url.encode", encoding.base64UrlEncode },
    .{ "base64url.encode_no_pad", encoding.base64UrlEncodeNoPad },
    .{ "bits.and", bits.bitwiseAnd },
    .{ "bits.lsh", bits.bitwiseLsh },
    .{ "bits.negate", bits.bitwiseNegate },
    .{ "bits.or", bits.bitwiseOr },
    .{ "bits.rsh", bits.bitwiseRsh },
    .{ "bits.xor", bits.bitwiseXor },
    .{ "ceil", numbers.ceil },
    .{ "concat", strings.concat },
    .{ "contains", strings.contains },
    .{ "count", arrays.count },
    .{ "crypto.md5", crypto.md5 },
    .{ "crypto.sha1", crypto.sha1 },
    .{ "crypto.sha256", crypto.sha256 },
    .{ "endswith", strings.endswith },
    .{ "floor", numbers.floor },
    .{ "format_int", numbers.formatInt },
    .{ "glob.match", glob.match },
    .{ "glob.quote_meta", glob.quoteMeta },
    .{ "graph.reachable", graph.reachable },
    .{ "graph.reachable_paths", graph.reachablePaths },
    .{ "hex.decode", encoding.hexDecode },
    .{ "hex.encode", encoding.hexEncode },
    .{ "indexof", strings.indexof },
    .{ "indexof_n", strings.indexof_n },
    .{ "intersection", arrays.intersection },
    .{ "is_array", types.isArray },
    .{ "is_boolean", types.isBoolean },
    .{ "is_null", types.isNull },
    .{ "is_number", types.isNumber },
    .{ "is_object", types.isObject },
    .{ "is_set", types.isSet },
    .{ "is_string", types.isString },
    .{ "json.filter", json_builtins.jsonFilter },
    .{ "json.is_valid", json_builtins.jsonIsValid },
    .{ "json.marshal", json_builtins.jsonMarshal },
    .{ "json.marshal_with_options", json_builtins.jsonMarshalWithOptions },
    .{ "json.patch", json_builtins.jsonPatch },
    .{ "json.remove", json_builtins.jsonRemove },
    .{ "json.unmarshal", json_builtins.jsonUnmarshal },
    .{ "lower", strings.lower },
    .{ "max", numbers.max },
    .{ "min", numbers.min },
    .{ "net.cidr_contains", net.cidrContains },
    .{ "net.cidr_contains_matches", net.cidrContainsMatches },
    .{ "net.cidr_expand", net.cidrExpand },
    .{ "net.cidr_intersects", net.cidrIntersects },
    .{ "net.cidr_is_valid", net.cidrIsValid },
    .{ "net.cidr_merge", net.cidrMerge },
    .{ "numbers.range", numbers.numbersRange },
    .{ "numbers.range_step", numbers.numbersRangeStep },
    .{ "object.filter", objects.filter },
    .{ "object.get", objects.get },
    .{ "object.keys", objects.keys },
    .{ "object.remove", objects.remove },
    .{ "object.subset", objects.subset },
    .{ "object.union_n", objects.unionN },
    .{ "opa.runtime", opa.runtime },
    .{ "print", opa.print },
    .{ "product", numbers.product },
    .{ "rand.intn", opa.randIntn },
    .{ "regex.find_all_string_submatch_n", regex.findAllStringSubmatchN },
    .{ "regex.find_n", regex.findN },
    .{ "regex.globs_match", regex.globsMatch },
    .{ "regex.is_valid", regex.isValid },
    .{ "regex.match", regex.match },
    .{ "regex.replace", regex.replace },
    .{ "regex.split", regex.split },
    .{ "regex.template_match", regex.templateMatch },
    .{ "replace", strings.replace },
    .{ "round", numbers.round },
    .{ "semver.compare", semver.compare },
    .{ "semver.is_valid", semver.isValid },
    .{ "sort", arrays.sort },
    .{ "split", strings.split },
    .{ "sprintf", strings.sprintf },
    .{ "startswith", strings.startswith },
    .{ "strings.any_prefix_match", strings.any_prefix_match },
    .{ "strings.any_suffix_match", strings.any_suffix_match },
    .{ "strings.count", strings.count },
    .{ "strings.render_template", strings.render_template },
    .{ "strings.replace_n", strings.replace_n },
    .{ "strings.reverse", strings.reverse },
    .{ "substring", strings.substring },
    .{ "sum", numbers.sum },
    .{ "time.add_date", time.addDate },
    .{ "time.clock", time.clock },
    .{ "time.date", time.date },
    .{ "time.diff", time.diff },
    .{ "time.format", time.format },
    .{ "time.now_ns", time.nowNs },
    .{ "time.parse_duration_ns", time.parseDurationNs },
    .{ "time.parse_ns", time.parseNs },
    .{ "time.parse_rfc3339_ns", time.parseRfc3339Ns },
    .{ "time.weekday", time.weekday },
    .{ "to_number", types.toNumber },
    .{ "trace", opa.trace },
    .{ "trim", strings.trim },
    .{ "trim_left", strings.trim_left },
    .{ "trim_prefix", strings.trim_prefix },
    .{ "trim_right", strings.trim_right },
    .{ "trim_space", strings.trim_space },
    .{ "trim_suffix", strings.trim_suffix },
    .{ "type_name", types.typeName },
    .{ "union", arrays.setUnion },
    .{ "units.parse", units.parse },
    .{ "units.parse_bytes", units.parseBytes },
    .{ "upper", strings.upper },
    .{ "urlquery.decode", encoding.urlQueryDecode },
    .{ "urlquery.decode_object", encoding.urlQueryDecodeObject },
    .{ "urlquery.encode", encoding.urlQueryEncode },
    .{ "urlquery.encode_object", encoding.urlQueryEncodeObject },
    .{ "uuid.parse", uuid.parse },
    .{ "uuid.rfc4122", uuid.rfc4122 },
    .{ "walk", arrays.walk },
    .{ "yaml.is_valid", yaml.isValid },
    .{ "yaml.marshal", yaml.marshal },
    .{ "yaml.unmarshal", yaml.unmarshal },
    // test builtins for OPA compliance suite
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
