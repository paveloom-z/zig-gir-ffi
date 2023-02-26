const std = @import("std");

const gir = @import("girepository");
const xml = @import("xml");

const emit = @import("emit/mod.zig");
const Arg = emit.Arg;
const Callable = emit.Callable;
const Field = emit.Field;
const GirFile = emit.GirFile;
const ObjectsSubdir = emit.ObjectsSubdir;
const Type = emit.Type;

pub const Repository = struct {
    const Self = @This();
    target_namespace_name: []const u8,
    target_namespace_version: []const u8 = undefined,
    repository: *gir.GIRepository,
    gir_file: GirFile = undefined,
    output_dir: *std.fs.Dir,
    allocator: std.mem.Allocator,
    fn loadTypelibFile(self: *Self) !void {
        var g_err: ?*gir.GError = null;
        _ = gir.g_irepository_require(
            self.repository,
            self.target_namespace_name.ptr,
            null,
            0,
            &g_err,
        );
        if (g_err) |_| {
            std.log.err(
                "Couldn't load the `.typelib` file.",
                .{},
            );
            return error.Error;
        }
        self.target_namespace_version = std.mem.sliceTo(gir.g_irepository_get_version(
            self.repository,
            self.target_namespace_name.ptr,
        ), 0);
    }
    fn loadGirFile(self: *Self) !void {
        self.gir_file = GirFile.from(self) catch {
            std.log.err(
                "Couldn't load the `.gir` file.",
                .{},
            );
            return error.Error;
        };
    }
    pub fn load(
        target_namespace_name: []const u8,
        output_dir: *std.fs.Dir,
        allocator: std.mem.Allocator,
    ) !Self {
        var self = Self{
            .target_namespace_name = target_namespace_name,
            .repository = gir.g_irepository_get_default(),
            .output_dir = output_dir,
            .allocator = allocator,
        };
        try self.loadTypelibFile();
        try self.loadGirFile();
        return self;
    }
    fn createLibFile(self: *const Self) !void {
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
    }
    fn createCFile(self: *const Self) !void {
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
    }
    pub fn cleanup(self: *const Self) void {
        self.gir_file.free();
    }
    pub fn emit(self: *const Self) !void {
        var objects_subdir = try ObjectsSubdir.from(self);
        defer objects_subdir.close();

        const n = gir.g_irepository_get_n_infos(
            self.repository,
            self.target_namespace_name.ptr,
        );
        var i: gir.gint = 0;
        while (i < n) : (i += 1) {
            const info = gir.g_irepository_get_info(
                self.repository,
                self.target_namespace_name.ptr,
                i,
            );
            defer gir.g_base_info_unref(info);

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
                    objects_subdir.emitObject(info, info_name) catch {
                        std.log.warn(
                            "Couldn't emit object `{s}`.",
                            .{info_name},
                        );
                        continue;
                    };
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

        try self.createLibFile();
        try self.createCFile();

        try objects_subdir.emitModFile();
    }
};
