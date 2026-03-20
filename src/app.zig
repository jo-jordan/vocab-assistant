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

            const summary = try runReviewMode(io, writer, reader, db, &store);
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
    db: anytype,
    store: *models.VocabularyStore,
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
        const now_ts = currentUnixSeconds(io);
        const entry = chooseDueEntry(io, store, now_ts) orelse {
            const next_ts = nextReviewAt(store) orelse {
                try writer.writeAll("No more cards are available right now.\n");
                break;
            };
            const wait_seconds = @max(next_ts - now_ts, 0);
            try writer.print(
                "No cards are due right now. Next review in about {} minute(s).\n",
                .{@divTrunc(wait_seconds + 59, 60)},
            );
            break;
        };

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
        const was_correct = std.mem.eql(u8, answer, entry.pronunciation);
        applyReviewResult(entry, was_correct, now_ts);
        try vocab_loader.updateReviewState(db, entry.*);

        if (was_correct) {
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
            .id = 0,
            .word = try allocator.dupe(u8, word),
            .meaning_cn = try allocator.dupe(u8, meaning_cn),
            .pronunciation = try allocator.dupe(u8, pronunciation),
            .review_streak = 0,
            .total_reviews = 0,
            .correct_reviews = 0,
            .interval_seconds = 0,
            .next_review_at = 0,
            .last_reviewed_at = 0,
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

fn chooseDueEntry(io: Io, store: *models.VocabularyStore, now_ts: i64) ?*models.Vocab {
    const random_source: std.Random.IoSource = .{ .io = io };
    const random = random_source.interface();
    var best_entry: ?*models.Vocab = null;
    var best_score: i128 = std.math.minInt(i128);

    for (store.entries.items) |*entry| {
        if (!entry.isDue(now_ts)) continue;

        const score = duePriorityScore(entry.*, now_ts) + @as(i128, random.uintLessThan(u16, 17));
        if (best_entry == null or score > best_score) {
            best_entry = entry;
            best_score = score;
        }
    }

    return best_entry;
}

fn accuracyColor(accuracy: u8) []const u8 {
    if (accuracy < 60) return ansi.red;
    if (accuracy < 80) return ansi.orange;
    return ansi.green;
}

fn currentUnixSeconds(io: Io) i64 {
    return std.Io.Clock.real.now(io).toSeconds();
}

fn nextReviewAt(store: *const models.VocabularyStore) ?i64 {
    var result: ?i64 = null;
    for (store.entries.items) |entry| {
        if (result) |current| {
            result = @min(current, entry.next_review_at);
        } else {
            result = entry.next_review_at;
        }
    }
    return result;
}

fn applyReviewResult(entry: *models.Vocab, was_correct: bool, now_ts: i64) void {
    entry.total_reviews += 1;
    entry.last_reviewed_at = now_ts;

    if (was_correct) {
        entry.correct_reviews += 1;
        entry.review_streak += 1;
        entry.interval_seconds = nextIntervalSeconds(entry.review_streak, entry.interval_seconds);
    } else {
        entry.review_streak = 0;
        entry.interval_seconds = 10 * 60;
    }

    entry.next_review_at = now_ts + entry.interval_seconds;
}

fn nextIntervalSeconds(streak: u16, previous_interval: i64) i64 {
    return switch (streak) {
        1 => 4 * 60 * 60,
        2 => 24 * 60 * 60,
        3 => 3 * 24 * 60 * 60,
        4 => 7 * 24 * 60 * 60,
        5 => 14 * 24 * 60 * 60,
        else => @min(if (previous_interval == 0) 30 * 24 * 60 * 60 else previous_interval * 2, 90 * 24 * 60 * 60),
    };
}

fn duePriorityScore(entry: models.Vocab, now_ts: i64) i128 {
    const overdue_seconds = @max(now_ts - entry.next_review_at, 0);
    const overdue_minutes = @divTrunc(overdue_seconds, 60);
    const streak_penalty = @as(i128, entry.review_streak) * 600;
    const review_bonus: i128 = if (entry.total_reviews == 0) 20_000 else 0;
    const accuracy_penalty = if (entry.total_reviews == 0)
        0
    else
        @as(i128, @divTrunc(@as(i128, entry.correct_reviews) * 10_000, entry.total_reviews));
    const short_interval_bonus: i128 = if (entry.interval_seconds == 0)
        5_000
    else
        @as(i128, @divTrunc(7 * 24 * 60 * 60, @max(entry.interval_seconds, 1)));

    return @as(i128, overdue_minutes) * 100 + review_bonus + short_interval_bonus - streak_penalty - accuracy_penalty;
}
