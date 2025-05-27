# Development

### Prerequisites

* [Zig](https://ziglang.org) 0.14.0
* [SQLite](https://www.sqlite.org) >= 3.20.0
* [libgit2](https://libgit2.org) >= 1.0.0

## Building

1. Clone the repository:

   ```bash
   git clone https://github.com/chrislloyd/git-remote-sqlite.git
   cd git-remote-sqlite
   ```

2. Build the binary using Zig:

   ```bash
   zig build
   ```

3. Copy the binary to your path:

   ```bash
   sudo cp zig-out/bin/git-remote-sqlite /usr/local/bin/
   ```

4. The installation is complete. The binary functions as both a standalone command and as a Git remote helper.

## Testing

```shell
zig build test # all
zig build test:unit
zig build test:e2e
```
