//! Abstract WASM runtime backend interface.

const std = @import("std");

pub const Error = error{
    EngineInit,
    StoreInit,
    ModuleInit,
    ModuleValidation,
    InstanceInit,
    ExportNotFound,
    FunctionCall,
    MemoryAccess,
    OutOfMemory,
    Trap,
};

/// WASM value types.
pub const Value = union(enum) {
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,
};

/// Host function imports required by OPA WASM modules.
pub const Imports = struct {
    opa_abort: ?*const fn (ctx: *anyopaque, msg_addr: i32) void = null,
    opa_println: ?*const fn (ctx: *anyopaque, msg_addr: i32) void = null,
    opa_builtin0: ?*const fn (ctx: *anyopaque, builtin_id: i32, ctx_addr: i32) i32 = null,
    opa_builtin1: ?*const fn (ctx: *anyopaque, builtin_id: i32, ctx_addr: i32, a0: i32) i32 = null,
    opa_builtin2: ?*const fn (ctx: *anyopaque, builtin_id: i32, ctx_addr: i32, a0: i32, a1: i32) i32 = null,
    opa_builtin3: ?*const fn (ctx: *anyopaque, builtin_id: i32, ctx_addr: i32, a0: i32, a1: i32, a2: i32) i32 = null,
    opa_builtin4: ?*const fn (ctx: *anyopaque, builtin_id: i32, ctx_addr: i32, a0: i32, a1: i32, a2: i32, a3: i32) i32 = null,
    context: ?*anyopaque = null,
};

/// Linear memory exported from WASM.
pub const Memory = struct {
    ptr: *anyopaque,
    vtable: *const MemoryVTable,

    pub const MemoryVTable = struct {
        data: *const fn (ptr: *anyopaque) [*]u8,
        size: *const fn (ptr: *anyopaque) usize,
        grow: *const fn (ptr: *anyopaque, pages: u32) Error!void,
    };

    pub fn data(self: Memory) [*]u8 {
        return self.vtable.data(self.ptr);
    }

    pub fn size(self: Memory) usize {
        return self.vtable.size(self.ptr);
    }

    pub fn slice(self: Memory) []u8 {
        return self.data()[0..self.size()];
    }

    pub fn grow(self: Memory, pages: u32) Error!void {
        return self.vtable.grow(self.ptr, pages);
    }

    pub fn read(self: Memory, offset: u32, len: u32) Error![]const u8 {
        const mem_size = self.size();
        if (offset + len > mem_size) return Error.MemoryAccess;
        return self.data()[offset..][0..len];
    }

    pub fn write(self: Memory, offset: u32, bytes: []const u8) Error!void {
        const mem_size = self.size();
        if (offset + bytes.len > mem_size) return Error.MemoryAccess;
        @memcpy(self.data()[offset..][0..bytes.len], bytes);
    }

    pub fn readCString(self: Memory, offset: u32) Error![]const u8 {
        const mem = self.slice();
        if (offset >= mem.len) return Error.MemoryAccess;
        const start = offset;
        var end = start;
        while (end < mem.len and mem[end] != 0) : (end += 1) {}
        return mem[start..end];
    }
};

/// Callable WASM function.
pub const Func = struct {
    ptr: *anyopaque,
    vtable: *const FuncVTable,

    pub const FuncVTable = struct {
        call0: *const fn (ptr: *anyopaque) Error!i32,
        call1: *const fn (ptr: *anyopaque, arg0: i32) Error!i32,
        call2: *const fn (ptr: *anyopaque, arg0: i32, arg1: i32) Error!i32,
        call1v: *const fn (ptr: *anyopaque, arg0: i32) Error!void,
        call2v: *const fn (ptr: *anyopaque, arg0: i32, arg1: i32) Error!void,
    };

    pub fn call0(self: Func) Error!i32 {
        return self.vtable.call0(self.ptr);
    }

    pub fn call1(self: Func, a0: i32) Error!i32 {
        return self.vtable.call1(self.ptr, a0);
    }

    pub fn call2(self: Func, a0: i32, a1: i32) Error!i32 {
        return self.vtable.call2(self.ptr, a0, a1);
    }

    pub fn call1v(self: Func, a0: i32) Error!void {
        return self.vtable.call1v(self.ptr, a0);
    }

    pub fn call2v(self: Func, a0: i32, a1: i32) Error!void {
        return self.vtable.call2v(self.ptr, a0, a1);
    }
};

/// Live WASM instance with exports accessible.
pub const Instance = struct {
    ptr: *anyopaque,
    vtable: *const InstanceVTable,
    module_ptr: *anyopaque,

    pub const InstanceVTable = struct {
        deinit: *const fn (ptr: *anyopaque) void,
        getFunc: *const fn (ptr: *anyopaque, module_ptr: *anyopaque, name: []const u8) ?Func,
        getMemory: *const fn (ptr: *anyopaque, module_ptr: *anyopaque, name: []const u8) ?Memory,
        getGlobal: *const fn (ptr: *anyopaque, module_ptr: *anyopaque, name: []const u8) ?i32,
    };

    pub fn deinit(self: Instance) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn getFunc(self: Instance, name: []const u8) ?Func {
        return self.vtable.getFunc(self.ptr, self.module_ptr, name);
    }

    pub fn getMemory(self: Instance, name: []const u8) ?Memory {
        return self.vtable.getMemory(self.ptr, self.module_ptr, name);
    }

    pub fn getGlobal(self: Instance, name: []const u8) ?i32 {
        return self.vtable.getGlobal(self.ptr, self.module_ptr, name);
    }
};

/// Compiled WASM module.
pub const Module = struct {
    ptr: *anyopaque,
    vtable: *const ModuleVTable,
    backend_ptr: *anyopaque,

    pub const ModuleVTable = struct {
        deinit: *const fn (ptr: *anyopaque) void,
        instantiate: *const fn (ptr: *anyopaque, backend_ptr: *anyopaque, imports: Imports) Error!Instance,
    };

    pub fn deinit(self: Module) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn instantiate(self: Module, imports: Imports) Error!Instance {
        return self.vtable.instantiate(self.ptr, self.backend_ptr, imports);
    }
};

/// Abstract WASM runtime backend interface.
pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const BackendVTable,

    pub const BackendVTable = struct {
        deinit: *const fn (ptr: *anyopaque) void,
        loadModule: *const fn (ptr: *anyopaque, wasm_bytes: []const u8) Error!Module,
    };

    pub fn deinit(self: Backend) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn loadModule(self: Backend, wasm_bytes: []const u8) Error!Module {
        return self.vtable.loadModule(self.ptr, wasm_bytes);
    }
};
