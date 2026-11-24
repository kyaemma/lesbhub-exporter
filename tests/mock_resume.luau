-- Synthetic in-memory executor; no Roblox server or third-party code.
local disk, directories, payloads, serial = {}, {}, {}, 0
local env = {}
function getgenv() return env end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local http = {}
function http:JSONEncode(value)
    serial = serial + 1
    local key = "json:" .. serial
    payloads[key] = copy(value)
    return key
end
function http:JSONDecode(value) return copy(assert(payloads[value], "invalid synthetic JSON")) end
local scriptInstance = {ClassName = "LocalScript"}
function scriptInstance:GetDebugId() return "debug-synthetic" end
function scriptInstance:GetChildren() return {} end
local visits = 0
local root = {ClassName = "ReplicatedStorage"}
function root:GetChildren() visits = visits + 1; return {scriptInstance} end
local players = {LocalPlayer = {}}
game = {PlaceId = 42, GameId = 11, GetService = function(_, name)
    if name == "HttpService" then return http end
    if name == "Players" then return players end
    if name == "ReplicatedStorage" then return root end
    error("unexpected service")
end}
workspace = {}
task = {wait = function() end}
function makefolder(path) directories[path] = true end
function isfolder(path) return directories[path] == true end
function isfile(path) return disk[path] ~= nil end
function readfile(path) return assert(disk[path], "missing file: " .. path) end
function writefile(path, content) disk[path] = content end
function appendfile(path, content) disk[path] = (disk[path] or "") .. content end
local attempts = 0
function decompile() attempts = attempts + 1; return "return 42\n" end
function loadstring() return function() end end

local Exporter = require("../src/engine")
local folder = "LesbhubExporter/test/resume"
local function json(path, value) disk[folder .. "/" .. path] = http:JSONEncode(value) end
local entry = {scriptId = "s1", instanceId = 1, name = "Fixture", className = "LocalScript",
    service = "ReplicatedStorage", robloxPath = "ReplicatedStorage/Fixture", guiPath = "",
    debugId = "debug-synthetic", method = "decompile", status = "empty", error = "empty",
    outputPath = "", byteLength = 0, lineCount = 0, checksum = "", attempted = true}
local counts = {discovered = 1, attempted = 1, succeeded = 0, failed = 0, inaccessible = 0,
    empty = 1, partial = 0, skipped = 0, pending = 0, files = 0, bytes = 0}
local manifest = {schemaVersion = 1, exporterVersion = "0.8.0", inspectionVersion = 1,
    game = {placeId = 42, gameId = 11}, clientOnly = true, status = "partial",
    partialReasons = {"script_extraction_incomplete"}, settings = {targets = {ReplicatedStorage = true}},
    stats = {written = 1, files = 1, bytes = 15}, services = {}, errors = {},
    scriptExport = {enabled = true, runtimeToken = env.LesbhubDeepRuntimeToken, stats = counts},
    relations = {status = "complete", counts = {relations = 1}},
    report = {version = 2, path = "report.json", markdownPath = "report.md"}}
json("manifest.json", manifest)
json("scripts/index.json", {version = 1, scripts = {entry}, stats = counts})
json("errors/index.json", {version = 1, metadata = {"original metadata error"}, scriptFailures = {}})
json("report.json", {reportVersion = 2, artifacts = {}, limitations = {"original limitation"}})
disk[folder .. "/relations/index.json"] = "frozen relationships"
disk[folder .. "/metadata.json"] = "frozen metadata"
local function artifact(path, kind)
    local content = readfile(folder .. "/" .. path)
    local a, b = 1, 0
    for i = 1, #content do a = (a + content:byte(i)) % 65521; b = (b + a) % 65521 end
    return {path = path, kind = kind, bytes = #content,
        checksumAlgorithm = "adler32", checksum = string.format("%08x", b * 65536 + a)}
end
json("artifacts/index.json", {version = 1, artifacts = {
    artifact("scripts/index.json", "sidecar"), artifact("errors/index.json", "sidecar"),
    artifact("relations/index.json", "sidecar"), artifact("metadata.json", "metadata")}})
local result, why = Exporter.resumeScripts(folder, nil, {})
assert(result, why)
assert(attempts == 1 and result.manifest.scriptExport.stats.succeeded == 1)
assert(result.manifest.relations.status == "partial" and result.manifest.status == "partial")
assert(table.find(result.manifest.partialReasons, "relations_stale_after_script_resume"))
assert(disk[folder .. "/metadata.json"] == "frozen metadata"
    and disk[folder .. "/relations/index.json"] == "frozen relationships")
local newIndex = http:JSONDecode(disk[folder .. "/scripts/index.json"])
assert(newIndex.scripts[1].analysis and newIndex.scripts[1].verifiedReadback)
local ledger = http:JSONDecode(disk[folder .. "/artifacts/index.json"])
local seen = {}
for _, item in ipairs(ledger.artifacts) do
    seen[item.path] = true
    assert(#readfile(folder .. "/" .. item.path) == item.bytes)
end
assert(seen["scripts/index.json"] and seen["scripts/progress.jsonl"]
    and seen[newIndex.scripts[1].outputPath] and seen["relations/index.json"])
local report = http:JSONDecode(disk[folder .. "/report.json"])
assert(report.reportVersion == 2 and report.status == result.manifest.status
    and report.layers.reconstructedScripts.counts.succeeded == 1)
local updatedErrors = http:JSONDecode(disk[folder .. "/errors/index.json"])
assert(updatedErrors.metadata[1] == "original metadata error" and #updatedErrors.scriptFailures == 0)
local firstVisits = visits
local second, secondError = Exporter.resumeScripts(folder, nil, {})
assert(second, secondError)
assert(attempts == 1 and visits == firstVisits, "verified resume should not scan Instances or decompile")
disk[folder .. "/" .. newIndex.scripts[1].outputPath] = "damaged source"
local repaired, repairError = Exporter.resumeScripts(folder, nil, {})
assert(repaired, repairError)
assert(attempts == 2 and repaired.manifest.validation.status == "partial"
    and table.find(repaired.manifest.partialReasons, "resume_prior_script_artifact_mismatch"),
    "corrupted reconstructed code must be retried and its earlier mismatch reported")
disk[folder .. "/metadata.json"] = "damaged metadata"
local rejectedDamage, damageError = Exporter.resumeScripts(folder, nil, {})
assert(not rejectedDamage and damageError:find("integrity mismatch", 1, true),
    "corrupt frozen metadata must not be silently rehashed")
disk[folder .. "/metadata.json"] = "frozen metadata"
ledger = http:JSONDecode(disk[folder .. "/artifacts/index.json"])
ledger.artifacts[1].path = "../outside"
json("artifacts/index.json", ledger)
local before = disk[folder .. "/scripts/index.json"]
local rejected, rejection = Exporter.resumeScripts(folder, nil, {})
assert(not rejected and rejection:find("unsafe path", 1, true)
    and disk[folder .. "/scripts/index.json"] == before, "unsafe ledger must fail before mutation")
local legacyFolder = "LesbhubExporter/test/legacy"
local legacyManifest = copy(manifest)
legacyManifest.inspectionVersion = nil
legacyManifest.exporterVersion = "0.7.0"
legacyManifest.report = nil
disk[legacyFolder .. "/manifest.json"] = http:JSONEncode(legacyManifest)
disk[legacyFolder .. "/scripts/index.json"] = http:JSONEncode({version = 1, scripts = {copy(entry)}, stats = counts})
local legacy, legacyError = Exporter.resumeScripts(legacyFolder, nil, {})
assert(legacy, legacyError)
assert(legacy.manifest.scriptExport.stats.succeeded == 1 and attempts == 3)
assert(not legacy.manifest.inspectionVersion, "legacy resume must retain its format")
print("Resume OK: ledger, report, stale relations and lazy identity scan")
