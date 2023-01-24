const std = @import("std");

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

// Ask the user whether we should proceed
// with overwriting the directory
fn askOverwriteDir() !void {
    while (true) {
        stdout.print(
            "\rOverwrite the output directory? (y/n) > ",
            .{},
        ) catch {};
        const answer = try stdin.readByte();
        switch (answer) {
            'y' => break,
            'n' => {
                return error.Error;
            },
            else => continue,
        }
    }
}

/// Get the output directory from the arguments
pub fn getOutputDir(allocator: std.mem.Allocator) !std.fs.Dir {
    // Prepare an arguments iterator
    var args = try std.process.argsWithAllocator(allocator);
    // Skip the first argument (which is a path to the binary)
    _ = args.skip();
    // Try to get the second argument
    const output_dir_path = args.next() orelse {
        std.log.err("Please provide a path to the output directory.", .{});
        return error.Error;
    };
    // Create the directory if it doesn't exist,
    // then return a handle. Works for absolute
    // paths, too
    const cwd = std.fs.cwd();
    cwd.makeDir(output_dir_path) catch |fs_err| {
        switch (fs_err) {
            std.os.MakeDirError.PathAlreadyExists => {
                // Ask for a permission to overwrite the output directory
                try askOverwriteDir();
                // If the permission is granted, recursively delete
                // the contents of the output directory
                var iterable_dir = cwd.makeOpenPathIterable(output_dir_path, .{}) catch {
                    std.log.err(
                        "Couldn't iterate over the directory `{s}`.",
                        .{output_dir_path},
                    );
                    return error.Error;
                };
                defer iterable_dir.close();
                var iterator = iterable_dir.iterate();
                while (iterator.next() catch null) |entry| {
                    switch (entry.kind) {
                        .File => iterable_dir.dir.deleteFile(entry.name) catch {
                            std.log.warn(
                                "Couldn't delete file `{s}`.",
                                .{entry.name},
                            );
                        },
                        .Directory => iterable_dir.dir.deleteTree(entry.name) catch {
                            std.log.warn(
                                "Couldn't delete tree `{s}`.",
                                .{entry.name},
                            );
                        },
                        else => {},
                    }
                }
            },
            else => {
                std.log.err(
                    "Couldn't create the directory `{s}`.",
                    .{output_dir_path},
                );
                return error.Error;
            },
        }
    };
    return cwd.openDir(output_dir_path, .{}) catch {
        std.log.err(
            "Couldn't open the output directory `{s}`.",
            .{output_dir_path},
        );
        return error.Error;
    };
}
