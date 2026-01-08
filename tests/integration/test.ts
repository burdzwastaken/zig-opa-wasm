import { file } from "bun";
import { join } from "path";

const __dirname = import.meta.dir;

async function test() {
  const engineWasm = await file(join(__dirname, "../../zig-out/bin/zig-opa-wasm.wasm")).arrayBuffer();
  const policyWasm = await file(join(__dirname, "policy.wasm")).arrayBuffer();

  const { instance } = await WebAssembly.instantiate(engineWasm, {});
  const exports = instance.exports as Record<string, WebAssembly.ExportValue>;

  const memory = exports.memory as WebAssembly.Memory;
  const ioBuffer = (exports.getIOBuffer as () => number)();
  const ioBufferSize = (exports.getIOBufferSize as () => number)();
  const resultBuffer = (exports.getResultBuffer as () => number)();

  console.log("IO buffer size:", ioBufferSize);

  const initResult = (exports.init as () => number)();
  console.log("init():", initResult);
  if (initResult !== 0) throw new Error("init failed");

  const memView = new Uint8Array(memory.buffer);
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  const policyName = "example";
  const policyNameBytes = encoder.encode(policyName);
  memView.set(policyNameBytes, ioBuffer);

  const policyWasmOffset = 256;
  memView.set(new Uint8Array(policyWasm), ioBuffer + policyWasmOffset);

  const loadPolicy = exports.loadPolicy as (a: number, b: number, c: number, d: number) => number;
  const loadResult = loadPolicy(0, policyNameBytes.length, policyWasmOffset, policyWasm.byteLength);
  console.log("loadPolicy():", loadResult);
  if (loadResult < 0) {
    const errLen = (exports.getResultLen as () => number)();
    const errMsg = decoder.decode(memView.slice(resultBuffer, resultBuffer + errLen));
    throw new Error(`loadPolicy failed: ${errMsg}`);
  }

  const getLoadedPolicies = exports.getLoadedPolicies as () => number;
  const listResult = getLoadedPolicies();
  console.log("getLoadedPolicies() len:", listResult);
  if (listResult > 0) {
    const policies = decoder.decode(memView.slice(resultBuffer, resultBuffer + listResult));
    console.log("Loaded policies:", policies);
  }

  const getEntrypoints = exports.getEntrypoints as (a: number, b: number) => number;
  const epResult = getEntrypoints(0, policyNameBytes.length);
  console.log("getEntrypoints() len:", epResult);
  if (epResult > 0) {
    const entrypoints = decoder.decode(memView.slice(resultBuffer, resultBuffer + epResult));
    console.log("Entrypoints:", entrypoints);
  }

  const entrypoint = "example/result";
  const input = JSON.stringify({ user: "admin", action: "write" });

  const entrypointBytes = encoder.encode(entrypoint);
  const inputBytes = encoder.encode(input);

  memView.set(policyNameBytes, ioBuffer);
  memView.set(entrypointBytes, ioBuffer + 64);
  memView.set(inputBytes, ioBuffer + 256);

  const evaluate = exports.evaluate as (a: number, b: number, c: number, d: number, e: number, f: number) => number;
  const evalResult = evaluate(
    0, policyNameBytes.length,
    64, entrypointBytes.length,
    256, inputBytes.length
  );
  console.log("evaluate() len:", evalResult);

  if (evalResult < 0) {
    const errLen = (exports.getResultLen as () => number)();
    const errMsg = decoder.decode(memView.slice(resultBuffer, resultBuffer + errLen));
    throw new Error(`evaluate failed: ${errMsg}`);
  }

  const result = decoder.decode(memView.slice(resultBuffer, resultBuffer + evalResult));
  console.log("Result:", result);

  const parsed = JSON.parse(result);
  console.log("Parsed result:", JSON.stringify(parsed, null, 2));

  if (!parsed[0]?.result?.allow) {
    throw new Error("Expected allow=true for admin user");
  }

  console.log("\nTest 2: non-admin read");
  const input2 = JSON.stringify({ user: "guest", action: "read" });
  const input2Bytes = encoder.encode(input2);
  memView.set(policyNameBytes, ioBuffer);
  memView.set(entrypointBytes, ioBuffer + 64);
  memView.set(input2Bytes, ioBuffer + 256);

  const evalResult2 = evaluate(0, policyNameBytes.length, 64, entrypointBytes.length, 256, input2Bytes.length);
  if (evalResult2 > 0) {
    const result2 = decoder.decode(memView.slice(resultBuffer, resultBuffer + evalResult2));
    console.log("Result:", result2);
  }

  console.log("\nTest 3: non-admin write (should deny)");
  const input3 = JSON.stringify({ user: "guest", action: "write" });
  const input3Bytes = encoder.encode(input3);
  memView.set(policyNameBytes, ioBuffer);
  memView.set(entrypointBytes, ioBuffer + 64);
  memView.set(input3Bytes, ioBuffer + 256);

  const evalResult3 = evaluate(0, policyNameBytes.length, 64, entrypointBytes.length, 256, input3Bytes.length);
  if (evalResult3 > 0) {
    const result3 = decoder.decode(memView.slice(resultBuffer, resultBuffer + evalResult3));
    console.log("Result:", result3);
    const parsed3 = JSON.parse(result3);
    if (parsed3[0]?.result?.allow) {
      throw new Error("Expected allow=false for guest write");
    }
  }

  (exports.deinit as () => void)();
  console.log("\nAll tests passed!");
}

test().catch(err => {
  console.error("Test failed:", err);
  process.exit(1);
});
