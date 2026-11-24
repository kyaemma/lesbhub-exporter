-- Immutable, verified segment journal. Rows are copied at admission.
local Journal = {}

local function copyValue(value, ancestors)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then return value end
    if kind == "number" then
        assert(value == value and value ~= math.huge and value ~= -math.huge, "non-finite journal number")
        return value
    end
    assert(kind == "table" and not ancestors[value], "journal rows must be acyclic data")
    ancestors[value] = true
    local result = {}
    for key, item in pairs(value) do
        local keyType = type(key)
        assert(keyType == "string" or (keyType == "number" and key > 0 and key % 1 == 0), "invalid journal key")
        result[key] = copyValue(item, ancestors)
    end
    ancestors[value] = nil
    return result
end

local function positiveInteger(value, default)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return default end
    return math.max(1, math.floor(n))
end

function Journal.new(cfg, context)
    cfg, context = cfg or {}, context or {}
    assert(type(context.write) == "function", "journal write callback required")
    local batchSize = positiveInteger(cfg.batchSize, 256)
    local maxQueued = positiveInteger(cfg.maxQueued, 8192)
    batchSize = math.min(batchSize, maxQueued)
    local streams = {}
    local queued, queuePeak, lostEvents, writeErrors = 0, 0, 0, 0
    local durableEvents, segmentCount, bytes = 0, 0, 0
    local busy, frozen = false, false
    local self = {}

    local function stateFor(stream)
        local state = streams[stream]
        if not state then
            state = {rows = {}, head = 1, tail = 0, pending = nil, segments = {}, events = 0, nextSegment = 1}
            streams[stream] = state
        end
        return state
    end
    for _,name in ipairs({"gui-actions","gui-transitions","remote-observations","temporal-relations"})do stateFor(name)end
    local function callback(name, ...)
        if type(context[name]) == "function" then pcall(context[name], ...) end
    end
    local function available(state) return state.tail - state.head + 1 end
    local function writeBatch(stream, state, count)
        if not state.pending then
            local rows = {}
            for i = 1, math.min(count, batchSize, available(state)) do
                rows[i] = state.rows[state.head]
                state.rows[state.head] = nil
                state.head = state.head + 1
            end
            if #rows == 0 then return true, 0 end
            if state.head > state.tail then state.rows = {}; state.head = 1; state.tail = 0 end
            state.pending = {path = string.format("journal/%s/b%06d.json", stream, state.nextSegment),
                payload = {version = 1, stream = stream, rows = rows}}
        end
        local pending = state.pending
        local ok, verified = pcall(context.write, pending.path, pending.payload)
        if not ok or verified ~= true then
            writeErrors = writeErrors + 1
            callback("onError", "journal_write_failed:" .. pending.path)
            return false, 0
        end
        local rows = pending.payload.rows
        local segment = {path = pending.path, count = #rows,
            firstSequence = rows[1].sequence, lastSequence = rows[#rows].sequence}
        if type(context.measure) == "function" then
            local measured, length = pcall(context.measure, pending.payload)
            if measured and type(length) == "number" and length >= 0 and length < math.huge then
                segment.bytes = length
                bytes = bytes + length
            end
        end
        state.segments[#state.segments + 1] = segment
        state.events = state.events + #rows
        state.nextSegment = state.nextSegment + 1
        state.pending = nil
        queued = queued - #rows
        durableEvents = durableEvents + #rows
        segmentCount = segmentCount + 1
        return true, #rows
    end

    function self:append(stream, row)
        assert(type(stream) == "string" and stream:match("^[%w_-]+$"), "invalid journal stream")
        assert(type(row) == "table" and type(row.sequence) == "number"
            and row.sequence > 0 and row.sequence % 1 == 0 and row.sequence < math.huge, "invalid journal sequence")
        if queued >= maxQueued then
            lostEvents = lostEvents + 1
            callback("onOverflow", lostEvents)
            return false
        end
        local copied = copyValue(row, {})
        local state = stateFor(stream)
        state.tail = state.tail + 1
        state.rows[state.tail] = copied
        queued = queued + 1
        queuePeak = math.max(queuePeak, queued)
        if cfg.autoFlush ~= false and not busy and not frozen and available(state) >= batchSize then
            self:flush(stream)
        end
        return true
    end

    function self:flush(stream)
        if busy then return false end
        if stream ~= nil then assert(type(stream) == "string" and stream:match("^[%w_-]+$"), "invalid journal stream") end
        -- Fix the work set before writing: producers can enqueue while write yields.
        local work = {}
        for name, state in pairs(streams) do
            if not stream or name == stream then
                local count = available(state) + (state.pending and #state.pending.payload.rows or 0)
                if count > 0 then work[#work + 1] = {name = name, state = state, count = count} end
            end
        end
        table.sort(work, function(a, b) return a.name < b.name end)
        busy = true
        local success = true
        for _, item in ipairs(work) do
            while item.count > 0 do
                local ok, written = writeBatch(item.name, item.state, item.count)
                if not ok or written == 0 then success = false; break end
                item.count = item.count - written
            end
        end
        busy = false
        return success
    end
    function self:freeze() frozen = true end
    function self:thaw() frozen = false end
    function self:isBusy() return busy end
    function self:index()
        local result = {version = 1, streams = {}}
        for name, state in pairs(streams) do
            local segments = {}
            for i, segment in ipairs(state.segments) do
                segments[i] = {path = segment.path, count = segment.count,
                    firstSequence = segment.firstSequence, lastSequence = segment.lastSequence, bytes = segment.bytes}
            end
            result.streams[name] = {segments = segments, events = state.events}
        end
        return result
    end
    function self:summary()
        return {queued = queued, queuePeak = queuePeak, lostEvents = lostEvents, writeErrors = writeErrors,
            durableEvents = durableEvents, segments = segmentCount, bytes = bytes}
    end
    return self
end

return Journal
