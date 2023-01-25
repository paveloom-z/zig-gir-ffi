const std = @import("std");

const gir = @import("girepository");
const xml = @import("xml");

const object = @import("object.zig");

/// Create a slice from a pointer to a null-terminated array
pub fn sliceFrom(ptr: [*c]const u8) [:0]const u8 {
    return std.mem.span(@ptrCast([*:0]const u8, ptr));
}

/// Emit code from a target namespace
pub fn from(
    repository: *gir.GIRepository,
    target_namespace_name: [:0]const u8,
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
        std.log.err("Couldn't load the namespace.", .{});
        std.os.exit(1);
    }
    // Get the loaded version
    const target_namespace_version = sliceFrom(gir.g_irepository_get_version(
        repository,
        target_namespace_name.ptr,
    ));
    // Get the path to the `.gir` file
    const gir_file_path = try std.mem.concatWithSentinel(
        allocator,
        u8,
        &.{
            "/usr/share/gir-1.0/",
            target_namespace_name,
            "-",
            target_namespace_version,
            ".gir",
        },
        0,
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
    {
        const ret = xml.xmlXPathRegisterNs(gir_context, "gir", "http://www.gtk.org/introspection/core/1.0");
        if (ret != 0) {
            std.log.err("Failed to register the namespace.", .{});
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
        const info_name = sliceFrom(gir.g_base_info_get_name(info));
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
            gir.GI_INFO_TYPE_CALLBACK => {
                std.log.info(
                    "Callback `{s}`",
                    .{info_name},
                );
            },
            gir.GI_INFO_TYPE_STRUCT => {
                std.log.info(
                    "Struct `{s}`",
                    .{info_name},
                );
            },
            gir.GI_INFO_TYPE_BOXED => {
                std.log.info(
                    "Boxed `{s}`",
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
                    info,
                    info_name,
                    &object_subdir,
                    gir_context,
                    allocator,
                ) catch {
                    std.log.warn(
                        "Couldn't emit object `{s}`",
                        .{info_name},
                    );
                    continue;
                };
                try objects_file_paths.append(object_file_path);
            },
            gir.GI_INFO_TYPE_INTERFACE => {
                std.log.info(
                    "Interface `{s}`",
                    .{info_name},
                );
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
            gir.GI_INFO_TYPE_VALUE => {
                std.log.info(
                    "Value `{s}`",
                    .{info_name},
                );
            },
            gir.GI_INFO_TYPE_SIGNAL => {
                std.log.info(
                    "Signal `{s}`",
                    .{info_name},
                );
            },
            gir.GI_INFO_TYPE_VFUNC => {
                std.log.info(
                    "VFunc `{s}`",
                    .{info_name},
                );
            },
            gir.GI_INFO_TYPE_PROPERTY => {
                std.log.info(
                    "Property `{s}`",
                    .{info_name},
                );
            },
            gir.GI_INFO_TYPE_FIELD => {
                std.log.info(
                    "Field `{s}`",
                    .{info_name},
                );
            },
            gir.GI_INFO_TYPE_ARG => {
                std.log.info(
                    "Argument `{s}`",
                    .{info_name},
                );
            },
            gir.GI_INFO_TYPE_TYPE => {
                std.log.info(
                    "Type `{s}`",
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
