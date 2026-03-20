const std = @import("std");
const models = @import("models/root.zig");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub fn openDatabase(allocator: std.mem.Allocator, path: []const u8) !*c.sqlite3 {
    const db_path = try allocator.dupeZ(u8, path);
    defer allocator.free(db_path);

    var db: ?*c.sqlite3 = null;
    const rc = c.sqlite3_open_v2(
        db_path.ptr,
        &db,
        c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE,
        null,
    );
    try checkResult(rc, db);
    errdefer _ = c.sqlite3_close(db);

    try ensureSchema(db.?);
    return db.?;
}

pub fn closeDatabase(db: *c.sqlite3) void {
    _ = c.sqlite3_close(db);
}

pub fn loadVocabFromDatabase(
    allocator: std.mem.Allocator,
    db: *c.sqlite3,
) !models.VocabularyStore {
    var store = models.VocabularyStore.init(allocator);
    errdefer store.deinit();

    const sql =
        \\SELECT rowid, word, meaning_cn, pronunciation,
        \\       review_streak, total_reviews, correct_reviews,
        \\       interval_seconds, next_review_at, last_reviewed_at
        \\FROM vocab
        \\ORDER BY rowid ASC;
    ;

    var statement: ?*c.sqlite3_stmt = null;
    try checkResult(c.sqlite3_prepare_v2(db, sql, -1, &statement, null), db);
    defer _ = c.sqlite3_finalize(statement);

    while (true) {
        const rc = c.sqlite3_step(statement);
        if (rc == c.SQLITE_DONE) break;
        if (rc != c.SQLITE_ROW) try checkResult(rc, db);

        try store.append(.{
            .id = c.sqlite3_column_int64(statement.?, 0),
            .word = try duplicateColumnText(allocator, statement.?, 1),
            .meaning_cn = try duplicateColumnText(allocator, statement.?, 2),
            .pronunciation = try duplicateColumnText(allocator, statement.?, 3),
            .review_streak = @intCast(c.sqlite3_column_int(statement.?, 4)),
            .total_reviews = @intCast(c.sqlite3_column_int(statement.?, 5)),
            .correct_reviews = @intCast(c.sqlite3_column_int(statement.?, 6)),
            .interval_seconds = c.sqlite3_column_int64(statement.?, 7),
            .next_review_at = c.sqlite3_column_int64(statement.?, 8),
            .last_reviewed_at = c.sqlite3_column_int64(statement.?, 9),
        });
    }

    return store;
}

pub fn insertVocab(db: *c.sqlite3, entry: models.Vocab) !void {
    const sql =
        \\INSERT OR IGNORE INTO vocab (
        \\    word, meaning_cn, pronunciation,
        \\    review_streak, total_reviews, correct_reviews,
        \\    interval_seconds, next_review_at, last_reviewed_at
        \\)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9);
    ;

    var statement: ?*c.sqlite3_stmt = null;
    try checkResult(c.sqlite3_prepare_v2(db, sql, -1, &statement, null), db);
    defer _ = c.sqlite3_finalize(statement);

    try bindText(statement.?, 1, entry.word);
    try bindText(statement.?, 2, entry.meaning_cn);
    try bindText(statement.?, 3, entry.pronunciation);
    try bindInt64(statement.?, 4, entry.review_streak);
    try bindInt64(statement.?, 5, entry.total_reviews);
    try bindInt64(statement.?, 6, entry.correct_reviews);
    try bindInt64(statement.?, 7, entry.interval_seconds);
    try bindInt64(statement.?, 8, entry.next_review_at);
    try bindInt64(statement.?, 9, entry.last_reviewed_at);

    const rc = c.sqlite3_step(statement);
    if (rc != c.SQLITE_DONE) try checkResult(rc, db);
}

pub fn updateReviewState(db: *c.sqlite3, entry: models.Vocab) !void {
    const sql =
        \\UPDATE vocab
        \\SET review_streak = ?1,
        \\    total_reviews = ?2,
        \\    correct_reviews = ?3,
        \\    interval_seconds = ?4,
        \\    next_review_at = ?5,
        \\    last_reviewed_at = ?6
        \\WHERE rowid = ?7;
    ;

    var statement: ?*c.sqlite3_stmt = null;
    try checkResult(c.sqlite3_prepare_v2(db, sql, -1, &statement, null), db);
    defer _ = c.sqlite3_finalize(statement);

    try bindInt64(statement.?, 1, entry.review_streak);
    try bindInt64(statement.?, 2, entry.total_reviews);
    try bindInt64(statement.?, 3, entry.correct_reviews);
    try bindInt64(statement.?, 4, entry.interval_seconds);
    try bindInt64(statement.?, 5, entry.next_review_at);
    try bindInt64(statement.?, 6, entry.last_reviewed_at);
    try bindInt64(statement.?, 7, entry.id);

    const rc = c.sqlite3_step(statement);
    if (rc != c.SQLITE_DONE) try checkResult(rc, db);
}

fn ensureSchema(db: *c.sqlite3) !void {
    if (try columnExists(db, "vocab", "prounonciation") and !(try columnExists(db, "vocab", "pronunciation"))) {
        try checkResult(
            c.sqlite3_exec(db, "ALTER TABLE vocab RENAME COLUMN prounonciation TO pronunciation;", null, null, null),
            db,
        );
    }

    const sql =
        \\CREATE TABLE IF NOT EXISTS vocab (
        \\    word TEXT NOT NULL,
        \\    meaning_cn TEXT NOT NULL,
        \\    pronunciation TEXT NOT NULL,
        \\    review_streak INTEGER NOT NULL DEFAULT 0,
        \\    total_reviews INTEGER NOT NULL DEFAULT 0,
        \\    correct_reviews INTEGER NOT NULL DEFAULT 0,
        \\    interval_seconds INTEGER NOT NULL DEFAULT 0,
        \\    next_review_at INTEGER NOT NULL DEFAULT 0,
        \\    last_reviewed_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE UNIQUE INDEX IF NOT EXISTS idx_vocab_unique
        \\ON vocab (word, meaning_cn, pronunciation);
    ;

    try checkResult(c.sqlite3_exec(db, sql, null, null, null), db);
    try ensureColumn(db, "review_streak", "INTEGER NOT NULL DEFAULT 0");
    try ensureColumn(db, "total_reviews", "INTEGER NOT NULL DEFAULT 0");
    try ensureColumn(db, "correct_reviews", "INTEGER NOT NULL DEFAULT 0");
    try ensureColumn(db, "interval_seconds", "INTEGER NOT NULL DEFAULT 0");
    try ensureColumn(db, "next_review_at", "INTEGER NOT NULL DEFAULT 0");
    try ensureColumn(db, "last_reviewed_at", "INTEGER NOT NULL DEFAULT 0");
}

fn ensureColumn(db: *c.sqlite3, column_name: []const u8, column_definition: []const u8) !void {
    if (try columnExists(db, "vocab", column_name)) return;

    var sql_buffer: [256]u8 = undefined;
    const sql = try std.fmt.bufPrintZ(
        &sql_buffer,
        "ALTER TABLE vocab ADD COLUMN {s} {s};",
        .{ column_name, column_definition },
    );

    try checkResult(c.sqlite3_exec(db, sql.ptr, null, null, null), db);
}

fn columnExists(db: *c.sqlite3, table_name: []const u8, column_name: []const u8) !bool {
    if (!std.mem.eql(u8, table_name, "vocab")) return false;

    const pragma = "PRAGMA table_info(vocab);";
    var statement: ?*c.sqlite3_stmt = null;
    defer {
        if (statement) |stmt| {
            _ = c.sqlite3_finalize(stmt);
        }
    }
    try checkResult(c.sqlite3_prepare_v2(db, pragma, -1, &statement, null), db);

    while (true) {
        const rc = c.sqlite3_step(statement);
        if (rc == c.SQLITE_DONE) return false;
        if (rc != c.SQLITE_ROW) try checkResult(rc, db);

        const current_name = c.sqlite3_column_text(statement.?, 1) orelse continue;
        const current_len: usize = @intCast(c.sqlite3_column_bytes(statement.?, 1));
        if (std.mem.eql(u8, current_name[0..current_len], column_name)) {
            return true;
        }
    }
}

fn bindText(statement: *c.sqlite3_stmt, index: c_int, value: []const u8) !void {
    const rc = c.sqlite3_bind_text(
        statement,
        index,
        value.ptr,
        @intCast(value.len),
        null,
    );
    if (rc != c.SQLITE_OK) return error.SqliteBindFailed;
}

fn bindInt64(statement: *c.sqlite3_stmt, index: c_int, value: anytype) !void {
    const rc = c.sqlite3_bind_int64(statement, index, @intCast(value));
    if (rc != c.SQLITE_OK) return error.SqliteBindFailed;
}

fn duplicateColumnText(
    allocator: std.mem.Allocator,
    statement: *c.sqlite3_stmt,
    column_index: c_int,
) ![]const u8 {
    const text_ptr = c.sqlite3_column_text(statement, column_index) orelse return error.NullColumnValue;
    const length: usize = @intCast(c.sqlite3_column_bytes(statement, column_index));
    return allocator.dupe(u8, text_ptr[0..length]);
}

fn checkResult(rc: c_int, db: ?*c.sqlite3) !void {
    if (rc == c.SQLITE_OK or rc == c.SQLITE_DONE or rc == c.SQLITE_ROW) return;

    if (db) |database| {
        std.log.err("sqlite error: {s}", .{c.sqlite3_errmsg(database)});
    }
    return error.SqliteFailure;
}
