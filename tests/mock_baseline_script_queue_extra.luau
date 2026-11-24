-- Appended to mock_capture by build_mock_baseline_script_queue.py.
local savedStorageChildren, savedWait, savedDecompile = storage._children, task.wait, decompile
local scripts, attempts = {}, 0
for i = 1, 9000 do
    scripts[i] = instance("Module" .. i, "ModuleScript")
    scripts[i].Parent = storage
end
storage._children = scripts
decompile = function() attempts += 1; return "" end
simulatedTime = 100
task.wait = function(seconds) simulatedTime += math.max(seconds or 0, 0.01) end
local captured, why = captureEngine({label="LargeScriptBaseline", targets={ReplicatedStorage=true},
    runtimeWindowSeconds=0, publicGameMetadata=false, includeReconstructedCode=true}, nil, {})
storage._children, task.wait, decompile = savedStorageChildren, savedWait, savedDecompile
simulatedTime = nil
assert(captured, why)
local counts = captured.manifest.scriptExport.stats
print("Large baseline result", "discovered=" .. counts.discovered, "attempts=" .. attempts,
    "inaccessible=" .. counts.inaccessible, "pending=" .. counts.pending)
assert(counts.discovered == 9000 and attempts == 9000 and counts.inaccessible == 0 and counts.pending == 0,
    "ordinary baseline hit the bounded asynchronous script queue")
print("Large baseline script queue OK: all 9000 scripts attempted")
