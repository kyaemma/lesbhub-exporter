-- Appended to mock_runtime_observer by build_mock_runtime_deferred.py.
local rawCallback, output, sequence, resolves, overflows, duringAdmission = nil, {}, 0, 0, 0, false
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) rawCallback=cb; return function() end end}
local known, unknown, moving, knownCaller, sameNameCaller = {}, {}, {}, {}, {}
local metadata = setmetatable({argumentCount=1, argumentTypes=setmetatable({"number"},
    {__index=function() error("types __index") end}), invokeKind="Request"},
    {__index=function() error("metadata __index") end})
local deferred
local rawContext = {now=function() return 0 end,
    reserve=function() sequence += 1; return sequence, "utc", sequence / 10 end,
    peekRemote=function(obj)
        if obj == known then return {instanceId=9, robloxPath="Root/Old", className="RemoteEvent"} end
    end,
    peekCaller=function(obj)
        if obj == knownCaller then return {instanceId=6, scriptId="s6"} end
    end,
    onRawOverflow=function() overflows += 1 end,
    resolve=function(obj)
        assert(not duringAdmission, "producer resolved an Instance")
        resolves += 1
        if obj == moving then return {instanceId=10, robloxPath="Root/New", className="RemoteEvent"} end
    end,
    emit=function(row) output[#output+1]=row; return row.sequence end}
deferred = Runtime.new({deferRaw=true,rawQueueLimit=3}, rawContext)
assert(deferred:start() == "attached")
duringAdmission = true
rawCallback(metadata, known, "Incoming", knownCaller)
rawCallback(metadata, unknown, "Outgoing", knownCaller)
rawCallback(metadata, moving, "Incoming", sameNameCaller)
rawCallback(metadata, {}, "Incoming", nil)
duringAdmission = false
assert(resolves == 0 and overflows == 1 and deferred:rawPending() == 3)
assert(deferred:summary().lostRawObservations == 1 and deferred:inFlight() == 0)
assert(deferred:stop() == "detached")
assert(deferred:drainRaw(2) and #output == 2 and deferred:rawPending() == 1)
assert(deferred:drainRaw(2) and #output == 3 and deferred:rawPending() == 0)
assert(output[1].instanceId == 9 and output[1].pathEvidence == "last_structural_observation"
    and output[1].scopeBasis == "last_known" and output[1].callerInstanceId == 6 and output[1].scriptId == "s6"
    and output[1].callerPathEvidence == "last_structural_observation")
assert(output[2].identityStatus == "unresolved" and output[2].reason == "deferred_identity_unavailable"
    and output[2].instanceId == nil and output[2].robloxPath == nil and output[2].className == nil
    and output[2].callerInstanceId == nil and output[2].scriptId == nil)
assert(output[3].instanceId == 10 and output[3].pathEvidence == "deferred_resolution"
    and output[3].scopeBasis == "resolved_at_drain" and output[3].callerInstanceId == nil,
    "a distinct unresolved caller must not reuse another caller's identity")
assert(output[1].sequence == 1 and output[2].sequence == 2 and output[3].sequence == 3
    and output[2].elapsedSeconds == 0.2 and deferred:summary().unresolvedCalls == 1
    and deferred:summary().observedCalls == 3)
print("Deferred runtime OK: admission has no resolve, unresolved occurrences retained, bounded FIFO")

local reentrantCallback, reentrant, reentrantRows, injected = nil, nil, {}, false
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) reentrantCallback=cb; return function() end end}
local serial = 0
local reentrantContext = {now=function() return 0 end,
    reserve=function() serial += 1; return serial, "utc", serial end,
    resolve=function()
        if not injected then injected = true; reentrantCallback({}, {}, "Incoming", nil) end
        return nil
    end,
    emit=function(row) reentrantRows[#reentrantRows+1]=row; return row.sequence end}
reentrant = Runtime.new({deferRaw=true,rawQueueLimit=4}, reentrantContext)
assert(reentrant:start() == "attached")
reentrantCallback({}, {}, "Incoming", nil)
assert(reentrant:drainRaw() and #reentrantRows == 1 and reentrant:rawPending() == 1,
    "reentrant admission changed the fixed drain cut")
assert(reentrant:drainRaw() and #reentrantRows == 2 and reentrant:rawPending() == 0)
reentrant:stop()

local failureCallback, admissionErrors = nil, 0
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) failureCallback=cb; return function() end end}
local failedAdmission = Runtime.new({deferRaw=true}, {now=function() return 0 end,
    reserve=function() error("synthetic admission failure") end,
    onRawError=function() admissionErrors += 1 end})
assert(failedAdmission:start() == "attached")
failureCallback({}, {}, "Incoming", nil)
assert(admissionErrors == 1 and failedAdmission:summary().lostRawObservations == 1
    and failedAdmission:rawPending() == 0, "admission error was not counted exactly")
failedAdmission:stop()
local fullCallback, canEmit, saved = nil, false, 0
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) fullCallback=cb; return function() end end}
local full = Runtime.new({deferRaw=true}, {now=function() return 0 end,
    reserve=function() return 1, "utc", 0 end, resolve=function() return nil end,
    canEmit=function() return canEmit end, emit=function(row) saved += 1; return row.sequence end})
assert(full:start() == "attached")
fullCallback({}, {}, "Incoming", nil)
assert(not full:drainRaw() and full:rawPending() == 1 and saved == 0 and full:summary().lostRawObservations == 0)
canEmit = true
assert(full:drainRaw() and full:rawPending() == 0 and saved == 1)
full:stop()
local uncertainCallback, uncertainAttempts, processErrors = nil, 0, 0
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) uncertainCallback=cb; return function() end end}
local uncertain = Runtime.new({deferRaw=true}, {now=function() return 0 end,
    reserve=function() return 1, "utc", 0 end, resolve=function() return nil end,
    emit=function() uncertainAttempts += 1; error("synthetic uncertain emit") end,
    onRawProcessError=function() processErrors += 1 end})
assert(uncertain:start() == "attached")
uncertainCallback({}, {}, "Incoming", nil)
assert(not uncertain:drainRaw() and not uncertain:drainRaw() and uncertainAttempts == 1
    and uncertain:rawPending() == 1 and processErrors == 1,
    "an uncertain emission was retried and could duplicate an occurrence")
uncertain:stop()
local callerCallback, savedCallerRow = nil, nil
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) callerCallback=cb; return function() end end}
local weakCaller = setmetatable({}, {__mode="v"})
local callerIds = setmetatable({}, {__mode="k"})
local liveCaller = {Name="Same"}
weakCaller[1] = liveCaller; callerIds[liveCaller] = {instanceId=72, scriptId="s72"}
local remoteRef = {}
local callerObserver = Runtime.new({deferRaw=true}, {now=function() return 0 end,
    reserve=function() return 1, "utc", 0 end,
    peekCaller=function(obj) local id=callerIds[obj]; return id and {instanceId=id.instanceId,scriptId=id.scriptId} end,
    resolve=function(obj) if obj == remoteRef then return {instanceId=10, className="RemoteEvent"} end end,
    emit=function(row) savedCallerRow=row; return row.sequence end})
assert(callerObserver:start() == "attached")
callerCallback({}, remoteRef, "Incoming", liveCaller)
liveCaller = nil; collectgarbage("collect")
assert(weakCaller[1], "raw caller reference must survive until drain")
assert(callerObserver:drainRaw() and savedCallerRow.callerInstanceId == 72 and savedCallerRow.scriptId == "s72"
    and savedCallerRow.callerPathEvidence == "last_structural_observation")
collectgarbage("collect")
assert(weakCaller[1] == nil, "drained raw caller reference was retained")
callerObserver:stop()
print("Deferred runtime reentrancy and admission failure OK")
