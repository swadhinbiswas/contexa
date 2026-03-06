# cortexa — Lua

Git-inspired context management for LLM agents — **COMMIT**, **BRANCH**, **MERGE**, and **CONTEXT** operations over a persistent versioned memory workspace.

Based on the paper *"Git Context Controller: Manage the Context of LLM-based Agents like Git"* ([arXiv:2508.00031](https://arxiv.org/abs/2508.00031)).

## Install

```bash
luarocks install cortexa
```

## Quick Start

```lua
local cortexa = require("cortexa")

-- Create workspace
local ws = cortexa.GCCWorkspace.new("/tmp/my-project")
ws:init("Build an AI agent")

-- Log observations
ws:log_ota("User asked about weather", "Need to call API", "Called weather API")

-- Commit milestone
ws:commit("Implemented weather lookup")

-- Branch for exploration
ws:branch("alt-approach", "Try different API")
ws:log_ota("Testing new API", "Seems faster", "Switched to new API")
ws:commit("New API integration")

-- Merge back
ws:merge("alt-approach", nil, "main")

-- Retrieve context
local ctx = ws:context("main", 3)
print(cortexa.context_summary(ctx))
```

## API

| Method | Description |
|--------|-------------|
| `GCCWorkspace.new(root)` | Create workspace handle |
| `ws:init(roadmap?)` | Initialize `.GCC/` directory |
| `ws:load()` | Attach to existing workspace |
| `ws:log_ota(obs, thought, action)` | Append OTA record |
| `ws:commit(contribution, prev?, roadmap?)` | Create milestone commit |
| `ws:branch(name, purpose)` | Create isolated branch |
| `ws:merge(branch, summary?, target?)` | Merge branch into target |
| `ws:context(branch?, k?)` | Retrieve hierarchical context |
| `ws:switch_branch(name)` | Switch active branch |
| `ws:list_branches()` | List all branches |
| `ws:current_branch()` | Get active branch name |

## Requirements

- Lua 5.1+ or LuaJIT
- LuaFileSystem (`lfs`) — optional but recommended for portable directory operations

## License

MIT
