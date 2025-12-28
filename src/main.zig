//! CLI entry point for opa-zig dispatches to subcommands.

const std = @import("std");
const info = @import("cli/info.zig");
const eval_cmd = @import("cli/eval.zig");
const bench_cmd = @import("cli/bench.zig");
const compliance_cmd = @import("cli/compliance.zig");

const stdout = std.fs.File.stdout();
const stderr = std.fs.File.stderr();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) {
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, cmd, "-v") or std.mem.eql(u8, cmd, "--version")) {
        try stdout.writeAll("opa-zig 0.0.2\n");
        return;
    }

    if (std.mem.eql(u8, cmd, "info")) {
        try runInfoCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "eval")) {
        try runEvalCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "bench")) {
        try runBenchCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "compliance")) {
        try runComplianceCommand(allocator, args[2..]);
    } else {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "error: unknown command '{s}'\n\n", .{cmd}) catch unreachable;
        try stderr.writeAll(msg);
        try printUsage();
    }
}

fn runInfoCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try stderr.writeAll("error: missing FILE argument\n\n");
        try info.printUsage();
        return;
    }

    const arg = args[0];

    if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
        try info.printUsage();
        return;
    }

    try info.run(allocator, .{ .file = arg });
}

fn runEvalCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0) {
        const arg = args[0];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try eval_cmd.printUsage();
            return;
        }
    }
    try eval_cmd.run(allocator, args);
}

fn runBenchCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0) {
        const arg = args[0];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try bench_cmd.printUsage();
            return;
        }
    }
    try bench_cmd.run(allocator, args);
}

fn runComplianceCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0) {
        const arg = args[0];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try compliance_cmd.printUsage();
            return;
        }
    }
    try compliance_cmd.run(allocator, args);
}

fn printUsage() !void {
    try stdout.writeAll(
        \\opa-zig - OPA WebAssembly Policy Evaluator
        \\
        \\USAGE:
        \\    opa-zig <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    info        Inspect a WASM module (ABI version, entrypoints, builtins)
        \\    eval        Evaluate a policy
        \\    bench       Benchmark policy evaluation
        \\    compliance  Run OPA WASM compliance tests
        \\
        \\OPTIONS:
        \\    -h, --help       Show this help message
        \\    -v, --version    Show version
        \\
        \\EXAMPLES:
        \\    opa-zig info policy.wasm
        \\    opa-zig eval -m policy.wasm -e "authz/allow" -i '{"user":"alice"}'
        \\
    );
}
