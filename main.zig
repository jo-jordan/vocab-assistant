const std = @import("std");
const debug = std.debug;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, "vocab.md", .{ .mode = .read_only });
    defer _ = file.close(io);
    debug.print("File Size: {!} \n", .{file.length(io)});
    
    var buffer:[128]u8 = undefined;
    var fileReader = file.readerStreaming(io, &buffer);
    const reader = &fileReader.interface;

    while(try reader.takeDelimiter('\n')) |line| {
        debug.print("Read Size: {}, line: {s}\n", .{reader.bufferedLen(), line} );
    }
}
