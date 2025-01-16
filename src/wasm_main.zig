const std = @import("std");
const wasm_print = @import("wasm_print.zig");
const wasm_asm = @import("wasm_asm.zig");
const logger = @import("logger.zig");
pub const allocator = std.heap.wasm_allocator;
pub const std_options: std.Options = .{
    .logFn = logger.std_options_impl.logFn,
    .log_level = .debug,
};
pub const panic = wasm_print.panic;
comptime {
    const jsalloc = @import("wasm_jsalloc.zig");
    std.mem.doNotOptimizeAway(jsalloc.WasmAlloc);
    std.mem.doNotOptimizeAway(jsalloc.WasmFree);
    std.mem.doNotOptimizeAway(jsalloc.WasmFreeAll);
    std.mem.doNotOptimizeAway(jsalloc.WasmListAllocs);
}
fn a() !void {
    for (0..100) |i| {
        //for (0..std.math.maxInt(usize) / 2048) |_|
        //    asm volatile ("nop");
        switch (@as(wasm_print.PrintType, @enumFromInt(i % 3))) {
            .log => std.log.debug("Sentence #{}\n", .{i + 1}),
            .warn => std.log.warn("Sentence #{}\n", .{i + 1}),
            .err => std.log.err("Sentence #{}\n", .{i + 1}),
        }
    }
    std.log.info("E" ** 8192, .{}); //Intentional message to fill buffer too quickly.
    return error.ErrorMessage;
}
pub export fn Hello() u32 {
    a() catch |e| wasm_print.WasmError(e);
    return 69;
}
