local Gui = require("../src/gui_states")
local files, events = {}, {}
local failWrite, failLookupAfterWrite, failRead = false, false, false
local function fingerprint() return "deliberate collision" end
local function encode(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t ~= "table" then return tostring(v) end
    local keys = {}; for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a,b) return tostring(a)<tostring(b) end)
    local p = {}; for _,k in ipairs(keys) do p[#p+1] = encode(k)..":"..encode(v[k]) end
    return "{"..table.concat(p,",").."}"
end
local context = {
    fingerprint=fingerprint, digest=function() return "collision" end,
    read=function(path)
        if failRead then return "error", "injected" end
        if files[path] then return "ok", files[path] end
        return "missing"
    end,
    write=function(path, payload)
        if failWrite then return false end
        files[path]=payload
        if failLookupAfterWrite and path:find("/lookup/",1,true) then failLookupAfterWrite=false; return false end
        return true
    end,
    emit=function(event) events[#events+1]=event; return #events end,
    measure=function(payload) return #encode(payload) end,
}
local function button(id, parent, text, visible, path)
    return {instanceId=id,parentInstanceId=parent,className="TextButton",path=path or "PlayerGui/Menu/Play",
        properties={Text=text,Visible=visible}}
end
local graph = Gui.new({guiStateCacheEntries=0}, context)
local a, b = button(1,20,"Play",true), button(1,20,"Pause",true)
for i, record in ipairs({a,b,a,b,a}) do
    assert(graph:observe(record)); assert(graph:commit("test") == (i%2==1 and 1 or 2))
end
assert(#events==4 and graph:summary().transitions==4 and graph:summary().diskReuses==3)
assert(graph:index().states[1].observations==3 and graph:index().states[2].observations==2)
assert(files["gui/states/state000002.json"].baseStateId==1)
local rebuilt = assert(Gui.reconstruct(context,2)); assert(rebuilt[1].properties.Text=="Pause")
assert(graph:observe(button(1,21,"Play",false,"Other"))); assert(graph:commit("move")==3)
assert(graph:observe({instanceId=1,operation="remove"})); assert(graph:commit("remove")==4)
assert(next(assert(Gui.reconstruct(context,4)))==nil)
failWrite=true; assert(graph:observe(button(1,20,"New",true))); assert(graph:commit("retry")==nil)
failWrite=false; assert(graph:commit("retry")==5)
local old = files["gui/states/lookup/collision/1.json"]
files["gui/states/lookup/collision/1.json"] = {schemaVersion=2,digest="bad",stateId=1}
assert(graph:observe(b)); assert(graph:commit("corrupt")==nil)
files["gui/states/lookup/collision/1.json"] = old
failRead=true; assert(graph:commit("bad read")==nil); failRead=false
assert(graph:commit("restored")==2)
local lost = Gui.new({}, context)
files={}; events={}; failLookupAfterWrite=true
assert(lost:observe(a)); assert(lost:commit("first")==nil)
assert(lost:commit("retry")==1 and #lost:index().states==1)
files={}; events={}; local yielding, changed = nil, false
context.budget={checkpoint=function()
    if not changed then changed=true; assert(yielding:observe({instanceId=129,operation="remove"})) end
end}
yielding=Gui.new({},context)
for i=1,129 do assert(yielding:observe(button(i,20,"same",true))) end
assert(yielding:commit("before yield")==1 and files["gui/states/state000001.json"].elementCount==129)
assert(yielding:commit("after yield")==2 and files["gui/states/state000002.json"].elementCount==128)
context.budget=nil
files={}; events={}; local checkpoints=Gui.new({},context)
for i=1,66 do
    assert(checkpoints:observe(button(1,20,tostring(i),true)))
    assert(checkpoints:commit("version")==i)
end
assert(files["gui/states/state000065.json"].baseStateId==nil)
assert(checkpoints:observe(button(1,20,"1",true)) and checkpoints:commit("return")==1)
assert(checkpoints:checkpoint() and files["gui/states/index.json"].schemaVersion==2)
files={}; events={}; local projection=Gui.new({},context)
local complete={instanceId=31,parentInstanceId=9,className="TextBox",path="PlayerGui/Foo",
    properties={Visible=true,Enabled=false,Text="x|;:=\n",Active=true,Interactable=false,
        Selected=true,Selectable=false,TextEditable=true,ScrollingEnabled=false,Playing=true,Ignored="excluded"}}
assert(projection:observe(complete) and projection:commit("all")==1)
local exact=assert(Gui.reconstruct(context,1))[31]
for k,v in pairs(complete.properties) do if k~="Ignored" then assert(exact.properties[k]==v) end end
assert(exact.properties.Ignored==nil and exact.parentInstanceId==9 and exact.className=="TextBox" and exact.path=="PlayerGui/Foo")
complete.properties.Interactable=true
assert(projection:observe(complete) and projection:commit("change")==2)
local invalid = Gui.new({}, {fingerprint=function() error("bad") end})
assert(not invalid:observe(a) and invalid:commit()==nil and invalid:summary().fingerprintErrors==1)
-- A large deterministic fixture: equivalent-size and delta-size use the same serializer.
files={}; events={}; local large=Gui.new({},context)
for i=1,10000 do assert(large:observe(button(i,20,"Button "..i,true))) end
assert(large:commit("A")==1)
assert(large:observe(button(1,20,"Changed",true))); assert(large:commit("B")==2)
assert(large:observe(button(1,20,"Button 1",true))); assert(large:commit("A")==1)
assert(large:observe(button(1,20,"Changed",true))); assert(large:commit("B")==2)
assert(large:observe(button(1,20,"Button 1",true))); assert(large:commit("A")==1)
for _=1,3600 do assert(large:commit("idle")==1) end
local s=large:summary()
assert(s.states==2 and s.transitions==4 and s.observations==3605 and s.diskReuses==3)
print("GUI fixture: states="..s.states.." transitions="..s.transitions.." idle=3600 encoded-delta="..s.stateBytes.." encoded-full="..s.fullSnapshotEquivalentBytes)
print("GUI states mock OK: exact projection, durable lookup, collision, replay, eviction, write/read failures")
