const std = @import("std");
const Io = std.Io;
const vocab_loader = @import("vocab_loader.zig");

pub const default_vocab_path = "data/vocab.md";

pub fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const vocab_path = if (args.len > 1) args[1] else default_vocab_path;

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_writer.interface;

    try vocab_loader.writeFileToWriter(io, writer, vocab_path);
    try writer.flush();
}
