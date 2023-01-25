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
    const docstring_slice = emit.sliceFrom(docstring);
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
    // Store fields
    const Field = struct {
        name: [:0]const u8,
        type: struct {
            name: [:0]const u8,
            is_pointer: bool,
        },
    };
    const fields_n = gir.g_object_info_get_n_fields(object);
    const fields = try allocator.alloc(Field, @intCast(usize, fields_n));
    {
        var i: usize = 0;
        while (i < fields_n) : (i += 1) {
            const field = gir.g_object_info_get_field(
                info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(field);
            const field_name_test = gir.g_base_info_get_name(field);
            const field_name = std.mem.span(@ptrCast([*:0]const u8, field_name_test));
            const field_type = gir.g_field_info_get_type(field);
            defer gir.g_base_info_unref(field_type);
            const field_type_is_pointer = gir.g_type_info_is_pointer(field_type) != 0;
            const field_type_tag = gir.g_type_info_get_tag(field_type);
            const field_type_slice = switch (field_type_tag) {
                gir.GI_TYPE_TAG_VOID => "void",
                gir.GI_TYPE_TAG_BOOLEAN => "bool",
                gir.GI_TYPE_TAG_INT8 => "i8",
                gir.GI_TYPE_TAG_UINT8 => "u8",
                gir.GI_TYPE_TAG_INT16 => "i16",
                gir.GI_TYPE_TAG_UINT16 => "u16",
                gir.GI_TYPE_TAG_INT32 => "i32",
                gir.GI_TYPE_TAG_UINT32 => "u32",
                gir.GI_TYPE_TAG_INT64 => "i64",
                gir.GI_TYPE_TAG_UINT64 => "u64",
                gir.GI_TYPE_TAG_FLOAT => "f32",
                gir.GI_TYPE_TAG_DOUBLE => "f64",
                gir.GI_TYPE_TAG_GTYPE => "GTYPE",
                gir.GI_TYPE_TAG_UTF8 => "UTF8",
                gir.GI_TYPE_TAG_FILENAME => "FILENAME",
                gir.GI_TYPE_TAG_ARRAY => "ARRAY",
                gir.GI_TYPE_TAG_INTERFACE => out: {
                    const interface = gir.g_type_info_get_interface(field_type);
                    defer gir.g_base_info_unref(interface);
                    const interface_name = emit.sliceFrom(
                        gir.g_base_info_get_name(interface),
                    );
                    const interface_namespace_name = emit.sliceFrom(
                        gir.g_base_info_get_namespace(interface),
                    );
                    const interface_string = in: {
                        if (std.mem.eql(
                            u8,
                            interface_namespace_name,
                            main.target_namespace_name,
                        )) {
                            _ = try dependencies.getOrPut(interface_name);
                            break :in interface_name;
                        } else {
                            break :in try std.mem.concatWithSentinel(
                                allocator,
                                u8,
                                &.{ "c.G", interface_name },
                                0,
                            );
                        }
                    };
                    break :out interface_string;
                },
                gir.GI_TYPE_TAG_GLIST => "GLIST",
                gir.GI_TYPE_TAG_GSLIST => "GSLIST",
                gir.GI_TYPE_TAG_GHASH => "GHASH",
                gir.GI_TYPE_TAG_ERROR => "ERROR",
                gir.GI_TYPE_TAG_UNICHAR => "UNICHAR",
                else => {
                    std.log.warn(
                        "No handle for type tag {}.",
                        .{field_type_tag},
                    );
                    return error.Error;
                },
            };
            fields[i] = Field{
                .name = field_name,
                .type = .{
                    .name = field_type_slice,
                    .is_pointer = field_type_is_pointer,
                },
            };
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
