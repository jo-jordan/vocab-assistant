const std = @import("std");
const models = @import("models/root.zig");

pub fn loadVocabFromFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !models.VocabularyStore {
    var store = models.VocabularyStore.init(allocator);
    errdefer store.deinit();

    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, path, .{ .mode = .read_only });
    defer _ = file.close(io);

    var buffer: [256]u8 = undefined;
    var file_reader = file.readerStreaming(io, &buffer);
    const reader = &file_reader.interface;
    var current_date: ?[]const u8 = null;

    while (try reader.takeDelimiter('\n')) |line| {
        try parseLine(allocator, std.mem.trimEnd(u8, line, "\r"), &store, &current_date);
    }

    if (reader.bufferedLen() > 0) {
        const trailing_line = try reader.peek(reader.bufferedLen());
        try parseLine(allocator, std.mem.trimEnd(u8, trailing_line, "\r"), &store, &current_date);
    }

    return store;
}

pub fn writeStoreToWriter(writer: *std.Io.Writer, store: *const models.VocabularyStore) !void {
    const dates = store.by_date.keys();
    const entry_lists = store.by_date.values();

    for (dates, entry_lists, 0..) |date, entries, index| {
        if (index > 0) {
            try writer.writeAll("\n");
        }

        try writer.print("# {s}\n\n", .{date});
        for (entries.items) |entry| {
            try writer.print("- {s}｜{s}\n", .{ entry.word, entry.pronunciation });
        }
    }
}

fn parseLine(
    allocator: std.mem.Allocator,
    line: []const u8,
    store: *models.VocabularyStore,
    current_date: *?[]const u8,
) !void {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return;

    if (std.mem.startsWith(u8, trimmed, "# ")) {
        current_date.* = try store.ensureDate(trimmed[2..]);
        return;
    }

    if (!std.mem.startsWith(u8, trimmed, "- ")) return;
    const date = current_date.* orelse return error.MissingDateHeader;
    const entry = try parseEntry(allocator, trimmed[2..]);
    errdefer entry.deinit(allocator);
    try store.append(date, entry);
}

fn parseEntry(allocator: std.mem.Allocator, line: []const u8) !models.Vocab {
    const separator = std.mem.indexOf(u8, line, "｜") orelse return error.InvalidVocabLine;
    const word = std.mem.trim(u8, line[0..separator], " \t");
    const pronunciation = std.mem.trim(u8, line[separator + "｜".len ..], " \t");

    if (word.len == 0 or pronunciation.len == 0) {
        return error.InvalidVocabLine;
    }

    return .{
        .word = try allocator.dupe(u8, word),
        .pronunciation = try allocator.dupe(u8, pronunciation),
    };
}

test "loads vocab entries into memory by date" {
    const allocator = std.testing.allocator;
    var store = models.VocabularyStore.init(allocator);
    defer store.deinit();

    var current_date: ?[]const u8 = null;
    try parseLine(allocator, "# 2026-03-12", &store, &current_date);
    try parseLine(allocator, "- 立ち入り｜たちいり", &store, &current_date);
    try parseLine(allocator, "- 宣告｜せんこく", &store, &current_date);

    try std.testing.expectEqual(@as(usize, 1), store.by_date.count());
    const entries = store.by_date.get("2026-03-12").?;
    try std.testing.expectEqual(@as(usize, 2), entries.items.len);
    try std.testing.expectEqualStrings("立ち入り", entries.items[0].word);
    try std.testing.expectEqualStrings("せんこく", entries.items[1].pronunciation);
}

test "rejects vocab entries before a date header" {
    const allocator = std.testing.allocator;
    var store = models.VocabularyStore.init(allocator);
    defer store.deinit();

    var current_date: ?[]const u8 = null;
    try std.testing.expectError(
        error.MissingDateHeader,
        parseLine(allocator, "- 立ち入り｜たちいり", &store, &current_date),
    );
}
