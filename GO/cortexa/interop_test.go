package cortexa

// interop_test.go — Cross-language interoperability tests.
//
// These tests verify that the on-disk .GCC/ format produced by the Go
// implementation matches the specification that all 7 language
// implementations (Python, JS/TS, Rust, Go, Zig, Lua, Elixir) agree on.
//
// They also verify that Go can read a workspace hand-crafted in the
// canonical format (simulating what any other language would produce).

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// ------------------------------------------------------------------ //
// Format verification: Go writes → verify raw files                  //
// ------------------------------------------------------------------ //

func TestInterop_OTASeparatorFormat(t *testing.T) {
	ws, _ := setupWorkspace(t, "interop test")
	ws.LogOTA("obs1", "thought1", "act1")
	ws.LogOTA("obs2", "thought2", "act2")

	raw := ws.read(ws.logPath(mainBranch))

	// OTA blocks MUST be separated by "---\n" (3 dashes), NOT "--------\n"
	if strings.Contains(raw, "--------") {
		t.Fatal("log.md must use '---' separator (3 dashes), not 8 dashes")
	}
	if !strings.Contains(raw, "\n---\n") {
		t.Fatal("log.md must contain '---' separator between OTA blocks")
	}

	// Headers must use em-dash: "### Step N — timestamp"
	if strings.Contains(raw, "Step 1-") || strings.Contains(raw, "Step 2-") {
		t.Fatal("OTA headers must use em-dash ' — ', not hyphen '-'")
	}
	if !strings.Contains(raw, " — ") {
		t.Fatal("OTA headers must contain em-dash ' — '")
	}
}

func TestInterop_CommitSeparatorFormat(t *testing.T) {
	ws, _ := setupWorkspace(t, "interop test")
	ws.Commit("First milestone", nil, nil)
	ws.Commit("Second milestone", nil, nil)

	raw := ws.read(ws.commitPath(mainBranch))

	// Commit blocks MUST be separated by "---\n"
	parts := strings.Split(raw, "\n---\n")
	if len(parts) < 2 {
		t.Fatalf("commit.md must have at least 2 blocks separated by '---', got %d", len(parts))
	}

	// Each commit must start with "## Commit `<id>`" (first block may have a header)
	for i, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed == "" {
			continue
		}
		// The first block may contain a "# Commit History" header before the commit
		if i == 0 && strings.HasPrefix(trimmed, "# Commit History") {
			// Check that the commit still appears after the header
			if !strings.Contains(trimmed, "## Commit `") {
				t.Errorf("first block has header but no commit: %q", trimmed[:min(80, len(trimmed))])
			}
			continue
		}
		if !strings.HasPrefix(trimmed, "## Commit `") {
			t.Errorf("commit block must start with '## Commit `<id>`', got: %q",
				trimmed[:min(60, len(trimmed))])
		}
	}
}

func TestInterop_MetadataYAMLFormat(t *testing.T) {
	ws, _ := setupWorkspace(t, "interop test")
	ws.Branch("feature", "Test cross-lang metadata")

	raw, err := os.ReadFile(ws.metaPath("feature"))
	if err != nil {
		t.Fatalf("read metadata.yaml: %v", err)
	}

	content := string(raw)

	// Must contain required YAML fields
	for _, field := range []string{"name:", "purpose:", "created_from:", "created_at:", "status:"} {
		if !strings.Contains(content, field) {
			t.Errorf("metadata.yaml missing required field: %s", field)
		}
	}

	// Verify values
	if !strings.Contains(content, "name: feature") {
		t.Error("metadata.yaml name should be 'feature'")
	}
	if !strings.Contains(content, "status: active") {
		t.Error("new branch metadata should have status: active")
	}
}

func TestInterop_MergeUpdatesMetadataStatus(t *testing.T) {
	ws, _ := setupWorkspace(t, "interop test")
	ws.Branch("exp", "experiment")
	ws.Commit("exp work", nil, nil)
	ws.Merge("exp", nil, mainBranch)

	raw, err := os.ReadFile(ws.metaPath("exp"))
	if err != nil {
		t.Fatalf("read metadata.yaml: %v", err)
	}
	content := string(raw)

	if !strings.Contains(content, "status: merged") {
		t.Error("merged branch metadata should have status: merged")
	}
	if !strings.Contains(content, "merged_into:") {
		t.Error("merged branch metadata should have merged_into field")
	}
	if !strings.Contains(content, "merged_at:") {
		t.Error("merged branch metadata should have merged_at field")
	}
}

func TestInterop_DirectoryLayout(t *testing.T) {
	ws, _ := setupWorkspace(t, "interop test")
	ws.Branch("alt", "alternative")

	// Verify exact directory layout
	checks := []struct {
		path  string
		isDir bool
	}{
		{filepath.Join(ws.root, gccDir, "main.md"), false},
		{filepath.Join(ws.root, gccDir, "branches"), true},
		{filepath.Join(ws.root, gccDir, "branches", "main"), true},
		{filepath.Join(ws.root, gccDir, "branches", "main", "log.md"), false},
		{filepath.Join(ws.root, gccDir, "branches", "main", "commit.md"), false},
		{filepath.Join(ws.root, gccDir, "branches", "main", "metadata.yaml"), false},
		{filepath.Join(ws.root, gccDir, "branches", "alt"), true},
		{filepath.Join(ws.root, gccDir, "branches", "alt", "log.md"), false},
		{filepath.Join(ws.root, gccDir, "branches", "alt", "commit.md"), false},
		{filepath.Join(ws.root, gccDir, "branches", "alt", "metadata.yaml"), false},
	}
	for _, c := range checks {
		info, err := os.Stat(c.path)
		if err != nil {
			t.Errorf("expected %s to exist", c.path)
			continue
		}
		if c.isDir && !info.IsDir() {
			t.Errorf("expected %s to be a directory", c.path)
		}
		if !c.isDir && info.IsDir() {
			t.Errorf("expected %s to be a file", c.path)
		}
	}
}

// ------------------------------------------------------------------ //
// Round-trip: hand-craft workspace → Go reads it                     //
// ------------------------------------------------------------------ //

func TestInterop_ReadHandCraftedWorkspace(t *testing.T) {
	// Simulate what another language (e.g., Python, Zig, Rust) would write
	dir := t.TempDir()
	gccRoot := filepath.Join(dir, ".GCC")
	branchDir := filepath.Join(gccRoot, "branches", "main")
	os.MkdirAll(branchDir, 0o755)

	// main.md — roadmap
	os.WriteFile(filepath.Join(gccRoot, "main.md"),
		[]byte("# Roadmap\nBuild a cross-language test system\n"), 0o644)

	// metadata.yaml — hand-crafted
	os.WriteFile(filepath.Join(branchDir, "metadata.yaml"),
		[]byte("name: main\npurpose: primary development branch\ncreated_from: \"\"\ncreated_at: \"2025-06-01T00:00:00Z\"\nstatus: active\n"), 0o644)

	// log.md — two OTA steps with canonical format
	os.WriteFile(filepath.Join(branchDir, "log.md"),
		[]byte("# OTA Log — main\n\n"+
			"### Step 1 — 2025-06-01T00:00:01Z\n"+
			"**Observation:** Saw the input data\n\n"+
			"**Thought:** Need to process it\n\n"+
			"**Action:** Called the API\n\n"+
			"---\n"+
			"### Step 2 — 2025-06-01T00:00:02Z\n"+
			"**Observation:** Got response\n\n"+
			"**Thought:** Looks correct\n\n"+
			"**Action:** Saved results\n\n"+
			"---\n"),
		0o644)

	// commit.md — two commits with canonical format
	os.WriteFile(filepath.Join(branchDir, "commit.md"),
		[]byte("## Commit `abc12345`\n"+
			"**Timestamp:** 2025-06-01T00:00:10Z\n\n"+
			"**Branch Purpose:** primary development branch\n\n"+
			"**Previous Progress Summary:** Initial state — no prior commits.\n\n"+
			"**This Commit's Contribution:** Completed data ingestion\n\n"+
			"---\n"+
			"## Commit `def67890`\n"+
			"**Timestamp:** 2025-06-01T00:00:20Z\n\n"+
			"**Branch Purpose:** primary development branch\n\n"+
			"**Previous Progress Summary:** Completed data ingestion\n\n"+
			"**This Commit's Contribution:** Added validation layer\n\n"+
			"---\n"),
		0o644)

	// Now read it with Go's workspace
	ws := New(dir)

	// Context should parse everything
	ctx, err := ws.Context(nil, 5)
	if err != nil {
		t.Fatalf("Context on hand-crafted workspace: %v", err)
	}

	if !strings.Contains(ctx.MainRoadmap, "cross-language test system") {
		t.Error("should read roadmap from hand-crafted main.md")
	}

	if len(ctx.Commits) != 2 {
		t.Fatalf("expected 2 commits, got %d", len(ctx.Commits))
	}

	if ctx.Commits[0].CommitID != "abc12345" {
		t.Errorf("first commit ID should be abc12345, got %s", ctx.Commits[0].CommitID)
	}
	if ctx.Commits[1].ThisCommitContribution != "Added validation layer" {
		t.Errorf("second commit contribution wrong: %s", ctx.Commits[1].ThisCommitContribution)
	}

	// K=1 should return only the last commit
	ctx1, err := ws.Context(nil, 1)
	if err != nil {
		t.Fatalf("Context K=1: %v", err)
	}
	if len(ctx1.Commits) != 1 {
		t.Fatalf("K=1 should return 1 commit, got %d", len(ctx1.Commits))
	}
	if ctx1.Commits[0].CommitID != "def67890" {
		t.Error("K=1 should return the most recent commit")
	}
}

func TestInterop_SanitizationRoundTrip(t *testing.T) {
	ws, _ := setupWorkspace(t, "interop sanitization test")

	// Content that contains the separator sequence
	dangerous := "Here is a separator:\n---\nThis should not break parsing"
	ws.LogOTA(dangerous, "safe thought", "safe action")
	ws.Commit(dangerous, nil, nil)

	// Read back via Context
	ctx, err := ws.Context(nil, 1)
	if err != nil {
		t.Fatalf("Context after sanitized write: %v", err)
	}

	// The commit contribution should contain the original text (desanitized)
	if ctx.Commits[0].ThisCommitContribution != dangerous {
		t.Errorf("round-trip sanitization failed.\nExpected: %q\nGot:      %q",
			dangerous, ctx.Commits[0].ThisCommitContribution)
	}

	// Raw file should contain the escaped form, not the raw separator
	rawLog := ws.read(ws.logPath(mainBranch))
	if strings.Contains(rawLog, "\n---\nThis should not break") {
		t.Error("raw log.md should contain escaped separator, not raw")
	}
	if !strings.Contains(rawLog, "\\---") {
		t.Error("raw log.md should contain escaped '\\---'")
	}
}

func TestInterop_BranchLogHasHeader(t *testing.T) {
	ws, _ := setupWorkspace(t, "interop test")
	ws.Branch("feat", "new feature")

	raw := ws.read(ws.logPath("feat"))
	// All languages write "# OTA Log — <branch>\n" as the first line
	if !strings.HasPrefix(raw, "# OTA Log") {
		t.Errorf("log.md should start with '# OTA Log', got: %q",
			raw[:min(40, len(raw))])
	}
	if !strings.Contains(raw, "feat") {
		t.Error("log.md header should contain branch name")
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
