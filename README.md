# contexa

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![arXiv](https://img.shields.io/badge/arXiv-2508.00031-b31b1b.svg)](https://arxiv.org/abs/2508.00031)
[![PyPI](https://img.shields.io/pypi/v/contexa.svg)](https://pypi.org/project/contexa/)
[![npm](https://img.shields.io/npm/v/contexa.svg)](https://www.npmjs.com/package/contexa)
[![crates.io](https://img.shields.io/crates/v/contexa.svg)](https://crates.io/crates/contexa)
[![Go Reference](https://pkg.go.dev/badge/github.com/swadhinbiswas/contexa/GO.svg)](https://pkg.go.dev/github.com/swadhinbiswas/contexa/GO)
[![Hex.pm](https://img.shields.io/hexpm/v/contexa.svg)](https://hex.pm/packages/contexa)

**Git-inspired context management for LLM agents.** COMMIT, BRANCH, MERGE, and CONTEXT operations over a persistent versioned memory workspace.

Based on the research paper:

> *"Git Context Controller: Manage the Context of LLM-based Agents like Git"*
> Junde Wu et al., [arXiv:2508.00031](https://arxiv.org/abs/2508.00031), 2025

Available in **Python**, **TypeScript/JavaScript**, **Rust**, **Go**, **Zig**, **Lua**, and **Elixir**.

---

## Why contexa?

LLM-based agents accumulate observations, thoughts, and actions over time. Context windows are finite. As conversations grow, agents lose track of earlier reasoning, repeat mistakes, or forget prior decisions.

**contexa** borrows Git's branching model to give agents structured, versioned memory:

```
                    main
                     |
    init --> log OTA --> COMMIT --> COMMIT --> MERGE <--+
                                      |                |
                                   BRANCH --> COMMIT --+
                                  (experiment)
```

| Command | Git Equivalent | What It Does |
|---------|---------------|--------------|
| **OTA Log** | Working directory | Continuous Observation-Thought-Action trace |
| **COMMIT** | `git commit` | Milestone summary, compresses older OTA steps |
| **BRANCH** | `git branch` | Isolated workspace for alternative reasoning |
| **MERGE** | `git merge` | Integrates a successful branch back into main |
| **CONTEXT** | `git log` | Retrieves history at K-commit resolution |

The paper shows **K=1 performs best** in most benchmarks -- agents do better with compressed recent context than full history dumps.

---

## Install

| Language | Package | Install |
|----------|---------|---------|
| Python | [`contexa`](https://pypi.org/project/contexa/) | `pip install contexa` |
| TypeScript/JS | [`contexa`](https://www.npmjs.com/package/contexa) | `npm install contexa` |
| Rust | [`contexa`](https://crates.io/crates/contexa) | `cargo add contexa` |
| Go | [`contexa`](https://pkg.go.dev/github.com/swadhinbiswas/contexa/GO) | `go get github.com/swadhinbiswas/contexa/GO/cortexa` |
| Lua | [`contexa`](https://luarocks.org/modules/swadhinbiswas/contexa) | `luarocks install contexa` |
| Elixir | [`contexa`](https://hex.pm/packages/contexa) | `{:contexa, "~> 0.1.1"}` in mix.exs |
| Zig | `contexa` | See [Zig README](ZIG/README.md) |

All packages implement the same API and produce the same `.GCC/` file system layout. Workspaces created by one language can be read by another.

---

## Quick Start

### Python

```python
from contexa import GCCWorkspace

ws = GCCWorkspace("/path/to/project")
ws.init("Build a REST API")
ws.log_ota("saw empty dir", "scaffold first", "create_files()")
ws.commit("Project scaffold done")
ws.branch("auth-jwt", "Explore JWT authentication")
ws.commit("JWT middleware implemented")
ws.merge("auth-jwt")
ctx = ws.context(k=1)
print(ctx.summary())
```

### TypeScript

```typescript
import { GCCWorkspace } from "contexa";

const ws = new GCCWorkspace("/path/to/project");
ws.init("Build a REST API");
ws.logOTA("saw empty dir", "scaffold first", "createFiles()");
ws.commit("Project scaffold done");
ws.branch("auth-jwt", "Explore JWT authentication");
ws.commit("JWT middleware implemented");
ws.merge("auth-jwt");
const ctx = ws.context(undefined, 1);
console.log(ctx.summary());
```

### Rust

```rust
use contexa::GCCWorkspace;

let mut ws = GCCWorkspace::new("/path/to/project");
ws.init("Build a REST API")?;
ws.log_ota("saw empty dir", "scaffold first", "create_files()")?;
ws.commit("Project scaffold done", None, None)?;
ws.branch("auth-jwt", "Explore JWT authentication")?;
ws.commit("JWT middleware implemented", None, None)?;
ws.merge("auth-jwt", None, "main")?;
let ctx = ws.context(None, 1)?;
println!("{}", ctx.summary());
```

### Go

```go
import "github.com/swadhinbiswas/contexa/GO/cortexa"

ws := cortexa.New("/path/to/project")
ws.Init("Build a REST API")
ws.LogOTA("saw empty dir", "scaffold first", "createFiles()")
ws.Commit("Project scaffold done", nil, nil)
ws.Branch("auth-jwt", "Explore JWT authentication")
ws.Commit("JWT middleware implemented", nil, nil)
ws.Merge("auth-jwt", nil, "main")
ctx, _ := ws.Context(nil, 1)
fmt.Println(ctx.Summary())
```

### Zig

```zig
const contexa = @import("contexa");

var ws = contexa.Workspace.init(allocator, "/path/to/project");
try ws.create("Build a REST API");
_ = try ws.logOTA("saw empty dir", "scaffold first", "createFiles()");
const c = try ws.commit("Project scaffold done", null);
defer allocator.free(c.commit_id);
try ws.branch("auth-jwt", "Explore JWT authentication");
const c2 = try ws.commit("JWT middleware implemented", null);
defer allocator.free(c2.commit_id);
const mc = try ws.merge("auth-jwt", "main");
defer allocator.free(mc.commit_id);
const ctx = try ws.context(null, 1);
defer ctx.deinit(allocator);
```

### Lua

```lua
local contexa = require("contexa")

local ws = contexa.GCCWorkspace.new("/path/to/project")
ws:init("Build a REST API")
ws:log_ota("saw empty dir", "scaffold first", "create_files()")
ws:commit("Project scaffold done")
ws:branch("auth-jwt", "Explore JWT authentication")
ws:commit("JWT middleware implemented")
ws:merge("auth-jwt", nil, "main")
local ctx = ws:context("main", 1)
print(contexa.context_summary(ctx))
```

### Elixir

```elixir
alias Contexa.{Workspace, Models}

ws = Workspace.new("/path/to/project")
ws = Workspace.init(ws, "Build a REST API")
{ws, _} = Workspace.log_ota(ws, "saw empty dir", "scaffold first", "create_files()")
{ws, _} = Workspace.commit(ws, "Project scaffold done")
ws = Workspace.branch(ws, "auth-jwt", "Explore JWT authentication")
{ws, _} = Workspace.commit(ws, "JWT middleware implemented")
{ws, _} = Workspace.merge(ws, "auth-jwt", nil, "main")
ctx = Workspace.context(ws, "main", 1)
IO.puts(Models.context_summary(ctx))
```

---

## File System Layout

All implementations produce the same on-disk structure:

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

All data is stored as **human-readable Markdown and YAML** -- inspect and debug agent memory directly in your editor.

---

## Repository Structure

```
contexa/
  PYTHON/        # PyPI: contexa
  JS/            # npm: contexa
  RUST/          # crates.io: contexa
  GO/            # pkg.go.dev: github.com/swadhinbiswas/contexa/GO
  ZIG/           # Zig package: contexa
  LUA/           # LuaRocks: contexa
  ELIXIR/        # Hex.pm: contexa
```

Each directory is an independent package with its own build tooling, tests, and README.

---

## Data Models

| Model | Description | Key Fields |
|-------|-------------|------------|
| **OTARecord** | Single Observation-Thought-Action cycle | `step`, `timestamp`, `observation`, `thought`, `action` |
| **CommitRecord** | Milestone checkpoint | `commit_id`, `branch_name`, `branch_purpose`, `previous_progress_summary`, `this_commit_contribution`, `timestamp` |
| **BranchMetadata** | Branch intent and status | `name`, `purpose`, `created_from`, `created_at`, `status`, `merged_into`, `merged_at` |
| **ContextResult** | CONTEXT retrieval result | `branch_name`, `k`, `commits`, `ota_records`, `main_roadmap`, `metadata` |

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes and add tests
4. Run the test suite for your language
5. Submit a pull request

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

- [Original Paper](https://arxiv.org/abs/2508.00031) -- arXiv:2508.00031
- [Python (PyPI)](https://pypi.org/project/contexa/)
- [TypeScript (npm)](https://www.npmjs.com/package/contexa)
- [Rust (crates.io)](https://crates.io/crates/contexa)
- [Go (pkg.go.dev)](https://pkg.go.dev/github.com/swadhinbiswas/contexa/GO)
- [Lua (LuaRocks)](https://luarocks.org/modules/swadhinbiswas/contexa)
- [Elixir (Hex.pm)](https://hex.pm/packages/contexa)
- [Author: Swadhin Biswas](https://github.com/swadhinbiswas)
