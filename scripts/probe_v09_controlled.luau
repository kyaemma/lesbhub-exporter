-- Controlled Roblox client fixture; no MCP or third-party GUI interaction.
-- Set getgenv().LesbhubV09TestEngine and LesbhubV09TestOptions before running.
local env = getgenv()
local engine = assert(env.LesbhubV09TestEngine, "LesbhubV09TestEngine is required")
local options = env.LesbhubV09TestOptions or {}
local label = tostring(options.label or "controlled")
local seconds = math.max(1, tonumber(options.seconds) or 120)
local interval = math.max(1, tonumber(options.interval) or 4)
local count = math.max(1, math.floor(tonumber(options.guiElements) or 5000))
local active = options.active == true
local starterGui = game:GetService("StarterGui")
local runService = game:GetService("RunService")
local http = game:GetService("HttpService")
local control = {stopRequested=false, cancelled=false}
local result = {label=label, active=active, secondsRequested=seconds, guiElements=count,
    interval=interval, module={requested=options.skipModules ~= true}, samples={}, stages={},
    synthetic={buttonFires=0, transientCreated=0, transientRemoved=0}, limitations={}}
env.LesbhubV09ControlledResult = result
local screen, heartbeat, ownButtonConnection
local running, monitoring = true, false
local frameCount, frameSeconds, worstFrame = 0, 0, 0

local function heap()
    local ok, value = pcall(function() return collectgarbage("count") end)
    if ok and type(value)=="number" then return value end
    if type(gcinfo)=="function" then local yes, n=pcall(gcinfo); if yes then return n end end
    return nil
end
local function sample(kind)
    result.samples[#result.samples+1] = {kind=kind, elapsed=monitoring and os.clock()-result.monitorStarted or 0,
        fps=frameSeconds>0 and frameCount/frameSeconds or nil, frames=frameCount,
        worstFrameMs=worstFrame*1000, luaHeapKiB=heap()}
    frameCount, frameSeconds, worstFrame = 0, 0, 0
end
local function connectionCount(signal)
    if type(getconnections) ~= "function" then return nil end
    local ok, connections = pcall(getconnections, signal)
    if not ok or type(connections) ~= "table" then return nil end
    return #connections
end
local function listeners(panel, button, status)
    return {screenChanged=connectionCount(screen.Changed), screenAncestry=connectionCount(screen.AncestryChanged),
        screenAdded=connectionCount(screen.DescendantAdded), screenRemoving=connectionCount(screen.DescendantRemoving),
        panelChanged=connectionCount(panel.Changed), panelVisible=connectionCount(panel:GetPropertyChangedSignal("Visible")),
        statusChanged=connectionCount(status.Changed), statusText=connectionCount(status:GetPropertyChangedSignal("Text")),
        buttonActivated=connectionCount(button.Activated)}
end
local function makeFixture()
    screen = Instance.new("ScreenGui")
    screen.Name="LesbhubV09Controlled"; screen.Enabled=false; screen.ResetOnSpawn=false
    local panel=Instance.new("Frame"); panel.Name="Panel"; panel.Visible=true; panel.Parent=screen
    local status=Instance.new("TextLabel"); status.Name="StatusText"; status.Text="A"; status.Parent=panel
    local button=Instance.new("TextButton"); button.Name="OwnButton"; button.Text="Synthetic"; button.Parent=panel
    ownButtonConnection=button.Activated:Connect(function() result.synthetic.buttonCallbacks=(result.synthetic.buttonCallbacks or 0)+1 end)
    for i=1,count do
        local text=Instance.new("TextLabel")
        text.Name=string.format("Item%05d", i); text.Text=string.format("Fixture %05d", i); text.Parent=panel
        if i%250==0 then task.wait() end
    end
    if options.skipModules ~= true then
        local storage=game:GetService("ReplicatedStorage")
        local original
        for _, item in ipairs(storage:GetDescendants()) do
            if item:IsA("ModuleScript") then original=item; break end
        end
        if original then
            local ok, clone=pcall(function() return original:Clone() end)
            if ok and clone then
                -- The clone is inert and never required. Remove cloned children, which could be runnable scripts.
                for _, child in ipairs(clone:GetChildren()) do child:Destroy() end
                clone.Name="OwnSourceModule"; clone.Parent=screen
                result.module.cloned=true
            else result.module.cloned=false; result.module.reason="first ModuleScript could not be cloned" end
        else result.module.cloned=false; result.module.reason="no ModuleScript found" end
    end
    screen.Parent=starterGui
    return panel, status, button
end
local function run()
    local panel,status,button=makeFixture()
    heartbeat=runService.Heartbeat:Connect(function(dt)
        frameCount+=1; frameSeconds+=dt; if dt>worstFrame then worstFrame=dt end
    end)
    task.wait(1)
    sample("baseline")
    result.listenersBefore=listeners(panel,button,status)
    local cfg={label=label,category="Controlled",variant="Fixture",targets=options.targets or {StarterGui=true},
        continuous=true,continuousInterval=tonumber(options.continuousInterval) or 1,
        twoPassGui=options.twoPassGui==true,runtimeWindowSeconds=tonumber(options.runtimeWindowSeconds) or 0,
        guiPasses=options.guiPasses,secondPassDelay=options.secondPassDelay,
        yieldEvery=140,chunkSize=300,observeRemotes=options.observeRemotes==true,includeReconstructedCode=true}
    result.config=cfg
    local capture, err=engine.capture(cfg,function(info)
        if type(info)~="table" then return end
        if type(options.stageCallback)=="function" then pcall(options.stageCallback,info) end
        if info.stage=="monitoring_start" and not monitoring then
            monitoring=true; result.monitorStarted=os.clock(); result.stages.monitoringStart=true
            frameCount,frameSeconds,worstFrame=0,0,0
            task.spawn(function()
                local nextStep=result.monitorStarted+interval
                local nextSample=result.monitorStarted+30
                local step=0
                while running and not control.stopRequested and not control.cancelled do
                    local now=os.clock()
                    if now-result.monitorStarted>=seconds then control.stopRequested=true; break end
                    if now>=nextSample then sample("monitoring"); nextSample+=30 end
                    if active and now>=nextStep then
                        step+=1; local phase=step%10
                        status.Text=phase==0 and "A" or ("State "..phase)
                        panel.Visible=phase%2==0
                        result.synthetic.lastStep=step
                        if step==1 then
                            local transient=Instance.new("TextLabel")
                            transient.Name="Transient"; transient.Text="Observed briefly"; transient.Parent=panel
                            result.synthetic.transientCreated+=1
                            task.delay(0.15,function()
                                if transient.Parent then transient:Destroy(); result.synthetic.transientRemoved+=1 end
                            end)
                        end
                        if options.fireButton==true and type(firesignal)=="function" then
                            local ok=pcall(firesignal,button.Activated)
                            if ok then result.synthetic.buttonFires+=1 end
                        end
                        nextStep+=interval
                    end
                    task.wait(0.05)
                end
            end)
        end
    end,control)
    running=false
    if monitoring then sample("final"); result.monitorElapsed=os.clock()-result.monitorStarted end
    result.listenersAfter=listeners(panel,button,status)
    result.capture=capture; result.error=err
    if capture then
        result.folder=capture.folder
        local manifest=capture.manifest or {}
        result.status=manifest.status; result.stats=manifest.stats; result.guiAnalysis=manifest.guiAnalysis
        result.scriptExport=manifest.scriptExport; result.diagnostics=manifest.diagnostics
    end
end
local ok, err=xpcall(run,debug.traceback)
running=false; control.stopRequested=true
if heartbeat then heartbeat:Disconnect() end
if ownButtonConnection then ownButtonConnection:Disconnect() end
if screen then screen:Destroy() end
result.fixtureDestroyed=screen==nil or screen.Parent==nil
if not ok then result.error=tostring(err) end
if type(getconnections)~="function" then result.limitations[#result.limitations+1]="getconnections unavailable; listener counts unavailable" end
-- Keep metrics outside the capture directory so they cannot affect the dataset ledger.
if type(writefile)=="function" and type(makefolder)=="function" then
    local folder="LesbhubV09ControlledMetrics"
    pcall(makefolder,folder)
    local safe=label:gsub("[^%w_%-]","_"):sub(1,80)
    local encodedOk,body=pcall(function() return http:JSONEncode(result) end)
    if encodedOk then pcall(writefile,folder.."/"..safe..".json",body) end
end
print("Lesbhub controlled",label,"folder",tostring(result.folder),"status",tostring(result.status),
    "monitorSeconds",tostring(result.monitorElapsed),"error",tostring(result.error))
