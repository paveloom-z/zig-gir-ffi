const std = @import("std");

const gir = @import("girepository");

const mod = @import("mod.zig");
const Type = mod.Type;

pub const Field = struct {
    const Self = @This();
    name: [:0]const u8,
    type: Type,
    pub fn from(
        field_info: ?*gir.GIFieldInfo,
        maybe_parent_name: ?[:0]const u8,
        dependencies: *std.StringHashMap(void),
        target_namespace_name: []const u8,
        allocator: std.mem.Allocator,
    ) !Self {
        const name = std.mem.sliceTo(gir.g_base_info_get_name(field_info), 0);
        const type_info = gir.g_field_info_get_type(field_info);
        defer gir.g_base_info_unref(type_info);
        const @"type" = try Type.from(
            type_info,
            maybe_parent_name,
            dependencies,
            target_namespace_name,
            allocator,
        );
        return Self{
            .name = name,
            .type = @"type",
        };
    }
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
