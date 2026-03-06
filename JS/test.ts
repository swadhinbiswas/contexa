/**
 * Tests for cortexa TypeScript package.
 * Run with: tsx --test test.ts
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GCCWorkspace } from "./src/workspace";

function makeWorkspace(): { dir: string; ws: GCCWorkspace } {
  const dir = mkdtempSync(join(tmpdir(), "gcc-test-"));
  const ws = new GCCWorkspace(dir);
  ws.init("Test project roadmap");
  return { dir, ws };
}

test("init creates .GCC structure", () => {
  const { dir } = makeWorkspace();
  try {
    assert.ok(existsSync(join(dir, ".GCC/main.md")));
    assert.ok(existsSync(join(dir, ".GCC/branches/main/log.md")));
    assert.ok(existsSync(join(dir, ".GCC/branches/main/commit.md")));
    assert.ok(existsSync(join(dir, ".GCC/branches/main/metadata.yaml")));
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("logOTA increments step", () => {
  const { dir, ws } = makeWorkspace();
  try {
    const r1 = ws.logOTA("obs1", "thought1", "action1");
    const r2 = ws.logOTA("obs2", "thought2", "action2");
    assert.equal(r1.step, 1);
    assert.equal(r2.step, 2);
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("commit writes checkpoint with correct fields", () => {
  const { dir, ws } = makeWorkspace();
  try {
    const c = ws.commit("Initial scaffold done");
    assert.equal(c.thisCommitContribution, "Initial scaffold done");
    assert.equal(c.branchName, "main");
    assert.equal(c.commitId.length, 8);
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("branch creates isolated workspace", () => {
  const { dir, ws } = makeWorkspace();
  try {
    ws.branch("experiment-a", "Try alternative algorithm");
    assert.equal(ws.currentBranch, "experiment-a");
    const branches = ws.listBranches();
    assert.ok(branches.includes("main"));
    assert.ok(branches.includes("experiment-a"));
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("branch OTA log starts empty", () => {
  const { dir, ws } = makeWorkspace();
  try {
    ws.logOTA("main obs", "main thought", "main action");
    ws.branch("clean-branch", "Fresh start");
    // context on new branch should have no OTA
    const ctx = ws.context("clean-branch", 1);
    assert.equal(ctx.otaRecords.length, 0);
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("merge integrates branch into main", () => {
  const { dir, ws } = makeWorkspace();
  try {
    ws.commit("Main first commit");
    ws.branch("feature", "Add feature X");
    ws.logOTA("feature obs", "feature thought", "feature action");
    ws.commit("Feature X implemented");
    const mergeCommit = ws.merge("feature", undefined, "main");
    assert.ok(mergeCommit.thisCommitContribution.includes("feature"));
    assert.equal(ws.currentBranch, "main");
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("context K=1 returns last commit only", () => {
  const { dir, ws } = makeWorkspace();
  try {
    ws.commit("C1");
    ws.commit("C2");
    ws.commit("C3");
    const ctx = ws.context(undefined, 1);
    assert.equal(ctx.commits.length, 1);
    assert.equal(ctx.commits[0]!.thisCommitContribution, "C3");
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("context K=3 returns last 3 commits", () => {
  const { dir, ws } = makeWorkspace();
  try {
    ws.commit("C1");
    ws.commit("C2");
    ws.commit("C3");
    ws.commit("C4");
    const ctx = ws.context(undefined, 3);
    assert.equal(ctx.commits.length, 3);
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("branch metadata records purpose and parent", () => {
  const { dir, ws } = makeWorkspace();
  try {
    ws.branch("jwt-branch", "JWT auth experiment");
    const ctx = ws.context("jwt-branch", 1);
    assert.equal(ctx.metadata?.purpose, "JWT auth experiment");
    assert.equal(ctx.metadata?.createdFrom, "main");
    assert.equal(ctx.metadata?.status, "active");
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("merge marks branch as merged", () => {
  const { dir, ws } = makeWorkspace();
  try {
    ws.branch("to-merge", "Will be merged");
    ws.commit("Branch work done");
    ws.merge("to-merge", undefined, "main");
    const ctx = ws.context("to-merge", 1);
    assert.equal(ctx.metadata?.status, "merged");
    assert.equal(ctx.metadata?.mergedInto, "main");
  } finally {
    rmSync(dir, { recursive: true });
  }
});
