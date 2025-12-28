//! OPA UUID generation builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;
const zul = @import("zul");

pub fn rfc4122(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const variant = try args.getString(0);
    const uuid = if (std.mem.eql(u8, variant, "v4"))
        zul.UUID.v4()
    else if (std.mem.eql(u8, variant, "v7"))
        zul.UUID.v7()
    else
        return error.InvalidArguments;
    const hex = uuid.toHex(.lower);
    return .{ .string = allocator.dupe(u8, &hex) catch return error.AllocationFailed };
}

pub fn parse(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const uuid_str = try args.getString(0);

    const uuid = zul.UUID.parse(uuid_str) catch return error.InvalidArguments;

    var result = std.json.ObjectMap.init(allocator);
    errdefer result.deinit();

    const version = (uuid.bin[6] >> 4) & 0x0F;
    const variant_byte = uuid.bin[8];
    const variant: []const u8 = if ((variant_byte & 0x80) == 0)
        "Reserved, NCS backward compatibility"
    else if ((variant_byte & 0xC0) == 0x80)
        "RFC4122"
    else if ((variant_byte & 0xE0) == 0xC0)
        "Reserved, Microsoft Corporation backward compatibility"
    else
        "Reserved for future definition";

    result.put("version", .{ .integer = @intCast(version) }) catch return error.AllocationFailed;
    result.put("variant", .{ .string = variant }) catch return error.AllocationFailed;

    return .{ .object = result };
}

test "uuid.rfc4122 v4" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try rfc4122(arena.allocator(), Args.init(&.{.{ .string = "v4" }}));
    try std.testing.expectEqual(@as(usize, 36), result.string.len);
    try std.testing.expectEqual(@as(u8, '-'), result.string[8]);
    try std.testing.expectEqual(@as(u8, '-'), result.string[13]);
    try std.testing.expectEqual(@as(u8, '4'), result.string[14]);
}

test "uuid.parse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), Args.init(&.{.{ .string = "550e8400-e29b-41d4-a716-446655440000" }}));
    try std.testing.expectEqual(@as(i64, 4), result.object.get("version").?.integer);
    try std.testing.expectEqualStrings("RFC4122", result.object.get("variant").?.string);
}
