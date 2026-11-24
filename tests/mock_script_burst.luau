local disk, dirs, overflow, attempts = {}, {}, 0, 0
local http = {JSONEncode = function() return "{}" end}
game = {GetService = function(_, name) assert(name == "HttpService"); return http end}
function makefolder(path) dirs[path] = true end
function isfolder(path) return dirs[path] == true end
function isfile(path) return disk[path] ~= nil end
function readfile(path) return assert(disk[path]) end
function writefile(path, data) disk[path] = data end
function appendfile(path, data) disk[path] = (disk[path] or "") .. data end
function decompile() attempts += 1; return "" end
task = {wait = function() end}
local Deep = require("../src/deep_scripts")
local writer = Deep.new("LesbhubExporter/mock/burst", true, {}, nil,
    {queueLimit=2, onOverflow=function() overflow += 1 end})
for i = 1, 3 do
    local obj = {GetDebugId=function() return tostring(i) end}
    writer:discover(obj, {instanceId=i, className="ModuleScript", name="M" .. i,
        path="Root/M" .. i, parentPath="Root"}, "Root")
end
assert(#writer.queue == 2 and overflow == 1 and writer.entries[3].status == "inaccessible")
writer:drain()
assert(attempts == 2 and #writer.queue == 0)
print("Asynchronous script burst OK: bounded queue and explicit overflow")
