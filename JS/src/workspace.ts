/**
 * GCC Workspace — core implementation. by @swadhinbiswas
 *
 * Paper: "Git Context Controller: Manage the Context of LLM-based Agents like Git"
 * arXiv:2508.00031v2 — Junde Wu et al., 2025
 *
 * Implements the four GCC commands:
 *   COMMIT  (§3.2) — milestone checkpointing to commit.md
 *   BRANCH  (§3.3) — isolated reasoning workspace
 *   MERGE   (§3.4) — synthesise divergent paths
 *   CONTEXT (§3.5) — hierarchical memory retrieval (K-commit window)
 *
 * File system layout:
 *   .GCC/
 *   ├── main.md                 # Global roadmap / planning artifact
 *   └── branches/
 *       ├── main/
 *       │   ├── log.md          # Continuous OTA trace
 *       │   ├── commit.md       # Milestone-level summaries
 *       │   └── metadata.yaml   # Branch intent & status
 *       └── <branch>/
 *           └── ...
 */

import * as fs from "fs";
import * as path from "path";
import * as yaml from "js-yaml";
import { randomBytes } from "crypto";
import type {
  BranchMetadata,
  CommitRecord,
  ContextResult,
  OTARecord,
} from "./types";

const MAIN_BRANCH = "main";
const GCC_DIR = ".GCC";

const now = (): string => new Date().toISOString();
const shortId = (): string => randomBytes(4).toString("hex");

/** Escape separator sequences in user-provided content to prevent parser breakage. */
function sanitize(text: string): string {
  return text.replace(/\n---\n/g, "\n\\---\n");
}

/** Reverse the escaping applied by `sanitize`. */
function desanitize(text: string): string {
  return text.replace(/\n\\---\n/g, "\n---\n");
}

/**
 * Split markdown text on `---\n` while respecting escaped separators
 * (`\---\n` produced by `sanitize`). After splitting, escaped separators
 * are left in place; callers should apply `desanitize` on field values.
 */
function splitBlocks(text: string): string[] {
  const raw = text.split("---\n");
  const blocks: string[] = [];
  let i = 0;
  while (i < raw.length) {
    let block = raw[i];
    while (block.endsWith("\\") && i + 1 < raw.length) {
      i++;
      block = block + "---\n" + raw[i];
    }
    blocks.push(block);
    i++;
  }
  return blocks;
}

function otaToMarkdown(r: OTARecord): string {
  return (
    `### Step ${r.step} — ${r.timestamp}\n` +
    `**Observation:** ${sanitize(r.observation)}\n\n` +
    `**Thought:** ${sanitize(r.thought)}\n\n` +
    `**Action:** ${sanitize(r.action)}\n\n` +
    `---\n`
  );
}

function commitToMarkdown(c: CommitRecord): string {
  return (
    `## Commit \`${c.commitId}\`\n` +
    `**Timestamp:** ${c.timestamp}\n\n` +
    `**Branch Purpose:** ${sanitize(c.branchPurpose)}\n\n` +
    `**Previous Progress Summary:** ${sanitize(c.previousProgressSummary)}\n\n` +
    `**This Commit's Contribution:** ${sanitize(c.thisCommitContribution)}\n\n` +
    `---\n`
  );
}

function makeContextResult(
  branchName: string,
  k: number,
  commits: CommitRecord[],
  otaRecords: OTARecord[],
  mainRoadmap: string,
  metadata?: BranchMetadata
): ContextResult {
  return {
    branchName,
    k,
    commits,
    otaRecords,
    mainRoadmap,
    metadata,
    summary(): string {
      const lines: string[] = [
        `# CONTEXT — branch \`${branchName}\` (K=${k})\n`,
        `## Global Roadmap\n${mainRoadmap}\n`,
        `## Last ${k} Commit(s)\n`,
      ];
      for (const c of commits) lines.push(commitToMarkdown(c));
      if (otaRecords.length > 0) {
        const recent = otaRecords.slice(-5);
        lines.push(
          `\n## Recent OTA Steps (showing last ${recent.length} of ${otaRecords.length})\n`
        );
        for (const r of recent) lines.push(otaToMarkdown(r));
      }
      return lines.join("\n");
    },
  };
}

/** Raise if value is empty or whitespace-only. */
function validateNotEmpty(value: string, field: string): void {
  if (!value || !value.trim()) {
    throw new Error(`${field} must not be empty.`);
  }
}

/** Raise if name is not a valid branch identifier. */
function validateBranchName(name: string): void {
  validateNotEmpty(name, "Branch name");
  if (name.includes("/") || name.includes("\\")) {
    throw new Error(`Branch name must not contain path separators: '${name}'`);
  }
  if (name === "." || name === "..") {
    throw new Error(`Branch name must not be '.' or '..': '${name}'`);
  }
}

/** Manages the `.GCC/` directory structure for one agent project. */
export class GCCWorkspace {
  private readonly root: string;
  private readonly gccDir: string;
  private _currentBranch: string = MAIN_BRANCH;

  constructor(projectRoot: string) {
    this.root = projectRoot;
    this.gccDir = path.join(projectRoot, GCC_DIR);
  }

  // ------------------------------------------------------------------ //
  // File locking                                                        //
  // ------------------------------------------------------------------ //

  /**
   * Acquire an exclusive lock on `.GCC/.lock` and run `fn`.
   *
   * Uses `O_EXLOCK` where available (macOS) and falls back to
   * `fs.flockSync` via a tight open-with-exclusive flag retry loop
   * on Linux/Windows.  The lock is always released when `fn` returns
   * (or throws).
   */
  private withLock<T>(fn: () => T): T {
    const lockPath = path.join(this.gccDir, ".lock");
    fs.mkdirSync(path.dirname(lockPath), { recursive: true });

    // Open (or create) the lock file.  We acquire an exclusive,
    // blocking lock by opening with O_RDWR|O_CREAT then using
    // Node's undocumented-but-stable flock binding through the fd.
    //
    // Since Node does not expose flock() directly, we use the
    // simplest portable approach: open with 'wx+' in a retry loop.
    // On success we hold the exclusive create lock; on EEXIST we
    // wait briefly and retry.  This is a cooperative lock: all
    // contexa JS instances follow the same protocol.
    const maxWait = 10_000; // 10 seconds
    const interval = 50;    // ms between retries
    let waited = 0;
    let fd: number;

    while (true) {
      try {
        // O_CREAT | O_EXCL | O_RDWR — atomic create-or-fail
        fd = fs.openSync(lockPath, fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_RDWR, 0o644);
        break;
      } catch (err: any) {
        if (err.code !== "EEXIST") throw err;
        if (waited >= maxWait) {
          // Stale lock — force remove and retry once
          try { fs.unlinkSync(lockPath); } catch { /* ignore */ }
          fd = fs.openSync(lockPath, fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_RDWR, 0o644);
          break;
        }
        // Busy-wait (synchronous context — no async available)
        const start = Date.now();
        while (Date.now() - start < interval) { /* spin */ }
        waited += interval;
      }
    }

    try {
      return fn();
    } finally {
      try { fs.closeSync(fd!); } catch { /* ignore */ }
      try { fs.unlinkSync(lockPath); } catch { /* ignore */ }
    }
  }

  // ------------------------------------------------------------------ //
  // Paths                                                                //
  // ------------------------------------------------------------------ //

  private branchDir(branch: string): string {
    return path.join(this.gccDir, "branches", branch);
  }
  private logPath(branch: string): string {
    return path.join(this.branchDir(branch), "log.md");
  }
  private commitPath(branch: string): string {
    return path.join(this.branchDir(branch), "commit.md");
  }
  private metaPath(branch: string): string {
    return path.join(this.branchDir(branch), "metadata.yaml");
  }
  private mainMd(): string {
    return path.join(this.gccDir, "main.md");
  }

  // ------------------------------------------------------------------ //
  // I/O helpers                                                          //
  // ------------------------------------------------------------------ //

  private read(filePath: string): string {
    try {
      return fs.readFileSync(filePath, "utf8");
    } catch {
      return "";
    }
  }

  private write(filePath: string, content: string): void {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, content, "utf8");
  }

  private append(filePath: string, content: string): void {
    fs.appendFileSync(filePath, content, "utf8");
  }

  private parseCommits(branch: string): CommitRecord[] {
    const text = this.read(this.commitPath(branch));
    const records: CommitRecord[] = [];
    for (const block of splitBlocks(text)) {
      const trimmed = block.trim();
      if (!trimmed) continue;
      let commitId = "",
        ts = "";
      const fields: Record<string, string[]> = {};
      let current: string | null = null;

      for (const line of trimmed.split("\n")) {
        if (line.startsWith("## Commit `")) {
          commitId = line.replace(/^## Commit `|`\s*$/g, "");
          current = null;
        } else if (line.startsWith("**Timestamp:**")) {
          ts = line.replace("**Timestamp:**", "").trim();
          current = null;
        } else if (line.startsWith("**Branch Purpose:**")) {
          fields.branchPurpose = [line.replace("**Branch Purpose:**", "").trim()];
          current = "branchPurpose";
        } else if (line.startsWith("**Previous Progress Summary:**")) {
          fields.prevSummary = [line.replace("**Previous Progress Summary:**", "").trim()];
          current = "prevSummary";
        } else if (line.startsWith("**This Commit's Contribution:**")) {
          fields.contribution = [line.replace("**This Commit's Contribution:**", "").trim()];
          current = "contribution";
        } else if (current && line.trim()) {
          fields[current].push(line.trim());
        }
      }
      if (commitId) {
        const get = (key: string) =>
          desanitize((fields[key] || [""]).join("\n").trim());
        records.push({
          commitId,
          branchName: branch,
          branchPurpose: get("branchPurpose"),
          previousProgressSummary: get("prevSummary"),
          thisCommitContribution: get("contribution"),
          timestamp: ts,
        });
      }
    }
    return records;
  }

  private parseOTA(branch: string): OTARecord[] {
    const text = this.read(this.logPath(branch));
    const records: OTARecord[] = [];
    for (const block of splitBlocks(text)) {
      const trimmed = block.trim();
      if (!trimmed) continue;
      let step = 0,
        ts = "";
      const fields: Record<string, string[]> = {};
      let current: string | null = null;

      for (const line of trimmed.split("\n")) {
        if (line.startsWith("### Step ")) {
          const parts = line.split(" — ");
          step = parseInt(parts[0]?.replace("### Step ", "") ?? "0", 10) || 0;
          ts = parts[1]?.trim() ?? "";
          current = null;
        } else if (line.startsWith("**Observation:**")) {
          fields.obs = [line.replace("**Observation:**", "").trim()];
          current = "obs";
        } else if (line.startsWith("**Thought:**")) {
          fields.thought = [line.replace("**Thought:**", "").trim()];
          current = "thought";
        } else if (line.startsWith("**Action:**")) {
          fields.action = [line.replace("**Action:**", "").trim()];
          current = "action";
        } else if (current && line.trim()) {
          fields[current].push(line.trim());
        }
      }
      const get = (key: string) =>
        desanitize((fields[key] || [""]).join("\n").trim());
      const obs = get("obs");
      const thought = get("thought");
      if (obs || thought) {
        records.push({ step, timestamp: ts, observation: obs, thought, action: get("action") });
      }
    }
    return records;
  }

  private parseMeta(branch: string): BranchMetadata | undefined {
    const text = this.read(this.metaPath(branch));
    if (!text) return undefined;
    try {
      const d = yaml.load(text) as Record<string, unknown>;
      return {
        name: String(d["name"] ?? ""),
        purpose: String(d["purpose"] ?? ""),
        createdFrom: String(d["created_from"] ?? ""),
        createdAt: String(d["created_at"] ?? ""),
        status: (d["status"] as BranchMetadata["status"]) ?? "active",
        mergedInto: d["merged_into"] ? String(d["merged_into"]) : undefined,
        mergedAt: d["merged_at"] ? String(d["merged_at"]) : undefined,
      };
    } catch {
      return undefined;
    }
  }

  private dumpMeta(meta: BranchMetadata): string {
    return yaml.dump({
      name: meta.name,
      purpose: meta.purpose,
      created_from: meta.createdFrom,
      created_at: meta.createdAt,
      status: meta.status,
      merged_into: meta.mergedInto ?? null,
      merged_at: meta.mergedAt ?? null,
    });
  }

  // ------------------------------------------------------------------ //
  // Initialisation                                                       //
  // ------------------------------------------------------------------ //

  /** Initialise a new GCC workspace. */
  init(projectRoadmap = ""): void {
    if (fs.existsSync(this.gccDir)) {
      throw new Error(`GCC workspace already exists at ${this.gccDir}`);
    }
    fs.mkdirSync(this.branchDir(MAIN_BRANCH), { recursive: true });

    this.withLock(() => {
      this.write(
        this.mainMd(),
        `# Project Roadmap\n\n**Initialized:** ${now()}\n\n${projectRoadmap}\n`
      );
      this.write(this.logPath(MAIN_BRANCH), `# OTA Log — branch \`${MAIN_BRANCH}\`\n\n`);
      this.write(this.commitPath(MAIN_BRANCH), `# Commit History — branch \`${MAIN_BRANCH}\`\n\n`);

      const meta: BranchMetadata = {
        name: MAIN_BRANCH,
        purpose: "Primary reasoning trajectory",
        createdFrom: "",
        createdAt: now(),
        status: "active",
      };
      this.write(this.metaPath(MAIN_BRANCH), this.dumpMeta(meta));
    });
    this._currentBranch = MAIN_BRANCH;
  }

  /** Load an existing GCC workspace. */
  load(): void {
    if (!fs.existsSync(this.gccDir)) {
      throw new Error(`No GCC workspace found at ${this.gccDir}`);
    }
    this._currentBranch = MAIN_BRANCH;
  }

  // ------------------------------------------------------------------ //
  // GCC Commands                                                         //
  // ------------------------------------------------------------------ //

  /**
   * Append an OTA step to current branch's log.md.
   * The paper logs continuous Observation–Thought–Action cycles.
   */
  logOTA(observation: string, thought: string, action: string): OTARecord {
    if (!observation?.trim() && !thought?.trim() && !action?.trim()) {
      throw new Error("At least one of observation, thought, or action must be non-empty.");
    }
    return this.withLock(() => {
      const existing = this.parseOTA(this._currentBranch);
      const record: OTARecord = {
        step: existing.length + 1,
        timestamp: now(),
        observation,
        thought,
        action,
      };
      this.append(this.logPath(this._currentBranch), otaToMarkdown(record));
      return record;
    });
  }

  /**
   * COMMIT command (paper §3.2).
   * Checkpoints milestone with: Branch Purpose, Previous Progress Summary,
   * This Commit's Contribution.
   */
  commit(
    contribution: string,
    previousSummary?: string,
    updateRoadmap?: string
  ): CommitRecord {
    validateNotEmpty(contribution, "Contribution");
    return this.withLock(() => {
      const meta = this.parseMeta(this._currentBranch);
      const branchPurpose = meta?.purpose ?? "";

      let prevSummary = previousSummary;
      if (!prevSummary) {
        const commits = this.parseCommits(this._currentBranch);
        prevSummary =
          commits.at(-1)?.thisCommitContribution ??
          "Initial state — no prior commits.";
      }

      const record: CommitRecord = {
        commitId: shortId(),
        branchName: this._currentBranch,
        branchPurpose,
        previousProgressSummary: prevSummary,
        thisCommitContribution: contribution,
        timestamp: now(),
      };

      this.append(this.commitPath(this._currentBranch), commitToMarkdown(record));

      if (updateRoadmap) {
        this.append(this.mainMd(), `\n## Update (${record.timestamp})\n${updateRoadmap}\n`);
      }

      return record;
    });
  }

  /**
   * BRANCH command (paper §3.3).
   * Creates isolated workspace: B_t^(name) = BRANCH(M_{t-1}).
   */
  branch(name: string, purpose: string): void {
    validateBranchName(name);
    validateNotEmpty(purpose, "Branch purpose");
    if (fs.existsSync(this.branchDir(name))) {
      throw new Error(`Branch '${name}' already exists.`);
    }
    fs.mkdirSync(this.branchDir(name), { recursive: true });

    this.withLock(() => {
      this.write(this.logPath(name), `# OTA Log — branch \`${name}\`\n\n`);
      this.write(this.commitPath(name), `# Commit History — branch \`${name}\`\n\n`);

      const meta: BranchMetadata = {
        name,
        purpose,
        createdFrom: this._currentBranch,
        createdAt: now(),
        status: "active",
      };
      this.write(this.metaPath(name), this.dumpMeta(meta));
    });
    this._currentBranch = name;
  }

  /**
   * MERGE command (paper §3.4).
   * Integrates branch into target, merging summaries and OTA traces.
   */
  merge(
    branchName: string,
    summary?: string,
    target: string = MAIN_BRANCH
  ): CommitRecord {
    validateBranchName(branchName);
    validateBranchName(target);
    if (!fs.existsSync(this.branchDir(branchName))) {
      throw new Error(`Branch '${branchName}' not found.`);
    }
    if (!fs.existsSync(this.branchDir(target))) {
      throw new Error(`Target branch '${target}' not found.`);
    }

    let mergeSummary: string;
    let metaCopy: BranchMetadata | undefined;

    this.withLock(() => {
      const branchCommits = this.parseCommits(branchName);
      const branchOTA = this.parseOTA(branchName);
      const meta = this.parseMeta(branchName);
      metaCopy = meta;

      mergeSummary =
        summary ??
        `Merged branch \`${branchName}\` (${branchCommits.length} commits). Contributions: ${branchCommits
          .map((c) => c.thisCommitContribution)
          .join(" | ")}`;

      if (branchOTA.length > 0) {
        this.append(
          this.logPath(target),
          `\n## Merged from \`${branchName}\` (${now()})\n\n`
        );
        for (const rec of branchOTA) {
          this.append(this.logPath(target), otaToMarkdown(rec));
        }
      }

      this._currentBranch = target;
    });

    // commit() acquires the lock internally
    const mergeCommit = this.commit(
      mergeSummary!,
      `Merging branch \`${branchName}\` with purpose: ${metaCopy?.purpose ?? ""}`,
      mergeSummary!
    );

    this.withLock(() => {
      if (metaCopy) {
        const updated: BranchMetadata = {
          ...metaCopy,
          status: "merged",
          mergedInto: target,
          mergedAt: now(),
        };
        this.write(this.metaPath(branchName), this.dumpMeta(updated));
      }
    });

    return mergeCommit;
  }

  /**
   * CONTEXT command (paper §3.5).
   * Retrieves history at K-commit resolution. Paper default: K=1.
   */
  context(branch?: string, k = 1): ContextResult {
    if (k < 1) {
      throw new Error(`k must be >= 1, got ${k}`);
    }
    const target = branch ?? this._currentBranch;
    if (!fs.existsSync(this.branchDir(target))) {
      throw new Error(`Branch '${target}' not found.`);
    }

    return this.withLock(() => {
      const allCommits = this.parseCommits(target);
      const commits = allCommits.slice(-k);
      const otaRecords = this.parseOTA(target);
      const mainRoadmap = this.read(this.mainMd());
      const metadata = this.parseMeta(target);

      return makeContextResult(target, k, commits, otaRecords, mainRoadmap, metadata);
    });
  }

  // ------------------------------------------------------------------ //
  // Helpers                                                              //
  // ------------------------------------------------------------------ //

  get currentBranch(): string {
    return this._currentBranch;
  }

  switchBranch(name: string): void {
    validateBranchName(name);
    if (!fs.existsSync(this.branchDir(name))) {
      throw new Error(`Branch '${name}' does not exist.`);
    }
    this._currentBranch = name;
  }

  listBranches(): string[] {
    const branchesRoot = path.join(this.gccDir, "branches");
    try {
      return fs
        .readdirSync(branchesRoot)
        .filter((f) => fs.statSync(path.join(branchesRoot, f)).isDirectory());
    } catch {
      return [];
    }
  }
}

