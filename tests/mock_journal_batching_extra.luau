-- Appended to mock_capture by build_mock_journal_batching.py.
local oldGetgenv, oldTypeof, oldWait, oldChildren = getgenv, typeof, task.wait, gui._children
local env, callback = {}, nil
getgenv = function() return env end
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) callback=cb; return function() end end}
local remote = instance("BatchRemote", "RemoteEvent")
remote.Parent = gui
function remote:IsDescendantOf(root) return root == gui end
typeof = function(value) if value == remote then return "Instance" end; return oldTypeof(value) end
gui._children = {remote}
local control, active, emitted = {}, false, 0
simulatedTime = 100
task.wait = function(seconds)
    simulatedTime += math.max(seconds or 0, 0.01)
    if active and seconds and seconds >= 0.14 and seconds <= 0.16 then
        for _ = 1, math.min(3, 100 - emitted) do
            callback({invokeKind=emitted % 2 == 0 and "Request" or "Callback"}, remote, "Incoming", nil)
            emitted += 1
        end
        if emitted == 100 then control.stopRequested = true end
    end
end
local result, why = captureEngine({label="JournalBatchFixture", targets={PlayerGui=true}, continuous=true,
    continuousInterval=3, runtimeWindowSeconds=0, observeRemotes=true, publicGameMetadata=false}, function(info)
    if info.stage == "monitoring_start" then active = true end
end, control)
getgenv, typeof, task.wait, gui._children = oldGetgenv, oldTypeof, oldWait, oldChildren
simulatedTime = nil
assert(result, why)
local stream = result.manifest.journal.streams["remote-observations"]
assert(emitted == 100 and stream.events == 100, "lost a synthetic remote occurrence")
local counted, segments, lastSequence = 0, #stream.segments, 0
local signatures = http:JSONDecode(rawWrites[result.folder .. "/remotes/signatures.json"]).signatures
for _, segment in ipairs(stream.segments) do
    local payload = http:JSONDecode(rawWrites[result.folder .. "/" .. segment.path])
    assert(#payload.rows == segment.count)
    for _, row in ipairs(payload.rows) do
        assert(row.sequence > lastSequence, "journal chronology changed")
        assert(signatures[row.signatureId].invokeKind == (counted % 2 == 0 and "Request" or "Callback"),
            "journal occurrence order changed")
        lastSequence = row.sequence; counted += 1
    end
end
assert(counted == 100)
print("Journal batching result", "events=" .. emitted, "segments=" .. segments,
    "meanRows=" .. string.format("%.2f", emitted / segments))
assert(segments <= 8, "partial segments were flushed more frequently than once per second")
print("Journal batching OK: all 100 occurrences preserved")
