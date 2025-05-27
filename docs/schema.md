# Database Schema

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