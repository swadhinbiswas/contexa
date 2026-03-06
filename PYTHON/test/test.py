"""Tests for Cortexa Python package."""

import pytest
from cortexa import GCCWorkspace


@pytest.fixture
def ws(tmp_path):
    workspace = GCCWorkspace(str(tmp_path))
    workspace.init("Test project roadmap")
    return workspace


def test_init_creates_gcc_directory(tmp_path):
    ws = GCCWorkspace(str(tmp_path))
    ws.init("Test project")
    assert (tmp_path / ".GCC" / "main.md").exists()
    assert (tmp_path / ".GCC" / "branches" / "main" / "log.md").exists()
    assert (tmp_path / ".GCC" / "branches" / "main" / "commit.md").exists()
    assert (tmp_path / ".GCC" / "branches" / "main" / "metadata.yaml").exists()


def test_log_ota(ws):
    rec = ws.log_ota("saw empty dir", "should read files", "list_files()")
    assert rec.step == 1
    assert rec.observation == "saw empty dir"


def test_commit(ws):
    ws.log_ota("obs", "thought", "action")
    commit = ws.commit("Initial scaffold done")
    assert commit.this_commit_contribution == "Initial scaffold done"
    assert commit.branch_name == "main"
    assert len(commit.commit_id) == 8


def test_branch_creates_isolated_workspace(ws):
    ws.branch("experiment-a", "Try alternative algorithm")
    assert ws.current_branch == "experiment-a"
    branches = ws.list_branches()
    assert "main" in branches
    assert "experiment-a" in branches


def test_branch_has_fresh_ota_log(ws):
    ws.log_ota("main obs", "main thought", "main action")
    ws.branch("clean-branch", "Fresh start")
    ota = ws._read_ota("clean-branch")
    assert ota == []


def test_merge_integrates_branch(ws):
    ws.commit("Main first commit")
    ws.branch("feature", "Add feature X")
    ws.log_ota("feature obs", "feature thought", "feature action")
    ws.commit("Feature X implemented")
    merge_commit = ws.merge("feature", target="main")
    assert "feature" in merge_commit.this_commit_contribution.lower()
    assert ws.current_branch == "main"


def test_context_k1_returns_last_commit(ws):
    ws.commit("First commit")
    ws.commit("Second commit")
    ws.commit("Third commit")
    ctx = ws.context(k=1)
    assert len(ctx.commits) == 1
    assert ctx.commits[0].this_commit_contribution == "Third commit"


def test_context_k3_returns_last_three(ws):
    ws.commit("C1")
    ws.commit("C2")
    ws.commit("C3")
    ws.commit("C4")
    ctx = ws.context(k=3)
    assert len(ctx.commits) == 3


def test_context_includes_roadmap(ws):
    ctx = ws.context()
    assert "Test project roadmap" in ctx.main_roadmap


def test_branch_metadata_records_purpose(ws):
    ws.branch("jwt-branch", "Test JWT auth approach")
    from cortexa.models import BranchMetadata

    meta_text = ws._read(ws._meta_path("jwt-branch"))
    meta = BranchMetadata.from_yaml(meta_text)
    assert meta.purpose == "Test JWT auth approach"
    assert meta.created_from == "main"
    assert meta.status == "active"


def test_merge_marks_branch_as_merged(ws):
    ws.branch("to-merge", "Will be merged")
    ws.commit("Branch work done")
    ws.merge("to-merge", target="main")
    from cortexa.models import BranchMetadata

    meta_text = ws._read(ws._meta_path("to-merge"))
    meta = BranchMetadata.from_yaml(meta_text)
    assert meta.status == "merged"
    assert meta.merged_into == "main"


def test_switch_branch(ws):
    ws.branch("b1", "Branch one")
    ws.switch_branch("main")
    assert ws.current_branch == "main"


def test_ota_step_increments(ws):
    r1 = ws.log_ota("o1", "t1", "a1")
    r2 = ws.log_ota("o2", "t2", "a2")
    r3 = ws.log_ota("o3", "t3", "a3")
    assert r1.step == 1
    assert r2.step == 2
    assert r3.step == 3
