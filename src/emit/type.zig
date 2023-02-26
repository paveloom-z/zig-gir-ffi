const std = @import("std");

const gir = @import("girepository");

pub const Type = struct {
    const Self = @This();
    name: [:0]const u8,
    is_void: bool,
    pub fn from(
        type_info: *gir.GITypeInfo,
        maybe_parent_name: ?[:0]const u8,
        dependencies: *std.StringHashMap(void),
        target_namespace_name: []const u8,
        allocator: std.mem.Allocator,
    ) !Self {
        const is_pointer = gir.g_type_info_is_pointer(type_info) != 0;
        const tag = gir.g_type_info_get_tag(type_info);
        const name = switch (tag) {
            gir.GI_TYPE_TAG_VOID => "void",
            gir.GI_TYPE_TAG_BOOLEAN => "bool",
            gir.GI_TYPE_TAG_INT8 => switch (is_pointer) {
                true => "?*i8",
                false => "i8",
            },
            gir.GI_TYPE_TAG_UINT8 => switch (is_pointer) {
                true => "?*u8",
                false => "u8",
            },
            gir.GI_TYPE_TAG_INT16 => switch (is_pointer) {
                true => "?*i16",
                false => "i16",
            },
            gir.GI_TYPE_TAG_UINT16 => switch (is_pointer) {
                true => "?*u16",
                false => "u16",
            },
            gir.GI_TYPE_TAG_INT32 => switch (is_pointer) {
                true => "?*i32",
                false => "i32",
            },
            gir.GI_TYPE_TAG_UINT32 => switch (is_pointer) {
                true => "?*u32",
                false => "u32",
            },
            gir.GI_TYPE_TAG_INT64 => switch (is_pointer) {
                true => "?*i64",
                false => "i64",
            },
            gir.GI_TYPE_TAG_UINT64 => switch (is_pointer) {
                true => "?*u64",
                false => "u64",
            },
            gir.GI_TYPE_TAG_FLOAT => switch (is_pointer) {
                true => "?*f32",
                false => "f32",
            },
            gir.GI_TYPE_TAG_DOUBLE => switch (is_pointer) {
                true => "?*f64",
                false => "f64",
            },
            gir.GI_TYPE_TAG_GTYPE => switch (is_pointer) {
                true => "?*c.GType",
                false => "c.GType",
            },
            gir.GI_TYPE_TAG_UTF8 => "?[*:0]const u8",
            gir.GI_TYPE_TAG_FILENAME => "?[*:0]const u8",
            gir.GI_TYPE_TAG_ARRAY => out: {
                const array_type = gir.g_type_info_get_array_type(type_info);
                switch (array_type) {
                    gir.GI_ARRAY_TYPE_C => {
                        const param_type_info = gir.g_type_info_get_param_type(type_info, 0);
                        defer gir.g_base_info_unref(param_type_info);
                        const param_type = try from(
                            param_type_info,
                            maybe_parent_name,
                            dependencies,
                            target_namespace_name,
                            allocator,
                        );
                        break :out try std.mem.concatWithSentinel(
                            allocator,
                            u8,
                            &.{ "?[*]", param_type.name },
                            0,
                        );
                    },
                    gir.GI_ARRAY_TYPE_ARRAY => switch (is_pointer) {
                        true => break :out "?*c.GArray",
                        false => break :out "c.GArray",
                    },
                    gir.GI_ARRAY_TYPE_PTR_ARRAY => switch (is_pointer) {
                        true => break :out "?*c.GPtrArray",
                        false => break :out "c.GPtrArray",
                    },
                    gir.GI_ARRAY_TYPE_BYTE_ARRAY => switch (is_pointer) {
                        true => break :out "?*c.GByteArray",
                        false => break :out "c.GByteArray",
                    },
                    else => {
                        std.log.warn(
                            "No handle for the array type of {}.",
                            .{tag},
                        );
                        return error.Error;
                    },
                }
            },
            gir.GI_TYPE_TAG_INTERFACE => out: {
                const interface = gir.g_type_info_get_interface(type_info);
                defer gir.g_base_info_unref(interface);
                const interface_name = std.mem.sliceTo(
                    gir.g_base_info_get_name(interface),
                    0,
                );
                const interface_namespace_name = std.mem.sliceTo(
                    gir.g_base_info_get_namespace(interface),
                    0,
                );
                const is_self = is_self: {
                    if (maybe_parent_name) |parent_name| {
                        break :is_self std.mem.eql(
                            u8,
                            interface_name,
                            parent_name,
                        );
                    } else {
                        break :is_self false;
                    }
                };
                if (is_self) switch (is_pointer) {
                    true => break :out "?*Self",
                    false => break :out "Self",
                };
                const same_namespace = std.mem.eql(
                    u8,
                    interface_namespace_name,
                    target_namespace_name,
                );
                if (same_namespace) {
                    _ = try dependencies.getOrPut(interface_name);
                    switch (is_pointer) {
                        true => break :out try std.mem.concatWithSentinel(
                            allocator,
                            u8,
                            &.{ "?*", interface_name },
                            0,
                        ),
                        false => break :out interface_name,
                    }
                } else {
                    switch (is_pointer) {
                        true => break :out try std.mem.concatWithSentinel(
                            allocator,
                            u8,
                            &.{ "?*c.G", interface_name },
                            0,
                        ),
                        false => break :out try std.mem.concatWithSentinel(
                            allocator,
                            u8,
                            &.{ "c.G", interface_name },
                            0,
                        ),
                    }
                }
            },
            gir.GI_TYPE_TAG_GLIST => switch (is_pointer) {
                true => "?*c.GList",
                false => "c.GList",
            },
            gir.GI_TYPE_TAG_GSLIST => switch (is_pointer) {
                true => "?*c.GSList",
                false => "c.GSList",
            },
            gir.GI_TYPE_TAG_GHASH => switch (is_pointer) {
                true => "?*c.GHashTable",
                false => "c.GHashTable",
            },
            gir.GI_TYPE_TAG_ERROR => switch (is_pointer) {
                true => "?*c.GError",
                false => "c.GError",
            },
            gir.GI_TYPE_TAG_UNICHAR => "UNICHAR",
            else => {
                std.log.warn(
                    "No handle for type tag {}.",
                    .{tag},
                );
                return error.Error;
            },
        };
        const is_void = std.mem.eql(u8, name, "void");
        return Self{
            .name = name,
            .is_void = is_void,
        };
    }
};
