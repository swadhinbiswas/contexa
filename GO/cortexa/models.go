// Package cortexa implements cortexa — Git-inspired context management
// for LLM agents. COMMIT, BRANCH, MERGE, and CONTEXT over versioned memory.
//
// Paper: "Git Context Controller: Manage the Context of LLM-based Agents like Git"
// arXiv:2508.00031 — Junde Wu et al., 2025
//
// Author: Swadhin Biswas (@swadhinbiswas)

package cortexa

import (
	"fmt"
	"strings"
)

// Sanitize escapes separator sequences in user-provided content.
func Sanitize(text string) string {
	return strings.Replace(text, "\n---\n", "\n\\---\n", -1)
}

// Desanitize reverses the escaping applied by Sanitize.
func Desanitize(text string) string {
	return strings.Replace(text, "\n\\---\n", "\n---\n", -1)
}

// SplitBlocks splits markdown text on the "---\n" separator while
// respecting escaped separators ("\---\n" produced by Sanitize).
// After splitting, escaped separators are left in place; callers
// should use Desanitize on individual field values.
func SplitBlocks(text string) []string {
	raw := strings.Split(text, "---\n")
	var blocks []string
	for i := 0; i < len(raw); i++ {
		block := raw[i]
		// If block ends with '\', the "---\n" was actually an escaped
		// separator — rejoin with the next fragment.
		for strings.HasSuffix(block, "\\") && i+1 < len(raw) {
			i++
			block = block + "---\n" + raw[i]
		}
		blocks = append(blocks, block)
	}
	return blocks
}

// OTARecord represents a single Observation–Thought–Action cycle logged to log.md.
type OTARecord struct {
	Step        int    `yaml:"step"`
	Timestamp   string `yaml:"timestamp"`
	Observation string `yaml:"observation"`
	Thought     string `yaml:"thought"`
	Action      string `yaml:"action"`
}

// ToMarkdown renders the OTA record in the markdown format used by GCC.
func (r OTARecord) ToMarkdown() string {
	return fmt.Sprintf(
		"### Step %d — %s\n**Observation:** %s\n\n**Thought:** %s\n\n**Action:** %s\n\n---\n",
		r.Step, r.Timestamp, Sanitize(r.Observation), Sanitize(r.Thought), Sanitize(r.Action),
	)
}

// CommitRecord represents a milestone checkpoint (paper §3.2).
// Fields: Branch Purpose, Previous Progress Summary, This Commit's Contribution.
type CommitRecord struct {
	CommitID                string `yaml:"commit_id"`
	BranchName              string `yaml:"branch_name"`
	BranchPurpose           string `yaml:"branch_purpose"`
	PreviousProgressSummary string `yaml:"previous_progress_summary"`
	ThisCommitContribution  string `yaml:"this_commit_contribution"`
	Timestamp               string `yaml:"timestamp"`
}

// ToMarkdown renders the commit record in the markdown format used by GCC.
func (c CommitRecord) ToMarkdown() string {
	return fmt.Sprintf(
		"## Commit `%s`\n**Timestamp:** %s\n\n**Branch Purpose:** %s\n\n"+
			"**Previous Progress Summary:** %s\n\n"+
			"**This Commit's Contribution:** %s\n\n---\n",
		c.CommitID, c.Timestamp, Sanitize(c.BranchPurpose),
		Sanitize(c.PreviousProgressSummary), Sanitize(c.ThisCommitContribution),
	)
}

// BranchMetadata is stored in metadata.yaml per branch (paper §3.1).
// Records architectural intent and motivation.
type BranchMetadata struct {
	Name        string  `yaml:"name"`
	Purpose     string  `yaml:"purpose"`
	CreatedFrom string  `yaml:"created_from"`
	CreatedAt   string  `yaml:"created_at"`
	Status      string  `yaml:"status"`
	MergedInto  *string `yaml:"merged_into,omitempty"`
	MergedAt    *string `yaml:"merged_at,omitempty"`
}

// ContextResult is the result of the CONTEXT command (paper §3.5).
// K controls the commit retrieval window (paper experiments: K=1).
type ContextResult struct {
	BranchName  string
	K           int
	Commits     []CommitRecord
	OTARecords  []OTARecord
	MainRoadmap string
	Metadata    *BranchMetadata
}

// Summary renders a formatted markdown summary of the context.
func (cr ContextResult) Summary() string {
	var b strings.Builder
	fmt.Fprintf(&b, "# CONTEXT — branch `%s` (K=%d)\n\n", cr.BranchName, cr.K)
	b.WriteString("## Global Roadmap\n")
	b.WriteString(cr.MainRoadmap)
	b.WriteString("\n\n")
	fmt.Fprintf(&b, "## Last %d Commit(s)\n", cr.K)
	for _, c := range cr.Commits {
		b.WriteString(c.ToMarkdown())
	}
	if len(cr.OTARecords) > 0 {
		recent := cr.OTARecords
		if len(recent) > 5 {
			recent = recent[len(recent)-5:]
		}
		fmt.Fprintf(&b, "\n## Recent OTA Steps (showing last %d of %d)\n",
			len(recent), len(cr.OTARecords))
		for _, r := range recent {
			b.WriteString(r.ToMarkdown())
		}
	}
	return b.String()
}
