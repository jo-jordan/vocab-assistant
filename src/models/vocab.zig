const std = @import("std");

pub const Vocab = struct {
    word: []const u8,
    meaning_cn: []const u8,
    pronunciation: []const u8,

    pub fn deinit(self: Vocab, allocator: std.mem.Allocator) void {
        allocator.free(self.word);
        allocator.free(self.meaning_cn);
        allocator.free(self.pronunciation);
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
