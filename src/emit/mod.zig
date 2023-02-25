const std = @import("std");

const gir = @import("girepository");
const xml = @import("xml");

const GirFile = @import("gir.zig").GirFile;

pub const arg = @import("arg.zig");
pub const @"type" = @import("type.zig");
pub const callable = @import("callable.zig");
pub const field = @import("field.zig");
pub const object = @import("object.zig");
pub const utils = @import("utils.zig");

/// The indentation padding
pub const pad = " " ** 4;

pub const EmitRequest = struct {
    const Self = @This();
    repository: *gir.GIRepository,
    target_namespace_name: []const u8,
    output_dir: *std.fs.Dir,
    allocator: std.mem.Allocator,
    fn loadTargetNamespace(self: *const Self) void {
        // Prepare a shared error handle
        var g_err: ?*gir.GError = null;
        // Load the namespace
        _ = gir.g_irepository_require(
            self.repository,
            self.target_namespace_name.ptr,
            null,
            0,
            &g_err,
        );
        if (g_err) |_| {
            std.log.err(
                "Couldn't load the namespace `{s}`.",
                .{self.target_namespace_name},
            );
            std.os.exit(1);
        }
    }
    fn getTargetNamespaceVersion(self: *const Self) []const u8 {
        return std.mem.sliceTo(gir.g_irepository_get_version(
            self.repository,
            self.target_namespace_name.ptr,
        ), 0);
    }
    pub fn emit(self: *const Self) !void {
        self.loadTargetNamespace();
        var gir_file = try GirFile.load(
            self.target_namespace_name,
            self.getTargetNamespaceVersion(),
            self.allocator,
        );
        defer gir_file.free();

        // Prepare output directories
        var object_subdir = try object.getSubdir(self.output_dir);
        defer object_subdir.close();
        // Prepare array lists for dependencies
        var objects_file_paths = std.ArrayList([]const u8).init(self.allocator);
        // For each index of a metadata entry
        const infos_n = gir.g_irepository_get_n_infos(
            self.repository,
            self.target_namespace_name.ptr,
        );
        var i: gir.gint = 0;
        while (i < infos_n) : (i += 1) {
            // Get the metadata entry
            const info = gir.g_irepository_get_info(
                self.repository,
                self.target_namespace_name.ptr,
                i,
            );
            defer gir.g_base_info_unref(info);
            // Depending on the type of the entry, emit the code
            const info_name = std.mem.sliceTo(gir.g_base_info_get_name(info), 0);
            const info_type = gir.g_base_info_get_type(info);
            switch (info_type) {
                gir.GI_INFO_TYPE_INVALID => {
                    std.log.warn(
                        "Invalid type `{s}`.",
                        .{info_name},
                    );
                },
                gir.GI_INFO_TYPE_FUNCTION => {
                    std.log.info(
                        "Function `{s}`",
                        .{info_name},
                    );
                },
                gir.GI_INFO_TYPE_STRUCT => {
                    std.log.info(
                        "Struct `{s}`",
                        .{info_name},
                    );
                },
                gir.GI_INFO_TYPE_ENUM => {
                    std.log.info(
                        "Enum `{s}`",
                        .{info_name},
                    );
                },
                gir.GI_INFO_TYPE_FLAGS => {
                    std.log.info(
                        "Flags `{s}`",
                        .{info_name},
                    );
                },
                gir.GI_INFO_TYPE_OBJECT => {
                    const object_file_path = object.from(
                        self.target_namespace_name,
                        info,
                        info_name,
                        &object_subdir,
                        &gir_file,
                        self.allocator,
                    ) catch {
                        std.log.warn(
                            "Couldn't emit object `{s}`.",
                            .{info_name},
                        );
                        continue;
                    };
                    try objects_file_paths.append(object_file_path);
                },
                gir.GI_INFO_TYPE_CONSTANT => {
                    std.log.info(
                        "Constant `{s}`",
                        .{info_name},
                    );
                },
                gir.GI_INFO_TYPE_UNION => {
                    std.log.info(
                        "Union `{s}`",
                        .{info_name},
                    );
                },
                gir.GI_INFO_TYPE_UNRESOLVED => {
                    std.log.warn(
                        "Unresolved type `{s}`.",
                        .{info_name},
                    );
                },
                else => {
                    std.log.warn(
                        "No handler for type `{s}`.",
                        .{info_name},
                    );
                },
            }
        }
        // Create extra files to glue things together
        var lib_file = self.output_dir.createFile("lib.zig", .{}) catch {
            std.log.warn("Couldn't create the `lib.zig` file.", .{});
            return error.Error;
        };
        defer lib_file.close();
        var lib_file_writer = lib_file.writer();
        try lib_file_writer.print(
            \\pub usingnamespace @import("c.zig");
            \\
            \\pub usingnamespace @import("objects/mod.zig");
            \\
        ,
            .{},
        );
        var c_file = self.output_dir.createFile("c.zig", .{}) catch {
            std.log.warn("Couldn't create the `c.zig` file.", .{});
            return error.Error;
        };
        defer c_file.close();
        var c_file_writer = c_file.writer();
        try c_file_writer.print(
            \\pub usingnamespace @cImport({{
            \\    @cInclude("girepository.h");
            \\}});
            \\
        ,
            .{},
        );
        var objects_mod_file = self.output_dir.createFile("objects/mod.zig", .{}) catch {
            std.log.warn("Couldn't create the `objects/mod.zig` file.", .{});
            return error.Error;
        };
        defer objects_mod_file.close();
        var objects_mod_file_writer = objects_mod_file.writer();
        for (objects_file_paths.items) |object_file_path| {
            try objects_mod_file_writer.print(
                "pub usingnamespace @import(\"{s}\");",
                .{object_file_path},
            );
        }
    }
};
