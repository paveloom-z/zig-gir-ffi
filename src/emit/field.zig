const std = @import("std");

const gir = @import("girepository");

/// A representation of a field
pub const Field = struct {
    name: [:0]const u8,
    type: struct {
        name: [:0]const u8,
        is_pointer: bool,
    },
};

/// Parse a field to a Zig struct
pub fn from(
    field: ?*gir.GIFieldInfo,
    dependencies: *std.StringHashMap(void),
    target_namespace_name: []const u8,
    allocator: std.mem.Allocator,
) !Field {
    const field_name = std.mem.sliceTo(gir.g_base_info_get_name(field), 0);
    const field_type = gir.g_field_info_get_type(field);
    defer gir.g_base_info_unref(field_type);
    const field_type_is_pointer = gir.g_type_info_is_pointer(field_type) != 0;
    const field_type_tag = gir.g_type_info_get_tag(field_type);
    const field_type_name = switch (field_type_tag) {
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
            const interface_name = std.mem.sliceTo(
                gir.g_base_info_get_name(interface),
                0,
            );
            const interface_namespace_name = std.mem.sliceTo(
                gir.g_base_info_get_namespace(interface),
                0,
            );
            const interface_string = in: {
                if (std.mem.eql(
                    u8,
                    interface_namespace_name,
                    target_namespace_name,
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
    return Field{
        .name = field_name,
        .type = .{
            .name = field_type_name,
            .is_pointer = field_type_is_pointer,
        },
    };
}
