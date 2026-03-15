const std = @import("std");

pub const Vocab = struct {
    word: []const u8,
    pronunciation: []const u8,

    pub fn deinit(self: Vocab, allocator: std.mem.Allocator) void {
        allocator.free(self.word);
        allocator.free(self.pronunciation);
    }
};

pub const VocabList = std.ArrayList(Vocab);

pub const VocabularyStore = struct {
    allocator: std.mem.Allocator,
    by_date: std.StringArrayHashMap(VocabList),

    pub fn init(allocator: std.mem.Allocator) VocabularyStore {
        return .{
            .allocator = allocator,
            .by_date = .init(allocator),
        };
    }

    pub fn deinit(self: *VocabularyStore) void {
        const keys = self.by_date.keys();
        const values = self.by_date.values();

        for (keys, values) |date, *entries| {
            self.allocator.free(date);
            for (entries.items) |entry| {
                entry.deinit(self.allocator);
            }
            entries.deinit(self.allocator);
        }

        self.by_date.deinit();
    }

    pub fn ensureDate(self: *VocabularyStore, date: []const u8) ![]const u8 {
        const owned_date = try self.allocator.dupe(u8, date);
        const result = try self.by_date.getOrPut(owned_date);

        if (result.found_existing) {
            self.allocator.free(owned_date);
        } else {
            result.value_ptr.* = .empty;
        }

        return result.key_ptr.*;
    }

    pub fn append(self: *VocabularyStore, date: []const u8, entry: Vocab) !void {
        const entries = self.by_date.getPtr(date) orelse return error.UnknownDate;
        try entries.append(self.allocator, entry);
    }
};
