defmodule Cortexa.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Cortexa.Workspace
  alias Cortexa.Models

  defp make_tmp do
    dir = Path.join(System.tmp_dir!(), "cortexa_ex_test_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp cleanup(dir) do
    File.rm_rf!(dir)
  end

  test "init creates workspace" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init("Test roadmap")
    assert ws.current_branch == "main"
    assert File.dir?(Path.join(dir, ".GCC"))
    cleanup(dir)
  end

  test "init fails if already exists" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    assert_raise RuntimeError, fn ->
      Workspace.init(ws)
    end
    cleanup(dir)
  end

  test "load attaches to existing workspace" do
    dir = make_tmp()
    Workspace.new(dir) |> Workspace.init()
    ws = Workspace.new(dir) |> Workspace.load()
    assert ws.current_branch == "main"
    cleanup(dir)
  end

  test "load fails if no workspace" do
    dir = make_tmp()
    assert_raise RuntimeError, fn ->
      Workspace.new(dir) |> Workspace.load()
    end
    cleanup(dir)
  end

  test "log_ota appends records with incrementing steps" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    {ws, r1} = Workspace.log_ota(ws, "obs1", "thought1", "act1")
    assert r1.step == 1
    {_ws, r2} = Workspace.log_ota(ws, "obs2", "thought2", "act2")
    assert r2.step == 2
    cleanup(dir)
  end

  test "commit creates record with auto previous_summary" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    {ws, c1} = Workspace.commit(ws, "First contribution")
    assert String.length(c1.commit_id) == 8
    {_ws, c2} = Workspace.commit(ws, "Second contribution")
    assert c2.previous_progress_summary == "First contribution"
    cleanup(dir)
  end

  test "branch creates isolated workspace" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    {ws, _} = Workspace.log_ota(ws, "obs", "thought", "action")
    ws = Workspace.branch(ws, "feature", "Test feature")
    assert ws.current_branch == "feature"
    ctx = Workspace.context(ws, "feature", 10)
    assert length(ctx.ota_records) == 0
    assert length(ctx.commits) == 0
    cleanup(dir)
  end

  test "branch fails if duplicate name" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    ws = Workspace.branch(ws, "dup", "purpose")
    ws = Workspace.switch_branch(ws, "main")
    assert_raise RuntimeError, fn ->
      Workspace.branch(ws, "dup", "purpose")
    end
    cleanup(dir)
  end

  test "switch_branch changes current branch" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    ws = Workspace.branch(ws, "feature", "purpose")
    ws = Workspace.switch_branch(ws, "main")
    assert ws.current_branch == "main"
    cleanup(dir)
  end

  test "switch_branch fails on non-existent branch" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    assert_raise RuntimeError, fn ->
      Workspace.switch_branch(ws, "nope")
    end
    cleanup(dir)
  end

  test "list_branches returns all branches" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    ws = Workspace.branch(ws, "alpha", "purpose a")
    ws = Workspace.switch_branch(ws, "main")
    ws = Workspace.branch(ws, "beta", "purpose b")
    branches = Workspace.list_branches(ws)
    assert length(branches) >= 3
    cleanup(dir)
  end

  test "merge integrates branch into target" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    ws = Workspace.branch(ws, "feature", "Add feature X")
    {ws, _} = Workspace.log_ota(ws, "obs", "thought", "action")
    {ws, _} = Workspace.commit(ws, "Implemented feature X")
    {ws, merge_rec} = Workspace.merge(ws, "feature", nil, "main")
    assert ws.current_branch == "main"
    assert String.length(merge_rec.commit_id) == 8
    ctx = Workspace.context(ws, "main", 10)
    assert length(ctx.commits) >= 1
    cleanup(dir)
  end

  test "merge fails on non-existent source" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    assert_raise RuntimeError, fn ->
      Workspace.merge(ws, "nope")
    end
    cleanup(dir)
  end

  test "context returns correct data" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init("My roadmap")
    {ws, _} = Workspace.log_ota(ws, "obs1", "t1", "a1")
    {ws, _} = Workspace.log_ota(ws, "obs2", "t2", "a2")
    {ws, _} = Workspace.commit(ws, "Commit 1")
    {ws, _} = Workspace.commit(ws, "Commit 2")
    {ws, _} = Workspace.commit(ws, "Commit 3")
    ctx = Workspace.context(ws, "main", 2)
    assert length(ctx.commits) == 2
    assert length(ctx.ota_records) == 2
    assert ctx.main_roadmap =~ "My roadmap"
    assert ctx.metadata != nil
    assert ctx.metadata.name == "main"
    cleanup(dir)
  end

  test "context k larger than available commits" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init()
    {ws, _} = Workspace.commit(ws, "Only commit")
    ctx = Workspace.context(ws, "main", 100)
    assert length(ctx.commits) == 1
    cleanup(dir)
  end

  test "context_summary renders markdown" do
    dir = make_tmp()
    ws = Workspace.new(dir) |> Workspace.init("Roadmap text")
    {ws, _} = Workspace.log_ota(ws, "obs", "thought", "action")
    {ws, _} = Workspace.commit(ws, "My contribution")
    ctx = Workspace.context(ws, "main", 1)
    summary = Models.context_summary(ctx)
    assert summary =~ "CONTEXT"
    assert summary =~ "Roadmap"
    assert summary =~ "My contribution"
    cleanup(dir)
  end
end
