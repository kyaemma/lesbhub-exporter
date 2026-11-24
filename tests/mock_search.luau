local folder = "LesbhubExporter/test/session"
local header = "-- HIDDEN_HEADER needle\n"
local contents = {
    [folder .. "/scripts/sources/a.luau"] = header .. "Needle first\nother NEEDLE\nlast needle\n",
    [folder .. "/scripts/sources/b.luau"] = header .. "nothing\n",
    [folder .. "/scripts/sources/invalid.luau"] = header .. "needle",
    [folder .. "/scripts/sources/notstring.luau"] = {},
}
local index = {scripts = {
    {name = "First", outputPath = "scripts/sources/a.luau", scriptId = "s1", headerByteLength = #header},
    {name = "Second", outputPath = "scripts/sources/b.luau", scriptId = "s2", headerByteLength = #header},
    {name = "Invalid", outputPath = "scripts/sources/invalid.luau", headerByteLength = -1},
    {name = "Absent", outputPath = "scripts/sources/invalid.luau"},
    {name = "Fraction", outputPath = "scripts/sources/invalid.luau", headerByteLength = 1.5},
    {name = "Oversized", outputPath = "scripts/sources/invalid.luau", headerByteLength = 10000},
    {name = "NotString", outputPath = "scripts/sources/notstring.luau", headerByteLength = 0},
    {name = "Traversal", outputPath = "scripts/sources/../../outside.luau", headerByteLength = 0},
    {name = "Absolute", outputPath = "/scripts/sources/a.luau", headerByteLength = 0},
    9,
}}
local decoded = {
    [folder .. "/scripts/index.json"] = index,
    [folder .. "/remotes/index.json"] = {remotes = {{name = "NeedleRemote"}}},
    [folder .. "/gui/index.json"] = {elements = {{name = "NEEDLEGui"}}},
}
local reads = {}
function readfile(path)
    reads[path] = (reads[path] or 0) + 1
    if decoded[path] then return path end
    if contents[path] ~= nil then return contents[path] end
    error("unexpected path " .. path)
end
local http = {JSONDecode = function(_, text) return decoded[text] end}
game = {GetService = function(_, name)
    if name == "HttpService" then return http end
    if name == "Players" then return {} end
    error(name)
end}
task = {wait = function() end}
local Exporter = require("../src/engine")
local page, status = Exporter.search(folder, "nEeDlE", {mode = "sources", limit = 1, offset = 0})
assert(#page == 1 and page[1].line == 1 and page[1].preview == "Needle first\n")
assert(status:find("3 matches", 1, true), status)
assert(status:find("5 unreadable or invalid source files skipped", 1, true), status)
page, status = Exporter.search(folder, "NEEDLE", {mode = "sources", limit = 1, offset = 1})
assert(#page == 1 and page[1].line == 2 and page[1].preview == "NEEDLE\n")
assert(status:find("3 matches", 1, true), status)
page, status = Exporter.search(folder, "needle", {mode = "sources", limit = 10, offset = 2})
assert(#page == 1 and page[1].line == 3 and status:find("3 matches", 1, true))
page, status = Exporter.search(folder, "HIDDEN_HEADER", {mode = "sources"})
assert(#page == 0 and status:find("0 matches", 1, true))
page = Exporter.search(folder, "needle.", {mode = "sources"})
assert(#page == 0, "query must be literal, not a pattern")
assert(not reads[folder .. "/scripts/sources/../../outside.luau"])
assert(Exporter.search("LesbhubExporter/../outside", "x") == nil)
assert(Exporter.search("LesbhubExporter/test\\outside", "x") == nil)
page, status = Exporter.search(folder, "needle", {limit = 1})
assert(#page == 1 and status:find("2 matches", 1, true), status)
print("Search mock OK: exact totals, pagination, literal queries, header and traversal safety")
