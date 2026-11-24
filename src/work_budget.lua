-- Cooperative work budget; executor and native calls cannot be preempted.
local Budget = {}

function Budget.new(cfg, control)
    cfg = type(cfg) == "table" and cfg or {}
    control = type(control) == "table" and control or {}
    local ms = tonumber(cfg.frameBudgetMs) or 4
    if ms ~= ms then ms = 4 end
    ms = math.max(0.25, math.min(ms, 50))
    local cadence = tonumber(cfg.yieldEvery) or 60
    if cadence ~= cadence then cadence = 60 end
    cadence = math.max(1, math.floor(cadence))
    local started, steps = os.clock(), 0
    local metrics = {yields = 0, maxSliceMs = 0, nativeOverruns = 0,
        maxNativeMs = 0, nativeByStage = {}}
    local self = {}
    function self:checkpoint(stage, force)
        local elapsed = (os.clock() - started) * 1000
        metrics.maxSliceMs = math.max(metrics.maxSliceMs, elapsed)
        steps = steps + 1
        if control.cancelled then return false end
        if force or elapsed >= ms or steps >= cadence then
            metrics.yields = metrics.yields + 1
            task.wait()
            started, steps = os.clock(), 0
        end
        return not control.cancelled
    end
    function self:native(stage, seconds)
        local elapsed = math.max(0, (tonumber(seconds) or 0) * 1000)
        metrics.maxNativeMs = math.max(metrics.maxNativeMs, elapsed)
        if elapsed > ms then metrics.nativeOverruns = metrics.nativeOverruns + 1 end
        local item = metrics.nativeByStage[stage] or {calls = 0, totalMs = 0, maxMs = 0, overruns = 0}
        item.calls = item.calls + 1
        item.totalMs = item.totalMs + elapsed
        item.maxMs = math.max(item.maxMs, elapsed)
        if elapsed > ms then item.overruns = item.overruns + 1 end
        metrics.nativeByStage[stage] = item
    end
    function self:wait(seconds)
        -- Deliberate observation/menu waits are not CPU work slices.
        metrics.maxSliceMs = math.max(metrics.maxSliceMs, (os.clock() - started) * 1000)
        task.wait(seconds)
        started, steps = os.clock(), 0
        return not control.cancelled
    end
    function self:summary()
        local stages = {}
        for name, item in pairs(metrics.nativeByStage) do
            stages[name] = {calls = item.calls, totalMs = item.totalMs, maxMs = item.maxMs, overruns = item.overruns}
        end
        return {frameBudgetMs = ms, yields = metrics.yields,
            maxSliceMs = math.max(metrics.maxSliceMs, (os.clock() - started) * 1000),
            nativeOverruns = metrics.nativeOverruns, maxNativeMs = metrics.maxNativeMs, nativeByStage = stages}
    end
    return self
end
return Budget
