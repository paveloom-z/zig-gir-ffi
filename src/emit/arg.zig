const std = @import("std");

const gir = @import("girepository");

const mod = @import("mod.zig");
const Repository = mod.Repository;
const Type = mod.Type;

pub const Arg = struct {
    const Self = @This();
    name: [:0]const u8,
    @"type": Type,
    pub fn from(
        repository: *const Repository,
        arg_info: ?*gir.GIArgInfo,
        maybe_parent_name: ?[:0]const u8,
        dependencies: *std.StringHashMap(void),
    ) !Arg {
        const name = std.mem.sliceTo(gir.g_base_info_get_name(arg_info), 0);
        const type_info = gir.g_arg_info_get_type(arg_info);
        defer gir.g_base_info_unref(type_info);
        const @"type" = try Type.from(
            repository,
            type_info,
            maybe_parent_name,
            dependencies,
        );
        return Arg{
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
            "{s}: {s}",
            .{
                self.name,
                self.type.name,
            },
        );
    }
};
