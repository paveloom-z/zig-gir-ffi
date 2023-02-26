const std = @import("std");

const gir = @import("girepository");

const mod = @import("mod.zig");
const PAD = mod.PAD;
const utils = mod.utils;
const Arg = mod.Arg;
const Dependencies = mod.Dependencies;
const GirFile = mod.GirFile;
const Type = mod.Type;

pub const Callable = struct {
    const Self = @This();
    target_namespace_name: []const u8,
    gir_file: *const GirFile,
    info: *gir.GICallableInfo,
    name: [:0]const u8,
    maybe_parent_name: ?[:0]const u8,
    symbol: [:0]const u8,
    is_method: bool,
    allocator: std.mem.Allocator,
    maybe_docstring: ?[:0]const u8 = undefined,
    args: []const Arg = undefined,
    return_type: Type = undefined,
    fn parseDocstring(self: *Self) !void {
        const expressions = &.{
            try std.mem.concatWithSentinel(self.allocator, u8, &.{
                "//core:function[@c:identifier=\"",
                self.symbol,
                "\"]/core:doc",
            }, 0),
            try std.mem.concatWithSentinel(self.allocator, u8, &.{
                "//core:method[@c:identifier=\"",
                self.symbol,
                "\"]/core:doc",
            }, 0),
        };
        self.maybe_docstring = try self.gir_file.getDocstring(
            self.symbol,
            expressions,
            true,
        );
        if (self.maybe_docstring == null) {
            std.log.warn(
                "Couldn't get the documentation string for `{s}`.",
                .{self.symbol},
            );
        }
    }
    fn parseArgs(self: *Self, dependencies: *Dependencies) !void {
        const n = gir.g_callable_info_get_n_args(self.info);
        const args = try self.allocator.alloc(
            Arg,
            @intCast(usize, n),
        );
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const argument = gir.g_callable_info_get_arg(
                self.info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(argument);
            args[i] = try Arg.from(
                argument,
                self.name,
                dependencies,
                self.target_namespace_name,
                self.allocator,
            );
        }
        self.args = args;
    }
    fn parseReturnType(self: *Self, dependencies: *Dependencies) !void {
        const return_type_info = gir.g_callable_info_get_return_type(self.info);
        defer gir.g_base_info_unref(return_type_info);
        self.return_type = try Type.from(
            return_type_info,
            self.maybe_parent_name,
            dependencies,
            self.target_namespace_name,
            self.allocator,
        );
    }
    pub fn from(
        target_namespace_name: []const u8,
        gir_file: *const GirFile,
        callable_info: *gir.GICallableInfo,
        maybe_parent_name: ?[:0]const u8,
        dependencies: *Dependencies,
        allocator: std.mem.Allocator,
    ) !Self {
        const name_snake_case = std.mem.sliceTo(gir.g_base_info_get_name(callable_info), 0);
        const name_camel_case = try utils.toCamelCase(name_snake_case, allocator);
        const is_method = gir.g_callable_info_is_method(callable_info) != 0;
        const symbol = std.mem.sliceTo(gir.g_function_info_get_symbol(callable_info), 0);

        var self = Self{
            .target_namespace_name = target_namespace_name,
            .gir_file = gir_file,
            .info = callable_info,
            .name = name_camel_case,
            .maybe_parent_name = maybe_parent_name,
            .symbol = symbol,
            .is_method = is_method,
            .allocator = allocator,
        };

        try self.parseDocstring();
        try self.parseArgs(dependencies);
        try self.parseReturnType(dependencies);

        return self;
    }
    pub fn toString(
        self: *const Self,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        var args_signature = std.ArrayList([]const u8).init(allocator);
        var args_call = std.ArrayList([]const u8).init(allocator);
        if (self.is_method) {
            try args_signature.append("self: *Self");
            try args_call.append("self");
        }
        for (self.args) |arg| {
            const string = try arg.toString(allocator);
            try args_signature.append(string);
            try args_call.append(arg.name);
        }
        const return_string = if (self.return_type.is_void)
            ""
        else
            "return ";
        const docstring = if (self.maybe_docstring) |docstring|
            try std.mem.concat(allocator, u8, &.{ docstring, "\n", PAD })
        else
            "";
        return try std.fmt.allocPrint(
            allocator,
            \\    {s}pub fn {s}({s}) {s} {{
            \\        {s}c.{s}({s});
            \\    }}
            \\
        ,
            .{
                docstring,
                self.name,
                try std.mem.join(allocator, ", ", args_signature.items),
                self.return_type.name,
                return_string,
                self.symbol,
                try std.mem.join(allocator, ", ", args_call.items),
            },
        );
    }
};
