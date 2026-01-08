# zig-opa-wasm

[![Zig](https://img.shields.io/badge/Zig-≥0.15.2-color?logo=zig&color=%23f3ab20)](https://ziglang.org/download/)
[![Release](https://img.shields.io/github/v/release/burdzwastaken/zig-opa-wasm)](https://github.com/burdzwastaken/zig-opa-wasm/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/burdzwastaken/zig-opa-wasm/ci.yml?branch=master)](https://github.com/burdzwastaken/zig-opa-wasm/actions)

A Zig library to use OPA policies compiled to WASM.

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zig_opa_wasm = .{
        .url = "git+https://github.com/burdzwastaken/zig-opa-wasm#v0.0.6",
        .hash = "...",
    },
},
```

Then in `build.zig`:

```zig
const opa = b.dependency("zig_opa_wasm", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("opa", opa.module("opa"));
```

## Build

```bash
# build with Wasmer (default)
zig build

# build with zware (pure Zig)
zig build -Dbackend=zware

# build for wasm32-freestanding
zig build -Dbackend=freestanding
```

## CLI

```bash
# evaluate a policy
zig-out/bin/opa-zig eval -m policy.wasm -e "example/allow" -i '{"user":"admin"}'

# evaluate with data
zig-out/bin/opa-zig eval -m policy.wasm -e "authz/allow" -d '{"roles":["admin"]}' -i '{"user":"alice"}'

# load from OPA bundle
zig-out/bin/opa-zig eval -m bundle.tar.gz -e "main/decision" -i '{"action":"read"}'

# inspect a WASM module
zig-out/bin/opa-zig info policy.wasm

# benchmark evaluation
zig-out/bin/opa-zig bench -m policy.wasm -e "example/allow" -i '{}' -n 10000
```

## API

### Basic Evaluation

```zig
const opa = @import("opa");

var wasm_backend = try opa.WasmerBackend.init(allocator);
defer wasm_backend.deinit();

var be = wasm_backend.asBackend();
var policy = try opa.Policy.load(allocator, &be, wasm_bytes);
defer policy.deinit();

var instance = try opa.Instance.create(allocator, &policy);
defer instance.deinit();

const result = try instance.evaluate("example/allow", "{\"user\":\"admin\"}");
defer allocator.free(result);
```

### With Data Document

```zig
var instance = try opa.Instance.create(allocator, &policy);
defer instance.deinit();

try instance.setData("{\"roles\":{\"admin\":[\"read\",\"write\"]}}");

const result = try instance.evaluate("authz/allow", "{\"user\":\"alice\",\"role\":\"admin\"}");
defer allocator.free(result);
```

### Typed Evaluation

```zig
// OPA returns results as [{"result": <value>}]
const OpaResult = struct { result: bool };

const results = try instance.evaluateTyped([]OpaResult, "authz/allow", .{ .user = "admin" });
if (results.len > 0 and results[0].result) {
    // allowed
}
```

### Instance Pooling

```zig
var pool = try opa.InstancePool.init(allocator, &policy, 4);
defer pool.deinit();

const inst = try pool.acquire();
defer pool.release(inst);

const result = try inst.evaluate("example/allow", "{}");
defer allocator.free(result);
```

### Bundle Loading

```zig
var bundle = try opa.Bundle.fromFile(allocator, "policy.tar.gz");
defer bundle.deinit();

var policy = try opa.Policy.load(allocator, &be, bundle.wasm);
defer policy.deinit();
```

### Policy Validation

```zig
var policy = try opa.Policy.load(allocator, &be, wasm_bytes);
defer policy.deinit();

var result = try policy.validate(allocator);
defer result.deinit(allocator);

if (!result.valid) {
    for (result.unsupported_builtins) |name| {
        std.debug.print("unsupported builtin: {s}\n", .{name});
    }
}
```

### Debug Logging

```zig
var wasm_backend = try opa.WasmerBackend.init(allocator);
defer wasm_backend.deinit();

wasm_backend.setLogCallback(struct {
    fn log(level: opa.LogLevel, msg: []const u8) void {
        std.debug.print("[{s}] {s}\n", .{ @tagName(level), msg });
    }
}.log, .debug);
```

## Architecture

### Pluggable Backend

The library uses an abstract backend interface allowing different WASM runtimes to be swapped without changing application code.

**Backends:**
| Backend               | Runtime                                              | Use Case                                            |
|-----------------------|------------------------------------------------------|-----------------------------------------------------|
| `WasmerBackend`       | [Wasmer](https://github.com/zig-wasm/wasmer-zig-api) | Native builds, JIT compilation, best performance    |
| `ZwareBackend`        | [zware](https://github.com/malcolmstill/zware)       | Pure Zig interpreter, no C dependencies             |
| `FreestandingBackend` | [zware](https://github.com/malcolmstill/zware)       | wasm32-freestanding target for browser/JS embedding |

Select backend at build time with `-Dbackend=wasmer` (default), `-Dbackend=zware`, or `-Dbackend=freestanding`. The freestanding backend compiles zig-opa-wasm itself to WebAssembly.

## Supported Builtins

100+ builtins implemented depending on the backend.

## License

MIT
