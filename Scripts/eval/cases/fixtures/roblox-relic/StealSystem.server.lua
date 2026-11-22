-- Lets a player steal the relic from another player's unlocked base.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StealRelic = ReplicatedStorage:WaitForChild("StealRelic")

StealRelic.OnServerEvent:Connect(function(thief, victimBase)
    if victimBase.locked or not victimBase.relic then
        return
    end
    local relic = victimBase.relic
    victimBase.relic = nil
    thief:SetAttribute("CarryingRelic", relic.Name)
end)
