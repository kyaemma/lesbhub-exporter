-- Appended to mock_capture by build_mock_full_weak_identity.py.
local originalGetgenv, originalTypeof, originalWait, originalChildren = getgenv, typeof, task.wait, storage.GetChildren
local env, callback = {}, nil
getgenv = function() return env end
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) callback=cb; return function() end end}
local cache = setmetatable({}, {__mode="v"})
local originalAdded, originalRemoving = storage.DescendantAdded, storage.DescendantRemoving
storage.DescendantAdded, storage.DescendantRemoving = eventSignal(), eventSignal()
local backing = instance("WeakFullRemote", "RemoteEvent")
backing.Parent = storage
local persistent = instance("PersistentDuringScan", "NumberValue", {Value=7})
persistent.Parent = storage
local persistentAdded = false
function backing:GetDebugId() return "weak-full-remote" end
function backing:IsDescendantOf(root) return backing.Parent == root end
local present = true
storage.GetChildren = function()
    if not present then return {} end
    local wrapper = cache[1]
    if not wrapper then wrapper = setmetatable({}, {__index=backing}); cache[1] = wrapper end
    if persistentAdded then return {wrapper, persistent} end
    return {wrapper}
end
typeof = function(value) if value == cache[1] then return "Instance" end; return originalTypeof(value) end
simulatedTime = 100
task.wait = function(seconds) simulatedTime += math.max(seconds or 0, 0.01) end
local survived, releasedOnRemove, transientReleased
local transientCache = setmetatable({}, {__mode="v"})
local result, why = captureEngine({label="FullWeakIdentity", targets={ReplicatedStorage=true},
    runtimeWindowSeconds=1, observeRemotes=true, publicGameMetadata=false}, function(info)
    if info.stage == "service_start" then
        persistentAdded = true
        storage.DescendantAdded:Fire(persistent)
        local function transient()
            local value = instance("FullTransient", "Folder")
            value.Parent = storage; transientCache[1] = value
            storage.DescendantAdded:Fire(value)
            storage.DescendantRemoving:Fire(value)
        end
        transient(); collectgarbage("collect")
        transientReleased = transientCache[1] == nil
    elseif info.stage == "runtime_window_start" then
        collectgarbage("collect")
        survived = cache[1] ~= nil
        local function observeThenRemove()
            local wrapper = storage:GetChildren()[1]
            callback({}, wrapper, "Incoming", nil)
            storage.DescendantRemoving:Fire(wrapper)
            backing.Parent = nil
            present = false
        end
        observeThenRemove()
        collectgarbage("collect")
        releasedOnRemove = cache[1] == nil
    end
end, {})
assert(result, why)
assert(not releasedOnRemove, "the admitted remote reference must remain until the raw queue drains")
assert(transientReleased, "Full retained a transient object after removal")
local baselineId, observedId, transientAdds, transientRemoves, transientBaselines = nil, nil, 0, 0, 0
local persistentRecords = 0
for filename, raw in pairs(rawWrites) do
    if filename:find(result.folder, 1, true) then
        local payload = encodedObjects[raw]
        if type(payload) == "table" then
            for _, record in ipairs(payload.records or {}) do
                if record.name == "WeakFullRemote" and not record.operation then baselineId = record.instanceId end
                if record.name == "PersistentDuringScan" then persistentRecords += 1 end
                if record.name == "FullTransient" then
                    if record.operation == "add" then transientAdds += 1
                    elseif record.operation == "remove" then transientRemoves += 1
                    else transientBaselines += 1 end
                end
            end
            for _, row in ipairs(payload.rows or {}) do
                if row.direction == "Incoming" then
                    observedId = row.instanceId
                    assert(row.identityStatus == "resolved" and row.pathEvidence == "last_structural_observation")
                end
            end
        end
    end
end
print("Full weak-wrapper result", "survived=" .. tostring(survived),
    "baselineId=" .. tostring(baselineId), "observedId=" .. tostring(observedId),
    "persistentRecords=" .. persistentRecords)
assert(baselineId and observedId and baselineId == observedId, "Full runtime observation changed a live Instance identity")
assert(transientAdds == 1 and transientRemoves == 1 and transientBaselines == 0,
    "Full transient signals should remain a single add/remove pair without a false baseline")
assert(persistentRecords == 1, "signal plus Full baseline duplicated a persistent Instance")
collectgarbage("collect")
assert(cache[1] == nil, "drained raw queue retained a removed wrapper")

-- No removal signal: the capture itself must release its live anchors.
present = true
backing.Parent = storage
local cleanResult, cleanError = captureEngine({label="FullWeakCleanup", targets={ReplicatedStorage=true},
    runtimeWindowSeconds=0, observeRemotes=false, publicGameMetadata=false}, nil, {})
assert(cleanResult, cleanError)
collectgarbage("collect")
assert(cache[1] == nil, "Full retained wrapper after successful capture")

-- An exception after a wrapper has been discovered must also release it.
local priorChildren = storage.GetChildren
storage.GetChildren = function()
    local children = priorChildren()
    for i = 1, 20 do children[#children + 1] = instance("Filler" .. i, "Folder") end
    return children
end
task.wait = function() if cache[1] then error("synthetic traversal failure") end end
local failed, failReason = captureEngine({label="FullWeakFailure", targets={ReplicatedStorage=true},
    runtimeWindowSeconds=0, observeRemotes=false, publicGameMetadata=false, yieldEvery=1}, nil, {})
assert(not failed and failReason, "synthetic capture failure did not fire")
collectgarbage("collect")
assert(cache[1] == nil, "Full retained wrapper after exceptional cleanup")
storage.GetChildren, storage.DescendantAdded, storage.DescendantRemoving = originalChildren, originalAdded, originalRemoving
getgenv, typeof, task.wait = originalGetgenv, originalTypeof, originalWait
simulatedTime = nil
print("Full weak-wrapper identity OK: removal, completion and exception release anchors")
