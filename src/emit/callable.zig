const std = @import("std");

const gir = @import("girepository");

const mod = @import("mod.zig");
const PAD = mod.PAD;
const utils = mod.utils;
const Arg = mod.Arg;
const Dependencies = mod.Dependencies;
const GirFile = mod.GirFile;
const Repository = mod.Repository;
const Type = mod.Type;

pub const Callable = struct {
    const Self = @This();
    repository: *const Repository,
    info: *gir.GICallableInfo,
    name: [:0]const u8,
    maybe_parent_name: ?[:0]const u8,
    symbol: [:0]const u8,
    is_method: bool,
    maybe_docstring: ?[:0]const u8 = undefined,
    args: []const Arg = undefined,
    return_type: Type = undefined,
    fn parseDocstring(self: *Self) !void {
        const expressions = &.{
            try std.mem.concatWithSentinel(self.repository.allocator, u8, &.{
                "//core:function[@c:identifier=\"",
                self.symbol,
                "\"]/core:doc",
            }, 0),
            try std.mem.concatWithSentinel(self.repository.allocator, u8, &.{
                "//core:method[@c:identifier=\"",
                self.symbol,
                "\"]/core:doc",
            }, 0),
        };
        self.maybe_docstring = try self.repository.gir_file.getDocstring(
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
        const args = try self.repository.allocator.alloc(
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
                self.repository,
                argument,
                self.name,
                dependencies,
            );
        }
        self.args = args;
    }
    fn parseReturnType(self: *Self, dependencies: *Dependencies) !void {
        const return_type_info = gir.g_callable_info_get_return_type(self.info);
        defer gir.g_base_info_unref(return_type_info);
        self.return_type = try Type.from(
            self.repository,
            return_type_info,
            self.maybe_parent_name,
            dependencies,
        );
    }
    pub fn from(
        repository: *const Repository,
        callable_info: *gir.GICallableInfo,
        maybe_parent_name: ?[:0]const u8,
        dependencies: *Dependencies,
    ) !Self {
        const name_snake_case = std.mem.sliceTo(gir.g_base_info_get_name(callable_info), 0);
        const name_camel_case = try utils.toCamelCase(name_snake_case, repository.allocator);
        const is_method = gir.g_callable_info_is_method(callable_info) != 0;
        const symbol = std.mem.sliceTo(gir.g_function_info_get_symbol(callable_info), 0);

        var self = Self{
            .repository = repository,
            .info = callable_info,
            .name = name_camel_case,
            .maybe_parent_name = maybe_parent_name,
            .symbol = symbol,
            .is_method = is_method,
        };

        try self.parseDocstring();
        try self.parseArgs(dependencies);
        try self.parseReturnType(dependencies);

        return self;
    }
    pub fn toString(self: *const Self) ![]const u8 {
        var args_signature = std.ArrayList([]const u8).init(self.repository.allocator);
        var args_call = std.ArrayList([]const u8).init(self.repository.allocator);
        if (self.is_method) {
            try args_signature.append("self: *Self");
            try args_call.append("self");
        }
        for (self.args) |arg| {
            const string = try arg.toString(self.repository.allocator);
            try args_signature.append(string);
            try args_call.append(if (arg.type.tag == .interface_t)
                try std.mem.concat(self.repository.allocator, u8, &.{ arg.name, ".toC()" })
            else
                arg.name);
        }
        const return_string = if (self.return_type.tag == .void_t)
            ""
        else
            "return ";
        const docstring = if (self.maybe_docstring) |docstring|
            try std.mem.concat(self.repository.allocator, u8, &.{ docstring, "\n", PAD })
        else
            "";
        return try std.fmt.allocPrint(
            self.repository.allocator,
            \\    {s}pub fn {s}({s}) {s} {{
            \\        {s}c.{s}({s});
            \\    }}
            \\
        ,
            .{
                docstring,
                self.name,
                try std.mem.join(self.repository.allocator, ", ", args_signature.items),
                self.return_type.name,
                return_string,
                self.symbol,
                try std.mem.join(self.repository.allocator, ", ", args_call.items),
            },
        );
    }
};
