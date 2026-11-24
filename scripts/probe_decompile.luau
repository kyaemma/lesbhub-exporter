-- Development-only, passive proof. Run on one explicitly selected client.
-- Source stays in the executor workspace; never uploads or executes recovered code.
local Http = game:GetService("HttpService")
local player = game:GetService("Players").LocalPlayer
local root = player:FindFirstChild("PlayerScripts")
assert(root, "PlayerScripts unavailable")
assert(type(decompile) == "function", "decompile unavailable")
assert(type(readfile) == "function" and type(writefile) == "function", "file verification unavailable")
local function unique(parent, name)
    local found
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then assert(not found, "ambiguous candidate"); found = child end
    end
    assert(found, "candidate unavailable: " .. name)
    return found
end
local module = unique(root, "PlayerModule")
local candidates = {unique(root, "SoundClient"), module, unique(module, "ControlModule")}
local stamp = os.date("!%Y%m%dT%H%M%SZ") .. "-" .. math.floor(os.clock() * 1000)
local base = "LesbhubExporter/deep-proof/" .. stamp
for _, folder in ipairs({"LesbhubExporter", "LesbhubExporter/deep-proof", base}) do
    if not isfolder(folder) then makefolder(folder) end
end
local entries, started = {}, os.clock()
for i, scriptInstance in ipairs(candidates) do
    local path = scriptInstance:GetFullName()
    local idOk, debugId = pcall(function() return scriptInstance:GetDebugId() end)
    local entry = {scriptId = "s" .. i, className = scriptInstance.ClassName,
        robloxPath = path, debugId = idOk and debugId or "unavailable", method = "decompile",
        status = "failed", byteLength = 0, lineCount = 0, error = "", outputPath = ""}
    print("DEEP_PROOF_START " .. i .. " " .. scriptInstance.ClassName .. " " .. scriptInstance.Name)
    local at = os.clock()
    local ok, source = pcall(decompile, scriptInstance)
    entry.elapsedSeconds = os.clock() - at
    if not ok then entry.error = tostring(source)
    elseif type(source) ~= "string" or not source:find("%S") then entry.status = "empty"
    else
        entry.byteLength = #source
        entry.lineCount = select(2, source:gsub("\n", "")) + 1
        entry.checksum = crypt.hash(source, "sha256")
        entry.outputPath = string.format("%04d_%s.luau", i, scriptInstance.Name:gsub("[^%w_-]", "_"))
        local filename = base .. "/" .. entry.outputPath
        local header = "-- Reconstructed pseudocode, not original source. Never executed by this probe.\n"
            .. "-- Roblox path: " .. path:gsub("[\r\n]", " ") .. "\n-- Class: " .. entry.className
            .. "\n-- DebugId: " .. tostring(entry.debugId) .. "\n\n"
        local writeOk, writeErr = pcall(function()
            writefile(filename, header .. source)
            assert(isfile(filename), "file missing after write")
            assert(readfile(filename) == header .. source, "readback mismatch")
        end)
        if writeOk then
            local compiled, compileError = loadstring(source, "@deep-proof")
            entry.compiles = compiled ~= nil
            entry.compileError = compiled and "" or tostring(compileError)
            entry.status = compiled and "success" or "partial"
            entry.fileByteLength = #header + #source
            entry.verifiedReadback = true
        else entry.error = tostring(writeErr) end
    end
    entries[#entries + 1] = entry
    writefile(base .. "/index.json", Http:JSONEncode({scripts = entries}))
    print("DEEP_PROOF_RESULT " .. Http:JSONEncode(entry))
    task.wait()
end
print("DEEP_PROOF_DONE " .. Http:JSONEncode({folder = base, elapsedSeconds = os.clock() - started, count = #entries}))
