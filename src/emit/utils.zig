const std = @import("std");

/// Convert a `snake_case` string to `camelCase` string
pub fn toCamelCase(
    slice: [:0]const u8,
    allocator: std.mem.Allocator,
) ![:0]const u8 {
    var buffer = try allocator.allocSentinel(u8, slice.len, 0);
    var change: bool = false;
    var shift: usize = 0;
    var total: usize = 0;
    for (slice) |char, i| {
        switch (char) {
            '_' => {
                shift += 1;
                change = true;
            },
            else => {
                total += 1;
                if (change) {
                    buffer[i - shift] = std.ascii.toUpper(char);
                    change = false;
                } else {
                    buffer[i - shift] = char;
                }
            },
        }
    }
    buffer[total] = 0;
    return buffer[0..total :0];
}
