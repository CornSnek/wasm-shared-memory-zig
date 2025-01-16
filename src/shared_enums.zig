//!This is created because there are problems referencing enums directly in some files.
pub const PrintType = enum(i32) { log, warn, err };
pub const PBLock = enum(i32) { unlocked, locked };
pub const PBStatus = enum(i32) {
    empty,
    filled,
    needs_empty,
    full,
};
