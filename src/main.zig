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
        try stdout.writeAll("opa-zig 0.0.7\n");
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

fn runCommand(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    printUsageFn: *const fn () anyerror!void,
    runFn: *const fn (std.mem.Allocator, []const []const u8) anyerror!void,
) !void {
    if (args.len > 0) {
        const arg = args[0];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printUsageFn();
            return;
        }
    }
    try runFn(allocator, args);
}

fn runInfoCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    try runCommand(allocator, args, info.printUsage, info.runWithArgs);
}

fn runEvalCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    try runCommand(allocator, args, eval_cmd.printUsage, eval_cmd.run);
}

fn runBenchCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    try runCommand(allocator, args, bench_cmd.printUsage, bench_cmd.run);
}

fn runComplianceCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    try runCommand(allocator, args, compliance_cmd.printUsage, compliance_cmd.run);
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
