// Package cortexa implements contexa — Git-inspired context management
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
		r.Step, r.Timestamp, r.Observation, r.Thought, r.Action,
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
		c.CommitID, c.Timestamp, c.BranchPurpose,
		c.PreviousProgressSummary, c.ThisCommitContribution,
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
