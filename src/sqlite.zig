const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("sqlite3.h");
});

comptime {
    const expected_sqlite_version = std.SemanticVersion{
        .major = 3,
        .minor = 20,
        .patch = 0,
    };
    const expected_sqlite_version_number = expected_sqlite_version.major * 1000000 +
        expected_sqlite_version.minor * 1000 +
        expected_sqlite_version.patch;
    const actual_sqlite_version_number = c.SQLITE_VERSION_NUMBER;
    if (actual_sqlite_version_number < expected_sqlite_version_number) {
        @compileError(std.fmt.comptimePrint(
            "unsupported sqlite version: expected {}, found {}",
            .{ expected_sqlite_version_number, actual_sqlite_version_number },
        ));
    }
}

// ---

/// Database-specific errors
pub const DatabaseError = error{
    ReadFailed,
    WriteFailed,
    InitializationFailed,
    SchemaError,
};

pub const SQLiteError = error{
    /// Generic SQL error or missing database
    SQLiteError,
    /// Internal logic error in SQLite
    SQLiteInternal,
    /// Access permission denied
    SQLitePerm,
    /// Callback routine requested an abort
    SQLiteAbort,
    /// The database file is locked
    SQLiteBusy,
    /// A table in the database is locked
    SQLiteLocked,
    /// A malloc() failed
    SQLiteNoMem,
    /// Attempt to write a readonly database
    SQLiteReadOnly,
    /// Operation terminated by sqlite3_interrupt()
    SQLiteInterrupt,
    /// Some kind of disk I/O error occurred
    SQLiteIOErr,
    /// The database disk image is malformed
    SQLiteCorrupt,
    /// Unknown opcode in sqlite3_file_control()
    SQLiteNotFound,
    /// Insertion failed because database is full
    SQLiteFull,
    /// Unable to open the database file
    SQLiteCantOpen,
    /// Database lock protocol error
    SQLiteProtocol,
    /// The database schema changed
    SQLiteSchema,
    /// String or BLOB exceeds size limit
    SQLiteTooBig,
    /// Abort due to constraint violation
    SQLiteConstraint,
    /// Data type mismatch
    SQLiteMismatch,
    /// Library used incorrectly
    SQLiteMisuse,
    /// Uses OS features not supported on host
    SQLiteNoLFS,
    /// Authorization denied
    SQLiteAuth,
    /// Not used
    SQLiteFormat,
    /// 2nd parameter to sqlite3_bind out of range
    SQLiteRange,
    /// File opened that is not a database file
    SQLiteNotADB,
    /// Notifications from sqlite3_log()
    SQLiteNotice,
    /// Warnings from sqlite3_log()
    SQLiteWarning,
};

/// Convert SQLite result code to Zig error
pub fn errorFromResultCode(code: c_int) SQLiteError {
    return switch (code) {
        c.SQLITE_ERROR => error.SQLiteError,
        c.SQLITE_INTERNAL => error.SQLiteInternal,
        c.SQLITE_PERM => error.SQLitePerm,
        c.SQLITE_ABORT => error.SQLiteAbort,
        c.SQLITE_BUSY => error.SQLiteBusy,
        c.SQLITE_LOCKED => error.SQLiteLocked,
        c.SQLITE_NOMEM => error.SQLiteNoMem,
        c.SQLITE_READONLY => error.SQLiteReadOnly,
        c.SQLITE_INTERRUPT => error.SQLiteInterrupt,
        c.SQLITE_IOERR => error.SQLiteIOErr,
        c.SQLITE_CORRUPT => error.SQLiteCorrupt,
        c.SQLITE_NOTFOUND => error.SQLiteNotFound,
        c.SQLITE_FULL => error.SQLiteFull,
        c.SQLITE_CANTOPEN => error.SQLiteCantOpen,
        c.SQLITE_PROTOCOL => error.SQLiteProtocol,
        c.SQLITE_SCHEMA => error.SQLiteSchema,
        c.SQLITE_TOOBIG => error.SQLiteTooBig,
        c.SQLITE_CONSTRAINT => error.SQLiteConstraint,
        c.SQLITE_MISMATCH => error.SQLiteMismatch,
        c.SQLITE_MISUSE => error.SQLiteMisuse,
        c.SQLITE_NOLFS => error.SQLiteNoLFS,
        c.SQLITE_AUTH => error.SQLiteAuth,
        c.SQLITE_FORMAT => error.SQLiteFormat,
        c.SQLITE_RANGE => error.SQLiteRange,
        c.SQLITE_NOTADB => error.SQLiteNotADB,
        c.SQLITE_NOTICE => error.SQLiteNotice,
        c.SQLITE_WARNING => error.SQLiteWarning,
        else => error.SQLiteError,
    };
}

// ---

pub const SHA_LENGTH = 40;

comptime {
    if (SHA_LENGTH != 40) @compileError("Invalid SHA length");
}

/// Git object types
pub const ObjectType = enum {
    blob,
    tree,
    commit,
    tag,

    /// Convert enum to string
    pub fn toString(self: ObjectType) []const u8 {
        return switch (self) {
            .blob => "blob",
            .tree => "tree",
            .commit => "commit",
            .tag => "tag",
        };
    }

    /// Parse string to enum
    pub fn fromString(str: []const u8) ?ObjectType {
        if (std.mem.eql(u8, str, "blob")) return .blob;
        if (std.mem.eql(u8, str, "tree")) return .tree;
        if (std.mem.eql(u8, str, "commit")) return .commit;
        if (std.mem.eql(u8, str, "tag")) return .tag;
        return null;
    }
};

pub const objects_schema =
    \\CREATE TABLE IF NOT EXISTS git_objects (
    \\    sha TEXT PRIMARY KEY CHECK (
    \\        length (sha) = 40
    \\        AND sha GLOB '[0-9a-f]*'
    \\    ),
    \\    type TEXT NOT NULL CHECK (type IN ('blob', 'tree', 'commit', 'tag')),
    \\    data BLOB NOT NULL
    \\);
    \\CREATE INDEX IF NOT EXISTS idx_git_objects_type ON git_objects (type)
;

pub const refs_schema =
    \\CREATE TABLE IF NOT EXISTS git_refs (
    \\    name TEXT PRIMARY KEY CHECK (name GLOB 'refs/*'),
    \\    sha TEXT NOT NULL,
    \\    type TEXT NOT NULL CHECK (type IN ('branch', 'tag', 'remote')),
    \\    FOREIGN KEY (sha) REFERENCES git_objects (sha)
    \\);
    \\CREATE INDEX IF NOT EXISTS idx_git_refs_sha ON git_refs (sha);
    \\CREATE TABLE IF NOT EXISTS git_symbolic_refs (
    \\    name TEXT PRIMARY KEY,
    \\    target TEXT NOT NULL,
    \\    FOREIGN KEY (target) REFERENCES git_refs (name)
    \\)
;

pub const config_schema =
    \\CREATE TABLE IF NOT EXISTS git_config (
    \\    key TEXT PRIMARY KEY,
    \\    value TEXT NOT NULL
    \\)
;

pub const packs_schema =
    \\CREATE TABLE IF NOT EXISTS git_packs (
    \\    id INTEGER PRIMARY KEY,
    \\    name TEXT NOT NULL UNIQUE,
    \\    data BLOB NOT NULL,
    \\    index_data BLOB NOT NULL
    \\);
    \\CREATE INDEX IF NOT EXISTS idx_git_packs_name ON git_packs (name);
    \\CREATE TABLE IF NOT EXISTS git_pack_entries (
    \\    pack_id INTEGER NOT NULL,
    \\    sha TEXT NOT NULL,
    \\    offset INTEGER NOT NULL,
    \\    PRIMARY KEY (pack_id, sha),
    \\    FOREIGN KEY (pack_id) REFERENCES git_packs (id),
    \\    FOREIGN KEY (sha) REFERENCES git_objects (sha)
    \\);
    \\CREATE INDEX IF NOT EXISTS idx_git_pack_entries_sha ON git_pack_entries (sha)
;

/// Initialize all database schemas
pub fn initializeAll(db: *Database) DatabaseError!void {
    db.exec(objects_schema) catch return DatabaseError.InitializationFailed;
    db.exec(refs_schema) catch return DatabaseError.InitializationFailed;
    db.exec(config_schema) catch return DatabaseError.InitializationFailed;
    db.exec(packs_schema) catch return DatabaseError.InitializationFailed;
}

// ---

pub const ResultSet = struct {
    stmt: *c.sqlite3_stmt,

    pub fn next(self: *ResultSet) SQLiteError!bool {
        const result = c.sqlite3_step(self.stmt);
        return switch (result) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => errorFromResultCode(result),
        };
    }

    pub fn columnText(self: *ResultSet, index: u32) ?[]const u8 {
        const ptr = c.sqlite3_column_text(self.stmt, @intCast(index));
        if (ptr == null) return null;

        const len = c.sqlite3_column_bytes(self.stmt, @intCast(index));
        return @as([*c]const u8, @ptrCast(ptr))[0..@intCast(len)];
    }

    pub fn columnBlob(self: *ResultSet, index: u32) ?[]const u8 {
        const ptr = c.sqlite3_column_blob(self.stmt, @intCast(index));
        if (ptr == null) return null;

        const len = c.sqlite3_column_bytes(self.stmt, @intCast(index));
        return @as([*c]const u8, @ptrCast(ptr))[0..@intCast(len)];
    }
};

pub const Statement = struct {
    stmt: *c.sqlite3_stmt,

    pub fn bindText(self: *Statement, index: u32, text: []const u8) void {
        assert(index > 0); // SQLite indices are 1-based
        _ = c.sqlite3_bind_text(self.stmt, @intCast(index), text.ptr, @intCast(text.len), null);
    }

    pub fn bindBlob(self: *Statement, index: u32, data: []const u8) void {
        assert(index > 0); // SQLite indices are 1-based
        _ = c.sqlite3_bind_blob(self.stmt, @intCast(index), data.ptr, @intCast(data.len), null);
    }

    pub fn execute(self: *Statement) ResultSet {
        return ResultSet{ .stmt = self.stmt };
    }

    pub fn finalize(self: *Statement) void {
        _ = c.sqlite3_finalize(self.stmt);
    }
};

pub const Database = struct {
    db: *c.sqlite3,
    allocator: std.mem.Allocator,

    /// Open SQLite database, creating file if needed
    pub fn open(allocator: std.mem.Allocator, path: [:0]const u8) SQLiteError!Database {
        assert(path.len > 0);
        var db: ?*c.sqlite3 = undefined;

        const result = c.sqlite3_open(path.ptr, &db);
        if (result != c.SQLITE_OK) {
            if (db) |valid_db| {
                _ = c.sqlite3_close(valid_db);
            }
            return errorFromResultCode(result);
        }
        assert(db != null);
        return Database{ .db = db.?, .allocator = allocator };
    }

    /// Close database connection
    pub fn close(self: *const Database) void {
        _ = c.sqlite3_close(self.db);
    }

    /// Execute non-query SQL statement
    pub fn exec(self: *Database, comptime sql: [:0]const u8) SQLiteError!void {
        assert(sql.len > 0);
        var err_msg: [*c]u8 = undefined;

        const result = c.sqlite3_exec(self.db, sql.ptr, null, null, &err_msg);
        if (result != c.SQLITE_OK) {
            defer c.sqlite3_free(err_msg);
            return errorFromResultCode(result);
        }
    }

    /// Prepare statement for execution (caller must call finalize())
    pub fn prepare(self: *Database, comptime sql: [:0]const u8) SQLiteError!Statement {
        assert(sql.len > 0);
        var stmt: ?*c.sqlite3_stmt = undefined;

        const result = c.sqlite3_prepare_v2(self.db, sql.ptr, -1, &stmt, null);
        if (result != c.SQLITE_OK) {
            return errorFromResultCode(result);
        }
        assert(stmt != null);
        return Statement{ .stmt = stmt.? };
    }

    /// Execute simple statement with automatic cleanup
    pub fn executeStatement(self: *Database, comptime sql: [:0]const u8) SQLiteError!void {
        var stmt = try self.prepare(sql);
        defer stmt.finalize();
        var results = stmt.execute();
        _ = try results.next();
    }

    /// Execute statement with parameters
    pub fn execParams(self: *Database, comptime sql: [:0]const u8, params: []const []const u8) SQLiteError!void {
        var stmt = try self.prepare(sql);
        defer stmt.finalize();
        
        for (params, 1..) |param, i| {
            stmt.bindText(@intCast(i), param);
        }
        
        var results = stmt.execute();
        _ = try results.next();
    }

    /// Query for single text value (returns allocated string or null)
    pub fn oneText(self: *Database, allocator: std.mem.Allocator, comptime sql: [:0]const u8, params: []const []const u8) (SQLiteError || error{OutOfMemory})!?[]const u8 {
        var stmt = try self.prepare(sql);
        defer stmt.finalize();
        
        for (params, 1..) |param, i| {
            stmt.bindText(@intCast(i), param);
        }
        
        var results = stmt.execute();
        if (try results.next()) {
            const value = results.columnText(0) orelse return null;
            return try allocator.dupe(u8, value);
        }
        return null;
    }

    /// Query for multiple text values from first column
    pub fn allText(self: *Database, allocator: std.mem.Allocator, comptime sql: [:0]const u8, params: []const []const u8) (SQLiteError || error{OutOfMemory})![][]const u8 {
        var stmt = try self.prepare(sql);
        defer stmt.finalize();
        
        for (params, 1..) |param, i| {
            stmt.bindText(@intCast(i), param);
        }
        
        var results = stmt.execute();
        var list = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (list.items) |item| {
                allocator.free(item);
            }
            list.deinit();
        }
        
        while (try results.next()) {
            const value = results.columnText(0) orelse continue;
            try list.append(try allocator.dupe(u8, value));
        }
        
        return try list.toOwnedSlice();
    }
};

// ---

/// SQLite implementation for git config storage
pub const ConfigDatabase = struct {
    db: *Database,

    const Self = @This();

    pub const Config = struct {
        key: []const u8,
        value: []const u8,

        pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
            allocator.free(self.key);
            allocator.free(self.value);
        }
    };

    pub fn init(db: *Database) DatabaseError!Self {
        db.exec(config_schema) catch return DatabaseError.InitializationFailed;
        return .{ .db = db };
    }

    /// Write config value
    pub fn writeConfig(self: *Self, key: []const u8, value: []const u8) DatabaseError!void {
        self.db.execParams("INSERT OR REPLACE INTO git_config (key, value) VALUES (?, ?)", &[_][]const u8{ key, value }) catch return DatabaseError.WriteFailed;
    }

    /// Read config value
    pub fn readConfig(self: *Self, allocator: std.mem.Allocator, key: []const u8) DatabaseError!?[]const u8 {
        return self.db.oneText(allocator, "SELECT value FROM git_config WHERE key = ?", &[_][]const u8{key}) catch return DatabaseError.ReadFailed;
    }

    /// Unset config key
    pub fn unsetConfig(self: *Self, key: []const u8) DatabaseError!void {
        self.db.execParams("DELETE FROM git_config WHERE key = ?", &[_][]const u8{key}) catch return DatabaseError.WriteFailed;
    }

    /// Iterate over all config entries
    pub fn iterateConfig(self: *Self, allocator: std.mem.Allocator) DatabaseError![]Config {
        var stmt = self.db.prepare("SELECT key, value FROM git_config ORDER BY key") catch return DatabaseError.ReadFailed;
        defer stmt.finalize();

        var entries = std.ArrayList(Config).init(allocator);
        errdefer {
            for (entries.items) |entry| {
                entry.deinit(allocator);
            }
            entries.deinit();
        }
        var results = stmt.execute();

        while (results.next() catch return DatabaseError.ReadFailed) {
            const key = results.columnText(0) orelse continue;
            const value = results.columnText(1) orelse continue;

            entries.append(Config{
                .key = allocator.dupe(u8, key) catch return DatabaseError.ReadFailed,
                .value = allocator.dupe(u8, value) catch return DatabaseError.ReadFailed,
            }) catch return DatabaseError.ReadFailed;
        }

        return entries.toOwnedSlice() catch return DatabaseError.ReadFailed;
    }
};


/// SQLite implementation for git objects storage
pub const ObjectDatabase = struct {
    db: *Database,

    const Self = @This();

    pub const Object = struct {
        object_type: ObjectType,
        data: []const u8,

        pub fn deinit(self: Object, allocator: std.mem.Allocator) void {
            allocator.free(self.data);
        }
    };

    pub fn init(db: *Database) DatabaseError!Self {
        db.exec(objects_schema) catch return DatabaseError.InitializationFailed;
        return .{ .db = db };
    }

    /// Write a git object to the database
    pub fn writeObject(self: *Self, sha: []const u8, object_type: ObjectType, data: []const u8) DatabaseError!void {
        var stmt = self.db.prepare("INSERT OR REPLACE INTO git_objects (sha, type, data) VALUES (?, ?, ?)") catch return DatabaseError.WriteFailed;
        defer stmt.finalize();

        stmt.bindText(1, sha);
        stmt.bindText(2, object_type.toString());
        stmt.bindBlob(3, data);

        var results = stmt.execute();
        if (results.next() catch return DatabaseError.WriteFailed) {
            // INSERT should not return any rows, so if next() returns true, something is wrong
            return DatabaseError.WriteFailed;
        }
    }

    /// Check if an object exists
    pub fn hasObject(self: *Self, sha: []const u8) DatabaseError!bool {
        var stmt = self.db.prepare("SELECT 1 FROM git_objects WHERE sha = ?") catch return DatabaseError.ReadFailed;
        defer stmt.finalize();

        stmt.bindText(1, sha);
        var results = stmt.execute();
        return results.next() catch return DatabaseError.ReadFailed;
    }

    /// Read object data by SHA
    pub fn readObject(self: *Self, allocator: std.mem.Allocator, sha: []const u8) DatabaseError!?Object {
        var stmt = self.db.prepare("SELECT type, data FROM git_objects WHERE sha = ?") catch return DatabaseError.ReadFailed;
        defer stmt.finalize();

        stmt.bindText(1, sha);
        var results = stmt.execute();

        if (results.next() catch return DatabaseError.ReadFailed) {
            const object_type_str = results.columnText(0) orelse return DatabaseError.ReadFailed;
            const data = results.columnBlob(1) orelse return DatabaseError.ReadFailed;

            const object_type = ObjectType.fromString(object_type_str) orelse return DatabaseError.ReadFailed;
            return Object{
                .object_type = object_type,
                .data = allocator.dupe(u8, data) catch return DatabaseError.ReadFailed,
            };
        }

        return null;
    }

    /// Iterate over objects of a specific type
    pub fn iterateObjectsByType(self: *Self, allocator: std.mem.Allocator, object_type: ObjectType) DatabaseError![][]const u8 {
        return self.db.allText(allocator, "SELECT sha FROM git_objects WHERE type = ? ORDER BY sha", &[_][]const u8{object_type.toString()}) catch return DatabaseError.ReadFailed;
    }

    /// Get total object count
    pub fn countObjects(self: *Self, allocator: std.mem.Allocator) DatabaseError!u64 {
        const count_str = (self.db.oneText(allocator, "SELECT COUNT(*) FROM git_objects", &[_][]const u8{}) catch return DatabaseError.ReadFailed) orelse return 0;
        defer allocator.free(count_str);

        return std.fmt.parseInt(u64, count_str, 10) catch return DatabaseError.ReadFailed;
    }
};


/// SQLite implementation for git refs storage
pub const RefDatabase = struct {
    db: *Database,

    const Self = @This();

    pub const Ref = struct {
        name: []const u8,
        sha: []const u8,
        ref_type: []const u8,

        pub fn deinit(self: Ref, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.sha);
            allocator.free(self.ref_type);
        }
    };

    pub fn init(db: *Database) DatabaseError!Self {
        db.exec(refs_schema) catch return DatabaseError.InitializationFailed;
        return .{ .db = db };
    }

    /// Write a reference (regular or symbolic)
    pub fn writeRef(self: *Self, name: []const u8, value: []const u8, ref_type: []const u8) DatabaseError!void {
        if (std.mem.startsWith(u8, value, "ref: ")) {
            const target = value[5..];
            self.db.execParams("INSERT OR REPLACE INTO git_symbolic_refs (name, target) VALUES (?, ?)", &[_][]const u8{ name, target }) catch return DatabaseError.WriteFailed;
        } else {
            self.db.execParams("INSERT OR REPLACE INTO git_refs (name, sha, type) VALUES (?, ?, ?)", &[_][]const u8{ name, value, ref_type }) catch return DatabaseError.WriteFailed;
        }
    }

    /// Read reference SHA
    pub fn readRef(self: *Self, allocator: std.mem.Allocator, name: []const u8) DatabaseError!?[]const u8 {
        return self.db.oneText(allocator, "SELECT sha FROM git_refs WHERE name = ?", &[_][]const u8{name}) catch return DatabaseError.ReadFailed;
    }

    /// Iterate over all references (including symbolic refs resolved to their target SHA)
    pub fn iterateRefs(self: *Self, allocator: std.mem.Allocator) DatabaseError![]Ref {
        var refs = std.ArrayList(Ref).init(allocator);
        errdefer {
            for (refs.items) |ref| {
                ref.deinit(allocator);
            }
            refs.deinit();
        }

        // First, get all regular refs
        var stmt = self.db.prepare("SELECT name, sha, type FROM git_refs ORDER BY name") catch return DatabaseError.ReadFailed;
        defer stmt.finalize();
        var results = stmt.execute();

        while (results.next() catch return DatabaseError.ReadFailed) {
            const name = results.columnText(0) orelse continue;
            const sha = results.columnText(1) orelse continue;
            const ref_type = results.columnText(2) orelse continue;

            refs.append(Ref{
                .name = allocator.dupe(u8, name) catch return DatabaseError.ReadFailed,
                .sha = allocator.dupe(u8, sha) catch return DatabaseError.ReadFailed,
                .ref_type = allocator.dupe(u8, ref_type) catch return DatabaseError.ReadFailed,
            }) catch return DatabaseError.ReadFailed;
        }

        // Then, get symbolic refs and resolve them to their target SHA
        var symref_stmt = self.db.prepare("SELECT s.name, r.sha, 'symbolic' FROM git_symbolic_refs s JOIN git_refs r ON s.target = r.name ORDER BY s.name") catch return DatabaseError.ReadFailed;
        defer symref_stmt.finalize();
        var symref_results = symref_stmt.execute();

        while (symref_results.next() catch return DatabaseError.ReadFailed) {
            const name = symref_results.columnText(0) orelse continue;
            const sha = symref_results.columnText(1) orelse continue;
            const ref_type = symref_results.columnText(2) orelse continue;

            refs.append(Ref{
                .name = allocator.dupe(u8, name) catch return DatabaseError.ReadFailed,
                .sha = allocator.dupe(u8, sha) catch return DatabaseError.ReadFailed,
                .ref_type = allocator.dupe(u8, ref_type) catch return DatabaseError.ReadFailed,
            }) catch return DatabaseError.ReadFailed;
        }

        return refs.toOwnedSlice() catch return DatabaseError.ReadFailed;
    }

    /// Delete a reference
    pub fn deleteRef(self: *Self, name: []const u8) DatabaseError!void {
        self.db.execParams("DELETE FROM git_refs WHERE name = ?", &[_][]const u8{name}) catch return DatabaseError.WriteFailed;
    }


};


// ---

const testing = std.testing;

test "Database open and close" {
    const allocator = testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();
    
    // Just verify that the database was opened successfully by testing a basic operation
    try db.exec("CREATE TABLE test (id INTEGER)");
}

test "ConfigDatabase set and get" {
    const allocator = testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    var config_db = try ConfigDatabase.init(&db);

    try config_db.writeConfig("user.name", "John Doe");
    const result = try config_db.readConfig(allocator, "user.name");
    defer if (result) |r| allocator.free(r);

    try testing.expect(result != null);
    try testing.expectEqualStrings("John Doe", result.?);
}

test "ConfigDatabase get non-existent key" {
    const allocator = testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    var config_db = try ConfigDatabase.init(&db);

    const result = try config_db.readConfig(allocator, "non.existent");
    try testing.expect(result == null);
}

test "ConfigDatabase listAll" {
    const allocator = testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    var config_db = try ConfigDatabase.init(&db);

    try config_db.writeConfig("core.editor", "vim");
    try config_db.writeConfig("user.name", "Jane");

    const entries = try config_db.iterateConfig(allocator);
    defer {
        for (entries) |entry| {
            entry.deinit(allocator);
        }
        allocator.free(entries);
    }

    try testing.expect(entries.len == 2);
    try testing.expectEqualStrings("core.editor", entries[0].key);
    try testing.expectEqualStrings("vim", entries[0].value);
    try testing.expectEqualStrings("user.name", entries[1].key);
    try testing.expectEqualStrings("Jane", entries[1].value);
}

test "ObjectDatabase store and get" {
    const allocator = testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    var object_db = try ObjectDatabase.init(&db);

    const sha = "abcdef1234567890abcdef1234567890abcdef12";
    const object_type = ObjectType.blob;
    const data = "Hello, World!";

    try object_db.writeObject(sha, object_type, data);

    const result = try object_db.readObject(allocator, sha);
    defer if (result) |r| r.deinit(allocator);

    try testing.expect(result != null);
    try testing.expect(result.?.object_type == object_type);
    try testing.expectEqualStrings(data, result.?.data);
}

test "ObjectDatabase exists" {
    const allocator = testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    var object_db = try ObjectDatabase.init(&db);

    const sha = "1111111111111111111111111111111111111111";

    try testing.expect(!(try object_db.hasObject(sha)));

    try object_db.writeObject(sha, ObjectType.commit, "commit data");

    try testing.expect(try object_db.hasObject(sha));
}

test "RefDatabase setRef and getRef" {
    const allocator = testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    var ref_db = try RefDatabase.init(&db);

    const ref_name = "refs/heads/main";
    const sha = "abc123def456789";
    const ref_type = "branch";

    try ref_db.writeRef(ref_name, sha, ref_type);

    const result = try ref_db.readRef(allocator, ref_name);
    defer if (result) |r| allocator.free(r);

    try testing.expect(result != null);
    try testing.expectEqualStrings(sha, result.?);
}


test "RefDatabase listRefs includes symbolic refs resolved to SHA" {
    const allocator = testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    var ref_db = try RefDatabase.init(&db);

    // Add a regular ref
    const ref_name = "refs/heads/main";
    const sha = "abc123def456789";
    try ref_db.writeRef(ref_name, sha, "branch");

    // Add a symbolic ref pointing to the regular ref
    const symbolic_name = "HEAD";
    try ref_db.writeRef(symbolic_name, "ref: refs/heads/main", "symbolic");

    // List all refs
    const refs = try ref_db.iterateRefs(allocator);
    defer {
        for (refs) |ref| {
            ref.deinit(allocator);
        }
        allocator.free(refs);
    }

    // Should have 2 refs: the regular ref and the symbolic ref resolved to same SHA
    try testing.expect(refs.len == 2);
    
    // Find HEAD in the results
    var head_found = false;
    var main_found = false;
    for (refs) |ref| {
        if (std.mem.eql(u8, ref.name, "HEAD")) {
            head_found = true;
            try testing.expectEqualStrings(sha, ref.sha); // HEAD should resolve to same SHA as main
            try testing.expectEqualStrings("symbolic", ref.ref_type);
        } else if (std.mem.eql(u8, ref.name, "refs/heads/main")) {
            main_found = true;
            try testing.expectEqualStrings(sha, ref.sha);
            try testing.expectEqualStrings("branch", ref.ref_type);
        }
    }
    
    try testing.expect(head_found);
    try testing.expect(main_found);
}