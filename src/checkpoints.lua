-- Verified immutable checkpoints. Recovery never appends to an old session.
local Checkpoints={}
function Checkpoints.new(context)
    local nextId,writes=1,0
    local self={}
    local function read(path)
        local ok,status,value=pcall(context.read,path)
        if not ok then return "error",status end
        return status,value
    end
    local function snapshot(path)
        local status,content=read(path)
        if status~="ok" or type(content)~="string"then return nil end
        local checksum,algorithm=context.checksum(content)
        local stem="checkpoints/files/"..algorithm.."-"..checksum.."-"..#content
        local slot=0
        while true do
            local target=stem..(slot==0 and""or("-"..slot))..".bin"
            local found,previous=read(target)
            if found=="error"then return nil end
            if found=="ok"and previous==content then
                return {path=path,snapshotPath=target,bytes=#content,checksum=checksum,checksumAlgorithm=algorithm}
            elseif found=="missing"then
                if not context.write(target,content)then return nil end
                return {path=path,snapshotPath=target,bytes=#content,checksum=checksum,checksumAlgorithm=algorithm}
            end
            slot=slot+1
        end
    end
    function self:save(manifest,artifacts,pending)
        local items,paths={},{}
        for path,item in pairs(artifacts)do
            if path:sub(1,12)~="checkpoints/"and path~="manifest.json"and path~="report.json"and path~="report.md"and path~="artifacts/index.json"then
                paths[#paths+1]=path
                local copy={};for key,value in pairs(item)do copy[key]=value end
                items[path]=copy
            end
        end
        table.sort(paths)
        local snapshots,list={},{}
        for _,path in ipairs(paths)do
            list[#list+1]=items[path]
            if path=="client.json"or path:match("/index%.json$")or path=="remotes/signatures.json"or path=="scripts/progress.jsonl"then
                local item=snapshot(path)
                if not item then return false,"checkpoint_snapshot_failed:"..path end
                snapshots[#snapshots+1]=item
                if item.bytes~=items[path].bytes or item.checksum~=items[path].checksum or item.checksumAlgorithm~=items[path].checksumAlgorithm then
                    return false,"checkpoint_artifact_changed:"..path
                end
            end
        end
        local payload={checkpointVersion=1,manifest=manifest,artifacts=list,snapshots=snapshots,
            lastSequence=manifest.identity.lastSequence,pending=pending or{}}
        while true do
            local path=string.format("checkpoints/c%06d.json",nextId)
            nextId=nextId+1
            local status=read(path)
            if status=="error"then return false,"checkpoint_read_failed"end
            if status=="missing"then
                if not context.writeJson(path,payload)then return false,"checkpoint_write_failed"end
                writes=writes+1;self.lastPath=path;self.lastSequence=payload.lastSequence
                return true,path
            end
        end
    end
    function self:summary()return {writes=writes,lastPath=self.lastPath,lastSequence=self.lastSequence or 0}end
    return self
end
return Checkpoints
