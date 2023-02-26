const std = @import("std");

const gir = @import("girepository");
const xml = @import("xml");

const mod = @import("mod.zig");
const PAD = mod.PAD;
const Repository = mod.Repository;

/// An interface to a `.gir` file
pub const GirFile = struct {
    const Self = @This();
    target_namespace_name: []const u8,
    target_namespace_version: []const u8,
    allocator: std.mem.Allocator,
    path: [:0]const u8 = undefined,
    doc: xml.xmlDocPtr = undefined,
    context: xml.xmlXPathContextPtr = undefined,
    fn findIn(self: *const Self, search_path: []const u8) !?[:0]const u8 {
        const gir_file_path = try std.mem.concatWithSentinel(
            self.allocator,
            u8,
            &.{
                search_path,
                "/gir-1.0/",
                self.target_namespace_name,
                "-",
                self.target_namespace_version,
                ".gir",
            },
            0,
        );
        std.fs.cwd().access(gir_file_path, .{}) catch return null;
        return gir_file_path;
    }
    fn find(self: *Self) !void {
        if (try self.findIn("/usr/share")) |gir_file_path| {
            self.path = gir_file_path;
            return;
        }

        var xdg_data_dirs_iterator = std.mem.split(
            u8,
            std.os.getenv("XDG_DATA_DIRS") orelse "",
            ":",
        );
        while (xdg_data_dirs_iterator.next()) |xdg_data_dir| {
            if (try self.findIn(xdg_data_dir)) |gir_file_path| {
                self.path = gir_file_path;
                return;
            }
        }

        std.log.err(
            "Couldn't find a matching `.gir` file for the namespace `{s}`.",
            .{self.target_namespace_name},
        );
        return error.Error;
    }
    fn parse(self: *Self) !void {
        self.doc = xml.xmlParseFile(self.path.ptr);
        if (self.doc == null) {
            std.log.err("Couldn't parse `{s}`.", .{self.path});
            return error.Error;
        }
    }
    fn prepareContext(self: *Self) !void {
        self.context = xml.xmlXPathNewContext(self.doc);
        inline for (.{
            .{ .name = "core", .uri = "http://www.gtk.org/introspection/core/1.0" },
            .{ .name = "c", .uri = "http://www.gtk.org/introspection/c/1.0" },
            .{ .name = "glib", .uri = "http://www.gtk.org/introspection/glib/1.0" },
        }) |xml_namespace| {
            const ret = xml.xmlXPathRegisterNs(
                self.context,
                xml_namespace.name,
                xml_namespace.uri,
            );
            if (ret != 0) {
                std.log.err(
                    "Failed to register the \"{s}\" namespace.",
                    .{xml_namespace.name},
                );
                return error.Error;
            }
        }
    }
    pub fn from(repository: *const Repository) !Self {
        var self = Self{
            .target_namespace_name = repository.target_namespace_name,
            .target_namespace_version = repository.target_namespace_version,
            .allocator = repository.allocator,
        };
        try self.find();
        try self.parse();
        try self.prepareContext();
        return self;
    }
    /// Evaluate each XPath expression, return the string
    /// contents of the first one that matched
    pub fn getDocstring(
        self: *const Self,
        symbol: [:0]const u8,
        expressions: []const []const u8,
        indent: bool,
    ) !?[:0]const u8 {
        for (expressions) |expression| {
            const result = xml.xmlXPathEval(
                expression.ptr,
                self.context,
            );
            if (result == null) {
                std.log.warn(
                    "Couldn't evaluate the XPath expression for `{s}`.",
                    .{symbol},
                );
                continue;
            }
            defer xml.xmlXPathFreeObject(result);
            // Check whether we got a match
            const nodeset = result.*.nodesetval;
            if (nodeset == null or nodeset.*.nodeNr == 0) {
                continue;
            }
            // Get the string from the first match
            const docstring = xml.xmlXPathCastNodeToString(
                nodeset.*.nodeTab[0],
            );
            defer xml.xmlFree.?(docstring);
            // Format the string
            const docstring_slice = std.mem.sliceTo(docstring, 0);
            const docstring_formatted = try std.mem.replaceOwned(
                xml.xmlChar,
                self.allocator,
                docstring_slice,
                "\n",
                if (indent) "\n" ++ PAD ++ "/// " else "\n/// ",
            );
            return try std.mem.concatWithSentinel(
                self.allocator,
                u8,
                &.{ "/// ", docstring_formatted },
                0,
            );
        }
        return null;
    }
    pub fn free(self: *const Self) void {
        xml.xmlFreeDoc(self.doc);
        xml.xmlXPathFreeContext(self.context);
    }
};
