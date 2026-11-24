-- Controlled client-local fixture only. No existing game button or remote is fired.
local Engine = assert(getgenv().LesbhubDeepTestEngine, "load the candidate engine first")
local root = game:GetService("StarterGui")
local fixture = Instance.new("ScreenGui")
fixture.Name = "LesbhubDeepControlledFixture"
fixture.Parent = root
local function value(name, n)
    local obj = Instance.new("NumberValue"); obj.Name = name; obj.Value = n; obj.Parent = fixture
    return obj
end
local first, second = value("SameName", 1), value("SameName", 2)
local button = Instance.new("TextButton"); button.Name = "SyntheticButton"; button.Parent = fixture
local caller = Instance.new("LocalScript"); caller.Name = "SyntheticCaller"; caller.Parent = fixture
local remote = Instance.new("RemoteEvent"); remote.Name = "SyntheticRemote"; remote.Parent = fixture
local initialConnections = #getconnections(root.DescendantAdded)
local control = {}
local result, err = Engine.capture({label = "controlled-continuous", category = "private-tests",
    variant = "synthetic", targets = {StarterGui = true}, continuous = true,
    observeGuiActions = true, observeRemotes = true, includeReconstructedCode = false,
    chunkSize = 25, yieldEvery = 45}, function(info)
    if info.stage == "service_start" and info.pass == 1 then
        local short = value("ShortLived", 17)
        short:Destroy()
    elseif info.stage == "monitoring_start" then
        first.Name = "Renamed"; first.Value = 3
        second:Destroy()
        value("SameName", 4)
        firesignal(button.Activated)
        -- Exercise the bridge protocol with our own inert, client-only object.
        -- This is NOT a claim of real Cobalt traffic observation.
        getgenv().LesbhubExporterObserveRemote({Origin = caller, Arguments = {"SECRET_NOT_TO_EXPORT", n = 1}},
            remote, "Outgoing")
        control.stopRequested = true
    end
end, control)
local remainingConnections = #getconnections(root.DescendantAdded)
fixture:Destroy()
assert(result, err)
assert(result.manifest.status == "stopped")
assert(initialConnections == remainingConnections, "continuous listeners leaked")
assert(getgenv().LesbhubExporterObserveRemote == nil, "observation bridge leaked")
assert(result.manifest.diagnostics.guiActions == 1, "synthetic GUI activation missed")
assert(result.manifest.diagnostics.remoteObservations == 1, "bridge fixture missed")
getgenv().LesbhubDeepContinuousTest = result
print("DEEP_CONTINUOUS_DONE " .. game:GetService("HttpService"):JSONEncode({folder = result.folder,
    status = result.manifest.status, stats = result.manifest.stats, identity = result.manifest.identity,
    diagnostics = result.manifest.diagnostics, listenersBefore = initialConnections,
    listenersAfter = remainingConnections}))
