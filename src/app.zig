const std = @import("std");
const Io = std.Io;
const vocab_loader = @import("vocab_loader.zig");
const models = @import("models/root.zig");

pub const default_db_path = "data/vocab.db";

const Mode = enum {
    review,
    add,
};

const ansi = struct {
    const reset = "\x1b[0m";
    const green = "\x1b[32m";
    const red = "\x1b[31m";
    const orange = "\x1b[33m";
};

pub fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const db_path = if (args.len > 1) args[1] else default_db_path;

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_writer.interface;

    const db = try vocab_loader.openDatabase(arena, db_path);
    defer vocab_loader.closeDatabase(db);

    var stdin_buffer: [256]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const reader = &stdin_reader.interface;

    const mode = try promptForMode(writer, reader);
    switch (mode) {
        .review => {
            var store = try vocab_loader.loadVocabFromDatabase(arena, db);
            defer store.deinit();

            const summary = try runReviewMode(io, writer, reader, &store);
            try writer.print(
                "Summary:\nTime Cost: {} sec\nAccuracy: {s}{}%{s}\n",
                .{ summary.contTime, accuracyColor(summary.accuracy), summary.accuracy, ansi.reset },
            );
        },
        .add => try runAddMode(arena, writer, reader, db),
    }

    try writer.flush();
}

fn promptForMode(writer: *Io.Writer, reader: *Io.Reader) !Mode {
    while (true) {
        try writer.writeAll("Select mode:\n1. vocab review\n2. vocab add\n> ");
        try writer.flush();

        const input = (try reader.takeDelimiter('\n')) orelse return error.EndOfStream;
        const answer = std.mem.trim(u8, input, " \t\r");

        if (std.mem.eql(u8, answer, "1") or std.mem.eql(u8, answer, "review")) return .review;
        if (std.mem.eql(u8, answer, "2") or std.mem.eql(u8, answer, "add")) return .add;

        try writer.writeAll("Please choose `1` for review or `2` for add.\n\n");
    }
}

fn runReviewMode(
    io: Io,
    writer: *Io.Writer,
    reader: *Io.Reader,
    store: *const models.VocabularyStore,
) !models.Summary {
    if (store.len() == 0) {
        try writer.writeAll("No vocab found. Switch to add mode first.\n");
        return .{ .contTime = 0, .accuracy = 0 };
    }

    try writer.writeAll("Type `exit` or `quit` to stop.\n\n");
    const start = std.Io.Clock.awake.now(io);
    var count: u16 = 0;
    var correct_count: u16 = 0;

    while (true) {
        const entry = chooseRandomEntry(io, store);

        try writer.print("Word: {s}\n", .{entry.word});
        try writer.print("Meaning (CN): {s}\n", .{entry.meaning_cn});
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
        if (std.mem.eql(u8, answer, entry.pronunciation)) {
            correct_count += 1;
            try writer.print("{s}Correct!{s}\n\n", .{ ansi.green, ansi.reset });
            continue;
        }

        try writer.print("{s}Incorrect!{s} Expected: {s}\n\n", .{ ansi.red, ansi.reset, entry.pronunciation });
    }

    const end = std.Io.Clock.awake.now(io);
    const elapsed = start.durationTo(end);
    const accuracy: u8 = if (count == 0)
        0
    else
        @intCast(@divTrunc(@as(u32, correct_count) * 100, @as(u32, count)));

    return .{
        .contTime = elapsed.toSeconds(),
        .accuracy = accuracy,
    };
}

fn runAddMode(
    allocator: std.mem.Allocator,
    writer: *Io.Writer,
    reader: *Io.Reader,
    db: anytype,
) !void {
    try writer.writeAll("Add mode. Type `exit` or `quit` at any prompt to stop.\n\n");

    while (true) {
        const word = (try promptForOwnedField(allocator, writer, reader, "Word: ")) orelse {
            try writer.writeAll("Session ended.\n");
            return;
        };
        defer allocator.free(word);

        const meaning_cn = (try promptForOwnedField(allocator, writer, reader, "Meaning (CN): ")) orelse {
            try writer.writeAll("Session ended.\n");
            return;
        };
        defer allocator.free(meaning_cn);

        const pronunciation = (try promptForOwnedField(allocator, writer, reader, "Pronunciation: ")) orelse {
            try writer.writeAll("Session ended.\n");
            return;
        };
        defer allocator.free(pronunciation);

        const entry = models.Vocab{
            .word = try allocator.dupe(u8, word),
            .meaning_cn = try allocator.dupe(u8, meaning_cn),
            .pronunciation = try allocator.dupe(u8, pronunciation),
        };
        defer entry.deinit(allocator);

        try vocab_loader.insertVocab(db, entry);
        try writer.writeAll("Saved.\n\n");
    }
}

fn promptForOwnedField(
    allocator: std.mem.Allocator,
    writer: *Io.Writer,
    reader: *Io.Reader,
    label: []const u8,
) !?[]const u8 {
    try writer.writeAll(label);
    try writer.flush();

    const input = (try reader.takeDelimiter('\n')) orelse return null;
    const answer = std.mem.trim(u8, input, " \t\r");

    if (std.mem.eql(u8, answer, "exit") or std.mem.eql(u8, answer, "quit")) {
        return null;
    }

    const owned = try allocator.dupe(u8, answer);
    return owned;
}

fn chooseRandomEntry(io: Io, store: *const models.VocabularyStore) models.Vocab {
    const random_source: std.Random.IoSource = .{ .io = io };
    const random = random_source.interface();
    const index = random.uintLessThan(usize, store.entries.items.len);
    return store.entries.items[index];
}

fn accuracyColor(accuracy: u8) []const u8 {
    if (accuracy < 60) return ansi.red;
    if (accuracy < 80) return ansi.orange;
    return ansi.green;
}
