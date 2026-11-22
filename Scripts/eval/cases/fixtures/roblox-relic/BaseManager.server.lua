-- Assigns each player a base and tracks the relic stored in it.
local Players = game:GetService("Players")
local BaseManager = {}
local bases = {}

function BaseManager.assign(player)
    bases[player.UserId] = { owner = player, relic = nil, locked = false }
end

function BaseManager.store(player, relic)
    local base = bases[player.UserId]
    if base and not base.relic then
        base.relic = relic
        return true
    end
    return false
end

Players.PlayerAdded:Connect(BaseManager.assign)
return BaseManager
