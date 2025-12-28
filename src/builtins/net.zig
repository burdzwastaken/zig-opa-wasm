//! OPA network and CIDR builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn cidrContains(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const cidr_str = try args.getString(0);
    const ip_or_cidr = try args.getString(1);

    const net = parseCidr(cidr_str) orelse return error.InvalidArguments;
    const target = parseCidrOrIp(ip_or_cidr) orelse return error.InvalidArguments;

    const contained = (target.addr & net.mask) == (net.addr & net.mask);
    return .{ .bool = contained };
}

pub fn cidrContainsMatches(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const cidrs_val = try args.get(0);
    const ips_val = try args.get(1);

    const cidrs = switch (cidrs_val) {
        .array => |arr| arr.items,
        .string => |s| &[_]std.json.Value{.{ .string = s }},
        else => return error.TypeMismatch,
    };

    const ips = switch (ips_val) {
        .array => |arr| arr.items,
        .string => |s| &[_]std.json.Value{.{ .string = s }},
        else => return error.TypeMismatch,
    };

    var results = std.json.Array.init(allocator);
    errdefer results.deinit();

    for (cidrs, 0..) |cidr_val, i| {
        const cidr_str = if (cidr_val == .string) cidr_val.string else continue;
        const net = parseCidr(cidr_str) orelse continue;

        for (ips, 0..) |ip_val, j| {
            const ip_str = if (ip_val == .string) ip_val.string else continue;
            const target = parseCidrOrIp(ip_str) orelse continue;

            if ((target.addr & net.mask) == (net.addr & net.mask)) {
                var pair = std.json.Array.init(allocator);
                pair.append(.{ .integer = @intCast(i) }) catch return error.AllocationFailed;
                pair.append(.{ .integer = @intCast(j) }) catch return error.AllocationFailed;
                results.append(.{ .array = pair }) catch return error.AllocationFailed;
            }
        }
    }

    return .{ .array = results };
}

pub fn cidrExpand(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const cidr_str = try args.getString(0);
    const net = parseCidr(cidr_str) orelse return error.InvalidArguments;

    const host_bits: u5 = @intCast(32 - net.prefix);
    const num_hosts: u32 = @as(u32, 1) << host_bits;

    if (num_hosts > 65536) return error.InvalidArguments;

    var results = std.json.Array.init(allocator);
    errdefer results.deinit();

    const base = net.addr & net.mask;
    var i: u32 = 0;
    while (i < num_hosts) : (i += 1) {
        const ip_str = formatIp4(allocator, base | i) catch return error.AllocationFailed;
        results.append(.{ .string = ip_str }) catch return error.AllocationFailed;
    }

    return .{ .array = results };
}

pub fn cidrMerge(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const arr = try args.getArray(0);

    var networks = std.ArrayListUnmanaged(Network){};
    defer networks.deinit(allocator);

    for (arr) |item| {
        if (item != .string) continue;
        if (parseCidr(item.string)) |net| {
            networks.append(allocator, net) catch return error.AllocationFailed;
        }
    }

    std.mem.sort(Network, networks.items, {}, struct {
        fn lessThan(_: void, a: Network, b: Network) bool {
            if (a.addr != b.addr) return a.addr < b.addr;
            return a.prefix < b.prefix;
        }
    }.lessThan);

    var results = std.json.Array.init(allocator);
    errdefer results.deinit();

    var idx: usize = 0;
    while (idx < networks.items.len) {
        var current = networks.items[idx];
        idx += 1;

        while (idx < networks.items.len) {
            const next = networks.items[idx];
            const current_end = (current.addr & current.mask) + (@as(u32, 1) << @intCast(32 - current.prefix));
            const next_start = next.addr & next.mask;

            if (next_start <= current_end) {
                const next_end = next_start + (@as(u32, 1) << @intCast(32 - next.prefix));
                if (next_end > current_end) {
                    const new_size = next_end - (current.addr & current.mask);
                    var new_prefix: u8 = 32;
                    var size: u32 = 1;
                    while (size < new_size and new_prefix > 0) {
                        new_prefix -= 1;
                        size <<= 1;
                    }
                    current.prefix = new_prefix;
                    current.mask = if (new_prefix == 0) 0 else (~@as(u32, 0)) << @intCast(32 - new_prefix);
                }
                idx += 1;
            } else {
                break;
            }
        }

        const cidr_str = formatCidr(allocator, current) catch return error.AllocationFailed;
        results.append(.{ .string = cidr_str }) catch return error.AllocationFailed;
    }

    return .{ .array = results };
}

const Network = struct {
    addr: u32,
    mask: u32,
    prefix: u8,
};

fn parseCidr(s: []const u8) ?Network {
    const slash_pos = std.mem.indexOf(u8, s, "/") orelse return null;
    const ip_part = s[0..slash_pos];
    const prefix_part = s[slash_pos + 1 ..];

    const addr = parseIpv4(ip_part) orelse return null;
    const prefix = std.fmt.parseInt(u8, prefix_part, 10) catch return null;
    if (prefix > 32) return null;

    const mask: u32 = if (prefix == 0) 0 else (~@as(u32, 0)) << @intCast(32 - prefix);
    return .{ .addr = addr, .mask = mask, .prefix = prefix };
}

fn parseCidrOrIp(s: []const u8) ?Network {
    if (std.mem.indexOf(u8, s, "/")) |_| {
        return parseCidr(s);
    }
    const addr = parseIpv4(s) orelse return null;
    return .{ .addr = addr, .mask = 0xFFFFFFFF, .prefix = 32 };
}

fn parseIpv4(s: []const u8) ?u32 {
    const addr = std.net.Ip4Address.parse(s, 0) catch return null;
    return std.mem.bigToNative(u32, addr.sa.addr);
}

fn formatIp4(allocator: std.mem.Allocator, addr: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{
        @as(u8, @truncate(addr >> 24)), @as(u8, @truncate(addr >> 16)),
        @as(u8, @truncate(addr >> 8)),  @as(u8, @truncate(addr)),
    });
}

fn formatCidr(allocator: std.mem.Allocator, net: Network) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{}.{}.{}.{}/{}", .{
        @as(u8, @truncate(net.addr >> 24)), @as(u8, @truncate(net.addr >> 16)),
        @as(u8, @truncate(net.addr >> 8)),  @as(u8, @truncate(net.addr)),
        net.prefix,
    });
}

test "net.cidr_contains" {
    const allocator = std.testing.allocator;

    var result = try cidrContains(allocator, Args.init(&.{
        .{ .string = "192.168.1.0/24" },
        .{ .string = "192.168.1.100" },
    }));
    try std.testing.expect(result.bool);

    result = try cidrContains(allocator, Args.init(&.{
        .{ .string = "192.168.1.0/24" },
        .{ .string = "192.168.2.100" },
    }));
    try std.testing.expect(!result.bool);

    result = try cidrContains(allocator, Args.init(&.{
        .{ .string = "10.0.0.0/8" },
        .{ .string = "10.255.255.255" },
    }));
    try std.testing.expect(result.bool);
}

pub fn cidrIntersects(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const cidr1_str = try args.getString(0);
    const cidr2_str = try args.getString(1);

    const net1 = parseCidr(cidr1_str) orelse return error.InvalidArguments;
    const net2 = parseCidr(cidr2_str) orelse return error.InvalidArguments;

    const smaller_prefix = @min(net1.prefix, net2.prefix);
    const mask: u32 = if (smaller_prefix == 0) 0 else (~@as(u32, 0)) << @intCast(32 - smaller_prefix);

    const intersects = (net1.addr & mask) == (net2.addr & mask);
    return .{ .bool = intersects };
}

pub fn cidrIsValid(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const cidr_str = try args.getString(0);
    return .{ .bool = parseCidr(cidr_str) != null };
}

test "net.cidr_expand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try cidrExpand(arena.allocator(), Args.init(&.{
        .{ .string = "192.168.1.0/30" },
    }));
    try std.testing.expectEqual(@as(usize, 4), result.array.items.len);
    try std.testing.expectEqualStrings("192.168.1.0", result.array.items[0].string);
    try std.testing.expectEqualStrings("192.168.1.1", result.array.items[1].string);
    try std.testing.expectEqualStrings("192.168.1.2", result.array.items[2].string);
    try std.testing.expectEqualStrings("192.168.1.3", result.array.items[3].string);
}

test "net.cidr_intersects" {
    const allocator = std.testing.allocator;

    var result = try cidrIntersects(allocator, Args.init(&.{
        .{ .string = "192.168.1.0/24" },
        .{ .string = "192.168.1.128/25" },
    }));
    try std.testing.expect(result.bool);

    result = try cidrIntersects(allocator, Args.init(&.{
        .{ .string = "192.168.1.0/24" },
        .{ .string = "192.168.2.0/24" },
    }));
    try std.testing.expect(!result.bool);

    result = try cidrIntersects(allocator, Args.init(&.{
        .{ .string = "10.0.0.0/8" },
        .{ .string = "10.1.2.0/24" },
    }));
    try std.testing.expect(result.bool);
}

test "net.cidr_is_valid" {
    const allocator = std.testing.allocator;

    var result = try cidrIsValid(allocator, Args.init(&.{.{ .string = "192.168.1.0/24" }}));
    try std.testing.expect(result.bool);

    result = try cidrIsValid(allocator, Args.init(&.{.{ .string = "not-a-cidr" }}));
    try std.testing.expect(!result.bool);

    result = try cidrIsValid(allocator, Args.init(&.{.{ .string = "192.168.1.0/33" }}));
    try std.testing.expect(!result.bool);
}
