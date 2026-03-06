package cortexa

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// helper: creates a temp dir, initialises a Workspace, returns ws + cleanup func.
func setupWorkspace(t *testing.T, roadmap string) (*Workspace, func()) {
	t.Helper()
	dir := t.TempDir()
	ws := New(dir)
	if err := ws.Init(roadmap); err != nil {
		t.Fatalf("Init: %v", err)
	}
	return ws, func() {} // t.TempDir handles cleanup
}

// ------------------------------------------------------------------ //
// Init                                                                //
// ------------------------------------------------------------------ //

func TestInit_CreatesGCCStructure(t *testing.T) {
	ws, _ := setupWorkspace(t, "Build an AI agent")

	// .GCC/main.md exists
	data, err := os.ReadFile(ws.mainMd())
	if err != nil {
		t.Fatalf("main.md missing: %v", err)
	}
	if !strings.Contains(string(data), "Build an AI agent") {
		t.Errorf("main.md missing roadmap content")
	}

	// branches/main/ directory created
	info, err := os.Stat(ws.branchDir(mainBranch))
	if err != nil || !info.IsDir() {
		t.Errorf("expected branches/main directory")
	}

	// log.md, commit.md, metadata.yaml present
	for _, f := range []string{ws.logPath(mainBranch), ws.commitPath(mainBranch), ws.metaPath(mainBranch)} {
		if _, err := os.Stat(f); err != nil {
			t.Errorf("expected %s to exist", filepath.Base(f))
		}
	}
}

func TestInit_DoubleInit_Fails(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")
	if err := ws.Init("again"); err == nil {
		t.Errorf("expected error on double init")
	}
}

// ------------------------------------------------------------------ //
// LogOTA                                                              //
// ------------------------------------------------------------------ //

func TestLogOTA_IncrementsStep(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")

	r1, err := ws.LogOTA("obs1", "thought1", "act1")
	if err != nil {
		t.Fatalf("LogOTA: %v", err)
	}
	if r1.Step != 1 {
		t.Errorf("expected step 1, got %d", r1.Step)
	}

	r2, err := ws.LogOTA("obs2", "thought2", "act2")
	if err != nil {
		t.Fatalf("LogOTA: %v", err)
	}
	if r2.Step != 2 {
		t.Errorf("expected step 2, got %d", r2.Step)
	}
}

func TestLogOTA_AppendsToLogMd(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")
	ws.LogOTA("observation text", "thinking hard", "do something")

	data := ws.read(ws.logPath(mainBranch))
	if !strings.Contains(data, "observation text") {
		t.Errorf("log.md missing observation")
	}
	if !strings.Contains(data, "thinking hard") {
		t.Errorf("log.md missing thought")
	}
}

// ------------------------------------------------------------------ //
// Commit                                                              //
// ------------------------------------------------------------------ //

func TestCommit_WritesToCommitMd(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")

	c, err := ws.Commit("Finished setup phase", nil, nil)
	if err != nil {
		t.Fatalf("Commit: %v", err)
	}
	if c.CommitID == "" {
		t.Error("expected non-empty commit ID")
	}
	if c.BranchName != mainBranch {
		t.Errorf("expected branch %s, got %s", mainBranch, c.BranchName)
	}

	data := ws.read(ws.commitPath(mainBranch))
	if !strings.Contains(data, "Finished setup phase") {
		t.Error("commit.md missing contribution text")
	}
}

func TestCommit_AutoPreviousSummary(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")

	// First commit — no prior, should default
	c1, _ := ws.Commit("First milestone", nil, nil)
	if c1.PreviousProgressSummary != "Initial state — no prior commits." {
		t.Errorf("unexpected first prev summary: %q", c1.PreviousProgressSummary)
	}

	// Second commit — auto-uses first's contribution
	c2, _ := ws.Commit("Second milestone", nil, nil)
	if c2.PreviousProgressSummary != "First milestone" {
		t.Errorf("expected auto previous summary 'First milestone', got %q", c2.PreviousProgressSummary)
	}
}

func TestCommit_UpdateRoadmap(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")

	update := "We pivoted to approach B"
	ws.Commit("Pivot done", nil, &update)

	data := ws.read(ws.mainMd())
	if !strings.Contains(data, "We pivoted to approach B") {
		t.Error("main.md should contain roadmap update")
	}
}

// ------------------------------------------------------------------ //
// Branch                                                              //
// ------------------------------------------------------------------ //

func TestBranch_CreatesIsolatedWorkspace(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")

	if err := ws.Branch("experiment", "Try alternative approach"); err != nil {
		t.Fatalf("Branch: %v", err)
	}
	if ws.CurrentBranch() != "experiment" {
		t.Errorf("expected current branch 'experiment', got %q", ws.CurrentBranch())
	}

	// Branch should have its own log.md
	info, err := os.Stat(ws.logPath("experiment"))
	if err != nil {
		t.Fatalf("experiment/log.md should exist: %v", err)
	}
	if info.Size() == 0 {
		t.Error("log.md should not be empty (should have header)")
	}

	// metadata.yaml should record purpose
	meta, err := ws.parseMeta("experiment")
	if err != nil {
		t.Fatalf("parseMeta: %v", err)
	}
	if meta == nil || meta.Purpose != "Try alternative approach" {
		t.Error("metadata should record purpose")
	}
}

func TestBranch_DuplicateName_Fails(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")
	ws.Branch("exp", "first")
	if err := ws.Branch("exp", "second"); err == nil {
		t.Error("expected error creating duplicate branch")
	}
}

// ------------------------------------------------------------------ //
// Merge                                                               //
// ------------------------------------------------------------------ //

func TestMerge_IntegratesBranchIntoTarget(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")

	// Work on main, then branch
	ws.LogOTA("main obs", "main thought", "main action")
	ws.Commit("Main setup done", nil, nil)

	ws.Branch("feature", "Add new capability")
	ws.LogOTA("feature obs", "feature thought", "feature action")
	ws.Commit("Feature implemented", nil, nil)

	// Merge back to main
	mergeCommit, err := ws.Merge("feature", nil, mainBranch)
	if err != nil {
		t.Fatalf("Merge: %v", err)
	}

	// Check merge commit
	if !strings.Contains(mergeCommit.ThisCommitContribution, "feature") {
		t.Error("merge commit should reference the merged branch")
	}
	if ws.CurrentBranch() != mainBranch {
		t.Errorf("after merge, should be on %s, got %s", mainBranch, ws.CurrentBranch())
	}

	// OTA from feature should appear in main's log
	data := ws.read(ws.logPath(mainBranch))
	if !strings.Contains(data, "feature obs") {
		t.Error("main log should contain merged OTA from feature branch")
	}

	// Feature branch metadata should say "merged"
	meta, _ := ws.parseMeta("feature")
	if meta == nil || meta.Status != "merged" {
		t.Error("feature branch metadata should be status=merged")
	}
}

func TestMerge_NonexistentBranch_Fails(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")
	_, err := ws.Merge("nope", nil, mainBranch)
	if err == nil {
		t.Error("expected error merging nonexistent branch")
	}
}

func TestMerge_NonexistentTarget_Fails(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")
	ws.Branch("feature", "test")
	_, err := ws.Merge("feature", nil, "nonexistent")
	if err == nil {
		t.Error("expected error merging into nonexistent target")
	}
}

// ------------------------------------------------------------------ //
// Context                                                             //
// ------------------------------------------------------------------ //

func TestContext_ReturnsRoadmapAndCommits(t *testing.T) {
	ws, _ := setupWorkspace(t, "Build a multi-agent system")
	ws.LogOTA("o", "t", "a")
	ws.Commit("Phase 1 complete", nil, nil)
	ws.Commit("Phase 2 complete", nil, nil)

	// K=1 should return only last commit
	ctx, err := ws.Context(nil, 1)
	if err != nil {
		t.Fatalf("Context: %v", err)
	}
	if !strings.Contains(ctx.MainRoadmap, "multi-agent system") {
		t.Error("context should include roadmap")
	}
	if len(ctx.Commits) != 1 {
		t.Errorf("K=1 should return 1 commit, got %d", len(ctx.Commits))
	}
	if ctx.Commits[0].ThisCommitContribution != "Phase 2 complete" {
		t.Error("K=1 should return the most recent commit")
	}

	// K=5 (more than available) should return all
	ctx2, _ := ws.Context(nil, 5)
	if len(ctx2.Commits) != 2 {
		t.Errorf("K=5 should return all 2 commits, got %d", len(ctx2.Commits))
	}
}

func TestContext_NonexistentBranch_Fails(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")
	nope := "nonexistent"
	_, err := ws.Context(&nope, 1)
	if err == nil {
		t.Error("expected error for nonexistent branch")
	}
}

func TestContext_Summary(t *testing.T) {
	ws, _ := setupWorkspace(t, "Project X")
	ws.LogOTA("obs", "thought", "action")
	ws.Commit("Done step 1", nil, nil)

	ctx, _ := ws.Context(nil, 1)
	summary := ctx.Summary()
	if !strings.Contains(summary, "CONTEXT") {
		t.Error("summary should contain CONTEXT header")
	}
	if !strings.Contains(summary, mainBranch) {
		t.Error("summary should mention branch name")
	}
}

// ------------------------------------------------------------------ //
// Helpers                                                             //
// ------------------------------------------------------------------ //

func TestSwitchBranch(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")
	ws.Branch("alt", "alternative path")
	ws.SwitchBranch(mainBranch)
	if ws.CurrentBranch() != mainBranch {
		t.Errorf("expected main, got %s", ws.CurrentBranch())
	}
}

func TestSwitchBranch_Nonexistent_Fails(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")
	if err := ws.SwitchBranch("nope"); err == nil {
		t.Error("expected error switching to nonexistent branch")
	}
}

func TestListBranches(t *testing.T) {
	ws, _ := setupWorkspace(t, "test")
	ws.Branch("alpha", "a")
	ws.Branch("beta", "b")

	branches, err := ws.ListBranches()
	if err != nil {
		t.Fatalf("ListBranches: %v", err)
	}
	// Should have main, alpha, beta
	if len(branches) != 3 {
		t.Errorf("expected 3 branches, got %d: %v", len(branches), branches)
	}
}

// ------------------------------------------------------------------ //
// Models                                                              //
// ------------------------------------------------------------------ //

func TestOTARecord_ToMarkdown(t *testing.T) {
	r := OTARecord{
		Step:        1,
		Timestamp:   "2025-01-01T00:00:00Z",
		Observation: "saw an error",
		Thought:     "need to fix it",
		Action:      "patched the code",
	}
	md := r.ToMarkdown()
	if !strings.Contains(md, "Step 1") {
		t.Error("markdown should contain step number")
	}
	if !strings.Contains(md, "saw an error") {
		t.Error("markdown should contain observation")
	}
}

func TestCommitRecord_ToMarkdown(t *testing.T) {
	c := CommitRecord{
		CommitID:                "abc123",
		BranchName:              "main",
		BranchPurpose:           "primary",
		PreviousProgressSummary: "none",
		ThisCommitContribution:  "added feature X",
		Timestamp:               "2025-01-01T00:00:00Z",
	}
	md := c.ToMarkdown()
	if !strings.Contains(md, "abc123") {
		t.Error("markdown should contain commit ID")
	}
	if !strings.Contains(md, "added feature X") {
		t.Error("markdown should contain contribution")
	}
}
