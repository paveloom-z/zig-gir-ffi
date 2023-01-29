const std = @import("std");

const gir = @import("girepository");
const xml = @import("xml");

const emit = @import("mod.zig");

pub const Callable = struct {
    const Self = @This();
    name: [:0]const u8,
    args: []const emit.arg.Arg,
    symbol: [:0]const u8,
    is_method: bool,
    return_type: emit.@"type".Type,
    maybe_docstring: ?[:0]const u8,
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
            try std.mem.concat(allocator, u8, &.{ docstring, "\n", emit.pad })
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

/// Parse a callable
pub fn from(
    callable_info: ?*gir.GICallableInfo,
    dependencies: *std.StringHashMap(void),
    maybe_self_name: ?[:0]const u8,
    target_namespace_name: []const u8,
    gir_context: xml.xmlXPathContextPtr,
    allocator: std.mem.Allocator,
) !Callable {
    const name_snake_case = std.mem.sliceTo(gir.g_base_info_get_name(callable_info), 0);
    const name_camel_case = try emit.utils.toCamelCase(name_snake_case, allocator);
    const is_method = gir.g_callable_info_is_method(callable_info) != 0;
    const symbol = std.mem.sliceTo(gir.g_function_info_get_symbol(callable_info), 0);
    // Get the documentation string
    const docstring_expressions = &.{
        try std.mem.concatWithSentinel(allocator, u8, &.{
            "//core:function[@c:identifier=\"",
            symbol,
            "\"]/core:doc",
        }, 0),
        try std.mem.concatWithSentinel(allocator, u8, &.{
            "//core:method[@c:identifier=\"",
            symbol,
            "\"]/core:doc",
        }, 0),
    };
    const maybe_docstring = try emit.getDocstring(
        symbol,
        docstring_expressions,
        gir_context,
        true,
        allocator,
    );
    if (maybe_docstring == null) {
        std.log.warn(
            "Couldn't get the documentation string for `{s}`.",
            .{symbol},
        );
    }
    // Parse arguments
    const args_n = gir.g_callable_info_get_n_args(callable_info);
    const args = try allocator.alloc(
        emit.arg.Arg,
        @intCast(usize, args_n),
    );
    {
        var i: usize = 0;
        while (i < args_n) : (i += 1) {
            const argument = gir.g_callable_info_get_arg(
                callable_info,
                @intCast(gir.gint, i),
            );
            defer gir.g_base_info_unref(argument);
            args[i] = try emit.arg.from(
                argument,
                maybe_self_name,
                dependencies,
                target_namespace_name,
                allocator,
            );
        }
    }
    // Parse a return type
    const return_type_info = gir.g_callable_info_get_return_type(callable_info);
    defer gir.g_base_info_unref(return_type_info);
    const return_type = try emit.@"type".from(
        return_type_info,
        maybe_self_name,
        dependencies,
        target_namespace_name,
        allocator,
    );
    return Callable{
        .name = name_camel_case,
        .args = args,
        .is_method = is_method,
        .symbol = symbol,
        .return_type = return_type,
        .maybe_docstring = maybe_docstring,
    };
}
