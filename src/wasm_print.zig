//!Overrides logFn and panic to log output to JavaScript.
const std = @import("std");
const shared_enums = @import("shared_enums.zig");
const wasm_asm = @import("wasm_asm.zig");
pub const PrintType = shared_enums.PrintType;
pub const PBLock = shared_enums.PBLock;
pub const PBStatus = shared_enums.PBStatus;
//Print panic non-asynchronously
pub extern fn JSPanic(buf_addr: [*c]const u8, usize) void;
pub fn panic(mesg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var ebi: usize = 0;
    var error_buffer: [512]u8 = undefined;
    for ("A wasm module has panicked. Panic message:\n'") |ch| {
        error_buffer[ebi] = ch;
        ebi += 1;
    }
    for (0..mesg.len) |i| {
        error_buffer[ebi] = mesg[i];
        ebi += 1;
    }
    for ("'\n") |ch| {
        error_buffer[ebi] = ch;
        ebi += 1;
    }
    print_before_trap();
    JSPanic(&error_buffer, ebi);
    @trap();
}
///Used because if @trap is called, printer_worker.js would not print/empty the buffer sometimes.
fn print_before_trap() void {
    var exit_early: usize = 0;
    while (@atomicRmw(PBLock, &PrintBufferLock, .Xchg, .locked, .acq_rel) == .locked) : (exit_early += 1) {
        if (exit_early == 1000000) return;
    }
    PrintBufferLock = .unlocked;
    _ = wasm_asm.atomic_notify32(PBLock, &PrintBufferLock, -1);
    while (@atomicLoad(PBStatus, &PrintBufferStatus, .acquire) != .empty) : (exit_early += 1) {
        _ = wasm_asm.atomic_notify32(PBStatus, &PrintBufferStatus, -1);
        if (exit_early == 1000000) return;
    }
}
export fn PrintBufferMax() usize {
    return 8192;
}
const PrintBufferT = [PrintBufferMax()]u8;
var wasm_printer = WasmPrinter.init();
pub export var PrintBufferLock: PBLock = .unlocked;
pub export var PrintBufferStatus: PBStatus = .empty;
//To export the buffer and length used
pub export var PrintBuffer: [*c]const u8 = &wasm_printer.buf;
pub export var PrintBufferLen: [*c]const usize = &wasm_printer.pos;
///Assuming buf is encoded properly using the comment from `std_options.logFn`
pub const std_options = struct {
    pub const log_level = .debug;
    /// Encodes string as {num_messages (1-byte), X0, X1, ..., Xnum_messages}
    ///
    /// Xn as {print_type (1-byte), message, '\0'}
    /// '\0' is internally used for printer_worker.js to signal the end of a message.
    pub fn logFn(
        comptime l: std.log.Level,
        comptime _: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = wasm_asm.atomic_wait32(PBStatus, &PrintBufferStatus, .needs_empty, -1);
        _ = wasm_asm.atomic_wait32(PBStatus, &PrintBufferStatus, .full, -1);
        //Just busy loop until js is done
        while (@atomicRmw(PBLock, &PrintBufferLock, .Xchg, .locked, .acq_rel) == .locked) {}
        if (PrintBufferStatus == .empty)
            wasm_printer.reset();
        const pt: PrintType = switch (l) {
            .debug, .info => .log,
            .warn => .warn,
            .err => .err,
        };
        if (wasm_printer.pos == wasm_printer.buf.len) {
            signal_wp_too_full();
            return;
        }
        while (true) {
            wasm_printer.buf[wasm_printer.pos] = @intCast(@intFromEnum(pt));
            wasm_printer.pos += 1;
            if (std.fmt.format(wasm_printer.writer(), format, args)) {
                wasm_printer.buf[wasm_printer.pos] = 0;
                wasm_printer.pos += 1;
                wasm_printer.buf[0] += 1;
                break;
            } else |err| {
                if (err == error.TooFull) {
                    wasm_printer.buf[0] += 1;
                    signal_wp_too_full();
                    return;
                }
            }
        }
        if (wasm_printer.pos != wasm_printer.buf.len) {
            PrintBufferStatus = if (wasm_printer.buf[0] != 255) .filled else .needs_empty;
        } else PrintBufferStatus = .full;
        _ = wasm_asm.atomic_notify32(PBStatus, &PrintBufferStatus, -1);
        PrintBufferLock = .unlocked;
        _ = wasm_asm.atomic_notify32(PBLock, &PrintBufferLock, -1);
    }
    fn signal_wp_too_full() void {
        PrintBufferStatus = .full;
        _ = wasm_asm.atomic_notify32(PBStatus, &PrintBufferStatus, -1);
        PrintBufferLock = .unlocked;
        _ = wasm_asm.atomic_notify32(PBLock, &PrintBufferLock, -1);
    }
};
const WasmPrinter = struct {
    const WriteError = error{TooFull};
    const Writer = std.io.Writer(*WasmPrinter, WasmPrinter.WriteError, WasmPrinter.write);
    pos: usize = 1,
    buf: PrintBufferT = undefined,
    fn init() WasmPrinter {
        var wp: WasmPrinter = .{};
        wp.buf[0] = 0; //0th byte represents the number of messages to be added to js console print.
        return wp;
    }
    /// Copied from std std.io.BufferedWriter.
    fn write(self: *@This(), bytes: []const u8) WriteError!usize {
        if (self.pos + bytes.len <= self.buf.len - 1) { //Too many messages fill up the buffer.
            @memcpy(self.buf[self.pos..(self.pos + bytes.len)], bytes);
            self.pos += bytes.len;
            return bytes.len;
        } else {
            @memcpy(self.buf[self.pos..], bytes[0 .. self.buf.len - self.pos]);
            self.buf[self.buf.len - 1] = 0; //Null-terminate last character.
            self.pos = self.buf.len;
            return WriteError.TooFull;
        }
    }
    fn reset(self: *@This()) void {
        self.pos = 1;
        self.buf[0] = 0;
    }
    fn writer(self: *@This()) Writer {
        return .{ .context = self };
    }
};
pub fn WasmError(err: anyerror) noreturn {
    var ebi: usize = 0;
    var error_buffer: [512]u8 = undefined;
    for ("A Wasm module has an uncaught error:\n'") |ch| {
        error_buffer[ebi] = ch;
        ebi += 1;
    }
    for (0..@errorName(err).len) |i| {
        error_buffer[ebi] = @errorName(err)[i];
        ebi += 1;
    }
    for ("'\n") |ch| {
        error_buffer[ebi] = ch;
        ebi += 1;
    }
    print_before_trap();
    JSPanic(&error_buffer, ebi);
    @trap();
}
