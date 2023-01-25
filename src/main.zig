const std = @import("std");

const gir = @import("girepository");

const emit = @import("emit/mod.zig");
const input = @import("input.zig");

/// Namespace in question
pub const target_namespace_name = "GIRepository";

/// Prepare output writers
const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

/// Override the default logger
pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const red = "\u{001b}[1;31m";
    const yellow = "\u{001b}[1;33m";
    const cyan = "\u{001b}[1;36m";
    const white = "\u{001b}[1;37m";
    const reset = "\u{001b}[m";
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

/// A callback in case of an interrupt
fn onInterrupt(signal: c_int) align(1) callconv(.C) void {
    _ = signal;
    std.os.exit(1);
}

/// Run the program
pub fn main() !void {
    // Setup an interrupt signal handler
    const sigaction = std.os.Sigaction{
        .handler = .{ .handler = onInterrupt },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
    try std.os.sigaction(std.os.SIG.INT, &sigaction, null);
    // Prepare an arena-wrapped allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    // Prepare an output directory
    var output_dir = input.getOutputDir(allocator) catch {
        std.log.err("Couldn't get the output directory.", .{});
        std.os.exit(1);
    };
    defer output_dir.close();
    // Get the singleton process-global default GIRepository
    var repository = gir.g_irepository_get_default();
    // Emit code from the target namespace
    emit.from(
        repository,
        target_namespace_name,
        &output_dir,
        allocator,
    ) catch {
        std.log.err("Couldn't emit code from the target namespace.", .{});
        std.os.exit(1);
    };
}
