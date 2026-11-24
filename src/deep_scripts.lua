-- Optional reconstructed-code writer. Never requires or executes captured modules.
local Deep = {}
local Http = game:GetService("HttpService")
local runtime = (type(getgenv) == "function" and getgenv()) or {}
runtime.LesbhubDeepRuntimeToken = runtime.LesbhubDeepRuntimeToken or tostring(os.clock()) .. tostring({})
Deep.runtimeToken = runtime.LesbhubDeepRuntimeToken

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

function Deep.checksum(text, requestedAlgorithm, budget)
    if requestedAlgorithm and requestedAlgorithm ~= "sha256" and requestedAlgorithm ~= "adler32" then
        return nil, "unavailable"
    end
    if requestedAlgorithm ~= "adler32" and type(crypt) == "table" and type(crypt.hash) == "function" then
        local at = os.clock()
        local ok, hash = pcall(crypt.hash, text, "sha256")
        if budget and budget.native then budget:native("hash", os.clock() - at) end
        if ok and type(hash) == "string" and #hash == 64 and hash:match("^%x+$") then
            return hash:lower(), "sha256"
        end
    end
    if requestedAlgorithm and requestedAlgorithm ~= "adler32" then return nil, "unavailable" end
    -- Portable integrity check, clearly named; not a cryptographic hash.
    local a, b = 1, 0
    for i = 1, #text do
        a = (a + text:byte(i)) % 65521
        b = (b + a) % 65521
        if i % 65536 == 0 then
            if budget then budget:checkpoint("checksum") else task.wait() end
        end
    end
    return string.format("%08x", b * 65536 + a), "adler32"
end

function Deep.new(base, enabled, control, progress, context)
    assert(type(base) == "string" and base:sub(1, 16) == "LesbhubExporter/", "unsafe export root")
    assert(not base:find("\\") and not base:find(":") and not base:find("//"), "unsafe export root")
    for part in base:gmatch("[^/]+") do assert(part ~= "." and part ~= "..", "unsafe export root") end
    local self = {enabled = enabled, entries = {}, queue = {}, seen = {}, byId = {},
        capabilities = Deep.capabilities(), indexPath = "scripts/index.json", failures = {}}
    context = type(context) == "table" and context or {}
    local budget = context.budget
    local start = os.clock()
    local function checkpoint(stage, force)
        if budget then return budget:checkpoint(stage, force) end
        if force then task.wait() end
        return not (control and control.cancelled)
    end
    local function timed(stage, fn, ...)
        local at = os.clock()
        local results = table.pack(pcall(fn, ...))
        if budget and budget.native then budget:native(stage, os.clock() - at) end
        return table.unpack(results, 1, results.n)
    end
    local function cancelled() return control and control.cancelled == true end
    local function counts()
        local result = {discovered = #self.entries, attempted = 0, succeeded = 0,
            failed = 0, inaccessible = 0, empty = 0, partial = 0, skipped = 0,
            pending = 0, files = 0, bytes = 0, logicalFiles = 0, logicalBytes = 0, sharedReferences = 0}
        local paths = {}
        for _, entry in ipairs(self.entries) do
            if entry.attempted then result.attempted = result.attempted + 1 end
            if entry.skipped then result.skipped = result.skipped + 1 end
            if entry.status == "success" then result.succeeded = result.succeeded + 1
            elseif result[entry.status] ~= nil then result[entry.status] = result[entry.status] + 1 end
            if entry.verifiedReadback then
                result.logicalFiles = result.logicalFiles + 1
                result.logicalBytes = result.logicalBytes + entry.fileByteLength
                if not paths[entry.outputPath] then
                    paths[entry.outputPath] = true
                    result.files = result.files + 1; result.bytes = result.bytes + entry.fileByteLength
                end
            end
        end
        result.sharedReferences = result.logicalFiles - result.files
        return result
    end
    function self:summary()
        return {version = 2, enabled = self.enabled, indexPath = self.indexPath,
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
            local encoded=Http:JSONEncode({version = 2,stats = counts(),capabilities = self.capabilities,scripts = self.entries})
            writefile(base .. "/" .. self.indexPath,encoded)
            if self.capabilities.readfile and self.capabilities.isfile then
                assert(isfile(base.."/"..self.indexPath)and readfile(base.."/"..self.indexPath)==encoded,"script index readback mismatch")
            end
        end)
        self.indexWritten = ok
        if ok then self.dirty = false end
        self.indexError = not ok and tostring(err) or nil
        return ok, err
    end
    function self:discover(instance, record, service)
        local id = "s" .. tostring(record.instanceId)
        if self.seen[id] then
            record.scriptId = id
            local latest = textSafe(record.path)
            if self.byId[id].latestObservedPath ~= latest then
                self.byId[id].latestObservedPath = latest
                self.dirty = true
            end
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
        self.dirty = true
        self.byId[id] = entry
        if self.enabled then
            if #self.queue >= (context.queueLimit or 8192)then
                entry.status="inaccessible";entry.error="script work queue overflow";entry.skipped=true
                if type(context.onOverflow)=="function"then context.onOverflow()end
            else self.queue[#self.queue+1]={instance=instance,entry=entry}end
        else entry.status = "inaccessible"; entry.error = "reconstructed code not enabled"; entry.skipped = true end
    end
    local function extract(job)
        local entry = job.entry
        if cancelled() then entry.status = "inaccessible"; entry.error = "cancelled"; entry.skipped = true; return end
        if not self.capabilities.decompile then
            entry.status = "inaccessible"; entry.error = "decompile is unavailable"; entry.skipped = true; return
        end
        entry.attempted = true
        entry.diagnosticPath = nil; entry.diagnosticByteLength = nil
        entry.diagnosticChecksum = nil; entry.diagnosticChecksumAlgorithm = nil; entry.diagnosticError = nil
        local at = os.clock()
        local ok, source = timed("decompile", decompile, job.instance)
        entry.elapsedSeconds = os.clock() - at
        if not ok then entry.status = "failed"; entry.error = textSafe(tostring(source)); return end
        if type(source) == "string" and type(context.analyze) == "function" then
            local analyzed, analysis = pcall(context.analyze, source, entry)
            if analyzed then entry.analysis = analysis
            else entry.analysisError = textSafe(tostring(analysis)) end
        end
        if type(source) ~= "string" or not source:find("%S") or not hasCode(source) then
            entry.status = "empty"
            entry.error = type(source) == "string" and source:find("%S")
                and "decompiler returned comments only" or "empty decompiler result"
            if type(source) == "string" then
                entry.diagnosticByteLength = #source
                entry.diagnosticChecksum, entry.diagnosticChecksumAlgorithm = Deep.checksum(source, nil, budget)
                if #source > 0 and not cancelled() then
                    local path = "errors/script-diagnostics/" .. entry.scriptId .. ".txt"
                    local saved, why = pcall(function()
                        folders(base .. "/errors/script-diagnostics")
                        writefile(base .. "/" .. path, source)
                        assert(self.capabilities.isfile and self.capabilities.readfile, "file readback unavailable")
                        assert(isfile(base .. "/" .. path) and readfile(base .. "/" .. path) == source,
                            "diagnostic readback mismatch")
                    end)
                    if saved then
                        entry.diagnosticPath = path
                        if type(context.artifact)=="function"then context.artifact(path,source,"decompiler_diagnostic")end
                    else entry.diagnosticError = textSafe(tostring(why)) end
                end
            end
            return
        end
        if cancelled() then entry.status = "inaccessible"; entry.error = "cancelled"; entry.skipped = true; return end
        entry.byteLength = #source
        entry.lineCount = select(2, source:gsub("\n", "")) + 1
        entry.checksum, entry.checksumAlgorithm = Deep.checksum(source, nil, budget)
        local lower = source:lower()
        local firstLine, lastLine, total = source:match("%-%- Lines (%d+)%-(%d+) of (%d+)")
        entry.truncationDetected = (firstLine ~= nil and (tonumber(firstLine) > 1 or tonumber(lastLine) < tonumber(total)))
            or lower:find("[truncated]", 1, true) ~= nil
            or lower:find("-- truncated", 1, true) ~= nil
        entry.truncationAssessment = entry.truncationDetected and "explicit_marker" or "not_observed_not_guaranteed"
        local syntaxOk, syntaxError = false, "loadstring unavailable"
        if self.capabilities.syntaxCheck then
            local checked, fn, why = timed("compile", loadstring, source, "@reconstructed/" .. entry.scriptId)
            syntaxOk = checked and type(fn) == "function"
            syntaxError = checked and tostring(why or "") or tostring(fn)
        end
        entry.compiles = syntaxOk; entry.compileError = syntaxOk and "" or textSafe(syntaxError)
        local utf8Ok = pcall(function() assert(utf8.len(source), "invalid UTF-8") end)
        entry.encoding = utf8Ok and "utf-8" or "invalid-utf8-preserved"
        local prefix = "scripts/sources/content/" .. entry.checksumAlgorithm .. "-" .. entry.checksum .. "-" .. #source
        entry.headerByteLength = 0; entry.fileByteLength = #source
        entry.fileChecksum, entry.fileChecksumAlgorithm = entry.checksum, entry.checksumAlgorithm
        if cancelled() then entry.status = "inaccessible"; entry.error = "cancelled"; entry.skipped = true; return end
        local written, writeError = pcall(function()
            assert(self.capabilities.isfile and self.capabilities.readfile, "file readback unavailable")
            folders(base .. "/scripts/sources/content")
            local collision = 0
            local filename
            while true do
                entry.outputPath = prefix .. (collision > 0 and ("-collision" .. collision) or "") .. ".luau"
                filename = base .. "/" .. entry.outputPath
                if not isfile(filename) then break end
                if readfile(filename) == source then entry.skipped = true; break end
                collision = collision + 1
            end
            entry.contentId = entry.outputPath
            if entry.skipped then
                -- Exact byte equality, never checksum equality alone.
            elseif self.capabilities.appendfile then
                writefile(filename, "")
                for offset = 1, #source, 65536 do
                    if cancelled() then error("cancelled during write") end
                    appendfile(filename, source:sub(offset, offset + 65535))
                    checkpoint("script_write", not budget)
                end
            else writefile(filename, source) end
            assert(isfile(filename), "file missing after write")
            assert(readfile(filename) == source, "file readback mismatch")
            entry.verifiedReadback = true
            if type(context.artifact) == "function" then context.artifact(entry.outputPath, source, "script") end
        end)
        if not written then
            entry.status = cancelled() and "inaccessible" or "failed"
            entry.skipped = cancelled() or nil
            entry.error = cancelled() and "cancelled" or textSafe(tostring(writeError)); return
        end
        entry.status = syntaxOk and utf8Ok and not entry.truncationDetected and "success" or "partial"
        if entry.status == "partial" then entry.error = entry.truncationDetected and "truncation marker detected"
            or (not utf8Ok and "invalid UTF-8 preserved" or "reconstructed code did not pass syntax check") end
    end
    function self:drain()
        if not self.enabled or #self.queue == 0 then return end
        -- Only discard the old journal after the current snapshot is durable.
        local snapshotted = self:saveIndex()
        if self.capabilities.appendfile and not self.progressStarted then
            if snapshotted then
                self.progressStarted = pcall(writefile, base .. "/scripts/progress.jsonl", "")
            else
                self.progressStarted = true
            end
        end
        local sinceIndex = 0
        local jobs = self.queue
        self.queue = {}
        for index, job in ipairs(jobs) do
            if cancelled() then
                job.entry.status = "inaccessible"; job.entry.error = "cancelled"; job.entry.skipped = true
            else
                if type(progress) == "function" and (index == 1 or index % 25 == 0) then progress(job.entry) end
                local ok, err = pcall(extract, job)
                if not ok then job.entry.status = "failed"; job.entry.error = textSafe(tostring(err)) end
            end
            self.dirty = true
            job.instance = nil
            sinceIndex = sinceIndex + 1
            if not cancelled() and self.capabilities.appendfile and self.progressStarted then
                local checkpointed = pcall(function()
                    local path = base .. "/scripts/progress.jsonl"
                    appendfile(path, Http:JSONEncode(job.entry) .. "\n")
                end)
                if not checkpointed then self:saveIndex(); sinceIndex = 0 end
            elseif not cancelled() and sinceIndex >= 25 then
                self:saveIndex(); sinceIndex = 0
            end
            if not cancelled() and type(context.pump)=="function" then context.pump()end
            if not cancelled() then checkpoint("script", not budget) end
        end
        if self.dirty then self:saveIndex() end
    end
    function self:resume(entries, resolve)
        self.entries = entries
        self.seen = {}; self.byId = {}; self.queue = {}
        self.dirty = true
        for _, entry in ipairs(entries) do
            assert(type(entry.scriptId) == "string" and entry.scriptId:match("^s%d+$"), "unsafe scriptId")
            assert(type(entry.outputPath) == "string" and type(entry.name) == "string", "malformed script entry")
            assert(entry.className == "LocalScript" or entry.className == "ModuleScript"
                or entry.className == "Script", "unexpected script class")
            self.seen[entry.scriptId] = true; self.byId[entry.scriptId] = entry
            local verified = false
            if entry.verifiedReadback and entry.outputPath:match("^scripts/sources/[%w_/-]+%.luau$")
                and not entry.outputPath:find("..", 1, true) then
                local ok, content = pcall(function() return readfile(base .. "/" .. entry.outputPath) end)
                if ok then
                    local checksum, algorithm = Deep.checksum(content, entry.fileChecksumAlgorithm, budget)
                    verified = checksum == entry.fileChecksum and algorithm == entry.fileChecksumAlgorithm
                end
            end
            if verified and entry.status == "success" then entry.skipped = true
            else
                local instance = not cancelled() and resolve(entry) or nil
                entry.skipped = nil; entry.attempted = false; entry.error = ""
                entry.verifiedReadback = false
                if instance then self.queue[#self.queue + 1] = {entry = entry, instance = instance}
                else entry.status = "inaccessible"; entry.error = cancelled() and "cancelled"
                    or "original instance is unavailable in this session" end
            end
        end
        self:drain()
        if self.dirty then self:saveIndex() end
    end
    return self
end

return Deep
