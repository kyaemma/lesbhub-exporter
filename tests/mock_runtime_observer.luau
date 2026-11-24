-- Standalone mock; build_mock_runtime.py inlines the module into this environment.
local env = {}
function getgenv() return env end
local Runtime = require("../src/runtime_observer")
local clock = 10
local events, cleanups = {}, 0
local remote = {id = 1}
local origin = {id = 2}
local late = false
local context = {
    now = function() return clock end,
    emit = function(event) event.sequence = #events + 1; events[#events + 1] = event; return event.sequence end,
    resolve = function(obj)
        if obj == remote then return {instanceId = 1, robloxPath = "ReplicatedStorage/Signal", className = "RemoteEvent"} end
        if obj == origin then return {instanceId = 2, scriptId = late and "s2" or nil} end
        return nil
    end,
}
local missing = Runtime.new({}, context)
assert(missing:start() == "unavailable" and missing:summary().reason == "cobalt_adapter_unavailable")
assert(Runtime.new({observeRemotes = false}, context):start() == "disabled")
env.LesbhubCobaltAdapter = {version = 1, subscribe = function() error("bad") end}
assert(Runtime.new({}, context):start() == "subscribe_failed")
local callback, unavailable
env.LesbhubCobaltAdapter = {version = 1, subscribe = function(cb, unavail)
    callback, unavailable = cb, unavail
    return function() cleanups += 1 end
end}
local observer = Runtime.new({}, context)
assert(observer:start() == "attached" and observer:summary().observedCalls == 0)
assert(observer:start() == "attached")
clock = 11
for i = 1, 5000 do
    observer:noteGuiAction({event = "gui_state_transition", sequence = 100 + i, toStateId = i, elapsedSeconds = 1})
end
observer:noteGuiAction({event = "activated", sequence = 90, instanceId = 9, elapsedSeconds = 1})
clock = 11.5
callback({argumentCount = 3, argumentTypes = {"string", "nil", "table"}, invokeKind = "Request", Arguments = {"SECRET"}}, remote, "Outgoing", origin)
assert(#events == 1 and events[1].argumentCount == 3 and events[1].Arguments == nil)
assert(events[1].argumentTypes[2] == "nil" and events[1].callerInstanceId == 2)
assert(events[1].scriptId == nil and events[1].invokeKind == "Request")
assert(#observer:relations() == 1 and observer:relations()[1].causal == false)
assert(observer:relations()[1].deltaSeconds == 0.5)
assert(observer:relations()[1].guiEventType == "activated" and observer:relations()[1].guiSequence == 90)
assert(observer:summary().droppedRelations == 0)
observer:noteGuiAction({event = "gui_state_transition", correlate = true, sequence = 99, toStateId = 8, elapsedSeconds = 1.5})
assert(#observer:relations() == 2 and observer:relations()[2].guiEventType == "gui_state_transition")
assert(observer:relations()[2].toStateId == 8 and observer:relations()[2].guiSequence == 99 and observer:relations()[2].causal == false)
-- Repeated unresolved calls for the same exact origin/remote pair cost one slot.
for _ = 1, 5000 do
    callback({argumentCount = 0, argumentTypes = {}}, remote, "Outgoing", origin)
end
assert(#observer.pending == 1 and observer:summary().droppedPendingCallers == 0)
late = true
local stats = observer:remoteStats()
assert(stats[1].outgoing == 5001 and stats[1].observedScriptLinks[1] == "s2")
assert(#observer.pending == 0 and next(observer.pendingByOrigin) == nil)
callback({argumentCount = 1, argumentTypes = {"SECRET"}, invokeKind = "SECRET"}, remote, "Incoming", nil)
assert(events[#events].argumentTypes[1] == "unknown" and events[#events].invokeKind == nil)
callback({}, {}, "Outgoing", nil)
assert(observer:summary().skipped == 1)
assert(observer:stop() == "detached" and observer:stop() == "detached" and cleanups == 1)
callback({}, remote, "Outgoing", nil)
assert(#events == 5002)
unavailable("late_unload")
assert(observer:summary().state == "detached", "late unload must not overwrite stopped status")
local unloaded = Runtime.new({}, context)
assert(unloaded:start() == "attached")
unavailable("cobalt_unloaded")
assert(unloaded:summary().state == "unloaded" and unloaded:stop() == "unloaded" and cleanups == 1)
env.LesbhubCobaltAdapter = {version = 1, subscribe = function() return function() error("unsubscribe failed") end end}
local badCleanup = Runtime.new({}, context)
assert(badCleanup:start() == "attached" and badCleanup:stop() == "cleanup_failed")
assert(badCleanup:stop() == "cleanup_failed")
local boundedCallback
local boundedEnv = {version = 1, subscribe = function(cb)
    boundedCallback = cb; return function() end
end}
env.LesbhubCobaltAdapter = boundedEnv
local boundedContext = {now = function() return 0 end, emit = function() return 1 end,
    resolve = function(obj)
        if obj == remote then return {instanceId = 1, className = "RemoteEvent"} end
        return {instanceId = 2}
    end}
local bounded = Runtime.new({}, boundedContext)
assert(bounded:start() == "attached")
local origins = {}
for i = 1, 512 do
    origins[i] = {}
    boundedCallback({}, remote, "Incoming", origins[i])
end
assert(#bounded.pending == 512 and bounded:summary().pendingOverflowOccurrences == 0)
boundedCallback({}, remote, "Incoming", origins[1])
assert(bounded:summary().pendingOverflowOccurrences == 0, "accepted pair must remain deduplicated at capacity")
local rejected = {}
boundedCallback({}, remote, "Incoming", rejected)
boundedCallback({}, remote, "Incoming", rejected)
assert(#bounded.pending == 512 and bounded:summary().pendingOverflowOccurrences == 2)
assert(bounded:summary().pendingOverflowCountMeaning == "occurrences_not_distinct_pairs")
bounded:stop()
local pausedCallback
env.LesbhubCobaltAdapter = {version=1, subscribe=function(cb) pausedCallback=cb; return function() end end}
local paused = Runtime.new({}, {now=function() return 0 end,
    resolve=function() return {instanceId=1,className="RemoteEvent"} end,
    emit=function() coroutine.yield("emitting"); return 7 end})
assert(paused:start() == "attached")
local active = coroutine.create(function() pausedCallback({}, remote, "Incoming", nil) end)
local resumed, stage = coroutine.resume(active)
assert(resumed and stage == "emitting" and paused:inFlight() == 1)
assert(paused:stop() == "detached" and paused:summary().observedCalls == 0)
assert(coroutine.resume(active) and paused:inFlight() == 0 and paused:summary().observedCalls == 1,
    "in-flight callback must finish its accounting after stop")
print("Runtime observer mock OK: state, lifecycle, types, late caller, temporal association")
