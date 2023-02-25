const std = @import("std");

const gir = @import("girepository");

const GirFile = @import("gir.zig").GirFile;

const emit = @import("mod.zig");
const main = @import("../main.zig");

/// Subdirectory for this type
pub const subdir_path = "objects";

/// Create if not exists and open the subdirectory
pub fn getSubdir(output_dir: *std.fs.Dir) !std.fs.Dir {
    return output_dir.makeOpenPath(subdir_path, .{}) catch {
        std.log.err(
            "Couldn't create the `{s}` subdirectory.",
            .{subdir_path},
        );
        return error.Error;
    };
}

/// Emit an object
pub fn from(
    target_namespace_name: []const u8,
    info: *gir.GIBaseInfo,
    info_name: [:0]const u8,
    subdir: *std.fs.Dir,
    gir_file: *const GirFile,
    allocator: std.mem.Allocator,
) ![:0]const u8 {
    const object = @ptrCast(*gir.GIObjectInfo, info);
    std.log.info("Emitting object `{s}`...", .{info_name});
    // Create a file
    const lowercase_info_name = try std.ascii.allocLowerString(
        allocator,
        info_name,
    );
    const file_path = try std.mem.concatWithSentinel(
        allocator,
        u8,
        &.{ lowercase_info_name, ".zig" },
        0,
    );
    const file = subdir.createFile(file_path, .{}) catch {
        std.log.warn("Couldn't create the `{s}` file.", .{file_path});
        return error.Error;
    };
    defer file.close();
    // Prepare a buffered writer
    var buffered_writer = std.io.bufferedWriter(file.writer());
    const writer = buffered_writer.writer();
    defer buffered_writer.flush() catch {
        std.log.warn(
            "Couldn't flush the writer for the `{s}` file.",
            .{file_path},
        );
    };
    // Prepare a hashset for dependencies
    var dependencies = std.StringHashMap(void).init(allocator);
    // Get the documentation string
    const expressions = &.{
        try std.mem.concatWithSentinel(allocator, u8, &.{
            "//core:class[@name=\"",
            info_name,
            "\"]/core:doc",
        }, 0),
    };
    const maybe_docstring = try gir_file.getDocstring(
        info_name,
        expressions,
        false,
    );
    if (maybe_docstring == null) {
        std.log.warn(
            "Couldn't get the documentation string for `{s}`.",
            .{info_name},
        );
    }
    // Parse constants
    const constants_n = gir.g_object_info_get_n_constants(object);
    {
        var i: usize = 0;
        while (i < constants_n) : (i += 1) {
            const constant = gir.g_object_info_get_constant(
                info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(constant);
            std.log.warn("TODO: Object Constants", .{});
        }
    }
    // Parse fields
    const fields_n = gir.g_object_info_get_n_fields(object);
    const fields = try allocator.alloc(
        emit.field.Field,
        @intCast(usize, fields_n),
    );
    {
        var i: usize = 0;
        while (i < fields_n) : (i += 1) {
            const field = gir.g_object_info_get_field(
                info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(field);
            fields[i] = try emit.field.from(
                field,
                info_name,
                &dependencies,
                target_namespace_name,
                allocator,
            );
        }
    }
    // Parse interfaces
    const interfaces_n = gir.g_object_info_get_n_interfaces(object);
    {
        var i: usize = 0;
        while (i < interfaces_n) : (i += 1) {
            const interface = gir.g_object_info_get_interface(
                info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(interface);
            std.log.warn("TODO: Object Interfaces", .{});
        }
    }
    // Parse methods
    const methods_n = gir.g_object_info_get_n_methods(object);
    const methods = try allocator.alloc(
        emit.callable.Callable,
        @intCast(usize, methods_n),
    );
    {
        var i: usize = 0;
        while (i < methods_n) : (i += 1) {
            const method = gir.g_object_info_get_method(
                info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(method);
            methods[i] = try emit.callable.from(
                method,
                &dependencies,
                info_name,
                target_namespace_name,
                gir_file,
                allocator,
            );
        }
    }
    // Print the results
    try writer.print(
        \\const lib = @import("../lib.zig");
        \\
        \\const c = lib.c;
        \\
        \\
    ,
        .{},
    );
    var dependencies_iterator = dependencies.keyIterator();
    while (dependencies_iterator.next()) |dependency| {
        try writer.print("const {0s} = lib.{0s};\n", .{dependency.*});
    }
    if (maybe_docstring) |docstring| {
        try writer.print("\n{s}", .{docstring});
    }
    try writer.print(
        \\
        \\pub const {s} = extern struct {{
        \\    const Self = @This();
        \\
    ,
        .{info_name},
    );
    for (fields) |field| {
        const string = try field.toString(allocator);
        try writer.print("{s}", .{string});
    }
    for (methods) |method| {
        const string = try method.toString(allocator);
        try writer.print("{s}", .{string});
    }
    try writer.print("}};\n", .{});
    return file_path;
}
