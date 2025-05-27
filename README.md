# git-remote-sqlite

- [Latest release](https://github.com/chrislloyd/git-remote-sqlite/releases/latest)
- [Latest changes](https://github.com/chrislloyd/git-remote-sqlite/commits/main)
- [Source code](https://github.com/chrislloyd/git-remote-sqlite)

---

**git-remote-sqlite(1)** is a [Git protocol helper](https://git-scm.com/docs/gitremote-helpers) that helps you store a Git repository in a [SQLite](https://www.sqlite.org) database. Why would you want to do this?

1. **Simple Git hosting**. Hosting git repositories typically involves using a third-party forge like GitHub or Sourcehut. These provide value by automating hosting NFS mounts and providing a web interface for collaboration.
2. **Self-contained application bundle**. It serves as both a Git repository hosting alternative and enables Lisp/Smalltalk-style development images where code and its runtime state coexist.
3. **(Advanced) More control over automation**. Leveraging Git hooks lets you transactionally automate tasks like migrations.
4. **(Advanced) Build your own workflows**. An application can be built that is self-updating - you don't need to rely on pull-requests or emails etc. to update your application, you can easily build updating itself into your application.

## Installation

### Prerequisites

- Git (version 2.25+)
- SQLite (version 3.30+)
- Zig (version 0.14.0) - only needed if building from source

### Using Pre-built Binaries (Recommended)

1. Download the latest release for your platform:

   ```bash
   # macOS
   curl -L https://github.com/chrislloyd/git-remote-sqlite/releases/latest/download/git-remote-sqlite-macos -o git-remote-sqlite

   # Linux
   curl -L https://github.com/chrislloyd/git-remote-sqlite/releases/latest/download/git-remote-sqlite-linux -o git-remote-sqlite
   ```

2. Make the binary executable:

   ```bash
   chmod +x git-remote-sqlite
   ```

3. Move the binary to your `$PATH`:

   ```bash
   sudo mv git-remote-sqlite /usr/local/bin/
   ```

4. The installation is complete. The binary functions as both a standalone command and as a Git remote helper.

### Building from Source

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

## Basic Usage

### 1. Configure Repository Settings

You can configure server-side git settings stored in the SQLite database:

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

These settings are stored in the `git_config` table and affect how git operations are processed when interacting with the SQLite repository.

### 2. Push Code to the Database (Coming Soon)

Push your code to the SQLite database:

```bash
git push sqlite://myapp.db main
```

### 3. Use as a Git Remote (Coming Soon)

Add the database as a git remote:

```bash
# In your existing git repository
git remote add origin sqlite://myapp.db

# Note: 'origin' is just a name for the remote - you can use any name you prefer
```

### 4. Checkout Code from the Database (Coming Soon)

Checkout a specific commit from the database:

```bash
git checkout sqlite://myapp.db main
```

This will extract the specified commit to the current directory.

## Development Status

Currently implemented:
- [x] Configuration management (set, get, list, unset)
- [ ] Git remote helper protocol (push/pull functionality)
- [ ] Git hooks
- [ ] Pack file management (tables defined but not yet implemented)

## Database Schema

**git_objects**: Stores git objects (blobs, trees, commits, tags)

| Column | Type | Constraints | Description |
|--|--|--|--|
| `sha` | TEXT | PRIMARY KEY, CHECK(length(sha) = 40 AND sha GLOB '[0-9a-f]*') | Object SHA hash |
| `type` | TEXT | NOT NULL, CHECK(type IN ('blob', 'tree', 'commit', 'tag')) | Object type (blob, tree, commit, tag) |
| `data` | BLOB | NOT NULL | Object content |

*Indexes:*
- `CREATE INDEX idx_git_objects_type ON git_objects(type);` - For efficient queries by object type

**git_refs**: Stores git references

| Column | Type | Constraints | Description |
|--|--|--|--|
| `name` | TEXT | PRIMARY KEY, CHECK(name GLOB 'refs/*') | Reference name (e.g., 'refs/heads/main') |
| `sha` | TEXT | NOT NULL, FOREIGN KEY REFERENCES git_objects(sha) | Commit SHA the ref points to |
| `type` | TEXT | NOT NULL, CHECK(type IN ('branch', 'tag', 'remote')) | Reference type (branch, tag, remote) |

*Indexes:*
- `CREATE INDEX idx_git_refs_sha ON git_refs(sha);` - For finding all refs pointing to a specific commit

**git_symbolic_refs**: Stores symbolic references (like HEAD)

| Column | Type | Constraints | Description |
|--|--|--|--|
| `name` | TEXT | PRIMARY KEY | Symbolic reference name (e.g., 'HEAD') |
| `target` | TEXT | NOT NULL, FOREIGN KEY REFERENCES git_refs(name) | Target reference path |

**git_packs**: Stores git pack files *(pending implementation)*

| Column | Type | Constraints | Description |
|--|--|--|--|
| `id` | INTEGER | PRIMARY KEY | Unique pack identifier |
| `name` | TEXT | NOT NULL, UNIQUE | Pack name/identifier |
| `data` | BLOB | NOT NULL | Pack file binary data |
| `index_data` | BLOB | NOT NULL | Pack index binary data |

*Indexes:*
- `CREATE INDEX idx_git_packs_name ON git_packs(name);` - For efficient lookups by pack name

**git_pack_entries**: Maps objects to packs for faster lookups *(pending implementation)*

| Column | Type | Constraints | Description |
|--|--|--|--|
| `pack_id` | INTEGER | NOT NULL, FOREIGN KEY REFERENCES git_packs(id) | Reference to the pack |
| `sha` | TEXT | NOT NULL, FOREIGN KEY REFERENCES git_objects(sha) | Object SHA contained in the pack |
| `offset` | INTEGER | NOT NULL | Offset position within the pack |
| PRIMARY KEY | | (pack_id, sha) | Composite primary key |

*Indexes:*
- `CREATE INDEX idx_git_pack_entries_sha ON git_pack_entries(sha);` - For finding which pack contains a specific object


**git_config**: Stores git configuration settings

| Column | Type | Constraints | Description |
|--|--|--|--|
| `key` | TEXT | PRIMARY KEY | Configuration key |
| `value` | TEXT | NOT NULL | Configuration value |

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.