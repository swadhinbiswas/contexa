/**
 * contexa — Git-inspired context management for LLM agents.
 * COMMIT, BRANCH, MERGE, and CONTEXT over versioned memory.
 *
 * Paper: "Git Context Controller: Manage the Context of LLM-based Agents like Git"
 * arXiv:2508.00031 — Junde Wu et al., 2025
 */

export { GCCWorkspace } from "./workspace";
export type {
  OTARecord,
  CommitRecord,
  BranchMetadata,
  ContextResult,
} from "./types";

