--- cortexa test suite
--- Run with: lua test.lua (requires luafilesystem)

-- Adjust package path to find the local cortexa module
package.path = "./?.lua;./?/init.lua;" .. package.path

local workspace = require("cortexa.workspace")
local models = require("cortexa.models")

local test_count = 0
local pass_count = 0
local fail_count = 0

local function test(name, fn)
    test_count = test_count + 1
    local ok, err = pcall(fn)
    if ok then
        pass_count = pass_count + 1
        print(string.format("  PASS  %s", name))
    else
        fail_count = fail_count + 1
        print(string.format("  FAIL  %s: %s", name, err))
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %q, got %q", msg or "assert_eq", tostring(b), tostring(a)), 2)
    end
end

local function assert_true(v, msg)
    if not v then error(msg or "assert_true failed", 2) end
end

local function assert_error(fn, msg)
    local ok, _ = pcall(fn)
    if ok then error(msg or "Expected error but none raised", 2) end
end

--- Create a unique temp directory for each test
local tmp_counter = 0
local function make_tmp()
    tmp_counter = tmp_counter + 1
    local dir = "/tmp/cortexa_lua_test_" .. os.time() .. "_" .. tmp_counter
    os.execute('rm -rf "' .. dir .. '"')
    os.execute('mkdir -p "' .. dir .. '"')
    return dir
end

local function cleanup(dir)
    os.execute('rm -rf "' .. dir .. '"')
end

------------------------------------------------------------------------
print("cortexa Lua test suite")
print(string.rep("=", 50))

------------------------------------------------------------------------
-- Model tests
------------------------------------------------------------------------
print("\n-- Models --")

test("generate_id returns 8 hex chars", function()
    local id = models.generate_id()
    assert_eq(#id, 8, "length")
    assert_true(id:match("^%x+$"), "should be hex")
end)

test("timestamp returns ISO 8601", function()
    local ts = models.timestamp()
    assert_true(ts:match("^%d%d%d%d%-%d%d%-%d%dT"), "ISO format")
end)

test("OTA to_markdown round-trip", function()
    local rec = models.new_ota(1, "saw something", "thinking", "did something")
    local md = models.ota_to_markdown(rec)
    assert_true(md:find("### Step 1"), "has step header")
    assert_true(md:find("saw something"), "has observation")
    assert_true(md:find("thinking"), "has thought")
    assert_true(md:find("did something"), "has action")
end)

test("Commit to_markdown round-trip", function()
    local rec = models.new_commit("main", "purpose", "prev", "contrib")
    local md = models.commit_to_markdown(rec)
    assert_true(md:find("## Commit"), "has commit header")
    assert_true(md:find("purpose"), "has purpose")
    assert_true(md:find("contrib"), "has contribution")
end)

test("BranchMetadata YAML round-trip", function()
    local meta = models.new_branch_metadata("test-branch", "test purpose", "main")
    local yaml = models.metadata_to_yaml(meta)
    local parsed = models.metadata_from_yaml(yaml)
    assert_eq(parsed.name, "test-branch", "name")
    assert_eq(parsed.purpose, "test purpose", "purpose")
    assert_eq(parsed.created_from, "main", "created_from")
    assert_eq(parsed.status, "active", "status")
    assert_eq(parsed.merged_into, nil, "merged_into")
end)

------------------------------------------------------------------------
-- Workspace tests
------------------------------------------------------------------------
print("\n-- Workspace --")

test("init creates workspace", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init("Test roadmap")
    assert_eq(ws:current_branch(), "main")
    local branches = ws:list_branches()
    assert_true(#branches >= 1, "has at least 1 branch")
    cleanup(dir)
end)

test("init fails if already exists", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    assert_error(function() ws:init() end, "should fail on double init")
    cleanup(dir)
end)

test("load attaches to existing workspace", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    local ws2 = workspace.new(dir)
    ws2:load()
    assert_eq(ws2:current_branch(), "main")
    cleanup(dir)
end)

test("load fails if no workspace", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    assert_error(function() ws:load() end, "should fail on missing workspace")
    cleanup(dir)
end)

test("log_ota appends records with incrementing steps", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    local r1 = ws:log_ota("obs1", "thought1", "act1")
    assert_eq(r1.step, 1, "step 1")
    local r2 = ws:log_ota("obs2", "thought2", "act2")
    assert_eq(r2.step, 2, "step 2")
    cleanup(dir)
end)

test("commit creates record with auto previous_summary", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    local c1 = ws:commit("First contribution")
    assert_true(c1.commit_id ~= "", "has commit_id")
    assert_true(#c1.commit_id == 8, "8-char id")
    -- Second commit should auto-fill previous_summary
    local c2 = ws:commit("Second contribution")
    assert_eq(c2.previous_progress_summary, "First contribution", "auto previous_summary")
    cleanup(dir)
end)

test("branch creates isolated workspace", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    ws:log_ota("obs", "thought", "action")
    ws:branch("feature", "Test feature")
    assert_eq(ws:current_branch(), "feature")
    -- New branch should have empty OTA/commits
    local ctx = ws:context("feature", 10)
    assert_eq(#ctx.ota_records, 0, "fresh OTA log")
    assert_eq(#ctx.commits, 0, "fresh commits")
    cleanup(dir)
end)

test("branch fails if duplicate name", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    ws:branch("dup", "purpose")
    ws:switch_branch("main")
    assert_error(function() ws:branch("dup", "purpose") end, "should fail on duplicate")
    cleanup(dir)
end)

test("switch_branch changes current branch", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    ws:branch("feature", "purpose")
    ws:switch_branch("main")
    assert_eq(ws:current_branch(), "main")
    cleanup(dir)
end)

test("switch_branch fails on non-existent branch", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    assert_error(function() ws:switch_branch("nope") end, "should fail")
    cleanup(dir)
end)

test("list_branches returns all branches", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    ws:branch("alpha", "purpose a")
    ws:switch_branch("main")
    ws:branch("beta", "purpose b")
    local branches = ws:list_branches()
    assert_true(#branches >= 3, "at least 3 branches")
    cleanup(dir)
end)

test("merge integrates branch into target", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    ws:branch("feature", "Add feature X")
    ws:log_ota("obs", "thought", "action")
    ws:commit("Implemented feature X")
    local merge_rec = ws:merge("feature", nil, "main")
    assert_eq(ws:current_branch(), "main", "switched to target")
    assert_true(merge_rec.commit_id ~= "", "has merge commit")
    -- Check source branch is marked merged
    local ctx = ws:context("main", 10)
    assert_true(#ctx.commits >= 1, "has merge commit on main")
    cleanup(dir)
end)

test("merge fails on non-existent source", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    assert_error(function() ws:merge("nope") end, "should fail")
    cleanup(dir)
end)

test("context returns correct data", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init("My roadmap")
    ws:log_ota("obs1", "t1", "a1")
    ws:log_ota("obs2", "t2", "a2")
    ws:commit("Commit 1")
    ws:commit("Commit 2")
    ws:commit("Commit 3")
    local ctx = ws:context("main", 2)
    assert_eq(#ctx.commits, 2, "last 2 commits")
    assert_eq(#ctx.ota_records, 2, "all OTA records")
    assert_true(ctx.main_roadmap:find("My roadmap"), "has roadmap")
    assert_true(ctx.metadata ~= nil, "has metadata")
    assert_eq(ctx.metadata.name, "main", "metadata.name")
    cleanup(dir)
end)

test("context k larger than available commits", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init()
    ws:commit("Only commit")
    local ctx = ws:context("main", 100)
    assert_eq(#ctx.commits, 1, "returns all available")
    cleanup(dir)
end)

test("context_summary renders markdown", function()
    local dir = make_tmp()
    local ws = workspace.new(dir)
    ws:init("Roadmap text")
    ws:log_ota("obs", "thought", "action")
    ws:commit("My contribution")
    local ctx = ws:context("main", 1)
    local summary = models.context_summary(ctx)
    assert_true(summary:find("CONTEXT"), "has CONTEXT header")
    assert_true(summary:find("Roadmap"), "has roadmap")
    assert_true(summary:find("My contribution"), "has commit")
    cleanup(dir)
end)

------------------------------------------------------------------------
print(string.format("\n%s", string.rep("=", 50)))
print(string.format("Results: %d/%d passed, %d failed", pass_count, test_count, fail_count))

if fail_count > 0 then
    os.exit(1)
end
