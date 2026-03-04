defmodule Contexa.ModelsTest do
  use ExUnit.Case, async: true

  alias Contexa.Models
  alias Contexa.Models.{OTARecord, CommitRecord, BranchMetadata}

  test "generate_id returns 8 hex chars" do
    id = Models.generate_id()
    assert String.length(id) == 8
    assert Regex.match?(~r/^[0-9a-f]+$/, id)
  end

  test "timestamp returns ISO 8601" do
    ts = Models.timestamp()
    assert Regex.match?(~r/^\d{4}-\d{2}-\d{2}T/, ts)
  end

  test "OTA to_markdown renders correctly" do
    rec = %OTARecord{step: 1, timestamp: "2026-01-01T00:00:00Z",
      observation: "saw something", thought: "thinking", action: "did something"}
    md = Models.ota_to_markdown(rec)
    assert md =~ "### Step 1"
    assert md =~ "saw something"
    assert md =~ "thinking"
    assert md =~ "did something"
  end

  test "Commit to_markdown renders correctly" do
    rec = %CommitRecord{commit_id: "abc12345", branch_name: "main",
      branch_purpose: "purpose", previous_progress_summary: "prev",
      this_commit_contribution: "contrib", timestamp: "2026-01-01T00:00:00Z"}
    md = Models.commit_to_markdown(rec)
    assert md =~ "## Commit `abc12345`"
    assert md =~ "purpose"
    assert md =~ "contrib"
  end

  test "BranchMetadata YAML round-trip" do
    meta = Models.new_branch_metadata("test-branch", "test purpose", "main")
    yaml = Models.metadata_to_yaml(meta)
    parsed = Models.metadata_from_yaml(yaml)
    assert parsed.name == "test-branch"
    assert parsed.purpose == "test purpose"
    assert parsed.created_from == "main"
    assert parsed.status == "active"
    assert parsed.merged_into == nil
  end

  test "parse_commits extracts records" do
    text = """
    # Header

    ## Commit `abc12345`
    **Timestamp:** 2026-01-01T00:00:00Z

    **Branch Purpose:** test

    **Previous Progress Summary:** prev

    **This Commit's Contribution:** contrib

    ---
    """
    commits = Models.parse_commits(text)
    assert length(commits) == 1
    assert hd(commits).commit_id == "abc12345"
    assert hd(commits).this_commit_contribution == "contrib"
  end

  test "parse_ota extracts records" do
    text = """
    # Header

    ### Step 1 — 2026-01-01T00:00:00Z
    **Observation:** obs1

    **Thought:** thought1

    **Action:** action1

    ---
    """
    records = Models.parse_ota(text)
    assert length(records) == 1
    assert hd(records).step == 1
    assert hd(records).observation == "obs1"
  end
end
