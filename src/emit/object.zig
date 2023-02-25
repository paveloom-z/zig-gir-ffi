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
        std.log.info("Emitting object `{s}`...", .{info_name});

        var object_file = try ObjectFile.new(self, info, info_name);
        defer object_file.close();

        try object_file.emit();

        try self.file_paths.append(object_file.path);
    }
};

const ObjectFile = struct {
    const Self = @This();
    const Dependencies = std.StringHashMap(void);
    target_namespace_name: []const u8,
    gir_file: *const GirFile,
    info: *gir.GIObjectInfo,
    name: [:0]const u8,
    allocator: std.mem.Allocator,
    file: std.fs.File,
    path: [:0]const u8,
    dependencies: Dependencies,
    docstring: ?[:0]const u8 = undefined,
    fields: []const Field = undefined,
    methods: []const Callable = undefined,
    fn getPath(name: [:0]const u8, allocator: std.mem.Allocator) ![:0]const u8 {
        const lowercase_info_name = try std.ascii.allocLowerString(
            allocator,
            name,
        );
        return try std.mem.concatWithSentinel(
            allocator,
            u8,
            &.{ lowercase_info_name, ".zig" },
            0,
        );
    }
    fn create(subdir: std.fs.Dir, file_path: [:0]const u8) !std.fs.File {
        return subdir.createFile(file_path, .{}) catch {
            std.log.warn("Couldn't create the `{s}` file.", .{file_path});
            return error.Error;
        };
    }
    pub fn new(
        objects_subdir: *ObjectsSubdir,
        info: *gir.GIBaseInfo,
        info_name: [:0]const u8,
    ) !Self {
        const target_namespace_name = objects_subdir.target_namespace_name;
        const gir_file = objects_subdir.gir_file;
        const subdir = objects_subdir.subdir;
        const allocator = objects_subdir.allocator;

        const path = try getPath(info_name, allocator);
        const file = try create(subdir, path);
        return Self{
            .target_namespace_name = target_namespace_name,
            .gir_file = gir_file,
            .info = @ptrCast(*gir.GIObjectInfo, info),
            .name = info_name,
            .allocator = allocator,
            .file = file,
            .path = path,
            .dependencies = Dependencies.init(allocator),
        };
    }
    pub fn close(self: *Self) void {
        self.file.close();
    }
    fn parseDocstring(self: *Self) !void {
        const expressions = &.{
            try std.mem.concatWithSentinel(self.allocator, u8, &.{
                "//core:class[@name=\"",
                self.name,
                "\"]/core:doc",
            }, 0),
        };
        self.docstring = try self.gir_file.getDocstring(
            self.name,
            expressions,
            false,
        );
        if (self.docstring == null) {
            std.log.warn(
                "Couldn't get the documentation string for `{s}`.",
                .{self.name},
            );
        }
    }
    fn parseConstants(self: *Self) void {
        const constants_n = gir.g_object_info_get_n_constants(self.info);
        var i: usize = 0;
        while (i < constants_n) : (i += 1) {
            const constant = gir.g_object_info_get_constant(
                self.info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(constant);
            std.log.warn("TODO: Object Constants", .{});
        }
    }
    fn parseFields(self: *Self) !void {
        const fields_n = gir.g_object_info_get_n_fields(self.info);
        const fields = try self.allocator.alloc(
            Field,
            @intCast(usize, fields_n),
        );
        var i: usize = 0;
        while (i < fields_n) : (i += 1) {
            const field = gir.g_object_info_get_field(
                self.info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(field);
            fields[i] = try Field.from(
                field,
                self.name,
                &self.dependencies,
                self.target_namespace_name,
                self.allocator,
            );
        }
        self.fields = fields;
    }
    fn parseInterfaces(self: *Self) void {
        const interfaces_n = gir.g_object_info_get_n_interfaces(self.info);
        {
            var i: usize = 0;
            while (i < interfaces_n) : (i += 1) {
                const interface = gir.g_object_info_get_interface(
                    self.info,
                    @intCast(gir.gint, i),
                );
                defer gir.g_base_info_unref(interface);
                std.log.warn("TODO: Object Interfaces", .{});
            }
        }
    }
    fn parseMethods(self: *Self) !void {
        const methods_n = gir.g_object_info_get_n_methods(self.info);
        const methods = try self.allocator.alloc(
            Callable,
            @intCast(usize, methods_n),
        );
        var i: usize = 0;
        while (i < methods_n) : (i += 1) {
            const method = gir.g_object_info_get_method(
                self.info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(method);
            methods[i] = try Callable.from(
                method,
                self.name,
                &self.dependencies,
                self.target_namespace_name,
                self.gir_file,
                self.allocator,
            );
        }
        self.methods = methods;
    }
    fn write(self: *const Self, writer: anytype) !void {
        try writer.print(
            \\const lib = @import("../lib.zig");
            \\
            \\const c = lib.c;
            \\
            \\
        ,
            .{},
        );

        var dependencies_iterator = self.dependencies.keyIterator();
        while (dependencies_iterator.next()) |dependency| {
            try writer.print("const {0s} = lib.{0s};\n", .{dependency.*});
        }

        if (self.docstring) |docstring| {
            try writer.print("\n{s}", .{docstring});
        }

        try writer.print(
            \\
            \\pub const {s} = extern struct {{
            \\    const Self = @This();
            \\
        ,
            .{self.name},
        );

        for (self.fields) |field| {
            const string = try field.toString(self.allocator);
            try writer.print("{s}", .{string});
        }

        for (self.methods) |method| {
            const string = try method.toString(self.allocator);
            try writer.print("{s}", .{string});
        }

        try writer.print("}};\n", .{});
    }
    pub fn emit(self: *Self) !void {
        var buffered_writer = std.io.bufferedWriter(self.file.writer());
        const writer = buffered_writer.writer();
        defer buffered_writer.flush() catch {
            std.log.warn(
                "Couldn't flush the writer for the `{s}` file.",
                .{self.path},
            );
        };

        try self.parseDocstring();
        self.parseConstants();
        try self.parseFields();
        self.parseInterfaces();
        try self.parseMethods();

        try self.write(writer);
    }
};
