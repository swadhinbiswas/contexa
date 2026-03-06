rockspec_format = "3.0"
package = "contexa"
version = "1.1.2-1"

source = {
    url = "git+https://github.com/swadhinbiswas/Cortexa.git",
    tag = "v1.1.2",
    dir = "LUA",
}

description = {
    summary = "Git-inspired context management for LLM agents",
    detailed = [[
        Contexa implements COMMIT, BRANCH, MERGE, and CONTEXT operations
        over a persistent versioned memory workspace for LLM agents.
        Based on the paper "Git Context Controller" (arXiv:2508.00031).
    ]],
    homepage = "https://github.com/swadhinbiswas/Cortexa",
    license = "MIT",
    maintainer = "Swadhin Biswas <swadhinbiswas.cse@gmail.com>",
    labels = { "llm", "agent", "context-management", "git", "memory" },
}

dependencies = {
    "lua >= 5.1",
    "luafilesystem >= 1.8",
}

build = {
    type = "builtin",
    modules = {
        ["contexa"]           = "contexa/init.lua",
        ["contexa.models"]    = "contexa/models.lua",
        ["contexa.workspace"] = "contexa/workspace.lua",
    },
}
