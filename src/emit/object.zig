const std = @import("std");

const gir = @import("girepository");

const mod = @import("mod.zig");
const Callable = mod.Callable;
const Dependencies = mod.Dependencies;
const Field = mod.Field;
const GirFile = mod.GirFile;
const Repository = mod.Repository;

pub const ObjectsSubdir = struct {
    const Self = @This();
    const FilePaths = std.ArrayList([]const u8);
    const subdir_name = "objects";
    repository: *const Repository,
    subdir: std.fs.Dir,
    file_paths: FilePaths,
    allocator: std.mem.Allocator,
    pub fn from(repository: *const Repository) !Self {
        const subdir = repository.output_dir.makeOpenPath(subdir_name, .{}) catch {
            std.log.err(
                "Couldn't create the `{s}` subdirectory.",
                .{subdir_name},
            );
            return error.Error;
        };
        return Self{
            .repository = repository,
            .subdir = subdir,
            .file_paths = FilePaths.init(repository.allocator),
            .allocator = repository.allocator,
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
    repository: *const Repository,
    subdir: std.fs.Dir,
    info: *gir.GIObjectInfo,
    name: [:0]const u8,
    file: std.fs.File = undefined,
    path: [:0]const u8 = undefined,
    dependencies: Dependencies = undefined,
    maybe_docstring: ?[:0]const u8 = undefined,
    fields: []const Field = undefined,
    methods: []const Callable = undefined,
    fn getPath(self: *Self) !void {
        const lowercase_info_name = try std.ascii.allocLowerString(
            self.repository.allocator,
            self.name,
        );
        self.path = try std.mem.concatWithSentinel(
            self.repository.allocator,
            u8,
            &.{ lowercase_info_name, ".zig" },
            0,
        );
    }
    fn createFile(self: *Self) !void {
        self.file = self.subdir.createFile(self.path, .{}) catch {
            std.log.warn("Couldn't create the `{s}` file.", .{self.path});
            return error.Error;
        };
    }
    pub fn new(
        objects_subdir: *const ObjectsSubdir,
        info: *gir.GIBaseInfo,
        info_name: [:0]const u8,
    ) !Self {
        var self = Self{
            .repository = objects_subdir.repository,
            .subdir = objects_subdir.subdir,
            .info = @ptrCast(*gir.GIObjectInfo, info),
            .name = info_name,
        };
        self.dependencies = Dependencies.init(self.repository.allocator);
        try self.getPath();
        try self.createFile();
        return self;
    }
    pub fn close(self: *Self) void {
        self.file.close();
    }
    fn parseDocstring(self: *Self) !void {
        const expressions = &.{
            try std.mem.concatWithSentinel(self.repository.allocator, u8, &.{
                "//core:class[@name=\"",
                self.name,
                "\"]/core:doc",
            }, 0),
        };
        self.maybe_docstring = try self.repository.gir_file.getDocstring(
            self.name,
            expressions,
            false,
        );
        if (self.maybe_docstring == null) {
            std.log.warn(
                "Couldn't get the documentation string for `{s}`.",
                .{self.name},
            );
        }
    }
    fn parseConstants(self: *Self) void {
        const n = gir.g_object_info_get_n_constants(self.info);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const constant = gir.g_object_info_get_constant(
                self.info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(constant);
            std.log.warn("TODO: Object Constants", .{});
        }
    }
    fn parseFields(self: *Self) !void {
        const n = gir.g_object_info_get_n_fields(self.info);
        const fields = try self.repository.allocator.alloc(
            Field,
            @intCast(usize, n),
        );
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const field_info = gir.g_object_info_get_field(
                self.info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(field_info);
            fields[i] = try Field.from(
                self.repository,
                field_info,
                self.name,
                &self.dependencies,
            );
        }
        self.fields = fields;
    }
    fn parseInterfaces(self: *Self) void {
        const n = gir.g_object_info_get_n_interfaces(self.info);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const interface_info = gir.g_object_info_get_interface(
                self.info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(interface_info);
            std.log.warn("TODO: Object Interfaces", .{});
        }
    }
    fn parseMethods(self: *Self) !void {
        const n = gir.g_object_info_get_n_methods(self.info);
        const methods = try self.repository.allocator.alloc(
            Callable,
            @intCast(usize, n),
        );
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const method_info = gir.g_object_info_get_method(
                self.info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(method_info);
            methods[i] = try Callable.from(
                self.repository,
                method_info,
                self.name,
                &self.dependencies,
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

        if (self.maybe_docstring) |docstring| {
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
            const string = try field.toString(self.repository.allocator);
            try writer.print("{s}", .{string});
        }

        for (self.methods) |method| {
            const string = try method.toString(self.repository.allocator);
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
