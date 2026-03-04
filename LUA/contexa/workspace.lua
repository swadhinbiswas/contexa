--- contexa — Git-inspired context management for LLM agents
--- GCCWorkspace: persistent versioned memory workspace.
--- Based on arXiv:2508.00031.
---
--- @module contexa.workspace

local models = require("contexa.models")
local lfs_ok, lfs = pcall(require, "lfs")

local W = {}
W.__index = W

local MAIN_BRANCH = "main"
local GCC_DIR = ".GCC"

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
    -- fallback: try to open directory
    local ok, _, code = os.rename(path, path)
    if ok then return true end
    -- code 13 = permission denied (exists but can't rename)
    return code == 13
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function mkdir_p(path)
    if lfs_ok then
        -- split and create each segment
        local accum = ""
        for seg in path:gmatch("[^/]+") do
            accum = accum == "" and seg or (accum .. "/" .. seg)
            if not dir_exists(accum) then
                lfs.mkdir(accum)
            end
        end
        return
    end
    -- fallback: use os.execute
    os.execute('mkdir -p "' .. path .. '"')
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

--- Extract a field value from a markdown block by prefix.
--- @param block string
--- @param prefix string  e.g. "**Timestamp:**"
--- @return string
local function extract_field(block, prefix)
    -- Escape Lua pattern special chars in prefix
    local escaped = prefix:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local val = block:match(escaped .. "%s*(.-)%s*\n")
    if not val then
        -- Try matching to end of string (last field in block)
        val = block:match(escaped .. "%s*(.-)%s*$")
    end
    return val or ""
end

--- Parse commit records from commit.md content.
--- @param text string
--- @return CommitRecord[]
local function parse_commits(text)
    local records = {}
    local blocks = split(text, "\n---\n")
    for _, block in ipairs(blocks) do
        block = block:match("^%s*(.-)%s*$") or "" -- trim
        if block ~= "" then
            local commit_id = block:match("## Commit `([^`]+)`") or ""
            if commit_id ~= "" then
                local rec = {
                    commit_id = commit_id,
                    timestamp = extract_field(block, "**Timestamp:**"),
                    branch_name = "",
                    branch_purpose = extract_field(block, "**Branch Purpose:**"),
                    previous_progress_summary = extract_field(block, "**Previous Progress Summary:**"),
                    this_commit_contribution = extract_field(block, "**This Commit's Contribution:**"),
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
    local blocks = split(text, "\n---\n")
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
            local obs = extract_field(block, "**Observation:**")
            local thought = extract_field(block, "**Thought:**")
            local action = extract_field(block, "**Action:**")
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
    local branch_dir = self:_branch_dir()
    local log_path = path_join(branch_dir, "log.md")
    local existing = parse_ota(read_file(log_path))
    local step = #existing + 1
    local rec = models.new_ota(step, observation, thought, action)
    append_file(log_path, models.ota_to_markdown(rec))
    return rec
end

--- COMMIT — checkpoint a milestone on the current branch.
--- @param contribution string
--- @param previous_summary string|nil
--- @param update_roadmap string|nil
--- @return CommitRecord
function W:commit(contribution, previous_summary, update_roadmap)
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

--- BRANCH — create an isolated reasoning workspace.
--- @param name string
--- @param purpose string
function W:branch(name, purpose)
    local branch_dir = path_join(self.gcc_dir, "branches", name)
    if dir_exists(branch_dir) then
        error("Branch already exists: " .. name)
    end

    mkdir_p(branch_dir)

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

    self._current_branch = name
end

--- Switch to an existing branch.
--- @param name string
function W:switch_branch(name)
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
    target = target or MAIN_BRANCH

    local src_dir = path_join(self.gcc_dir, "branches", branch_name)
    local tgt_dir = path_join(self.gcc_dir, "branches", target)

    if not dir_exists(src_dir) then
        error("Source branch does not exist: " .. branch_name)
    end
    if not dir_exists(tgt_dir) then
        error("Target branch does not exist: " .. target)
    end

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

    -- Switch to target and create merge commit
    self._current_branch = target
    local prev = string.format("Merging branch `%s` with purpose: %s", branch_name, src_meta.purpose or "")
    local roadmap_update = string.format("Merged `%s`: %s", branch_name, summary)
    local commit_rec = self:commit(summary, prev, roadmap_update)

    -- Update source metadata
    local ts = models.timestamp()
    src_meta.status = "merged"
    src_meta.merged_into = target
    src_meta.merged_at = ts
    write_file(path_join(src_dir, "metadata.yaml"), models.metadata_to_yaml(src_meta))

    return commit_rec
end

--- CONTEXT — hierarchical memory retrieval.
--- @param branch string|nil
--- @param k number|nil
--- @return ContextResult
function W:context(branch, k)
    branch = branch or self._current_branch
    k = k or 1

    local branch_dir = path_join(self.gcc_dir, "branches", branch)
    if not dir_exists(branch_dir) then
        error("Branch does not exist: " .. branch)
    end

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

    local result = models.new_context_result(branch, k)
    result.commits = commits
    result.ota_records = all_ota
    result.main_roadmap = roadmap
    result.metadata = meta

    return result
end

return W
