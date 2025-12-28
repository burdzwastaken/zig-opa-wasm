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
        .url = "git+https://github.com/burdzwastaken/zig-opa-wasm#v0.0.2",
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

## CLI

```bash
zig build

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
const Decision = struct { allow: bool };

const decision = try instance.evaluateTyped(Decision, "authz/allow", "{\"user\":\"admin\"}");
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

wasm_backend.setLogLevel(.debug);
wasm_backend.setLogCallback(struct {
    fn log(level: opa.LogLevel, msg: []const u8) void {
        std.debug.print("[{s}] {s}\n", .{@tagName(level), msg});
    }
}.log);
```

## Architecture

### Pluggable Backend

The library uses an abstract backend interface allowing different WASM runtimes to be swapped without changing application code.

**Current backends:**
- `WasmerBackend` - [Wasmer](https://github.com/zig-wasm/wasmer-zig-api) runtime (default)

## Supported Builtins

85+ builtins implemented including:

- **Strings**: `concat`, `contains`, `sprintf`, `split`, `trim`, `lower`, `upper`, etc.
- **Numbers**: `abs`, `round`, `ceil`, `floor`, `numbers.range`
- **Arrays**: `array.concat`, `array.slice`, `count`, `sort`
- **Objects**: `object.get`, `object.keys`, `object.remove`, `object.union`
- **Encoding**: `base64.encode/decode`, `hex.encode/decode`, `urlquery.encode/decode`
- **Crypto**: `crypto.md5`, `crypto.sha1`, `crypto.sha256`
- **Time**: `time.now_ns`, `time.parse_rfc3339_ns`, `time.date`, `time.diff`
- **Regex**: `regex.match`, `regex.split`, `regex.find_n`
- **Net**: `net.cidr_contains`, `net.cidr_intersects`
- **Types**: `is_string`, `is_number`, `is_array`, `is_object`, `type_name`

## License

MIT
