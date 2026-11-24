-- Optional reconstructed-code writer. Never requires or executes captured modules.
local Deep = {}
local Http = game:GetService("HttpService")
local runtime = (type(getgenv) == "function" and getgenv()) or {}
runtime.LesbhubDeepRuntimeToken = runtime.LesbhubDeepRuntimeToken or tostring(os.clock()) .. tostring({})
Deep.runtimeToken = runtime.LesbhubDeepRuntimeToken

local function safeSegment(value, maximum)
    local result = tostring(value or "script"):gsub("[^%w_-]", "_")
    result = result:sub(1, maximum or 42)
    return result ~= "" and result or "script"
end

local function folders(path)
    local current = ""
    for part in path:gmatch("[^/]+") do
        assert(part ~= ".." and part ~= ".", "unsafe directory")
        current = current == "" and part or current .. "/" .. part
        local ok, exists = pcall(function() return type(isfolder) == "function" and isfolder(current) end)
        if not (ok and exists) then
            local made, err = pcall(makefolder, current)
            if not made then
                local checked, found = pcall(function() return isfolder(current) end)
                assert(checked and found, tostring(err))
            end
        end
    end
end

local function hasCode(source)
    local position = 1
    while true do
        position = source:find("%S", position)
        if not position then return false end
        if source:sub(position, position + 1) ~= "--" then return true end
        local start, finish, equals = source:find("%-%-%[(=*)%[", position)
        if start == position then
            local _, closing = source:find("]" .. equals .. "]", finish + 1, true)
            if not closing then return false end
            position = closing + 1
        else
            local newline = source:find("\n", position + 2, true)
            if not newline then return false end
            position = newline + 1
        end
    end
end

function Deep.capabilities()
    return {decompile = type(decompile) == "function", writefile = type(writefile) == "function",
        appendfile = type(appendfile) == "function", readfile = type(readfile) == "function",
        isfile = type(isfile) == "function", makefolder = type(makefolder) == "function",
        syntaxCheck = type(loadstring) == "function",
        sha256 = type(crypt) == "table" and type(crypt.hash) == "function"}
end

function Deep.checksum(text)
    if type(crypt) == "table" and type(crypt.hash) == "function" then
        local ok, hash = pcall(crypt.hash, text, "sha256")
        if ok and type(hash) == "string" and #hash == 64 and hash:match("^%x+$") then
            return hash:lower(), "sha256"
        end
    end
    -- Portable integrity check, clearly named; not a cryptographic hash.
    local a, b = 1, 0
    for i = 1, #text do
        a = (a + text:byte(i)) % 65521
        b = (b + a) % 65521
        if i % 65536 == 0 then task.wait() end
    end
    return string.format("%08x", b * 65536 + a), "adler32"
end

function Deep.new(base, enabled, control, progress)
    assert(type(base) == "string" and base:sub(1, 16) == "LesbhubExporter/", "unsafe export root")
    assert(not base:find("\\") and not base:find(":") and not base:find("//"), "unsafe export root")
    for part in base:gmatch("[^/]+") do assert(part ~= "." and part ~= "..", "unsafe export root") end
    local self = {enabled = enabled, entries = {}, queue = {}, seen = {}, byId = {},
        capabilities = Deep.capabilities(), indexPath = "scripts/index.json", failures = {}}
    local start = os.clock()
    local function cancelled() return control and control.cancelled == true end
    local function counts()
        local result = {discovered = #self.entries, attempted = 0, succeeded = 0,
            failed = 0, inaccessible = 0, empty = 0, partial = 0, skipped = 0,
            pending = 0, files = 0, bytes = 0}
        for _, entry in ipairs(self.entries) do
            if entry.attempted then result.attempted = result.attempted + 1 end
            if entry.skipped then result.skipped = result.skipped + 1 end
            if entry.status == "success" then result.succeeded = result.succeeded + 1
            elseif result[entry.status] ~= nil then result[entry.status] = result[entry.status] + 1 end
            if entry.verifiedReadback then
                result.files = result.files + 1; result.bytes = result.bytes + entry.fileByteLength
            end
        end
        return result
    end
    function self:summary()
        return {version = 1, enabled = self.enabled, indexPath = self.indexPath,
            capabilities = self.capabilities, stats = counts(), indexWritten = self.indexWritten == true,
            runtimeToken = Deep.runtimeToken,
            elapsedSeconds = os.clock() - start, error = self.indexError or "",
            scope = "selected client-visible instances; reconstructed pseudocode, not original source"}
    end
    local function textSafe(value)
        local ok = pcall(function() Http:JSONEncode(value) end)
        if ok then return value end
        return (tostring(value):gsub("[^ -~]", function(c) return string.format("~%02X", c:byte()) end))
    end
    function self:saveIndex()
        local ok, err = pcall(function()
            folders(base .. "/scripts")
            writefile(base .. "/" .. self.indexPath, Http:JSONEncode({version = 1,
                stats = counts(), capabilities = self.capabilities, scripts = self.entries}))
        end)
        self.indexWritten = ok
        self.indexError = not ok and tostring(err) or nil
        return ok, err
    end
    function self:discover(instance, record, service)
        local id = "s" .. tostring(record.instanceId)
        if self.seen[id] then
            record.scriptId = id
            self.byId[id].latestObservedPath = textSafe(record.path)
            return
        end
        self.seen[id] = true; record.scriptId = id
        local debugOk, debugId = pcall(function() return instance:GetDebugId() end)
        local entry = {scriptId = id, instanceId = record.instanceId,
            name = textSafe(record.name), className = record.className, service = service,
            robloxPath = textSafe(record.path), guiPath = service == "PlayerGui" and textSafe(record.parentPath) or "",
            latestObservedPath = textSafe(record.path),
            debugId = debugOk and textSafe(debugId) or "unavailable", method = "decompile",
            status = "pending", error = "", outputPath = "", byteLength = 0, lineCount = 0,
            checksum = "", checksumAlgorithm = "", truncationDetected = false,
            truncationAssessment = "unknown", attempted = false}
        self.entries[#self.entries + 1] = entry
        self.byId[id] = entry
        if self.enabled then self.queue[#self.queue + 1] = {instance = instance, entry = entry}
        else entry.status = "inaccessible"; entry.error = "reconstructed code not enabled"; entry.skipped = true end
    end
    local function extract(job)
        local entry = job.entry
        if cancelled() then entry.status = "inaccessible"; entry.error = "cancelled"; entry.skipped = true; return end
        if not self.capabilities.decompile then
            entry.status = "inaccessible"; entry.error = "decompile is unavailable"; entry.skipped = true; return
        end
        entry.attempted = true
        local at = os.clock()
        local ok, source = pcall(decompile, job.instance)
        entry.elapsedSeconds = os.clock() - at
        if not ok then entry.status = "failed"; entry.error = textSafe(tostring(source)); return end
        if type(source) ~= "string" or not source:find("%S") then entry.status = "empty"; entry.error = "empty decompiler result"; return end
        if not hasCode(source) then
            entry.status = "empty"; entry.error = "decompiler returned comments only"; return
        end
        entry.byteLength = #source
        entry.lineCount = select(2, source:gsub("\n", "")) + 1
        entry.checksum, entry.checksumAlgorithm = Deep.checksum(source)
        local lower = source:lower()
        local firstLine, lastLine, total = source:match("%-%- Lines (%d+)%-(%d+) of (%d+)")
        entry.truncationDetected = (firstLine ~= nil and (tonumber(firstLine) > 1 or tonumber(lastLine) < tonumber(total)))
            or lower:find("[truncated]", 1, true) ~= nil
            or lower:find("-- truncated", 1, true) ~= nil
        entry.truncationAssessment = entry.truncationDetected and "explicit_marker" or "not_observed_not_guaranteed"
        local syntaxOk, syntaxError = false, "loadstring unavailable"
        if self.capabilities.syntaxCheck then
            local checked, fn, why = pcall(loadstring, source, "@reconstructed/" .. entry.scriptId)
            syntaxOk = checked and type(fn) == "function"
            syntaxError = checked and tostring(why or "") or tostring(fn)
        end
        entry.compiles = syntaxOk; entry.compileError = syntaxOk and "" or textSafe(syntaxError)
        local utf8Ok = pcall(function() assert(utf8.len(source), "invalid UTF-8") end)
        entry.encoding = utf8Ok and "utf-8" or "invalid-utf8-preserved"
        local relative = "scripts/sources/" .. safeSegment(entry.service) .. "/" .. entry.scriptId .. "_"
        local budget = math.max(1, math.min(42, 239 - #base - #relative - 6))
        entry.outputPath = relative .. safeSegment(entry.name, budget) .. ".luau"
        local header = "-- Reconstructed client pseudocode; original source is unavailable.\n"
            .. "-- Roblox path: " .. entry.robloxPath:gsub("[\r\n]", " ")
            .. "\n-- Class: " .. entry.className .. "\n-- DebugId: " .. entry.debugId:gsub("[\r\n]", " ")
            .. "\n-- ScriptId: " .. entry.scriptId .. "\n\n"
        local filename, content = base .. "/" .. entry.outputPath, header .. source
        entry.headerByteLength = #header; entry.fileByteLength = #content
        entry.fileChecksum, entry.fileChecksumAlgorithm = Deep.checksum(content)
        if cancelled() then entry.status = "inaccessible"; entry.error = "cancelled"; entry.skipped = true; return end
        local written, writeError = pcall(function()
            folders(filename:match("^(.*)/[^/]+$"))
            -- Resume an interrupted extraction in this capture only, after exact verification.
            if self.capabilities.isfile and self.capabilities.readfile and isfile(filename)
                and readfile(filename) == content then entry.skipped = true
            elseif self.capabilities.appendfile then
                writefile(filename, header)
                for offset = 1, #source, 65536 do
                    if cancelled() then error("cancelled during write") end
                    appendfile(filename, source:sub(offset, offset + 65535))
                    task.wait()
                end
            else writefile(filename, content) end
            assert(self.capabilities.isfile and self.capabilities.readfile, "file readback unavailable")
            assert(isfile(filename), "file missing after write")
            assert(readfile(filename) == content, "file readback mismatch")
            entry.verifiedReadback = true
        end)
        if not written then entry.status = "failed"; entry.error = textSafe(tostring(writeError)); return end
        entry.status = syntaxOk and utf8Ok and not entry.truncationDetected and "success" or "partial"
        if entry.status == "partial" then entry.error = entry.truncationDetected and "truncation marker detected"
            or (not utf8Ok and "invalid UTF-8 preserved" or "reconstructed code did not pass syntax check") end
    end
    function self:drain()
        if not self.enabled then return end
        self:saveIndex()
        for _, job in ipairs(self.queue) do
            if type(progress) == "function" then progress(job.entry) end
            local ok, err = pcall(extract, job)
            if not ok then job.entry.status = "failed"; job.entry.error = textSafe(tostring(err)) end
            job.instance = nil
            if self.capabilities.appendfile then
                local checkpointed = pcall(function()
                    local path = base .. "/scripts/progress.jsonl"
                    if not self.progressStarted then writefile(path, ""); self.progressStarted = true end
                    appendfile(path, Http:JSONEncode(job.entry) .. "\n")
                end)
                if not checkpointed then self:saveIndex() end
            else self:saveIndex() end -- fallback when appendfile is unavailable
            task.wait()
        end
        table.clear(self.queue)
        self:saveIndex()
    end
    function self:resume(entries, resolve)
        self.entries = entries
        for _, entry in ipairs(entries) do
            assert(type(entry.scriptId) == "string" and entry.scriptId:match("^s%d+$"), "unsafe scriptId")
            assert(type(entry.outputPath) == "string" and type(entry.name) == "string", "malformed script entry")
            assert(entry.className == "LocalScript" or entry.className == "ModuleScript"
                or entry.className == "Script", "unexpected script class")
            local verified = false
            if entry.verifiedReadback and entry.outputPath:match("^scripts/sources/[%w_/-]+%.luau$")
                and not entry.outputPath:find("..", 1, true) then
                local ok, content = pcall(function() return readfile(base .. "/" .. entry.outputPath) end)
                if ok then
                    local checksum, algorithm = Deep.checksum(content)
                    verified = checksum == entry.fileChecksum and algorithm == entry.fileChecksumAlgorithm
                end
            end
            if verified and entry.status == "success" then entry.skipped = true
            else
                local instance = resolve(entry)
                entry.verifiedReadback = false
                if instance then self.queue[#self.queue + 1] = {entry = entry, instance = instance}
                else entry.status = "inaccessible"; entry.error = "original instance is unavailable in this session" end
            end
        end
        self:drain()
    end
    return self
end

return Deep
