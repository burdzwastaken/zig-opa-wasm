//! OPA bundle (.tar.gz) loader.

const std = @import("std");

/// Extracted OPA bundle contents.
pub const Bundle = struct {
    allocator: std.mem.Allocator,
    wasm: []const u8,
    data: ?[]const u8,
    manifest: ?[]const u8,

    pub fn deinit(self: *Bundle) void {
        self.allocator.free(self.wasm);
        if (self.data) |d| self.allocator.free(d);
        if (self.manifest) |m| self.allocator.free(m);
    }

    /// Extract bundle from a file path.
    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Bundle {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const bytes = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(bytes);
        return fromBytes(allocator, bytes);
    }
};

const BundleFile = enum { wasm, data, manifest };

const known_files = std.StaticStringMap(BundleFile).initComptime(.{
    .{ "policy.wasm", .wasm },
    .{ "/policy.wasm", .wasm },
    .{ "data.json", .data },
    .{ "/data.json", .data },
    .{ ".manifest", .manifest },
    .{ "/.manifest", .manifest },
});

/// Extract bundle from gzipped tar bytes.
pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !Bundle {
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var gzip_reader = std.Io.Reader.fixed(bytes);
    var decompressor = std.compress.flate.Decompress.init(&gzip_reader, .gzip, &window);

    var wasm: ?[]const u8 = null;
    var data: ?[]const u8 = null;
    var manifest: ?[]const u8 = null;

    var file_name_buf: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buf: [std.fs.max_path_bytes]u8 = undefined;
    var iter = std.tar.Iterator.init(&decompressor.reader, .{
        .file_name_buffer = &file_name_buf,
        .link_name_buffer = &link_name_buf,
    });

    while (true) {
        const file = iter.next() catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        } orelse break;

        if (known_files.get(file.name)) |file_type| {
            const content = try readTarEntry(allocator, &iter, file);
            switch (file_type) {
                .wasm => wasm = content,
                .data => data = content,
                .manifest => manifest = content,
            }
        } else {
            const skip_buf = try readTarEntry(allocator, &iter, file);
            allocator.free(skip_buf);
        }
    }

    if (wasm == null) return error.NoPolicyWasm;

    return Bundle{
        .allocator = allocator,
        .wasm = wasm.?,
        .data = data,
        .manifest = manifest,
    };
}

fn readTarEntry(allocator: std.mem.Allocator, iter: *std.tar.Iterator, file: std.tar.Iterator.File) ![]const u8 {
    if (file.size == 0) return try allocator.dupe(u8, "");

    const buf = try allocator.alloc(u8, file.size);
    errdefer allocator.free(buf);

    var io_writer = std.Io.Writer.fixed(buf);
    try iter.streamRemaining(file, &io_writer);

    return buf;
}

/// Check if path looks like an OPA bundle.
pub fn isBundle(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".tar.gz") or std.mem.endsWith(u8, path, ".tgz");
}

test "isBundle" {
    try std.testing.expect(isBundle("policy.tar.gz"));
    try std.testing.expect(isBundle("/path/to/bundle.tar.gz"));
    try std.testing.expect(isBundle("bundle.tgz"));
    try std.testing.expect(!isBundle("policy.wasm"));
    try std.testing.expect(!isBundle("policy.tar"));
}

test "fromFile with non-existent file" {
    const result = Bundle.fromFile(std.testing.allocator, "/non/existent/bundle.tar.gz");
    try std.testing.expectError(error.FileNotFound, result);
}
