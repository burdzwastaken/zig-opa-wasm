const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn reachable(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const graph = try args.getObject(0);
    const initial = try args.getSetOrArray(1);

    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    var queue = std.ArrayListUnmanaged([]const u8){};
    defer queue.deinit(allocator);

    for (initial) |node| {
        if (node == .string) {
            queue.append(allocator, node.string) catch return error.AllocationFailed;
        }
    }

    while (queue.items.len > 0) {
        const node = queue.orderedRemove(0);
        if (visited.contains(node)) continue;
        visited.put(node, {}) catch return error.AllocationFailed;

        if (graph.get(node)) |neighbors| {
            const neighbor_list = switch (neighbors) {
                .array => |a| a.items,
                else => continue,
            };
            for (neighbor_list) |neighbor| {
                if (neighbor == .string and !visited.contains(neighbor.string)) {
                    queue.append(allocator, neighbor.string) catch return error.AllocationFailed;
                }
            }
        }
    }

    var result = std.json.Array.init(allocator);
    errdefer result.deinit();
    var iter = visited.keyIterator();
    while (iter.next()) |key| {
        result.append(.{ .string = key.* }) catch return error.AllocationFailed;
    }

    return .{ .array = result };
}

pub fn reachablePaths(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const graph = try args.getObject(0);
    const initial = try args.getSetOrArray(1);

    var all_paths = std.json.Array.init(allocator);

    for (initial) |start| {
        if (start != .string) continue;
        var path = std.json.Array.init(allocator);
        path.append(start) catch return error.AllocationFailed;
        findPaths(allocator, graph, start.string, &path, &all_paths) catch return error.AllocationFailed;
        path.deinit();
    }

    return .{ .array = all_paths };
}

fn findPaths(allocator: std.mem.Allocator, graph: std.json.ObjectMap, node: []const u8, current_path: *std.json.Array, all_paths: *std.json.Array) !void {
    var path_copy = std.json.Array.init(allocator);
    try path_copy.appendSlice(current_path.items);
    try all_paths.append(.{ .array = path_copy });

    if (graph.get(node)) |neighbors| {
        const neighbor_list = switch (neighbors) {
            .array => |a| a.items,
            else => return,
        };
        for (neighbor_list) |neighbor| {
            if (neighbor != .string) continue;
            var in_path = false;
            for (current_path.items) |p| {
                if (p == .string and std.mem.eql(u8, p.string, neighbor.string)) {
                    in_path = true;
                    break;
                }
            }
            if (!in_path) {
                try current_path.append(neighbor);
                try findPaths(allocator, graph, neighbor.string, current_path, all_paths);
                _ = current_path.pop();
            }
        }
    }
}

test "graph.reachable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = std.json.ObjectMap.init(alloc);
    var a_neighbors = std.json.Array.init(alloc);
    try a_neighbors.append(.{ .string = "b" });
    try graph.put("a", .{ .array = a_neighbors });
    var b_neighbors = std.json.Array.init(alloc);
    try b_neighbors.append(.{ .string = "c" });
    try graph.put("b", .{ .array = b_neighbors });

    var initial = std.json.Array.init(alloc);
    try initial.append(.{ .string = "a" });

    const result = try reachable(alloc, Args.init(&.{ .{ .object = graph }, .{ .array = initial } }));
    try std.testing.expect(result.array.items.len == 3);
}

test "graph.reachable_paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = std.json.ObjectMap.init(alloc);
    var a_neighbors = std.json.Array.init(alloc);
    try a_neighbors.append(.{ .string = "b" });
    try graph.put("a", .{ .array = a_neighbors });

    var initial = std.json.Array.init(alloc);
    try initial.append(.{ .string = "a" });

    const result = try reachablePaths(alloc, Args.init(&.{ .{ .object = graph }, .{ .array = initial } }));
    try std.testing.expect(result.array.items.len >= 1);
}
