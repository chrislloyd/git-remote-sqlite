# git-remote-sqlite

[Latest release](https://github.com/chrislloyd/git-remote-sqlite/releases/latest) | [Changes](https://github.com/chrislloyd/git-remote-sqlite/commits/main) | [Source](https://github.com/chrislloyd/git-remote-sqlite)

---

**git-remote-sqlite** is a [Git protocol helper](https://git-scm.com/docs/gitremote-helpers) that helps you store a Git repository in a [SQLite](https://www.sqlite.org) database. Why would you want to do this?

1. **Simple Git hosting**. Hosting git repositories typically involves using a third-party forge like [GitHub](https://github.com) or [Sourcehut](https://sourcehut.org). These primarily provide value by handling the storage, networking, and access control complexity of hosting Git repositories. At a smaller scale, **git-remote-sqlite** (combined with other tools like [Litestream](https://litestream.io)) may be cheaper and practically easy enough to use.
2. **Self-contained application bundle**. While **git-remote-sqlite** isn't as powerful as Lisp/Smalltalk-style images, it does allow an application's data to be distributed alongside its code. What can you do with this? I don't know but it sounds cool!
3. **(Advanced) More control over workflows**. Leveraging Git hooks lets you transactionally automate code changes. Think Erlang/OTP's `code_change/3` but more generic.

## Installation

1. Prerequisites:

* [Git](https://git-scm.com) >= 1.6.6
* [SQLite](https://sqlite.org) >= 3.0.0

2. Download and extract the latest release for your platform:

   ```bash
   # macOS (Apple Silicon)
   curl -L https://github.com/chrislloyd/git-remote-sqlite/releases/latest/download/git-remote-sqlite-aarch64-macos.tar.gz | tar xz

   # Linux (x86_64)
   curl -L https://github.com/chrislloyd/git-remote-sqlite/releases/latest/download/git-remote-sqlite-x86_64-linux.tar.gz | tar xz
   ```

3. Move the binary to your `$PATH`:

   ```bash
   sudo mv git-remote-sqlite /usr/local/bin/
   ```

## Basic Usage

### 1. Push to/pull from the database

When `git-remote-sqlite` is in your $PATH, you can push your code to a local SQLite database. If it doesn't exist, it'll be created:

```bash
git push sqlite://myapp.db main
```

Pull it back:

```bash
git pull sqlite://myapp.db main
```

All done! Fancy.

### 2. Configure Repository Settings

You can configure server-side git settings. These don't currently affect any behavior.

```bash
# Set configuration variables (similar to editing server-side git config)
git-remote-sqlite config myapp.db receive.denyDeletes true
git-remote-sqlite config myapp.db receive.denyNonFastForwards true

# List all configured settings
git-remote-sqlite config myapp.db --list

# Get a specific setting value
git-remote-sqlite config myapp.db --get receive.denyDeletes

# Remove a setting
git-remote-sqlite config myapp.db --unset receive.denyDeletes
```

## How it works

**git-remote-sqlite** stores Git objects (commits, trees, blobs) as rows in SQLite tables. When you push to `sqlite://myapp.db`, Git objects are inserted into the database. When you pull, they're read back out.

The [database schema](docs/schema.md) includes:

- `git_objects` - stores all Git objects with their SHA, type, and data
- `git_refs` - tracks branches and tags
- `git_symbolic_refs` - handles HEAD and other symbolic references

Since it's just a SQLite database, you can query your repository with SQL, back it up with standard tools, or even replicate it with Litestream.

## FAQ

### Why not just use a bare Git repository?

Bare repos work great for traditional hosting, but SQLite gives you:
- Queryable data - find large objects, analyze commit patterns, or build
custom workflows with SQL
- Single-file deployment - one `.db` file instead of a directory tree
- Replication options - tools like Litestream can continuously replicate
SQLite to S3

### How does performance compare to regular Git?

For small-to-medium repositories, performance is comparable. The SQLite
overhead is minimal for most operations. However:
- Large repositories with thousands of objects may be slower
- Pack files aren't implemented yet, so storage is less efficient
- Clone operations might be slower than optimized Git servers

**git-remote-sqlite** is currently proitizing simplicity and trying new stuff over raw performance.

### Can I use this with existing Git workflows?

Yes! **git-remote-sqlite** is a standard Git remote helper. You can:
- Push/pull between SQLite and regular Git repos
- Use it alongside other remotes (GitHub, GitLab, etc.)
- Apply standard Git workflows (branches, merges, rebases)

### Is the database format stable?

The schema is documented in [docs/schema.md](docs/schema.md). While I may
add tables (like pack support), I'll try not to break existing tables without an automatic migration plan.

### What about security?

**git-remote-sqlite** provides no authentication or access control - it's
designed for local use or trusted environments. For remote access, you'd need
  to add your own security layer or use SQLite's built-in encryption
extensions.

### Should I use this for my companies Git Repo?

Probably not. **git-remote-sqlite** is not 1.0 yet. It _definitely_ has bugs, performance cliffs and unknown behavior that makes it unsuitable for anything other than disposable toys.

## TODO

- [ ] Git hook support
- [ ] Pack-file management
- [ ] Full support for protocol commands
- [ ] Performance profiling for large repos
