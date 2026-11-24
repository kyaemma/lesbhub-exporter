-- Appended to mock_capture by build_mock_callback_no_io.py.
local oldGetgenv, oldTypeof, oldWait, oldWrite, oldChildren = getgenv, typeof, task.wait, writefile, gui._children
local env, callback = {}, nil
getgenv = function() return env end
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) callback=cb; return function() end end}
local producing, apiReads, metadataReads = false, 0, 0
local backing = instance("NoIOBurstRemote", "RemoteEvent")
backing.Parent = gui
function backing:IsDescendantOf(root) return root == gui end
local remote = setmetatable({}, {__index=function(_, key)
    if producing then apiReads += 1; error("producer accessed Instance property " .. tostring(key)) end
    return backing[key]
end})
typeof = function(value) if value == remote then return "Instance" end; return oldTypeof(value) end
gui._children = {remote}
local control, producerWrites, producerWaits, producerCallbacks = {}, 0, 0, 0
local metadata = {}
for _, kind in ipairs({"Request", "Callback"}) do
    metadata[kind] = setmetatable({invokeKind=kind,argumentCount=1,
        argumentTypes=setmetatable({"number"}, {__index=function() metadataReads += 1; error("type metamethod called") end})},
        {__index=function() metadataReads += 1; error("metadata metamethod called") end})
end
writefile = function(path, data)
    if producing then producerWrites += 1 end
    return oldWrite(path, data)
end
simulatedTime = 100
task.wait = function(seconds)
    if producing then producerWaits += 1 end
    simulatedTime += math.max(seconds or 0, 0.01)
end
local result, why = captureEngine({label="CallbackNoIO", targets={PlayerGui=true}, continuous=true,
    runtimeWindowSeconds=0, observeRemotes=true, publicGameMetadata=false}, function(info)
    if info.stage ~= "monitoring_start" then return end
    producing = true
    for i = 1, 10000 do
        callback(metadata[i % 2 == 1 and "Request" or "Callback"], remote, "Incoming", nil)
        producerCallbacks += 1
    end
    producing = false
    control.stopRequested = true
end, control)
getgenv, typeof, task.wait, writefile, gui._children = oldGetgenv, oldTypeof, oldWait, oldWrite, oldChildren
simulatedTime = nil
assert(result, why)
assert(producerCallbacks == 10000 and producerWrites == 0 and producerWaits == 0 and apiReads == 0 and metadataReads == 0,
    "callback producer accessed Instances/metamethods, filesystem, or cooperative waits")
local stream = result.manifest.journal.streams["remote-observations"]
assert(stream.events == 10000 and result.manifest.runtime.observer.observedCalls == 10000)
local signatures = http:JSONDecode(rawWrites[result.folder .. "/remotes/signatures.json"]).signatures
local total, lastSequence = 0, 0
for _, segment in ipairs(stream.segments) do
    local payload = http:JSONDecode(rawWrites[result.folder .. "/" .. segment.path])
    for _, row in ipairs(payload.rows) do
        assert(row.sequence > lastSequence)
        assert(signatures[row.signatureId].invokeKind == (total % 2 == 0 and "Request" or "Callback"))
        lastSequence = row.sequence; total += 1
    end
end
assert(total == 10000 and result.manifest.dedup.lostEvents == 0)
print("Callback producer OK: 10000 ordered events, zero callback writes/waits, " .. #stream.segments .. " pump segments")

-- An unknown remote that vanishes before the pump still has an occurrence,
-- without invented identity, private names, paths, classes, or caller links.
local unknown = instance("PrivateUnknown", "RemoteEvent")
function unknown:IsDescendantOf() return false end
local unknownEnv, unknownCallback = {}, nil
unknownEnv.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) unknownCallback=cb; return function() end end}
getgenv = function() return unknownEnv end
typeof = function(value) if value == unknown then return "Instance" end; return oldTypeof(value) end
gui._children = {}
simulatedTime = 100
task.wait = function(seconds) simulatedTime += math.max(seconds or 0, 0.01) end
local unknownControl, admittedElapsed = {}, nil
local laterObject = instance("LaterStructuralEvent", "NumberValue", {Value=1})
laterObject.Parent = gui
local unknownResult, unknownError = captureEngine({label="UnresolvedRemote", targets={PlayerGui=true}, continuous=true,
    runtimeWindowSeconds=0, observeRemotes=true, publicGameMetadata=false}, function(info)
    if info.stage == "monitoring_start" then
        admittedElapsed = simulatedTime - 100
        unknownCallback({argumentCount=0}, unknown, "Incoming", {})
        gui._children = {laterObject}; gui.DescendantAdded:Fire(laterObject)
        simulatedTime += 20
        unknownControl.stopRequested = true
    end
end, unknownControl)
getgenv, typeof, task.wait, gui._children = oldGetgenv, oldTypeof, oldWait, oldChildren
simulatedTime = nil
assert(unknownResult, unknownError)
local unknownStream = unknownResult.manifest.journal.streams["remote-observations"]
local unknownRow = http:JSONDecode(rawWrites[unknownResult.folder .. "/" .. unknownStream.segments[1].path]).rows[1]
assert(unknownStream.events == 1 and unknownResult.manifest.runtime.observer.observedCalls == 1
    and unknownResult.manifest.runtime.observer.unresolvedCalls == 1 and unknownResult.manifest.runtime.status == "partial")
assert(unknownRow.identityStatus == "unresolved" and unknownRow.reason == "deferred_identity_unavailable"
    and unknownRow.instanceId == nil and unknownRow.robloxPath == nil and unknownRow.className == nil
    and unknownRow.callerInstanceId == nil and unknownRow.scriptId == nil)
assert(math.abs(unknownRow.elapsedSeconds - admittedElapsed) < 0.001,
    "deferred event timestamp must describe admission, not processing")
local laterSequence
for path, raw in pairs(rawWrites) do
    if path:find(unknownResult.folder, 1, true) then
        local payload = encodedObjects[raw]
        if type(payload) == "table" then
            for _, record in ipairs(payload.records or {}) do
                if record.name == "LaterStructuralEvent" then laterSequence = record.sequence end
            end
        end
    end
end
assert(laterSequence and unknownRow.sequence < laterSequence, "raw event lost its admission order")
print("Unresolved callback OK: retained without private metadata and with admission time")

-- Exceed the raw admission bound once: the loss is counted once, not hidden.
getgenv = function() return env end
typeof = function(value) if value == remote then return "Instance" end; return oldTypeof(value) end
gui._children = {remote}; simulatedTime = 100
task.wait = function(seconds) simulatedTime += math.max(seconds or 0, 0.01) end
local overflowResult, overflowError = captureEngine({label="RawOverflow", targets={PlayerGui=true}, continuous=true,
    runtimeWindowSeconds=0, observeRemotes=true, publicGameMetadata=false}, function(info)
    if info.stage ~= "monitoring_start" then return end
    producing = true
    for _ = 1, 16385 do callback(metadata.Request, remote, "Incoming", nil) end
    producing = false
end, {})
getgenv, typeof, task.wait, gui._children = oldGetgenv, oldTypeof, oldWait, oldChildren
simulatedTime = nil
assert(overflowResult, overflowError)
assert(overflowResult.manifest.runtime.observer.observedCalls == 16384
    and overflowResult.manifest.runtime.observer.lostRawObservations == 1
    and overflowResult.manifest.dedup.lostEvents == 1
    and overflowResult.manifest.dedup.pendingRawObservations == 0
    and overflowResult.manifest.runtime.status == "partial"
    and table.find(overflowResult.manifest.partialReasons, "remote_raw_queue_overflow"),
    "raw queue overflow must be counted exactly and reported")
print("Raw overflow OK: 16384 retained, one explicitly counted loss")
