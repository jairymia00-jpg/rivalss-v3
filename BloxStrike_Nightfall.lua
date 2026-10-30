-- Nightfall BloxStrike v1.0.0 - original, self-contained source
-- F1: menu | F6: save profile | F10: full unload
-- Live BloxStrike/executor compatibility must be verified in Roblox.
-- No external scripts or UI libraries are downloaded by this file.

local Core = (function()
-- Original Nightfall logic. This module is also exercised by the offline tests.
local Core = {}
Core.Version = "1.0.0"
Core.Schema = {
    AimEnabled = {"boolean", false},
    AimFOV = {"number", 150, 25, 500, 1},
    AimSmooth = {"number", 6, 0, 20, 1},
    AimPart = {"enum", "Head", {"Head", "Torso", "Root"}},
    AimPriority = {"enum", "Crosshair", {"Crosshair", "Distance"}},
    AimVisibleOnly = {"boolean", true},
    AimSticky = {"boolean", false},
    AimDistance = {"number", 2000, 50, 5000, 50},
    ShowFOV = {"boolean", true},
    ESPEnabled = {"boolean", true},
    ESPBoxes = {"boolean", true},
    ESPNames = {"boolean", true},
    ESPHealth = {"boolean", true},
    ESPDistance = {"boolean", true},
    ESPSkeleton = {"boolean", false},
    ESPTracers = {"boolean", false},
    ESPOutline = {"boolean", false},
    ESPVisibleOnly = {"boolean", false},
    ESPTeammates = {"boolean", false},
    ESPDistanceLimit = {"number", 3000, 50, 6000, 50},
    IncludePlayers = {"boolean", true},
    IncludeBots = {"boolean", true},
    TeamCheck = {"boolean", true},
    AllowUnknownTeams = {"boolean", false},
    TeamMode = {"enum", "Auto", {"Auto", "Teams", "FFA"}},
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
    return result
end

function Core.flag(value)
    return value == true or value == 1 or value == "true" or value == "True"
end

function Core.team(value)
    if type(value) ~= "string" then return nil end
    local normalized = string.lower(value):gsub("[^%w]", "")
    if normalized == "ct" or normalized == "counterterrorist" or normalized == "counterterrorists" then
        return "CT"
    end
    if normalized == "t" or normalized == "terrorist" or normalized == "terrorists" then return "T" end
    if normalized == "" or normalized == "none" or normalized == "spectator"
        or normalized == "spectators" or normalized == "neutral" then return nil end
    return string.lower(value)
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
    local health = Core.finite(ownerHealth) and ownerHealth
        or (Core.finite(modelHealth) and modelHealth)
        or (Core.finite(humanoidHealth) and humanoidHealth) or nil
    local dead = Core.flag(modelDead) or Core.flag(ownerDead)
    for _, number in pairs({modelHealth, ownerHealth, humanoidHealth}) do
        if Core.finite(number) and number <= 0 then dead = true end
    end
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
    if purpose == "aim" and not row.lifeKnown then return false, "health unknown" end
    if settings.TeamCheck then
        if row.relation == "friendly" and not (purpose == "esp" and settings.ESPTeammates) then
            return false, "teammate"
        end
        if row.relation == "unknown" and not settings.AllowUnknownTeams then return false, "team unknown" end
    end
    return true
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
    local Adapter = {records = {}, folder = nil, folderPath = "waiting", truncated = false}
    local ownersByName, ownersById = {}, {}
    local torsoNames = {"UpperTorso", "Torso", "LowerTorso"}
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
            local item = model:FindFirstChild(name)
            if item and item:IsA("BasePart") then return item end
        end
        return nil
    end

    function Adapter:owner(model)
        local found = Players:GetPlayerFromCharacter(model)
        if found then return found end
        local id = numeric(model:GetAttribute("UserId") or model:GetAttribute("PlayerUserId"))
        return (id and ownersById[id]) or ownersByName[model.Name]
    end

    function Adapter:team(model, owner)
        local result = owner and Core.team(owner:GetAttribute("Team"))
        if result then return result end
        result = Core.team(model:GetAttribute("Team"))
        if result then return result end
        local skin = model:GetAttribute("CharacterName")
        if skin ~= nil then
            local ct, t = World:GetAttribute("CTCharacter"), World:GetAttribute("TCharacter")
            if ct ~= t then
                if ct ~= nil and skin == ct then return "CT" end
                if t ~= nil and skin == t then return "T" end
            end
        end
        local node = model.Parent
        while node and node ~= World and node ~= self.folder do
            result = Core.team(node.Name)
            if result == "CT" or result == "T" then return result end
            node = node.Parent
        end
        return owner and owner.Team and Core.team(owner.Team.Name) or nil
    end

    function Adapter:life(record)
        local model, owner, humanoid = record.model, record.owner, record.humanoid
        if not model.Parent then return {alive = false, known = true} end
        local maximum = numeric(owner and owner:GetAttribute("MaxHealth"))
            or numeric(model:GetAttribute("MaxHealth"))
            or (humanoid and humanoid.MaxHealth)
        return Core.life(numeric(model:GetAttribute("Health")),
            numeric(owner and owner:GetAttribute("Health")), humanoid and humanoid.Health,
            maximum, model:GetAttribute("Dead"), owner and owner:GetAttribute("Dead"))
    end

    function Adapter:scan()
        table.clear(ownersByName)
        table.clear(ownersById)
        for _, owner in ipairs(Players:GetPlayers()) do
            ownersByName[owner.Name], ownersById[owner.UserId] = owner, owner
        end
        self.folder = World:FindFirstChild("Characters") or World:FindFirstChild("characters")
        self.folderPath = self.folder and self.folder:GetFullName() or "Player.Character fallback; bot folder missing"
        self.truncated = false
        local found, ownerModels = {}, {}
        local function consider(model, inFolder)
            if not model:IsA("Model") or found[model] then return end
            local head = part(model, {"Head"})
            local root = part(model, {"HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso"})
            if not head or not root then return end
            local owner = self:owner(model)
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local health = numeric(model:GetAttribute("Health"))
            if not owner and not humanoid and health == nil then return end
            local record = self.records[model] or {model = model}
            record.owner, record.humanoid, record.head, record.root = owner, humanoid, head, root
            record.bot = owner == nil
            record.self = owner == Me or model == Me.Character or model.Name == Me.Name
            record.name = owner and owner.DisplayName or model.Name
            record.body, record.bones = {}, {}
            local byName = {}
            for _, item in ipairs(model:GetChildren()) do
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
            local life = self:life(record)
            local score = (life.alive and 10 or 0) + (inFolder and 5 or 0)
            if owner and ownerModels[owner] then
                local previous = ownerModels[owner]
                if previous.score >= score then return end
                found[previous.model] = nil
            end
            found[model] = record
            if owner then ownerModels[owner] = {model = model, score = score} end
        end
        if self.folder then
            local descendants = self.folder:GetDescendants()
            self.truncated = #descendants > 12000
            for index = 1, math.min(#descendants, 12000) do consider(descendants[index], true) end
        end
        for _, owner in ipairs(Players:GetPlayers()) do
            if owner.Character and not ownerModels[owner] then consider(owner.Character, false) end
        end
        self.records = found
        return found
    end

    function Adapter:localContext(settings)
        local model = Me.Character
        for _, record in pairs(self.records) do
            if record.self then model = record.model break end
        end
        local localTeam = Core.team(Me:GetAttribute("Team"))
            or (model and self:team(model, Me))
            or (Me.Team and Core.team(Me.Team.Name))
        local mode = World:GetAttribute("Gamemode") or World:GetAttribute("GameMode") or "unknown"
        local freeForAll = Core.ffa(mode, World:GetAttribute("FreeForAll"), settings.TeamMode)
        local localAlive = model ~= nil and model.Parent ~= nil and not Core.flag(Me:GetAttribute("Dead"))
        if model then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local life = Core.life(numeric(model:GetAttribute("Health")), numeric(Me:GetAttribute("Health")),
                humanoid and humanoid.Health, nil, model:GetAttribute("Dead"), Me:GetAttribute("Dead"))
            localAlive = localAlive and life.alive
        end
        return model, localTeam, freeForAll, tostring(mode), localAlive
    end

    function Adapter:aimPart(record, selected)
        if selected == "Head" then return part(record.model, {"Head"}) end
        if selected == "Torso" then return part(record.model, torsoNames) end
        return part(record.model, {"HumanoidRootPart"})
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
        {"mode", "Game mode"}, {"aim", "Aim state"}, {"target", "Current target"}, {"save", "Profile"}}) do
        status(overview, item[1], item[2])
    end
    local controls = card("Overview", 1, "Controls")
    note(controls, "F1  Show / hide menu\nF6  Save current settings\nF10  Stop and fully unload", 67)
    local counts = card("Overview", 2, "Target cache")
    for _, item in ipairs({{"players", "Player models"}, {"bots", "Bot models"}, {"eligible", "Aim eligible"},
        {"visible", "ESP drawn"}, {"unknown", "Unknown teams"}, {"dead", "Dead / removed"},
        {"fps", "Render FPS"}, {"errors", "Runtime errors"}}) do status(counts, item[1], item[2]) end
    local availability = card("Overview", 2, "Data availability")
    UI.Availability = note(availability, "Waiting for the first character scan.", 100)

    local aim = card("Aim", 1, "Aim assist")
    toggle(aim, "AimEnabled", "Enable aim", "Hold RMB while the menu is closed")
    slider(aim, "AimFOV", "FOV radius", " px")
    slider(aim, "AimSmooth", "Smoothing", "")
    note(aim, "0 = instant camera snap. Higher values turn more slowly.", 36)
    toggle(aim, "AimSticky", "Keep current target", "Otherwise choose the closest valid target")
    local aiming = card("Aim", 2, "Target selection")
    choice(aiming, "AimPart", "Aim at")
    choice(aiming, "AimPriority", "Target priority")
    toggle(aiming, "AimVisibleOnly", "Visible targets only", "Raycast checks are repeated while aiming")
    slider(aiming, "AimDistance", "Maximum range", " st")
    toggle(aiming, "ShowFOV", "Show FOV circle")
    note(aiming, "Aim runs independently of the ESP toggle. Distance is shown in Roblox studs.", 46)

    local visuals = card("Visuals", 1, "ESP")
    toggle(visuals, "ESPEnabled", "Enable ESP")
    toggle(visuals, "ESPBoxes", "Thin boxes")
    toggle(visuals, "ESPNames", "Names + bot label")
    toggle(visuals, "ESPHealth", "Live health")
    toggle(visuals, "ESPDistance", "Distance")
    toggle(visuals, "ESPSkeleton", "Skeleton")
    toggle(visuals, "ESPTracers", "Bottom tracers")
    toggle(visuals, "ESPOutline", "Character outline")
    local filters = card("Visuals", 2, "Display filters")
    toggle(filters, "ESPVisibleOnly", "Visible ESP only", "Off allows overlays through walls")
    toggle(filters, "ESPTeammates", "Also show teammates", "This never enables aim at teammates")
    slider(filters, "ESPDistanceLimit", "Maximum ESP range", " st")
    note(filters, "Health bars require a known maximum. Missing health is shown as HP ?, not a guessed value.", 62)
    note(filters, "Bot colors are amber. Teammates are blue. The selected target is mint.", 43)

    local targets = card("Targets", 1, "Included targets")
    toggle(targets, "IncludePlayers", "Players")
    toggle(targets, "IncludeBots", "Bots / NPCs", "Reads live character models, not just Players")
    toggle(targets, "TeamCheck", "Skip teammates")
    toggle(targets, "AllowUnknownTeams", "Allow unknown teams", "Off waits for reliable team information")
    choice(targets, "TeamMode", "Team mode")
    local targetInfo = card("Targets", 2, "Recognition")
    note(targetInfo, "Reads the Characters folder, character health/dead attributes, Humanoids, team folders and team attributes.", 83)
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
    selectTab("Overview")
    UI:Refresh()
    return UI
end

end)()

-- Nightfall BloxStrike bootstrap. Core, Resources, makeAdapter and makeUI are bundled above.
local Services = {
    Players = game:GetService("Players"), Workspace = game:GetService("Workspace"),
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
local INSTANCE_KEY, SAVE_KEY = "__NightfallBloxStrikeV1", "__NightfallBloxStrikeProfilesV1"
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
    ProfileFile = "Nightfall_BloxStrike_v1_" .. tostring(game.GameId) .. ".json",
    Stats = {players = 0, bots = 0, eligible = 0, visible = 0, unknown = 0, dead = 0, fps = 0},
    AimStatus = "OFF", AimWrites = 0, RenderFrames = 0,
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
    if self.UI then self.UI:Refresh() end
end
function App:SetMenu(open)
    if not self.Alive then return end
    self.MenuOpen, self.Target = open == true, nil
    if self.UI then self.UI:EndDrag() self.UI:Refresh() end
end
function App:Reset()
    self.Settings, self.Dirty, self.Target = Core.settings(), true, nil
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

-- Register emergency cleanup before constructing the UI.
App:Connect(Services.Input.InputBegan, function(input)
    local focused = Services.Input:GetFocusedTextBox()
    local action = Core.action(input.KeyCode.Name, focused ~= nil)
    if action == "unload" then App:Destroy("F10")
    elseif action == "menu" then App:SetMenu(not App.MenuOpen)
    elseif action == "save" then App:Save() end
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
    App.Focused = false
    if App.UI then App.UI:EndDrag() end
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
    view.boxStroke = uiObject("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 1}, view.box)
    view.name, view.detail = visualLabel(root, 12), visualLabel(root, 10)
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
    self.Adapter:scan()
    for model, view in pairs(self.Visuals) do
        if not self.Adapter.records[model] then view.maid:clean() self.Visuals[model] = nil end
    end
end

local function bounds(record, camera)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local found = false
    for _, part in ipairs(record.body) do
        if part.Parent and part:IsDescendantOf(record.model) then
            local cf, half = part.CFrame, part.Size * 0.5
            local pos, right, up, look = cf.Position, cf.RightVector, cf.UpVector, cf.LookVector
            if finiteVector(pos) and finiteVector(half) then
                local ex = math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z
                local ey = math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z
                local ez = math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
                minX, minY, minZ = math.min(minX, pos.X - ex), math.min(minY, pos.Y - ey), math.min(minZ, pos.Z - ez)
                maxX, maxY, maxZ = math.max(maxX, pos.X + ex), math.max(maxY, pos.Y + ey), math.max(maxZ, pos.Z + ez)
                found = true
            end
        end
    end
    if not found then return nil end
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    for x = 0, 1 do for y = 0, 1 do for z = 0, 1 do
        local projected = camera:WorldToViewportPoint(Vector3.new(x == 0 and minX or maxX,
            y == 0 and minY or maxY, z == 0 and minZ or maxZ))
        if projected.Z <= 0.05 or not finiteVector(projected) then return nil end
        left, right = math.min(left, projected.X), math.max(right, projected.X)
        top, bottom = math.min(top, projected.Y), math.max(bottom, projected.Y)
    end end end
    local width, height = right - left, bottom - top
    local viewport = camera.ViewportSize
    if width < 2 or height < 2 or width > viewport.X * 2 or height > viewport.Y * 2
        or right < 0 or left > viewport.X or bottom < 0 or top > viewport.Y then return nil end
    return left, top, width, height
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
function App:Visible(row, camera, localModel)
    if not row.part or not row.part.Parent then return false end
    local exclusions = {camera}
    if localModel then exclusions[#exclusions + 1] = localModel end
    rayParams.FilterDescendantsInstances = exclusions
    local origin, destination = camera.CFrame.Position, row.part.Position
    if not finiteVector(destination) or (destination - origin).Magnitude < 0.01 then return false end
    local ok, hit = pcall(Services.Workspace.Raycast, Services.Workspace, origin, destination - origin, rayParams)
    if not ok then
        self.VisibilityError = tostring(hit)
        return false
    end
    return hit == nil or hit.Instance:IsDescendantOf(row.model)
end
function App:DrawRecord(row, camera, localModel)
    local config, record = self.Settings, row.record
    local previousView = self.Visuals[row.model]
    if not config.ESPEnabled or not Core.eligible(row, config, "esp") or row.distance > config.ESPDistanceLimit then
        if previousView then self:HideVisual(previousView) end
        return false
    end
    if config.ESPVisibleOnly then
        local now = os.clock()
        if now - (record.visibleAt or -math.huge) > 0.1 then
            record.visibleAt, record.visible = now, self:Visible(row, camera, localModel)
        end
        if not record.visible then if previousView then self:HideVisual(previousView) end return false end
    end
    local x, y, width, height = bounds(record, camera)
    if not x then if previousView then self:HideVisual(previousView) end return false end
    local view = previousView or self:EnsureVisual(record)
    view.root.Visible = true
    local color = self.UI:Accent()
    if row.relation == "friendly" then color = Color3.fromRGB(104, 176, 255)
    elseif row.bot then color = Color3.fromRGB(246, 191, 91) end
    if self.Target and self.Target.model == row.model then color = Color3.fromRGB(89, 234, 186) end
    view.box.Visible, view.boxStroke.Color = config.ESPBoxes, color
    view.box.Position, view.box.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(width, height)
    view.name.Visible, view.name.TextColor3 = config.ESPNames, color
    view.name.Position = UDim2.fromOffset(x + width / 2, y - 20)
    view.name.Text = record.name .. (row.bot and " [BOT]" or "")
    local details = {}
    if config.ESPHealth then details[#details + 1] = row.health and (tostring(math.floor(row.health + 0.5)) .. " HP") or "HP ?" end
    if config.ESPDistance then details[#details + 1] = tostring(math.floor(row.distance + 0.5)) .. " st" end
    view.detail.Visible, view.detail.Text = #details > 0, table.concat(details, "  |  ")
    view.detail.Position = UDim2.fromOffset(x + width / 2, y + height + 3)
    view.health.Visible = config.ESPHealth and row.health ~= nil and row.maximum ~= nil
    if view.health.Visible then
        local ratio = math.clamp(row.health / row.maximum, 0, 1)
        view.health.Position, view.health.Size = UDim2.fromOffset(x - 6, y), UDim2.fromOffset(3, height)
        view.fill.Size = UDim2.fromScale(1, ratio)
        view.fill.BackgroundColor3 = Color3.fromRGB(244, 100, 116):Lerp(Color3.fromRGB(89, 218, 166), ratio)
    end
    view.tracer.Visible = false
    if config.ESPTracers then
        setLine(view.tracer, Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y - 14),
            Vector2.new(x + width / 2, y + height), color, 1)
    end
    for _, line in ipairs(view.bones) do line.Visible = false end
    if config.ESPSkeleton then
        for index, pair in ipairs(record.bones) do
            if pair[1].Parent and pair[2].Parent then
                local a, b = camera:WorldToViewportPoint(pair[1].Position), camera:WorldToViewportPoint(pair[2].Position)
                if a.Z > 0.05 and b.Z > 0.05 then
                    if not view.bones[index] then view.bones[index] = makeLine(view.root) end
                    setLine(view.bones[index], a, b, color, 1)
                end
            end
        end
    end
    if config.ESPOutline and not view.highlight then
        local highlight = Instance.new("Highlight")
        view.highlight = highlight
        view.maid:give(function() highlight:Destroy() end)
        highlight.Name = "Nightfall_" .. self.Id
        highlight.Adornee, highlight.FillTransparency = row.model, 1
        highlight.OutlineTransparency = 0.1
        highlight.Parent = row.model
    end
    if view.highlight then
        view.highlight.Enabled = config.ESPOutline
        view.highlight.OutlineColor = color
        view.highlight.DepthMode = config.ESPVisibleOnly and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
    end
    return config.ESPBoxes or config.ESPNames or config.ESPHealth or config.ESPDistance
        or config.ESPTracers or config.ESPSkeleton or config.ESPOutline
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
    local rows, present, stats = {}, {}, {players = 0, bots = 0, eligible = 0, visible = 0, unknown = 0, dead = 0, fps = self.Stats.fps}
    local center, origin = viewport / 2, camera.CFrame.Position
    for _, record in pairs(self.Adapter.records) do
        local model = record.model
        if not record.self and model.Parent and record.root.Parent then
            local life = self.Adapter:life(record)
            local part = self.Adapter:aimPart(record, self.Settings.AimPart)
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
                rows[#rows + 1] = row
                present[model] = true
                if row.bot then stats.bots += 1 else stats.players += 1 end
                if not row.alive then stats.dead += 1 end
                if row.alive and row.relation == "unknown" then stats.unknown += 1 end
                if Core.eligible(row, self.Settings, "aim") and row.hasPart then stats.eligible += 1 end
            end
        end
    end
    local typing = Services.Input:GetFocusedTextBox() ~= nil
    local active = self.Settings.AimEnabled and localAlive and not self.MenuOpen and not typing and self.Focused
    local sticky = self.Target and self.Target.model
    self.Target = active and Core.pick(rows, self.Settings,
        function(row) return self:Visible(row, camera, localModel) end, sticky) or nil
    if not self.Settings.AimEnabled then self.AimStatus = "OFF"
    elseif not self.Focused then self.AimStatus = "WINDOW UNFOCUSED"
    elseif self.MenuOpen then self.AimStatus = "MENU PAUSED"
    elseif typing then self.AimStatus = "TYPING PAUSED"
    elseif not localAlive then self.AimStatus = "WAITING FOR SPAWN"
    elseif not self.Target then self.AimStatus = "NO VALID TARGET"
    elseif Services.Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local position = self.Target.part.Position
        if (position - origin).Magnitude > 0.01 then
            local desired = CFrame.lookAt(origin, position, camera.CFrame.UpVector)
            camera.CFrame = camera.CFrame:Lerp(desired, Core.alpha(self.Settings.AimSmooth, delta))
            self.AimWrites += 1
            self.AimStatus = "AIMING / RMB"
        end
    else self.AimStatus = "READY / HOLD RMB" end
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

function App:UpdateStatus()
    local ui, stats = self.UI, self.Stats
    local hasFolder = self.Adapter.folder ~= nil
    ui:Status("camera", self.CameraPresent and "AVAILABLE" or "WAITING", self.CameraPresent and "Green" or "Amber")
    ui:Status("cache", hasFolder and "CHARACTERS" or "FALLBACK", hasFolder and "Green" or "Amber")
    ui:Status("team", self.IsFFA and "FFA" or self.LocalTeam or "UNKNOWN", (self.LocalTeam or self.IsFFA) and "Green" or "Amber")
    ui:Status("mode", self.Mode or "unknown")
    ui:Status("aim", self.AimStatus, self.AimStatus == "AIMING / RMB" and "Green" or "Muted")
    ui:Status("target", self.Target and self.Target.record.name or "none")
    ui:Status("save", self.ProfileStatus, self.Dirty and "Amber" or "Muted")
    for _, key in ipairs({"players", "bots", "eligible", "visible", "unknown", "dead"}) do ui:Status(key, stats[key], "Text") end
    ui:Status("fps", math.floor(stats.fps + 0.5), "Text")
    ui:Status("errors", self.ErrorCount, self.ErrorCount > 0 and "Red" or "Muted")
    local total = stats.players + stats.bots
    ui.SideStatus.Text = total > 0 and (tostring(total) .. " models detected") or "Waiting for targets"
    ui.SideStatus.TextColor3 = total > 0 and Color3.fromRGB(89, 218, 166) or Color3.fromRGB(246, 191, 91)
    ui.HUDText.Text = string.format("NIGHTFALL  |  P %d / B %d  |  %s  |  F1 MENU", stats.players, stats.bots, self.AimStatus)
    local availability = hasFolder and "Character folder found. " or "Character folder missing; bot support is pending. "
    if total == 0 then availability ..= "No live target models detected yet. " end
    if stats.unknown > 0 then availability ..= tostring(stats.unknown) .. " models have unknown team data. " end
    if self.Adapter.truncated then availability ..= "Scan limit reached. " end
    if self.VisibilityError then availability ..= "Raycast unavailable: " .. self.VisibilityError .. " " end
    if self.LastError ~= "" then availability ..= "Latest error: " .. self.LastError end
    if availability == "Character folder found. " then
        availability ..= "Target data is available; this does not validate shot accuracy or server hits."
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
    App.UI = makeUI(App)
    App:Load(false)
    App:Scan()
    App.Maid:give(function()
        for model, view in pairs(App.Visuals) do view.maid:clean() App.Visuals[model] = nil end
    end)
    local binding = "NightfallBloxStrike_" .. App.Id
    App.Maid:give(function() Services.RunService:UnbindFromRenderStep(binding) end)
    Services.RunService:BindToRenderStep(binding, Enum.RenderPriority.Camera.Value + 10, function(delta)
        if not App.Alive then return end
        local ok, problem = xpcall(function() App:Render(delta) end, debug.traceback)
        if not ok then App:Error("render", problem) end
    end)
    local scanElapsed, statusElapsed, fpsElapsed, fpsFrames = 0, 0, 0, 0
    App:Connect(Services.RunService.Heartbeat, function(delta)
        scanElapsed, statusElapsed, fpsElapsed = scanElapsed + delta, statusElapsed + delta, fpsElapsed + delta
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
