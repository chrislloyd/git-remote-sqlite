# Style Guide

Coding conventions for git-remote-sqlite.

## Files

File names should be simple and descriptive: `main.zig`, `git.zig`, `sqlite.zig`. Each file should have a single responsibility and act as a namespace. Don't bury the lede - organize files so that the most important functions and declarations are at the top.

Separate public and private functions clearly. Order imports with standard library first, then relative imports, then C imports last. Within each section, organize alphabetically.

```zig
const std = @import("std");                    // Standard library first
const config = @import("./config.zig");        // Local imports
const c = @cImport({ @cInclude("header.h") }); // C imports last
```

## Naming Conventions

Functions use **camelCase**: `parseCommand()`, `writeResponse()`, `handleCapabilities()`.

Variables use **snake_case**: `null_terminated_path`, `parsed_url`, `object_data`.

Types and structs use **PascalCase**: `RemoteUrl`, `GitError`, `ObjectData`. Make struct names descriptive: `ParsedRefspec`, `GitObjectWriter`, `ProgressMessage`. Use tagged unions for variants: `Command`, `Response`, `Result`.

## Function Design

Be explicit over implicit - make intentions clear in code. Follow single responsibility - each function and module should have one job. Practice resource safety by always cleaning up resources, especially in error cases.

Write documentation as you write code. Use test-driven development to validate expected behavior.

Functions should do one thing well. Don't provide default arguments - prefer that callsites always provide defaults.

Try to keep lists of things (struct keys, switch cases) sorted alphabetically.

Use `@""` syntax for reserved words rather than alternatives. Leverage comptime for validation where appropriate.

## Testing

Keep unit tests in the same file as implementation when possible. Each test should have a single, clear purpose. Err on fewer high-signal tests than lots of low-value tests - 100% coverage isn't the goal.

Always have an e2e test for any command or behavior claimed in the README.

## Comments

Use `// --` for section breaks in files. This keeps visual noise low while providing clear section delineation.
