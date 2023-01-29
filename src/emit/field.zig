const std = @import("std");

const gir = @import("girepository");

const emit = @import("mod.zig");

pub const Field = struct {
    const Self = @This();
    name: [:0]const u8,
    type: emit.@"type".Type,
    pub fn toString(
        self: *const Self,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        return try std.fmt.allocPrint(
            allocator,
            "    {s}: {s},\n",
            .{
                self.name,
                self.type.name,
            },
        );
    }
};

/// Parse a field
pub fn from(
    field: ?*gir.GIFieldInfo,
    maybe_self_name: ?[:0]const u8,
    dependencies: *std.StringHashMap(void),
    target_namespace_name: []const u8,
    allocator: std.mem.Allocator,
) !Field {
    const name = std.mem.sliceTo(gir.g_base_info_get_name(field), 0);
    const type_info = gir.g_field_info_get_type(field);
    defer gir.g_base_info_unref(type_info);
    const @"type" = try emit.@"type".from(
        type_info,
        maybe_self_name,
        dependencies,
        target_namespace_name,
        allocator,
    );
    return Field{
        .name = name,
        .type = @"type",
    };
}
