-- Controlled client-owned fixture. This script never touches existing game UI
-- or any remotes. activate() can emit a SYNTHETIC Activated only on its own button.
-- Load once before the export, then call getgenv().LesbhubV08GuiFixture.begin().
-- begin invokes only this fixture's own handlers; a real click on its buttons
-- separately tests observation of a real operator Activated signal.
local env = assert(type(getgenv) == "function" and getgenv(), "getgenv unavailable")
assert(env.LesbhubV08GuiFixture == nil, "fixture already installed; clean it up first")
local player = assert(game:GetService("Players").LocalPlayer, "LocalPlayer unavailable")
local playerGui = assert(player:FindFirstChildOfClass("PlayerGui"), "PlayerGui unavailable")
local fixture = Instance.new("ScreenGui")
fixture.Name = "LesbhubV08ControlledFixture"
fixture.ResetOnSpawn = false
fixture.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "FixturePanel"
panel.Size = UDim2.fromOffset(220, 120)
panel.Position = UDim2.fromOffset(30, 100)
panel.Parent = fixture
local label = Instance.new("TextLabel")
label.Name = "FixtureStatus"
label.Size = UDim2.fromOffset(200, 35)
label.Text = "Fixture: initial"
label.Parent = panel
local button = Instance.new("TextButton")
button.Name = "FixtureOpen"
button.Size = UDim2.fromOffset(100, 35)
button.Position = UDim2.fromOffset(0, 45)
button.Text = "Open fixture"
button.Parent = panel
local untouched = Instance.new("TextButton")
untouched.Name = "FixtureUntouched"
untouched.Size = UDim2.fromOffset(100, 35)
untouched.Position = UDim2.fromOffset(105, 45)
untouched.Text = "Untouched"
untouched.Parent = panel
local detail = Instance.new("Frame")
detail.Name = "FixtureDetails"
detail.Size = UDim2.fromOffset(80, 20)
detail.Position = UDim2.fromOffset(0, 90)
detail.Visible = false
detail.Parent = panel
local actions = {}
function actions.open()
    label.Text = "Fixture: opened"
    detail.Visible = true
end
function actions.change()
    label.Text = "Fixture: changed"
    detail.Visible = false
end
function actions.add()
    if panel:FindFirstChild("FixtureAdded") then return end
    local added = Instance.new("TextLabel")
    added.Name = "FixtureAdded"
    added.Text = "Added locally"
    added.Size = UDim2.fromOffset(100, 20)
    added.Position = UDim2.fromOffset(110, 90)
    added.Parent = panel
end
function actions.remove()
    local added = panel:FindFirstChild("FixtureAdded")
    if added then added:Destroy() end
    label.Text = "Fixture: complete"
end
local connection = button.Activated:Connect(actions.open)
local active, finished = true, false
local api = {}
function api.begin()
    assert(active and not api.started, "fixture inactive or already started")
    api.started = true
    task.spawn(function()
        for _, action in ipairs({actions.open, actions.change, actions.add, actions.remove}) do
            task.wait(1.2)
            if not active then return end
            action()
        end
        finished = true
    end)
end
-- Potassium Signal Library: firesignal(signal: RBXScriptSignal, ...).
-- This tests signal observation, not a human click or network causality.
function api.activate()
    assert(active and type(firesignal)=="function","fixture inactive or firesignal unavailable")
    firesignal(button.Activated)
end
function api.status() return {active = active, started = api.started == true, finished = finished} end
function api.cleanup()
    if not active then return end
    active = false
    connection:Disconnect()
    fixture:Destroy()
    if env.LesbhubV08GuiFixture == api then env.LesbhubV08GuiFixture = nil end
end
env.LesbhubV08GuiFixture = api
print("LESBHUB_V08_GUI_FIXTURE_READY")
