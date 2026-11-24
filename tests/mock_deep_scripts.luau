-- Synthetic code only. No third-party game sources belong in this repository.
local disk, dirs, payloads = {}, {}, {}
local encodes, decompiles, appends = 0, 0, 0
local failWrite, failIndex, corruptRead, onWait = false, false, false, nil
local http = {}
function http:JSONEncode(value)
    encodes = encodes + 1
    local key = "json:" .. encodes
    payloads[key] = value
    return key
end
game = {GetService = function(_, name) assert(name == "HttpService"); return http end}
function makefolder(path) dirs[path] = true end
function isfolder(path) return dirs[path] == true end
function isfile(path) return disk[path] ~= nil end
function writefile(path, value)
    if failWrite and path:match("%.luau$") then error("simulated disk failure") end
    if failIndex and path:match("scripts/index%.json$") then error("simulated index failure") end
    assert(not path:find("..", 1, true), "write escaped output root")
    disk[path] = value
end
function appendfile(path, value) appends = appends + 1; disk[path] = (disk[path] or "") .. value end
function readfile(path) return corruptRead and "corrupted" or assert(disk[path], "file missing") end
function decompile(instance)
    decompiles = decompiles + 1
    if instance.failure then error(instance.failure) end
    return instance.code
end
function loadstring(source)
    if source:find("BROKEN", 1, true) then return nil, "synthetic syntax failure" end
    return function() error("reconstructed code must never be executed") end
end
task = {wait = function() if onWait then onWait() end end}
local Deep = require("../src/deep_scripts")
local hash, algorithm = Deep.checksum("abc")
assert(hash == "024d0127" and algorithm == "adler32")
local serial = 0
local function capture(codes, control)
    serial = serial + 1
    local base = "LesbhubExporter/mock/run" .. serial
    local writer = Deep.new(base, true, control or {})
    local instances = {}
    for id, code in ipairs(codes) do
        local obj = {code = code, failure = code == "ERROR" and "simulated decompiler failure" or nil}
        function obj:GetDebugId() return "debug:" .. id end
        instances[id] = obj
        writer:discover(obj, {instanceId = id, className = "ModuleScript", name = "CON:<same>/../name",
            path = "ReplicatedStorage/Folder/Same", parentPath = "ReplicatedStorage/Folder"}, "ReplicatedStorage")
    end
    writer:drain()
    return writer, base, instances
end
local long = string.rep("-- synthetic unbounded line with UTF-8: é\r\n", 3001) .. "return 42\n"
local good, base, objects = capture({"return 1", long, "return 3"})
assert(good:summary().stats.succeeded == 3)
assert(appends >= 4, "long output was not progressively written")
local entry = good.entries[2]
assert(entry.lineCount == 3003 and entry.byteLength == #long)
assert(readfile(base .. "/" .. entry.outputPath):sub(entry.headerByteLength + 1) == long,
    "code was modified or truncated")
assert(good.entries[1].outputPath ~= good.entries[3].outputPath, "same-name files collide")
assert(not entry.outputPath:find("[<>:]"))
local attempts = decompiles
good:resume(good.entries, function(e) return objects[e.instanceId] end)
assert(decompiles == attempts and good:summary().stats.skipped == 3, "resume re-decompiled verified files")
local errors = capture({"ERROR", "", "-- comment only", "BROKEN", "-- Lines 1-2000 of 7000\nreturn 1"})
assert(errors.entries[1].status == "failed")
assert(errors.entries[2].status == "empty" and errors.entries[3].status == "empty")
assert(errors.entries[2].diagnosticByteLength == 0 and not errors.entries[2].diagnosticPath)
assert(errors.entries[3].diagnosticByteLength == #"-- comment only")
assert(errors.entries[4].status == "partial" and errors.entries[4].verifiedReadback)
assert(errors.entries[5].status == "partial" and errors.entries[5].truncationDetected)
local commentOnly = capture({"--[[decompilation unavailable\nno code\n]]", "--[=[only a comment]=]"})
assert(commentOnly.entries[1].status == "empty" and commentOnly.entries[2].status == "empty",
    "comment-only failure was saved as successful code")
local diagnostic = commentOnly.entries[1]
assert(diagnostic.diagnosticPath and diagnostic.diagnosticChecksumAlgorithm == "adler32")
assert(readfile("LesbhubExporter/mock/run3/" .. diagnostic.diagnosticPath)
    == "--[[decompilation unavailable\nno code\n]]", "diagnostic bytes changed")
local originalDecompile = decompile
decompile = nil
local unsupported = capture({"return 1"})
assert(unsupported.entries[1].status == "inaccessible" and not unsupported.entries[1].attempted)
decompile = originalDecompile
local cancelled = capture({"return 1"}, {cancelled = true})
assert(cancelled:summary().stats.succeeded == 0 and not cancelled.entries[1].attempted)
failWrite = true
local failedDisk = capture({"return 1"})
assert(failedDisk.entries[1].status == "failed" and not failedDisk.entries[1].verifiedReadback)
failWrite = false
corruptRead = true
local badReadback = capture({"return 1"})
assert(badReadback.entries[1].status == "failed", "corrupt output reported as success")
corruptRead = false
local control = {}
local beforeAppends = appends
onWait = function() if appends > beforeAppends then control.cancelled = true end end
local interrupted = capture({long}, control)
assert(interrupted.entries[1].status == "inaccessible" and not interrupted.entries[1].verifiedReadback)
onWait = nil
local beforeEmpty = encodes
good:drain()
assert(encodes == beforeEmpty, "empty drain rewrote the index")
crypt = {hash = function() return string.rep("a", 64) end}
local previousAttempts = decompiles
good:resume(good.entries, function(e) return objects[e.instanceId] end)
assert(decompiles == previousAttempts, "resume must use each stored checksum algorithm")
crypt = nil
local batchControl = {}
local batchAttempts = decompiles
onWait = function() batchControl.cancelled = true end
local batch = capture({"return 1", "return 2", "return 3"}, batchControl)
onWait = nil
assert(decompiles == batchAttempts + 1 and batch.entries[2].status == "inaccessible"
    and batch.entries[3].status == "inaccessible", "cancel should skip all remaining jobs")
assert(batch.seen.s1 and batch.byId.s1 == batch.entries[1], "identity index missing")
local journalBase = "LesbhubExporter/mock/journal"
disk[journalBase .. "/scripts/progress.jsonl"] = "old checkpoint\n"
local analysisSeen
local journal = Deep.new(journalBase, true, {}, nil, {analyze = function(source)
    analysisSeen = source
    return {synthetic = true}
end})
local sourceObject = {code = "return 123", GetDebugId = function() return "synthetic" end}
journal:discover(sourceObject, {instanceId = 1, name = "x", className = "ModuleScript",
    path = "Root/x", parentPath = "Root"}, "Root")
failIndex = true
journal:drain()
failIndex = false
assert(disk[journalBase .. "/scripts/progress.jsonl"]:sub(1, 15) == "old checkpoint\n",
    "failed index snapshot must preserve the prior journal")
assert(analysisSeen == sourceObject.code and journal.entries[1].analysis.synthetic,
    "analysis must receive the exact returned code")
assert(not pcall(Deep.new, "LesbhubExporter/../outside", true, {}))
local unsafe = {{scriptId = "../../outside", outputPath = "", name = "x", className = "ModuleScript"}}
assert(not pcall(function() good:resume(unsafe, function() return objects[1] end) end))
print("Deep script writer OK: real files, long code, errors, collisions, resume, cancellation, no traversal")
