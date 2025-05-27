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

## Basic Usage

### 1. Push to/pull from the database

Push your code to the SQLite database:

```bash
git push sqlite://myapp.db main
```

Pull it back:

```bash
git pull sqlite://myapp.db main
```

### 2. Configure Repository Settings

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


## Development Status

Currently implemented:
- [x] Configuration management (set, get, list, unset)
- [x] Git remote helper protocol (push/pull functionality)
- [ ] Pack file management (tables defined but not yet implemented)
- [ ] Git hooks
