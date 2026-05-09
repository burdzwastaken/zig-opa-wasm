//! OPA UUID generation builtins.
//! UUID implementation inlined from zul (https://github.com/karlseguin/zul)
//! to avoid external dependency.

const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

var clock_sequence: u16 = 0;
var last_timestamp: u64 = 0;

const UUID = struct {
    bin: [16]u8,

    fn fillRandom(buf: []u8) void {
        if (builtin.os.tag == .linux) {
            _ = std.os.linux.getrandom(buf.ptr, buf.len, 0);
        } else {
            var threaded = std.Io.Threaded.init(std.mem.Allocator.failing, .{});
            threaded.io().random(buf);
        }
    }

    fn milliTimestamp() u64 {
        if (builtin.os.tag == .linux) {
            var ts: std.os.linux.timespec = undefined;
            _ = std.os.linux.clock_gettime(.REALTIME, &ts);
            const sec_ms: u64 = @intCast(@as(i64, @intCast(ts.sec)) * 1000);
            const nsec_ms: u64 = @intCast(@divFloor(@as(i64, @intCast(ts.nsec)), 1_000_000));
            return sec_ms + nsec_ms;
        } else {
            var threaded = std.Io.Threaded.init(std.mem.Allocator.failing, .{});
            const io = threaded.io();
            const now = io.vtable.now(io.userdata, .real);
            return @intCast(@divFloor(now.nanoseconds, std.time.ns_per_ms));
        }
    }

    pub fn v4() UUID {
        var bin: [16]u8 = undefined;
        fillRandom(&bin);
        bin[6] = (bin[6] & 0x0f) | 0x40;
        bin[8] = (bin[8] & 0x3f) | 0x80;
        return .{ .bin = bin };
    }

    pub fn v7() UUID {
        const ts = milliTimestamp();
        const last = @atomicRmw(u64, &last_timestamp, .Xchg, ts, .monotonic);
        const sequence = if (ts <= last)
            @atomicRmw(u16, &clock_sequence, .Add, 1, .monotonic) + 1
        else
            @atomicLoad(u16, &clock_sequence, .monotonic);

        var bin: [16]u8 = undefined;
        const ts_buf = std.mem.asBytes(&ts);
        bin[0] = ts_buf[5];
        bin[1] = ts_buf[4];
        bin[2] = ts_buf[3];
        bin[3] = ts_buf[2];
        bin[4] = ts_buf[1];
        bin[5] = ts_buf[0];

        const seq_buf = std.mem.asBytes(&sequence);
        bin[6] = (seq_buf[1] & 0x0f) | 0x70;
        bin[7] = seq_buf[0];

        fillRandom(bin[8..]);
        bin[8] = (bin[8] & 0x3f) | 0x80;

        return .{ .bin = bin };
    }

    pub fn parse(hex: []const u8) !UUID {
        var bin: [16]u8 = undefined;

        if (hex.len != 36 or hex[8] != '-' or hex[13] != '-' or hex[18] != '-' or hex[23] != '-') {
            return error.InvalidUUID;
        }

        inline for (encoded_pos, 0..) |i, j| {
            const hi = hex_to_nibble[hex[i + 0]];
            const lo = hex_to_nibble[hex[i + 1]];
            if (hi == 0xff or lo == 0xff) {
                return error.InvalidUUID;
            }
            bin[j] = hi << 4 | lo;
        }
        return .{ .bin = bin };
    }

    pub fn toHex(self: UUID, case: std.fmt.Case) [36]u8 {
        var hex: [36]u8 = undefined;
        const alphabet = if (case == .lower) "0123456789abcdef" else "0123456789ABCDEF";

        hex[8] = '-';
        hex[13] = '-';
        hex[18] = '-';
        hex[23] = '-';

        inline for (encoded_pos, 0..) |i, j| {
            hex[i + 0] = alphabet[self.bin[j] >> 4];
            hex[i + 1] = alphabet[self.bin[j] & 0x0f];
        }
        return hex;
    }

    const encoded_pos = [16]u8{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };

    const hex_to_nibble = [_]u8{0xff} ** 48 ++ [_]u8{
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
    } ++ [_]u8{0xff} ** 152;
};

pub fn rfc4122(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    if (builtin.os.tag == .freestanding) return error.NotImplemented;
    const variant = try args.getString(0);
    const uuid = if (std.mem.eql(u8, variant, "v4"))
        UUID.v4()
    else if (std.mem.eql(u8, variant, "v7"))
        UUID.v7()
    else
        return error.InvalidArguments;
    const hex = uuid.toHex(.lower);
    return .{ .string = allocator.dupe(u8, &hex) catch return error.AllocationFailed };
}

pub fn parse(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    if (builtin.os.tag == .freestanding) return error.NotImplemented;
    const uuid_str = try args.getString(0);

    const uuid = UUID.parse(uuid_str) catch return error.InvalidArguments;

    var result = std.json.ObjectMap.empty;
    errdefer result.deinit(allocator);

    const version = (uuid.bin[6] >> 4) & 0x0F;
    const variant_byte = uuid.bin[8];
    const variant_name: []const u8 = if ((variant_byte & 0x80) == 0)
        "Reserved, NCS backward compatibility"
    else if ((variant_byte & 0xC0) == 0x80)
        "RFC4122"
    else if ((variant_byte & 0xE0) == 0xC0)
        "Reserved, Microsoft Corporation backward compatibility"
    else
        "Reserved for future definition";

    result.put(allocator, "version", .{ .integer = @intCast(version) }) catch return error.AllocationFailed;
    result.put(allocator, "variant", .{ .string = variant_name }) catch return error.AllocationFailed;

    return .{ .object = result };
}

test "uuid.rfc4122 v4" {
    if (builtin.os.tag == .freestanding) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try rfc4122(arena.allocator(), Args.init(&.{.{ .string = "v4" }}));
    try std.testing.expectEqual(@as(usize, 36), result.string.len);
    try std.testing.expectEqual(@as(u8, '-'), result.string[8]);
    try std.testing.expectEqual(@as(u8, '-'), result.string[13]);
    try std.testing.expectEqual(@as(u8, '4'), result.string[14]);
}

test "uuid.parse" {
    if (builtin.os.tag == .freestanding) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), Args.init(&.{.{ .string = "550e8400-e29b-41d4-a716-446655440000" }}));
    try std.testing.expectEqual(@as(i64, 4), result.object.get("version").?.integer);
    try std.testing.expectEqualStrings("RFC4122", result.object.get("variant").?.string);
}
