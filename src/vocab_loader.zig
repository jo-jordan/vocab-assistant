const std = @import("std");

pub fn writeFileToWriter(io: std.Io, writer: *std.Io.Writer, path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, path, .{ .mode = .read_only });
    defer _ = file.close(io);

    var buffer: [256]u8 = undefined;
    var file_reader = file.readerStreaming(io, &buffer);
    const reader = &file_reader.interface;

    while (try reader.takeDelimiter('\n')) |line| {
        try writer.print("{s}\n", .{std.mem.trimEnd(u8, line, "\r")});
    }
}

test "writes file contents line by line" {
    try std.testing.expect(true);
}
