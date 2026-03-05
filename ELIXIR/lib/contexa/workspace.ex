defmodule Contexa.Workspace do
  @moduledoc """
  GCCWorkspace — persistent versioned memory workspace for LLM agents.

  contexa — Git-inspired context management.
  Based on arXiv:2508.00031.
  """

  alias Contexa.Models
  alias Contexa.Models.{OTARecord, CommitRecord, ContextResult}

  @main_branch "main"
  @gcc_dir ".GCC"

  defstruct [:root, :gcc_dir, current_branch: "main"]

  @type t :: %__MODULE__{
          root: String.t(),
          gcc_dir: String.t(),
          current_branch: String.t()
        }

  # ── Constructor ───────────────────────────────────────────────────

  @doc "Create a new workspace handle."
  @spec new(String.t()) :: t()
  def new(project_root) do
    %__MODULE__{
      root: project_root,
      gcc_dir: Path.join(project_root, @gcc_dir),
      current_branch: @main_branch
    }
  end

  # ── Init / Load ──────────────────────────────────────────────────

  @doc "Initialize a fresh .GCC workspace."
  @spec init(t(), String.t()) :: t()
  def init(ws, project_roadmap \\ "") do
    if File.dir?(ws.gcc_dir) do
      raise "Workspace already exists at #{ws.gcc_dir}"
    end

    branch_dir = branch_dir(ws, @main_branch)
    File.mkdir_p!(branch_dir)

    ts = Models.timestamp()

    # main.md
    File.write!(
      Path.join(ws.gcc_dir, "main.md"),
      "# Project Roadmap\n\n**Initialized:** #{ts}\n\n#{project_roadmap}\n"
    )

    # log.md
    File.write!(
      Path.join(branch_dir, "log.md"),
      "# OTA Log — branch `main`\n\n"
    )

    # commit.md
    File.write!(
      Path.join(branch_dir, "commit.md"),
      "# Commit History — branch `main`\n\n"
    )

    # metadata.yaml
    meta = Models.new_branch_metadata(@main_branch, "Primary reasoning trajectory", "")
    File.write!(
      Path.join(branch_dir, "metadata.yaml"),
      Models.metadata_to_yaml(meta)
    )

    %{ws | current_branch: @main_branch}
  end

  @doc "Attach to an existing .GCC workspace."
  @spec load(t()) :: t()
  def load(ws) do
    unless File.dir?(ws.gcc_dir) do
      raise "No workspace found at #{ws.gcc_dir}"
    end

    %{ws | current_branch: @main_branch}
  end

  # ── Branch helpers ───────────────────────────────────────────────

  defp branch_dir(ws, name) do
    Path.join([ws.gcc_dir, "branches", name])
  end

  defp read_file_safe(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  # ── Log OTA ──────────────────────────────────────────────────────

  @doc "Append an OTA cycle to the current branch."
  @spec log_ota(t(), String.t(), String.t(), String.t()) :: {t(), OTARecord.t()}
  def log_ota(ws, observation, thought, action) do
    dir = branch_dir(ws, ws.current_branch)
    log_path = Path.join(dir, "log.md")
    existing = read_file_safe(log_path) |> Models.parse_ota()
    step = length(existing) + 1
    rec = Models.new_ota(step, observation, thought, action)
    File.write!(log_path, read_file_safe(log_path) <> Models.ota_to_markdown(rec))
    {ws, rec}
  end

  # ── Commit ───────────────────────────────────────────────────────

  @doc "COMMIT — checkpoint a milestone on the current branch."
  @spec commit(t(), String.t(), String.t() | nil, String.t() | nil) :: {t(), CommitRecord.t()}
  def commit(ws, contribution, previous_summary \\ nil, update_roadmap \\ nil) do
    dir = branch_dir(ws, ws.current_branch)

    meta = Path.join(dir, "metadata.yaml")
      |> read_file_safe()
      |> Models.metadata_from_yaml()

    branch_purpose = meta.purpose || ""

    previous_summary = if is_nil(previous_summary) or previous_summary == "" do
      commits = Path.join(dir, "commit.md") |> read_file_safe() |> Models.parse_commits()
      if length(commits) > 0 do
        List.last(commits).this_commit_contribution
      else
        "Initial state — no prior commits."
      end
    else
      previous_summary
    end

    rec = Models.new_commit(ws.current_branch, branch_purpose, previous_summary, contribution)

    commit_path = Path.join(dir, "commit.md")
    File.write!(commit_path, read_file_safe(commit_path) <> Models.commit_to_markdown(rec))

    if not is_nil(update_roadmap) and update_roadmap != "" do
      ts = Models.timestamp()
      roadmap_path = Path.join(ws.gcc_dir, "main.md")
      File.write!(
        roadmap_path,
        read_file_safe(roadmap_path) <> "\n## Update (#{ts})\n#{update_roadmap}\n"
      )
    end

    {ws, rec}
  end

  # ── Branch ───────────────────────────────────────────────────────

  @doc "BRANCH — create an isolated reasoning workspace."
  @spec branch(t(), String.t(), String.t()) :: t()
  def branch(ws, name, purpose) do
    dir = branch_dir(ws, name)
    if File.dir?(dir) do
      raise "Branch already exists: #{name}"
    end

    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "log.md"),
      "# OTA Log — branch `#{name}`\n\n"
    )
    File.write!(
      Path.join(dir, "commit.md"),
      "# Commit History — branch `#{name}`\n\n"
    )

    meta = Models.new_branch_metadata(name, purpose, ws.current_branch)
    File.write!(
      Path.join(dir, "metadata.yaml"),
      Models.metadata_to_yaml(meta)
    )

    %{ws | current_branch: name}
  end

  # ── Switch ───────────────────────────────────────────────────────

  @doc "Switch to an existing branch."
  @spec switch_branch(t(), String.t()) :: t()
  def switch_branch(ws, name) do
    dir = branch_dir(ws, name)
    unless File.dir?(dir) do
      raise "Branch does not exist: #{name}"
    end
    %{ws | current_branch: name}
  end

  # ── List branches ────────────────────────────────────────────────

  @doc "List all branches."
  @spec list_branches(t()) :: [String.t()]
  def list_branches(ws) do
    branches_dir = Path.join(ws.gcc_dir, "branches")
    case File.ls(branches_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn entry ->
          File.dir?(Path.join(branches_dir, entry))
        end)
        |> Enum.sort()
      {:error, _} -> []
    end
  end

  # ── Merge ────────────────────────────────────────────────────────

  @doc "MERGE — integrate a branch back into a target."
  @spec merge(t(), String.t(), String.t() | nil, String.t()) :: {t(), CommitRecord.t()}
  def merge(ws, branch_name, summary \\ nil, target \\ "main") do
    src_dir = branch_dir(ws, branch_name)
    tgt_dir = branch_dir(ws, target)

    unless File.dir?(src_dir), do: raise("Source branch does not exist: #{branch_name}")
    unless File.dir?(tgt_dir), do: raise("Target branch does not exist: #{target}")

    src_commits = Path.join(src_dir, "commit.md") |> read_file_safe() |> Models.parse_commits()
    src_ota = Path.join(src_dir, "log.md") |> read_file_safe() |> Models.parse_ota()
    src_meta = Path.join(src_dir, "metadata.yaml") |> read_file_safe() |> Models.metadata_from_yaml()

    summary = if is_nil(summary) or summary == "" do
      contributions = Enum.map(src_commits, & &1.this_commit_contribution) |> Enum.join(" | ")
      "Merged branch `#{branch_name}` (#{length(src_commits)} commits). Contributions: #{contributions}"
    else
      summary
    end

    # Append OTA records from source to target
    if length(src_ota) > 0 do
      ts = Models.timestamp()
      tgt_log = Path.join(tgt_dir, "log.md")
      header = "\n## Merged from `#{branch_name}` (#{ts})\n\n"
      ota_text = Enum.map(src_ota, &Models.ota_to_markdown/1) |> Enum.join("")
      File.write!(tgt_log, read_file_safe(tgt_log) <> header <> ota_text)
    end

    # Switch to target and create merge commit
    ws = %{ws | current_branch: target}
    prev = "Merging branch `#{branch_name}` with purpose: #{src_meta.purpose || ""}"
    roadmap_update = "Merged `#{branch_name}`: #{summary}"
    {ws, commit_rec} = commit(ws, summary, prev, roadmap_update)

    # Update source metadata
    ts = Models.timestamp()
    updated_meta = %{src_meta | status: "merged", merged_into: target, merged_at: ts}
    File.write!(Path.join(src_dir, "metadata.yaml"), Models.metadata_to_yaml(updated_meta))

    {ws, commit_rec}
  end

  # ── Context ──────────────────────────────────────────────────────

  @doc "CONTEXT — hierarchical memory retrieval."
  @spec context(t(), String.t() | nil, non_neg_integer()) :: ContextResult.t()
  def context(ws, branch_name \\ nil, k \\ 1) do
    branch_name = branch_name || ws.current_branch
    dir = branch_dir(ws, branch_name)

    unless File.dir?(dir), do: raise("Branch does not exist: #{branch_name}")

    all_commits = Path.join(dir, "commit.md") |> read_file_safe() |> Models.parse_commits()
    all_ota = Path.join(dir, "log.md") |> read_file_safe() |> Models.parse_ota()
    roadmap = Path.join(ws.gcc_dir, "main.md") |> read_file_safe()

    meta_text = Path.join(dir, "metadata.yaml") |> read_file_safe()
    meta = if meta_text != "", do: Models.metadata_from_yaml(meta_text), else: nil

    commits = Enum.take(all_commits, -k)

    %ContextResult{
      branch_name: branch_name,
      k: k,
      commits: commits,
      ota_records: all_ota,
      main_roadmap: roadmap,
      metadata: meta
    }
  end
end
