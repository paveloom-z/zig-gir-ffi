const std = @import("std");

const gir = @import("girepository");

const mod = @import("mod.zig");
const Repository = mod.Repository;
const Type = mod.Type;
const Value = mod.Value;

pub const Constant = struct {
    const Self = @This();
    repository: *const Repository,
    info: *gir.GICallableInfo,
    name: [:0]const u8 = undefined,
    maybe_docstring: ?[:0]const u8 = undefined,
    type: Type = undefined,
    value: []const u8 = undefined,
    fn getName(self: *Self) !void {
        self.name = std.mem.sliceTo(gir.g_base_info_get_name(self.info), 0);
    }
    fn getDocstring(self: *Self) !void {
        const expressions = &.{
            try std.mem.concatWithSentinel(self.repository.allocator, u8, &.{
                "//core:constant[@name=\"",
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
    fn getType(self: *Self) !void {
        const type_info = gir.g_constant_info_get_type(self.info);
        defer gir.g_base_info_unref(type_info);

        self.type = try Type.from(
            self.repository,
            type_info,
            null,
            null,
        );
    }
    fn formatValue(self: *const Self, value: anytype) ![]const u8 {
        return try std.fmt.allocPrint(self.repository.allocator, "{}", .{value});
    }
    fn getValue(self: *Self) !void {
        const argument = try self.repository.allocator.create(gir.GIArgument);
        _ = gir.g_constant_info_get_value(self.info, argument);
        defer gir.g_constant_info_free_value(self.info, argument);

        self.value = switch (self.type.tag) {
            .bool_t => try self.formatValue(argument.v_boolean),
            .i8_t => try self.formatValue(argument.v_int8),
            .u8_t => try self.formatValue(argument.v_uint8),
            .i16_t => try self.formatValue(argument.v_int16),
            .u16_t => try self.formatValue(argument.v_uint32),
            .i32_t => try self.formatValue(argument.v_int32),
            .u32_t => try self.formatValue(argument.v_uint32),
            .i64_t => try self.formatValue(argument.v_int64),
            .u64_t => try self.formatValue(argument.v_uint64),
            .f32_t => try self.formatValue(argument.v_float),
            .f64_t => try self.formatValue(argument.v_double),
            .utf_8 => std.mem.sliceTo(argument.v_string, 0),
            else => unreachable,
        };
    }
    pub fn from(
        repository: *const Repository,
        constant_info: *gir.GIConstantInfo,
    ) !Self {
        var self = Self{
            .repository = repository,
            .info = constant_info,
        };

        try self.getName();
        try self.getDocstring();
        try self.getType();
        try self.getValue();

        return self;
    }
    pub fn toString(self: *const Self) ![]const u8 {
        const docstring = if (self.maybe_docstring) |docstring|
            try std.mem.concat(self.repository.allocator, u8, &.{ docstring, "\n" })
        else
            "";
        return try std.fmt.allocPrint(
            self.repository.allocator,
            "{s}const {s}: {s} = {s};\n",
            .{
                docstring,
                self.name,
                self.type.name,
                self.value,
            },
        );
    }
};

pub const ConstantsFile = struct {
    const Self = @This();
    const Constants = std.ArrayList(Constant);
    const name = "constants.zig";
    repository: *const Repository,
    file: std.fs.File = undefined,
    path: [:0]const u8 = undefined,
    constants: Constants = undefined,
    fn createFile(self: *Self) !void {
        self.file = self.repository.output_dir.createFile(name, .{}) catch {
            std.log.warn("Couldn't create the `{s}` file.", .{name});
            return error.Error;
        };
    }
    pub fn from(repository: *const Repository) !Self {
        var self = Self{ .repository = repository };

        try self.createFile();
        self.constants = Constants.init(repository.allocator);

        return self;
    }
    pub fn close(self: *Self) void {
        self.file.close();
    }
    pub fn write(self: *const Self) !void {
        var buffered_writer = std.io.bufferedWriter(self.file.writer());
        const writer = buffered_writer.writer();
        defer buffered_writer.flush() catch {
            std.log.warn(
                "Couldn't flush the writer for the `{s}` file.",
                .{self.path},
            );
        };

        for (self.constants.items) |constant, i| {
            const string = try constant.toString();
            if (i != 0) {
                try writer.print("\n", .{});
            }
            try writer.print("{s}", .{string});
        }
    }
    pub fn emitConstant(
        self: *Self,
        info: *gir.GIBaseInfo,
        info_name: [:0]const u8,
    ) !void {
        std.log.info("Emitting constant `{s}`...", .{info_name});

        const constant = try Constant.from(self.repository, info);
        try self.constants.append(constant);
    }
};
