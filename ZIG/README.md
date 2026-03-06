# cortexa

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-swadhinbiswas%2FCortexa-black.svg?logo=github)](https://github.com/swadhinbiswas/Cortexa)

**Git-inspired context management for LLM agents.** COMMIT, BRANCH, MERGE, and CONTEXT operations over a persistent versioned memory workspace.

Zig implementation of the **cortexa** framework.

Based on: [arXiv:2508.00031](https://arxiv.org/abs/2508.00031) -- *"Git Context Controller: Manage the Context of LLM-based Agents like Git"* (Junde Wu et al., 2025)

---

## Installation

### As a Zig package dependency

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .cortexa = .{
        .url = "https://github.com/swadhinbiswas/Cortexa/archive/refs/tags/v0.1.1.tar.gz",
        .hash = "...", // zig build will tell you the correct hash
    },
},
```

Then in your `build.zig`:

```zig
const cortexa = b.dependency("cortexa", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("cortexa", cortexa.module("cortexa"));
```

---

## Quick Start

```zig
const std = @import("std");
const cortexa = @import("cortexa");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Initialize a workspace
    var ws = cortexa.Workspace.init(allocator, "/path/to/project");
    try ws.create("Build a REST API service with user auth");

    // 2. Agent logs its reasoning as it works
    _ = try ws.logOTA(
        "Project directory is empty",
        "Need to scaffold the project structure first",
        "create_files(['main.zig', 'build.zig'])",
    );

    // 3. Commit a milestone
    const c = try ws.commit("Project scaffold complete", null);
    defer allocator.free(c.commit_id);

    // 4. Branch to explore an alternative approach
    try ws.branch("auth-jwt", "Explore JWT-based authentication");
    _ = try ws.logOTA("Reading JWT docs", "JWT is stateless", "implementJWT()");
    const c2 = try ws.commit("JWT auth implemented", null);
    defer allocator.free(c2.commit_id);

    // 5. Merge the successful branch back
    const mc = try ws.merge("auth-jwt", "main");
    defer allocator.free(mc.commit_id);

    // 6. Retrieve context (K=1: paper default)
    const ctx = try ws.context(null, 1);
    defer ctx.deinit(allocator);

    std.debug.print("Roadmap:\n{s}\n", .{ctx.main_roadmap});
}
```

---

## Core Concepts

### Workspace

The `Workspace` struct manages the `.GCC/` directory structure. All operations use the Zig allocator pattern -- the caller is responsible for freeing returned allocations.

### Data Models

| Type | Description |
|------|-------------|
| `OTARecord` | Single Observation-Thought-Action cycle with `writeMarkdown()` |
| `CommitRecord` | Milestone checkpoint with `writeMarkdown()` |
| `BranchMetadata` | Branch intent and status with `writeYaml()` |
| `ContextSnapshot` | CONTEXT result with `deinit()` for cleanup |

### GCC Commands

| Command | Method | Description |
|---------|--------|-------------|
| *(init)* | `create(roadmap)` | Create `.GCC/` structure with main branch |
| OTA | `logOTA(obs, thought, action)` | Append OTA step to current branch |
| COMMIT | `commit(contribution, prev?)` | Save milestone checkpoint |
| BRANCH | `branch(name, purpose)` | Create isolated workspace |
| MERGE | `merge(branch, target)` | Integrate branch into target |
| CONTEXT | `context(branch?, k)` | Retrieve history (K-commit window) |

---

## Memory Management

This library follows Zig conventions:

- `Workspace.init()` takes an `Allocator` used for all internal operations
- `CommitRecord.commit_id` returned by `commit()` and `merge()` must be freed by the caller
- `ContextSnapshot` returned by `context()` owns `main_roadmap`, `ota_log`, and `commit_history` -- call `ctx.deinit(allocator)` when done
- Path helpers allocate and must be freed with `defer allocator.free(path)`

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

## Building and Testing

```bash
# Build the library
zig build

# Run unit tests
zig build test
```

5 tests cover workspace creation, OTA logging, commits, branching, and context retrieval.

---

## Requirements

- **Zig** >= 0.14.0
- No external dependencies (standard library only)

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
- [Original Paper](https://arxiv.org/abs/2508.00031)
- [Author: Swadhin Biswas](https://github.com/swadhinbiswas)
