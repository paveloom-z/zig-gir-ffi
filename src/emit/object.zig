const std = @import("std");

const gir = @import("girepository");
const xml = @import("xml");

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

/// Get the documentation string for the object
fn getDocstring(
    info_name: [:0]const u8,
    gir_context: xml.xmlXPathContextPtr,
    allocator: std.mem.Allocator,
) !?[:0]const u8 {
    // Evaluate an XPath expression
    const expression = try std.mem.concatWithSentinel(
        allocator,
        u8,
        &.{
            "//gir:class[@name=\"",
            info_name,
            "\"]/gir:doc",
        },
        0,
    );
    const result = xml.xmlXPathEval(
        expression.ptr,
        gir_context,
    );
    if (result == null) {
        std.log.warn(
            "Couldn't evaluate the XPath expression for `{s}`",
            .{info_name},
        );
        return null;
    }
    defer xml.xmlXPathFreeObject(result);
    // Check that whether we got a match
    const nodeset = result.*.nodesetval;
    if (nodeset.*.nodeNr == 0) {
        std.log.warn(
            "The nodeset wasn't populated for {s}.",
            .{info_name},
        );
        return null;
    }
    // Get the string from the first match
    const docstring = xml.xmlXPathCastNodeToString(
        nodeset.*.nodeTab[0],
    );
    defer xml.xmlFree.?(docstring);
    // Format the string
    const docstring_slice = std.mem.sliceTo(docstring, 0);
    const docstring_formatted = try std.mem.replaceOwned(
        xml.xmlChar,
        allocator,
        docstring_slice,
        "\n",
        "\n/// ",
    );
    return try std.mem.concatWithSentinel(
        allocator,
        u8,
        &.{ "/// ", docstring_formatted },
        0,
    );
}

/// Emit an object
pub fn from(
    target_namespace_name: []const u8,
    info: *gir.GIBaseInfo,
    info_name: [:0]const u8,
    subdir: *std.fs.Dir,
    gir_context: xml.xmlXPathContextPtr,
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
    const maybe_docstring = try getDocstring(info_name, gir_context, allocator);
    if (maybe_docstring == null) {
        std.log.warn(
            "Couldn't get the documentation string for `{s}`",
            .{info_name},
        );
    }
    // For each index of a constant
    {
        const n = gir.g_object_info_get_n_constants(object);
        var i: gir.gint = 0;
        while (i < n) : (i += 1) {
            // Get the constant
            const constant = gir.g_object_info_get_constant(info, i);
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
                &dependencies,
                target_namespace_name,
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
        "\npub const {s} = extern struct {{\n",
        .{info_name},
    );
    for (fields) |field| {
        const pointer_string = if (field.type.is_pointer) "?*" else "";
        try writer.print("    {s}: {s}{s},\n", .{
            field.name,
            pointer_string,
            field.type.name,
        });
    }
    try writer.print("}};\n", .{});
    return file_path;
}
