local Journal = require("../src/journal")
local segments, writes, definition = {}, 0, {remoteId = 7, className = "RemoteEvent"}
local journal = Journal.new({}, {write = function(path, payload)
    assert(not segments[path], "durable segment overwritten")
    writes = writes + 1
    segments[path] = payload
    return true
end})
for i = 1, 10000 do
    assert(journal:append("remotes", {sequence = i, remoteId = definition.remoteId, elapsedSeconds = i / 10}))
end
assert(journal:flush())
local index, stats = journal:index(), journal:summary()
assert(index.version == 1 and index.streams.remotes.events == 10000 and stats.durableEvents == 10000)
assert(stats.lostEvents == 0 and stats.queued == 0 and stats.segments == 40)
local expected = 1
for _, segment in ipairs(index.streams.remotes.segments) do
    local data = assert(segments[segment.path])
    assert(segment.count == #data.rows and segment.firstSequence == expected)
    for _, row in ipairs(data.rows) do
        assert(row.sequence == expected and row.remoteId == definition.remoteId)
        expected = expected + 1
    end
    assert(segment.lastSequence == expected - 1)
end
assert(expected == 10001)
local before = writes
assert(journal:flush() and writes == before, "unchanged flush wrote data")

local calls, failedPath, failedPayload, retained = 0, nil, nil, {}
local retry = Journal.new({batchSize = 2}, {write = function(path, payload)
    calls = calls + 1
    if calls == 1 then
        -- Simulate a prefix left on disk despite the failed write.
        retained[path] = {payload.rows[1]}
        failedPath, failedPayload = path, payload
        return false
    end
    assert(path == failedPath and payload == failedPayload, "retry changed segment")
    retained[path] = payload.rows
    return true
end})
local mutable = {sequence = 1, nested = {value = "original"}}
assert(retry:append("actions", mutable))
mutable.nested.value = "changed"
assert(retry:append("actions", {sequence = 2}))
assert(retry:summary().queued == 2 and retry:index().streams.actions.events == 0)
assert(retry:flush())
assert(#retained[failedPath] == 2 and retained[failedPath][1].nested.value == "original")
assert(retry:summary().writeErrors == 1 and retry:index().streams.actions.events == 2)

local incoming, target, callbackCount = {}, nil, 0
target = Journal.new({batchSize = 2}, {write = function(path, payload)
    callbackCount = callbackCount + 1
    incoming[path] = payload
    if callbackCount == 1 then assert(target:append("events", {sequence = 3})) end
    return true
end})
assert(target:append("events", {sequence = 1}))
assert(target:append("events", {sequence = 2}))
assert(target:summary().queued == 1 and target:summary().durableEvents == 2)
assert(target:flush() and target:summary().durableEvents == 3)
assert(incoming["journal/events/b000002.json"].rows[1].sequence == 3)

local lost, overflow = 0, nil
overflow = Journal.new({batchSize = 1, maxQueued = 2}, {write = function(_, _)
    assert(overflow:append("events", {sequence = 2}))
    assert(not overflow:append("events", {sequence = 3}))
    return true
end, onOverflow = function(count) lost = count end})
assert(overflow:append("events", {sequence = 1}))
assert(lost == 1 and overflow:summary().lostEvents == 1 and overflow:summary().queuePeak == 2)
assert(overflow:summary().durableEvents == 1 and overflow:summary().queued == 1)

local frozenWrites = 0
local frozen = Journal.new({batchSize = 1}, {write = function() frozenWrites = frozenWrites + 1; return true end})
frozen:freeze()
assert(frozen:append("events", {sequence = 1}) and frozenWrites == 0)
assert(frozen:flush() and frozenWrites == 1)
frozen:thaw()
assert(frozen:append("events", {sequence = 2}) and frozenWrites == 2)
assert(not pcall(function() frozen:append("../escape", {sequence = 3}) end))
assert(not pcall(function() frozen:append("events", {sequence = 3, invalid = function() end}) end))
print("Journal OK: 10000 ordered occurrences, retry, reentrant arrivals, overflow and freeze")
