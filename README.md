<p align="center">
  <img src="assets/logo.svg" alt="Cortexa" width="500" />
</p>

<p align="center">
  <strong>Versioned memory for AI agents</strong><br>
  <em>A brain-inspired context management system based on Git's branching model</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT" /></a>
  <a href="https://arxiv.org/abs/2508.00031"><img src="https://img.shields.io/badge/arXiv-2508.00031-b31b1b.svg" alt="arXiv" /></a>
  <a href="https://pypi.org/project/cortexa/"><img src="https://img.shields.io/pypi/v/cortexa.svg" alt="PyPI" /></a>
  <a href="https://www.npmjs.com/package/cortexa"><img src="https://img.shields.io/npm/v/cortexa.svg" alt="npm" /></a>
  <a href="https://crates.io/crates/cortexa"><img src="https://img.shields.io/crates/v/cortexa.svg" alt="crates.io" /></a>
  <a href="https://pkg.go.dev/github.com/swadhinbiswas/cortexa/GO"><img src="https://pkg.go.dev/badge/github.com/swadhinbiswas/cortexa/GO.svg" alt="Go Reference" /></a>
  <a href="https://hex.pm/packages/cortexa"><img src="https://img.shields.io/hexpm/v/cortexa.svg" alt="Hex.pm" /></a>
</p>

---

**Cortexa** implements the [Git Context Controller (GCC)](https://arxiv.org/abs/2508.00031) -- a structured, versioned memory system for LLM-based agents. Named after the cerebral cortex, it gives agents a persistent brain that survives across sessions, branches for parallel exploration, and compressed recall at any resolution.

Available in **Python**, **TypeScript/JavaScript**, **Rust**, **Go**, **Zig**, **Lua**, and **Elixir**. All 7 implementations produce the same `.GCC/` on-disk format (Markdown + YAML) and are fully interoperable.

## Why Cortexa?

LLM agents lose track of earlier reasoning as context windows fill up. Current workarounds -- full history dumps, naive summarization, or ad-hoc memory stores -- are expensive, lossy, or unstructured.

GCC applies Git's proven branching model to agent memory:

| GCC Command | Git Analogy | What It Does |
|-------------|-------------|--------------|
| **OTA Log** | Working directory | Continuous Observation-Thought-Action trace |
| **COMMIT** | `git commit` | Milestone summary that compresses older OTA steps |
| **BRANCH** | `git branch` | Isolated workspace for alternative reasoning paths |
| **MERGE** | `git merge` | Integrates a successful branch back into the main trajectory |
| **CONTEXT** | `git log` | Retrieves history at K-commit resolution |

### Results from the paper

The GCC framework achieves state-of-the-art results:

| Benchmark | Score | Model |
|-----------|-------|-------|
| **SWE-Bench Verified** | **80.2%** | Claude 4 Sonnet |
| **BrowseComp-Plus** | **83.4%** | GPT-5 |

Outperforms 26 existing open and commercial agent systems. Key findings:

- **K=1** (most recent commit only) performs best in most benchmarks
- Each component contributes: RoadMap+COMMIT (69.1%) -> +Logs+CONTEXT (75.3%) -> +Metadata (77.8%) -> +BRANCH&MERGE (80.2%)
- Agents with GCC allocate more computation (more tool calls) but achieve better cost-efficiency

### Three-tiered memory hierarchy

```
.GCC/
  main.md                    # Tier 1: Global roadmap / planning artifact
  branches/
    main/
      commit.md              # Tier 2: Commit-level milestone summaries
      log.md                 # Tier 3: Fine-grained OTA traces
      metadata.yaml          # Branch intent, status, provenance
    experiment/
      commit.md
      log.md
      metadata.yaml
```

---

## Install

| Language | Package | Install |
|----------|---------|---------|
| Python | [`cortexa`](https://pypi.org/project/cortexa/) | `pip install cortexa` |
| TypeScript/JS | [`cortexa`](https://www.npmjs.com/package/cortexa) | `npm install cortexa` |
| Rust | [`cortexa-gcc`](https://crates.io/crates/cortexa-gcc) | `cargo add cortexa-gcc` |
| Go | [`cortexa`](https://pkg.go.dev/github.com/swadhinbiswas/cortexa/GO) | `go get github.com/swadhinbiswas/cortexa/GO/cortexa` |
| Lua | [`cortexa`](https://luarocks.org/modules/swadhinbiswas/cortexa) | `luarocks install cortexa` |
| Elixir | [`cortexa`](https://hex.pm/packages/cortexa) | `{:cortexa, "~> 0.1.1"}` in mix.exs |
| Zig | `cortexa` | See [Zig README](ZIG/README.md) |

All 7 packages produce the same `.GCC/` file system layout. A workspace created by one language can be read or extended by any other.

---

## Quick Start

### Python

```python
from cortexa import GCCWorkspace

ws = GCCWorkspace("/path/to/project")
ws.init("Build a REST API with user auth")

# Agent logs its reasoning
ws.log_ota("saw empty dir", "scaffold first", "create_files()")
ws.log_ota("files created", "implement user model", "write_code('models.py')")
ws.commit("Project scaffold and User model complete")

# Branch to explore alternatives
ws.branch("auth-jwt", "Explore JWT authentication")
ws.log_ota("JWT docs reviewed", "stateless, good for APIs", "implement_jwt()")
ws.commit("JWT auth middleware implemented")

# Merge and retrieve context
ws.merge("auth-jwt")
ctx = ws.context(k=1)  # K=1: paper's recommended default
print(ctx.summary())   # Formatted markdown ready for LLM prompt injection
```

### TypeScript

```typescript
import { GCCWorkspace } from "cortexa";

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
use cortexa::GCCWorkspace;

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
import "github.com/swadhinbiswas/cortexa/GO/cortexa"

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
const cortexa = @import("cortexa");

var ws = cortexa.Workspace.init(allocator, "/path/to/project");
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
local cortexa = require("cortexa")

local ws = cortexa.GCCWorkspace.new("/path/to/project")
ws:init("Build a REST API")
ws:log_ota("saw empty dir", "scaffold first", "create_files()")
ws:commit("Project scaffold done")
ws:branch("auth-jwt", "Explore JWT authentication")
ws:commit("JWT middleware implemented")
ws:merge("auth-jwt", nil, "main")
local ctx = ws:context("main", 1)
print(cortexa.context_summary(ctx))
```

### Elixir

```elixir
alias Cortexa.{Workspace, Models}

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

## Architecture

```
                      main
                       |
      init --> OTA --> COMMIT --> COMMIT ---------> MERGE <--+
                                    |                        |
                                 BRANCH --> OTA --> COMMIT --+
                                (experiment)

      CONTEXT(k=1) returns: roadmap + last commit + current OTA log
```

The CONTEXT command controls **how much history** the agent sees. The paper's experiments show K=1 (most recent commit only) is optimal -- agents perform better with compressed recent context than with full history dumps.

---

## Data Models

| Model | Description | Key Fields |
|-------|-------------|------------|
| **OTARecord** | Single Observation-Thought-Action cycle | `step`, `timestamp`, `observation`, `thought`, `action` |
| **CommitRecord** | Milestone checkpoint | `commit_id`, `branch_name`, `branch_purpose`, `previous_progress_summary`, `this_commit_contribution`, `timestamp` |
| **BranchMetadata** | Branch intent and status | `name`, `purpose`, `created_from`, `created_at`, `status`, `merged_into`, `merged_at` |
| **ContextResult** | CONTEXT retrieval result | `branch_name`, `k`, `commits`, `ota_records`, `main_roadmap`, `metadata` |

All data is stored as **human-readable Markdown and YAML** -- inspect and debug agent memory directly in your editor.

---

## Repository Structure

```
Cortexa/
  PYTHON/        # PyPI: cortexa          (Python 3.10+)
  JS/            # npm: cortexa           (Node.js 18+)
  RUST/          # crates.io: cortexa     (Rust stable)
  GO/            # pkg.go.dev             (Go 1.21+)
  ZIG/           # Zig package            (Zig 0.14+)
  LUA/           # LuaRocks: cortexa      (Lua 5.1+)
  ELIXIR/        # Hex.pm: cortexa        (Elixir 1.15+)
  assets/        # Logo and visual assets
```

Each directory is an independent package with its own build tooling, tests, and README.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing instructions, and guidelines.

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-change`
3. Make your changes and add tests
4. Run the test suite for your language
5. Submit a pull request

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Citation

If you use Cortexa in research, please cite the original paper:

```bibtex
@article{wu2025gcc,
  title={Git Context Controller: Manage the Context of LLM-based Agents like Git},
  author={Wu, Junde and others},
  journal={arXiv preprint arXiv:2508.00031v2},
  year={2025}
}
```

---

## Links

- [Original Paper](https://arxiv.org/abs/2508.00031) -- arXiv:2508.00031v2
- [Python (PyPI)](https://pypi.org/project/cortexa/)
- [TypeScript (npm)](https://www.npmjs.com/package/cortexa)
- [Rust (crates.io)](https://crates.io/crates/cortexa)
- [Go (pkg.go.dev)](https://pkg.go.dev/github.com/swadhinbiswas/cortexa/GO)
- [Lua (LuaRocks)](https://luarocks.org/modules/swadhinbiswas/cortexa)
- [Elixir (Hex.pm)](https://hex.pm/packages/cortexa)
- [Author: Swadhin Biswas](https://github.com/swadhinbiswas)
