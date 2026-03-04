# contexa — Elixir

Git-inspired context management for LLM agents — **COMMIT**, **BRANCH**, **MERGE**, and **CONTEXT** operations over a persistent versioned memory workspace.

Based on the paper *"Git Context Controller: Manage the Context of LLM-based Agents like Git"* ([arXiv:2508.00031](https://arxiv.org/abs/2508.00031)).

## Install

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:contexa, "~> 0.1.1"}
  ]
end
```

## Quick Start

```elixir
alias Contexa.{Workspace, Models}

# Create workspace
ws = Workspace.new("/tmp/my-project")
ws = Workspace.init(ws, "Build an AI agent")

# Log observations
{ws, _ota} = Workspace.log_ota(ws, "User asked about weather", "Need to call API", "Called weather API")

# Commit milestone
{ws, _commit} = Workspace.commit(ws, "Implemented weather lookup")

# Branch for exploration
ws = Workspace.branch(ws, "alt-approach", "Try different API")
{ws, _ota} = Workspace.log_ota(ws, "Testing new API", "Seems faster", "Switched to new API")
{ws, _commit} = Workspace.commit(ws, "New API integration")

# Merge back
{ws, _merge} = Workspace.merge(ws, "alt-approach", nil, "main")

# Retrieve context
ctx = Workspace.context(ws, "main", 3)
IO.puts(Models.context_summary(ctx))
```

## API

### `Contexa.Workspace`

| Function | Description |
|----------|-------------|
| `new(root)` | Create workspace handle |
| `init(ws, roadmap \\ "")` | Initialize `.GCC/` directory |
| `load(ws)` | Attach to existing workspace |
| `log_ota(ws, obs, thought, action)` | Append OTA record |
| `commit(ws, contribution, prev \\ nil, roadmap \\ nil)` | Create milestone commit |
| `branch(ws, name, purpose)` | Create isolated branch |
| `merge(ws, branch, summary \\ nil, target \\ "main")` | Merge branch into target |
| `context(ws, branch \\ nil, k \\ 1)` | Retrieve hierarchical context |
| `switch_branch(ws, name)` | Switch active branch |
| `list_branches(ws)` | List all branches |

### Functional Style

The Elixir implementation uses a functional approach — workspace state is an immutable struct returned from each operation:

```elixir
ws = Workspace.new("/tmp/project") |> Workspace.init()
{ws, _} = Workspace.log_ota(ws, "obs", "thought", "action")
{ws, _} = Workspace.commit(ws, "milestone")
```

## License

MIT
