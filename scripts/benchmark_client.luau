-- Development helper. Load the desired bundled engine first. Metrics stay local.
-- Repeat with each engine/config in the same client; live game changes are confounders.
local env=(type(getgenv)=="function"and getgenv())or _G
local engine=assert(env.LesbhubBenchmarkEngine or env.LesbhubExporterEngine,"load engine first")
local options=env.LesbhubBenchmarkOptions or {label="benchmark",category="private-tests",
    variant="comparable",yieldEvery=140,chunkSize=300,twoPassGui=false}
local frames,preFrames,active={},0,false
local started=os.clock()
local connection=game:GetService("RunService").RenderStepped:Connect(function(dt)
    if active then frames[#frames+1]=dt else preFrames=preFrames+1 end
end)
task.wait(2)
local baseline=preFrames/(os.clock()-started)
local heap=gcinfo()
active=true;started=os.clock()
local ok,result,err=pcall(engine.capture,options,nil,{})
active=false;connection:Disconnect()
assert(ok,result);assert(result,err)
table.sort(frames)
local sum=0;for _,dt in ipairs(frames)do sum=sum+dt end
local function percentile(p)return frames[math.max(1,math.ceil(#frames*p))]end
local metrics={folder=result.folder,elapsedSeconds=os.clock()-started,
    baselineFps=baseline,averageFps=#frames/math.max(sum,.000001),
    frameP50=percentile(.5),frameP95=percentile(.95),frameP99=percentile(.99),
    maxFrameSeconds=frames[#frames],luaHeapBeforeKiB=heap,luaHeapAfterKiB=gcinfo(),
    caveat="Live game state, GC and other client tools can change between runs."}
-- Outside the capture: no unindexed file is added to its integrity ledger.
local metricsPath=result.folder.."-performance.json"
writefile(metricsPath,game:GetService("HttpService"):JSONEncode(metrics))
print("LESBHUB_BENCHMARK "..game:GetService("HttpService"):JSONEncode(metrics))
