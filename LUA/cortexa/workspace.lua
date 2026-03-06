--- cortexa — Git-inspired context management for LLM agents
--- GCCWorkspace: persistent versioned memory workspace.
--- Based on arXiv:2508.00031.
---
--- @module cortexa.workspace

local models = require("cortexa.models")
local lfs_ok, lfs = pcall(require, "lfs")

local W = {}
W.__index = W

local MAIN_BRANCH = "main"
local GCC_DIR = ".GCC"

------------------------------------------------------------------------
-- Input validation
------------------------------------------------------------------------

--- Check if a string is nil, empty, or whitespace-only.
--- @param s string|nil
--- @return boolean
local function is_blank(s)
    if s == nil then return true end
    if type(s) ~= "string" then return true end
    return s:match("^%s*$") ~= nil
end

--- Validate a branch name: non-blank, no / or \, not "." or "..".
--- @param name string
local function validate_branch_name(name)
    if is_blank(name) then
        error("Branch name must not be empty")
    end
    if name:find("/", 1, true) or name:find("\\", 1, true) then
        error("Branch name must not contain '/' or '\\'")
    end
    if name == "." or name == ".." then
        error("Branch name must not be '.' or '..'")
    end
end

------------------------------------------------------------------------
-- Filesystem helpers
------------------------------------------------------------------------

local function path_join(...)
    local parts = { ... }
    return table.concat(parts, "/")
end

local function dir_exists(path)
    if lfs_ok then
        local attr = lfs.attributes(path)
        return attr and attr.mode == "directory"
    end
    -- fallback: use os.rename (works on most POSIX systems)
    local ok, _, code = os.rename(path, path)
    if ok then return true end
    if code == 13 then return true end
    -- second fallback: try test -d
    local ret = os.execute('test -d "' .. path .. '"')
    -- Lua 5.1 returns number, 5.2+ returns boolean
    if ret == true or ret == 0 then return true end
    return false
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function mkdir_p(path)
    if lfs_ok then
        -- split and create each segment, preserving leading /
        local accum = path:sub(1, 1) == "/" and "/" or ""
        for seg in path:gmatch("[^/]+") do
            accum = accum == "" and seg
                or accum == "/" and ("/" .. seg)
                or (accum .. "/" .. seg)
            if not dir_exists(accum) then
                lfs.mkdir(accum)
            end
        end
        return
    end
    -- fallback: rely on system mkdir -p
    os.execute('mkdir -p "' .. path .. '"')
    -- verify, retry with segment-by-segment if needed
    if not dir_exists(path) then
        local accum = path:sub(1, 1) == "/" and "/" or ""
        for seg in path:gmatch("[^/]+") do
            accum = accum == "" and seg
                or accum == "/" and ("/" .. seg)
                or (accum .. "/" .. seg)
            os.execute('mkdir "' .. accum .. '" 2>/dev/null')
        end
    end
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local content = f:read("*a")
    f:close()
    return content or ""
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then error("Cannot write to " .. path) end
    f:write(content)
    f:close()
end

local function append_file(path, content)
    local f = io.open(path, "a")
    if not f then error("Cannot append to " .. path) end
    f:write(content)
    f:close()
end

local function list_dirs(path)
    local dirs = {}
    if lfs_ok then
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then
                local full = path_join(path, entry)
                local attr = lfs.attributes(full)
                if attr and attr.mode == "directory" then
                    dirs[#dirs + 1] = entry
                end
            end
        end
    else
        -- fallback: use ls
        local handle = io.popen('ls -1 "' .. path .. '" 2>/dev/null')
        if handle then
            for line in handle:lines() do
                if line ~= "" then
                    local full = path_join(path, line)
                    if dir_exists(full) then
                        dirs[#dirs + 1] = line
                    end
                end
            end
            handle:close()
        end
    end
    table.sort(dirs)
    return dirs
end

------------------------------------------------------------------------
-- File locking (mkdir-based, atomic on POSIX)
------------------------------------------------------------------------

local LOCK_TIMEOUT = 10  -- seconds
local LOCK_RETRY_MS = 50 -- milliseconds between retries

--- Acquire a workspace lock by creating .GCC/.lock directory.
--- mkdir is atomic on POSIX filesystems, so only one process succeeds.
--- @param gcc_dir string
--- @return boolean success
local function acquire_lock(gcc_dir)
    local lock_dir = path_join(gcc_dir, ".lock_dir")
    local deadline = os.time() + LOCK_TIMEOUT

    while true do
        -- Try mkdir — succeeds only if directory doesn't exist
        if lfs_ok then
            local ok = lfs.mkdir(lock_dir)
            if ok then return true end
        else
            -- Use mkdir without -p so it fails if dir exists
            local ret = os.execute('mkdir "' .. lock_dir .. '" 2>/dev/null')
            if ret == true or ret == 0 then return true end
        end

        -- Check for stale lock (older than LOCK_TIMEOUT)
        if lfs_ok then
            local attr = lfs.attributes(lock_dir)
            if attr and os.time() - attr.modification > LOCK_TIMEOUT then
                -- Stale lock, force remove and retry
                os.execute('rmdir "' .. lock_dir .. '" 2>/dev/null')
            end
        elseif os.time() > deadline then
            -- Fallback: force remove stale lock after timeout
            os.execute('rmdir "' .. lock_dir .. '" 2>/dev/null')
        end

        if os.time() > deadline then
            error("Failed to acquire workspace lock at " .. lock_dir)
        end

        -- Sleep briefly before retry (Lua has no native sleep, use os.execute)
        os.execute("sleep 0.05")
    end
end

--- Release the workspace lock.
--- @param gcc_dir string
local function release_lock(gcc_dir)
    local lock_dir = path_join(gcc_dir, ".lock_dir")
    os.execute('rmdir "' .. lock_dir .. '" 2>/dev/null')
end

--- Run a function while holding the workspace lock.
--- @param gcc_dir string
--- @param fn function
--- @return any ... returns from fn
local function with_lock(gcc_dir, fn)
    acquire_lock(gcc_dir)
    local ok, result = pcall(fn)
    release_lock(gcc_dir)
    if not ok then error(result, 0) end
    return result
end

------------------------------------------------------------------------
-- Parsing helpers
------------------------------------------------------------------------

--- Split a string by a delimiter pattern.
--- @param text string
--- @param delim string
--- @return string[]
local function split(text, delim)
    local parts = {}
    local pos = 1
    while true do
        local s, e = text:find(delim, pos, true)  -- plain find
        if not s then
            parts[#parts + 1] = text:sub(pos)
            break
        end
        parts[#parts + 1] = text:sub(pos, s - 1)
        pos = e + 1
    end
    return parts
end

--- Split markdown text on the separator while respecting escaped separators.
--- After naive splitting, blocks whose predecessor ends with "\" are rejoined
--- (the backslash means the separator was escaped by sanitize).
--- @param text string
--- @param delim string
--- @return string[]
local function split_blocks(text, delim)
    local raw = split(text, delim)
    local blocks = {}
    local i = 1
    while i <= #raw do
        local block = raw[i]
        while block:sub(-1) == "\\" and i + 1 <= #raw do
            i = i + 1
            block = block .. delim .. raw[i]
        end
        blocks[#blocks + 1] = block
        i = i + 1
    end
    return blocks
end

--- Extract a field value from a markdown block by prefix, supporting multi-line.
--- Collects lines until the next recognized field marker or end of block.
--- @param block string
--- @param prefix string  e.g. "**Timestamp:**"
--- @return string
local function extract_field(block, prefix)
    -- Escape Lua pattern special chars in prefix
    local escaped = prefix:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    -- Find the line that starts with the prefix
    local start_pos = block:find(escaped)
    if not start_pos then
        return ""
    end
    -- Get the first line's value
    local first_line = block:match(escaped .. "%s*(.-)\n", start_pos)
    if not first_line then
        first_line = block:match(escaped .. "%s*(.-)$", start_pos)
        return first_line and first_line:match("^%s*(.-)%s*$") or ""
    end
    -- Collect continuation lines until the next field marker or end of block
    local lines = { first_line:match("^%s*(.-)%s*$") }
    local after = block:sub(start_pos + #prefix + #first_line + 1)
    for line in after:gmatch("([^\n]*)") do
        local trimmed = line:match("^%s*(.-)%s*$") or ""
        -- Stop if we hit another field marker or header
        if trimmed:match("^%*%*[^*]+:%*%*") or trimmed:match("^##") then
            break
        end
        if trimmed ~= "" then
            lines[#lines + 1] = trimmed
        end
    end
    return table.concat(lines, "\n")
end

--- Parse commit records from commit.md content.
--- @param text string
--- @return CommitRecord[]
local function parse_commits(text)
    local records = {}
    local blocks = split_blocks(text, "\n---\n")
    for _, block in ipairs(blocks) do
        block = block:match("^%s*(.-)%s*$") or "" -- trim
        if block ~= "" then
            local commit_id = block:match("## Commit `([^`]+)`") or ""
            if commit_id ~= "" then
                local rec = {
                    commit_id = commit_id,
                    timestamp = extract_field(block, "**Timestamp:**"),
                    branch_name = "",
                    branch_purpose = models.desanitize(extract_field(block, "**Branch Purpose:**")),
                    previous_progress_summary = models.desanitize(extract_field(block, "**Previous Progress Summary:**")),
                    this_commit_contribution = models.desanitize(extract_field(block, "**This Commit's Contribution:**")),
                }
                records[#records + 1] = rec
            end
        end
    end
    return records
end

--- Parse OTA records from log.md content.
--- @param text string
--- @return OTARecord[]
local function parse_ota(text)
    local records = {}
    local blocks = split_blocks(text, "\n---\n")
    for _, block in ipairs(blocks) do
        block = block:match("^%s*(.-)%s*$") or "" -- trim
        if block ~= "" then
            local step_str, ts = block:match("### Step (%d+) %— (.-)%s*\n")
            if not step_str then
                step_str, ts = block:match("### Step (%d+)%-(.-)%s*\n")
            end
            if not step_str then
                step_str, ts = block:match("### Step (%d+) %— (.-)%s*$")
            end
            local step = tonumber(step_str) or 0
            local obs = models.desanitize(extract_field(block, "**Observation:**"))
            local thought = models.desanitize(extract_field(block, "**Thought:**"))
            local action = models.desanitize(extract_field(block, "**Action:**"))
            if obs ~= "" or thought ~= "" or action ~= "" then
                records[#records + 1] = {
                    step = step,
                    timestamp = ts or "",
                    observation = obs,
                    thought = thought,
                    action = action,
                }
            end
        end
    end
    return records
end

------------------------------------------------------------------------
-- GCCWorkspace
------------------------------------------------------------------------

--- Create a new GCCWorkspace.
--- @param project_root string
--- @return GCCWorkspace
function W.new(project_root)
    local self = setmetatable({}, W)
    self.root = project_root
    self.gcc_dir = path_join(project_root, GCC_DIR)
    self._current_branch = MAIN_BRANCH
    return self
end

--- Initialize a fresh .GCC workspace.
--- @param project_roadmap string|nil
function W:init(project_roadmap)
    if dir_exists(self.gcc_dir) then
        error("Workspace already exists at " .. self.gcc_dir)
    end

    local branch_dir = path_join(self.gcc_dir, "branches", MAIN_BRANCH)
    mkdir_p(branch_dir)

    with_lock(self.gcc_dir, function()
        local ts = models.timestamp()
        local roadmap = project_roadmap or ""
        write_file(
            path_join(self.gcc_dir, "main.md"),
            string.format("# Project Roadmap\n\n**Initialized:** %s\n\n%s\n", ts, roadmap)
        )

        write_file(
            path_join(branch_dir, "log.md"),
            "# OTA Log — branch `main`\n\n"
        )
        write_file(
            path_join(branch_dir, "commit.md"),
            "# Commit History — branch `main`\n\n"
        )

        local meta = models.new_branch_metadata(MAIN_BRANCH, "Primary reasoning trajectory", "", ts)
        write_file(
            path_join(branch_dir, "metadata.yaml"),
            models.metadata_to_yaml(meta)
        )
    end)

    self._current_branch = MAIN_BRANCH
end

--- Attach to an existing .GCC workspace.
function W:load()
    if not dir_exists(self.gcc_dir) then
        error("No workspace found at " .. self.gcc_dir)
    end
    self._current_branch = MAIN_BRANCH
end

--- Get current branch name.
--- @return string
function W:current_branch()
    return self._current_branch
end

--- Get the directory path for a branch.
--- @param name string|nil
--- @return string
function W:_branch_dir(name)
    return path_join(self.gcc_dir, "branches", name or self._current_branch)
end

--- Log an OTA cycle to the current branch.
--- @param observation string
--- @param thought string
--- @param action string
--- @return OTARecord
function W:log_ota(observation, thought, action)
    if is_blank(observation) and is_blank(thought) and is_blank(action) then
        error("At least one of observation, thought, or action must be non-empty")
    end

    local rec
    with_lock(self.gcc_dir, function()
        local branch_dir = self:_branch_dir()
        local log_path = path_join(branch_dir, "log.md")
        local existing = parse_ota(read_file(log_path))
        local step = #existing + 1
        rec = models.new_ota(step, observation, thought, action)
        append_file(log_path, models.ota_to_markdown(rec))
    end)
    return rec
end

--- Internal commit logic (called with lock already held).
--- @param contribution string
--- @param previous_summary string|nil
--- @param update_roadmap string|nil
--- @return CommitRecord
function W:_commit_inner(contribution, previous_summary, update_roadmap)
    local branch_dir = self:_branch_dir()
    local meta_text = read_file(path_join(branch_dir, "metadata.yaml"))
    local meta = models.metadata_from_yaml(meta_text)
    local branch_purpose = meta.purpose or ""

    if not previous_summary or previous_summary == "" then
        local commits = parse_commits(read_file(path_join(branch_dir, "commit.md")))
        if #commits > 0 then
            previous_summary = commits[#commits].this_commit_contribution
        else
            previous_summary = "Initial state — no prior commits."
        end
    end

    local rec = models.new_commit(
        self._current_branch, branch_purpose,
        previous_summary, contribution
    )
    append_file(
        path_join(branch_dir, "commit.md"),
        models.commit_to_markdown(rec)
    )

    if update_roadmap and update_roadmap ~= "" then
        local ts = models.timestamp()
        append_file(
            path_join(self.gcc_dir, "main.md"),
            string.format("\n## Update (%s)\n%s\n", ts, update_roadmap)
        )
    end

    return rec
end

--- COMMIT — checkpoint a milestone on the current branch.
--- @param contribution string
--- @param previous_summary string|nil
--- @param update_roadmap string|nil
--- @return CommitRecord
function W:commit(contribution, previous_summary, update_roadmap)
    if is_blank(contribution) then
        error("Contribution must not be empty")
    end

    local rec
    with_lock(self.gcc_dir, function()
        rec = self:_commit_inner(contribution, previous_summary, update_roadmap)
    end)
    return rec
end

--- BRANCH — create an isolated reasoning workspace.
--- @param name string
--- @param purpose string
function W:branch(name, purpose)
    validate_branch_name(name)
    if is_blank(purpose) then
        error("Branch purpose must not be empty")
    end

    local branch_dir = path_join(self.gcc_dir, "branches", name)
    if dir_exists(branch_dir) then
        error("Branch already exists: " .. name)
    end

    mkdir_p(branch_dir)

    with_lock(self.gcc_dir, function()
        write_file(
            path_join(branch_dir, "log.md"),
            string.format("# OTA Log — branch `%s`\n\n", name)
        )
        write_file(
            path_join(branch_dir, "commit.md"),
            string.format("# Commit History — branch `%s`\n\n", name)
        )

        local meta = models.new_branch_metadata(name, purpose, self._current_branch)
        write_file(
            path_join(branch_dir, "metadata.yaml"),
            models.metadata_to_yaml(meta)
        )
    end)

    self._current_branch = name
end

--- Switch to an existing branch.
--- @param name string
function W:switch_branch(name)
    validate_branch_name(name)
    local branch_dir = path_join(self.gcc_dir, "branches", name)
    if not dir_exists(branch_dir) then
        error("Branch does not exist: " .. name)
    end
    self._current_branch = name
end

--- List all branches.
--- @return string[]
function W:list_branches()
    local branches_dir = path_join(self.gcc_dir, "branches")
    if not dir_exists(branches_dir) then return {} end
    return list_dirs(branches_dir)
end

--- MERGE — integrate a branch back into a target.
--- @param branch_name string
--- @param summary string|nil
--- @param target string|nil
--- @return CommitRecord
function W:merge(branch_name, summary, target)
    validate_branch_name(branch_name)
    target = target or MAIN_BRANCH
    validate_branch_name(target)

    local src_dir = path_join(self.gcc_dir, "branches", branch_name)
    local tgt_dir = path_join(self.gcc_dir, "branches", target)

    if not dir_exists(src_dir) then
        error("Source branch does not exist: " .. branch_name)
    end
    if not dir_exists(tgt_dir) then
        error("Target branch does not exist: " .. target)
    end

    local commit_rec
    with_lock(self.gcc_dir, function()
        local src_commits = parse_commits(read_file(path_join(src_dir, "commit.md")))
        local src_ota = parse_ota(read_file(path_join(src_dir, "log.md")))
        local src_meta_text = read_file(path_join(src_dir, "metadata.yaml"))
        local src_meta = models.metadata_from_yaml(src_meta_text)

        -- Auto-generate summary if not provided
        if not summary or summary == "" then
            local contributions = {}
            for _, c in ipairs(src_commits) do
                contributions[#contributions + 1] = c.this_commit_contribution
            end
            summary = string.format(
                "Merged branch `%s` (%d commits). Contributions: %s",
                branch_name, #src_commits, table.concat(contributions, " | ")
            )
        end

        -- Append OTA records from source to target
        if #src_ota > 0 then
            local ts = models.timestamp()
            local header = string.format("\n## Merged from `%s` (%s)\n\n", branch_name, ts)
            append_file(path_join(tgt_dir, "log.md"), header)
            for _, rec in ipairs(src_ota) do
                append_file(path_join(tgt_dir, "log.md"), models.ota_to_markdown(rec))
            end
        end

        -- Switch to target and create merge commit (using inner to avoid double-lock)
        self._current_branch = target
        local prev = string.format("Merging branch `%s` with purpose: %s", branch_name, src_meta.purpose or "")
        local roadmap_update = string.format("Merged `%s`: %s", branch_name, summary)
        commit_rec = self:_commit_inner(summary, prev, roadmap_update)

        -- Update source metadata
        local ts = models.timestamp()
        src_meta.status = "merged"
        src_meta.merged_into = target
        src_meta.merged_at = ts
        write_file(path_join(src_dir, "metadata.yaml"), models.metadata_to_yaml(src_meta))
    end)

    return commit_rec
end

--- CONTEXT — hierarchical memory retrieval.
--- @param branch string|nil
--- @param k number|nil
--- @return ContextResult
function W:context(branch, k)
    branch = branch or self._current_branch
    k = k or 1
    if k < 1 then
        error("k must be >= 1")
    end

    local branch_dir = path_join(self.gcc_dir, "branches", branch)
    if not dir_exists(branch_dir) then
        error("Branch does not exist: " .. branch)
    end

    local result
    with_lock(self.gcc_dir, function()
        local all_commits = parse_commits(read_file(path_join(branch_dir, "commit.md")))
        local all_ota = parse_ota(read_file(path_join(branch_dir, "log.md")))
        local roadmap = read_file(path_join(self.gcc_dir, "main.md"))
        local meta_text = read_file(path_join(branch_dir, "metadata.yaml"))
        local meta = nil
        if meta_text ~= "" then
            meta = models.metadata_from_yaml(meta_text)
        end

        -- Last k commits
        local commits = {}
        local start = math.max(1, #all_commits - k + 1)
        for i = start, #all_commits do
            commits[#commits + 1] = all_commits[i]
        end

        result = models.new_context_result(branch, k)
        result.commits = commits
        result.ota_records = all_ota
        result.main_roadmap = roadmap
        result.metadata = meta
    end)

    return result
end

return W
