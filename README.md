# Vocab Assistant

`vocab-assistant` is a small Zig command-line tool for streaming a Markdown vocabulary list to standard output.

## Project Structure

- `build.zig`: Zig build configuration and developer commands.
- `build.zig.zon`: package metadata.
- `src/main.zig`: CLI entrypoint.
- `src/app.zig`: application orchestration.
- `src/vocab_loader.zig`: vocabulary file loading and output logic.
- `src/root.zig`: package exports for tests and future reuse.
- `data/vocab.md`: default vocabulary source file.

## Requirements

- Zig `0.16.0-dev.2905+5d71e3051`

## Usage

Run with the default vocabulary file:

```bash
zig build run
```

Run with a custom Markdown file:

```bash
zig build run -- path/to/vocab.md
```

## Development

Build the executable:

```bash
zig build
```

Run tests:

```bash
zig build test
```
