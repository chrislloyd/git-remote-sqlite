# Development

## Stack

* [Zig](https://ziglang.org) 0.14.0
* [SQLite](https://www.sqlite.org) >= 3.20.0
* [libgit2](https://libgit2.org) >= 1.0.0

## Building

Build the project using Zig's build system:

```bash
zig build
```

The binary will be created at `zig-out/bin/git-remote-sqlite`.

## Testing

```shell
zig build test # all
zig build test:unit
zig build test:e2e
```
