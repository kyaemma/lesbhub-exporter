-- Public identity/capabilities only. No player names, session IDs or uploads.
local Metadata = {}
function Metadata.capture(cfg, budget)
    local result = {placeId=game.PlaceId,gameId=game.GameId,universeId=game.GameId,
        methods={},placeIds={status="partial",known={game.PlaceId},reason="only the current place is established"},
        capabilities={},limitations={"Server-only objects and original script source are unavailable."}}
    local env = getfenv()
    for _, name in ipairs({"decompile","writefile","readfile","appendfile","isfile","makefolder",
        "loadstring","getscripts","getloadedmodules","compareinstances","cloneref"}) do
        result.capabilities[name]=type(env[name])=="function"
    end
    local versionOk, version = pcall(function()return game.PlaceVersion end)
    if versionOk then result.placeVersion=version end
    local streamingOk,streaming=pcall(function()return workspace.StreamingEnabled end)
    if streamingOk then result.streamingEnabled=streaming end
    if streaming then result.limitations[#result.limitations+1]="Streaming can omit Workspace descendants." end
    if type(identifyexecutor)=="function" then
        local ok,name,executorVersion=pcall(identifyexecutor)
        if ok then result.executor={name=tostring(name),version=tostring(executorVersion or "unavailable")} end
    end
    result.publicMetadata={status="unavailable",reason="public product metadata unavailable"}
    if cfg.publicGameMetadata~=false then
        local at=os.clock()
        local ok,info,method=pcall(function()
            local marketplace=game:GetService("MarketplaceService")
            if type(marketplace.GetProductInfoAsync)=="function" then
                return marketplace:GetProductInfoAsync(game.PlaceId,Enum.InfoType.Asset),"MarketplaceService.GetProductInfoAsync"
            end
            return marketplace:GetProductInfo(game.PlaceId,Enum.InfoType.Asset),"MarketplaceService.GetProductInfo"
        end)
        if budget then budget:native("public_game_metadata",os.clock()-at);budget:checkpoint("public_game_metadata")end
        if ok and type(info)=="table" then
            result.publicMetadata={status="available",method=method,fields={}}
            for _, key in ipairs({"Name","Description","AssetId","AssetTypeId","Created","Updated"})do
                local value=info[key]
                if type(value)=="string" or type(value)=="number" then result.publicMetadata.fields[key]=value end
            end
            if type(info.Creator)=="table" then
                result.publicMetadata.fields.Creator={name=info.Creator.Name,id=info.Creator.CreatorTargetId or info.Creator.Id,
                    type=info.Creator.CreatorType}
            end
            result.methods[#result.methods+1]=method
        end
    else result.publicMetadata={status="disabled",reason="disabled_by_config"}end
    return result
end
return Metadata
