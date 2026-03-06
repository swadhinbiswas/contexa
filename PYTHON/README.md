# cortexa

[![PyPI version](https://img.shields.io/pypi/v/cortexa.svg)](https://pypi.org/project/cortexa/)
[![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-blue.svg)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/swadhinbiswas/Cortexa/blob/main/LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-swadhinbiswas%2FCortexa-black.svg?logo=github)](https://github.com/swadhinbiswas/Cortexa)

A Python implementation of the **cortexa** framework -- Git-inspired context management for LLM agents.

Based on: [arXiv:2508.00031](https://arxiv.org/abs/2508.00031) -- *"Git Context Controller: Manage the Context of LLM-based Agents like Git"* (Junde Wu et al., 2025)

---

## Table of Contents

- [The Problem](#the-problem)
- [How GCC Solves It](#how-gcc-solves-it)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [OTA Logging](#1-ota-logging-observation-thought-action)
  - [COMMIT](#2-commit---save-milestones)
  - [BRANCH](#3-branch---explore-alternatives)
  - [MERGE](#4-merge---integrate-results)
  - [CONTEXT](#5-context---retrieve-history)
- [API Reference](#api-reference)
- [Directory Structure](#directory-structure)
- [Data Models](#data-models)
- [Real-World Example](#real-world-example)
- [Running Tests](#running-tests)
- [Contributing](#contributing)
- [Requirements](#requirements)
- [License](#license)
- [Citation](#citation)
- [Links](#links)

---

## The Problem

LLM-based agents (like coding assistants, research agents, or autonomous planners) accumulate **observations**, **thoughts**, and **actions** over time. But context windows are finite. As conversations grow, agents lose track of earlier reasoning, repeat mistakes, or forget prior decisions.

Current approaches either:
- Dump the entire history into the prompt (expensive, hits token limits)
- Use simple summarization (loses critical details)
- Have no structured way to explore alternative strategies

## How GCC Solves It

GCC borrows **Git's branching model** to give agents structured, versioned memory:

```
                    main
                     |
    init ──> log OTA ──> COMMIT ──> COMMIT ──> MERGE <──┐
                                      |                  |
                                   BRANCH ──> COMMIT ────┘
                                  (experiment)
```

| Concept | Git Equivalent | What It Does |
|---------|---------------|--------------|
| **OTA Log** | Working directory | Continuous trace of Observation-Thought-Action cycles |
| **COMMIT** | `git commit` | Saves a milestone summary, compressing older OTA steps |
| **BRANCH** | `git branch` | Creates an isolated workspace for alternative reasoning |
| **MERGE** | `git merge` | Integrates a successful branch back into main |
| **CONTEXT** | `git log` | Retrieves historical context at varying resolutions (K commits) |

The key insight from the paper: by controlling **how much history** the agent sees (the K parameter in CONTEXT), you can balance between detailed recent context and compressed older summaries.

---

## Installation

```bash
pip install cortexa
```

Or with [uv](https://docs.astral.sh/uv/):

```bash
uv add cortexa
```

---

## Quick Start

```python
from cortexa import GCCWorkspace

# 1. Initialize a workspace
ws = GCCWorkspace("/path/to/project")
ws.init("Build a REST API service with user auth")

# 2. Agent logs its reasoning as it works
ws.log_ota(
    observation="Project directory is empty",
    thought="Need to scaffold the project structure first",
    action="create_files(['main.py', 'requirements.txt', 'models.py'])"
)
ws.log_ota(
    observation="Files created successfully",
    thought="Now implement the user model",
    action="write_code('models.py', user_model_code)"
)

# 3. Commit a milestone (compresses OTA history)
ws.commit("Project scaffold and User model complete")

# 4. Branch to explore an alternative approach
ws.branch("auth-jwt", "Explore JWT-based authentication instead of sessions")
ws.log_ota("Reading JWT docs", "JWT is stateless, good for APIs", "implement_jwt()")
ws.commit("JWT auth middleware implemented")

# 5. Merge the successful branch back
ws.merge("auth-jwt")

# 6. Retrieve context for the agent's next step
ctx = ws.context(k=1)  # K=1: only the most recent commit (paper default)
print(ctx.summary())
```

---

## Core Concepts

### 1. OTA Logging (Observation-Thought-Action)

Every reasoning step an agent takes is an OTA cycle. These are logged continuously in `log.md`:

```python
rec = ws.log_ota(
    observation="API returns 500 error on /users endpoint",
    thought="The database connection might not be initialized",
    action="check_db_connection()"
)
print(rec.step)       # 1 (auto-incremented)
print(rec.timestamp)  # 2025-03-04T12:00:00+00:00
```

This produces a markdown entry:

```markdown
### Step 1-2025-03-04T12:00:00+00:00
**Observation:** API returns 500 error on /users endpoint

**Thought:** The database connection might not be initialized

**Action:** check_db_connection()

--------
```

### 2. COMMIT - Save Milestones

When the agent reaches a significant checkpoint, commit it. This creates a structured summary that can be retrieved later without replaying every OTA step:

```python
commit = ws.commit(
    contribution="Fixed database connection and /users endpoint now returns 200",
    update_roadmap="Database layer is stable, move to auth next"  # optional
)
print(commit.commit_id)   # "a3f2b1c4" (8-char UUID)
print(commit.branch_name) # "main"
```

The `previous_progress_summary` is auto-populated from the last commit if not provided.

### 3. BRANCH - Explore Alternatives

When an agent wants to explore a different strategy without risking the main trajectory:

```python
# Creates isolated workspace with fresh OTA log
ws.branch("redis-cache", "Try Redis caching instead of in-memory")

# Agent works in the branch
ws.log_ota("Redis docs reviewed", "Need redis-py package", "pip_install('redis')")
ws.commit("Redis caching layer implemented")

# Check what branches exist
print(ws.list_branches())      # ['main', 'redis-cache']
print(ws.current_branch)       # 'redis-cache'
```

Each branch gets its own:
- `log.md` -- fresh OTA trace (no carry-over from parent)
- `commit.md` -- independent commit history
- `metadata.yaml` -- records why the branch was created and from where

### 4. MERGE - Integrate Results

When a branch's exploration succeeds, merge it back:

```python
merge_commit = ws.merge("redis-cache", target="main")
# - Appends the branch's OTA trace to main's log
# - Creates a merge commit on main
# - Marks the branch as "merged" in its metadata
```

After merging, `ws.current_branch` automatically switches back to the target.

### 5. CONTEXT - Retrieve History

The CONTEXT command is the agent's way of "remembering". The **K parameter** controls resolution:

```python
# K=1: Only the most recent commit (paper's recommended default)
ctx = ws.context(k=1)

# K=3: Last 3 commits for more detailed history
ctx = ws.context(k=3)

# Access the structured result
print(ctx.branch_name)      # "main"
print(ctx.main_roadmap)     # Global project roadmap from main.md
print(ctx.commits)           # List of last K CommitRecord objects
print(ctx.ota_records)       # All OTA records on the branch
print(ctx.metadata)          # BranchMetadata object

# Get a formatted markdown summary ready to inject into an LLM prompt
prompt_context = ctx.summary()
```

The paper's experiments (Table 2, Section 4) show that **K=1 performs best** in most benchmarks -- agents do better with compressed recent context than with full history dumps.

---

## API Reference

### `GCCWorkspace`

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `__init__` | `project_root: str` | -- | Set the project root directory |
| `init` | `project_roadmap: str = ""` | `None` | Create `.GCC/` structure with main branch |
| `load` | -- | `None` | Load an existing workspace |
| `log_ota` | `observation, thought, action` | `OTARecord` | Append OTA step to current branch |
| `commit` | `contribution, previous_summary=None, update_roadmap=None` | `CommitRecord` | Create milestone checkpoint |
| `branch` | `name, purpose` | `GCCWorkspace` | Create and switch to new branch |
| `merge` | `branch_name, summary=None, target="main"` | `CommitRecord` | Merge branch into target |
| `context` | `branch=None, k=1` | `ContextResult` | Retrieve historical context |
| `switch_branch` | `name` | `None` | Switch active branch |
| `list_branches` | -- | `list[str]` | List all branch names |
| `update_roadmap` | `content` | `None` | Append to global roadmap |
| `current_branch` | *(property)* | `str` | Get current active branch name |

---

## Directory Structure

When you call `ws.init()`, the following structure is created on disk:

```
your-project/
  .GCC/
    main.md                          # Global roadmap / planning artifact
    branches/
      main/
        log.md                       # Continuous OTA trace
        commit.md                    # Milestone-level commit summaries
        metadata.yaml                # Branch intent, status, creation info
      feature-branch/                # Created by ws.branch()
        log.md                       # Independent OTA trace
        commit.md                    # Independent commit history
        metadata.yaml                # Why this branch exists
```

All data is stored as **human-readable Markdown and YAML** -- you can inspect and debug the agent's memory directly in your editor.

---

## Data Models

| Class | Description | Key Fields |
|-------|-------------|------------|
| `OTARecord` | Single Observation-Thought-Action cycle | `timestamp`, `observation`, `thought`, `action`, `step` |
| `CommitRecord` | Milestone commit snapshot | `commit_id`, `branch_name`, `branch_purpose`, `previous_progress_summary`, `this_commit_contribution`, `timestamp` |
| `BranchMetadata` | Branch creation intent and status | `name`, `purpose`, `created_from`, `created_at`, `status`, `merged_into`, `merged_at` |
| `ContextResult` | Result of CONTEXT retrieval | `branch_name`, `k`, `commits`, `ota_records`, `main_roadmap`, `metadata` |

All models support serialization:

```python
from cortexa import OTARecord, BranchMetadata

# OTARecord <-> dict
record = OTARecord.from_dict({"timestamp": "...", "observation": "...", ...})

# BranchMetadata <-> YAML
meta = BranchMetadata(name="main", purpose="Primary trajectory", ...)
yaml_str = meta.to_yaml()
meta_back = BranchMetadata.from_yaml(yaml_str)

# All records can be rendered as Markdown
print(record.to_markdown())
```

---

## Real-World Example

Here's how an autonomous coding agent might use cortexa to manage its memory while building a web application:

```python
from cortexa import GCCWorkspace

ws = GCCWorkspace("./my-webapp")
ws.init("Build a Flask web app with user auth, blog posts, and admin panel")

# === Phase 1: Project Setup ===
ws.log_ota("No project files exist", "Start with Flask boilerplate", "scaffold_project()")
ws.log_ota("Flask app created", "Need database models", "create_models()")
ws.log_ota("Models created", "Database migrations needed", "run_migrations()")
ws.commit("Project scaffold with Flask + SQLAlchemy models")

# === Phase 2: Explore auth strategies in parallel branches ===

# Try JWT auth
ws.branch("auth-jwt", "Explore stateless JWT authentication")
ws.log_ota("JWT docs reviewed", "Good for API, complex for sessions", "implement_jwt()")
ws.commit("JWT auth prototype -- works but session handling is messy")

# Go back and try session auth
ws.switch_branch("main")
ws.branch("auth-session", "Explore Flask-Login session authentication")
ws.log_ota("Flask-Login docs reviewed", "Simple, works well with templates", "implement_sessions()")
ws.commit("Session auth prototype -- clean integration with Flask")

# Session auth won, merge it
ws.merge("auth-session")

# === Phase 3: Continue on main with context ===
ctx = ws.context(k=2)  # See last 2 commits: the merge + scaffold
# Feed ctx.summary() to the LLM as its "memory"

ws.log_ota("Auth is done", "Now build blog post CRUD", "implement_blog()")
ws.commit("Blog post CRUD with auth-protected routes")

# The agent always knows where it's been, without replaying everything
```

---

## Running Tests

```bash
# Clone the repository
git clone https://github.com/swadhinbiswas/Cortexa.git
cd cortexa

# Install dev dependencies and run tests
uv sync
uv run pytest -v
```

All 13 tests cover the core GCC commands:

```
test_init_creates_gcc_directory       # Workspace initialization
test_log_ota                          # OTA logging
test_commit                           # Milestone commits
test_branch_creates_isolated_workspace # Branch creation
test_branch_has_fresh_ota_log         # Branch isolation
test_merge_integrates_branch          # Branch merging
test_context_k1_returns_last_commit   # Context retrieval (K=1)
test_context_k3_returns_last_three    # Context retrieval (K=3)
test_context_includes_roadmap         # Roadmap in context
test_branch_metadata_records_purpose  # Metadata persistence
test_merge_marks_branch_as_merged     # Post-merge metadata
test_switch_branch                    # Branch switching
test_ota_step_increments              # Step auto-increment
```

---

## Contributing

Contributions are welcome! Here's how to get started:

1. Fork the repository: [https://github.com/swadhinbiswas/Cortexa](https://github.com/swadhinbiswas/Cortexa)
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes and add tests
4. Run the test suite: `uv run pytest -v`
5. Submit a pull request

Please open an [issue](https://github.com/swadhinbiswas/Cortexa/issues) first for major changes to discuss the approach.

---

## Requirements

- **Python** >= 3.10
- **PyYAML** >= 6.0

No other dependencies. The entire implementation uses Python's standard library (`dataclasses`, `pathlib`, `uuid`, `datetime`) plus PyYAML for metadata serialization.

---

## License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/swadhinbiswas/Cortexa/blob/main/LICENSE) file for details.

---

## Citation

If you use this in research, please cite the original paper:

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

- **GitHub Repository**: [https://github.com/swadhinbiswas/Cortexa](https://github.com/swadhinbiswas/Cortexa)
- **PyPI Package**: [https://pypi.org/project/cortexa/](https://pypi.org/project/cortexa/)
- **Issue Tracker**: [https://github.com/swadhinbiswas/Cortexa/issues](https://github.com/swadhinbiswas/Cortexa/issues)
- **Original Paper**: [arXiv:2508.00031v2](https://arxiv.org/abs/2508.00031v2)
- **Author**: [Swadhin Biswas](https://github.com/swadhinbiswas)
