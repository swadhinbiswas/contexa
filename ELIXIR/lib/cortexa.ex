defmodule Cortexa do
  @moduledoc """
  cortexa — Git-inspired context management for LLM agents.

  COMMIT, BRANCH, MERGE, and CONTEXT operations over a persistent
  versioned memory workspace. Based on arXiv:2508.00031.

  ## Quick Start

      ws = Cortexa.Workspace.new("/tmp/my-project")
      ws = Cortexa.Workspace.init(ws, "Build an AI agent")

      {ws, _ota} = Cortexa.Workspace.log_ota(ws, "Observed X", "Thinking Y", "Did Z")
      {ws, _commit} = Cortexa.Workspace.commit(ws, "Implemented feature")

      ws = Cortexa.Workspace.branch(ws, "explore", "Try alternative approach")
      {ws, _commit} = Cortexa.Workspace.merge(ws, "explore")

      ctx = Cortexa.Workspace.context(ws, "main", 3)
      IO.puts(Cortexa.Models.context_summary(ctx))
  """
end
