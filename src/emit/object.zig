const std = @import("std");

const gir = @import("girepository");

const c = gir.c;

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
    info: *c.GIBaseInfo,
    info_name: [:0]const u8,
    subdir: *std.fs.Dir,
    allocator: std.mem.Allocator,
) ![:0]const u8 {
    const object = @ptrCast(*c.GIObjectInfo, info);
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
    // Prepare a hashset for dependencies
    var dependencies = std.StringHashMap(void).init(allocator);
    // Prepare a buffered writer
    var buffered_writer = std.io.bufferedWriter(file.writer());
    const writer = buffered_writer.writer();
    defer buffered_writer.flush() catch {
        std.log.warn(
            "Couldn't flush the writer for the `{s}` file.",
            .{file_path},
        );
    };
    // For each index of a constant
    {
        const n = c.g_object_info_get_n_constants(object);
        var i: c.gint = 0;
        while (i < n) : (i += 1) {
            // Get the constant
            const constant = c.g_object_info_get_constant(info, i);
            defer c.g_base_info_unref(constant);
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
    const fields_n = c.g_object_info_get_n_fields(object);
    const fields = try allocator.alloc(Field, @intCast(usize, fields_n));
    {
        var i: usize = 0;
        while (i < fields_n) : (i += 1) {
            const field = c.g_object_info_get_field(
                info,
                @intCast(c.gint, i),
            );
            defer c.g_base_info_unref(field);
            const field_name_test = c.g_base_info_get_name(field);
            const field_name = std.mem.span(@ptrCast([*:0]const u8, field_name_test));
            const field_type = c.g_field_info_get_type(field);
            defer c.g_base_info_unref(field_type);
            const field_type_is_pointer = c.g_type_info_is_pointer(field_type) != 0;
            const field_type_tag = c.g_type_info_get_tag(field_type);
            const field_type_slice = switch (field_type_tag) {
                c.GI_TYPE_TAG_VOID => "void",
                c.GI_TYPE_TAG_BOOLEAN => "bool",
                c.GI_TYPE_TAG_INT8 => "i8",
                c.GI_TYPE_TAG_UINT8 => "u8",
                c.GI_TYPE_TAG_INT16 => "i16",
                c.GI_TYPE_TAG_UINT16 => "u16",
                c.GI_TYPE_TAG_INT32 => "i32",
                c.GI_TYPE_TAG_UINT32 => "u32",
                c.GI_TYPE_TAG_INT64 => "i64",
                c.GI_TYPE_TAG_UINT64 => "u64",
                c.GI_TYPE_TAG_FLOAT => "f32",
                c.GI_TYPE_TAG_DOUBLE => "f64",
                c.GI_TYPE_TAG_GTYPE => "GTYPE",
                c.GI_TYPE_TAG_UTF8 => "UTF8",
                c.GI_TYPE_TAG_FILENAME => "FILENAME",
                c.GI_TYPE_TAG_ARRAY => "ARRAY",
                c.GI_TYPE_TAG_INTERFACE => out: {
                    const interface = c.g_type_info_get_interface(field_type);
                    defer c.g_base_info_unref(interface);
                    const interface_name = emit.sliceFrom(
                        c.g_base_info_get_name(interface),
                    );
                    const interface_namespace_name = emit.sliceFrom(
                        c.g_base_info_get_namespace(interface),
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
                c.GI_TYPE_TAG_GLIST => "GLIST",
                c.GI_TYPE_TAG_GSLIST => "GSLIST",
                c.GI_TYPE_TAG_GHASH => "GHASH",
                c.GI_TYPE_TAG_ERROR => "ERROR",
                c.GI_TYPE_TAG_UNICHAR => "UNICHAR",
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
    try writer.print("\npub const {s} = extern struct {{\n", .{info_name});
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
