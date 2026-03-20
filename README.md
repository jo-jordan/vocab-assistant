# Vocab Assistant

`vocab-assistant` is a Zig command-line app for storing vocabulary in SQLite and reviewing it interactively.

## Project Structure

- `build.zig`: Zig build configuration and sqlite linking.
- `build.zig.zon`: package metadata.
- `src/main.zig`: CLI entrypoint.
- `src/app.zig`: startup menu, review mode, and add mode.
- `src/vocab_loader.zig`: SQLite schema setup, reads, and inserts.
- `src/models`: application data models.
- `data/vocab.db`: default SQLite database file, created automatically on first run.

## Database Schema

Table name: `vocab`

Fields:

- `word`
- `meaning_cn`
- `pronunciation`

## Usage

Run with the default database:

```bash
zig build run
```

Run with a custom database path:

```bash
zig build run -- path/to/vocab.db
```

When the app starts, choose one of these modes:

- `vocab review`: quiz mode using the saved vocabulary
- `vocab add`: insert new entries into SQLite

## Development

```bash
zig build
zig build test
```
