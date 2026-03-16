const std = @import("std");
const Io = std.Io;
const vocab_loader = @import("vocab_loader.zig");
const models = @import("models/root.zig");

pub const default_vocab_path = "data/vocab.md";

pub fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const vocab_path = if (args.len > 1) args[1] else default_vocab_path;

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_writer.interface;

    var store: models.VocabularyStore = try vocab_loader.loadVocabFromFile(arena, io, vocab_path);
    defer store.deinit();

    const summary = try runQuiz(io, writer, &store);

    try writer.print("Summary: \nTime Cost: {}sec, Accuracy: {}%\n", .{summary.contTime, summary.accuracy});
    try writer.flush();
}

fn runQuiz(io: Io, writer: *Io.Writer, store: *const models.VocabularyStore) !models.Summary {
    var stdin_buffer: [256]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const reader = &stdin_reader.interface;

    try writer.writeAll("Type `exit` or `quit` to stop.\n\n");
    const start = std.Io.Clock.awake.now(io);
    var count: u16 = 0;
    var correctCount: u16 = 0;
    while (true) {
        const prompt = try chooseRandomEntry(io, store);

        try writer.print("Date: {s}\n", .{prompt.date});
        try writer.print("Word: {s}\n", .{prompt.entry.word});
        try writer.writeAll("Pronunciation: ");
        try writer.flush();

        const input = (try reader.takeDelimiter('\n')) orelse {
            try writer.writeAll("\nSession ended.\n");
            break;
        };
        const answer = std.mem.trim(u8, input, " \t\r");

        if (std.mem.eql(u8, answer, "exit") or std.mem.eql(u8, answer, "quit")) {
            try writer.writeAll("Session ended.\n");
            break;
        }

        count += 1;
        if (std.mem.eql(u8, answer, prompt.entry.pronunciation)) {
            correctCount += 1;
            try writer.writeAll("Correct!\n\n");
            continue;
        }

        try writer.print("Expected: {s}\n\n", .{prompt.entry.pronunciation});
    }
    const end = std.Io.Clock.awake.now(io);
    const elapsed = start.durationTo(end);
    const accuracy: u8 = if (count == 0)
        0
    else
        @intCast(@divTrunc(@as(u32, correctCount) * 100, @as(u32, count)));
    const summary: models.Summary = .{ .accuracy = accuracy, .contTime = elapsed.toSeconds() };
    
    return summary;
}

fn chooseRandomEntry(io: Io, store: *const models.VocabularyStore) !struct {
    date: []const u8,
    entry: models.Vocab,
} {
    const dates = store.by_date.keys();
    const entry_lists = store.by_date.values();

    var total_entries: usize = 0;
    for (entry_lists) |entries| {
        total_entries += entries.items.len;
    }

    if (total_entries == 0) {
        return error.EmptyVocabularyStore;
    }

    const random_source: std.Random.IoSource = .{ .io = io };
    const random = random_source.interface();
    var target_index = random.uintLessThan(usize, total_entries);

    for (dates, entry_lists) |date, entries| {
        if (target_index < entries.items.len) {
            return .{
                .date = date,
                .entry = entries.items[target_index],
            };
        }
        target_index -= entries.items.len;
    }

    unreachable;
}
