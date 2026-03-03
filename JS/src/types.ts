/**
 * GCC (Git-Context-Controller) type definitions.
 * Paper: arXiv:2508.00031v2 — Junde Wu et al., 2025
 */

/** A single Observation–Thought–Action cycle logged to log.md. */
export interface OTARecord {
  step: number;
  timestamp: string;
  observation: string;
  thought: string;
  action: string;
}

/**
 * A commit checkpoint (paper §3.2).
 * Fields: Branch Purpose, Previous Progress Summary, This Commit's Contribution.
 */
export interface CommitRecord {
  commitId: string;
  branchName: string;
  branchPurpose: string;
  previousProgressSummary: string;
  thisCommitContribution: string;
  timestamp: string;
}

/**
 * Branch metadata stored in metadata.yaml (paper §3.1).
 * Records architectural intent and motivation.
 */
export interface BranchMetadata {
  name: string;
  purpose: string;
  createdFrom: string;
  createdAt: string;
  status: "active" | "merged" | "abandoned";
  mergedInto?: string;
  mergedAt?: string;
}

/**
 * Result of the CONTEXT command (paper §3.5).
 * K controls the commit retrieval window (paper experiments: K=1).
 */
export interface ContextResult {
  branchName: string;
  k: number;
  commits: CommitRecord[];
  otaRecords: OTARecord[];
  mainRoadmap: string;
  metadata?: BranchMetadata;
  summary(): string;
}

