-- Public offline GUI reconstruction wrapper contract.
local Reconstruct = require("../src/gui_reconstruct")
local files = {
    ["gui/states/state000001.json"] = {schemaVersion = 2, stateId = 1,
        upserts = {{instanceId = 1, properties = {Text = "A"}}}, removes = {}, elementCount = 1},
    ["gui/states/state000002.json"] = {schemaVersion = 2, stateId = 2, baseStateId = 1,
        upserts = {{instanceId = 1, properties = {Text = "B"}},
            {instanceId = 2, properties = {Visible = true}}}, removes = {}, elementCount = 2},
    ["gui/states/state000003.json"] = {schemaVersion = 2, stateId = 3, baseStateId = 2,
        upserts = {}, removes = {2}, elementCount = 1},
}
local context = {read = function(path)
    if files[path] then return "ok", files[path] end
    return "missing"
end}
local state = assert(Reconstruct.reconstruct(context, 3))
assert(state[1].properties.Text == "B" and state[2] == nil)
files["gui/states/state000001.json"].baseStateId = 2
local broken, reason = Reconstruct.reconstruct(context, 3)
assert(broken == nil and (reason == "invalid state chain" or reason == "invalid base state"))
print("GUI reconstruction wrapper OK: baseline, delta, removal and damaged cycle")
