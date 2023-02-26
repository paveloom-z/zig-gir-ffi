const std = @import("std");

const gir = @import("girepository");

const mod = @import("mod.zig");
const Repository = mod.Repository;
const Type = mod.Type;

pub const Field = struct {
    const Self = @This();
    name: [:0]const u8,
    type: Type,
    pub fn from(
        repository: *const Repository,
        field_info: ?*gir.GIFieldInfo,
        maybe_parent_name: ?[:0]const u8,
        dependencies: *std.StringHashMap(void),
    ) !Self {
        const name = std.mem.sliceTo(gir.g_base_info_get_name(field_info), 0);
        const type_info = gir.g_field_info_get_type(field_info);
        defer gir.g_base_info_unref(type_info);
        const @"type" = try Type.from(
            repository,
            type_info,
            maybe_parent_name,
            dependencies,
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
