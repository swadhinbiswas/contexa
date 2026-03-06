//! cortexa — Git-inspired context management for LLM agents.
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
// Input Validation                                                     //
// ------------------------------------------------------------------ //

pub const ValidationError = error{
    EmptyInput,
    InvalidBranchName,
};

/// Returns true if value is empty or whitespace-only.
fn isEmpty(value: []const u8) bool {
    if (value.len == 0) return true;
    for (value) |c| {
        if (c != ' ' and c != '\t' and c != '\n' and c != '\r') return false;
    }
    return true;
}

/// Return error if value is empty or whitespace-only.
fn validateNotEmpty(value: []const u8) ValidationError!void {
    if (isEmpty(value)) return ValidationError.EmptyInput;
}

/// Return error if name is not a valid branch identifier.
fn validateBranchName(name: []const u8) ValidationError!void {
    try validateNotEmpty(name);
    if (mem.indexOf(u8, name, "/") != null or mem.indexOf(u8, name, "\\") != null) {
        return ValidationError.InvalidBranchName;
    }
    if (mem.eql(u8, name, ".") or mem.eql(u8, name, "..")) {
        return ValidationError.InvalidBranchName;
    }
}

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

/// Parsed branch metadata from YAML. Owns all string memory.
const ParsedBranchMetadata = struct {
    name: []u8,
    purpose: []u8,
    created_from: []u8,
    created_at: []u8,
    status: []u8,
    merged_into: ?[]u8 = null,
    merged_at: ?[]u8 = null,

    pub fn deinit(self: *const ParsedBranchMetadata, allocator: mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.purpose);
        allocator.free(self.created_from);
        allocator.free(self.created_at);
        allocator.free(self.status);
        if (self.merged_into) |mi| allocator.free(mi);
        if (self.merged_at) |ma| allocator.free(ma);
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
    // File locking                                                       //
    // ---------------------------------------------------------------- //

    /// Acquire an exclusive file lock on .GCC/.lock.
    /// Returns the lock file handle; caller must call unlock() + close() when done.
    fn acquireLock(self: Self) !fs.File {
        const lock_path = try fs.path.join(self.allocator, &.{ self.root, GCC_DIR, ".lock" });
        defer self.allocator.free(lock_path);
        const file = fs.createFileAbsolute(lock_path, .{ .truncate = false }) catch |err| {
            if (err == error.PathAlreadyExists) {
                const f = try fs.openFileAbsolute(lock_path, .{ .mode = .write_only });
                try f.lock(.exclusive);
                return f;
            }
            return err;
        };
        try file.lock(.exclusive);
        return file;
    }

    fn releaseLock(_: Self, file: fs.File) void {
        file.unlock();
        file.close();
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

    /// Returns an allocated ISO 8601 UTC timestamp string.
    /// The caller owns the returned memory.
    fn nowTimestamp(self: Self) ![]u8 {
        const epoch_seconds = std.time.timestamp();
        const es = std.time.epoch.EpochSeconds{ .secs = @intCast(epoch_seconds) };
        const epoch_day = es.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = es.getDaySeconds();

        return fmt.allocPrint(self.allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
            year_day.year,
            @intFromEnum(month_day.month),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        });
    }

    fn generateID(self: Self) ![]u8 {
        var rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const r = rng.random();
        const id = try fmt.allocPrint(self.allocator, "{x:0>8}", .{r.int(u32)});
        return id;
    }

    /// Parse a YAML value from a line of text.
    /// Returns the value after "key: " with surrounding quotes stripped.
    fn parseYamlValue(self: Self, content: []const u8, key: []const u8) ![]u8 {
        const search = try fmt.allocPrint(self.allocator, "{s}: ", .{key});
        defer self.allocator.free(search);

        var lines_it = mem.splitScalar(u8, content, '\n');
        while (lines_it.next()) |line| {
            if (mem.startsWith(u8, line, search)) {
                var val = line[search.len..];
                // Strip surrounding single quotes
                if (val.len >= 2 and val[0] == '\'' and val[val.len - 1] == '\'') {
                    val = val[1 .. val.len - 1];
                }
                if (mem.eql(u8, val, "null")) {
                    return try self.allocator.dupe(u8, "");
                }
                return try self.allocator.dupe(u8, val);
            }
        }
        return try self.allocator.dupe(u8, "");
    }

    /// Parse branch metadata from YAML content.
    fn parseBranchMetadata(self: Self, content: []const u8) !ParsedBranchMetadata {
        const name = try self.parseYamlValue(content, "name");
        const purpose = try self.parseYamlValue(content, "purpose");
        const created_from = try self.parseYamlValue(content, "created_from");
        const created_at = try self.parseYamlValue(content, "created_at");
        const status = try self.parseYamlValue(content, "status");
        const mi_str = try self.parseYamlValue(content, "merged_into");
        const ma_str = try self.parseYamlValue(content, "merged_at");

        const merged_into: ?[]u8 = if (mi_str.len == 0) blk: {
            self.allocator.free(mi_str);
            break :blk null;
        } else mi_str;

        const merged_at: ?[]u8 = if (ma_str.len == 0) blk: {
            self.allocator.free(ma_str);
            break :blk null;
        } else ma_str;

        return .{
            .name = name,
            .purpose = purpose,
            .created_from = created_from,
            .created_at = created_at,
            .status = status,
            .merged_into = merged_into,
            .merged_at = merged_at,
        };
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

        const lock_file = try self.acquireLock();
        defer self.releaseLock(lock_file);

        // main.md — global roadmap
        const main_path = try self.mainMdPath();
        defer self.allocator.free(main_path);
        const ts = try self.nowTimestamp();
        defer self.allocator.free(ts);
        const roadmap = try fmt.allocPrint(
            self.allocator,
            "# Project Roadmap\n\n**Initialized:** {s}\n\n{s}\n",
            .{ ts, project_roadmap },
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
        const meta_ts = try self.nowTimestamp();
        defer self.allocator.free(meta_ts);
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.allocator);
        const meta = BranchMetadata{
            .name = MAIN_BRANCH,
            .purpose = "Primary reasoning trajectory",
            .created_from = "",
            .created_at = meta_ts,
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
        // At least one field must be non-empty
        if (isEmpty(observation) and isEmpty(thought) and isEmpty(action))
            return ValidationError.EmptyInput;

        const lock_file = try self.acquireLock();
        defer self.releaseLock(lock_file);

        const step = (try self.countOTASteps(self.current_branch)) + 1;
        const ts = try self.nowTimestamp();
        defer self.allocator.free(ts);
        const record = OTARecord{
            .step = step,
            .timestamp = ts,
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
        try validateNotEmpty(contribution);

        const lock_file = try self.acquireLock();
        defer self.releaseLock(lock_file);
        return self.commitInner(contribution, previous_summary);
    }

    /// Internal commit logic, called with lock already held.
    fn commitInner(
        self: *Self,
        contribution: []const u8,
        previous_summary: ?[]const u8,
    ) !CommitRecord {
        const id = try self.generateID();

        // Read branch purpose from metadata
        const meta_file = try self.metaFilePath(self.current_branch);
        defer self.allocator.free(meta_file);
        const meta_content = try self.readFile(meta_file);
        defer self.allocator.free(meta_content);
        var branch_purpose: []const u8 = "Active branch";
        var parsed_meta: ?ParsedBranchMetadata = null;
        if (meta_content.len > 0) {
            parsed_meta = try self.parseBranchMetadata(meta_content);
            branch_purpose = parsed_meta.?.purpose;
        }
        defer if (parsed_meta) |pm| pm.deinit(self.allocator);

        const prev = previous_summary orelse "Initial state — no prior commits.";

        const ts = try self.nowTimestamp();
        defer self.allocator.free(ts);
        const record = CommitRecord{
            .commit_id = id,
            .branch_name = self.current_branch,
            .branch_purpose = branch_purpose,
            .previous_progress_summary = prev,
            .this_commit_contribution = contribution,
            .timestamp = ts,
        };

        const commit_file = try self.commitFilePath(self.current_branch);
        defer self.allocator.free(commit_file);

        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.allocator);
        try record.writeMarkdown(buf.writer(self.allocator));
        try self.appendToFile(commit_file, buf.items);

        // Return record — commit_id ownership transfers to caller
        return CommitRecord{
            .commit_id = id,
            .branch_name = self.current_branch,
            .branch_purpose = branch_purpose,
            .previous_progress_summary = prev,
            .this_commit_contribution = contribution,
            .timestamp = ts,
        };
    }

    /// BRANCH command (paper §3.3).
    /// Creates isolated workspace: B_t^(name) = BRANCH(M_{t-1}).
    pub fn branch(self: *Self, name: []const u8, purpose: []const u8) !void {
        try validateBranchName(name);
        try validateNotEmpty(purpose);

        const branch_dir = try self.branchDir(name);
        defer self.allocator.free(branch_dir);
        try fs.makeDirAbsolute(branch_dir);

        const lock_file = try self.acquireLock();
        defer self.releaseLock(lock_file);

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
        const ts = try self.nowTimestamp();
        defer self.allocator.free(ts);
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.allocator);
        const meta = BranchMetadata{
            .name = name,
            .purpose = purpose,
            .created_from = self.current_branch,
            .created_at = ts,
            .status = "active",
        };
        try meta.writeYaml(buf.writer(self.allocator));
        try self.writeFile(meta_file, buf.items);

        self.current_branch = name;
    }

    /// MERGE command (paper §3.4).
    /// Integrates branch into target, merging summaries and OTA traces.
    /// Preserves the original branch metadata (purpose, created_from, created_at)
    /// and only updates status, merged_into, and merged_at fields.
    pub fn merge(self: *Self, branch_name: []const u8, target: []const u8) !CommitRecord {
        try validateBranchName(branch_name);
        try validateBranchName(target);

        // Read original branch metadata before anything else
        const orig_meta_file = try self.metaFilePath(branch_name);
        defer self.allocator.free(orig_meta_file);
        const orig_meta_content = try self.readFile(orig_meta_file);
        defer self.allocator.free(orig_meta_content);
        var parsed_meta: ?ParsedBranchMetadata = null;
        if (orig_meta_content.len > 0) {
            parsed_meta = try self.parseBranchMetadata(orig_meta_content);
        }
        defer if (parsed_meta) |pm| pm.deinit(self.allocator);

        const lock_file = try self.acquireLock();
        defer self.releaseLock(lock_file);

        // Append branch OTA to target's log
        const src_log = try self.logPath(branch_name);
        defer self.allocator.free(src_log);
        const src_content = try self.readFile(src_log);
        defer self.allocator.free(src_content);

        if (src_content.len > 0) {
            const target_log = try self.logPath(target);
            defer self.allocator.free(target_log);
            const merge_ts = try self.nowTimestamp();
            defer self.allocator.free(merge_ts);
            const header = try fmt.allocPrint(
                self.allocator,
                "\n## Merged from `{s}` ({s})\n\n",
                .{ branch_name, merge_ts },
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
        defer self.allocator.free(summary);
        const merge_commit = try self.commitInner(summary, null);

        // Update branch metadata to mark as merged, preserving original fields
        const meta_file2 = try self.metaFilePath(branch_name);
        defer self.allocator.free(meta_file2);
        const merged_ts = try self.nowTimestamp();
        defer self.allocator.free(merged_ts);
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.allocator);

        if (parsed_meta) |pm| {
            const updated_meta = BranchMetadata{
                .name = pm.name,
                .purpose = pm.purpose,
                .created_from = pm.created_from,
                .created_at = pm.created_at,
                .status = "merged",
                .merged_into = target,
                .merged_at = merged_ts,
            };
            try updated_meta.writeYaml(buf.writer(self.allocator));
        } else {
            const fallback_meta = BranchMetadata{
                .name = branch_name,
                .purpose = "",
                .created_from = "",
                .created_at = "",
                .status = "merged",
                .merged_into = target,
                .merged_at = merged_ts,
            };
            try fallback_meta.writeYaml(buf.writer(self.allocator));
        }
        try self.writeFile(meta_file2, buf.items);

        return merge_commit;
    }

    /// CONTEXT command (paper §3.5).
    /// Reads the K most-recent commits + OTA log from the given branch.
    /// Paper experiments fix K=1 (most recent commit record only).
    /// Returns a ContextSnapshot with parsed commits filtered to last K.
    pub fn context(self: Self, branch_name: ?[]const u8, k: usize) !ContextSnapshot {
        if (k < 1) return ValidationError.EmptyInput;

        const target = branch_name orelse self.current_branch;

        const lock_file = try self.acquireLock();
        defer self.releaseLock(lock_file);

        const main_path = try self.mainMdPath();
        defer self.allocator.free(main_path);
        const roadmap = try self.readFile(main_path);

        const log = try self.logPath(target);
        defer self.allocator.free(log);
        const ota_content = try self.readFile(log);

        const commit_file = try self.commitFilePath(target);
        defer self.allocator.free(commit_file);
        const all_commit_content = try self.readFile(commit_file);
        defer self.allocator.free(all_commit_content);

        // Parse and filter to last K commits for the returned content
        var commit_blocks: std.ArrayListUnmanaged([]const u8) = .empty;
        defer commit_blocks.deinit(self.allocator);
        const split_result = try splitBlocks(self.allocator, all_commit_content);
        defer {
            for (split_result) |blk| self.allocator.free(blk);
            self.allocator.free(split_result);
        }
        for (split_result) |block| {
            const trimmed = mem.trim(u8, block, " \t\n\r");
            if (trimmed.len > 0 and mem.indexOf(u8, trimmed, "## Commit `") != null) {
                try commit_blocks.append(self.allocator, trimmed);
            }
        }

        // Build filtered commit content (last K blocks)
        var filtered_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer filtered_buf.deinit(self.allocator);
        const total = commit_blocks.items.len;
        const start_idx = if (total > k) total - k else 0;
        for (commit_blocks.items[start_idx..]) |block| {
            const writer = filtered_buf.writer(self.allocator);
            try writer.writeAll(block);
            try writer.writeAll("\n\n---\n");
        }
        const commit_history = try self.allocator.dupe(u8, filtered_buf.items);

        return ContextSnapshot{
            .branch_name = target,
            .k = k,
            .main_roadmap = roadmap,
            .ota_log = ota_content,
            .commit_history = commit_history,
        };
    }

    /// List all branches in the workspace.
    pub fn listBranches(self: Self) ![][]u8 {
        const branches_path = try fs.path.join(self.allocator, &.{ self.root, GCC_DIR, "branches" });
        defer self.allocator.free(branches_path);

        var dir = fs.openDirAbsolute(branches_path, .{ .iterate = true }) catch return &[_][]u8{};
        defer dir.close();

        var names: std.ArrayListUnmanaged([]u8) = .empty;
        var dir_it = dir.iterate();
        while (try dir_it.next()) |entry| {
            if (entry.kind == .directory) {
                try names.append(self.allocator, try self.allocator.dupe(u8, entry.name));
            }
        }
        return names.toOwnedSlice(self.allocator);
    }

    pub fn currentBranch(self: Self) []const u8 {
        return self.current_branch;
    }

    pub fn switchBranch(self: *Self, name: []const u8) ValidationError!void {
        try validateBranchName(name);
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

    /// Render a formatted markdown summary of this context.
    pub fn summary(self: *const ContextSnapshot, allocator: mem.Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(allocator);
        const writer = buf.writer(allocator);

        try writer.print("# CONTEXT — branch `{s}` (K={d})\n\n", .{ self.branch_name, self.k });
        try writer.writeAll("## Global Roadmap\n");
        try writer.writeAll(self.main_roadmap);
        try writer.writeAll("\n\n");
        try writer.print("## Last {d} Commit(s)\n", .{self.k});
        try writer.writeAll(self.commit_history);
        if (self.ota_log.len > 0) {
            try writer.writeAll("\n## Recent OTA Steps\n");
            try writer.writeAll(self.ota_log);
        }

        return allocator.dupe(u8, buf.items);
    }

    /// Free all owned memory.
    pub fn deinit(self: *const ContextSnapshot, allocator: mem.Allocator) void {
        allocator.free(self.main_roadmap);
        allocator.free(self.ota_log);
        allocator.free(self.commit_history);
    }
};

// ------------------------------------------------------------------ //
// Input sanitization                                                   //
// ------------------------------------------------------------------ //

/// Escape content that could break the markdown separator format.
/// Replaces occurrences of "\n---\n" in user content with "\n\---\n"
/// to prevent parser confusion.
pub fn sanitizeContent(allocator: mem.Allocator, input: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (i + 4 <= input.len and mem.eql(u8, input[i .. i + 4], "\n---")) {
            // Check if followed by \n or end of string
            if (i + 4 == input.len or input[i + 4] == '\n') {
                try result.appendSlice(allocator, "\n\\---");
                i += 4;
                continue;
            }
        }
        try result.append(allocator, input[i]);
        i += 1;
    }
    return allocator.dupe(u8, result.items);
}

/// Reverse the escaping applied by sanitizeContent.
/// Replaces "\n\---\n" back to "\n---\n".
pub fn desanitizeContent(allocator: mem.Allocator, input: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (i + 5 <= input.len and mem.eql(u8, input[i .. i + 5], "\n\\---")) {
            if (i + 5 == input.len or input[i + 5] == '\n') {
                try result.appendSlice(allocator, "\n---");
                i += 5;
                continue;
            }
        }
        try result.append(allocator, input[i]);
        i += 1;
    }
    return allocator.dupe(u8, result.items);
}

/// Split text on "---\n" separator while respecting escaped separators
/// ("\---\n" produced by sanitizeContent). Returns a list of blocks.
pub fn splitBlocks(allocator: mem.Allocator, text: []const u8) ![][]const u8 {
    // First, naive split on "---\n"
    var raw_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer raw_parts.deinit(allocator);

    var it = mem.splitSequence(u8, text, "---\n");
    while (it.next()) |part| {
        try raw_parts.append(allocator, part);
    }

    // Rejoin blocks where previous block ends with '\'
    var blocks: std.ArrayListUnmanaged([]const u8) = .empty;
    defer blocks.deinit(allocator);

    var i: usize = 0;
    while (i < raw_parts.items.len) {
        var block_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer block_buf.deinit(allocator);
        try block_buf.appendSlice(allocator, raw_parts.items[i]);

        while (block_buf.items.len > 0 and
            block_buf.items[block_buf.items.len - 1] == '\\' and
            i + 1 < raw_parts.items.len)
        {
            i += 1;
            try block_buf.appendSlice(allocator, "---\n");
            try block_buf.appendSlice(allocator, raw_parts.items[i]);
        }
        try blocks.append(allocator, try allocator.dupe(u8, block_buf.items));
        i += 1;
    }
    return try allocator.dupe([]const u8, blocks.items);
}

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

test "timestamp is not hardcoded" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var ws = Workspace.init(std.testing.allocator, root);
    const ts = try ws.nowTimestamp();
    defer std.testing.allocator.free(ts);

    // Should NOT be the old hardcoded value
    try std.testing.expect(!mem.eql(u8, ts, "2025-01-01T00:00:00Z"));
    // Should look like an ISO timestamp: YYYY-MM-DDTHH:MM:SSZ
    try std.testing.expectEqual(@as(usize, 20), ts.len);
    try std.testing.expectEqual(@as(u8, 'T'), ts[10]);
    try std.testing.expectEqual(@as(u8, 'Z'), ts[19]);
}

test "merge preserves branch metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var ws = Workspace.init(std.testing.allocator, root);
    try ws.create("Test");
    try ws.branch("feature", "Implement auth system");

    const c = try ws.commit("Auth done", null);
    defer std.testing.allocator.free(c.commit_id);
    const mc = try ws.merge("feature", "main");
    defer std.testing.allocator.free(mc.commit_id);

    // Read metadata and verify original purpose is preserved
    const meta_file = try ws.metaFilePath("feature");
    defer std.testing.allocator.free(meta_file);
    const meta_content = try ws.readFile(meta_file);
    defer std.testing.allocator.free(meta_content);

    try std.testing.expect(mem.indexOf(u8, meta_content, "Implement auth system") != null);
    try std.testing.expect(mem.indexOf(u8, meta_content, "merged") != null);
    try std.testing.expect(mem.indexOf(u8, meta_content, "merged_into: main") != null);
}

test "context K filters commits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var ws = Workspace.init(std.testing.allocator, root);
    try ws.create("Test");

    const c1 = try ws.commit("Commit one", null);
    defer std.testing.allocator.free(c1.commit_id);
    const c2 = try ws.commit("Commit two", null);
    defer std.testing.allocator.free(c2.commit_id);
    const c3 = try ws.commit("Commit three", null);
    defer std.testing.allocator.free(c3.commit_id);

    // K=1 should only return the last commit
    const ctx = try ws.context(null, 1);
    defer ctx.deinit(std.testing.allocator);

    try std.testing.expect(mem.indexOf(u8, ctx.commit_history, "Commit three") != null);
    try std.testing.expect(mem.indexOf(u8, ctx.commit_history, "Commit one") == null);
}

test "sanitizeContent escapes separators" {
    const input = "some text\n---\nmore text";
    const result = try sanitizeContent(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(mem.indexOf(u8, result, "\n---\n") == null);
    try std.testing.expect(mem.indexOf(u8, result, "\\---") != null);
}
