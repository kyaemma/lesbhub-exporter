-- Regression probe: a flush already in progress outlives a competing flush.
local Journal = require("../src/journal")
local writes = 0
local journal = Journal.new({batchSize=1}, {write=function()
    coroutine.yield("write_in_progress")
    writes += 1
    return true
end})
local producer = coroutine.create(function() journal:append("remote-observations", {sequence=1}) end)
local ok, state = coroutine.resume(producer)
assert(ok and state == "write_in_progress")
journal:freeze()
assert(not journal:flush(), "concurrent flush should report busy")
assert(journal:summary().durableEvents == 0 and journal:index().streams["remote-observations"].events == 0)
assert(coroutine.resume(producer))
assert(coroutine.status(producer) == "dead" and writes == 1)
assert(journal:summary().durableEvents == 1 and journal:index().streams["remote-observations"].events == 1,
    "suspended writer should commit after the competing flush returned")
print("Finalization race reproduced: a busy flush can finish after its competitor returns")
