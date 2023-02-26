const std = @import("std");

const clap = @import("clap");
const gir = @import("girepository");

const Repository = @import("repository.zig").Repository;
const input = @import("input.zig");

const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

/// ANSI escape codes
const red = "\u{001b}[1;31m";
const green = "\u{001b}[1;32m";
const yellow = "\u{001b}[1;33m";
const cyan = "\u{001b}[1;36m";
const white = "\u{001b}[1;37m";
const reset = "\u{001b}[m";

/// Override the default logger
pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime switch (message_level) {
        .err => red ++ "ERROR" ++ reset,
        .warn => yellow ++ "WARNING" ++ reset,
        .info => white ++ "INFO" ++ reset,
        .debug => cyan ++ "DEBUG" ++ reset,
    };
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    nosuspend stderr.print(level_txt ++ prefix ++ format ++ "\n", args) catch return;
}

const Args = struct {
    target_namespace_name: []const u8,
    output_directory_path: []const u8,
};

const Params = clap.parseParamsComptime(
    \\    --help
    \\      Display this help and exit.
    \\
    \\-t, --target <str>
    \\      Target namespace name.
    \\
    \\-o, --output <str>
    \\      Output directory path.
    \\
);

fn parseArgs() !Args {
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &Params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        var longest = diag.name.longest();
        if (longest.kind == .positional)
            longest.name = diag.arg;

        switch (err) {
            error.DoesntTakeValue => std.log.err(
                "The argument '{s}{s}' does not take a value.",
                .{ longest.kind.prefix(), longest.name },
            ),
            error.MissingValue => std.log.err(
                "The argument '{s}{s}' requires a value but none was supplied.",
                .{ longest.kind.prefix(), longest.name },
            ),
            error.InvalidArgument => std.log.err(
                "Invalid argument '{s}{s}'.",
                .{ longest.kind.prefix(), longest.name },
            ),
            else => std.log.err(
                "Error while parsing arguments: {s}\n",
                .{@errorName(err)},
            ),
        }
        return error.Error;
    };
    defer res.deinit();

    if (res.args.help) {
        try stdout.print("{s}\n{s}\n{s}\n\n{s}", .{
            green ++ "zig-gir-ffi" ++ reset ++ " 0.1.0",
            "Pavel Sobolev <paveloom@riseup.net>",
            "Generate FFI bindings for Zig using GObject Introspection",
            "\u{001b}[0;33mOPTIONS:\u{001b}[m\n",
        });
        try clap.help(stdout, clap.Help, &Params, .{});
        std.os.exit(0);
    }

    const target_namespace_name = res.args.target orelse {
        std.log.err("A name of the target namespace is required.", .{});
        std.os.exit(1);
    };
    const output_directory_path = res.args.output orelse {
        std.log.err("A path to the output directory is required.", .{});
        std.os.exit(1);
    };

    return Args{
        .target_namespace_name = target_namespace_name,
        .output_directory_path = output_directory_path,
    };
}

fn setupInterrupt() !void {
    const sigaction = std.os.Sigaction{
        .handler = .{ .handler = onInterrupt },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
    try std.os.sigaction(std.os.SIG.INT, &sigaction, null);
}

fn onInterrupt(signal: c_int) align(1) callconv(.C) void {
    _ = signal;
    std.os.exit(1);
}

pub fn main() !void {
    const args = parseArgs() catch {
        std.log.err("Couldn't parse the arguments.", .{});
        std.os.exit(1);
    };

    try setupInterrupt();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var output_dir = input.getOutputDir(args.output_directory_path) catch {
        std.log.err("Couldn't get the output directory.", .{});
        std.os.exit(1);
    };
    defer output_dir.close();

    const repository = Repository.load(
        args.target_namespace_name,
        &output_dir,
        allocator,
    ) catch {
        std.log.err("Couldn't load the repository.", .{});
        std.os.exit(1);
    };
    defer repository.cleanup();

    repository.emit() catch {
        std.log.err("Couldn't emit code from the repository.", .{});
        std.os.exit(1);
    };
}
