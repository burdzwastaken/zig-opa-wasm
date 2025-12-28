//! OPA UUID generation builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;
const zul = @import("zul");

pub fn rfc4122(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const variant = try args.getString(0);

    if (std.mem.eql(u8, variant, "v4")) {
        const uuid = zul.UUID.v4();
        const hex = uuid.toHex(.lower);
        const str = allocator.dupe(u8, &hex) catch return error.AllocationFailed;
        return .{ .string = str };
    }

    if (std.mem.eql(u8, variant, "v7")) {
        const uuid = zul.UUID.v7();
        const hex = uuid.toHex(.lower);
        const str = allocator.dupe(u8, &hex) catch return error.AllocationFailed;
        return .{ .string = str };
    }

    return error.InvalidArguments;
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
