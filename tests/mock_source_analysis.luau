-- All inputs are synthetic; analysis never executes the input.
local Analysis = require("../src/source_analysis")
local entry = {robloxPath = "PlayerScripts/Example"}
local code = [==[
-- game:GetService("ReplicatedStorage").Fake:FireServer()
local text = 'game:GetService("ReplicatedStorage").Fake:FireServer()'
local interpolation = `game:GetService("ReplicatedStorage").Fake:FireServer()`
local nested = `outer {`nested {"literal"}`} text`
local root = game["ReplicatedStorage"]
local remote = root:WaitForChild("\x52emote")
remote:FireServer()
remote.OnClientEvent:Connect(function() end)
local module = require(root:WaitForChild("Folder"):WaitForChild("Module"))
local uncertain = root:WaitForChild(dynamicName)
uncertain:FireServer()
local unsupported = root:WaitForChild("\u{52}emote")
unsupported:FireServer()
]==]
local result = Analysis.analyze(code, entry)
assert(#result.remoteReferences == 2, "strings, comments or dynamic paths produced remote hints")
assert(result.remoteReferences[1].pathCandidate == "ReplicatedStorage/Remote")
assert(result.remoteReferences[1].kind == "FireServer")
assert(result.remoteReferences[2].kind == "OnClientEvent")
assert(#result.imports == 1 and result.imports[1].pathCandidate == "ReplicatedStorage/Folder/Module")
assert(result.imports[1].expression == 'require(root:WaitForChild("Folder"):WaitForChild("Module"))')
local escaped = Analysis.analyze('local r=game:GetService("ReplicatedStorage"):WaitForChild("\\082emote"); r:FireServer()', entry)
assert(escaped.remoteReferences[1].pathCandidate == "ReplicatedStorage/Remote")
local dynamic = Analysis.analyze('local r=game:GetService("ReplicatedStorage"):WaitForChild(name); r:FireServer()', entry)
assert(#dynamic.remoteReferences == 0)
local dynamicImport = Analysis.analyze('require(game.ReplicatedStorage.Module or fallback)', entry)
assert(#dynamicImport.imports == 1 and dynamicImport.imports[1].pathCandidate == nil)
local waits = 0
local budget = {checkpoint = function() waits = waits + 1 end}
local huge = string.rep("x", 300000)
local large = Analysis.analyze('local s="' .. huge .. '"; game.Workspace.X:FireServer()', entry, budget)
assert(#large.remoteReferences == 1 and waits > 10, "long strings should be processed cooperatively")
assert(not pcall(Analysis.analyze, '"' .. huge .. '"', entry,
    {checkpoint = function() return false end}), "analysis should stop on cancellation")
local start = os.clock()
local punctuation = Analysis.analyze(string.rep(";", 32000), entry, budget)
assert(punctuation.tokenCount == 32000 and os.clock() - start < 2,
    "punctuation scanning should remain linear")
print("Source analysis OK: conservative lexical hints and bounded scanning")
