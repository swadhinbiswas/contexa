# cortexa

[![Go Reference](https://pkg.go.dev/badge/github.com/swadhinbiswas/Cortexa/GO.svg)](https://pkg.go.dev/github.com/swadhinbiswas/Cortexa/GO)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-swadhinbiswas%2FCortexa-black.svg?logo=github)](https://github.com/swadhinbiswas/Cortexa)

**Git-inspired context management for LLM agents.** COMMIT, BRANCH, MERGE, and CONTEXT operations over a persistent versioned memory workspace.

Go implementation of the **cortexa** framework.

Based on: [arXiv:2508.00031](https://arxiv.org/abs/2508.00031) -- *"Git Context Controller: Manage the Context of LLM-based Agents like Git"* (Junde Wu et al., 2025)

---

## Installation

```bash
go get github.com/swadhinbiswas/Cortexa/GO/cortexa
```

---

## Quick Start

```go
package main

import (
    "fmt"
    "github.com/swadhinbiswas/Cortexa/GO/cortexa"
)

func main() {
    ws := cortexa.New("/path/to/project")
    if err := ws.Init("Build a REST API service with user auth"); err != nil {
        panic(err)
    }

    ws.LogOTA(
        "Project directory is empty",
        "Need to scaffold the project structure first",
        "create_files(['main.go', 'go.mod', 'models.go'])",
    )

    ws.Commit("Project scaffold and User model complete", nil, nil)

    ws.Branch("auth-jwt", "Explore JWT-based authentication")
    ws.LogOTA("Reading JWT docs", "JWT is stateless", "implementJWT()")
    ws.Commit("JWT auth middleware implemented", nil, nil)

    ws.Merge("auth-jwt", nil, "main")

    ctx, _ := ws.Context(nil, 1) // K=1: paper default
    fmt.Println(ctx.Summary())
}
```

---

## Core Concepts

### OTA Logging (Observation-Thought-Action)

```go
rec, err := ws.LogOTA(
    "API returns 500 error on /users endpoint",
    "The database connection might not be initialized",
    "checkDbConnection()",
)
fmt.Println(rec.Step)      // 1 (auto-incremented)
fmt.Println(rec.Timestamp) // RFC3339 timestamp
```

### COMMIT -- Save Milestones

```go
commit, err := ws.Commit(
    "Fixed database connection, /users returns 200",
    nil, // previous summary auto-populated from last commit
    nil, // optional roadmap update
)
fmt.Println(commit.CommitID)   // "a3f2b1c4" (8-char hex)
fmt.Println(commit.BranchName) // "main"
```

### BRANCH -- Explore Alternatives

```go
ws.Branch("redis-cache", "Try Redis caching instead of in-memory")
ws.LogOTA("Redis docs reviewed", "Need redis package", "goGet('redis')")
ws.Commit("Redis caching layer implemented", nil, nil)

fmt.Println(ws.CurrentBranch()) // "redis-cache"
branches, _ := ws.ListBranches()
fmt.Println(branches) // ["main", "redis-cache"]
```

### MERGE -- Integrate Results

```go
mergeCommit, err := ws.Merge("redis-cache", nil, "main")
// Appends branch OTA trace to main's log
// Creates a merge commit on main
// Marks branch as "merged" in metadata
fmt.Println(ws.CurrentBranch()) // "main"
```

### CONTEXT -- Retrieve History

```go
ctx, err := ws.Context(nil, 1) // K=1: paper default

fmt.Println(ctx.BranchName)  // "main"
fmt.Println(ctx.MainRoadmap) // Global project roadmap
fmt.Println(ctx.Commits)     // Last K CommitRecords
fmt.Println(ctx.OTARecords)  // All OTA records
fmt.Println(ctx.Metadata)    // *BranchMetadata

// Formatted markdown summary for LLM prompt injection
fmt.Println(ctx.Summary())
```

---

## API Overview

### `Workspace`

| Method | Signature | Description |
|--------|-----------|-------------|
| `New` | `(projectRoot string) *Workspace` | Create workspace handle |
| `Init` | `(roadmap string) error` | Create `.GCC/` structure |
| `Load` | `() error` | Load existing workspace |
| `LogOTA` | `(obs, thought, action string) (OTARecord, error)` | Append OTA step |
| `Commit` | `(contribution string, prev, roadmap *string) (CommitRecord, error)` | Checkpoint milestone |
| `Branch` | `(name, purpose string) error` | Create and switch branch |
| `Merge` | `(branch string, summary *string, target string) (CommitRecord, error)` | Merge branch |
| `Context` | `(branch *string, k int) (ContextResult, error)` | Retrieve context |
| `SwitchBranch` | `(name string) error` | Switch active branch |
| `ListBranches` | `() ([]string, error)` | List all branches |
| `CurrentBranch` | `() string` | Get current branch |

### Data Models

| Struct | Description |
|--------|-------------|
| `OTARecord` | Single Observation-Thought-Action cycle |
| `CommitRecord` | Milestone commit snapshot |
| `BranchMetadata` | Branch creation intent and status (YAML-serializable) |
| `ContextResult` | Result of CONTEXT retrieval with `.Summary()` method |

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
cd cortexa/GO
go test -v ./cortexa/
```

20 tests cover all GCC commands: init, OTA logging, commit, branch, merge, context, switch, list, and model serialization.

---

## Requirements

- **Go** >= 1.21
- **gopkg.in/yaml.v3** -- YAML serialization for branch metadata

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
- [pkg.go.dev](https://pkg.go.dev/github.com/swadhinbiswas/Cortexa/GO)
- [Original Paper](https://arxiv.org/abs/2508.00031)
- [Author: Swadhin Biswas](https://github.com/swadhinbiswas)
