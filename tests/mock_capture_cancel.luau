-- In-memory client-only integration test. The only reconstructed source is synthetic.
local disk, directories, payloads, serial = {}, {}, {}, 0
local env, control = {}, {}
function getgenv() return env end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local http = {}
function http:JSONEncode(value)
    serial += 1
    local key = "json:" .. serial
    payloads[key] = copy(value)
    return key
end
function http:JSONDecode(value) return copy(assert(payloads[value], "bad synthetic JSON")) end
local root = {Name = "ReplicatedStorage", ClassName = "ReplicatedStorage"}
local scriptInstance = {Name = "SyntheticLong", ClassName = "LocalScript", Parent = root, Archivable = true}
function scriptInstance:GetChildren() return {} end
function scriptInstance:GetAttributes() return {} end
function scriptInstance:GetTags() return {} end
function scriptInstance:GetDebugId() return "synthetic-id" end
function scriptInstance:IsA(class) return self.ClassName == class end
function root:GetChildren() return {scriptInstance} end
function root:GetAttributes() return {} end
function root:GetTags() return {} end
function root:IsA(class) return self.ClassName == class end
local players = {LocalPlayer = {}}
function players:GetPlayers() return {} end
game = {PlaceId = 42, GameId = 11, GetService = function(_, name)
    if name == "HttpService" then return http end
    if name == "Players" then return players end
    if name == "ReplicatedStorage" then return root end
    error("unexpected service " .. name)
end}
root.Parent = game
workspace = {}
task = {wait = function() end}
function makefolder(path) directories[path] = true end
function isfolder(path) return directories[path] == true end
function isfile(path) return disk[path] ~= nil end
function readfile(path) return assert(disk[path], "missing file: " .. path) end
function writefile(path, content) disk[path] = content end
local partialPath, partialAppends
function appendfile(path, content)
    disk[path] = (disk[path] or "") .. content
    if path:match("%.luau$") then
        partialPath, partialAppends = path, (partialAppends or 0) + 1
        control.cancelled = true
    end
end
local source = string.rep("-- synthetic test line only\n", 5000) .. "return 42\n"
function decompile() return source end
function loadstring() return function() end end
local Exporter = require("../src/engine")
local result, why = Exporter.capture({label = "cancel", category = "tests", variant = "fixture",
    targets = {ReplicatedStorage = true}, runtimeWindowSeconds = 0, publicGameMetadata = false,
    observeRemotes = false, includeReconstructedCode = true, chunkSize = 25, yieldEvery = 100}, nil, control)
assert(result, why)
assert(partialPath and partialAppends == 1, "must cancel during an actual appendfile chunk")
assert(result.manifest.status == "cancelled" and result.manifest.endedReason == "cancelled")
assert(result.manifest.scriptExport.stats.succeeded == 0, "interrupted script was falsely successful")
local index = http:JSONDecode(readfile(result.folder .. "/scripts/index.json"))
local entry = assert(index.scripts[1])
assert(entry.status ~= "success" and entry.verifiedReadback ~= true and entry.error == "cancelled")
assert(partialPath == result.folder .. "/" .. entry.outputPath)
assert(#readfile(partialPath) > entry.headerByteLength and #readfile(partialPath) < entry.fileByteLength)
local ledger = http:JSONDecode(readfile(result.folder .. "/artifacts/index.json"))
local found
for _, item in ipairs(ledger.artifacts) do
    if item.path == entry.outputPath then found = item end
end
assert(found and found.kind == "incomplete_script", "partial source missing or mislabeled in artifact ledger")
local actual = readfile(partialPath)
assert(found.bytes == #actual, "ledger must describe actual partial bytes")
local a, b = 1, 0
for i = 1, #actual do a = (a + actual:byte(i)) % 65521; b = (b + a) % 65521 end
assert(found.checksumAlgorithm == "adler32" and found.checksum == string.format("%08x", b * 65536 + a),
    "ledger checksum must describe actual partial bytes")
local report = http:JSONDecode(readfile(result.folder .. "/report.json"))
assert(report.status == "cancelled" and report.endedReason == "cancelled")
print("Capture cancellation OK: interrupted append, cancelled report and incomplete ledger artifact")
