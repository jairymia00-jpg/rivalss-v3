-- Nightfall BloxStrike v1.3.0 - configurable aim controls and global character tracking
-- F1: menu | F6: save profile | F8: copy live trace | F10: full unload
-- Aim tab: Hold/Toggle plus changeable keyboard/mouse binding. No weapon recoil modification.
-- Blue = teammate, pink = enemy, amber = team not yet known.
-- Blue teammates, pink enemies. Unverified positions can be hidden or labelled.
-- Live BloxStrike/executor compatibility must be verified in Roblox.
-- No external scripts or UI libraries are downloaded by this file.

local Core = (function()
-- Original Nightfall logic. This module is also exercised by the offline tests.
local Core = {}
Core.Version = "1.3.0"
Core.Schema = {
    AimEnabled = {"boolean", true},
    AimMode = {"enum", "Hold", {"Hold", "Toggle"}},
    AimBind = {"bind", "MouseButton2"},
    AimFOV = {"number", 150, 25, 500, 1},
    AimSmooth = {"number", 0, 0, 20, 1},
    AimPriority = {"enum", "Crosshair", {"Crosshair", "Distance"}},
    AimVisibleOnly = {"boolean", true},
    AimSticky = {"boolean", true},
    AimDistance = {"number", 2000, 50, 5000, 50},
    ShowFOV = {"boolean", true},
    ESPEnabled = {"boolean", true},
    ESPMode = {"enum", "Toggle", {"Toggle", "Hold"}},
    ESPBind = {"bind", "F4"},
    ESPBoxes = {"boolean", true},
    ESPNames = {"boolean", true},
    ESPHealth = {"boolean", true},
    ESPDistance = {"boolean", true},
    ESPSkeleton = {"boolean", false},
    ESPTracers = {"boolean", false},
    ESPOutline = {"boolean", true},
    ESPThroughWalls = {"boolean", true},
    GlobalSearch = {"boolean", true},
    ESPOffscreen = {"boolean", true},
    UnverifiedPositions = {"enum", "Hide", {"Hide", "Label", "Show"}},
    PositionTimeout = {"number", 3, 1, 15, 1},
    ESPTeammates = {"boolean", true},
    ShowHeadDot = {"boolean", true},
    HeadDotSize = {"number", 8, 4, 18, 1},
    ESPDistanceLimit = {"number", 3000, 50, 6000, 50},
    IncludePlayers = {"boolean", true},
    IncludeBots = {"boolean", true},
    AllowUnknownTeams = {"boolean", false},
    TeamMode = {"enum", "Auto", {"Auto", "Teams", "FFA"}},
    LocalTeamOverride = {"enum", "Auto", {"Auto", "CT", "T"}},
    CharacterSource = {"enum", "Auto", {"Auto", "Player.Character", "World rigs"}},
    Theme = {"enum", "Violet", {"Violet", "Cyan", "Crimson", "Amber"}},
    WindowScale = {"number", 1, 0.7, 1.2, 0.05},
    WindowX = {"number", 0.5, 0, 1, 0.001},
    WindowY = {"number", 0.5, 0, 1, 0.001},
    ShowHUD = {"boolean", true},
}

function Core.finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Core.value(key, value)
    local rule = Core.Schema[key]
    if not rule then return nil end
    if rule[1] == "boolean" then
        if type(value) == "boolean" then return value end
    elseif rule[1] == "number" then
        if Core.finite(value) then
            local result = math.clamp(value, rule[3], rule[4])
            result = math.floor(result / rule[5] + 0.5) * rule[5]
            return math.clamp(result, rule[3], rule[4])
        end
    elseif rule[1] == "bind" then
        if type(value) == "string" and #value <= 32 and value:match("^[%a][%w_]*$")
            and not ({F1=true,F6=true,F8=true,F10=true,Escape=true,Unknown=true})[value] then
            if value:match("^MouseButton[123]$") then return value end
            local ok, item = pcall(function() return Enum.KeyCode[value] end)
            if ok and item ~= nil then return value end
        end
    elseif rule[1] == "enum" then
        for _, item in ipairs(rule[3]) do
            if value == item then return value end
        end
    end
    return rule[2]
end

function Core.settings(raw)
    local result = {}
    raw = type(raw) == "table" and raw or {}
    for key in pairs(Core.Schema) do result[key] = Core.value(key, raw[key]) end
    if result.AimBind == result.ESPBind then result.ESPBind = result.AimBind == "F4" and "F5" or "F4" end
    return result
end

function Core.flag(value)
    return value == true or value == 1 or value == "true" or value == "True"
end

function Core.team(value)
    if type(value) == "number" and Core.finite(value) then return "id:" .. tostring(value) end
    if type(value) ~= "string" then return nil end
    local numeric = tonumber(value)
    if numeric and Core.finite(numeric) then return "id:" .. tostring(numeric) end
    local normalized = string.lower(value):gsub("[^%w]", "")
    if normalized == "ct" or normalized == "counterterrorist" or normalized == "counterterrorists" then
        return "CT"
    end
    if normalized == "t" or normalized == "terrorist" or normalized == "terrorists" then return "T" end
    if normalized == "" or normalized == "none" or normalized == "spectator"
        or normalized == "spectators" or normalized == "neutral" or normalized == "unassigned"
        or normalized == "lobby" then return nil end
    return normalized
end

function Core.ffa(mode, explicit, override)
    if override == "FFA" then return true end
    if override == "Teams" then return false end
    if explicit == true then return true end
    local normalized = string.lower(tostring(mode or "")):gsub("[^%w]", "")
    -- Team Deathmatch must not accidentally match Deathmatch.
    return normalized == "deathmatch" or normalized == "ffa" or normalized == "freeforall"
end

function Core.life(modelHealth, ownerHealth, humanoidHealth, maximum, modelDead, ownerDead)
    -- A custom character's live model attributes take priority over stale player/Humanoid data.
    local health = Core.finite(modelHealth) and modelHealth
        or (Core.finite(ownerHealth) and ownerHealth)
        or (Core.finite(humanoidHealth) and humanoidHealth) or nil
    local deadFlag = modelDead
    if deadFlag == nil then deadFlag = ownerDead end
    local dead = Core.flag(deadFlag) or (health ~= nil and health <= 0)
    local known = health ~= nil or modelDead == false or ownerDead == false
    local maxHealth = Core.finite(maximum) and maximum > 0 and maximum or nil
    if health and maxHealth then health = math.clamp(health, 0, maxHealth) end
    return {health = health, maximum = maxHealth, alive = not dead, known = known}
end

function Core.relation(team, localTeam, freeForAll)
    if freeForAll then return "enemy" end
    if team == nil or localTeam == nil then return "unknown" end
    return team == localTeam and "friendly" or "enemy"
end

function Core.eligible(row, settings, purpose)
    if row.self then return false, "self" end
    if row.bot and not settings.IncludeBots then return false, "bots off" end
    if not row.bot and not settings.IncludePlayers then return false, "players off" end
    if not row.alive then return false, "dead" end
    if purpose == "aim" and row.positionUncertain then return false, "position unverified" end
    if purpose == "aim" and not row.lifeKnown then return false, "health unknown" end
    if row.relation == "friendly" and (purpose == "aim" or not settings.ESPTeammates) then
        return false, "teammate"
    end
    if purpose == "aim" and row.relation == "unknown" and not settings.AllowUnknownTeams then
        return false, "team unknown"
    end
    return true
end

function Core.bindLabel(name)
    return ({MouseButton1="Left click",MouseButton2="Right click",MouseButton3="Middle click"})[name] or name
end

function Core.edgePoint(x, y, z, width, height, margin)
    if not (Core.finite(x) and Core.finite(y) and Core.finite(z)) then return nil end
    local dx, dy = x - width / 2, y - height / 2
    if z < 0 then dx, dy = -dx, -dy end
    if math.abs(dx) + math.abs(dy) < 0.001 then dx, dy = 0, -1 end
    local scale = math.min(math.max(1, width / 2 - margin) / math.max(math.abs(dx), 0.001),
        math.max(1, height / 2 - margin) / math.max(math.abs(dy), 0.001))
    return width / 2 + dx * scale, height / 2 + dy * scale, math.deg(math.atan2(dy, dx)) + 90
end

function Core.relationStyle(relation)
    if relation == "friendly" then return 70, 155, 255, "TEAM" end
    if relation == "enemy" then return 255, 90, 180, "ENEMY" end
    return 255, 195, 80, "TEAM ?"
end

function Core.pick(rows, settings, visible, sticky)
    local candidates = {}
    for _, row in ipairs(rows) do
        if Core.eligible(row, settings, "aim") and row.onScreen and row.hasPart
            and Core.finite(row.screenDistance) and Core.finite(row.distance)
            and row.screenDistance <= settings.AimFOV and row.distance <= settings.AimDistance then
            candidates[#candidates + 1] = row
        end
    end
    table.sort(candidates, function(a, b)
        local as = settings.AimPriority == "Distance" and a.distance or a.screenDistance
        local bs = settings.AimPriority == "Distance" and b.distance or b.screenDistance
        if as == bs then return a.screenDistance < b.screenDistance end
        return as < bs
    end)
    local function canSee(row)
        return not settings.AimVisibleOnly or visible(row) == true
    end
    if settings.AimSticky and sticky then
        for _, row in ipairs(candidates) do
            if row.model == sticky and canSee(row) then return row end
        end
    end
    for _, row in ipairs(candidates) do if canSee(row) then return row end end
    return nil
end

function Core.alpha(smoothing, delta)
    if not Core.finite(delta) or delta <= 0 then return 0 end
    if smoothing <= 0 then return 1 end
    return 1 - math.exp(-(90 / smoothing) * math.min(delta, 0.1))
end

function Core.action(key, typing)
    if key == "F10" then return "unload" end
    if typing then return nil end
    if key == "F1" then return "menu" end
    if key == "F6" then return "save" end
    if key == "F8" then return "diagnostics" end
    return nil
end

return Core

end)()

local Resources = (function()
-- Own only this script's resources. Cleanup is idempotent and continues on error.
local Resources = {}
Resources.__index = Resources

function Resources.new()
    return setmetatable({alive = true, disposers = {}}, Resources)
end

function Resources:give(dispose)
    assert(type(dispose) == "function", "Expected cleanup function")
    if self.alive then self.disposers[#self.disposers + 1] = dispose
    else pcall(dispose) end
    return dispose
end

function Resources:clean()
    if not self.alive then return 0 end
    self.alive = false
    local failures = 0
    for index = #self.disposers, 1, -1 do
        local dispose = self.disposers[index]
        self.disposers[index] = nil
        if not pcall(dispose) then failures += 1 end
    end
    return failures
end

return Resources

end)()

local makeAdapter = (function()
-- Read-only character discovery. No game modules, remotes, or character mutations.
return function(services, Core)
    local Players, World, Me = services.Players, services.Workspace, services.Player
    local Adapter = {records = {}, candidates = {}, folder = nil, folderPath = "waiting",
        truncated = false, duplicateOwners = 0, sourceMode = "Auto"}
    Adapter.globalModels = setmetatable({}, {__mode = "k"})
    function Adapter:start(resources)
        local added = World.DescendantAdded:Connect(function(item)
            if item:IsA("Model") then self.globalModels[item] = true end
        end)
        local removed = World.DescendantRemoving:Connect(function(item)
            if item:IsA("Model") then self.globalModels[item] = nil end
        end)
        resources:give(function() added:Disconnect() removed:Disconnect() table.clear(self.globalModels) end)
    end

    function Adapter:indexWorld()
        if self.indexed then return end
        self.indexed = true
        for _, item in ipairs(World:GetDescendants()) do
            if item:IsA("Model") then self.globalModels[item] = true end
        end
    end
    local ownersByName, ownersById = {}, {}
    local bodyNames = {
        Head = true, HumanoidRootPart = true, Torso = true, UpperTorso = true, LowerTorso = true,
        ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
        LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
        RightUpperArm = true, RightLowerArm = true, RightHand = true,
        LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
        RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    }
    local boneLinks = {
        {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
        {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
        {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
        {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
        {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
        {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
        {"Torso", "Left Leg"}, {"Torso", "Right Leg"},
    }
    local function numeric(value)
        local result = tonumber(value)
        return Core.finite(result) and result or nil
    end
    local function part(model, names)
        for _, name in ipairs(names) do
            local item = model:FindFirstChild(name, true)
            if item and item:IsA("BasePart") then return item end
        end
        return nil
    end

    local function inWorld(model)
        return model ~= nil and model:IsDescendantOf(World)
    end

    function Adapter:usable(record)
        return inWorld(record.model) and record.root ~= nil and record.root:IsDescendantOf(record.model)
    end

    function Adapter:refreshParts(record)
        -- Streamed-out ancestors can retain children and readable, obsolete Position values.
        if not inWorld(record.model) then return false end
        if not record.root or not record.root:IsDescendantOf(record.model) then
            record.root = part(record.model, {"HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso", "RootPart"})
        end
        if not record.head or not record.head:IsDescendantOf(record.model) then
            record.head = part(record.model, {"Head"})
        end
        return record.root ~= nil and record.head ~= nil
    end

    function Adapter:owner(model)
        local found = Players:GetPlayerFromCharacter(model)
        if found then return found end
        for _, key in ipairs({"Player", "Owner"}) do
            local reference = model:FindFirstChild(key)
            if reference and reference:IsA("ObjectValue") and reference.Value
                and reference.Value:IsA("Player") then return reference.Value end
        end
        local id = numeric(model:GetAttribute("UserId") or model:GetAttribute("PlayerUserId")
            or model:GetAttribute("OwnerUserId") or model.Name)
        local name = model:GetAttribute("PlayerName") or model:GetAttribute("OwnerName")
        return (id and ownersById[id]) or (name and ownersByName[name]) or ownersByName[model.Name]
    end

    local function teamValue(value)
        if typeof(value) == "Instance" then
            return value:IsA("Team") and Core.team(value.Name) or nil
        end
        if typeof(value) == "BrickColor" or typeof(value) == "Color3" then
            for _, team in ipairs(services.Teams:GetTeams()) do
                if value == team.TeamColor or value == team.TeamColor.Color then return Core.team(team.Name) end
            end
            return nil
        end
        return Core.team(value)
    end
    local function teamField(node)
        if not node then return nil end
        for _, key in ipairs({"Team", "TeamName", "TeamId", "TeamID", "Side", "Faction"}) do
            local result = teamValue(node:GetAttribute(key))
            if result then return result end
            local child = node:FindFirstChild(key)
            if child and child:IsA("ValueBase") then
                result = teamValue(child.Value)
                if result then return result end
            end
        end
        return nil
    end
    local function numberField(node, names)
        if not node then return nil end
        for _, name in ipairs(names) do
            local result = numeric(node:GetAttribute(name))
            if result ~= nil then return result end
            local child = node:FindFirstChild(name)
            if child and child:IsA("ValueBase") then
                result = numeric(child.Value)
                if result ~= nil then return result end
            end
        end
        return nil
    end
    function Adapter:team(model, owner)
        local result = teamField(model) or teamField(owner)
        if result then return result end
        if owner and not owner.Neutral and owner.Team then
            result = Core.team(owner.Team.Name)
            if result then return result end
        end
        local node = model.Parent
        while node and node ~= World do
            result = teamField(node)
            if result then return result end
            result = Core.team(node.Name)
            if result == "CT" or result == "T" or services.Teams:FindFirstChild(node.Name) then return result end
            node = node.Parent
        end
        local skin = model:GetAttribute("CharacterName")
        if skin ~= nil then
            local ct, t = World:GetAttribute("CTCharacter"), World:GetAttribute("TCharacter")
            if ct ~= t then
                if ct ~= nil and skin == ct then return "CT" end
                if t ~= nil and skin == t then return "T" end
            end
        end
        return teamValue(model:GetAttribute("TeamColor"))
    end

    function Adapter:life(record)
        local model, owner, humanoid = record.model, record.owner, record.humanoid
        if not inWorld(model) then return {alive = false, known = true} end
        local maximum = numberField(model, {"MaxHealth", "MaxHP"})
            or numberField(owner, {"MaxHealth", "MaxHP"})
            or (humanoid and humanoid.MaxHealth)
        return Core.life(numberField(model, {"Health", "HP"}),
            numberField(owner, {"Health", "HP"}), humanoid and humanoid.Health,
            maximum, model:GetAttribute("Dead"), owner and owner:GetAttribute("Dead"))
    end

    function Adapter:scan(settings)
        self.sourceMode = settings and settings.CharacterSource or "Auto"
        self.globalActive = settings and settings.GlobalSearch == true or false
        table.clear(ownersByName)
        table.clear(ownersById)
        for _, owner in ipairs(Players:GetPlayers()) do
            ownersByName[owner.Name], ownersById[owner.UserId] = owner, owner
        end
        local folders, visited = {}, {}
        for _, parent in ipairs({World, World:FindFirstChild("Entities") or World}) do
            for _, name in ipairs({"Characters", "characters", "Players", "Bots", "NPCs", "Live", "Alive"}) do
                local folder = parent:FindFirstChild(name)
                if folder and not visited[folder] then
                    visited[folder] = true
                    folders[#folders + 1] = folder
                end
            end
        end
        self.folder = folders[1]
        local paths = {}
        for _, folder in ipairs(folders) do paths[#paths + 1] = folder:GetFullName() end
        self.folderPath = #paths > 0 and table.concat(paths, "; ") or "Player.Character fallback"
        self.truncated = false
        local found, candidates, groups = {}, {}, {}
        local function consider(model, inFolder)
            if not model:IsA("Model") or candidates[model] or not inWorld(model) then return end
            local camera = World.CurrentCamera
            if camera and model:IsDescendantOf(camera) then return end
            local owner = self:owner(model)
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local health = numberField(model, {"Health", "HP"})
            if not owner and not humanoid and health == nil then return end
            local head = part(model, {"Head"})
            local root = part(model, {"HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso", "RootPart"})
            if not head or not root then return end
            local record = self.candidates[model] or {model = model}
            record.firstSeenAt = record.firstSeenAt or os.clock()
            record.owner, record.humanoid, record.head, record.root = owner, humanoid, head, root
            record.inFolder = inFolder
            record.isCharacter = owner ~= nil and owner.Character == model
            record.bot = owner == nil
            record.self = owner == Me or model == Me.Character or model.Name == Me.Name
            record.name = owner and owner.DisplayName or model.Name
            record.body, record.bones = {}, {}
            local byName = {}
            for _, item in ipairs(model:GetDescendants()) do
                if item:IsA("BasePart") and bodyNames[item.Name] then
                    record.body[#record.body + 1] = item
                    byName[item.Name] = item
                end
            end
            for _, pair in ipairs(boneLinks) do
                if byName[pair[1]] and byName[pair[2]] then
                    record.bones[#record.bones + 1] = {byName[pair[1]], byName[pair[2]]}
                end
            end
            local generation = owner and owner.Character or nil
            if record.generation ~= generation or not record.rootAnchor or record.rootRef ~= root then
                record.generation, record.rootRef = generation, root
                record.rootAnchor, record.headAnchor = root.Position, head.Position
                record.observedMotion, record.motionAt = false, nil
                record.firstSeenAt, record.seenAt = os.clock(), nil
                record.sampleRoot, record.sampleHead, record.rayAt = nil, nil, nil
            end
            local rootDelta = (root.Position - record.rootAnchor).Magnitude
            local headDelta = (head.Position - record.headAnchor).Magnitude
            if (Core.finite(rootDelta) and rootDelta > 0.25) or (Core.finite(headDelta) and headDelta > 2) then
                record.observedMotion, record.motionAt = true, os.clock()
                record.rootAnchor, record.headAnchor = root.Position, head.Position
            end
            candidates[model] = record
            if owner then
                local group = groups[owner] or {}
                groups[owner] = group
                group[#group + 1] = record
            else found[model] = record end
        end
        local scanned = 0
        for _, folder in ipairs(folders) do
            local descendants = folder:GetDescendants()
            local count = math.min(#descendants, math.max(0, 12000 - scanned))
            if count < #descendants then self.truncated = true end
            for index = 1, count do consider(descendants[index], true) end
            scanned += count
        end
        for _, owner in ipairs(Players:GetPlayers()) do
            -- Always compare the actual Character, even if a namesake spawn copy was found first.
            if owner.Character then consider(owner.Character, false) end
        end
        if settings and settings.GlobalSearch then
            self:indexWorld()
            local count = 0
            for model in pairs(self.globalModels) do
                if count >= 6000 then self.truncated = true break end
                consider(model, false)
                count += 1
            end
        end
        self.duplicateOwners = 0
        for owner, group in pairs(groups) do
            if #group > 1 then self.duplicateOwners += 1 end
            local best, bestScore
            for _, record in ipairs(group) do
                local life = self:life(record)
                local score = (life.alive and 10000 or 0) + (record.isCharacter and 200 or 0)
                    + (record.inFolder and 20 or 0)
                if self.sourceMode == "Player.Character" then
                    score = score + (record.isCharacter and 2000 or 0)
                elseif self.sourceMode == "World rigs" then
                    score = score + (not record.isCharacter and 2000 or 0)
                else
                    -- Motion is evidence for choosing between duplicates, never a position prediction.
                    -- Remember it after the player stops; a stationary player must not jump back to spawn.
                    score = score + (record.observedMotion and 400 or 0)
                end
                if not bestScore or score > bestScore
                    or (score == bestScore and self.records[record.model] ~= nil) then
                    best, bestScore = record, score
                end
            end
            if best then
                best.source = best.isCharacter and "Player.Character" or "World rig"
                best.alternatives = #group - 1
                found[best.model] = best
            end
        end
        self.records, self.candidates = found, candidates
        return found
    end

    function Adapter:diagnostics()
        local result = {}
        for model, record in pairs(self.candidates) do
            if #result >= 100 then break end
            if not record.self and self:usable(record) then
                local root, head = record.root.Position, record.head.Position
                result[#result + 1] = {
                    name = record.name, path = model:GetFullName(), selected = self.records[model] ~= nil,
                    currentCharacter = record.isCharacter, inCharacterFolder = record.inFolder,
                    motionObserved = record.observedMotion,
                    lastVisibleSecondsAgo = record.seenAt and (os.clock() - record.seenAt) or nil,
                    team = self:team(model, record.owner),
                    modelTeam = tostring(model:GetAttribute("Team")),
                    playerTeam = record.owner and tostring(record.owner:GetAttribute("Team")) or nil,
                    nativeTeam = record.owner and record.owner.Team and record.owner.Team.Name or nil,
                    secondsSinceMotion = record.motionAt and (os.clock() - record.motionAt) or nil,
                    root = {x = root.X, y = root.Y, z = root.Z}, head = {x = head.X, y = head.Y, z = head.Z},
                }
            end
        end
        return {mode = self.sourceMode, globalSearch = self.globalActive,
            duplicatePlayers = self.duplicateOwners, candidates = result,
            note = "Client observations only. No motion can also mean a stationary player."}
    end

    function Adapter:localContext(settings)
        local model = Me.Character
        for _, record in pairs(self.records) do
            if record.self and self:usable(record) then model = record.model break end
        end
        local localTeam = (model and self:team(model, Me)) or teamField(Me)
            or (not Me.Neutral and Me.Team and Core.team(Me.Team.Name)) or nil
        if settings.LocalTeamOverride ~= "Auto" then localTeam = settings.LocalTeamOverride end
        local mode = World:GetAttribute("Gamemode") or World:GetAttribute("GameMode") or "unknown"
        local freeForAll = Core.ffa(mode, World:GetAttribute("FreeForAll"), settings.TeamMode)
        local localAlive = inWorld(model)
        if model then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local life = Core.life(numberField(model, {"Health", "HP"}), numberField(Me, {"Health", "HP"}),
                humanoid and humanoid.Health, nil, model:GetAttribute("Dead"), Me:GetAttribute("Dead"))
            localAlive = localAlive and life.alive
        end
        return model, localTeam, freeForAll, tostring(mode), localAlive
    end

    function Adapter:aimPart(record)
        if not self:refreshParts(record) then return nil end
        return record.head
    end

    return Adapter
end

end)()

local makeUI = (function()
-- Original native Roblox UI. No external library, Drawing dependency, or HTTP requests.
return function(App)
    local UI = {refreshers = {}, accents = {}, tabs = {}, status = {}, selected = "Overview"}
    local C = {
        Background = Color3.fromRGB(13, 15, 23), Panel = Color3.fromRGB(19, 22, 33),
        Raised = Color3.fromRGB(26, 30, 44), Border = Color3.fromRGB(43, 48, 66),
        Text = Color3.fromRGB(237, 240, 249), Muted = Color3.fromRGB(139, 149, 172),
        Green = Color3.fromRGB(89, 218, 166), Amber = Color3.fromRGB(246, 191, 91),
        Red = Color3.fromRGB(248, 112, 137),
    }
    local themes = {
        Violet = Color3.fromRGB(164, 133, 255), Cyan = Color3.fromRGB(90, 218, 239),
        Crimson = Color3.fromRGB(249, 112, 145), Amber = Color3.fromRGB(246, 191, 91),
    }
    local ordering = setmetatable({}, {__mode = "k"})
    local function new(class, properties, parent)
        local object = Instance.new(class)
        for key, value in pairs(properties or {}) do object[key] = value end
        if parent and object:IsA("GuiObject") and (not properties or properties.LayoutOrder == nil) then
            ordering[parent] = (ordering[parent] or 0) + 1
            object.LayoutOrder = ordering[parent]
        end
        object.Parent = parent
        return object
    end
    local function round(object, radius)
        new("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, object)
    end
    local function stroke(object, color, thickness)
        return new("UIStroke", {Color = color or C.Border, Thickness = thickness or 1}, object)
    end
    local function text(parent, value, size, color, properties)
        local data = {
            Text = value, TextSize = size or 13, TextColor3 = color or C.Text,
            Font = Enum.Font.Gotham, BackgroundTransparency = 1,
            BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, 0, 0, 24),
        }
        for key, item in pairs(properties or {}) do data[key] = item end
        return new("TextLabel", data, parent)
    end
    local function accent(object, property)
        UI.accents[#UI.accents + 1] = {object, property}
        object[property] = themes[App.Settings.Theme]
        return object
    end
    local function button(parent, caption, callback)
        local result = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.Raised,
            BorderSizePixel = 0, Text = caption, TextColor3 = C.Text,
            TextSize = 12, Font = Enum.Font.GothamMedium, AutoButtonColor = false,
        }, parent)
        round(result, 7)
        stroke(result)
        App:Connect(result.MouseButton1Click, callback)
        App:Connect(result.MouseEnter, function() result.BackgroundColor3 = Color3.fromRGB(35, 39, 56) end)
        App:Connect(result.MouseLeave, function() result.BackgroundColor3 = C.Raised end)
        return result
    end

    local gui = App:Own(Instance.new("ScreenGui"))
    gui.Name = "Nightfall_BloxStrike_" .. App.Id
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 100000
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = App.GuiParent
    UI.Gui = gui
    local canvas = new("Frame", {
        Name = "WorldOverlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        ClipsDescendants = true, BorderSizePixel = 0, Active = false, ZIndex = 1,
    }, gui)
    UI.Canvas = canvas
    local circle = new("Frame", {
        Name = "AimFOV", AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
    }, canvas)
    new("UICorner", {CornerRadius = UDim.new(1, 0)}, circle)
    local circleStroke = stroke(circle, themes[App.Settings.Theme], 1)
    UI.Circle, UI.CircleStroke = circle, circleStroke

    local hud = new("Frame", {
        Name = "SessionHUD", Position = UDim2.fromOffset(18, 18),
        Size = UDim2.fromOffset(470, 32), BackgroundColor3 = C.Background,
        BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 5,
    }, gui)
    round(hud, 8)
    accent(stroke(hud), "Color")
    UI.HUD = hud
    UI.HUDText = text(hud, "NIGHTFALL  /  waiting for character data", 11, C.Muted, {
        Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Font = Enum.Font.Code,
    })

    local main = new("Frame", {
        Name = "Menu", Size = UDim2.fromOffset(820, 550), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.Background,
        BorderSizePixel = 0, ZIndex = 20, Active = true,
    }, gui)
    round(main, 14)
    stroke(main, Color3.fromRGB(57, 60, 83))
    UI.Main, UI.Scale = main, new("UIScale", {Scale = 1}, main)
    local sidebar = new("Frame", {
        Size = UDim2.new(0, 176, 1, -2), Position = UDim2.fromOffset(1, 1),
        BackgroundColor3 = Color3.fromRGB(17, 19, 29), BorderSizePixel = 0,
    }, main)
    round(sidebar, 13)
    new("Frame", {Position = UDim2.new(1, -1, 0, 14), Size = UDim2.new(0, 1, 1, -28),
        BackgroundColor3 = C.Border, BorderSizePixel = 0}, sidebar)
    local logo = new("Frame", {Position = UDim2.fromOffset(18, 20), Size = UDim2.fromOffset(38, 38),
        BackgroundColor3 = Color3.fromRGB(35, 30, 57), BorderSizePixel = 0}, sidebar)
    round(logo, 10)
    accent(stroke(logo), "Color")
    accent(text(logo, "NF", 17, nil, {TextXAlignment = Enum.TextXAlignment.Center,
        Font = Enum.Font.GothamBold, Size = UDim2.fromScale(1, 1)}), "TextColor3")
    text(sidebar, "NIGHTFALL", 14, C.Text, {Position = UDim2.fromOffset(65, 20),
        Size = UDim2.fromOffset(103, 21), Font = Enum.Font.GothamBold})
    text(sidebar, "BLOXSTRIKE", 10, C.Muted, {Position = UDim2.fromOffset(65, 40),
        Size = UDim2.fromOffset(103, 17), Font = Enum.Font.Code})
    text(sidebar, "WORKSPACE", 10, C.Muted, {Position = UDim2.fromOffset(20, 84),
        Size = UDim2.fromOffset(140, 20), Font = Enum.Font.GothamBold})
    local descriptions = {
        Overview = "Live session and data availability", Aim = "RMB targeting and camera control",
        Visuals = "Player and bot overlays", Targets = "Who appears and who can be selected",
        Profiles = "Save, restore, and personalize",
    }
    local pageTitle = text(main, "Overview", 23, C.Text, {Position = UDim2.fromOffset(198, 17),
        Size = UDim2.fromOffset(385, 30), Font = Enum.Font.GothamBold})
    local pageDescription = text(main, descriptions.Overview, 11, C.Muted, {
        Position = UDim2.fromOffset(199, 47), Size = UDim2.fromOffset(440, 20)})
    local drag = new("TextButton", {Text = "", Modal = true, AutoButtonColor = false,
        BackgroundTransparency = 1, Position = UDim2.fromOffset(180, 0),
        Size = UDim2.new(1, -302, 0, 72), BorderSizePixel = 0}, main)
    UI.Modal = drag
    App:Connect(drag.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            UI.windowDrag = {point = input.Position, x = main.AbsolutePosition.X + main.AbsoluteSize.X / 2,
                y = main.AbsolutePosition.Y + main.AbsoluteSize.Y / 2}
        end
    end)
    local hide = button(main, "F1", function() App:SetMenu(not App.MenuOpen) end)
    hide.Position, hide.Size = UDim2.fromOffset(706, 22), UDim2.fromOffset(43, 30)
    local close = button(main, "F10", function() App:Destroy("F10 / unload button") end)
    close.Position, close.Size = UDim2.fromOffset(757, 22), UDim2.fromOffset(45, 30)
    close.TextColor3 = C.Red

    new("Frame", {Position = UDim2.fromOffset(196, 80), Size = UDim2.new(1, -218, 0, 1),
        BackgroundColor3 = C.Border, BorderSizePixel = 0}, main)
    text(sidebar, "LOCAL SESSION", 10, C.Muted, {Position = UDim2.new(0, 20, 1, -78),
        Size = UDim2.fromOffset(140, 18), Font = Enum.Font.GothamBold})
    UI.SideStatus = text(sidebar, "Waiting for data", 11, C.Amber, {
        Position = UDim2.new(0, 20, 1, -57), Size = UDim2.fromOffset(140, 18)})
    text(sidebar, "v" .. App.Core.Version .. "  /  PC", 10, C.Muted, {
        Position = UDim2.new(0, 20, 1, -32), Size = UDim2.fromOffset(140, 18), Font = Enum.Font.Code})
    UI.Footer = text(main, "F6 saves settings", 10, C.Muted, {
        Position = UDim2.new(0, 198, 1, -30), Size = UDim2.fromOffset(360, 20), Font = Enum.Font.Code})
    text(main, "F1 MENU   F6 SAVE   F10 UNLOAD", 10, C.Muted, {
        Position = UDim2.new(1, -265, 1, -30), Size = UDim2.fromOffset(245, 20),
        TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.Code})

    local nav = {}
    local function selectTab(name)
        UI.selected = name
        pageTitle.Text, pageDescription.Text = name, descriptions[name]
        for key, item in pairs(UI.tabs) do item.page.Visible = key == name end
        for key, item in pairs(nav) do
            item.button.BackgroundColor3 = key == name and C.Raised or Color3.fromRGB(17, 19, 29)
            item.label.TextColor3 = key == name and C.Text or C.Muted
            item.marker.Visible = key == name
        end
    end
    for index, name in ipairs({"Overview", "Aim", "Visuals", "Targets", "Profiles"}) do
        local navButton = new("TextButton", {Text = "", AutoButtonColor = false,
            Position = UDim2.fromOffset(12, 111 + (index - 1) * 44), Size = UDim2.fromOffset(151, 38),
            BackgroundColor3 = C.Raised, BorderSizePixel = 0}, sidebar)
        round(navButton, 8)
        local marker = new("Frame", {Position = UDim2.fromOffset(0, 9), Size = UDim2.fromOffset(3, 20),
            BackgroundColor3 = themes[App.Settings.Theme], BorderSizePixel = 0}, navButton)
        accent(marker, "BackgroundColor3")
        local label = text(navButton, name, 12, C.Text, {Position = UDim2.fromOffset(36, 0),
            Size = UDim2.new(1, -43, 1, 0), Font = Enum.Font.GothamMedium})
        text(navButton, string.format("%02d", index), 10, C.Muted, {Position = UDim2.fromOffset(13, 0),
            Size = UDim2.fromOffset(22, 38), Font = Enum.Font.Code})
        nav[name] = {button = navButton, label = label, marker = marker}
        App:Connect(navButton.MouseButton1Click, function() selectTab(name) end)
        local page = new("ScrollingFrame", {Name = name, Position = UDim2.fromOffset(198, 96),
            Size = UDim2.new(1, -218, 1, -140), BackgroundTransparency = 1,
            BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.Muted,
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false}, main)
        local columns = {}
        for column = 1, 2 do
            columns[column] = new("Frame", {Position = UDim2.new((column - 1) * 0.5, (column - 1) * 5, 0, 0),
                Size = UDim2.new(0.5, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, BorderSizePixel = 0}, page)
            new("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, columns[column])
            new("UIPadding", {PaddingBottom = UDim.new(0, 6)}, columns[column])
        end
        UI.tabs[name] = {page = page, columns = columns}
    end
    local function card(tab, column, caption)
        local result = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = C.Panel, BorderSizePixel = 0}, UI.tabs[tab].columns[column])
        round(result, 10)
        stroke(result)
        new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
            PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 10)}, result)
        new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, result)
        accent(text(result, string.upper(caption), 10, nil, {Size = UDim2.new(1, 0, 0, 27),
            Font = Enum.Font.GothamBold, LayoutOrder = -10}), "TextColor3")
        return result
    end
    local function note(parent, caption, height)
        return text(parent, caption, 11, C.Muted, {TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None, Size = UDim2.new(1, 0, 0, height or 42)})
    end
    local function toggle(parent, key, caption, explanation)
        local row = new("Frame", {Size = UDim2.new(1, 0, 0, explanation and 48 or 36),
            BackgroundTransparency = 1, BorderSizePixel = 0}, parent)
        text(row, caption, 12, C.Text, {Size = UDim2.new(1, -55, 0, explanation and 24 or 36)})
        if explanation then text(row, explanation, 9, C.Muted, {
            Position = UDim2.fromOffset(0, 23), Size = UDim2.new(1, -4, 0, 20)}) end
        local switch = new("TextButton", {Text = "", Size = UDim2.fromOffset(36, 20),
            Position = UDim2.new(1, -36, 0, explanation and 3 or 8),
            BackgroundColor3 = C.Border, BorderSizePixel = 0, AutoButtonColor = false}, row)
        round(switch, 10)
        local dot = new("Frame", {Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(3, 3),
            BackgroundColor3 = C.Text, BorderSizePixel = 0}, switch)
        round(dot, 7)
        UI.refreshers[#UI.refreshers + 1] = function()
            local on = App.Settings[key]
            switch.BackgroundColor3 = on and themes[App.Settings.Theme] or C.Border
            dot.Position = UDim2.fromOffset(on and 19 or 3, 3)
            dot.BackgroundColor3 = on and C.Background or C.Muted
        end
        App:Connect(switch.MouseButton1Click, function() App:Set(key, not App.Settings[key]) end)
    end
    local function slider(parent, key, caption, suffix)
        local rule = App.Core.Schema[key]
        local row = new("Frame", {Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1,
            BorderSizePixel = 0}, parent)
        text(row, caption, 12, C.Text, {Size = UDim2.new(1, -68, 0, 25)})
        local value = text(row, "", 11, C.Muted, {Position = UDim2.new(1, -75, 0, 0),
            Size = UDim2.fromOffset(75, 25), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.Code})
        local bar = new("TextButton", {Text = "", Position = UDim2.fromOffset(0, 27),
            Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, BorderSizePixel = 0,
            AutoButtonColor = false}, row)
        local track = new("Frame", {Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 4),
            BackgroundColor3 = C.Border, BorderSizePixel = 0}, bar)
        round(track, 2)
        local fill = new("Frame", {Size = UDim2.fromScale(0.5, 1), BorderSizePixel = 0}, track)
        accent(fill, "BackgroundColor3")
        round(fill, 2)
        local knob = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(10, 10), BackgroundColor3 = C.Text, BorderSizePixel = 0}, track)
        round(knob, 5)
        UI.refreshers[#UI.refreshers + 1] = function()
            local number = App.Settings[key]
            local ratio = (number - rule[3]) / (rule[4] - rule[3])
            fill.Size, knob.Position = UDim2.fromScale(ratio, 1), UDim2.fromScale(ratio, 0.5)
            value.Text = (rule[5] < 1 and string.format("%.2f", number) or tostring(math.floor(number))) .. (suffix or "")
        end
        App:Connect(bar.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                UI.sliderDrag = {key = key, bar = bar, minimum = rule[3], maximum = rule[4]}
                UI:Move(input.Position)
            end
        end)
    end
    local function choice(parent, key, caption)
        local row = new("Frame", {Size = UDim2.new(1, 0, 0, 53), BackgroundTransparency = 1,
            BorderSizePixel = 0}, parent)
        text(row, caption, 11, C.Muted, {Size = UDim2.new(1, 0, 0, 20)})
        local picker = button(row, "", function()
            local choices = App.Core.Schema[key][3]
            local index = table.find(choices, App.Settings[key]) or 1
            App:Set(key, choices[index % #choices + 1])
        end)
        picker.Position, picker.Size = UDim2.fromOffset(0, 22), UDim2.new(1, 0, 0, 28)
        UI.refreshers[#UI.refreshers + 1] = function() picker.Text = App.Settings[key] .. "   >" end
    end
    local function status(parent, key, caption)
        local row = new("Frame", {Size = UDim2.new(1, 0, 0, 29), BackgroundTransparency = 1,
            BorderSizePixel = 0}, parent)
        text(row, caption, 11, C.Muted, {Size = UDim2.new(0.43, 0, 1, 0)})
        local value = text(row, "waiting", 10, C.Amber, {Position = UDim2.fromScale(0.43, 0),
            Size = UDim2.fromScale(0.57, 1), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.Code})
        UI.status[key] = value
    end

    local overview = card("Overview", 1, "Live status")
    for _, item in ipairs({{"camera", "Camera"}, {"cache", "Character cache"}, {"team", "Local team"},
        {"mode", "Game mode"}, {"source", "Tracking source"}, {"aim", "Aim state"}, {"target", "Current target"}, {"save", "Profile"}}) do
        status(overview, item[1], item[2])
    end
    local controls = card("Overview", 1, "Controls")
    note(controls, "F1  Show / hide menu\nF6  Save current settings\nF8  Copy live diagnostics\nF10  Stop and fully unload", 85)
    local counts = card("Overview", 2, "Target cache")
    for _, item in ipairs({{"players", "Player models"}, {"bots", "Bot models"}, {"eligible", "Aim eligible"},
        {"visible", "ESP drawn"}, {"unknown", "Unknown teams"}, {"dead", "Dead / removed"},
        {"fps", "Render FPS"}, {"errors", "Runtime errors"}}) do status(counts, item[1], item[2]) end
    local availability = card("Overview", 2, "Data availability")
    UI.Availability = note(availability, "Waiting for the first character scan.", 100)

    local aim = card("Aim", 1, "Aim assist")
    toggle(aim, "AimEnabled", "Enable aim")
    choice(aim, "AimMode", "Activation: Hold or Toggle")
    local bindButton = button(aim, "", function()
        App.BindCapture, App.AimLatched, App.Target = "AimBind", false, nil
        UI:Refresh()
        App:Notify("Press the aim key or mouse button. Escape cancels.")
    end)
    UI.refreshers[#UI.refreshers + 1] = function()
        bindButton.Text = App.BindCapture == "AimBind" and "Press key / mouse button..." or ("Aim button: " .. Core.bindLabel(App.Settings.AimBind))
    end
    note(aim, "Hold: aim while pressed. Toggle: press once to start, press again to stop. F1 opens the menu.", 67)
    slider(aim, "AimFOV", "FOV radius", " px")
    slider(aim, "AimSmooth", "Smoothing", "")
    note(aim, "0 = instant camera snap. Higher values turn more slowly.", 36)
    toggle(aim, "AimSticky", "Keep current target", "Otherwise choose the closest valid target")
    local aiming = card("Aim", 2, "Target selection")
    note(aiming, "Aim point: HEAD CENTER. The head dot marks that same position.", 42)
    toggle(aiming, "ShowHeadDot", "Head dot on / off", "Hiding the dot does not change head lock")
    choice(aiming, "AimPriority", "Target priority")
    toggle(aiming, "AimVisibleOnly", "Visible targets only", "Raycast checks are repeated while aiming")
    slider(aiming, "AimDistance", "Maximum range", " st")
    toggle(aiming, "ShowFOV", "Show FOV circle")
    note(aiming, "Aim runs independently of the ESP toggle. Distance is shown in Roblox studs.", 46)

    local visuals = card("Visuals", 1, "ESP")
    toggle(visuals, "ESPEnabled", "Enable ESP")
    choice(visuals, "ESPMode", "Activation: Toggle or Hold")
    local espBindButton = button(visuals, "", function()
        App.BindCapture, App.AimLatched, App.Target = "ESPBind", false, nil
        UI:Refresh()
        App:Notify("Press the ESP key or mouse button. Escape cancels.")
    end)
    UI.refreshers[#UI.refreshers + 1] = function()
        espBindButton.Text = App.BindCapture == "ESPBind" and "Press key / mouse button..."
            or ("ESP button: " .. Core.bindLabel(App.Settings.ESPBind))
    end
    note(visuals, "Toggle flips the ESP switch. Hold shows ESP while pressed when Enable ESP is on.", 52)
    toggle(visuals, "ESPBoxes", "Thin boxes")
    toggle(visuals, "ESPNames", "Names + bot label")
    toggle(visuals, "ESPHealth", "Live health")
    toggle(visuals, "ESPDistance", "Distance")
    toggle(visuals, "ESPSkeleton", "Skeleton")
    toggle(visuals, "ESPTracers", "Bottom tracers")
    toggle(visuals, "ESPOutline", "Character silhouette")
    toggle(visuals, "ESPOffscreen", "Off-screen direction arrows")
    slider(visuals, "HeadDotSize", "Head dot diameter", " px")
    local filters = card("Visuals", 2, "Display filters")
    toggle(filters, "ESPThroughWalls", "Through-wall ESP", "Shows boxes, dots and silhouettes behind walls")
    toggle(filters, "ESPTeammates", "Also show teammates", "This never enables aim at teammates")
    toggle(filters, "GlobalSearch", "Global character search", "Finds rigs anywhere in Workspace")
    choice(filters, "CharacterSource", "Character tracking")
    button(filters, "Rescan characters", function() App:Scan() end)
    note(filters, "If Auto follows a spawn copy, try Player.Character or World rigs.", 52)
    choice(filters, "UnverifiedPositions", "When hidden positions stop changing")
    slider(filters, "PositionTimeout", "Mark unverified after", " sec")
    note(filters, "Hide removes uncertain markers. Label marks them UNVERIFIED. A stationary player can also become unverified.", 76)
    slider(filters, "ESPDistanceLimit", "Maximum ESP range", " st")
    note(filters, "Health bars require a known maximum. Missing health is shown as HP ?, not a guessed value.", 62)
    note(filters, "BLUE = TEAM   /   PINK = ENEMY\nAMBER = TEAM UNKNOWN\nTarget selection never changes team colors.", 65)

    local targets = card("Targets", 1, "Included targets")
    toggle(targets, "IncludePlayers", "Players")
    toggle(targets, "IncludeBots", "Bots / NPCs", "Reads live character models, not just Players")
    note(targets, "Aiming always skips known teammates. Unknown teams remain amber until recognized.", 58)
    toggle(targets, "AllowUnknownTeams", "Aim at unknown teams", "Off waits for reliable team information")
    choice(targets, "TeamMode", "Team mode")
    choice(targets, "LocalTeamOverride", "Your side (if Auto cannot detect it)")
    local targetInfo = card("Targets", 2, "Recognition")
    note(targetInfo, "Global search reads character models across Workspace, current Player.Character references, health and team data.", 83)
    note(targetInfo, "Auto FFA recognizes explicit Deathmatch / FFA modes. Team Deathmatch still keeps team filtering.", 69)
    note(targetInfo, "Dead targets are always ignored. Aim pauses while you are dead, typing, or using the menu.", 64)

    local profiles = card("Profiles", 1, "Saved profile")
    button(profiles, "Save current settings   /   F6", function() App:Save() end)
    button(profiles, "Load saved settings", function() App:Load(true) end)
    button(profiles, "Reset to defaults", function() App:Reset() end)
    note(profiles, "Save uses executor file access when available. Otherwise it keeps an honest session-only copy.", 66)
    UI.ProfileDetail = note(profiles, "Checking save support...", 61)
    local appearance = card("Profiles", 2, "Appearance")
    choice(appearance, "Theme", "Accent theme")
    slider(appearance, "WindowScale", "Menu scale", "x")
    toggle(appearance, "ShowHUD", "Show compact HUD")
    button(appearance, "Copy diagnostics", function() App:CopyDiagnostics() end)
    button(appearance, "Fully unload   /   F10", function() App:Destroy("profile unload button") end)

    function UI:Accent() return themes[App.Settings.Theme] end
    function UI:Status(key, value, tone)
        local label = self.status[key]
        if label then label.Text, label.TextColor3 = tostring(value), C[tone or "Muted"] or C.Muted end
    end
    function UI:Layout(viewport)
        local factor = math.max(0.35, math.min(App.Settings.WindowScale,
            (viewport.X - 24) / 820, (viewport.Y - 24) / 550))
        self.Scale.Scale = factor
        local halfW, halfH = 410 * factor, 275 * factor
        local x = math.clamp(App.Settings.WindowX * viewport.X, halfW + 6, math.max(halfW + 6, viewport.X - halfW - 6))
        local y = math.clamp(App.Settings.WindowY * viewport.Y, halfH + 6, math.max(halfH + 6, viewport.Y - halfH - 6))
        main.Position = UDim2.fromOffset(x, y)
    end
    function UI:Move(position)
        if self.sliderDrag then
            local dragState = self.sliderDrag
            if dragState.bar.AbsoluteSize.X > 0 then
                local ratio = math.clamp((position.X - dragState.bar.AbsolutePosition.X) / dragState.bar.AbsoluteSize.X, 0, 1)
                App:Set(dragState.key, dragState.minimum + ratio * (dragState.maximum - dragState.minimum))
            end
        elseif self.windowDrag then
            local camera = App.Services.Workspace.CurrentCamera
            if not camera then return end
            local delta = position - self.windowDrag.point
            App:Set("WindowX", (self.windowDrag.x + delta.X) / math.max(camera.ViewportSize.X, 1))
            App:Set("WindowY", (self.windowDrag.y + delta.Y) / math.max(camera.ViewportSize.Y, 1))
        end
    end
    function UI:EndDrag() self.sliderDrag, self.windowDrag = nil, nil end
    function UI:Refresh()
        for _, item in ipairs(self.accents) do item[1][item[2]] = themes[App.Settings.Theme] end
        for _, refresh in ipairs(self.refreshers) do refresh() end
        hud.Visible = App.Settings.ShowHUD
        main.Visible, self.Modal.Modal = App.MenuOpen, App.MenuOpen
        if App.Services.Workspace.CurrentCamera then self:Layout(App.Services.Workspace.CurrentCamera.ViewportSize) end
    end
    function UI:FooterUpdate()
        if App.ToastUntil and os.clock() < App.ToastUntil then
            self.Footer.Text, self.Footer.TextColor3 = App.ToastText, App.ToastError and C.Red or C.Green
        else
            self.Footer.Text = App.Dirty and "UNSAVED CHANGES  /  F6 TO SAVE" or App.ProfileStatus
            self.Footer.TextColor3 = App.Dirty and C.Amber or C.Muted
        end
    end
    selectTab("Aim")
    UI:Refresh()
    return UI
end

end)()

-- Nightfall BloxStrike bootstrap. Core, Resources, makeAdapter and makeUI are bundled above.
local Services = {
    Players = game:GetService("Players"), Workspace = game:GetService("Workspace"),
    Teams = game:GetService("Teams"),
    RunService = game:GetService("RunService"), Input = game:GetService("UserInputService"),
    Http = game:GetService("HttpService"),
}
if not game:IsLoaded() then game.Loaded:Wait() end
Services.Player = Services.Players.LocalPlayer
if not Services.Player then error("Nightfall requires a Roblox client session.") end

local environment = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then environment = value end
end
local INSTANCE_KEY, SAVE_KEY = "__NightfallBloxStrikeV1", "__NightfallBloxStrikeProfilesV1_3"
local previous = environment[INSTANCE_KEY]
if type(previous) == "table" and type(previous.Destroy) == "function" then
    local ok, problem = pcall(previous.Destroy, previous, "re-executed")
    if not ok then warn("[Nightfall] Previous instance cleanup reported: " .. tostring(problem)) end
end
local function capability(name)
    local value = environment[name]
    if type(value) ~= "function" then
        local ok, global = pcall(function() return getfenv(0)[name] end)
        if ok then value = global end
    end
    return type(value) == "function" and value or nil
end

local App = {
    Core = Core, Services = Services, Alive = true, Maid = Resources.new(),
    Settings = Core.settings(), MenuOpen = true, Dirty = false, Visuals = {},
    ProfileStatus = "Default profile", LastError = "", ErrorCount = 0,
    Id = Services.Http:GenerateGUID(false):gsub("[^%w]", ""),
    ProfileFile = "Nightfall_BloxStrike_v1_3_" .. tostring(game.GameId) .. ".json",
    Stats = {players = 0, bots = 0, eligible = 0, visible = 0, unknown = 0, dead = 0, fps = 0},
    AimStatus = "OFF", AimWrites = 0, RenderFrames = 0,
    AimLatched = false, Trace = {}, ActiveTrace = {},
}
environment[INSTANCE_KEY] = App
local readFile, writeFile, isFile = capability("readfile"), capability("writefile"), capability("isfile")
local clip = capability("setclipboard") or capability("toclipboard")
local function finiteVector(value)
    return Core.finite(value.X) and Core.finite(value.Y) and Core.finite(value.Z)
end
local function uiObject(class, properties, parent)
    local item = Instance.new(class)
    for key, value in pairs(properties) do item[key] = value end
    item.Parent = parent
    return item
end

function App:Own(instance)
    self.Maid:give(function() instance:Destroy() end)
    return instance
end
function App:Connect(signal, callback)
    local connection = signal:Connect(function(...)
        if not self.Alive then return end
        local ok, problem = pcall(callback, ...)
        if not ok then self:Error("UI/input", problem) end
    end)
    self.Maid:give(function() connection:Disconnect() end)
    return connection
end
function App:Notify(message, failure)
    self.ToastText, self.ToastUntil, self.ToastError = tostring(message), os.clock() + 4, failure == true
    print("[Nightfall] " .. tostring(message))
end
function App:Error(stage, problem)
    local message = stage .. ": " .. tostring(problem)
    self.ErrorCount += 1
    if message ~= self.LastError or os.clock() - (self.LastWarnTime or 0) > 5 then
        warn("[Nightfall] " .. message)
        self.LastWarnTime = os.clock()
    end
    self.LastError = message
    if stage == "render" then
        self.Settings.AimEnabled, self.Settings.ESPEnabled = false, false
        self.Target, self.Dirty = nil, true
        for _, view in pairs(self.Visuals) do
            pcall(function() view.root.Visible = false end)
            pcall(function() if view.highlight then view.highlight.Enabled = false end end)
        end
        if self.UI then pcall(function() self.UI:Refresh() end) end
    end
    self:Notify("Runtime error - see Overview / diagnostics", true)
end
function App:Set(key, value)
    if not self.Alive or not Core.Schema[key] then return end
    value = Core.value(key, value)
    if self.Settings[key] == value then return end
    self.Settings[key], self.Dirty = value, true
    self.Target = nil
    if key == "AimBind" or key == "AimMode" or key == "AimEnabled" then
        self.AimLatched, self.AimHeld = false, false
    end
    if key == "ESPThroughWalls" then
        for _, record in pairs(self.Adapter and self.Adapter.records or {}) do record.visibleAt = nil end
    end
    if (key == "CharacterSource" or key == "GlobalSearch") and self.Adapter then self:Scan() end
    if self.UI then self.UI:Refresh() end
end
function App:SetMenu(open)
    if not self.Alive then return end
    self.MenuOpen, self.Target = open == true, nil
    self.AimLatched, self.AimHeld, self.BindCapture = false, false, false
    if self.UI then self.UI:EndDrag() self.UI:Refresh() end
end
function App:Reset()
    self.Settings, self.Dirty, self.Target = Core.settings(), true, nil
    self.AimLatched, self.AimHeld, self.BindCapture = false, false, false
    if self.UI then self.UI:Refresh() end
    self:Notify("Defaults restored. Press F6 to save them.")
end
function App:Save()
    if not self.Alive then return end
    local snapshot = Core.settings(self.Settings)
    local saved = environment[SAVE_KEY]
    if type(saved) ~= "table" then saved = {} environment[SAVE_KEY] = saved end
    saved[tostring(game.GameId)] = snapshot
    self.Dirty = false
    if writeFile then
        local ok, problem = pcall(function()
            local json = Services.Http:JSONEncode({schema = 1, gameId = tostring(game.GameId), settings = snapshot})
            writeFile(self.ProfileFile, json)
        end)
        if ok then
            self.ProfileStatus = readFile and "Saved to disk" or "Saved to disk; read API unavailable"
            self:Notify(self.ProfileStatus)
            return
        end
        self.LastSaveError = tostring(problem)
        self.ProfileStatus = "Session saved; disk write failed"
        self:Notify(self.ProfileStatus, true)
        return
    end
    self.ProfileStatus = "Session saved; disk API unavailable"
    self:Notify(self.ProfileStatus)
end
function App:Load(manual)
    if not self.Alive then return end
    local raw, source, failure
    if readFile then
        local ok, result = pcall(function()
            if isFile and not isFile(self.ProfileFile) then return nil end
            local encoded = readFile(self.ProfileFile)
            if type(encoded) ~= "string" or #encoded > 65536 then error("Invalid profile size") end
            local decoded = Services.Http:JSONDecode(encoded)
            if type(decoded) ~= "table" or decoded.schema ~= 1
                or tostring(decoded.gameId) ~= tostring(game.GameId) or type(decoded.settings) ~= "table" then
                error("Profile schema or game ID does not match")
            end
            return decoded.settings
        end)
        if ok and type(result) == "table" then raw, source = result, "Disk profile loaded"
        elseif not ok then failure = tostring(result) end
    end
    if not raw then
        local stored = environment[SAVE_KEY]
        if type(stored) == "table" and type(stored[tostring(game.GameId)]) == "table" then
            raw, source = stored[tostring(game.GameId)], "Session profile loaded"
        end
    end
    if raw then
        self.Settings, self.Dirty, self.Target = Core.settings(raw), false, nil
        self.AimLatched, self.AimHeld, self.BindCapture = false, false, false
        self.ProfileStatus = source
        if self.UI then self.UI:Refresh() end
        if manual then self:Notify(source) end
    elseif manual then
        self.LastSaveError = failure
        self:Notify("No readable saved profile found; current settings kept", true)
    end
end
function App:Diagnostics()
    return {
        version = Core.Version, gameId = tostring(game.GameId), placeId = tostring(game.PlaceId),
        characterPath = self.Adapter and self.Adapter.folderPath or "not initialized",
        counts = table.clone(self.Stats), aimState = self.AimStatus, cameraWrites = self.AimWrites,
        profile = self.ProfileStatus, diskRead = readFile ~= nil, diskWrite = writeFile ~= nil,
        latestError = self.LastError, saveError = self.LastSaveError,
        scanTruncated = self.Adapter and self.Adapter.truncated or false,
        tracking = self.Adapter and self.Adapter:diagnostics() or nil,
        streamingEnabled = Services.Workspace.StreamingEnabled,
        focused = self.Focused, localTeam = self.LocalTeam, mode = self.Mode,
        settings = Core.settings(self.Settings),
        liveFix = {revision = "2", samples = self.Trace, aimSamples = self.ActiveTrace},
    }
end
function App:CopyDiagnostics()
    local encoded = Services.Http:JSONEncode(self:Diagnostics())
    if clip then
        local ok = pcall(clip, encoded)
        if ok then self:Notify("Diagnostics copied") return end
    end
    print("[Nightfall diagnostics] " .. encoded)
    self:Notify("Clipboard unavailable; diagnostics printed to console")
end
function App:Destroy(reason)
    if not self.Alive then return end
    self.Alive = false
    self.Target, self.ActiveRows = nil, nil
    if environment[INSTANCE_KEY] == self then environment[INSTANCE_KEY] = nil end
    local failures = self.Maid:clean()
    self.UI, self.Adapter, self.Visuals = nil, nil, {}
    print(string.format("[Nightfall] Fully unloaded (%s); cleanup errors: %d", tostring(reason or "requested"), failures))
end

function App:IsButtonDown(bind)
    if bind:match("^MouseButton[123]$") then
        return Services.Input:IsMouseButtonPressed(Enum.UserInputType[bind])
    end
    return Services.Input:IsKeyDown(Enum.KeyCode[bind])
end
function App:IsAimButtonDown() return self:IsButtonDown(self.Settings.AimBind) end
function App:ESPActive()
    return self.Settings.ESPEnabled and (self.Settings.ESPMode == "Toggle" or self:IsButtonDown(self.Settings.ESPBind))
end
function App:AimActivated()
    if self.Settings.AimMode == "Toggle" then return self.AimLatched end
    return self:IsAimButtonDown()
end

-- Register cleanup and input handling before constructing the UI.
App:Connect(Services.Input.InputBegan, function(input, processed)
    local focused = Services.Input:GetFocusedTextBox()
    local action = Core.action(input.KeyCode.Name, focused ~= nil)
    if action == "unload" then App:Destroy("F10") return end
    if App.BindCapture then
        if input.KeyCode == Enum.KeyCode.Escape then
            App.BindCapture = false
            if App.UI then App.UI:Refresh() end
            return
        end
        local name = input.UserInputType.Name
        if not name:match("^MouseButton[123]$") then
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            name = input.KeyCode.Name
        end
        local setting = App.BindCapture
        if Core.value(setting, name) ~= name then
            App:Notify("That key is reserved. Choose another.", true)
            return
        end
        local other = setting == "AimBind" and "ESPBind" or "AimBind"
        if App.Settings[other] == name then App:Notify("Choose separate aim and ESP buttons.", true) return end
        App.BindCapture = false
        App:Set(setting, name)
        if App.UI then App.UI:Refresh() end
        App:Notify((setting == "AimBind" and "Aim" or "ESP") .. " button set to " .. Core.bindLabel(name))
        return
    end
    if action == "menu" then App:SetMenu(not App.MenuOpen) return end
    if action == "save" then App:Save() return end
    if action == "diagnostics" then App:CopyDiagnostics() return end
    if focused or processed or App.MenuOpen or not App.Focused then return end
    local function matchesBind(bind)
        if bind:match("^MouseButton[123]$") then return input.UserInputType == Enum.UserInputType[bind] end
        return input.KeyCode == Enum.KeyCode[bind]
    end
    if matchesBind(App.Settings.ESPBind) and App.Settings.ESPMode == "Toggle" then
        App:Set("ESPEnabled", not App.Settings.ESPEnabled)
    end
    if not App.Settings.AimEnabled then return end
    local bind = App.Settings.AimBind
    local matches = bind:match("^MouseButton[123]$") and input.UserInputType == Enum.UserInputType[bind]
        or (not bind:match("^MouseButton[123]$") and input.KeyCode == Enum.KeyCode[bind])
    if matches and App.Settings.AimMode == "Toggle" then
        App.AimLatched = not App.AimLatched
        if not App.AimLatched then App.Target = nil end
    end
end)
App:Connect(Services.Input.InputChanged, function(input)
    if App.UI and App.MenuOpen and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then App.UI:Move(input.Position) end
end)
App:Connect(Services.Input.InputEnded, function(input)
    if App.UI and (input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch) then App.UI:EndDrag() end
end)
App:Connect(Services.Input.WindowFocusReleased, function()
    App.Target = nil
    App.AimLatched, App.AimHeld, App.BindCapture = false, false, false
    App.Focused = false
    if App.UI then App.UI:EndDrag() App.UI:Refresh() end
end)
App:Connect(Services.Input.WindowFocused, function() App.Focused = true end)
App.Focused = true

local function makeLine(parent)
    return uiObject("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.1, BorderSizePixel = 0, Visible = false}, parent)
end
local function setLine(line, a, b, color, thickness)
    local dx, dy = b.X - a.X, b.Y - a.Y
    local length = math.sqrt(dx * dx + dy * dy)
    if not Core.finite(length) or length < 0.5 then line.Visible = false return end
    line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
    line.Size, line.Rotation = UDim2.fromOffset(length, thickness or 1), math.deg(math.atan2(dy, dx))
    line.BackgroundColor3, line.Visible = color, true
end
local function visualLabel(parent, size)
    return uiObject("TextLabel", {BackgroundTransparency = 1, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(300, 18), Text = "",
        TextSize = size, TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.new(),
        TextStrokeTransparency = 0.25, Font = Enum.Font.Code, RichText = false,
        TextXAlignment = Enum.TextXAlignment.Center}, parent)
end
function App:EnsureVisual(record)
    local existing = self.Visuals[record.model]
    if existing then return existing end
    local view = {maid = Resources.new(), bones = {}}
    local root = uiObject("Frame", {Name = "TargetOverlay", BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Visible = false}, self.UI.Canvas)
    view.root = root
    view.maid:give(function() root:Destroy() end)
    view.box = uiObject("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0}, root)
    view.boxShadow = uiObject("UIStroke", {Color = Color3.new(), Thickness = 3, Transparency = 0.25},
        uiObject("Frame", {Name = "BoxBacking", Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1, BorderSizePixel = 0}, view.box))
    view.boxStroke = uiObject("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 1}, view.box)
    view.headDot = uiObject("Frame", {Name = "HeadDot", AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(8, 8), BorderSizePixel = 0, Visible = false, ZIndex = 4}, root)
    uiObject("UICorner", {CornerRadius = UDim.new(1, 0)}, view.headDot)
    view.dotStroke = uiObject("UIStroke", {Color = Color3.new(), Thickness = 1.5}, view.headDot)
    view.name, view.detail = visualLabel(root, 12), visualLabel(root, 10)
    view.arrow = visualLabel(root, 22)
    view.arrow.Text, view.arrow.Size = "▲", UDim2.fromOffset(24, 24)
    view.arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    view.edgeLabel = visualLabel(root, 10)
    view.health = uiObject("Frame", {BackgroundColor3 = Color3.fromRGB(9, 12, 17),
        BorderSizePixel = 0, Size = UDim2.fromOffset(3, 40)}, root)
    view.fill = uiObject("Frame", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(89, 218, 166), BorderSizePixel = 0}, view.health)
    view.tracer = makeLine(root)
    self.Visuals[record.model] = view
    return view
end
function App:HideVisual(view)
    view.root.Visible = false
    if view.highlight then view.highlight.Enabled = false end
end
function App:Scan()
    self.Adapter:scan(self.Settings)
    for model, view in pairs(self.Visuals) do
        if not self.Adapter.records[model] then view.maid:clean() self.Visuals[model] = nil end
    end
end

-- Project body parts directly, keeping partial on-screen characters visible.
local function bounds(record, camera)
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    local found = false
    for _, bodyPart in ipairs(record.body) do
        if bodyPart.Parent and bodyPart:IsDescendantOf(record.model) then
            local half = bodyPart.Size * 0.5
            for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
                local world = bodyPart.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
                local projected = camera:WorldToViewportPoint(world)
                if finiteVector(projected) and projected.Z > 0.05 then
                    left, right = math.min(left, projected.X), math.max(right, projected.X)
                    top, bottom = math.min(top, projected.Y), math.max(bottom, projected.Y)
                    found = true
                end
            end end end
        end
    end
    local viewport = camera.ViewportSize
    if not found or right < 0 or left > viewport.X or bottom < 0 or top > viewport.Y then return nil end
    left, right = math.clamp(left, -2, viewport.X + 2), math.clamp(right, -2, viewport.X + 2)
    top, bottom = math.clamp(top, -2, viewport.Y + 2), math.clamp(bottom, -2, viewport.Y + 2)
    local width, height = right - left, bottom - top
    if width < 2 or height < 2 then return nil end
    return left, top, width, height
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
function App:Visible(row, camera, localModel)
    if not row.part or not row.part:IsDescendantOf(Services.Workspace) then row.liveBlock = "missing head" return false end
    local ignore = {camera}
    if localModel then ignore[#ignore + 1] = localModel end
    local origin, direction = camera.CFrame.Position, row.part.Position - camera.CFrame.Position
    if not self.Core.finite(direction.Magnitude) or direction.Magnitude < 0.001 then return false end
    for _ = 1, 8 do
        rayParams.FilterDescendantsInstances = ignore
        local ok, hit = pcall(Services.Workspace.Raycast, Services.Workspace, origin, direction, rayParams)
        if not ok then row.liveBlock = "raycast error: " .. tostring(hit) return false end
        if not hit or hit.Instance:IsDescendantOf(row.model) then row.liveBlock = nil return true end
        local part = hit.Instance
        local invisible = part:IsA("BasePart") and not part.CanCollide
            and (part.Transparency >= 0.99 or part.LocalTransparencyModifier >= 0.99)
        if not invisible then row.liveBlock = part:GetFullName() return false end
        ignore[#ignore + 1] = part
    end
    row.liveBlock = "too many invisible blockers"
    return false
end

function App:ObserveRow(row, camera, localModel)
    local record, now = row.record, os.clock()
    local root, head = record.root.Position, row.part and row.part.Position
    if record.sampleRoot and ((root - record.sampleRoot).Magnitude > 0.1
        or (head and record.sampleHead and (head - record.sampleHead).Magnitude > 2)) then
        record.motionAt = now
        record.sampleRoot, record.sampleHead = root, head
    end
    record.sampleRoot, record.sampleHead = record.sampleRoot or root, record.sampleHead or head
    if now - (record.rayAt or -math.huge) >= 0.1 then
        record.rayAt, record.rayVisible = now, self:Visible(row, camera, localModel)
    end
    row.rayVisible = record.rayVisible == true
    local bodyShown = false
    if row.onScreen and row.rayVisible then
        for _, body in ipairs(record.body) do
            if body.Parent and body.Transparency < 0.99 and body.LocalTransparencyModifier < 0.99 then bodyShown = true break end
        end
        if bodyShown then record.seenAt = now end
    end
    row.bodyShown = bodyShown
    local confirmed = math.max(record.firstSeenAt or now, record.motionAt or 0, record.seenAt or 0)
    row.positionAge = math.max(0, now - confirmed)
    row.positionUncertain = row.positionAge > self.Settings.PositionTimeout
end

function App:DrawRecord(row, camera, localModel)
    local config, record = self.Settings, row.record
    local espOn = self:ESPActive()
    local previousView = self.Visuals[row.model]
    if (not espOn and not config.ShowHeadDot) or not Core.eligible(row, config, "esp")
        or row.distance > config.ESPDistanceLimit then
        if previousView then self:HideVisual(previousView) end
        return false
    end
    if row.positionUncertain and config.UnverifiedPositions == "Hide" then
        if previousView then self:HideVisual(previousView) end
        return false
    end
    if not config.ESPThroughWalls then
        local now = os.clock()
        if now - (record.visibleAt or -math.huge) > 0.1 then
            record.visibleAt, record.visible = now, self:Visible(row, camera, localModel)
        end
        if not record.visible then if previousView then self:HideVisual(previousView) end return false end
    end
    local view = previousView or self:EnsureVisual(record)
    local red, green, blue, label = Core.relationStyle(row.relation)
    local color = Color3.fromRGB(red, green, blue)
    local selected = self.Target and self.Target.model == row.model
    view.root.Visible = true
    for _, element in ipairs({view.box, view.name, view.detail, view.health, view.tracer, view.headDot, view.arrow, view.edgeLabel}) do
        element.Visible = false
    end
    for _, line in ipairs(view.bones) do line.Visible = false end

    -- The dot and aim use the exact same Head.Position; hiding it only hides the marker.
    if config.ShowHeadDot and row.part and row.part.Parent then
        local head, onScreen = camera:WorldToViewportPoint(row.part.Position)
        if onScreen and head.Z > 0.05 and finiteVector(head) then
            local diameter = config.HeadDotSize
            view.headDot.Visible, view.headDot.BackgroundColor3 = true, color
            view.headDot.Position = UDim2.fromOffset(head.X, head.Y)
            view.headDot.Size = UDim2.fromOffset(diameter, diameter)
            view.dotStroke.Color = selected and Color3.new(1, 1, 1) or Color3.new()
            view.dotStroke.Thickness = selected and 2 or 1.5
        end
    end

    local x, y, width, height
    if espOn then x, y, width, height = bounds(record, camera) end
    if x then
        view.box.Visible, view.boxStroke.Color = config.ESPBoxes, color
        view.box.Position, view.box.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(width, height)
        view.name.Visible, view.name.TextColor3 = config.ESPNames, color
        view.name.Position = UDim2.fromOffset(x + width / 2, math.max(0, y - 20))
        local suffix = row.positionUncertain and config.UnverifiedPositions == "Label"
            and (" [UNVERIFIED " .. tostring(math.floor(row.positionAge)) .. "s]") or ""
        view.name.Text = "[" .. label .. "] " .. record.name .. (row.bot and " [BOT]" or "") .. suffix
        local details = {}
        if config.ESPHealth then details[#details + 1] = row.health and (tostring(math.floor(row.health + 0.5)) .. " HP") or "HP ?" end
        if config.ESPDistance then details[#details + 1] = tostring(math.floor(row.distance + 0.5)) .. " st" end
        view.detail.Visible, view.detail.Text = #details > 0, table.concat(details, "  |  ")
        view.detail.Position = UDim2.fromOffset(x + width / 2, math.min(y + height + 3, camera.ViewportSize.Y - 18))
        view.health.Visible = config.ESPHealth and row.health ~= nil and row.maximum ~= nil
        if view.health.Visible then
            local ratio = math.clamp(row.health / row.maximum, 0, 1)
            view.health.Position, view.health.Size = UDim2.fromOffset(x - 6, y), UDim2.fromOffset(3, height)
            view.fill.Size = UDim2.fromScale(1, ratio)
            view.fill.BackgroundColor3 = Color3.fromRGB(244, 100, 116):Lerp(Color3.fromRGB(89, 218, 166), ratio)
        end
        if config.ESPTracers then
            setLine(view.tracer, Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y - 14),
                Vector2.new(x + width / 2, y + height), color, 1)
        end
    end
    if espOn and config.ESPOffscreen and not row.onScreen and row.part and row.part.Parent then
        local point = camera:WorldToViewportPoint(row.part.Position)
        local ex, ey, angle = Core.edgePoint(point.X, point.Y, point.Z, camera.ViewportSize.X, camera.ViewportSize.Y, 44)
        if ex then
            view.arrow.Visible, view.arrow.TextColor3 = true, color
            view.arrow.Position, view.arrow.Rotation = UDim2.fromOffset(ex, ey), angle
            view.edgeLabel.Visible, view.edgeLabel.TextColor3 = true, color
            view.edgeLabel.Position = UDim2.fromOffset(ex, ey + 15)
            view.edgeLabel.Text = record.name .. " / " .. tostring(math.floor(row.distance)) .. " st"
                .. (row.positionUncertain and config.UnverifiedPositions == "Label" and " / UNVERIFIED" or "")
        end
    end
    if espOn and config.ESPSkeleton then
        for index, pair in ipairs(record.bones) do
            if pair[1].Parent and pair[2].Parent then
                local a, b = camera:WorldToViewportPoint(pair[1].Position), camera:WorldToViewportPoint(pair[2].Position)
                if a.Z > 0.05 and b.Z > 0.05 and finiteVector(a) and finiteVector(b) then
                    if not view.bones[index] then view.bones[index] = makeLine(view.root) end
                    setLine(view.bones[index], a, b, color, 1)
                end
            end
        end
    end
    if espOn and config.ESPOutline and not view.highlight and not view.outlineFailed then
        -- Unsupported Highlight creation must not disable the camera or 2D overlays.
        local ok, failure = pcall(function()
            local highlight = Instance.new("Highlight")
            view.maid:give(function() highlight:Destroy() end)
            highlight.Name = "Nightfall_" .. self.Id
            highlight.Adornee = row.model
            highlight.FillTransparency, highlight.OutlineTransparency = 0.84, 0
            highlight.Parent = row.model
            view.highlight = highlight
        end)
        if not ok then view.outlineFailed, self.OutlineError = true, tostring(failure) end
    end
    if view.highlight then
        view.highlight.Enabled = espOn and config.ESPOutline
        view.highlight.FillColor, view.highlight.OutlineColor = color, color
        view.highlight.DepthMode = config.ESPThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    end
    if view.headDot.Visible or view.box.Visible or view.name.Visible or view.detail.Visible or view.arrow.Visible
        or view.health.Visible or view.tracer.Visible or (view.highlight and view.highlight.Enabled and row.onScreen) then return true end
    for _, line in ipairs(view.bones) do if line.Visible then return true end end
    return false
end

function App:Render(delta)
    if not self.Alive then return end
    local camera = Services.Workspace.CurrentCamera
    self.CameraPresent = camera ~= nil
    if not camera or camera.ViewportSize.X < 1 or camera.ViewportSize.Y < 1 then
        self.Target, self.AimStatus = nil, "NO CAMERA"
        self.UI.Circle.Visible = false
        for _, view in pairs(self.Visuals) do self:HideVisual(view) end
        return
    end
    local viewport = camera.ViewportSize
    if not self.LastViewport or self.LastViewport ~= viewport then self.UI:Layout(viewport) self.LastViewport = viewport end
    local localModel, team, ffa, mode, localAlive = self.Adapter:localContext(self.Settings)
    self.LocalTeam, self.Mode, self.IsFFA = team, mode, ffa
    local rows, present, stats = {}, {}, {players = 0, bots = 0, eligible = 0, visible = 0, unknown = 0, dead = 0,
        unverified = 0, fps = self.Stats.fps}
    local center, origin = viewport / 2, camera.CFrame.Position
    for _, record in pairs(self.Adapter.records) do
        local model = record.model
        if not record.self and self.Adapter:refreshParts(record) then
            local life = self.Adapter:life(record)
            local part = self.Adapter:aimPart(record)
            local point = part and part.Position or record.root.Position
            if finiteVector(point) and finiteVector(origin) then
                local screen, onScreen = camera:WorldToViewportPoint(point)
                local row = {
                    model = model, record = record, part = part, hasPart = part ~= nil,
                    self = false, bot = record.bot, alive = life.alive, lifeKnown = life.known,
                    health = life.health, maximum = life.maximum,
                    relation = Core.relation(self.Adapter:team(model, record.owner), team, ffa),
                    distance = (point - origin).Magnitude,
                    screenDistance = (Vector2.new(screen.X, screen.Y) - center).Magnitude,
                    onScreen = onScreen and screen.Z > 0.05,
                }
                self:ObserveRow(row, camera, localModel)
                rows[#rows + 1] = row
                present[model] = true
                if row.bot then stats.bots += 1 else stats.players += 1 end
                if not row.alive then stats.dead += 1 end
                if row.alive and row.relation == "unknown" then stats.unknown += 1 end
                if row.alive and row.positionUncertain then stats.unverified += 1 end
                if Core.eligible(row, self.Settings, "aim") and row.hasPart then stats.eligible += 1 end
            end
        end
    end
    local typing = Services.Input:GetFocusedTextBox() ~= nil
    if typing or not localAlive or not self.Focused or self.MenuOpen then self.AimLatched = false end
    local active = self.Settings.AimEnabled and localAlive and not self.MenuOpen and not self.BindCapture and not typing and self.Focused
    local holdingAim = self:AimActivated()
    local sticky = holdingAim and self.AimHeld and self.Target and self.Target.model
    self.Target = active and Core.pick(rows, self.Settings,
        function(row) return self:Visible(row, camera, localModel) end, sticky) or nil
    if not self.Settings.AimEnabled then self.AimStatus = "OFF"
    elseif not self.Focused then self.AimStatus = "WINDOW UNFOCUSED"
    elseif self.MenuOpen then self.AimStatus = "MENU PAUSED"
    elseif typing then self.AimStatus = "TYPING PAUSED"
    elseif not localAlive then self.AimStatus = "WAITING FOR SPAWN"
    elseif not self.Target then self.AimStatus = stats.unverified > 0 and "NO VERIFIED TARGET" or "NO VALID TARGET"
    elseif holdingAim then
        local position = self.Target.part.Position
        if (position - origin).Magnitude > 0.01 then
            local desired = CFrame.lookAt(origin, position, camera.CFrame.UpVector)
            camera.CFrame = camera.CFrame:Lerp(desired, Core.alpha(self.Settings.AimSmooth, delta))
            self.AimWrites += 1
            self.AimStatus = self.Settings.AimMode == "Toggle" and "AIMING / TOGGLE"
                or (self.Settings.AimBind == "MouseButton2" and "AIMING / RMB" or "AIMING / " .. Core.bindLabel(self.Settings.AimBind))
        end
    else self.AimStatus = "READY / " .. (self.Settings.AimMode == "Toggle" and "PRESS " or "HOLD ")
        .. Core.bindLabel(self.Settings.AimBind) end
    self.AimHeld = active and holdingAim
    for _, row in ipairs(rows) do
        if self:DrawRecord(row, camera, localModel) then stats.visible += 1 end
    end
    -- Old view resources are hidden immediately when a model streams out between scans.
    for model, view in pairs(self.Visuals) do
        if not present[model] then self:HideVisual(view) end
    end
    local radius = self.Settings.AimFOV
    self.UI.Circle.Visible = self.Settings.ShowFOV and self.Focused
    self.UI.Circle.Position, self.UI.Circle.Size = UDim2.fromOffset(center.X, center.Y), UDim2.fromOffset(radius * 2, radius * 2)
    self.UI.CircleStroke.Color = self.Target and Color3.fromRGB(89, 234, 186) or self.UI:Accent()
    self.Stats, self.ActiveRows = stats, rows
    self.RenderFrames += 1
end

function App:RecordTrace()
    -- Preserve useful in-game evidence when the user switches to the executor to copy it.
    if not self.Focused then return end
    local camera = Services.Workspace.CurrentCamera
    if not camera then return end
    local sample = {state = self.AimStatus, time = os.clock(), aimActive = self.AimHeld == true,
        aimMode = self.Settings.AimMode, aimBind = self.Settings.AimBind, aimLatched = self.AimLatched,
        rmb = Services.Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2),
        esp = self:ESPActive(), throughWalls = self.Settings.ESPThroughWalls, localTeam = self.LocalTeam,
        unverifiedPolicy = self.Settings.UnverifiedPositions, targets = {}, error = self.LastError}
    if self.AimHeld and self.Target and self.Target.part and self.Target.part.Parent then
        local p = camera:WorldToViewportPoint(self.Target.part.Position)
        local errorPixels = (Vector2.new(p.X, p.Y) - camera.ViewportSize / 2).Magnitude
        if Core.finite(errorPixels) then sample.headErrorPixels = errorPixels end
    end
    for _, row in ipairs(self.ActiveRows or {}) do
        if #sample.targets >= 24 then break end
        local p = row.part and row.part.Parent and row.part.Position
        local eligible, reason = Core.eligible(row, self.Settings, "aim")
        local view = self.Visuals[row.model]
        sample.targets[#sample.targets + 1] = {
            name = row.record.name, model = row.model:GetFullName(), relation = row.relation,
            head = p and finiteVector(p) and {x = p.X, y = p.Y, z = p.Z} or nil,
            eligible = eligible, rejected = reason, onScreen = row.onScreen,
            insideFOV = row.screenDistance <= self.Settings.AimFOV,
            lineOfSight = row.rayVisible, bodyShown = row.bodyShown,
            positionUncertain = row.positionUncertain, secondsSinceConfirmation = row.positionAge,
            boxEnabled = view and view.root.Visible and view.box.Visible or false,
            arrowEnabled = view and view.root.Visible and view.arrow.Visible or false,
            dotEnabled = view and view.root.Visible and view.headDot.Visible or false,
            highlightEnabled = view and view.highlight and view.highlight.Enabled or false,
        }
    end
    self.Trace[#self.Trace + 1] = sample
    if #self.Trace > 24 then table.remove(self.Trace, 1) end
    if sample.aimActive then
        self.ActiveTrace[#self.ActiveTrace + 1] = sample
        if #self.ActiveTrace > 24 then table.remove(self.ActiveTrace, 1) end
    end
end

function App:UpdateStatus()
    local ui, stats = self.UI, self.Stats
    local hasFolder = self.Adapter.folder ~= nil
    ui:Status("camera", self.CameraPresent and "AVAILABLE" or "WAITING", self.CameraPresent and "Green" or "Amber")
    ui:Status("cache", hasFolder and "CHARACTERS" or "FALLBACK", hasFolder and "Green" or "Amber")
    ui:Status("team", self.IsFFA and "FFA" or self.LocalTeam or "UNKNOWN", (self.LocalTeam or self.IsFFA) and "Green" or "Amber")
    ui:Status("mode", self.Mode or "unknown")
    ui:Status("source", self.Settings.CharacterSource)
    ui:Status("aim", self.AimStatus, self.AimStatus:sub(1, 6) == "AIMING" and "Green" or "Muted")
    ui:Status("target", self.Target and self.Target.record.name or "none")
    ui:Status("save", self.ProfileStatus, self.Dirty and "Amber" or "Muted")
    for _, key in ipairs({"players", "bots", "eligible", "visible", "unknown", "dead"}) do ui:Status(key, stats[key], "Text") end
    ui:Status("fps", math.floor(stats.fps + 0.5), "Text")
    ui:Status("errors", self.ErrorCount, self.ErrorCount > 0 and "Red" or "Muted")
    local total = stats.players + stats.bots
    ui.SideStatus.Text = total > 0 and (tostring(total) .. " models detected") or "Waiting for targets"
    ui.SideStatus.TextColor3 = total > 0 and Color3.fromRGB(89, 218, 166) or Color3.fromRGB(246, 191, 91)
    ui.HUDText.Text = string.format("%s / %s | ESP %s (%s) | F1 MENU", self.Settings.AimMode,
        Core.bindLabel(self.Settings.AimBind), self:ESPActive() and "ON" or "OFF", Core.bindLabel(self.Settings.ESPBind))
    local availability = hasFolder and "Character folder found. " or "Character folder missing; bot support is pending. "
    if total == 0 then availability ..= "No live target models detected yet. " end
    if stats.unknown > 0 then availability ..= tostring(stats.unknown) .. " models have unknown team data. " end
    if (stats.unverified or 0) > 0 then availability ..= tostring(stats.unverified) .. " positions are unverified. " end
    if self.Adapter.duplicateOwners > 0 then
        availability ..= tostring(self.Adapter.duplicateOwners) .. " players have multiple models; use Visuals > Character tracking if a spawn copy is selected. "
    end
    if self.Adapter.truncated then availability ..= "Scan limit reached. " end
    if self.VisibilityError then availability ..= "Raycast unavailable: " .. self.VisibilityError .. " " end
    if self.OutlineError then availability ..= "Silhouettes unavailable; 2D ESP is still active. " end
    if self.LastError ~= "" then availability ..= "Latest error: " .. self.LastError end
    if availability == "Character folder found. " then
        availability ..= "Tracks client character data. Hidden positions still need updates from the game."
    end
    ui.Availability.Text = availability
    ui.ProfileDetail.Text = (writeFile and "Disk save API available. " or "Disk saving unavailable. ")
        .. (readFile and "Disk load API available. " or "Disk loading unavailable. ")
        .. "\n" .. self.ProfileStatus
    ui:FooterUpdate()
end

local startupOK, startupError = xpcall(function()
    local hiddenUI = capability("gethui")
    if hiddenUI then
        local ok, parent = pcall(hiddenUI)
        if ok and typeof(parent) == "Instance" then App.GuiParent = parent end
    end
    App.GuiParent = App.GuiParent or Services.Player:FindFirstChildOfClass("PlayerGui")
        or Services.Player:WaitForChild("PlayerGui", 10)
    if not App.Alive then return end
    if not App.GuiParent then error("No accessible UI parent found") end
    App.Adapter = makeAdapter(Services, Core)
    App.Adapter:start(App.Maid)
    App.UI = makeUI(App)
    App:Load(false)
    App:Scan()
    App.Maid:give(function()
        for model, view in pairs(App.Visuals) do view.maid:clean() App.Visuals[model] = nil end
    end)
    local binding = "NightfallBloxStrike_" .. App.Id
    App.Maid:give(function() Services.RunService:UnbindFromRenderStep(binding) end)
    Services.RunService:BindToRenderStep(binding, Enum.RenderPriority.Last.Value + 1, function(delta)
        if not App.Alive then return end
        local ok, problem = xpcall(function() App:Render(delta) end, debug.traceback)
        if not ok then App:Error("render", problem) end
    end)
    local scanElapsed, statusElapsed, fpsElapsed, fpsFrames, traceElapsed = 0, 0, 0, 0, 0
    App:Connect(Services.RunService.Heartbeat, function(delta)
        scanElapsed, statusElapsed, fpsElapsed = scanElapsed + delta, statusElapsed + delta, fpsElapsed + delta
        traceElapsed = traceElapsed + delta
        if traceElapsed >= 0.25 then traceElapsed = 0 App:RecordTrace() end
        if scanElapsed >= 0.25 then scanElapsed = 0 App:Scan() end
        if fpsElapsed >= 1 then
            App.Stats.fps = (App.RenderFrames - fpsFrames) / fpsElapsed
            fpsFrames, fpsElapsed = App.RenderFrames, 0
        end
        if statusElapsed >= 0.2 then statusElapsed = 0 App:UpdateStatus() end
    end)
    App:UpdateStatus()
    App:Notify("Nightfall loaded. F1 menu / F6 save / F10 full unload")
    print("[Nightfall] Source build " .. Core.Version .. "; GameId=" .. tostring(game.GameId)
        .. "; character path=" .. App.Adapter.folderPath)
end, debug.traceback)
if not startupOK then
    App:Destroy("startup failed")
    warn("[Nightfall] Startup failed: " .. tostring(startupError))
end


