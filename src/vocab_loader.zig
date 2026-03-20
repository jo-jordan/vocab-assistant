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
        \\SELECT word, meaning_cn, pronunciation
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
            .word = try duplicateColumnText(allocator, statement.?, 0),
            .meaning_cn = try duplicateColumnText(allocator, statement.?, 1),
            .pronunciation = try duplicateColumnText(allocator, statement.?, 2),
        });
    }

    return store;
}

pub fn insertVocab(db: *c.sqlite3, entry: models.Vocab) !void {
    const sql =
        \\INSERT OR IGNORE INTO vocab (word, meaning_cn, pronunciation)
        \\VALUES (?1, ?2, ?3);
    ;

    var statement: ?*c.sqlite3_stmt = null;
    try checkResult(c.sqlite3_prepare_v2(db, sql, -1, &statement, null), db);
    defer _ = c.sqlite3_finalize(statement);

    try bindText(statement.?, 1, entry.word);
    try bindText(statement.?, 2, entry.meaning_cn);
    try bindText(statement.?, 3, entry.pronunciation);

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
        \\    pronunciation TEXT NOT NULL
        \\);
        \\CREATE UNIQUE INDEX IF NOT EXISTS idx_vocab_unique
        \\ON vocab (word, meaning_cn, pronunciation);
    ;

    try checkResult(c.sqlite3_exec(db, sql, null, null, null), db);
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
