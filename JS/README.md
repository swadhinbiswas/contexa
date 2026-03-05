# contexa

[![npm version](https://img.shields.io/npm/v/contexa.svg)](https://www.npmjs.com/package/contexa)
[![Node.js 18+](https://img.shields.io/badge/node-18%2B-blue.svg)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-swadhinbiswas%2FCortexa-black.svg?logo=github)](https://github.com/swadhinbiswas/Cortexa)

**Git-inspired context management for LLM agents.** COMMIT, BRANCH, MERGE, and CONTEXT operations over a persistent versioned memory workspace.

TypeScript/JavaScript implementation of the **contexa** framework.

Based on: [arXiv:2508.00031](https://arxiv.org/abs/2508.00031) -- *"Git Context Controller: Manage the Context of LLM-based Agents like Git"* (Junde Wu et al., 2025)

---

## Installation

```bash
npm install contexa
```

Or with yarn/pnpm:

```bash
yarn add contexa
pnpm add contexa
```

---

## Quick Start

```typescript
import { GCCWorkspace } from "contexa";

// 1. Initialize a workspace
const ws = new GCCWorkspace("/path/to/project");
ws.init("Build a REST API service with user auth");

// 2. Agent logs its reasoning as it works
ws.logOTA(
  "Project directory is empty",
  "Need to scaffold the project structure first",
  "create_files(['main.ts', 'package.json', 'models.ts'])"
);

// 3. Commit a milestone (compresses OTA history)
ws.commit("Project scaffold and User model complete");

// 4. Branch to explore an alternative approach
ws.branch("auth-jwt", "Explore JWT-based authentication");
ws.logOTA("Reading JWT docs", "JWT is stateless, good for APIs", "implementJWT()");
ws.commit("JWT auth middleware implemented");

// 5. Merge the successful branch back
ws.merge("auth-jwt");

// 6. Retrieve context for the agent's next step
const ctx = ws.context(undefined, 1); // K=1: paper default
console.log(ctx.summary());
```

---

## Core Concepts

### OTA Logging (Observation-Thought-Action)

Every reasoning step is an OTA cycle, logged continuously in `log.md`:

```typescript
const rec = ws.logOTA(
  "API returns 500 error on /users endpoint",
  "The database connection might not be initialized",
  "checkDbConnection()"
);
console.log(rec.step);      // 1 (auto-incremented)
console.log(rec.timestamp); // 2025-03-04T12:00:00.000Z
```

### COMMIT -- Save Milestones

```typescript
const commit = ws.commit(
  "Fixed database connection and /users endpoint returns 200",
  undefined,                       // previous summary auto-populated
  "Database layer stable, move on" // optional roadmap update
);
console.log(commit.commitId);   // "a3f2b1c4" (8-char hex)
console.log(commit.branchName); // "main"
```

### BRANCH -- Explore Alternatives

```typescript
ws.branch("redis-cache", "Try Redis caching instead of in-memory");
ws.logOTA("Redis docs reviewed", "Need redis package", "npmInstall('redis')");
ws.commit("Redis caching layer implemented");

console.log(ws.listBranches()); // ['main', 'redis-cache']
console.log(ws.currentBranch); // 'redis-cache'
```

### MERGE -- Integrate Results

```typescript
const mergeCommit = ws.merge("redis-cache", undefined, "main");
// - Appends branch OTA trace to main's log
// - Creates a merge commit on main
// - Marks branch as "merged" in metadata
console.log(ws.currentBranch); // 'main'
```

### CONTEXT -- Retrieve History

```typescript
// K=1: only the most recent commit (paper's recommended default)
const ctx = ws.context(undefined, 1);

console.log(ctx.branchName);  // "main"
console.log(ctx.mainRoadmap); // Global project roadmap
console.log(ctx.commits);     // Last K CommitRecord objects
console.log(ctx.otaRecords);  // All OTA records on the branch
console.log(ctx.metadata);    // BranchMetadata object

// Formatted markdown summary ready for LLM prompt injection
const promptContext = ctx.summary();
```

---

## API Reference

### `GCCWorkspace`

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `constructor` | `projectRoot: string` | -- | Set the project root directory |
| `init` | `projectRoadmap?: string` | `void` | Create `.GCC/` structure with main branch |
| `load` | -- | `void` | Load an existing workspace |
| `logOTA` | `observation, thought, action` | `OTARecord` | Append OTA step to current branch |
| `commit` | `contribution, previousSummary?, updateRoadmap?` | `CommitRecord` | Create milestone checkpoint |
| `branch` | `name, purpose` | `void` | Create and switch to new branch |
| `merge` | `branchName, summary?, target?` | `CommitRecord` | Merge branch into target |
| `context` | `branch?, k?` | `ContextResult` | Retrieve historical context |
| `switchBranch` | `name` | `void` | Switch active branch |
| `listBranches` | -- | `string[]` | List all branch names |
| `currentBranch` | *(getter)* | `string` | Get current active branch name |

---

## Type Definitions

```typescript
interface OTARecord {
  step: number;
  timestamp: string;
  observation: string;
  thought: string;
  action: string;
}

interface CommitRecord {
  commitId: string;
  branchName: string;
  branchPurpose: string;
  previousProgressSummary: string;
  thisCommitContribution: string;
  timestamp: string;
}

interface BranchMetadata {
  name: string;
  purpose: string;
  createdFrom: string;
  createdAt: string;
  status: "active" | "merged" | "abandoned";
  mergedInto?: string;
  mergedAt?: string;
}

interface ContextResult {
  branchName: string;
  k: number;
  commits: CommitRecord[];
  otaRecords: OTARecord[];
  mainRoadmap: string;
  metadata?: BranchMetadata;
  summary(): string;
}
```

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
cd contexa/JS
npm install
npm test
```

---

## Building

```bash
npm run build
# Outputs dist/index.js (CJS), dist/index.mjs (ESM), dist/index.d.ts (types)
```

---

## Requirements

- **Node.js** >= 18
- **js-yaml** >= 4.1.0

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
- [npm Package](https://www.npmjs.com/package/contexa)
- [Original Paper](https://arxiv.org/abs/2508.00031)
- [Author: Swadhin Biswas](https://github.com/swadhinbiswas)
