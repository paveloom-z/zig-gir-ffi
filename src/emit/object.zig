const std = @import("std");

const gir = @import("girepository");

const mod = @import("mod.zig");
const Callable = mod.Callable;
const EmitRequest = mod.EmitRequest;
const Field = mod.Field;
const GirFile = mod.GirFile;

pub const ObjectsSubdir = struct {
    const Self = @This();
    const FilePaths = std.ArrayList([]const u8);
    target_namespace_name: []const u8,
    gir_file: *const GirFile,
    subdir: std.fs.Dir,
    file_paths: FilePaths,
    allocator: std.mem.Allocator,
    pub fn from(emit_request: *const EmitRequest, gir_file: *const GirFile) !Self {
        const subdir_path = "objects";
        const subdir = emit_request.output_dir.makeOpenPath(subdir_path, .{}) catch {
            std.log.err(
                "Couldn't create the `{s}` subdirectory.",
                .{subdir_path},
            );
            return error.Error;
        };
        return Self{
            .target_namespace_name = emit_request.target_namespace_name,
            .gir_file = gir_file,
            .subdir = subdir,
            .file_paths = FilePaths.init(emit_request.allocator),
            .allocator = emit_request.allocator,
        };
    }
    pub fn close(self: *Self) void {
        self.subdir.close();
    }
    pub fn emitModFile(self: *const Self) !void {
        var objects_mod_file = self.subdir.createFile("mod.zig", .{}) catch {
            std.log.warn("Couldn't create the `objects/mod.zig` file.", .{});
            return error.Error;
        };
        defer objects_mod_file.close();

        var objects_mod_file_writer = objects_mod_file.writer();
        for (self.file_paths.items) |object_file_path| {
            try objects_mod_file_writer.print(
                "pub usingnamespace @import(\"{s}\");",
                .{object_file_path},
            );
        }
    }
    pub fn emitObject(
        self: *Self,
        info: *gir.GIBaseInfo,
        info_name: [:0]const u8,
    ) !void {
        const object = @ptrCast(*gir.GIObjectInfo, info);
        std.log.info("Emitting object `{s}`...", .{info_name});
        // Create a file
        const lowercase_info_name = try std.ascii.allocLowerString(
            self.allocator,
            info_name,
        );
        const file_path = try std.mem.concatWithSentinel(
            self.allocator,
            u8,
            &.{ lowercase_info_name, ".zig" },
            0,
        );
        const file = self.subdir.createFile(file_path, .{}) catch {
            std.log.warn("Couldn't create the `{s}` file.", .{file_path});
            return error.Error;
        };
        defer file.close();
        // Prepare a buffered writer
        var buffered_writer = std.io.bufferedWriter(file.writer());
        const writer = buffered_writer.writer();
        defer buffered_writer.flush() catch {
            std.log.warn(
                "Couldn't flush the writer for the `{s}` file.",
                .{file_path},
            );
        };
        // Prepare a hashset for dependencies
        var dependencies = std.StringHashMap(void).init(self.allocator);
        // Get the documentation string
        const expressions = &.{
            try std.mem.concatWithSentinel(self.allocator, u8, &.{
                "//core:class[@name=\"",
                info_name,
                "\"]/core:doc",
            }, 0),
        };
        const maybe_docstring = try self.gir_file.getDocstring(
            info_name,
            expressions,
            false,
        );
        if (maybe_docstring == null) {
            std.log.warn(
                "Couldn't get the documentation string for `{s}`.",
                .{info_name},
            );
        }
        // Parse constants
        const constants_n = gir.g_object_info_get_n_constants(object);
        {
            var i: usize = 0;
            while (i < constants_n) : (i += 1) {
                const constant = gir.g_object_info_get_constant(
                    info,
                    @intCast(gir.gint, i),
                );
                defer gir.g_base_info_unref(constant);
                std.log.warn("TODO: Object Constants", .{});
            }
        }
        // Parse fields
        const fields_n = gir.g_object_info_get_n_fields(object);
        const fields = try self.allocator.alloc(
            Field,
            @intCast(usize, fields_n),
        );
        {
            var i: usize = 0;
            while (i < fields_n) : (i += 1) {
                const field = gir.g_object_info_get_field(
                    info,
                    @intCast(gir.gint, i),
                );
                defer gir.g_base_info_unref(field);
                fields[i] = try Field.from(
                    field,
                    info_name,
                    &dependencies,
                    self.target_namespace_name,
                    self.allocator,
                );
            }
        }
        // Parse interfaces
        const interfaces_n = gir.g_object_info_get_n_interfaces(object);
        {
            var i: usize = 0;
            while (i < interfaces_n) : (i += 1) {
                const interface = gir.g_object_info_get_interface(
                    info,
                    @intCast(gir.gint, i),
                );
                defer gir.g_base_info_unref(interface);
                std.log.warn("TODO: Object Interfaces", .{});
            }
        }
        // Parse methods
        const methods_n = gir.g_object_info_get_n_methods(object);
        const methods = try self.allocator.alloc(
            Callable,
            @intCast(usize, methods_n),
        );
        {
            var i: usize = 0;
            while (i < methods_n) : (i += 1) {
                const method = gir.g_object_info_get_method(
                    info,
                    @intCast(gir.gint, i),
                );
                defer gir.g_base_info_unref(method);
                methods[i] = try Callable.from(
                    method,
                    &dependencies,
                    info_name,
                    self.target_namespace_name,
                    self.gir_file,
                    self.allocator,
                );
            }
        }
        // Print the results
        try writer.print(
            \\const lib = @import("../lib.zig");
            \\
            \\const c = lib.c;
            \\
            \\
        ,
            .{},
        );
        var dependencies_iterator = dependencies.keyIterator();
        while (dependencies_iterator.next()) |dependency| {
            try writer.print("const {0s} = lib.{0s};\n", .{dependency.*});
        }
        if (maybe_docstring) |docstring| {
            try writer.print("\n{s}", .{docstring});
        }
        try writer.print(
            \\
            \\pub const {s} = extern struct {{
            \\    const Self = @This();
            \\
        ,
            .{info_name},
        );
        for (fields) |field| {
            const string = try field.toString(self.allocator);
            try writer.print("{s}", .{string});
        }
        for (methods) |method| {
            const string = try method.toString(self.allocator);
            try writer.print("{s}", .{string});
        }
        try writer.print("}};\n", .{});

        try self.file_paths.append(file_path);
    }
};
