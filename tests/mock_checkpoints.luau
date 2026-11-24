local Checkpoints = require("../src/checkpoints")
local files, json, writes, blobWrites = {}, {}, {}, 0
local failedCheckpoint, failBlob = false, false
local function checksum(content)
    -- Deliberate collision for all equal-length contents.
    return string.rep("a", 8), "adler32"
end
local function artifact(path, content)
    files[path] = content
    local hash, algorithm = checksum(content)
    return {path = path, kind = "sidecar", bytes = #content, checksum = hash, checksumAlgorithm = algorithm}
end
local writer = Checkpoints.new({
    checksum = checksum,
    read = function(path)
        if files[path] ~= nil then return "ok", files[path] end
        return "missing"
    end,
    write = function(path, content)
        assert(files[path] == nil, "existing blob was overwritten")
        blobWrites = blobWrites + 1
        if failBlob then files[path] = content:sub(1, 1); return false end
        files[path] = content
        return true
    end,
    writeJson = function(path, payload)
        assert(files[path] == nil, "existing checkpoint was overwritten")
        writes[#writes + 1] = path
        if failedCheckpoint then files[path] = "{partial"; failedCheckpoint = false; return false end
        files[path] = "verified-json"
        json[path] = payload
        return true
    end,
})
local manifest = {identity = {lastSequence = 7}}
local artifacts = {["scripts/index.json"] = artifact("scripts/index.json", "alpha"),
    ["client.json"] = artifact("client.json", "alpha"),
    ["gui/states/index.json"] = artifact("gui/states/index.json", "bravo"),
    ["journal/events/b000001.json"] = artifact("journal/events/b000001.json", "event")}
local ok, first = writer:save(manifest, artifacts, {journalQueued = 0})
assert(ok and first == "checkpoints/c000001.json")
assert(blobWrites == 2, "identical bytes did not reuse the blob, or collision was conflated")
local firstPayload = json[first]
local snapshots = {}
for _, item in ipairs(firstPayload.snapshots) do snapshots[item.path] = item end
assert(snapshots["client.json"].snapshotPath == snapshots["scripts/index.json"].snapshotPath)
assert(snapshots["client.json"].snapshotPath ~= snapshots["gui/states/index.json"].snapshotPath)
assert(files[snapshots["client.json"].snapshotPath] == "alpha")
assert(files[snapshots["gui/states/index.json"].snapshotPath] == "bravo")
assert(not snapshots["journal/events/b000001.json"], "immutable journal segment was needlessly copied")
assert(firstPayload.lastSequence == 7 and firstPayload.manifest == manifest and #firstPayload.artifacts == 4)
local ok2, second = writer:save(manifest, artifacts, {})
assert(ok2 and second == "checkpoints/c000002.json" and blobWrites == 2, "unchanged blobs rewritten")

failedCheckpoint = true
local rejected, why = writer:save(manifest, artifacts, {})
assert(not rejected and why == "checkpoint_write_failed")
local success, fourth = writer:save(manifest, artifacts, {})
assert(success and fourth == "checkpoints/c000004.json")
assert(files["checkpoints/c000003.json"] == "{partial", "uncertain checkpoint overwritten")

artifacts["scripts/index.json"] = artifact("scripts/index.json", "charl")
failBlob = true
local failedBlob, blobError = writer:save(manifest, artifacts, {})
assert(not failedBlob and blobError == "checkpoint_snapshot_failed:scripts/index.json")
failBlob = false
local resumed, resumedPath = writer:save(manifest, artifacts, {})
assert(resumed and resumedPath == "checkpoints/c000005.json")
assert(files[snapshots["client.json"].snapshotPath] == "alpha", "old snapshot mutated")

-- Index read differs from the registered bytes: no checkpoint may claim either.
files["scripts/index.json"] = "different length"
local changed, changedReason = writer:save(manifest, artifacts, {})
assert(not changed and changedReason == "checkpoint_artifact_changed:scripts/index.json")
assert(writer:summary().writes == 4 and writer:summary().lastSequence == 7)
print("Checkpoint OK: immutable ids, exact-byte blob reuse, collisions, partial writes and stale hashes")
