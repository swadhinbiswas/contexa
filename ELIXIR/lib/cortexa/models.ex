defmodule Cortexa.Models do
  @moduledoc """
  Data structures for the cortexa GCC workspace.

  cortexa — Git-inspired context management for LLM agents.
  Based on arXiv:2508.00031.
  """

  # ── OTARecord ─────────────────────────────────────────────────────

  defmodule OTARecord do
    @moduledoc "An Observation-Thought-Action cycle record."
    defstruct [:step, :timestamp, :observation, :thought, :action]

    @type t :: %__MODULE__{
            step: non_neg_integer(),
            timestamp: String.t(),
            observation: String.t(),
            thought: String.t(),
            action: String.t()
          }
  end

  defmodule CommitRecord do
    @moduledoc "A milestone checkpoint record."
    defstruct [
      :commit_id,
      :branch_name,
      :branch_purpose,
      :previous_progress_summary,
      :this_commit_contribution,
      :timestamp
    ]

    @type t :: %__MODULE__{
            commit_id: String.t(),
            branch_name: String.t(),
            branch_purpose: String.t(),
            previous_progress_summary: String.t(),
            this_commit_contribution: String.t(),
            timestamp: String.t()
          }
  end

  defmodule BranchMetadata do
    @moduledoc "Branch metadata stored in metadata.yaml."
    defstruct [
      :name,
      :purpose,
      :created_from,
      :created_at,
      status: "active",
      merged_into: nil,
      merged_at: nil
    ]

    @type t :: %__MODULE__{
            name: String.t(),
            purpose: String.t(),
            created_from: String.t(),
            created_at: String.t(),
            status: String.t(),
            merged_into: String.t() | nil,
            merged_at: String.t() | nil
          }
  end

  defmodule ContextResult do
    @moduledoc "Result of a CONTEXT query."
    defstruct [
      :branch_name,
      :k,
      commits: [],
      ota_records: [],
      main_roadmap: "",
      metadata: nil
    ]

    @type t :: %__MODULE__{
            branch_name: String.t(),
            k: non_neg_integer(),
            commits: [CommitRecord.t()],
            ota_records: [OTARecord.t()],
            main_roadmap: String.t(),
            metadata: BranchMetadata.t() | nil
          }
  end

  # ── Constructors ──────────────────────────────────────────────────

  @doc "Generate an 8-character hex ID."
  @spec generate_id() :: String.t()
  def generate_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end

  @doc "Get current UTC timestamp in ISO 8601 format."
  @spec timestamp() :: String.t()
  def timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  @doc "Create a new OTARecord."
  @spec new_ota(non_neg_integer(), String.t(), String.t(), String.t()) :: OTARecord.t()
  def new_ota(step, observation, thought, action) do
    %OTARecord{
      step: step,
      timestamp: timestamp(),
      observation: observation || "",
      thought: thought || "",
      action: action || ""
    }
  end

  @doc "Create a new CommitRecord."
  @spec new_commit(String.t(), String.t(), String.t(), String.t()) :: CommitRecord.t()
  def new_commit(branch_name, branch_purpose, previous_summary, contribution) do
    %CommitRecord{
      commit_id: generate_id(),
      branch_name: branch_name,
      branch_purpose: branch_purpose || "",
      previous_progress_summary: previous_summary || "",
      this_commit_contribution: contribution || "",
      timestamp: timestamp()
    }
  end

  @doc "Create a new BranchMetadata."
  @spec new_branch_metadata(String.t(), String.t(), String.t()) :: BranchMetadata.t()
  def new_branch_metadata(name, purpose, created_from \\ "") do
    %BranchMetadata{
      name: name,
      purpose: purpose,
      created_from: created_from,
      created_at: timestamp(),
      status: "active",
      merged_into: nil,
      merged_at: nil
    }
  end

  # ── Input sanitization ─────────────────────────────────────────────

  @doc "Escape separator sequences in user-provided content."
  @spec sanitize(String.t()) :: String.t()
  def sanitize(text) when is_binary(text) do
    String.replace(text, "\n---\n", "\n\\---\n")
  end
  def sanitize(nil), do: ""

  @doc "Reverse the escaping applied by sanitize."
  @spec desanitize(String.t()) :: String.t()
  def desanitize(text) when is_binary(text) do
    String.replace(text, "\n\\---\n", "\n---\n")
  end
  def desanitize(nil), do: ""

  @doc """
  Split markdown text on separator while respecting escaped separators.

  After naive splitting on the delimiter, blocks whose predecessor ends
  with `\\` are rejoined (the backslash means `\\---\\n` was an escaped
  separator produced by `sanitize/1`).
  """
  @spec split_blocks(String.t(), String.t()) :: [String.t()]
  def split_blocks(text, delim \\ "\n---\n") do
    text
    |> String.split(delim)
    |> rejoin_escaped(delim, [])
  end

  defp rejoin_escaped([], _delim, acc), do: Enum.reverse(acc)
  defp rejoin_escaped([block | rest], delim, []) do
    rejoin_escaped(rest, delim, [block])
  end
  defp rejoin_escaped([block | rest], delim, [prev | acc]) do
    if String.ends_with?(prev, "\\") do
      rejoin_escaped(rest, delim, [prev <> delim <> block | acc])
    else
      rejoin_escaped(rest, delim, [block, prev | acc])
    end
  end

  # ── Markdown serialization ────────────────────────────────────────

  @doc "Render an OTARecord as markdown."
  @spec ota_to_markdown(OTARecord.t()) :: String.t()
  def ota_to_markdown(%OTARecord{} = rec) do
    """
    ### Step #{rec.step} — #{rec.timestamp}
    **Observation:** #{sanitize(rec.observation)}

    **Thought:** #{sanitize(rec.thought)}

    **Action:** #{sanitize(rec.action)}

    ---
    """
  end

  @doc "Render a CommitRecord as markdown."
  @spec commit_to_markdown(CommitRecord.t()) :: String.t()
  def commit_to_markdown(%CommitRecord{} = rec) do
    """
    ## Commit `#{rec.commit_id}`
    **Timestamp:** #{rec.timestamp}

    **Branch Purpose:** #{sanitize(rec.branch_purpose)}

    **Previous Progress Summary:** #{sanitize(rec.previous_progress_summary)}

    **This Commit's Contribution:** #{sanitize(rec.this_commit_contribution)}

    ---
    """
  end

  # ── YAML serialization ───────────────────────────────────────────

  @doc "Serialize BranchMetadata to YAML string."
  @spec metadata_to_yaml(BranchMetadata.t()) :: String.t()
  def metadata_to_yaml(%BranchMetadata{} = meta) do
    yaml_val = fn
      nil -> "null"
      "" -> "''"
      v when is_binary(v) ->
        if String.contains?(v, ":") or String.contains?(v, "#") do
          "'#{String.replace(v, "'", "''")}'"
        else
          v
        end
    end

    # Keys in sorted order for cross-language compatibility
    [
      "created_at: #{yaml_val.(meta.created_at)}",
      "created_from: #{yaml_val.(meta.created_from)}",
      "merged_at: #{yaml_val.(meta.merged_at)}",
      "merged_into: #{yaml_val.(meta.merged_into)}",
      "name: #{yaml_val.(meta.name)}",
      "purpose: #{yaml_val.(meta.purpose)}",
      "status: #{yaml_val.(meta.status)}"
    ]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc "Parse BranchMetadata from YAML string."
  @spec metadata_from_yaml(String.t()) :: BranchMetadata.t()
  def metadata_from_yaml(text) do
    pairs =
      text
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case Regex.run(~r/^(\S+):\s*(.*)$/, line) do
          [_, key, val] ->
            val = val |> String.trim()
            val = cond do
              val == "null" -> nil
              val == "''" -> ""
              String.starts_with?(val, "'") and String.ends_with?(val, "'") ->
                val |> String.slice(1..-2//1) |> String.replace("''", "'")
              true -> val
            end
            Map.put(acc, key, val)
          _ -> acc
        end
      end)

    %BranchMetadata{
      name: Map.get(pairs, "name", ""),
      purpose: Map.get(pairs, "purpose", ""),
      created_from: Map.get(pairs, "created_from", ""),
      created_at: Map.get(pairs, "created_at", ""),
      status: Map.get(pairs, "status", "active"),
      merged_into: Map.get(pairs, "merged_into"),
      merged_at: Map.get(pairs, "merged_at")
    }
  end

  # ── Markdown parsing ──────────────────────────────────────────────

  @doc "Parse commit records from commit.md content."
  @spec parse_commits(String.t()) :: [CommitRecord.t()]
  def parse_commits(text) do
    text
    |> split_blocks("\n---\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.reduce([], fn block, acc ->
      commit_id = case Regex.run(~r/## Commit `([^`]+)`/, block) do
        [_, id] -> id
        _ -> ""
      end

      if commit_id != "" do
        extract = fn pattern ->
          case Regex.run(pattern, block) do
            [_, val] -> String.trim(val)
            _ -> ""
          end
        end

        rec = %CommitRecord{
          commit_id: commit_id,
          branch_name: "",
          timestamp: extract.(~r/\*\*Timestamp:\*\*\s*(.+)/),
          branch_purpose: desanitize(extract.(~r/\*\*Branch Purpose:\*\*\s*([\s\S]+?)(?=\n\n\*\*|\z)/)),
          previous_progress_summary: desanitize(extract.(~r/\*\*Previous Progress Summary:\*\*\s*([\s\S]+?)(?=\n\n\*\*|\z)/)),
          this_commit_contribution: desanitize(extract.(~r/\*\*This Commit's Contribution:\*\*\s*([\s\S]+?)(?=\n\n\*\*|\n\n---|\z)/))
        }
        acc ++ [rec]
      else
        acc
      end
    end)
  end

  @doc "Parse OTA records from log.md content."
  @spec parse_ota(String.t()) :: [OTARecord.t()]
  def parse_ota(text) do
    text
    |> split_blocks("\n---\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.reduce([], fn block, acc ->
      {step, ts} = case Regex.run(~r/### Step (\d+)\s*[—-]\s*(.+)/, block) do
        [_, s, t] -> {String.to_integer(s), String.trim(t)}
        _ -> {0, ""}
      end

      extract = fn pattern ->
        case Regex.run(pattern, block) do
          [_, val] -> String.trim(val)
          _ -> ""
        end
      end

      obs = desanitize(extract.(~r/\*\*Observation:\*\*\s*([\s\S]+?)(?=\n\n\*\*|\z)/))
      thought = desanitize(extract.(~r/\*\*Thought:\*\*\s*([\s\S]+?)(?=\n\n\*\*|\z)/))
      action = desanitize(extract.(~r/\*\*Action:\*\*\s*([\s\S]+?)(?=\n\n\*\*|\n\n---|\z)/))

      if obs != "" or thought != "" or action != "" do
        rec = %OTARecord{
          step: step,
          timestamp: ts,
          observation: obs,
          thought: thought,
          action: action
        }
        acc ++ [rec]
      else
        acc
      end
    end)
  end

  # ── Context summary ──────────────────────────────────────────────

  @doc "Render a ContextResult as a markdown summary."
  @spec context_summary(ContextResult.t()) :: String.t()
  def context_summary(%ContextResult{} = ctx) do
    commit_text = ctx.commits
      |> Enum.map(&commit_to_markdown/1)
      |> Enum.join("\n")

    total = length(ctx.ota_records)
    recent_ota = ctx.ota_records |> Enum.take(-5)
    ota_text = recent_ota
      |> Enum.map(&ota_to_markdown/1)
      |> Enum.join("\n")

    """
    # CONTEXT — branch `#{ctx.branch_name}` (K=#{ctx.k})

    ## Global Roadmap
    #{ctx.main_roadmap}

    ## Last #{ctx.k} Commit(s)
    #{commit_text}

    ## Recent OTA steps (#{total} total)
    #{ota_text}
    """
  end
end
