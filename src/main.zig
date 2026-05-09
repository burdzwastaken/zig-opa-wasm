//! CLI entry point for opa-zig dispatches to subcommands.

const std = @import("std");
const info = @import("cli/info.zig");
const eval_cmd = @import("cli/eval.zig");
const bench_cmd = @import("cli/bench.zig");
const compliance_cmd = @import("cli/compliance.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    const all_args = try init.minimal.args.toSlice(init.arena.allocator());
    const args = if (all_args.len > 0) all_args[1..] else all_args[0..0];

    if (args.len < 1) {
        printUsage(io);
        return;
    }

    const cmd = args[0];

    if (std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) {
        printUsage(io);
        return;
    }

    if (std.mem.eql(u8, cmd, "-v") or std.mem.eql(u8, cmd, "--version")) {
        std.Io.File.stdout().writeStreamingAll(io, "opa-zig 0.0.8\n") catch {};
        return;
    }

    if (std.mem.eql(u8, cmd, "info")) {
        try runInfoCommand(allocator, io, args[1..]);
    } else if (std.mem.eql(u8, cmd, "eval")) {
        try runEvalCommand(allocator, io, args[1..]);
    } else if (std.mem.eql(u8, cmd, "bench")) {
        try runBenchCommand(allocator, io, args[1..]);
    } else if (std.mem.eql(u8, cmd, "compliance")) {
        try runComplianceCommand(allocator, io, args[1..]);
    } else {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "error: unknown command '{s}'\n\n", .{cmd}) catch unreachable;
        std.Io.File.stderr().writeStreamingAll(io, msg) catch {};
        printUsage(io);
    }
}

fn runCommand(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: []const []const u8,
    printUsageFn: *const fn (std.Io) void,
    runFn: *const fn (std.mem.Allocator, std.Io, []const []const u8) anyerror!void,
) !void {
    if (args.len > 0) {
        const arg = args[0];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsageFn(io);
            return;
        }
    }
    try runFn(allocator, io, args);
}

fn runInfoCommand(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    try runCommand(allocator, io, args, info.printUsage, info.runWithArgs);
}

fn runEvalCommand(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    try runCommand(allocator, io, args, eval_cmd.printUsage, eval_cmd.run);
}

fn runBenchCommand(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    try runCommand(allocator, io, args, bench_cmd.printUsage, bench_cmd.run);
}

fn runComplianceCommand(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    try runCommand(allocator, io, args, compliance_cmd.printUsage, compliance_cmd.run);
}

fn printUsage(io: std.Io) void {
    std.Io.File.stdout().writeStreamingAll(io,
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
    ) catch {};
}
