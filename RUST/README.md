# cortexa

[![Crates.io](https://img.shields.io/crates/v/cortexa.svg)](https://crates.io/crates/cortexa)
[![docs.rs](https://docs.rs/cortexa/badge.svg)](https://docs.rs/cortexa)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-swadhinbiswas%2FCortexa-black.svg?logo=github)](https://github.com/swadhinbiswas/Cortexa)

**Git-inspired context management for LLM agents.** COMMIT, BRANCH, MERGE, and CONTEXT operations over a persistent versioned memory workspace.

Rust implementation of the **cortexa** framework.

Based on: [arXiv:2508.00031](https://arxiv.org/abs/2508.00031) -- *"Git Context Controller: Manage the Context of LLM-based Agents like Git"* (Junde Wu et al., 2025)

---

## Installation

```toml
[dependencies]
cortexa = "0.1"
```

---

## Quick Start

```rust
use cortexa::GCCWorkspace;

fn main() -> cortexa::Result<()> {
    let mut ws = GCCWorkspace::new("/path/to/project");
    ws.init("Build a REST API service with user auth")?;

    ws.log_ota(
        "Project directory is empty",
        "Need to scaffold the project structure first",
        "create_files(['main.rs', 'Cargo.toml', 'models.rs'])",
    )?;

    ws.commit("Project scaffold and User model complete", None, None)?;

    ws.branch("auth-jwt", "Explore JWT-based authentication")?;
    ws.log_ota("Reading JWT docs", "JWT is stateless", "implement_jwt()")?;
    ws.commit("JWT auth middleware implemented", None, None)?;

    ws.merge("auth-jwt", None, "main")?;

    let ctx = ws.context(None, 1)?; // K=1: paper default
    println!("{}", ctx.summary());

    Ok(())
}
```

---

## Core Concepts

### OTA Logging (Observation-Thought-Action)

```rust
let rec = ws.log_ota(
    "API returns 500 error on /users endpoint",
    "The database connection might not be initialized",
    "check_db_connection()",
)?;
println!("Step: {}", rec.step);           // 1 (auto-incremented)
println!("Timestamp: {}", rec.timestamp); // RFC3339
```

### COMMIT -- Save Milestones

```rust
let commit = ws.commit(
    "Fixed database connection, /users now returns 200",
    None,                                        // previous summary auto-populated
    Some("Database layer stable, move to auth"), // optional roadmap update
)?;
assert_eq!(commit.commit_id.len(), 8);
assert_eq!(commit.branch_name, "main");
```

### BRANCH -- Explore Alternatives

```rust
ws.branch("redis-cache", "Try Redis caching instead of in-memory")?;
ws.log_ota("Redis docs reviewed", "Need redis crate", "cargo add redis")?;
ws.commit("Redis caching layer implemented", None, None)?;

assert_eq!(ws.current_branch(), "redis-cache");
println!("{:?}", ws.list_branches()); // ["main", "redis-cache"]
```

### MERGE -- Integrate Results

```rust
let merge_commit = ws.merge("redis-cache", None, "main")?;
// Appends branch OTA trace to main's log
// Creates a merge commit on main
// Marks branch as "merged" in metadata
assert_eq!(ws.current_branch(), "main");
```

### CONTEXT -- Retrieve History

```rust
let ctx = ws.context(None, 1)?; // K=1: paper default

println!("{}", ctx.branch_name);  // "main"
println!("{}", ctx.main_roadmap); // Global project roadmap
println!("{:?}", ctx.commits);    // Last K CommitRecords
println!("{:?}", ctx.ota_records); // All OTA records
println!("{:?}", ctx.metadata);   // BranchMetadata

// Formatted markdown summary for LLM prompt injection
println!("{}", ctx.summary());
```

---

## API Overview

### `GCCWorkspace`

| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `(project_root: impl AsRef<Path>) -> Self` | Create workspace handle |
| `init` | `(&mut self, roadmap: &str) -> Result<()>` | Create `.GCC/` structure |
| `load` | `(&mut self) -> Result<()>` | Load existing workspace |
| `log_ota` | `(&self, obs, thought, action) -> Result<OTARecord>` | Append OTA step |
| `commit` | `(&self, contribution, prev?, roadmap?) -> Result<CommitRecord>` | Checkpoint milestone |
| `branch` | `(&mut self, name, purpose) -> Result<()>` | Create and switch branch |
| `merge` | `(&mut self, branch, summary?, target) -> Result<CommitRecord>` | Merge branch |
| `context` | `(&self, branch?, k) -> Result<ContextResult>` | Retrieve context |
| `switch_branch` | `(&mut self, name) -> Result<()>` | Switch active branch |
| `list_branches` | `(&self) -> Vec<String>` | List all branches |
| `current_branch` | `(&self) -> &str` | Get current branch |

### Data Models

| Struct | Description |
|--------|-------------|
| `OTARecord` | Single Observation-Thought-Action cycle |
| `CommitRecord` | Milestone commit snapshot |
| `BranchMetadata` | Branch creation intent and status (Serde-serializable) |
| `ContextResult` | Result of CONTEXT retrieval with `.summary()` method |
| `GCCError` | Error type covering IO, YAML, and workspace errors |

---

## Directory Structure

```
your-project/
  .GCC/
    main.md                          # Global roadmap
    branches/
      main/
        log.md                       # Continuous OTA trace
        commit.md                    # Milestone-level summaries
        metadata.yaml                # Branch intent & status
      feature-branch/
        log.md
        commit.md
        metadata.yaml
```

All data is stored as **human-readable Markdown and YAML**.

---

## Running Tests

```bash
git clone https://github.com/swadhinbiswas/Cortexa.git
cd cortexa/RUST
cargo test
```

8 tests + 1 doc-test cover all GCC commands.

---

## Dependencies

- **serde** + **serde_yaml** -- YAML serialization for branch metadata
- **chrono** -- UTC timestamps (RFC3339)
- **uuid** -- Commit ID generation (v4 UUIDs, first 8 chars)
- **thiserror** -- Ergonomic error types

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Citation

```bibtex
@article{wu2025gcc,
  title={Git Context Controller: Manage the Context of LLM-based Agents like Git},
  author={Wu, Junde and others},
  journal={arXiv preprint arXiv:2508.00031},
  year={2025}
}
```

---

## Links

- [GitHub Repository](https://github.com/swadhinbiswas/Cortexa)
- [crates.io](https://crates.io/crates/cortexa)
- [docs.rs](https://docs.rs/cortexa)
- [Original Paper](https://arxiv.org/abs/2508.00031)
- [Author: Swadhin Biswas](https://github.com/swadhinbiswas)
