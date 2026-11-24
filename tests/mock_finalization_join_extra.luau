-- Appended to mock_capture by build_mock_finalization_join.py.
local originalWrite, originalWait, originalTypeof, originalGetgenv, originalDate = writefile, task.wait, typeof, getgenv, os.date
local mockEnv, callback = {}, nil
getgenv = function() return mockEnv end
mockEnv.LesbhubCobaltAdapter = {version = 1, subscribe = function(cb)
    callback = cb
    return function() end
end}
local remote = instance("JoinRemote", "RemoteEvent")
remote.Parent = gui
local pauseDate = false
function remote:IsDescendantOf(root)
    assert(root == gui)
    return true
end
typeof = function(value) if value == remote then return "Instance" end; return originalTypeof(value) end
local button = instance("JoinButton", "TextButton", {Text = "Test"})
button.Parent = gui; button.Activated = eventSignal(); gui._children = {button, remote}
local joinedRemote, joinedGui, resumedGui
os.date = function(...)
    if pauseDate then
        pauseDate = false
        coroutine.yield("gui_callback")
    end
    return originalDate(...)
end
simulatedTime = 100
task.wait = function(seconds)
    simulatedTime += math.max(seconds or 0, 0.01)
    if joinedGui and coroutine.status(joinedGui) == "suspended" then
        resumedGui = true; assert(coroutine.resume(joinedGui)); return
    end
end
local control = {}
local result, why = Exporter.capture({label="ConcurrentFinalize", targets={PlayerGui=true},
    continuous=true, observeRemotes=true}, function(info)
    if info.stage ~= "monitoring_start" then return end
    joinedRemote = coroutine.create(function() callback({}, remote, "Incoming", nil) end)
    local ok1 = coroutine.resume(joinedRemote)
    assert(ok1 and coroutine.status(joinedRemote) == "dead", "raw admission must return synchronously")
    for _ = 1, 255 do button.Activated:Fire() end
    joinedGui = coroutine.create(function() pauseDate = true; button.Activated:Fire() end)
    local ok2, step2 = coroutine.resume(joinedGui)
    assert(ok2 and step2 == "gui_callback")
    control.stopRequested = true
end, control)
writefile, task.wait, typeof, getgenv, os.date = originalWrite, originalWait, originalTypeof, originalGetgenv, originalDate
simulatedTime = nil; gui._children = savedChildren
assert(result, why)
assert(resumedGui and coroutine.status(joinedRemote) == "dead" and coroutine.status(joinedGui) == "dead",
    "finalization failed to join the admitted GUI callback")
assert(result.manifest.diagnostics.guiActions == 256 and result.manifest.runtime.observer.observedCalls == 1,
    "callback completion occurred after final statistics were frozen")
assert(result.manifest.journal.streams["gui-actions"].events == 256
    and result.manifest.journal.streams["remote-observations"].events == 1,
    "in-flight observations missing from final journal")
print("Finalization join OK: raw remote and suspended GUI callback complete before final snapshot")

local stalledButton = instance("StalledButton", "TextButton", {Text="Test"})
stalledButton.Parent = gui; stalledButton.Activated = eventSignal(); gui._children = {stalledButton}
local stalled, pauseStalled, failControl = nil, false, {}
simulatedTime = 100
task.wait = function(seconds) simulatedTime += math.max(seconds or 0, 0.01) end
os.date = function(...)
    if pauseStalled then
        pauseStalled = false; coroutine.yield("stalled_callback")
    end
    return originalDate(...)
end
local timeoutResult, timeoutError = Exporter.capture({label="FinalizeTimeout", targets={PlayerGui=true},
    continuous=true, observeRemotes=false}, function(info)
    if info.stage ~= "monitoring_start" then return end
    for _ = 1, 255 do stalledButton.Activated:Fire() end
    stalled = coroutine.create(function() pauseStalled = true; stalledButton.Activated:Fire() end)
    local ok, step = coroutine.resume(stalled)
    assert(ok and step == "stalled_callback")
    failControl.stopRequested = true
end, failControl)
assert(not timeoutResult and timeoutError:find("timed out", 1, true), "stalled writer did not fail finalization")
for path in pairs(rawWrites) do
    assert(not (path:find("finalizetimeout", 1, true) and path:match("/report%.json$")),
        "a final report was published while a writer remained active")
end
writefile, task.wait, os.date = originalWrite, originalWait, originalDate
assert(coroutine.resume(stalled))
simulatedTime = nil; gui._children = savedChildren
print("Finalization timeout OK: no final report while writer remains active")
