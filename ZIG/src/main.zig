//! contexa — Git-inspired context management for LLM agents.
//! COMMIT, BRANCH, MERGE, and CONTEXT over versioned memory.
//!
//! Paper: "Git Context Controller: Manage the Context of LLM-based Agents like Git"
//! arXiv:2508.00031 — Junde Wu et al., 2025
//!
//! File system layout:
//!   .GCC/
//!   ├── main.md                  # Global roadmap / planning artifact
//!   └── branches/
//!       ├── main/
//!       │   ├── log.md           # Continuous OTA trace (Observation-Thought-Action)
//!       │   ├── commit.md        # Milestone-level commit summaries
//!       │   └── metadata.yaml    # Branch intent, status, creation info
//!       └── <branch>/
//!           └── ...

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;

pub const MAIN_BRANCH = "main";
pub const GCC_DIR = ".GCC";

// ------------------------------------------------------------------ //
// Data Models                                                          //
// ------------------------------------------------------------------ //

/// A single Observation–Thought–Action cycle (logged to log.md).
/// The paper logs continuous OTA cycles as the agent executes.
pub const OTARecord = struct {
    step: usize,
    timestamp: []const u8,
    observation: []const u8,
    thought: []const u8,
    action: []const u8,

    /// Write this record to the log.md format used by the paper.
    pub fn writeMarkdown(self: OTARecord, writer: anytype) !void {
        try writer.print(
            "### Step {d} — {s}\n**Observation:** {s}\n\n**Thought:** {s}\n\n**Action:** {s}\n\n---\n",
            .{ self.step, self.timestamp, self.observation, self.thought, self.action },
        );
    }
};

/// A commit checkpoint (paper §3.2).
/// Fields: Branch Purpose, Previous Progress Summary, This Commit's Contribution.
pub const CommitRecord = struct {
    commit_id: []const u8,
    branch_name: []const u8,
    branch_purpose: []const u8,
    previous_progress_summary: []const u8,
    this_commit_contribution: []const u8,
    timestamp: []const u8,

    pub fn writeMarkdown(self: CommitRecord, writer: anytype) !void {
        try writer.print(
            "## Commit `{s}`\n**Timestamp:** {s}\n\n**Branch Purpose:** {s}\n\n" ++
                "**Previous Progress Summary:** {s}\n\n" ++
                "**This Commit's Contribution:** {s}\n\n---\n",
            .{
                self.commit_id,                self.timestamp,
                self.branch_purpose,           self.previous_progress_summary,
                self.this_commit_contribution,
            },
        );
    }
};

/// Branch metadata written to metadata.yaml (paper §3.1).
pub const BranchMetadata = struct {
    name: []const u8,
    purpose: []const u8,
    created_from: []const u8,
    created_at: []const u8,
    status: []const u8, // "active" | "merged" | "abandoned"
    merged_into: ?[]const u8 = null,
    merged_at: ?[]const u8 = null,

    pub fn writeYaml(self: BranchMetadata, writer: anytype) !void {
        try writer.print(
            "name: {s}\npurpose: {s}\ncreated_from: {s}\ncreated_at: {s}\nstatus: {s}\n",
            .{ self.name, self.purpose, self.created_from, self.created_at, self.status },
        );
        if (self.merged_into) |mi| {
            try writer.print("merged_into: {s}\n", .{mi});
        } else {
            try writer.writeAll("merged_into: null\n");
        }
        if (self.merged_at) |ma| {
            try writer.print("merged_at: {s}\n", .{ma});
        } else {
            try writer.writeAll("merged_at: null\n");
        }
    }
};

// ------------------------------------------------------------------ //
// Workspace                                                            //
// ------------------------------------------------------------------ //

/// Manages the .GCC/ directory structure for one agent project.
/// Implements the four GCC commands from arXiv:2508.00031v2.
pub const Workspace = struct {
    allocator: mem.Allocator,
    root: []const u8,
    current_branch: []const u8,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, project_root: []const u8) Self {
        return .{
            .allocator = allocator,
            .root = project_root,
            .current_branch = MAIN_BRANCH,
        };
    }

    // ---------------------------------------------------------------- //
    // Path helpers                                                       //
    // ---------------------------------------------------------------- //

    fn gccPath(self: Self) ![]u8 {
        return fs.path.join(self.allocator, &.{ self.root, GCC_DIR });
    }

    fn branchDir(self: Self, b: []const u8) ![]u8 {
        return fs.path.join(self.allocator, &.{ self.root, GCC_DIR, "branches", b });
    }

    fn logPath(self: Self, b: []const u8) ![]u8 {
        return fs.path.join(self.allocator, &.{ self.root, GCC_DIR, "branches", b, "log.md" });
    }

    fn commitFilePath(self: Self, b: []const u8) ![]u8 {
        return fs.path.join(self.allocator, &.{ self.root, GCC_DIR, "branches", b, "commit.md" });
    }

    fn metaFilePath(self: Self, b: []const u8) ![]u8 {
        return fs.path.join(self.allocator, &.{ self.root, GCC_DIR, "branches", b, "metadata.yaml" });
    }

    fn mainMdPath(self: Self) ![]u8 {
        return fs.path.join(self.allocator, &.{ self.root, GCC_DIR, "main.md" });
    }

    // ---------------------------------------------------------------- //
    // I/O helpers                                                        //
    // ---------------------------------------------------------------- //

    fn writeFile(self: Self, path: []const u8, content: []const u8) !void {
        _ = self;
        const file = try fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(content);
    }

    fn appendToFile(self: Self, path: []const u8, content: []const u8) !void {
        _ = self;
        const file = try fs.openFileAbsolute(path, .{ .mode = .write_only });
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(content);
    }

    fn readFile(self: Self, path: []const u8) ![]u8 {
        const file = fs.openFileAbsolute(path, .{}) catch return try self.allocator.dupe(u8, "");
        defer file.close();
        return file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
    }

    fn countOTASteps(self: Self, b: []const u8) !usize {
        const path = try self.logPath(b);
        defer self.allocator.free(path);
        const content = try self.readFile(path);
        defer self.allocator.free(content);
        var count: usize = 0;
        var it = mem.splitSequence(u8, content, "### Step ");
        _ = it.next(); // skip header
        while (it.next()) |_| count += 1;
        return count;
    }

    fn countCommits(self: Self, b: []const u8) !usize {
        const path = try self.commitFilePath(b);
        defer self.allocator.free(path);
        const content = try self.readFile(path);
        defer self.allocator.free(content);
        var count: usize = 0;
        var it = mem.splitSequence(u8, content, "## Commit `");
        _ = it.next(); // skip header
        while (it.next()) |_| count += 1;
        return count;
    }

    fn nowTimestamp(_: Self) []const u8 {
        // Returns a static placeholder; in production use std.time
        return "2025-01-01T00:00:00Z";
    }

    fn generateID(self: Self) ![]u8 {
        var rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const r = rng.random();
        const id = try fmt.allocPrint(self.allocator, "{x:0>8}", .{r.int(u32)});
        return id;
    }

    // ---------------------------------------------------------------- //
    // GCC Workspace Initialisation                                       //
    // ---------------------------------------------------------------- //

    /// Initialise a new GCC workspace.
    /// Creates .GCC/ structure: main.md, branches/main/{log,commit,metadata}.
    pub fn create(self: *Self, project_roadmap: []const u8) !void {
        const gcc = try self.gccPath();
        defer self.allocator.free(gcc);

        // Create directory structure
        const branch_dir = try self.branchDir(MAIN_BRANCH);
        defer self.allocator.free(branch_dir);
        try fs.makeDirAbsolute(gcc);
        const branches_path = try fs.path.join(self.allocator, &.{ gcc, "branches" });
        defer self.allocator.free(branches_path);
        try fs.makeDirAbsolute(branches_path);
        try fs.makeDirAbsolute(branch_dir);

        // main.md — global roadmap
        const main_path = try self.mainMdPath();
        defer self.allocator.free(main_path);
        const roadmap = try fmt.allocPrint(
            self.allocator,
            "# Project Roadmap\n\n**Initialized:** {s}\n\n{s}\n",
            .{ self.nowTimestamp(), project_roadmap },
        );
        defer self.allocator.free(roadmap);
        try self.writeFile(main_path, roadmap);

        // log.md
        const log = try self.logPath(MAIN_BRANCH);
        defer self.allocator.free(log);
        try self.writeFile(log, "# OTA Log — branch `main`\n\n");

        // commit.md
        const commit_file = try self.commitFilePath(MAIN_BRANCH);
        defer self.allocator.free(commit_file);
        try self.writeFile(commit_file, "# Commit History — branch `main`\n\n");

        // metadata.yaml
        const meta_file = try self.metaFilePath(MAIN_BRANCH);
        defer self.allocator.free(meta_file);
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.allocator);
        const meta = BranchMetadata{
            .name = MAIN_BRANCH,
            .purpose = "Primary reasoning trajectory",
            .created_from = "",
            .created_at = self.nowTimestamp(),
            .status = "active",
        };
        try meta.writeYaml(buf.writer(self.allocator));
        try self.writeFile(meta_file, buf.items);

        self.current_branch = MAIN_BRANCH;
    }

    // ---------------------------------------------------------------- //
    // GCC Commands                                                       //
    // ---------------------------------------------------------------- //

    /// Append an OTA step to current branch's log.md.
    /// The paper logs continuous Observation–Thought–Action cycles.
    pub fn logOTA(
        self: *Self,
        observation: []const u8,
        thought: []const u8,
        action: []const u8,
    ) !OTARecord {
        const step = (try self.countOTASteps(self.current_branch)) + 1;
        const record = OTARecord{
            .step = step,
            .timestamp = self.nowTimestamp(),
            .observation = observation,
            .thought = thought,
            .action = action,
        };
        const log = try self.logPath(self.current_branch);
        defer self.allocator.free(log);

        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.allocator);
        try record.writeMarkdown(buf.writer(self.allocator));
        try self.appendToFile(log, buf.items);
        return record;
    }

    /// COMMIT command (paper §3.2).
    /// Checkpoints milestone: Branch Purpose, Previous Progress Summary,
    /// This Commit's Contribution.
    pub fn commit(
        self: *Self,
        contribution: []const u8,
        previous_summary: ?[]const u8,
    ) !CommitRecord {
        const id = try self.generateID();

        const prev = previous_summary orelse "Initial state — no prior commits.";

        const record = CommitRecord{
            .commit_id = id,
            .branch_name = self.current_branch,
            .branch_purpose = "Active branch",
            .previous_progress_summary = prev,
            .this_commit_contribution = contribution,
            .timestamp = self.nowTimestamp(),
        };

        const commit_file = try self.commitFilePath(self.current_branch);
        defer self.allocator.free(commit_file);

        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.allocator);
        try record.writeMarkdown(buf.writer(self.allocator));
        try self.appendToFile(commit_file, buf.items);

        // Return record (commit_id is already owned by caller via generateID)
        return CommitRecord{
            .commit_id = id,
            .branch_name = self.current_branch,
            .branch_purpose = "Active branch",
            .previous_progress_summary = prev,
            .this_commit_contribution = contribution,
            .timestamp = self.nowTimestamp(),
        };
    }

    /// BRANCH command (paper §3.3).
    /// Creates isolated workspace: B_t^(name) = BRANCH(M_{t-1}).
    pub fn branch(self: *Self, name: []const u8, purpose: []const u8) !void {
        const branch_dir = try self.branchDir(name);
        defer self.allocator.free(branch_dir);
        try fs.makeDirAbsolute(branch_dir);

        // Empty OTA log (fresh execution trace, per paper §3.3)
        const log = try self.logPath(name);
        defer self.allocator.free(log);
        const log_header = try fmt.allocPrint(
            self.allocator,
            "# OTA Log — branch `{s}`\n\n",
            .{name},
        );
        defer self.allocator.free(log_header);
        try self.writeFile(log, log_header);

        // Empty commit.md
        const commit_file = try self.commitFilePath(name);
        defer self.allocator.free(commit_file);
        const commit_header = try fmt.allocPrint(
            self.allocator,
            "# Commit History — branch `{s}`\n\n",
            .{name},
        );
        defer self.allocator.free(commit_header);
        try self.writeFile(commit_file, commit_header);

        // metadata.yaml records intent and motivation (paper §3.3)
        const meta_file = try self.metaFilePath(name);
        defer self.allocator.free(meta_file);
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.allocator);
        const meta = BranchMetadata{
            .name = name,
            .purpose = purpose,
            .created_from = self.current_branch,
            .created_at = self.nowTimestamp(),
            .status = "active",
        };
        try meta.writeYaml(buf.writer(self.allocator));
        try self.writeFile(meta_file, buf.items);

        self.current_branch = name;
    }

    /// MERGE command (paper §3.4).
    /// Integrates branch into target, merging summaries and OTA traces.
    pub fn merge(self: *Self, branch_name: []const u8, target: []const u8) !CommitRecord {
        // Append branch OTA to target's log
        const src_log = try self.logPath(branch_name);
        defer self.allocator.free(src_log);
        const src_content = try self.readFile(src_log);
        defer self.allocator.free(src_content);

        if (src_content.len > 0) {
            const target_log = try self.logPath(target);
            defer self.allocator.free(target_log);
            const header = try fmt.allocPrint(
                self.allocator,
                "\n## Merged from `{s}` ({s})\n\n",
                .{ branch_name, self.nowTimestamp() },
            );
            defer self.allocator.free(header);
            try self.appendToFile(target_log, header);
            try self.appendToFile(target_log, src_content);
        }

        // Switch to target and commit the merge
        self.current_branch = target;
        const summary = try fmt.allocPrint(
            self.allocator,
            "Merged branch `{s}` into `{s}`",
            .{ branch_name, target },
        );
        // Note: summary is owned by allocator; commit will reference it, then we free
        const merge_commit = try self.commit(summary, null);

        // Update branch metadata to mark as merged
        const meta_file = try self.metaFilePath(branch_name);
        defer self.allocator.free(meta_file);
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.allocator);
        const meta = BranchMetadata{
            .name = branch_name,
            .purpose = "Merged branch",
            .created_from = "",
            .created_at = self.nowTimestamp(),
            .status = "merged",
            .merged_into = target,
            .merged_at = self.nowTimestamp(),
        };
        try meta.writeYaml(buf.writer(self.allocator));
        try self.writeFile(meta_file, buf.items);

        return merge_commit;
    }

    /// CONTEXT command (paper §3.5).
    /// Reads the K most-recent commits + OTA log from the given branch.
    /// Paper experiments fix K=1 (most recent commit record only).
    pub fn context(self: Self, branch_name: ?[]const u8, k: usize) !ContextSnapshot {
        const target = branch_name orelse self.current_branch;

        const main_path = try self.mainMdPath();
        defer self.allocator.free(main_path);
        const roadmap = try self.readFile(main_path);

        const log = try self.logPath(target);
        defer self.allocator.free(log);
        const ota_content = try self.readFile(log);

        const commit_file = try self.commitFilePath(target);
        defer self.allocator.free(commit_file);
        const commit_content = try self.readFile(commit_file);

        return ContextSnapshot{
            .branch_name = target,
            .k = k,
            .main_roadmap = roadmap,
            .ota_log = ota_content,
            .commit_history = commit_content,
        };
    }

    pub fn currentBranch(self: Self) []const u8 {
        return self.current_branch;
    }

    pub fn switchBranch(self: *Self, name: []const u8) void {
        self.current_branch = name;
    }
};

/// Snapshot returned by the CONTEXT command (paper §3.5).
/// The caller is responsible for freeing main_roadmap, ota_log, and commit_history.
pub const ContextSnapshot = struct {
    branch_name: []const u8,
    k: usize,
    main_roadmap: []const u8,
    ota_log: []const u8,
    commit_history: []const u8,

    /// Free all owned memory.
    pub fn deinit(self: *const ContextSnapshot, allocator: mem.Allocator) void {
        allocator.free(self.main_roadmap);
        allocator.free(self.ota_log);
        allocator.free(self.commit_history);
    }
};

// ------------------------------------------------------------------ //
// Tests                                                                //
// ------------------------------------------------------------------ //

test "workspace init creates GCC structure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var ws = Workspace.init(std.testing.allocator, root);
    try ws.create("Test project");

    // Verify .GCC/main.md exists
    const main_path = try ws.mainMdPath();
    defer std.testing.allocator.free(main_path);
    const f = try fs.openFileAbsolute(main_path, .{});
    f.close();
}

test "logOTA increments step" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var ws = Workspace.init(std.testing.allocator, root);
    try ws.create("Test");

    const r1 = try ws.logOTA("obs1", "thought1", "action1");
    const r2 = try ws.logOTA("obs2", "thought2", "action2");
    try std.testing.expectEqual(@as(usize, 1), r1.step);
    try std.testing.expectEqual(@as(usize, 2), r2.step);
}

test "commit writes checkpoint" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var ws = Workspace.init(std.testing.allocator, root);
    try ws.create("Test");

    const c = try ws.commit("Initial scaffold done", null);
    defer std.testing.allocator.free(c.commit_id);
    try std.testing.expectEqualStrings("Initial scaffold done", c.this_commit_contribution);
    try std.testing.expectEqualStrings(MAIN_BRANCH, c.branch_name);
}

test "branch creates isolated workspace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var ws = Workspace.init(std.testing.allocator, root);
    try ws.create("Test");
    try ws.branch("experiment", "Try alternative");
    try std.testing.expectEqualStrings("experiment", ws.currentBranch());

    // Branch should have fresh empty OTA log
    const step_count = try ws.countOTASteps("experiment");
    try std.testing.expectEqual(@as(usize, 0), step_count);
}

test "context returns roadmap and history" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var ws = Workspace.init(std.testing.allocator, root);
    try ws.create("My AI project roadmap");
    const c = try ws.commit("First milestone", null);
    defer std.testing.allocator.free(c.commit_id);

    const ctx = try ws.context(null, 1);
    defer ctx.deinit(std.testing.allocator);

    try std.testing.expect(mem.indexOf(u8, ctx.main_roadmap, "My AI project roadmap") != null);
    try std.testing.expect(mem.indexOf(u8, ctx.commit_history, "First milestone") != null);
}
