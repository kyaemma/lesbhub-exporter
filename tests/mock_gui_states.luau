local Gui = require("../src/gui_states")
local files, transitions = {}, {}
local writeFails = false
local function fingerprint(record)
    local p = record.properties
    return tostring(record.className) .. "|" .. tostring(p.Visible) .. "|" .. tostring(p.Enabled) .. "|" .. tostring(p.Text)
end
local context = {
    fingerprint = fingerprint,
    write = function(path, payload)
        if writeFails then return false end
        assert(not files[path]); files[path] = payload; return true
    end,
    emit = function(event) transitions[#transitions + 1] = event; return #transitions end,
    now = function() return 0 end,
}
local graph = Gui.new({}, context)
local function button(id, parent, text, visible, path)
    return {instanceId = id, parentInstanceId = parent, className = "TextButton",
        path = path or "PlayerGui/Menu/Play", properties = {Text = text, Visible = visible}}
end
local a = button(1, 20, "Play", true)
local b = button(2, 20, "Play", true)
assert(graph:observe(a) and graph:observe(b))
assert(graph:commit("baseline") == 1)
assert(graph:observe(a) and graph:observe(b))
assert(graph:commit("same") == 1)
assert(graph:summary().states == 1 and graph:summary().observations == 2)
assert(#files["gui/states/state000001.json"].elements == 2)
graph:noteActivation({instanceId = 1, sequence = 7})
assert(graph:summary().knownButtons == 2 and graph:summary().activatedKnownButtons == 1)
assert(graph:summary().unactivatedKnownButtons == 1)
assert(graph:observe(button(1, 20, "Pause", true)))
assert(graph:commit("text") == 2)
assert(graph:observe(button(1, 20, "Pause", false)))
assert(graph:commit("visibility") == 3)
assert(graph:observe(button(1, 21, "Pause", false)))
assert(graph:commit("parent") == 4)
assert(graph:observe({instanceId = 2, operation = "remove"}))
assert(graph:commit("remove") == 5)
assert(#graph:index().states == 5 and #graph:index().transitions == 4)
assert(transitions[1].causal == false and transitions[1].evidence == "successive_observations")
assert(graph:index().buttons[1].activationCount == 1 and graph:index().buttons[2].activationCount == 0)
writeFails = true
assert(graph:observe(button(1, 21, "Next", true)))
assert(graph:commit("error") == nil and graph:summary().writeErrors == 1)
writeFails = false
assert(graph:commit("retry") == 6)
local small = Gui.new({guiStateCacheEntries = 1}, context)
-- Separate output collector: each graph normally writes into a separate export directory.
context.write = function() return true end
assert(small:observe(button(1, 20, "a", true)))
assert(small:commit("a") == 1)
assert(small:observe(button(1, 20, "b", true)))
assert(small:commit("b") == 2)
assert(small:observe(button(1, 20, "a", true)))
assert(small:commit("a_again") == 3 and small:summary().cacheEvictions == 2)
local fingerprintCalls, writes = 0, 0
local fast = Gui.new({guiStateCacheEntries = 0}, {
    fingerprint = function(record) fingerprintCalls += 1; return fingerprint(record) end,
    write = function() writes += 1; return true end,
    emit = function() return 1 end,
})
assert(fast:observe(a) and fast:commit("first") == 1)
assert(fast:observe(a) and fast:commit("unchanged") == 1)
assert(writes == 1 and fast:summary().observations == 2)
assert(fingerprintCalls == 2)
local during, checkpoints, versions = nil, 0, {}
local changeDuringCommit = false
local yieldingContext = {fingerprint = fingerprint,
    write = function(_, payload) versions[#versions + 1] = payload; return true end,
    emit = function() return 1 end,
    budget = {checkpoint = function()
        checkpoints += 1
        if changeDuringCommit then
            changeDuringCommit = false
            assert(during:observe({instanceId = 129, operation = "remove"}))
        end
    end}}
during = Gui.new({}, yieldingContext)
for i = 1, 129 do assert(during:observe(button(i, 20, "same", true))) end
changeDuringCommit = true
assert(during:commit("before_yield") == 1)
assert(#versions[1].elements == 129)
assert(during:commit("after_yield") == 2 and #versions[2].elements == 128)
local before = checkpoints
assert(during:commit("clean") == 2 and checkpoints == before, "clean commit must not rebuild")
local badContext = {fingerprint = function() error("unreadable") end, write = function() error("must not write") end, emit = function() end}
local bad = Gui.new({}, badContext)
assert(not bad:observe(a) and bad:commit("invalid") == nil and bad:summary().fingerprintErrors == 1)
print("GUI states mock OK: dedup, identity, structure, coverage, errors, bounded cache")
