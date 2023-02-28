const std = @import("std");

const gir = @import("girepository");

const mod = @import("mod.zig");
const Dependencies = mod.Dependencies;
const Repository = mod.Repository;

const Tag = enum(c_uint) {
    const Self = @This();
    void_t = gir.GI_TYPE_TAG_VOID,
    bool_t = gir.GI_TYPE_TAG_BOOLEAN,
    i8_t = gir.GI_TYPE_TAG_INT8,
    u8_t = gir.GI_TYPE_TAG_UINT8,
    i16_t = gir.GI_TYPE_TAG_INT16,
    u16_t = gir.GI_TYPE_TAG_UINT16,
    i32_t = gir.GI_TYPE_TAG_INT32,
    u32_t = gir.GI_TYPE_TAG_UINT32,
    i64_t = gir.GI_TYPE_TAG_INT64,
    u64_t = gir.GI_TYPE_TAG_UINT64,
    f32_t = gir.GI_TYPE_TAG_FLOAT,
    f64_t = gir.GI_TYPE_TAG_DOUBLE,
    gtype_t = gir.GI_TYPE_TAG_GTYPE,
    utf_8 = gir.GI_TYPE_TAG_UTF8,
    filename_t = gir.GI_TYPE_TAG_FILENAME,
    array_t = gir.GI_TYPE_TAG_ARRAY,
    interface_t = gir.GI_TYPE_TAG_INTERFACE,
    glist_t = gir.GI_TYPE_TAG_GLIST,
    gslist_t = gir.GI_TYPE_TAG_GSLIST,
    ghash_t = gir.GI_TYPE_TAG_GHASH,
    error_t = gir.GI_TYPE_TAG_ERROR,
    unichar_t = gir.GI_TYPE_TAG_UNICHAR,
};

// Setting this explicitly because of
// https://github.com/ziglang/zig/issues/2971
const Error = error{
    OutOfMemory,
};

pub const Type = struct {
    const Self = @This();
    repository: *const Repository,
    info: *gir.GICallableInfo,
    maybe_parent_name: ?[:0]const u8,
    maybe_dependencies: ?*Dependencies,
    is_pointer: bool = undefined,
    tag: Tag = undefined,
    name: []const u8 = undefined,
    fn getVoidName() []const u8 {
        return "void";
    }
    fn getBoolName() []const u8 {
        return "bool";
    }
    fn getI8Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*i8",
            false => "i8",
        };
    }
    fn getU8Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*i8",
            false => "i8",
        };
    }
    fn getI16Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*i16",
            false => "i16",
        };
    }
    fn getU16Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*i16",
            false => "i16",
        };
    }
    fn getI32Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*i32",
            false => "i32",
        };
    }
    fn getU32Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*i32",
            false => "i32",
        };
    }
    fn getI64Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*i64",
            false => "i64",
        };
    }
    fn getU64Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*i64",
            false => "i64",
        };
    }
    fn getF32Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*f32",
            false => "f32",
        };
    }
    fn getF64Name(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*f64",
            false => "f64",
        };
    }
    fn getGTypeName(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*c.GType",
            false => "c.GType",
        };
    }
    fn getUTF8Name() []const u8 {
        return "?[*:0]const u8";
    }
    fn getFilenameName() []const u8 {
        return "?[*:0]const u8";
    }
    fn getArrayName(self: *Self) ![]const u8 {
        const array_type = gir.g_type_info_get_array_type(self.info);
        switch (array_type) {
            gir.GI_ARRAY_TYPE_C => {
                const param_type_info = gir.g_type_info_get_param_type(self.info, 0);
                defer gir.g_base_info_unref(param_type_info);
                const param_type = try from(
                    self.repository,
                    param_type_info,
                    self.maybe_parent_name,
                    self.maybe_dependencies,
                );
                return try std.mem.concatWithSentinel(
                    self.repository.allocator,
                    u8,
                    &.{ "?[*]", param_type.name },
                    0,
                );
            },
            gir.GI_ARRAY_TYPE_ARRAY => switch (self.is_pointer) {
                true => return "?*c.GArray",
                false => return "c.GArray",
            },
            gir.GI_ARRAY_TYPE_PTR_ARRAY => switch (self.is_pointer) {
                true => return "?*c.GPtrArray",
                false => return "c.GPtrArray",
            },
            gir.GI_ARRAY_TYPE_BYTE_ARRAY => switch (self.is_pointer) {
                true => return "?*c.GByteArray",
                false => return "c.GByteArray",
            },
            else => unreachable,
        }
    }
    fn getInterfaceName(self: *Self) ![]const u8 {
        const interface = gir.g_type_info_get_interface(self.info);
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
            if (self.maybe_parent_name) |parent_name| {
                break :is_self std.mem.eql(
                    u8,
                    interface_name,
                    parent_name,
                );
            } else {
                break :is_self false;
            }
        };
        if (is_self) switch (self.is_pointer) {
            true => return "?*Self",
            false => return "Self",
        };
        const same_namespace = std.mem.eql(
            u8,
            interface_namespace_name,
            self.repository.target_namespace_name,
        );
        if (same_namespace) {
            if (self.maybe_dependencies) |dependencies| {
                _ = try dependencies.getOrPut(interface_name);
            }
            switch (self.is_pointer) {
                true => return try std.mem.concatWithSentinel(
                    self.repository.allocator,
                    u8,
                    &.{ "?*", interface_name },
                    0,
                ),
                false => return interface_name,
            }
        } else {
            switch (self.is_pointer) {
                true => return try std.mem.concatWithSentinel(
                    self.repository.allocator,
                    u8,
                    &.{ "?*c.G", interface_name },
                    0,
                ),
                false => return try std.mem.concatWithSentinel(
                    self.repository.allocator,
                    u8,
                    &.{ "c.G", interface_name },
                    0,
                ),
            }
        }
    }
    fn getGListName(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*c.GList",
            false => "c.GList",
        };
    }
    fn getGSListName(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*c.GSList",
            false => "c.GSList",
        };
    }
    fn getGHashName(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*c.GHashTable",
            false => "c.GHashTable",
        };
    }
    fn getGErrorName(self: *const Self) []const u8 {
        return switch (self.is_pointer) {
            true => "?*c.GError",
            false => "c.GError",
        };
    }
    fn getUnicharName() []const u8 {
        return "UNICHAR";
    }
    fn getName(self: *Self) !void {
        self.name = switch (self.tag) {
            .void_t => getVoidName(),
            .bool_t => getBoolName(),
            .i8_t => self.getI8Name(),
            .u8_t => self.getU8Name(),
            .i16_t => self.getI16Name(),
            .u16_t => self.getU16Name(),
            .i32_t => self.getI32Name(),
            .u32_t => self.getU32Name(),
            .i64_t => self.getI64Name(),
            .u64_t => self.getU64Name(),
            .f32_t => self.getF32Name(),
            .f64_t => self.getF64Name(),
            .gtype_t => self.getGTypeName(),
            .utf_8 => getUTF8Name(),
            .filename_t => getFilenameName(),
            .array_t => try self.getArrayName(),
            .interface_t => try self.getInterfaceName(),
            .glist_t => self.getGListName(),
            .gslist_t => self.getGSListName(),
            .ghash_t => self.getGHashName(),
            .error_t => self.getGErrorName(),
            .unichar_t => getUnicharName(),
        };
    }
    pub fn from(
        repository: *const Repository,
        type_info: *gir.GITypeInfo,
        maybe_parent_name: ?[:0]const u8,
        maybe_dependencies: ?*Dependencies,
    ) Error!Self {
        var self = Self{
            .repository = repository,
            .info = type_info,
            .maybe_parent_name = maybe_parent_name,
            .maybe_dependencies = maybe_dependencies,
        };

        self.is_pointer = gir.g_type_info_is_pointer(type_info) != 0;
        self.tag = @intToEnum(Tag, gir.g_type_info_get_tag(type_info));
        try self.getName();

        return self;
    }
};
