--- cortexa — Git-inspired context management for LLM agents
--- COMMIT, BRANCH, MERGE, and CONTEXT operations over a persistent
--- versioned memory workspace. Based on arXiv:2508.00031.
---
--- @module cortexa.models

local M = {}

--- Generate an 8-character hex ID.
--- @return string
function M.generate_id()
    local bytes = {}
    for i = 1, 4 do
        bytes[i] = string.format("%02x", math.random(0, 255))
    end
    return table.concat(bytes)
end

--- Get current UTC timestamp in ISO 8601 format.
--- @return string
function M.timestamp()
    return os.date("!%Y-%m-%dT%H:%M:%S+00:00")
end

------------------------------------------------------------------------
-- Input sanitization
------------------------------------------------------------------------

--- Escape the separator sequence so user content cannot break parsers.
--- @param text string|nil
--- @return string
function M.sanitize(text)
    if not text then return "" end
    return (text:gsub("\n---\n", "\n\\---\n"))
end

--- Reverse the escaping applied by sanitize().
--- @param text string|nil
--- @return string
function M.desanitize(text)
    if not text then return "" end
    return (text:gsub("\n\\---\n", "\n---\n"))
end

------------------------------------------------------------------------
-- OTARecord
------------------------------------------------------------------------

--- @class OTARecord
--- @field step number
--- @field timestamp string
--- @field observation string
--- @field thought string
--- @field action string

--- Create a new OTARecord.
--- @param step number
--- @param observation string
--- @param thought string
--- @param action string
--- @param ts string|nil
--- @return OTARecord
function M.new_ota(step, observation, thought, action, ts)
    return {
        step = step,
        timestamp = ts or M.timestamp(),
        observation = observation or "",
        thought = thought or "",
        action = action or "",
    }
end

--- Render an OTARecord as markdown.
--- @param rec OTARecord
--- @return string
function M.ota_to_markdown(rec)
    return string.format(
        "### Step %d — %s\n**Observation:** %s\n\n**Thought:** %s\n\n**Action:** %s\n\n---\n",
        rec.step, rec.timestamp,
        M.sanitize(rec.observation), M.sanitize(rec.thought), M.sanitize(rec.action)
    )
end

------------------------------------------------------------------------
-- CommitRecord
------------------------------------------------------------------------

--- @class CommitRecord
--- @field commit_id string
--- @field branch_name string
--- @field branch_purpose string
--- @field previous_progress_summary string
--- @field this_commit_contribution string
--- @field timestamp string

--- Create a new CommitRecord.
--- @param branch_name string
--- @param branch_purpose string
--- @param previous_progress_summary string
--- @param this_commit_contribution string
--- @param ts string|nil
--- @return CommitRecord
function M.new_commit(branch_name, branch_purpose, previous_progress_summary, this_commit_contribution, ts)
    return {
        commit_id = M.generate_id(),
        branch_name = branch_name,
        branch_purpose = branch_purpose or "",
        previous_progress_summary = previous_progress_summary or "",
        this_commit_contribution = this_commit_contribution or "",
        timestamp = ts or M.timestamp(),
    }
end

--- Render a CommitRecord as markdown.
--- @param rec CommitRecord
--- @return string
function M.commit_to_markdown(rec)
    return string.format(
        "## Commit `%s`\n**Timestamp:** %s\n\n**Branch Purpose:** %s\n\n**Previous Progress Summary:** %s\n\n**This Commit's Contribution:** %s\n\n---\n",
        rec.commit_id, rec.timestamp,
        M.sanitize(rec.branch_purpose), M.sanitize(rec.previous_progress_summary),
        M.sanitize(rec.this_commit_contribution)
    )
end

------------------------------------------------------------------------
-- BranchMetadata
------------------------------------------------------------------------

--- @class BranchMetadata
--- @field name string
--- @field purpose string
--- @field created_from string
--- @field created_at string
--- @field status string
--- @field merged_into string|nil
--- @field merged_at string|nil

--- Create a new BranchMetadata.
--- @param name string
--- @param purpose string
--- @param created_from string
--- @param ts string|nil
--- @return BranchMetadata
function M.new_branch_metadata(name, purpose, created_from, ts)
    return {
        name = name,
        purpose = purpose,
        created_from = created_from or "",
        created_at = ts or M.timestamp(),
        status = "active",
        merged_into = nil,
        merged_at = nil,
    }
end

--- Serialize BranchMetadata to YAML string.
--- We write our own minimal serializer to avoid external YAML deps.
--- @param meta BranchMetadata
--- @return string
function M.metadata_to_yaml(meta)
    local function yaml_val(v)
        if v == nil then return "null" end
        if v == "" then return "''" end
        -- Quote strings that contain colons or special chars
        if v:find(":") or v:find("#") or v:find("'") then
            return "'" .. v:gsub("'", "''") .. "'"
        end
        return v
    end
    -- Write keys in sorted order for cross-language compatibility
    local lines = {
        "created_at: " .. yaml_val(meta.created_at),
        "created_from: " .. yaml_val(meta.created_from),
        "merged_at: " .. yaml_val(meta.merged_at),
        "merged_into: " .. yaml_val(meta.merged_into),
        "name: " .. yaml_val(meta.name),
        "purpose: " .. yaml_val(meta.purpose),
        "status: " .. yaml_val(meta.status),
    }
    return table.concat(lines, "\n") .. "\n"
end

--- Parse BranchMetadata from YAML string.
--- @param text string
--- @return BranchMetadata
function M.metadata_from_yaml(text)
    local meta = {
        name = "",
        purpose = "",
        created_from = "",
        created_at = "",
        status = "active",
        merged_into = nil,
        merged_at = nil,
    }
    for line in text:gmatch("[^\n]+") do
        local key, val = line:match("^(%S+):%s*(.*)$")
        if key and val then
            -- Strip surrounding quotes
            val = val:match("^'(.*)'$") or val
            if val == "null" then val = nil
            elseif val == "''" then val = ""
            end
            if key == "name" then meta.name = val or ""
            elseif key == "purpose" then meta.purpose = val or ""
            elseif key == "created_from" then meta.created_from = val or ""
            elseif key == "created_at" then meta.created_at = val or ""
            elseif key == "status" then meta.status = val or "active"
            elseif key == "merged_into" then meta.merged_into = val
            elseif key == "merged_at" then meta.merged_at = val
            end
        end
    end
    return meta
end

------------------------------------------------------------------------
-- ContextResult
------------------------------------------------------------------------

--- @class ContextResult
--- @field branch_name string
--- @field k number
--- @field commits CommitRecord[]
--- @field ota_records OTARecord[]
--- @field main_roadmap string
--- @field metadata BranchMetadata|nil

--- Create a new ContextResult.
--- @param branch_name string
--- @param k number
--- @return ContextResult
function M.new_context_result(branch_name, k)
    return {
        branch_name = branch_name,
        k = k,
        commits = {},
        ota_records = {},
        main_roadmap = "",
        metadata = nil,
    }
end

--- Render ContextResult summary as markdown.
--- @param ctx ContextResult
--- @return string
function M.context_summary(ctx)
    local parts = {}
    table.insert(parts, string.format("# CONTEXT — branch `%s` (K=%d)\n", ctx.branch_name, ctx.k))

    table.insert(parts, "## Global Roadmap\n" .. ctx.main_roadmap .. "\n")

    table.insert(parts, string.format("## Last %d Commit(s)\n", ctx.k))
    for _, c in ipairs(ctx.commits) do
        table.insert(parts, M.commit_to_markdown(c))
    end

    local total = #ctx.ota_records
    table.insert(parts, string.format("## Recent OTA steps (%d total)\n", total))
    local start = math.max(1, total - 4)
    for i = start, total do
        table.insert(parts, M.ota_to_markdown(ctx.ota_records[i]))
    end

    return table.concat(parts, "\n")
end

return M
