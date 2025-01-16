const std = @import("std");
fn EnumsToJSClass(EnumClass: anytype, export_name: []const u8) []const u8 {
    if (@typeInfo(EnumClass) != .Enum) @compileError(@typeName(EnumClass) ++ " must be an enum type.");
    var export_str: []const u8 = &.{};
    export_str = export_str ++ std.fmt.comptimePrint("//Exported Zig enums '{s}' to javascript variable name '{s}'\n", .{ @typeName(EnumClass), export_name });
    export_str = export_str ++ "export class " ++ export_name ++ " {\n";
    const fields = std.meta.fields(EnumClass);
    for (fields) |field|
        export_str = export_str ++ std.fmt.comptimePrint("\tstatic get {s}() {{ return {}; }}\n", .{ field.name, field.value });
    export_str = export_str ++ std.fmt.comptimePrint("\tstatic get $$length() {{ return {}; }}\n", .{fields.len});
    export_str = export_str ++ "\tstatic get $$names() { return Array.from([";
    for (fields) |field|
        export_str = export_str ++ std.fmt.comptimePrint(" \"{s}\",", .{field.name});
    export_str = export_str ++ " ]); }\n";
    for (@typeInfo(EnumClass).Enum.decls) |decl| { //Get string descriptions of enums.
        const DeclType = @TypeOf(@field(EnumClass, decl.name));
        if (@typeInfo(DeclType) == .Fn) {
            const FnInfo = @typeInfo(DeclType).Fn;
            if (FnInfo.return_type == []const u8 and FnInfo.params.len == 1 and FnInfo.params[0].type == EnumClass) {
                export_str = export_str ++ "\tstatic get $" ++ decl.name ++ "() { return Array.from([";
                for (fields) |field|
                    export_str = export_str ++ std.fmt.comptimePrint(" \"{s}\",", .{@field(EnumClass, decl.name)(@enumFromInt(field.value))});
                export_str = export_str ++ " ]); }\n";
            }
        }
    }
    export_str = export_str ++ "};\n\n";
    return export_str;
}
const shared_enums = @import("src/shared_enums.zig");
const write_export_enums_str: []const u8 = v: {
    var str: []const u8 = "//This is auto-generated from the build.zig file to use for wasm-javascript reading\n\n";
    for (std.meta.declarations(shared_enums)) |decl| {
        str = str ++ EnumsToJSClass(@field(shared_enums, decl.name), decl.name);
    }
    break :v str;
};
const www_root = "www";
const wasm_name = "todo";
const wasm_enums_name = "wasm_enums";
pub fn build(b: *std.Build) !void {
    //const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const install_website = b.addInstallDirectory(.{
        .source_dir = b.path(www_root),
        .install_dir = .bin,
        .install_subdir = www_root,
    });
    const install_website_run_step = b.step("website", "Copies website files to bin");
    install_website.step.dependOn(b.getUninstallStep());
    b.getInstallStep().dependOn(&install_website.step);
    install_website_run_step.dependOn(&install_website.step);

    const wasm_exe = b.addExecutable(.{
        .name = wasm_name,
        .root_source_file = b.path("src/wasm_main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(&.{ .atomics, .bulk_memory }),
        }),
        .optimize = optimize,
    });
    wasm_exe.import_memory = true;
    wasm_exe.initial_memory = 65536 * 20;
    wasm_exe.max_memory = 65536 * 100;
    wasm_exe.shared_memory = true;
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;

    wasm_exe.root_module.export_symbol_names = &.{
        "Hello",
        "WasmListAllocs",
        "WasmAlloc",
        "WasmFree",
        "WasmFreeAll",
        "PrintBufferMax",
        "PrintBufferLock",
        "PrintBuffer",
        "PrintBufferLen",
        "PrintBufferStatus",
    };

    const install_wasm = b.addInstallArtifact(wasm_exe, .{
        .dest_sub_path = std.fmt.comptimePrint("{s}/{s}.wasm", .{ www_root, wasm_name }),
    });
    const wasm_step = b.step("wasm", "Build wasm binaries and copies files to bin.");
    wasm_step.dependOn(&install_wasm.step);
    install_wasm.step.dependOn(&install_website.step);

    const run_website_step = b.step("server", "Initializes the wasm step, and runs python http.server");
    const python_http = b.addSystemCommand(&.{ "python", "test_website.py" });
    run_website_step.dependOn(&python_http.step);

    const write_export_enums = b.addWriteFile(
        std.fmt.comptimePrint("{s}.js", .{wasm_enums_name}),
        write_export_enums_str,
    );
    write_export_enums.step.dependOn(&install_website.step);
    const add_export_enums = b.addInstallDirectory(.{
        .source_dir = write_export_enums.getDirectory(),
        .install_dir = .bin,
        .install_subdir = www_root,
    });
    install_wasm.step.dependOn(&add_export_enums.step);
    add_export_enums.step.dependOn(&write_export_enums.step);
}
