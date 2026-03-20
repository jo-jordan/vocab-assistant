const std = @import("std");

pub const Vocab = struct {
    id: i64,
    word: []const u8,
    meaning_cn: []const u8,
    pronunciation: []const u8,
    review_streak: u16,
    total_reviews: u32,
    correct_reviews: u32,
    interval_seconds: i64,
    next_review_at: i64,
    last_reviewed_at: i64,

    pub fn deinit(self: Vocab, allocator: std.mem.Allocator) void {
        allocator.free(self.word);
        allocator.free(self.meaning_cn);
        allocator.free(self.pronunciation);
    }

    pub fn isDue(self: Vocab, now_ts: i64) bool {
        return self.next_review_at <= now_ts;
    }
};

pub const VocabularyStore = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Vocab),

    pub fn init(allocator: std.mem.Allocator) VocabularyStore {
        return .{
            .allocator = allocator,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *VocabularyStore) void {
        for (self.entries.items) |entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn append(self: *VocabularyStore, entry: Vocab) !void {
        try self.entries.append(self.allocator, entry);
    }

    pub fn len(self: *const VocabularyStore) usize {
        return self.entries.items.len;
    }
};
