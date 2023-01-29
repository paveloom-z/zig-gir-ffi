const std = @import("std");

const gir = @import("girepository");

const emit = @import("mod.zig");

pub const Arg = struct {
    const Self = @This();
    name: [:0]const u8,
    @"type": emit.@"type".Type,
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

/// Parse an argument
pub fn from(
    arg_info: ?*gir.GIArgInfo,
    maybe_self_name: ?[:0]const u8,
    dependencies: *std.StringHashMap(void),
    target_namespace_name: []const u8,
    allocator: std.mem.Allocator,
) !Arg {
    const name = std.mem.sliceTo(gir.g_base_info_get_name(arg_info), 0);
    const type_info = gir.g_arg_info_get_type(arg_info);
    defer gir.g_base_info_unref(type_info);
    const @"type" = try emit.@"type".from(
        type_info,
        maybe_self_name,
        dependencies,
        target_namespace_name,
        allocator,
    );
    return Arg{
        .name = name,
        .type = @"type",
    };
}
