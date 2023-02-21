const std = @import("std");

const gir = @import("girepository");
const xml = @import("xml");

pub const arg = @import("arg.zig");
pub const @"type" = @import("type.zig");
pub const callable = @import("callable.zig");
pub const field = @import("field.zig");
pub const object = @import("object.zig");
pub const utils = @import("utils.zig");

/// The indentation padding
pub const pad = " " ** 4;

/// Find a matching `.gir` file by traversing search paths
fn getGirFilePath(
    target_namespace_name: []const u8,
    target_namespace_version: []const u8,
    allocator: std.mem.Allocator,
) ![:0]const u8 {
    var search_paths = std.ArrayList([]const u8).init(allocator);
    defer search_paths.deinit();

    try search_paths.append("/usr/share");
    var data_dirs_iterator = std.mem.split(
        u8,
        std.os.getenv("XDG_DATA_DIRS") orelse "",
        ":",
    );
    while (data_dirs_iterator.next()) |data_dir| {
        try search_paths.append(data_dir);
    }

    for (search_paths.items) |search_path| {
        const gir_file_path = try std.mem.concatWithSentinel(
            allocator,
            u8,
            &.{
                search_path,
                "/gir-1.0/",
                target_namespace_name,
                "-",
                target_namespace_version,
                ".gir",
            },
            0,
        );
        std.fs.cwd().access(gir_file_path, .{}) catch continue;
        return gir_file_path;
    }

    std.log.err(
        "Couldn't find a matching `.gir` file for the namespace {s}.",
        .{target_namespace_name},
    );
    return error.Error;
}

pub fn getDocstring(
    symbol: [:0]const u8,
    expressions: []const []const u8,
    gir_context: xml.xmlXPathContextPtr,
    indent: bool,
    allocator: std.mem.Allocator,
) !?[:0]const u8 {
    // Evaluate each XPath expression,
    // return the first one that matched
    for (expressions) |expression| {
        const result = xml.xmlXPathEval(
            expression.ptr,
            gir_context,
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
            allocator,
            docstring_slice,
            "\n",
            if (indent) "\n" ++ pad ++ "/// " else "\n/// ",
        );
        return try std.mem.concatWithSentinel(
            allocator,
            u8,
            &.{ "/// ", docstring_formatted },
            0,
        );
    }
    return null;
}

/// Emit code from a target namespace
pub fn from(
    repository: *gir.GIRepository,
    target_namespace_name: []const u8,
    output_dir: *std.fs.Dir,
    allocator: std.mem.Allocator,
) !void {
    // Prepare a shared error handle
    var g_err: ?*gir.GError = null;
    // Load the namespace
    _ = gir.g_irepository_require(
        repository,
        target_namespace_name.ptr,
        null,
        0,
        &g_err,
    );
    if (g_err) |_| {
        std.log.err(
            "Couldn't load the namespace `{s}`.",
            .{target_namespace_name},
        );
        std.os.exit(1);
    }
    // Get the loaded version
    const target_namespace_version = std.mem.sliceTo(gir.g_irepository_get_version(
        repository,
        target_namespace_name.ptr,
    ), 0);
    // Get the path to the `.gir` file
    const gir_file_path = try getGirFilePath(
        target_namespace_name,
        target_namespace_version,
        allocator,
    );
    // Prepare an XML reader (for documentation strings)
    const gir_doc = xml.xmlParseFile(gir_file_path.ptr);
    if (gir_doc == null) {
        std.log.err(
            "Couldn't parse `{s}`.",
            .{gir_file_path},
        );
        return error.Error;
    }
    defer xml.xmlFreeDoc(gir_doc);
    const gir_context = xml.xmlXPathNewContext(gir_doc);
    defer xml.xmlXPathFreeContext(gir_context);
    inline for (.{
        .{ .name = "core", .uri = "http://www.gtk.org/introspection/core/1.0" },
        .{ .name = "c", .uri = "http://www.gtk.org/introspection/c/1.0" },
        .{ .name = "glib", .uri = "http://www.gtk.org/introspection/glib/1.0" },
    }) |xml_namespace| {
        const ret = xml.xmlXPathRegisterNs(
            gir_context,
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
    // Prepare output directories
    var object_subdir = try object.getSubdir(output_dir);
    defer object_subdir.close();
    // Prepare array lists for dependencies
    var objects_file_paths = std.ArrayList([]const u8).init(allocator);
    // For each index of a metadata entry
    const infos_n = gir.g_irepository_get_n_infos(
        repository,
        target_namespace_name.ptr,
    );
    var i: gir.gint = 0;
    while (i < infos_n) : (i += 1) {
        // Get the metadata entry
        const info = gir.g_irepository_get_info(
            repository,
            target_namespace_name.ptr,
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
                    target_namespace_name,
                    info,
                    info_name,
                    &object_subdir,
                    gir_context,
                    allocator,
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
    var lib_file = output_dir.createFile("lib.zig", .{}) catch {
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
    var c_file = output_dir.createFile("c.zig", .{}) catch {
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
    var objects_mod_file = output_dir.createFile("objects/mod.zig", .{}) catch {
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
