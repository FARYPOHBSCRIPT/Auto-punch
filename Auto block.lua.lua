print("[Swesaken] === SCRIPT START ===")

-- [FIX] 缩短初始等待，方便调试
task.wait(1)
print("[Swesaken] Fetching WindUI...")

local WindUI
local ok, err = pcall(function()
    WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)
if not ok or not WindUI then
    warn("[Swesaken] WindUI 加载失败: " .. tostring(err))
    return
end
print("[Swesaken] WindUI loaded OK")

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local TextChatService   = game:GetService("TextChatService")
local HttpService       = game:GetService("HttpService")
local TeleportService   = game:GetService("TeleportService")
local lp     = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ==========================================
-- [FIX] 游戏模块改为软检查（不再提前 return）
-- ==========================================
local Modules      = ReplicatedStorage:FindFirstChild("Modules")
local Network      = Modules and Modules:FindFirstChild("Network")
local InnerNetwork = Network and Network:FindFirstChild("Network")
local testRemote   = InnerNetwork and InnerNetwork:FindFirstChild("RemoteEvent")

local NetworkModule
if InnerNetwork then
    local rok, res = pcall(require, InnerNetwork)
    if rok then
        NetworkModule = res
        print("[Swesaken] NetworkModule OK")
    else
        warn("[Swesaken] require(InnerNetwork) 失败: " .. tostring(res))
    end
end
if not (Modules and Network and InnerNetwork and testRemote) then
    warn("[Swesaken] 部分游戏模块缺失，部分功能将不可用（UI 仍会加载）")
end

local PlayersFolder = Workspace:FindFirstChild("Players")
if not PlayersFolder then
    print("[Swesaken] Waiting for Workspace.Players (up to 30s)...")
    local startT = tick()
    repeat
        task.wait(1)
        PlayersFolder = Workspace:FindFirstChild("Players")
        local elapsed = math.floor(tick() - startT)
        if not PlayersFolder and elapsed > 0 and elapsed % 5 == 0 then
            print(string.format("[Swesaken] Still waiting... %ds", elapsed))
        end
    until PlayersFolder or (tick() - startT) > 30
end

local KillersFolder, SurvivorsFolder
if PlayersFolder then
    print("[Swesaken] Workspace.Players found!")
    KillersFolder   = PlayersFolder:FindFirstChild("Killers")   or PlayersFolder:WaitForChild("Killers", 10)
    SurvivorsFolder = PlayersFolder:FindFirstChild("Survivors") or PlayersFolder:WaitForChild("Survivors", 10)
end

if not (PlayersFolder and KillersFolder and SurvivorsFolder) then
    warn("[Swesaken] Missing Workspace.Players/Killers/Survivors! Using placeholders.")
    PlayersFolder   = PlayersFolder   or Instance.new("Folder")
    KillersFolder   = KillersFolder   or Instance.new("Folder")
    SurvivorsFolder = SurvivorsFolder or Instance.new("Folder")
else
    print("[Swesaken] Killers & Survivors folders OK")
end

print("[Swesaken] Environment ready. Building UI...")

-- ==========================================
-- 全局配置变量
-- ==========================================
local SwesakenAutoBlockEnabled = false
local SwesakenBaseHitboxSize = Vector3.new(4.5, 6, 7.5)
local SwesakenHitboxScale = 1.6
local SwesakenHitboxWidthScale = 1.0
local SwesakenHitboxOffset = -1.4
local SwesakenHitboxFrontBackOffset = 0
local SwesakenShowOutline = true
local SwesakenOutlineThickness = 0.01
local SwesakenShowHitboxVisual = true
local SwesakenHitboxTransparency = 0.5
local SwesakenHitboxDuration = 1.5
local SwesakenBlockDelay = 0
local SwesakenLastAbilityLastUsed, SwesakenLastAbilitiesUsed, SwesakenBlockLocked = nil, nil, false

local hitboxDraggingTech = false
local Dspeed, Ddelay = 7.5, 0
local HDT_Duration, HDT_StopDistance = 1.2, 2.5
local HDT_TurnSmoothness = 5
local HDT_DetectRange = 30
local HDT_GraceAfterBlock = 0.35
local HDT_MinDuration = 0.8
local _hdt_lastBlockTrack = nil
local _hitboxDraggingDebounce = false

local MyAnimLockOn = false
local lastAimTrigger = {}
local AIM_COOLDOWN, AIM_WINDOW, predictionValue = 0.8, 0.8, 4
local aimPunchToggles = { ["Character Lock"] = true, ["Camera Lock"] = false }
local autoPunchEventEnabled = false
local lastPunchFire = 0

local _speedEnabled, _speedValue = false, 16
local _flightEnabled, _flightSpeed, _flightLoop = false, 50, nil
local _fovEnabled, _fovValue, _fovSetting = false, 70, nil
local _silentAimEnabled, _silentAimConn, _silentAimDistance = false, nil, 100
local _generalAimEnabled, _generalAimConn, _generalAimSmoothness = false, nil, 20
local _antiLagActive = false
local _antiLagSaved = { Lighting = {}, PostEffects = {}, Objects = {}, OriginalQuality = nil, GlobalShadows = nil }
local _antiLagConn = nil
local _deleteFakeNoliEnabled = false
local _c00lkiddDashTurnConn = nil
local _autoBreakFreeEnabled, _autoBreakFreeTask = false, nil
local _autoPullRopeEnabled, _autoPullRopeTask = false, nil
local _showChatEnabled = false

local _survivorSkill404Enabled = false
local _survivorSkill404Range = 25
local _survivorSkill404Cooldown = 1.0
local _lastSurvivorSkill404Time = 0
local _survivorSkillRagingEnabled = false
local _survivorSkillRagingRange = 25
local _survivorSkillRagingCooldown = 1.0
local _lastSurvivorSkillRagingTime = 0
local _stunSkillAnimIds = {}

-- ==========================================
-- [FIX] 缺失函数的占位实现（防止点开关报错）
-- ==========================================
local function _notImplemented(name)
    return function()
        if WindUI and WindUI.Notify then
            pcall(function()
                WindUI:Notify({ Title = "未实现", Content = name .. " 功能未实现", Duration = 2 })
            end)
        end
    end
end

-- 那些脚本里引用但没定义的回调，全部给个占位
VX_NoilStarAim             = _notImplemented("Star Bomb Aim")
VX_NoilVoidAim             = _notImplemented("Void Rush Aim")
VX_enableAzureQTE          = _notImplemented("Azure QTE")
VX_disableAzureQTE         = function() end
VX_enableC00lkiddDashTurn  = _notImplemented("c00lkidd Dash Turn")
VX_disableC00lkiddDashTurn = function() end
VX_startBreakFree          = _notImplemented("Auto Break Free")
VX_startPullRope           = _notImplemented("Auto Pull Rope")
VX_startFlight             = _notImplemented("Flight")
VX_stopFlight              = function() end
setAntiLag                 = function() end
_applyHideInjury           = function() end
_applyDisableBlindness     = function() end
_updateStaminaCallbacks    = function() end
_unlimitedStamina          = false
_enableMaxStamina          = false
_maxStaminaVal             = 100
_enableMinStamina          = false
_minStaminaVal             = 0
_enableStaminaGain         = false
_staminaGainVal            = 20
_enableStaminaLoss         = false
_staminaLossVal            = 10
_enableSprintSpeed         = false
_sprintSpeedVal            = 26
_antiAcid                  = false

-- ==========================================
-- 设备伪装模块
-- ==========================================
local _deviceSpoofEnabled = false
local _deviceSpoofTarget  = "Mobile"

local function _safePlat(name)
    local pok, v = pcall(function() return Enum.Platform[name] end)
    if pok and v then return v end
    return nil
end

local DeviceSpoofProfiles = {
    PC      = { props = { TouchEnabled=false, KeyboardEnabled=true,  MouseEnabled=true,  GamepadEnabled=false, AccelerometerEnabled=false, GyroscopeEnabled=false, VREnabled=false }, platform = _safePlat("Windows") },
    Mobile  = { props = { TouchEnabled=true,  KeyboardEnabled=false, MouseEnabled=false, GamepadEnabled=false, AccelerometerEnabled=true,  GyroscopeEnabled=true,  VREnabled=false }, platform = _safePlat("Android") },
    Tablet  = { props = { TouchEnabled=true,  KeyboardEnabled=false, MouseEnabled=false, GamepadEnabled=false, AccelerometerEnabled=true,  GyroscopeEnabled=true,  VREnabled=false }, platform = _safePlat("Android") },
    Console = { props = { TouchEnabled=false, KeyboardEnabled=false, MouseEnabled=false, GamepadEnabled=true,  AccelerometerEnabled=false, GyroscopeEnabled=false, VREnabled=false }, platform = _safePlat("XBoxOne") or _safePlat("XboxOne") },
    VR      = { props = { TouchEnabled=false, KeyboardEnabled=false, MouseEnabled=false, GamepadEnabled=true,  AccelerometerEnabled=false, GyroscopeEnabled=false, VREnabled=true  }, platform = _safePlat("Oculus") },
}

local function sendDeviceSpoofToServer(target)
    if not NetworkModule then return end
    pcall(function()
        NetworkModule:FireServerConnection("SetDevice", "REMOTE_EVENT", target)
    end)
end

local _deviceSpoofInstalled = false
local function installDeviceSpoof()
    if _deviceSpoofInstalled then return true end
    if type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function" or type(newcclosure) ~= "function" then
        return false, "executor_not_supported"
    end
    local ok2, err2 = pcall(function()
        local mt = getrawmetatable(game)
        local oldIndex    = mt.__index
        local oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__index = newcclosure(function(self, key)
            if _deviceSpoofEnabled and self == UserInputService then
                local prof = DeviceSpoofProfiles[_deviceSpoofTarget]
                if prof and prof.props[key] ~= nil then return prof.props[key] end
            end
            return oldIndex(self, key)
        end)
        mt.__namecall = newcclosure(function(self, ...)
            if _deviceSpoofEnabled and self == UserInputService then
                local method = getnamecallmethod()
                if method == "GetPlatform" then
                    local prof = DeviceSpoofProfiles[_deviceSpoofTarget]
                    if prof and prof.platform then return prof.platform end
                end
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
    if ok2 then _deviceSpoofInstalled = true end
    return ok2, err2
end

flow = { on = false, nodeDelay = 0.04 }

local espKillerEnabled, espSurvivorEnabled = false, false
local espEnabledMedkit, espEnabledBloxy = false, false
local espGeneratorsActive, enableTextESP = false, false
local espFakeNoliEnabled, espGraffitiEnabled, espFoldersEnabled = false, false, false
local espPlantTrapsEnabled, espGolemAzureEnabled, espSentryDispEnabled = false, false, false
local espMinionsEnabled, espDeviceEnabled, espPlantZonesEnabled = false, false, false
local espColorKiller, espColorSurvivor = Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0)
local espColorFakeNoli = Color3.fromRGB(255, 0, 255)
local espColorGenerator = Color3.fromRGB(255, 255, 0)
local espColorItem = Color3.fromRGB(210, 255, 210)
local espColorGraffiti = Color3.fromRGB(255, 230, 100)
local espColorFolder = Color3.fromRGB(255, 255, 255)
local espColorPlantTrap = Color3.fromRGB(100, 255, 100)
local espColorGolemAzure = Color3.fromRGB(100, 180, 255)
local espColorSentryDisp = Color3.fromRGB(255, 80, 80)
local espColorMinion = Color3.fromRGB(255, 160, 0)
local espFillTransparency, espOutlineTransparency = 0.7, 0.3
local espTextSize, espOffset = 8, 4
local espCache = setmetatable({}, { __mode = "k" })
local espSignalCache = setmetatable({}, { __mode = "k" })
local generatorProgConns = {}
local heavyCache = setmetatable({}, { __mode = "k" })
local generatorEspCache = setmetatable({}, { __mode = "k" })

-- ★ 2D Box ESP 状态
local _2dBoxEnabled = false
local _2dBoxShowSurvivor = true
local _2dBoxShowKiller = true
local _2dBoxColor = Color3.fromRGB(255, 60, 60)
local _2dBoxShowName = true
local _2dBoxShowHP = true
local _2dBoxShowDist = true
local _2dBoxShowStatus = false
local _2dBoxTagDir = "Top"

-- ★ Anti-Backstab 状态
local _absEnabled = false
local _absRange = 40
local _absDuration = 1.5
local _absVis = false
local _absLocked = false
local _absRings = {}
local _absSoundConn = nil
local _absScanThread = nil
local _absTriggerSounds = { ["86710781315432"] = true, ["99820161736138"] = true }

-- ★ Low Graphics 状态
local _lowGfxEnabled = false
local _lowGfxBackup = { Lighting = {}, Objects = {} }

-- ★ Hidden Info 状态
local _hiddenInfoEnabled = false
local _hiddenInfoOriginals = {}
local _hiddenInfoConn = nil
local _hiddenInfoKeys = { "HideKillerWins", "HidePlaytime", "HideSurvivorWins" }

local blockAnimIds = { "72722244508749","96959123077498","95802026624883","140671644163156","100926346851492","72182155407310","82605295530067","138407964761603","133292581373127","116427323741607","90970641235403","87716278630738","82036084568393","102517104852347","127040663332045" }
local blockAnimSet = {}
for _, id in ipairs(blockAnimIds) do blockAnimSet[id] = true end
local punchAnimSet = {}
for _, id in ipairs({"87259391926321","99100240941590","72685103823181","81905101227053","113936304594883","140703210927645","136007065400978","129843313690921","86709774283672","108807732150251","138040001965654","86096387000557","119850211147676","131696603025265","119462383658044","116618003477002","133491532453922","76649505662612","71190646367497","72182155407310","82605295530067","138407964761603","133292581373127","116427323741607","90970641235403","87716278630738","82036084568393","138936949998619","78440860685556","123825742002486","125854302746190","132298811847315","135209101640984","18568553101","423041300","423041325","423041356","81114852524420","82772022662025","108911997126897","117216912143451","82137285150006","102808968188291","116616310968045","117828699507982"}) do punchAnimSet[id] = true end

-- ==========================================
-- 核心辅助函数
-- ==========================================
local function _getAllPlayerCharacters()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            table.insert(list, p.Character)
        end
    end
    return list
end

local function _aimAtNearest(targets)
    local myHRP = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil end
    local best, bd = nil, math.huge
    for _, ch in ipairs(targets) do
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        if hrp then
            local d = (hrp.Position - myHRP.Position).Magnitude
            if d < bd then bd = d; best = ch end
        end
    end
    return best
end

local function getNearestKillerModel()
    local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    local best, bd = nil, math.huge
    for _, k in ipairs(KillersFolder:GetChildren()) do
        if k and k:IsA("Model") then
            local hrp = k:FindFirstChild("HumanoidRootPart")
            if hrp then
                local d = (hrp.Position - myRoot.Position).Magnitude
                if d < bd then best, bd = k, d end
            end
        end
    end
    return best
end
local function getKillerHRP(m) return m and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart) end

-- [FIX] 加 nil 判断，防止 testRemote 为空时崩溃
local function fireRemoteBlock()
    if not testRemote then return end
    testRemote:FireServer("UseActorAbility", { buffer.fromstring("\003\005\000\000\000Block") })
end

-- ==========================================
-- 发电机三级进度兜底
-- ==========================================
local function GetGeneratorAccurateProgress(genModel)
    if not genModel or not genModel.Parent then return 0 end
    local attr = genModel:GetAttribute("Progress") or genModel:GetAttribute("RepairProgress")
        or genModel:GetAttribute("Percent") or genModel:GetAttribute("CurrentProgress")
    if attr and type(attr) == "number" then
        return attr <= 1 and math.floor(attr * 100) or math.floor(attr)
    end
    for _, desc in ipairs(genModel:GetDescendants()) do
        if desc:IsA("SurfaceGui") or desc:IsA("BillboardGui") then
            for _, bar in ipairs(desc:GetDescendants()) do
                if (bar:IsA("Frame") or bar:IsA("ImageLabel"))
                    and bar.Size.X.Scale > 0 and bar.Size.X.Scale <= 1 then
                    if bar.BackgroundColor3.G > 0.5 and bar.BackgroundColor3.R < 0.5 then
                        return math.floor(bar.Size.X.Scale * 100)
                    end
                end
            end
        end
    end
    local obj = Workspace:FindFirstChild("ObjectiveStorage") or ReplicatedStorage:FindFirstChild("ObjectiveStorage")
    if obj then
        local match = obj:FindFirstChild(genModel.Name)
        if not match then
            for _, val in ipairs(obj:GetChildren()) do
                if val.Name:find(genModel.Name) then match = val; break end
            end
        end
        if match and (match:IsA("IntValue") or match:IsA("NumberValue")) then
            local v = match.Value
            return v <= 1 and math.floor(v * 100) or math.floor(v)
        end
    end
    local prog = genModel:FindFirstChild("Progress") or genModel:FindFirstChild("Progress", true)
    if prog and prog:IsA("NumberValue") then return math.floor(prog.Value) end
    return 0
end

-- ==========================================
-- ESP 核心逻辑
-- ==========================================
local function VX_createPlayerESP(model, color, isKiller)
    if espCache[model] then return end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local hl = Instance.new("Highlight")
    hl.Name = "Swesaken_Highlight"
    hl.Adornee = model
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = espFillTransparency
    hl.OutlineTransparency = espOutlineTransparency
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = model

    local bb = Instance.new("BillboardGui")
    bb.Name = "Swesaken_Billboard"
    bb.Adornee = hrp
    bb.Size = UDim2.new(0, 160, 0, 50)
    bb.StudsOffset = Vector3.new(0, espOffset, 0)
    bb.AlwaysOnTop = true
    bb.Parent = model

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name = "ESP_Name"
    nameLbl.Size = UDim2.new(1, 0, 0.4, 0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = ">w< " .. (isKiller and "Killer-kun" or "Cutie-chan") .. " uwu"
    nameLbl.Font = Enum.Font.Jura
    nameLbl.TextColor3 = color
    nameLbl.TextSize = espTextSize
    nameLbl.TextStrokeTransparency = 0.6
    nameLbl.Visible = enableTextESP
    nameLbl.Parent = bb

    local hpLbl = Instance.new("TextLabel")
    hpLbl.Name = "ESP_HP"
    hpLbl.Size = UDim2.new(1, 0, 0.4, 0)
    hpLbl.Position = UDim2.new(0, 0, 0.4, 0)
    hpLbl.BackgroundTransparency = 1
    hpLbl.Text = "HP uwu"
    hpLbl.Font = Enum.Font.Jura
    hpLbl.TextColor3 = color
    hpLbl.TextSize = espTextSize
    hpLbl.TextStrokeTransparency = 0.6
    hpLbl.Visible = enableTextESP
    hpLbl.Parent = bb

    espCache[model] = { hl = hl, bb = bb, nameLbl = nameLbl, hpLbl = hpLbl, isKiller = isKiller }

    if not espSignalCache[model] then
        espSignalCache[model] = true
        local function upd()
            local rec = espCache[model]; if not rec then return end
            local text = rec.isKiller and "Killer-kun" or "Cutie-chan"
            if rec.nameLbl and rec.nameLbl.Parent then rec.nameLbl.Text = ">w< " .. text .. " uwu" end
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and rec.hpLbl and rec.hpLbl.Parent then
                local h, mh = math.floor(hum.Health), math.floor(hum.MaxHealth)
                local pct = h / math.max(mh, 1)
                local face = "(๑•̀ㅂ•́)و✧"
                if pct <= 0.7 and pct > 0.3 then face = "(｡･ω･｡)"
                elseif pct <= 0.3 then face = "(;´Д`)" end
                rec.hpLbl.Text = string.format("HP %d/%d %s", h, mh, face)
            end
        end
        model:GetAttributeChangedSignal("ActorDisplayName"):Connect(upd)
        model:GetAttributeChangedSignal("SkinNameDisplay"):Connect(upd)
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:GetPropertyChangedSignal("Health"):Connect(upd)
            hum:GetPropertyChangedSignal("MaxHealth"):Connect(upd)
        end
        task.defer(upd)
    end
end

local function VX_removePlayerESP(model)
    local rec = espCache[model]
    if rec then
        pcall(function() if rec.hl then rec.hl:Destroy() end end)
        pcall(function() if rec.bb then rec.bb:Destroy() end end)
        espCache[model] = nil
    end
end

local function VX_refreshKillerESP()
    if not espKillerEnabled then return end
    for _, m in ipairs(KillersFolder:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character then VX_createPlayerESP(m, espColorKiller, true) end
    end
end

local function VX_refreshSurvivorESP()
    if not espSurvivorEnabled then return end
    for _, m in ipairs(SurvivorsFolder:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character then VX_createPlayerESP(m, espColorSurvivor, false) end
    end
end

function onKillerESPToggle(v)
    espKillerEnabled = v
    if v then VX_refreshKillerESP()
    else
        for _, m in ipairs(KillersFolder:GetChildren()) do
            if m:IsA("Model") then VX_removePlayerESP(m) end
        end
    end
end

function onSurvivorESPToggle(v)
    espSurvivorEnabled = v
    if v then VX_refreshSurvivorESP()
    else
        for _, m in ipairs(SurvivorsFolder:GetChildren()) do
            if m:IsA("Model") then VX_removePlayerESP(m) end
        end
    end
end

function onFakeNoliToggle(v)
    espFakeNoliEnabled = v
    if v then
        for _, k in ipairs(KillersFolder:GetChildren()) do
            local isFake = k:GetAttribute("IsFakeNoli") == true or not Players:GetPlayerFromCharacter(k)
            if isFake then
                local h = Instance.new("Highlight")
                h.Name = "VX_ESP_FakeNoli"
                h.Adornee = k
                h.FillColor = espColorFakeNoli
                h.OutlineColor = espColorFakeNoli
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = k
            end
        end
    else
        for _, k in ipairs(KillersFolder:GetChildren()) do
            if k:FindFirstChild("VX_ESP_FakeNoli") then k.VX_ESP_FakeNoli:Destroy() end
        end
    end
end

local function isModelHeldByPlayer(model)
    if Players:GetPlayerFromCharacter(model) then return true end
    if model:FindFirstChildOfClass("Humanoid") then return true end
    local ancestor = model.Parent
    local depth = 0
    while ancestor and depth < 5 do
        if ancestor == Workspace.Players or (Workspace.Players and (ancestor == Workspace.Players:FindFirstChild("Killers") or ancestor == Workspace.Players:FindFirstChild("Survivors"))) then return true end
        ancestor = ancestor.Parent
        depth = depth + 1
    end
    return false
end

local function getItemType(model)
    local n = string.lower(model.Name)
    if n:find("medkit") or n:find("firstaid") or n:find("bandage") or n:find("healthkit") then return "medkit" end
    if n:find("bloxy") or n:find("cola") then return "bloxy" end
    if n:find("generator") and not n:find("fake") then return "generator" end
    if model:FindFirstChildOfClass("Humanoid") then return nil end
    local prog = model:FindFirstChild("Progress") or model:FindFirstChild("Progress", true)
    if prog and prog:IsA("NumberValue") then
        local lowerNames = ""
        for _, d in ipairs(model:GetDescendants()) do
            lowerNames = lowerNames .. string.lower(d.Name) .. " "
            if #lowerNames > 400 then break end
        end
        if not (lowerNames:find("medkit") or lowerNames:find("cola") or lowerNames:find("bloxy")) then
            return "generator"
        end
    end
    return nil
end

local function VX_tryItemHighlight(model)
    if not model or not model.Parent or isModelHeldByPlayer(model) then return end
    local size = Vector3.new(0, 0, 0)
    pcall(function() local _, s = model:GetBoundingBox(); size = s end)
    if size.X > 50 or size.Y > 50 or size.Z > 50 then return end

    local itemType = getItemType(model)
    if not itemType then return end

    local anchor = model:FindFirstChildWhichIsA("BasePart", true) or model
    if not anchor then return end

    if itemType == "medkit" and espEnabledMedkit then
        if model:FindFirstChild("ItemHighlight_Medkit") then return end
        local color = Color3.fromRGB(255, 105, 180)
        local hl = Instance.new("Highlight")
        hl.Name = "ItemHighlight_Medkit"
        hl.Adornee = model
        hl.FillColor = color
        hl.OutlineColor = color
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = model
        local bb = Instance.new("BillboardGui")
        bb.Name = "ItemHighlight_Medkit_bb"
        bb.Adornee = anchor
        bb.Size = UDim2.new(0, 150, 0, 30)
        bb.StudsOffset = Vector3.new(0, 2, 0)
        bb.AlwaysOnTop = true
        bb.MaxDistance = 1000
        bb.Parent = anchor
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "(つ≧▽≦)つ Medkit"
        lbl.TextColor3 = color
        lbl.TextStrokeTransparency = 0.5
        lbl.TextSize = 14
        lbl.Font = Enum.Font.Jura
        lbl.Parent = bb
    elseif itemType == "bloxy" and espEnabledBloxy then
        if model:FindFirstChild("ItemHighlight_Bloxy") then return end
        local color = Color3.fromRGB(0, 150, 255)
        local hl = Instance.new("Highlight")
        hl.Name = "ItemHighlight_Bloxy"
        hl.Adornee = model
        hl.FillColor = color
        hl.OutlineColor = color
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = model
        local bb = Instance.new("BillboardGui")
        bb.Name = "ItemHighlight_Bloxy_bb"
        bb.Adornee = anchor
        bb.Size = UDim2.new(0, 150, 0, 30)
        bb.StudsOffset = Vector3.new(0, 2, 0)
        bb.AlwaysOnTop = true
        bb.MaxDistance = 1000
        bb.Parent = anchor
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "🥤 (๑>؂<๑) Cola"
        lbl.TextColor3 = color
        lbl.TextStrokeTransparency = 0.5
        lbl.TextSize = 14
        lbl.Font = Enum.Font.Jura
        lbl.Parent = bb
    elseif itemType == "generator" and espGeneratorsActive then
        if generatorEspCache[model] or model:FindFirstChild("ItemHighlight_Generator") then return end
        local pct = GetGeneratorAccurateProgress(model)
        generatorEspCache[model] = true

        local color = espColorGenerator
        local hl = Instance.new("Highlight")
        hl.Name = "ItemHighlight_Generator"
        hl.Adornee = model
        hl.FillColor = color
        hl.OutlineColor = color
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = model

        local bb = Instance.new("BillboardGui")
        bb.Name = "ItemHighlight_Generator_bb"
        bb.Adornee = anchor
        bb.Size = UDim2.new(0, 180, 0, 30)
        bb.StudsOffset = Vector3.new(0, espOffset + 2, 0)
        bb.AlwaysOnTop = true
        bb.MaxDistance = 1000
        bb.Parent = anchor

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = string.format("⚡ (ﾉ≧∇≦)ﾉ Generator %d%%", pct)
        lbl.TextColor3 = color
        lbl.TextStrokeTransparency = 0.5
        lbl.TextSize = 14
        lbl.Font = Enum.Font.Jura
        lbl.Parent = bb

        generatorProgConns[model] = RunService.Heartbeat:Connect(function()
            if not lbl.Parent then return end
            local newPct = GetGeneratorAccurateProgress(model)
            local newText = string.format("⚡ (ﾉ≧∇≦)ﾉ Generator %d%%", newPct)
            if lbl.Text ~= newText then lbl.Text = newText end
        end)
    end
end

function onMedkitToggle(v)
    espEnabledMedkit = v
    if not v then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj.Name == "ItemHighlight_Medkit" or obj.Name == "ItemHighlight_Medkit_bb" then pcall(function() obj:Destroy() end) end
        end
    end
end

function onBloxyToggle(v)
    espEnabledBloxy = v
    if not v then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj.Name == "ItemHighlight_Bloxy" or obj.Name == "ItemHighlight_Bloxy_bb" then pcall(function() obj:Destroy() end) end
        end
    end
end

function onGenToggle(v)
    espGeneratorsActive = v
    if not v then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj.Name == "ItemHighlight_Generator" or obj.Name == "ItemHighlight_Generator_bb" then
                pcall(function() obj:Destroy() end)
            end
        end
        for _, conn in pairs(generatorProgConns) do pcall(function() conn:Disconnect() end) end
        if table.clear then table.clear(generatorEspCache) end
        if table.clear then table.clear(generatorProgConns) end
    end
end

function VX_bindDevice(p)
    if not espDeviceEnabled or not p or not p.Character then return end
    local head = p.Character:FindFirstChild("Head")
    if not head or head:FindFirstChild("DeviceESP") then return end
    local bb = Instance.new("BillboardGui")
    bb.Name = "DeviceESP"; bb.AlwaysOnTop = true; bb.LightInfluence = 0
    bb.StudsOffset = Vector3.new(0, 2.8, 0); bb.Size = UDim2.fromOffset(28, 28)
    bb.Parent = head
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.new(1, 0, 1, 0); img.BackgroundTransparency = 1
    img.ScaleType = Enum.ScaleType.Fit
    img.Image = "rbxassetid://89227325753198"; img.Parent = bb
end

-- ==========================================
-- 2D Box ESP 引擎
-- ==========================================
local _2dScreenGui, _2dFolder
local function _2dInit()
    if _2dScreenGui and _2dScreenGui.Parent then return end
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    _2dScreenGui = Instance.new("ScreenGui")
    _2dScreenGui.Name = "Swesaken_2DBox"
    _2dScreenGui.ResetOnSpawn = false
    _2dScreenGui.IgnoreGuiInset = true
    _2dScreenGui.DisplayOrder = 999
    _2dScreenGui.Parent = parent
    _2dFolder = Instance.new("Folder")
    _2dFolder.Name = "Boxes"
    _2dFolder.Parent = _2dScreenGui
end
_2dInit()

local _2dCache = setmetatable({}, { __mode = "k" })

local function _2dGetOrCreate(model)
    if _2dCache[model] and _2dCache[model].box and _2dCache[model].box.Parent then
        return _2dCache[model]
    end
    _2dInit()
    local box = Instance.new("Frame")
    box.Name = "2D_" .. model.Name
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Visible = false
    box.ZIndex = 100
    box.Parent = _2dFolder

    local stroke = Instance.new("UIStroke", box)
    stroke.Name = "BoxStroke"
    stroke.Thickness = 1.5
    stroke.Transparency = 0

    local topHolder = Instance.new("Frame", box)
    topHolder.Name = "TopHolder"
    topHolder.BackgroundTransparency = 1
    topHolder.AnchorPoint = Vector2.new(0.5, 1)
    topHolder.Position = UDim2.new(0.5, 0, 0, -3)
    topHolder.Size = UDim2.new(0, 200, 0, 0)
    topHolder.AutomaticSize = Enum.AutomaticSize.Y
    topHolder.ZIndex = 101
    local topLayout = Instance.new("UIListLayout", topHolder)
    topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    topLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    topLayout.SortOrder = Enum.SortOrder.LayoutOrder
    topLayout.Padding = UDim.new(0, 1)

    local botHolder = Instance.new("Frame", box)
    botHolder.Name = "BottomHolder"
    botHolder.BackgroundTransparency = 1
    botHolder.AnchorPoint = Vector2.new(0.5, 0)
    botHolder.Position = UDim2.new(0.5, 0, 1, 3)
    botHolder.Size = UDim2.new(0, 200, 0, 0)
    botHolder.AutomaticSize = Enum.AutomaticSize.Y
    botHolder.ZIndex = 101
    local botLayout = Instance.new("UIListLayout", botHolder)
    botLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    botLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    botLayout.SortOrder = Enum.SortOrder.LayoutOrder
    botLayout.Padding = UDim.new(0, 1)

    local function mkLabel(name, order)
        local l = Instance.new("TextLabel")
        l.Name = name
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.GothamBold
        l.TextSize = 12
        l.TextColor3 = Color3.fromRGB(255, 255, 255)
        l.TextStrokeTransparency = 0
        l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        l.Text = ""
        l.Visible = false
        l.ZIndex = 102
        l.Size = UDim2.new(0, 200, 0, 14)
        l.LayoutOrder = order
        return l
    end

    local rec = {
        box = box,
        stroke = stroke,
        top = topHolder,
        bottom = botHolder,
        name = mkLabel("Name", 1),
        hp = mkLabel("HP", 2),
        dist = mkLabel("Dist", 3),
        status = mkLabel("Status", 4),
    }
    rec.name.Parent = topHolder
    rec.hp.Parent = topHolder
    rec.status.Parent = topHolder
    rec.dist.Parent = botHolder
    _2dCache[model] = rec
    return rec
end

local function _2dClear(model)
    local rec = _2dCache[model]
    if rec and rec.box then rec.box.Visible = false end
end

RunService.Heartbeat:Connect(function()
    if not _2dBoxEnabled then
        for model in pairs(_2dCache) do _2dClear(model) end
        return
    end
    local cam = Camera
    if not cam then return end
    local myChar = lp.Character
    local rendered = {}

    local function process(folder, isKiller)
        if not folder then return end
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model ~= myChar then
                local hum = model:FindFirstChildOfClass("Humanoid")
                local hrp = model:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0 then
                    local dist = (cam.CFrame.Position - hrp.Position).Magnitude
                    if dist <= 900 then
                        local top2D = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 2.5, 0))
                        local bot2D = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3.0, 0))
                        local root2D = cam:WorldToViewportPoint(hrp.Position)
                        if root2D.Z > 0 and top2D.Z > 0 and bot2D.Z > 0 then
                            local h = math.max(math.abs(bot2D.Y - top2D.Y), 10)
                            local w = math.floor(h * 0.62)
                            local minX = math.floor(root2D.X - w / 2)
                            local minY = math.floor(math.min(top2D.Y, bot2D.Y))
                            local rec = _2dGetOrCreate(model)
                            if rec and rec.box then
                                rec.box.Position = UDim2.fromOffset(minX, minY)
                                rec.box.Size = UDim2.fromOffset(w, h)
                                rec.box.Visible = true
                                local col = isKiller and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(60, 255, 120)
                                rec.stroke.Color = col
                                rec.stroke.Thickness = 1.5
                                rec.name.TextColor3 = col
                                rec.hp.TextColor3 = col
                                rec.dist.TextColor3 = col
                                if _2dBoxShowName then
                                    local dName = model:GetAttribute("ActorDisplayName") or model.Name
                                    rec.name.Text = tostring(dName)
                                    rec.name.Visible = true
                                else
                                    rec.name.Visible = false
                                end
                                if _2dBoxShowHP then
                                    rec.hp.Text = string.format("HP %d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth))
                                    rec.hp.Visible = true
                                else
                                    rec.hp.Visible = false
                                end
                                if _2dBoxShowDist then
                                    rec.dist.Text = string.format("%d studs", math.floor(dist))
                                    rec.dist.Visible = true
                                else
                                    rec.dist.Visible = false
                                end
                                if _2dBoxShowStatus then
                                    local badges = {}
                                    if model:GetAttribute("IsStunned") then table.insert(badges, "[Stunned]") end
                                    if model:GetAttribute("Invincible") then table.insert(badges, "[Invincible]") end
                                    if model:GetAttribute("FixingGenerator") then table.insert(badges, "[Fixing]") end
                                    rec.status.Text = table.concat(badges, " ")
                                    rec.status.Visible = #badges > 0
                                else
                                    rec.status.Visible = false
                                end
                                rendered[model] = true
                            end
                        else
                            _2dClear(model)
                        end
                    else
                        _2dClear(model)
                    end
                end
            end
        end
    end

    if _2dBoxShowKiller then process(KillersFolder, true) end
    if _2dBoxShowSurvivor then process(SurvivorsFolder, false) end

    for model in pairs(_2dCache) do
        if not rendered[model] then _2dClear(model) end
    end
end)

-- ==========================================
-- 防背刺引擎
-- ==========================================
local function _absAddRing(model)
    pcall(function()
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if not hrp or _absRings[model] then return end
        local ring = Instance.new("Part")
        ring.Name = "AbsRing"
        ring.Shape = Enum.PartType.Cylinder
        ring.Size = Vector3.new(0.1, _absRange * 2, _absRange * 2)
        ring.Color = Color3.fromRGB(220, 50, 50)
        ring.Material = Enum.Material.ForceField
        ring.Transparency = 0.5
        ring.CanCollide = false
        ring.CanTouch = false
        ring.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.rad(90))
        ring.Parent = hrp
        local w = Instance.new("WeldConstraint")
        w.Part0 = hrp; w.Part1 = ring; w.Parent = ring
        _absRings[model] = ring
    end)
end

local function _absRemoveRing(model)
    pcall(function()
        local r = _absRings[model]
        if r then r:Destroy() end
        _absRings[model] = nil
    end)
end

local function _absResizeRings()
    for _, r in pairs(_absRings) do
        if r and r.Parent then r.Size = Vector3.new(0.1, _absRange * 2, _absRange * 2) end
    end
end

local function _absCleanRings()
    for m in pairs(_absRings) do _absRemoveRing(m) end
end

local function _absFindTwoTime()
    local players = workspace:FindFirstChild("Players")
    if not players then return nil end
    for _, folder in ipairs(players:GetChildren()) do
        local tt = folder:FindFirstChild("TwoTime")
        if tt then return tt end
    end
    return nil
end

local function _absTrigger()
    pcall(function()
        if _absLocked then return end
        local ch = lp.Character
        local myRoot = ch and ch:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end
        local ttModel = _absFindTwoTime()
        if not ttModel then return end
        local ttRoot = ttModel:FindFirstChild("HumanoidRootPart")
        if not ttRoot then return end
        if (myRoot.Position - ttRoot.Position).Magnitude > _absRange then return end
        _absLocked = true
        task.spawn(function()
            local deadline = tick() + _absDuration
            while tick() < deadline do
                if not _absEnabled then break end
                local ch2 = lp.Character
                local r2 = ch2 and ch2:FindFirstChild("HumanoidRootPart")
                if not r2 or not ttRoot.Parent then break end
                r2.CFrame = CFrame.lookAt(r2.Position, Vector3.new(ttRoot.Position.X, r2.Position.Y, ttRoot.Position.Z))
                RunService.RenderStepped:Wait()
            end
            _absLocked = false
        end)
    end)
end

local function _absHookSounds()
    pcall(function()
        if _absSoundConn then _absSoundConn:Disconnect(); _absSoundConn = nil end
        local function checkSound(obj)
            if not _absEnabled or not obj:IsA("Sound") then return end
            local id = obj.SoundId:match("%d+")
            if id and _absTriggerSounds[id] then _absTrigger() end
        end
        _absSoundConn = workspace.DescendantAdded:Connect(function(obj)
            if obj:IsA("Sound") then
                checkSound(obj)
                obj:GetPropertyChangedSignal("SoundId"):Connect(function() checkSound(obj) end)
            end
        end)
    end)
end

local function _absStartScan()
    if _absScanThread then return end
    _absScanThread = task.spawn(function()
        while _absEnabled do
            pcall(function()
                local players = workspace:FindFirstChild("Players")
                if players then
                    for _, folder in ipairs(players:GetChildren()) do
                        for _, model in ipairs(folder:GetChildren()) do
                            if model.Name == "TwoTime" then _absAddRing(model) end
                        end
                    end
                end
                for m in pairs(_absRings) do
                    if not m.Parent then _absRemoveRing(m) end
                end
            end)
            task.wait(1)
        end
        _absScanThread = nil
    end)
end

local function _absStart()
    _absHookSounds()
    _absStartScan()
end

local function _absStop()
    if _absSoundConn then _absSoundConn:Disconnect(); _absSoundConn = nil end
    if _absScanThread then task.cancel(_absScanThread); _absScanThread = nil end
    _absCleanRings()
    _absLocked = false
end

-- ==========================================
-- AutoBlock 碰撞盒
-- ==========================================
local SwesakenDebugPart, SwesakenDebugOutline
local function initSwesakenDebugBox()
    if SwesakenDebugPart then return end
    SwesakenDebugPart = Instance.new("Part")
    SwesakenDebugPart.Name = "SwesakenAutoBlockHitbox_Visual"
    SwesakenDebugPart.CanCollide = false; SwesakenDebugPart.CanTouch = false; SwesakenDebugPart.CanQuery = false; SwesakenDebugPart.CastShadow = false
    SwesakenDebugPart.Anchored = true; SwesakenDebugPart.Material = Enum.Material.ForceField
    SwesakenDebugPart.Parent = nil
    SwesakenDebugOutline = Instance.new("SelectionBox")
    SwesakenDebugOutline.Adornee = SwesakenDebugPart
    SwesakenDebugOutline.LineThickness = 0.01
    SwesakenDebugOutline.Transparency = 0.1
    SwesakenDebugOutline.Parent = SwesakenDebugPart
end
initSwesakenDebugBox()

local function SwesakenCreateSpatialOverlapBox(creatorChar, size, onHitDetected)
    local creatorRoot = creatorChar:FindFirstChild("HumanoidRootPart") or creatorChar:FindFirstChild("RootPart")
    if not creatorRoot then return end
    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Include
    overlapParams.FilterDescendantsInstances = { KillersFolder, SurvivorsFolder, lp.Character }
    if SwesakenShowHitboxVisual then
        if not SwesakenDebugPart then initSwesakenDebugBox() end
        SwesakenDebugPart.Size = size
        SwesakenDebugPart.Transparency = SwesakenHitboxTransparency
        SwesakenDebugPart.Parent = workspace
        SwesakenDebugOutline.Visible = SwesakenShowOutline
    end
    task.spawn(function()
        local timePast = 0
        local hasHit = false
        while creatorChar.Parent and creatorRoot and creatorRoot.Parent and timePast < SwesakenHitboxDuration do
            local checkCFrame = creatorRoot.CFrame * CFrame.new(0, 0, SwesakenHitboxOffset - SwesakenHitboxFrontBackOffset)
            if SwesakenDebugPart and SwesakenDebugPart.Parent then SwesakenDebugPart.CFrame = checkCFrame end
            local parts = workspace:GetPartBoundsInBox(checkCFrame, size, overlapParams)
            local hit = false
            local isGuestHit = false
            for _, v in ipairs(parts) do
                local hum = v.Parent:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local player = Players:GetPlayerFromCharacter(hum.Parent)
                    if player and (player.Name == "Guest1337" or player == lp) then isGuestHit = true end
                    if Players:GetPlayerFromCharacter(hum.Parent) == lp then hit = true end
                end
            end
            if SwesakenDebugPart and SwesakenDebugPart.Parent then
                local targetColor = isGuestHit and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
                SwesakenDebugPart.Color = targetColor
                if SwesakenDebugOutline then SwesakenDebugOutline.Color3 = targetColor end
            end
            if hit and not hasHit then
                hasHit = true
                if onHitDetected then onHitDetected() end
            end
            timePast = timePast + task.wait(0.05)
        end
        if SwesakenDebugPart then SwesakenDebugPart.Parent = nil end
    end)
end

local function SwesakenCheckAbilityAttributes()
    local kf = KillersFolder
    local slasher = kf:GetChildren()[1]
    if not slasher or not slasher:IsA("Model") then return end
    local a = slasher:GetAttribute("AbilityLastUsed") or 0
    local b = slasher:GetAttribute("AbilitiesUsed") or 0
    if SwesakenLastAbilityLastUsed == nil then SwesakenLastAbilityLastUsed = a; SwesakenLastAbilitiesUsed = b; return end
    if b > SwesakenLastAbilitiesUsed then SwesakenBlockLocked = true end
    if a > SwesakenLastAbilityLastUsed then
        if SwesakenBlockLocked then SwesakenBlockLocked = false
        else
            local baseSize = SwesakenBaseHitboxSize * SwesakenHitboxScale
            local finalSize = Vector3.new(baseSize.X * SwesakenHitboxWidthScale, baseSize.Y, baseSize.Z)
            SwesakenCreateSpatialOverlapBox(slasher, finalSize, function()
                if SwesakenBlockDelay > 0 then task.wait(SwesakenBlockDelay) end
                fireRemoteBlock()
            end)
        end
    end
    SwesakenLastAbilityLastUsed = a
    SwesakenLastAbilitiesUsed = b
end

-- [FIX] 之前这个函数没人调用，加了循环让它真正生效
task.spawn(function()
    while true do
        task.wait(0.1)
        if SwesakenAutoBlockEnabled then
            pcall(SwesakenCheckAbilityAttributes)
        end
    end
end)

-- ==========================================
-- HDT 拖拽
-- ==========================================
local function beginDragIntoKiller(killerModel)
    if _hitboxDraggingDebounce then return end
    if not killerModel or not killerModel.Parent then return end
    local char = lp.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then return end

    local targetHRP = getKillerHRP(killerModel)
    if not targetHRP then return end

    _hitboxDraggingDebounce = true

    local oldWalk       = humanoid.WalkSpeed
    local oldJump       = humanoid.JumpPower
    local oldAutoRotate = humanoid.AutoRotate

    pcall(function()
        humanoid.WalkSpeed  = 0
        humanoid.JumpPower  = 0
        humanoid.AutoRotate = false
    end)

    local bv = Instance.new("BodyVelocity")
    bv.Name = "Swesaken_HDT_BV"
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bv.Velocity = Vector3.zero
    bv.Parent = hrp

    local dragStartTick = tick()
    local lastBlockTick = tick()

    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not _hitboxDraggingDebounce then
            if conn then conn:Disconnect() end
            if bv and bv.Parent then pcall(function() bv:Destroy() end) end
            return
        end
        if not (char and char.Parent) or not (killerModel and killerModel.Parent) then
            _hitboxDraggingDebounce = false
            return
        end
        targetHRP = getKillerHRP(killerModel)
        if not targetHRP then
            _hitboxDraggingDebounce = false
            return
        end

        local elapsed = tick() - dragStartTick

        local stillBlocking = false
        if cachedAnimator then
            for _, t in ipairs(cachedAnimator:GetPlayingAnimationTracks()) do
                local aid = nil
                pcall(function() aid = t.Animation and tostring(t.Animation.AnimationId):match("%d+") end)
                if aid and blockAnimSet[aid] then
                    stillBlocking = true
                    break
                end
            end
        end
        if stillBlocking then lastBlockTick = tick() end

        if elapsed >= HDT_MinDuration and (tick() - lastBlockTick) > HDT_GraceAfterBlock then
            _hitboxDraggingDebounce = false
            return
        end

        local myPos = hrp.Position
        local toTarget = targetHRP.Position - myPos
        local horiz = Vector3.new(toTarget.X, 0, toTarget.Z)
        local horizDist = horiz.Magnitude

        if horizDist <= 0.05 then
            bv.Velocity = Vector3.zero
            if horizDist <= HDT_StopDistance and elapsed >= HDT_MinDuration then
                _hitboxDraggingDebounce = false
            end
            return
        end

        local unit = horiz.Unit

        local baseSpeed = Dspeed
        if horizDist < 5 then baseSpeed = math.max(Dspeed * (horizDist / 5), 1.5) end
        bv.Velocity = Vector3.new(unit.X * baseSpeed, 0, unit.Z * baseSpeed)

        local curLookVec = hrp.CFrame.LookVector
        local curLookXZ  = Vector3.new(curLookVec.X, 0, curLookVec.Z)
        if curLookXZ.Magnitude > 0.001 then
            curLookXZ = curLookXZ.Unit
            local targetLook = CFrame.lookAt(Vector3.zero, unit)
            local targetRot  = targetLook - targetLook.Position
            local curRot     = hrp.CFrame - myPos
            local _, curY, _ = curRot:ToEulerAnglesYXZ()
            local _, tarY, _ = targetRot:ToEulerAnglesYXZ()
            local angleDiff = math.abs(math.atan2(math.sin(tarY - curY), math.cos(tarY - curY)))
            if angleDiff > math.rad(2) then
                local t = math.min(1 - math.exp(-HDT_TurnSmoothness * dt), 0.35)
                hrp.CFrame = CFrame.new(myPos) * curRot:Lerp(targetRot, t)
            end
        end

        if horizDist <= HDT_StopDistance and elapsed >= HDT_MinDuration then
            _hitboxDraggingDebounce = false
        end
    end)

    task.delay(HDT_Duration, function()
        if _hitboxDraggingDebounce then _hitboxDraggingDebounce = false end
    end)

    task.spawn(function()
        while _hitboxDraggingDebounce do task.wait(0.05) end
        if bv and bv.Parent then pcall(function() bv:Destroy() end) end
        pcall(function()
            humanoid.WalkSpeed  = oldWalk
            humanoid.JumpPower  = oldJump
            humanoid.AutoRotate = oldAutoRotate
        end)
    end)
end

-- ==========================================
-- Auto Punch Hook
-- ==========================================
local function connectAutoPunchNetwork()
    if not NetworkModule then return end
    pcall(function()
        -- [FIX] "%*" 不是合法格式符，改成 "%s"
        NetworkModule:SetConnection(("%s1337ParryIcon"):format(lp.Name), "REMOTE_EVENT", function(blocked)
            if blocked and autoPunchEventEnabled then
                if not testRemote then return end
                pcall(function()
                    testRemote:FireServer("UseActorAbility", { buffer.fromstring("\003\005\000\000\000Punch") })
                end)
            end
        end)
    end)
end
connectAutoPunchNetwork()
lp.CharacterAdded:Connect(function()
    task.wait(0.9)
    connectAutoPunchNetwork()
end)

-- ==========================================
-- 动画监听 + Punch Aim + HDT
-- ==========================================
local cachedAnimator = nil
local function refreshAnimator()
    local char = lp.Character
    -- [FIX] 加换行 / 分号，避免语法歧义
    if not char then cachedAnimator = nil; return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    cachedAnimator = hum and hum:FindFirstChildOfClass("Animator")
end

refreshAnimator()
lp.CharacterAdded:Connect(function() task.wait(0.5) refreshAnimator() end)

RunService.RenderStepped:Connect(function()
    if not cachedAnimator then refreshAnimator() end
    if not cachedAnimator then return end

    local isLocalKiller = KillersFolder:FindFirstChild(lp.Name) ~= nil
        or (lp.Character and lp.Character.Parent == KillersFolder)

    local isBlocking = false
    local blockTrack = nil
    local punchTrack = nil

    for _, track in ipairs(cachedAnimator:GetPlayingAnimationTracks()) do
        local aid = nil
        pcall(function() aid = track.Animation and tostring(track.Animation.AnimationId):match("%d+") end)
        if aid then
            if isLocalKiller then
                if blockAnimSet[aid] and not blockTrack then
                    isBlocking = true; blockTrack = track
                end
            else
                if punchAnimSet[aid] and not punchTrack then punchTrack = track end
                if not punchTrack and blockAnimSet[aid] and not blockTrack then
                    isBlocking = true; blockTrack = track
                end
            end
        end
    end

    if isBlocking and blockTrack and hitboxDraggingTech and not _hitboxDraggingDebounce then
        if _hdt_lastBlockTrack ~= blockTrack then
            local nearest = getNearestKillerModel()
            if nearest then
                local kmHRP = nearest:FindFirstChild("HumanoidRootPart")
                local myHRP = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                if kmHRP and myHRP then
                    if (kmHRP.Position - myHRP.Position).Magnitude <= HDT_DetectRange then
                        _hdt_lastBlockTrack = blockTrack
                        task.spawn(function()
                            task.wait(Ddelay)
                            beginDragIntoKiller(nearest)
                        end)
                    end
                end
            end
        end
    elseif not isBlocking then
        _hdt_lastBlockTrack = nil
    end

    if punchTrack and (MyAnimLockOn or aimPunchToggles["Character Lock"] or aimPunchToggles["Camera Lock"]) then
        if not isLocalKiller then
            local last = lastAimTrigger[punchTrack]
            if not last or tick() - last >= AIM_COOLDOWN then
                local tp = 0
                pcall(function() tp = punchTrack.TimePosition or 0 end)
                if tp <= 0.3 then
                    lastAimTrigger[punchTrack] = tick()
                    local wantAim = MyAnimLockOn or aimPunchToggles["Character Lock"]
                    local wantCam = aimPunchToggles["Camera Lock"]
                    local myChar = lp.Character
                    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                    if myRoot then
                        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
                        if humanoid and wantAim then humanoid.AutoRotate = false end
                        task.spawn(function()
                            local start = tick()
                            while tick() - start < AIM_WINDOW do
                                if not (myRoot.Parent and myChar.Parent) then break end
                                local best, bd = nil, math.huge
                                for _, k in ipairs(KillersFolder:GetChildren()) do
                                    if k:IsA("Model") and k:GetAttribute("IsFakeNoli") ~= true then
                                        local root = k:FindFirstChild("HumanoidRootPart")
                                        local kh   = k:FindFirstChildOfClass("Humanoid")
                                        if root and kh and kh.Health > 0 then
                                            local d = (root.Position - myRoot.Position).Magnitude
                                            if d < bd then best, bd = root, d end
                                        end
                                    end
                                end
                                if best then
                                    local vel = best.Velocity or Vector3.zero
                                    local hVel = Vector3.new(vel.X, 0, vel.Z)
                                    local speed = hVel.Magnitude
                                    local dynamicLead = math.clamp(0.08 + speed * 0.014, 0.08, 0.42)
                                    local pred = math.min(predictionValue, bd * 0.5)
                                    local lookXZ = Vector3.new(best.CFrame.LookVector.X, 0, best.CFrame.LookVector.Z)
                                    if lookXZ.Magnitude > 0.001 then lookXZ = lookXZ.Unit else lookXZ = Vector3.zero end
                                    local predictedPos = best.Position + lookXZ * pred + hVel * dynamicLead
                                    if wantAim then
                                        local pos = myRoot.Position
                                        local dir = Vector3.new(predictedPos.X - pos.X, 0, predictedPos.Z - pos.Z)
                                        if dir.Magnitude > 0.001 then
                                            pcall(function() myRoot.CFrame = CFrame.lookAt(pos, pos + dir.Unit) end)
                                        end
                                    end
                                    if wantCam then
                                        pcall(function() Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, predictedPos) end)
                                    end
                                end
                                task.wait()
                            end
                            if humanoid and humanoid.Parent and wantAim then humanoid.AutoRotate = true end
                            task.delay(AIM_COOLDOWN, function() lastAimTrigger[punchTrack] = nil end)
                        end)
                    end
                end
            end
        end
    end
end)

-- ==========================================
-- Survivor 眩晕技能检测
-- ==========================================
local _hookedSurvivors = setmetatable({}, { __mode = "k" })

local function checkSurvivorSkillTrigger(survModel, track)
    if not (_survivorSkill404Enabled or _survivorSkillRagingEnabled) then return end
    local aid = nil
    pcall(function() aid = track.Animation and tostring(track.Animation.AnimationId):match("%d+") end)
    if not aid then return end
    local isStunSkill = false
    if next(_stunSkillAnimIds) then
        isStunSkill = _stunSkillAnimIds[aid] == true
    else
        local pri = track.Priority
        isStunSkill = (pri == Enum.AnimationPriority.Action) or (pri == Enum.AnimationPriority.Action2)
            or (pri == Enum.AnimationPriority.Action3) or (pri == Enum.AnimationPriority.Action4)
    end
    if not isStunSkill then return end
    local myChar = lp.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local survRoot = survModel:FindFirstChild("HumanoidRootPart")
    if not myRoot or not survRoot then return end
    local dist = (survRoot.Position - myRoot.Position).Magnitude
    local now = tick()
    if _survivorSkill404Enabled and dist <= _survivorSkill404Range and (now - _lastSurvivorSkill404Time >= _survivorSkill404Cooldown) then
        _lastSurvivorSkill404Time = now
        if testRemote then
            pcall(function() testRemote:FireServer("UseActorAbility", { buffer.fromstring("\003\008\000\000\000404Error") }) end)
        end
    end
    if _survivorSkillRagingEnabled and dist <= _survivorSkillRagingRange and (now - _lastSurvivorSkillRagingTime >= _survivorSkillRagingCooldown) then
        _lastSurvivorSkillRagingTime = now
        if testRemote then
            pcall(function() testRemote:FireServer("UseActorAbility", { buffer.fromstring("\003\010\000\000\000RagingPace") }) end)
        end
    end
end

local function hookSurvivorModel(survModel)
    if _hookedSurvivors[survModel] then return end
    local hum = survModel:FindFirstChildOfClass("Humanoid")
    if not hum then
        task.delay(0.5, function()
            local h2 = survModel:FindFirstChildOfClass("Humanoid")
            if h2 and not _hookedSurvivors[survModel] then
                _hookedSurvivors[survModel] = true
                local a2 = h2:FindFirstChildOfClass("Animator")
                if a2 then a2.AnimationPlayed:Connect(function(track) checkSurvivorSkillTrigger(survModel, track) end) end
            end
        end)
        return
    end
    _hookedSurvivors[survModel] = true
    local anim = hum:FindFirstChildOfClass("Animator")
    if anim then anim.AnimationPlayed:Connect(function(track) checkSurvivorSkillTrigger(survModel, track) end) end
end

for _, surv in ipairs(SurvivorsFolder:GetChildren()) do
    if surv:IsA("Model") then hookSurvivorModel(surv) end
end
SurvivorsFolder.ChildAdded:Connect(function(child)
    if child:IsA("Model") then hookSurvivorModel(child) end
end)

-- ==========================================
-- Backstab / Stealth / Hitbox / Parry 引擎
-- ==========================================
local _bsEnabled, _bsRange, _bsBehindDist, _bsCone, _bsCooldown, _bsMode = false, 8, 3.5, 70, 5, "Lerp"
local _bsLastTrigger = 0
local _bsRunning = false

local function _bsIsValidKiller(model)
    if not model or not model:IsA("Model") then return false end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hrp and hum and hum.Health > 0
end

local function _bsIsBehind(myHRP, kHRP, dist)
    if dist > _bsRange or dist < 0.01 then return false end
    local toPlayer = (myHRP.Position - kHRP.Position).Unit
    local killerBack = -kHRP.CFrame.LookVector
    return toPlayer:Dot(killerBack) >= math.cos(math.rad(_bsCone))
end

local function _bsMoveBehind(myHRP, kHRP, mode)
    local kCF = kHRP.CFrame
    local behindPos = kCF.Position - kCF.LookVector.Unit * _bsBehindDist
    behindPos = Vector3.new(behindPos.X, kCF.Position.Y, behindPos.Z)
    local behindCF = CFrame.new(behindPos, behindPos + kCF.LookVector.Unit)
    if mode == "Teleport" then
        pcall(function() myHRP.CFrame = behindCF end)
    elseif mode == "Aim" then
        local aim = kHRP.Position + kHRP.CFrame.LookVector * 2
        pcall(function() myHRP.CFrame = CFrame.new(myHRP.Position, Vector3.new(aim.X, myHRP.Position.Y, aim.Z)) end)
    else
        local t0 = tick()
        while tick() - t0 < 0.45 do
            if not _bsRunning then break end
            if not (myHRP.Parent and kHRP.Parent) then break end
            pcall(function() myHRP.CFrame = myHRP.CFrame:Lerp(behindCF, 0.55) end)
            RunService.Heartbeat:Wait()
        end
    end
end

local function _bsLoop()
    if _bsRunning then return end
    _bsRunning = true
    while _bsEnabled do
        task.wait(0.05)
        if not _bsEnabled then break end
        local char = lp.Character
        local myHRP = char and char:FindFirstChild("HumanoidRootPart")
        if myHRP then
            local triggered = false
            for _, killer in ipairs(KillersFolder:GetChildren()) do
                if triggered then break end
                if _bsIsValidKiller(killer) then
                    local kHRP = killer:FindFirstChild("HumanoidRootPart")
                    local dist = (kHRP.Position - myHRP.Position).Magnitude
                    if _bsIsBehind(myHRP, kHRP, dist) and tick() - _bsLastTrigger >= _bsCooldown then
                        _bsLastTrigger = tick()
                        triggered = true
                        task.spawn(_bsMoveBehind, myHRP, kHRP, _bsMode)
                    end
                end
            end
        end
    end
    _bsRunning = false
end

local _invEnabled, _invOffset = false, 5000
local _invOrigSerialize, _invHooked = nil, nil
local function _invInstall()
    if _invHooked then return true end
    local pok, CharRepl = pcall(function() return require(ReplicatedStorage.Systems.Player.Game.CharacterReplication) end)
    if not pok or not CharRepl or type(CharRepl.Serialize) ~= "function" then return false end
    _invOrigSerialize = CharRepl.Serialize
    local old = _invOrigSerialize
    _invHooked = hookfunction(old, newcclosure(function(...)
        if not _invEnabled then return old(...) end
        local args = { ... }
        if typeof(args[1]) ~= "CFrame" or typeof(args[2]) ~= "Vector3" then return old(...) end
        return old(args[1], args[2] + Vector3.new(0, _invOffset, 0))
    end))
    return true
end

local _suctionEnabled, _suctionStrength, _suctionRange = false, 50, 100
local _suctionConn = nil
local function _suctionGetNearest()
    local char = lp.Character
    local myHRP = char and char:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil end
    local best, bd = nil, math.huge
    for _, m in ipairs(SurvivorsFolder:GetChildren()) do
        if m:IsA("Model") then
            local hum = m:FindFirstChildOfClass("Humanoid")
            local root = m:FindFirstChild("HumanoidRootPart")
            if hum and root and hum.Health > 0 then
                local d = (root.Position - myHRP.Position).Magnitude
                if d < bd and d <= _suctionRange then bd = d; best = root end
            end
        end
    end
    return best
end
local function _suctionTick()
    if _suctionConn then _suctionConn:Disconnect(); _suctionConn = nil end
    _suctionConn = RunService.RenderStepped:Connect(function()
        if not _suctionEnabled then return end
        local char = lp.Character
        local myHRP = char and char:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end
        local target = _suctionGetNearest()
        if not target then return end
        local dir = target.Position - myHRP.Position
        if dir.Magnitude < 0.1 then return end
        dir = dir.Unit
        myHRP.AssemblyLinearVelocity = myHRP.AssemblyLinearVelocity:Lerp(myHRP.AssemblyLinearVelocity + dir * _suctionStrength, 0.3)
    end)
end

local _hbeEnabled, _hbeRange = false, 10
local _hbtEnabled, _hbtRange = false, 60
local _hbtRandom = Random.new()

local _parryAnims = {
    ["121255898612475"]=true,["105614318732282"]=true,["116618003477002"]=true,
    ["87259391926321"]=true,["86096387000557"]=true,["86709774283672"]=true,
    ["140703210927645"]=true,["136007065400978"]=true,["129843313690921"]=true,
    ["108807732150251"]=true,["138040001965654"]=true,["90499469533503"]=true,
    ["133491532453922"]=true,["73921036900313"]=true,["111384272984267"]=true,
}
local _parrySounds = {
    ["92445809840331"]=true,["140258770018994"]=true,["12222225"]=true,
    ["118234760889759"]=true,["81714228693719"]=true,["114486446625838"]=true,
}
local _slasherEnabled, _slasherRange, _slasherLast = false, 15, 0
local _jdEnabled, _jdRange, _jdLast = false, 15, 0

local function _parryShouldFire(range)
    local char = lp.Character
    local myHRP = char and char:FindFirstChild("HumanoidRootPart")
    if not myHRP then return false end
    for _, surv in ipairs(SurvivorsFolder:GetChildren()) do
        local sHRP = surv:FindFirstChild("HumanoidRootPart")
        if sHRP then
            local dist = (sHRP.Position - myHRP.Position).Magnitude
            if dist <= range then
                local hum = surv:FindFirstChildOfClass("Humanoid")
                local anim = hum and hum:FindFirstChildOfClass("Animator")
                if anim then
                    for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                        local id = tostring(track.Animation and track.Animation.AnimationId or ""):match("%d+")
                        if id and _parryAnims[id] and track.TimePosition <= 0.45 then return true end
                    end
                end
                for _, d in ipairs(surv:GetDescendants()) do
                    if d:IsA("Sound") and d.IsPlaying then
                        local sid = tostring(d.SoundId):match("%d+")
                        if sid and _parrySounds[sid] then return true end
                    end
                end
            end
        end
    end
    return false
end

local function _parryGetCooldown(name)
    local pg = lp:FindFirstChild("PlayerGui")
    local main = pg and pg:FindFirstChild("MainUI")
    local container = main and main:FindFirstChild("AbilityContainer")
    local btn = container and container:FindFirstChild(name)
    local cd = btn and btn:FindFirstChild("CooldownTime")
    if cd and cd.Visible and cd.Text ~= "" then return tonumber(cd.Text) or 0 end
    return 0
end

task.spawn(function()
    while true do
        task.wait(0.1)
        if _slasherEnabled and testRemote then
            local char = lp.Character
            local name = char and char.Name or ""
            if name:find("Slasher") and char:GetAttribute("Username") == lp.Name then
                if _parryShouldFire(_slasherRange) and _parryGetCooldown("RagingPace") <= 0 then
                    if tick() - _slasherLast >= 0.5 then
                        _slasherLast = tick()
                        local args = { "UseActorAbility", { buffer.fromstring("\003\n\000\000\000RagingPace") } }
                        for i = 1, 3 do pcall(function() testRemote:FireServer(unpack(args)) end) end
                        task.wait(0.05)
                        for i = 1, 3 do pcall(function() testRemote:FireServer(unpack(args)) end) end
                    end
                end
            end
        end
        if _jdEnabled and testRemote then
            local char = lp.Character
            local name = char and char.Name or ""
            if name:find("JohnDoe") and char:GetAttribute("Username") == lp.Name then
                if _parryShouldFire(_jdRange) and _parryGetCooldown("404Error") <= 0 then
                    if tick() - _jdLast >= 2.0 then
                        _jdLast = tick()
                        local args = { "UseActorAbility", { buffer.fromstring("\003\b\000\000\000404Error") } }
                        pcall(function() testRemote:FireServer(unpack(args)) end)
                    end
                end
            end
        end
    end
end)

-- ==========================================
-- Show Hidden Info 引擎
-- ==========================================
local function _hiddenInfoGetPrivacy(player)
    local pd = player:FindFirstChild("PlayerData")
    local st = pd and pd:FindFirstChild("Settings")
    return st and st:FindFirstChild("Privacy")
end
local function _hiddenInfoSave(player)
    local p = _hiddenInfoGetPrivacy(player); if not p then return end
    _hiddenInfoOriginals[player.UserId] = _hiddenInfoOriginals[player.UserId] or {}
    for _, k in ipairs(_hiddenInfoKeys) do
        local v = p:FindFirstChild(k)
        if v then _hiddenInfoOriginals[player.UserId][k] = v.Value end
    end
end
local function _hiddenInfoReveal(player)
    local p = _hiddenInfoGetPrivacy(player); if not p then return end
    for _, k in ipairs(_hiddenInfoKeys) do
        local v = p:FindFirstChild(k); if v then v.Value = false end
    end
end
local function _hiddenInfoRestore(player)
    local p = _hiddenInfoGetPrivacy(player)
    local saved = _hiddenInfoOriginals[player.UserId]
    if not p or not saved then return end
    for k, val in pairs(saved) do
        local v = p:FindFirstChild(k); if v then v.Value = val end
    end
end
local function _hiddenInfoApply(enable)
    for _, p in ipairs(Players:GetPlayers()) do
        if enable then _hiddenInfoSave(p); _hiddenInfoReveal(p)
        else _hiddenInfoRestore(p) end
    end
end

-- ==========================================
-- Low Graphics 引擎
-- ==========================================
local function _setLowGraphics(on)
    if on then
        pcall(function()
            local terrain = Workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                terrain.WaterWaveSize = 0
                terrain.WaterWaveSpeed = 0
                terrain.WaterReflectance = 0
                terrain.WaterTransparency = 1
            end
            _lowGfxBackup.Lighting.GlobalShadows = Lighting.GlobalShadows
            _lowGfxBackup.Lighting.FogEnd = Lighting.FogEnd
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 9e9
            for _, v in ipairs(game:GetDescendants()) do
                if v:IsA("BasePart") then
                    if not _lowGfxBackup.Objects[v] then
                        _lowGfxBackup.Objects[v] = { Material = v.Material, Reflectance = v.Reflectance }
                    end
                    v.Material = Enum.Material.SmoothPlastic
                    v.Reflectance = 0
                elseif v:IsA("Decal") or v:IsA("Texture") then
                    if not _lowGfxBackup.Objects[v] then _lowGfxBackup.Objects[v] = { Transparency = v.Transparency } end
                    v.Transparency = 1
                elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
                    if not _lowGfxBackup.Objects[v] then _lowGfxBackup.Objects[v] = { Enabled = v.Enabled } end
                    v.Enabled = false
                end
            end
        end)
    else
        pcall(function()
            Lighting.GlobalShadows = _lowGfxBackup.Lighting.GlobalShadows or true
            Lighting.FogEnd = _lowGfxBackup.Lighting.FogEnd or 100000
            for obj, data in pairs(_lowGfxBackup.Objects) do
                if obj and obj.Parent then
                    if data.Material then pcall(function() obj.Material = data.Material end) end
                    if data.Reflectance then pcall(function() obj.Reflectance = data.Reflectance end) end
                    if data.Transparency then pcall(function() obj.Transparency = data.Transparency end) end
                    if data.Enabled ~= nil then pcall(function() obj.Enabled = data.Enabled end) end
                end
            end
            if table.clear then table.clear(_lowGfxBackup.Objects) end
        end)
    end
end

local function _suicide()
    local char = lp.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.Health = 0 end
end

-- ==========================================
-- 服务器功能
-- ==========================================
local function _rejoinServer()
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp)
    end)
end

local function _findLowPingServer()
    local success, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
    end)
    if success and data and data.data then
        local list = {}
        for _, srv in ipairs(data.data) do
            if srv.playing < srv.maxPlayers and srv.id ~= game.JobId then
                table.insert(list, srv)
            end
        end
        if #list > 0 then return list[math.random(1, #list)].id end
    end
    return nil
end

local function _findBeginnerServer()
    local success, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
    end)
    if success and data and data.data then
        table.sort(data.data, function(a, b) return a.playing < b.playing end)
        local cur = #Players:GetPlayers()
        for _, srv in ipairs(data.data) do
            if srv.playing < cur and srv.id ~= game.JobId and srv.playing > 0 then return srv.id end
        end
        for _, srv in ipairs(data.data) do
            if srv.id ~= game.JobId and srv.playing > 0 then return srv.id end
        end
    end
    return nil
end

local function _openServerBrowser()
    pcall(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "Swesaken_ServerBrowser"
        sg.ResetOnSpawn = false
        sg.Parent = (gethui and gethui()) or game:GetService("CoreGui")

        local main = Instance.new("Frame")
        main.Size = UDim2.new(0, 420, 0, 320)
        main.Position = UDim2.new(0.5, -210, 0.5, -160)
        main.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
        main.BorderSizePixel = 0
        main.Active = true
        main.Draggable = true
        main.Parent = sg
        Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -30, 0, 30)
        title.Position = UDim2.new(0, 10, 0, 0)
        title.BackgroundTransparency = 1
        title.Text = "Server Browser (服务器浏览器)"
        title.TextColor3 = Color3.fromRGB(255, 255, 255)
        title.TextSize = 16
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = main

        local close = Instance.new("TextButton")
        close.Size = UDim2.new(0, 22, 0, 22)
        close.Position = UDim2.new(1, -28, 0, 4)
        close.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        close.Text = "X"
        close.TextColor3 = Color3.fromRGB(255, 255, 255)
        close.Font = Enum.Font.GothamBold
        close.Parent = main
        Instance.new("UICorner", close).CornerRadius = UDim.new(0, 4)

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, -20, 1, -80)
        scroll.Position = UDim2.new(0, 10, 0, 40)
        scroll.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 6
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.Parent = main
        local layout = Instance.new("UIListLayout", scroll)
        layout.Padding = UDim.new(0, 4)

        local refresh = Instance.new("TextButton")
        refresh.Size = UDim2.new(0, 100, 0, 30)
        refresh.Position = UDim2.new(0, 10, 1, -36)
        refresh.BackgroundColor3 = Color3.fromRGB(50, 120, 200)
        refresh.Text = "Refresh (刷新)"
        refresh.TextColor3 = Color3.fromRGB(255, 255, 255)
        refresh.Font = Enum.Font.GothamBold
        refresh.Parent = main
        Instance.new("UICorner", refresh).CornerRadius = UDim.new(0, 4)

        local status = Instance.new("TextLabel")
        status.Size = UDim2.new(0, 280, 0, 30)
        status.Position = UDim2.new(0, 120, 1, -36)
        status.BackgroundTransparency = 1
        status.Text = "Ready (就绪)"
        status.TextColor3 = Color3.fromRGB(200, 200, 200)
        status.TextSize = 13
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.Parent = main

        local function createRow(srv)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 52)
            row.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
            row.BorderSizePixel = 0
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

            local cnt = Instance.new("TextLabel")
            cnt.Size = UDim2.new(0, 80, 1, 0)
            cnt.BackgroundTransparency = 1
            cnt.Text = srv.playing .. "/" .. srv.maxPlayers
            cnt.TextColor3 = Color3.fromRGB(255, 255, 255)
            cnt.TextSize = 14
            cnt.Parent = row

            local ping = Instance.new("TextLabel")
            ping.Size = UDim2.new(0, 100, 0, 20)
            ping.Position = UDim2.new(0, 85, 0, 4)
            ping.BackgroundTransparency = 1
            ping.Text = "Ping: " .. (srv.ping or "N/A")
            ping.TextColor3 = Color3.fromRGB(200, 200, 200)
            ping.TextSize = 12
            ping.TextXAlignment = Enum.TextXAlignment.Left
            ping.Parent = row

            local idL = Instance.new("TextLabel")
            idL.Size = UDim2.new(0, 200, 0, 20)
            idL.Position = UDim2.new(0, 85, 0, 24)
            idL.BackgroundTransparency = 1
            idL.Text = "ID: " .. tostring(srv.id):sub(1, 20)
            idL.TextColor3 = Color3.fromRGB(180, 180, 180)
            idL.TextSize = 11
            idL.TextXAlignment = Enum.TextXAlignment.Left
            idL.Parent = row

            local join = Instance.new("TextButton")
            join.Size = UDim2.new(0, 60, 0, 26)
            join.Position = UDim2.new(1, -68, 0.5, -13)
            join.BackgroundColor3 = Color3.fromRGB(70, 150, 70)
            join.Text = "Join (加入)"
            join.TextColor3 = Color3.fromRGB(255, 255, 255)
            join.Font = Enum.Font.GothamBold
            join.TextSize = 12
            Instance.new("UICorner", join).CornerRadius = UDim.new(0, 4)
            join.MouseButton1Click:Connect(function()
                status.Text = "Joining... (加入中)"
                TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, lp)
            end)
            join.Parent = row
            return row
        end

        local function fetch()
            status.Text = "Fetching servers... (获取中)"
            for _, c in ipairs(scroll:GetChildren()) do
                if c:IsA("Frame") then c:Destroy() end
            end
            local ok3, res = pcall(function()
                return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
            end)
            if ok3 and res and res.data then
                for _, srv in ipairs(res.data) do
                    createRow(srv).Parent = scroll
                end
                scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
                status.Text = "Found " .. #res.data .. " servers (已找到)"
            else
                status.Text = "Fetch failed (获取失败)"
            end
        end

        refresh.MouseButton1Click:Connect(fetch)
        close.MouseButton1Click:Connect(function() sg:Destroy() end)
        fetch()
    end)
end

-- ==========================================
-- Unlock 函数
-- ==========================================
local function _unlockAllChars()
    task.spawn(function()
        pcall(function()
            local purchased = lp:WaitForChild("PlayerData"):WaitForChild("Purchased")
            local killersFolder = purchased:FindFirstChild("Killers") or Instance.new("Folder", purchased)
            killersFolder.Name = "Killers"
            local survivorsFolder = purchased:FindFirstChild("Survivors") or Instance.new("Folder", purchased)
            survivorsFolder.Name = "Survivors"
            local skinsFolder = purchased:FindFirstChild("Skins") or Instance.new("Folder", purchased)
            skinsFolder.Name = "Skins"
            local kAssets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Killers")
            if kAssets then
                for _, k in ipairs(kAssets:GetChildren()) do
                    if not killersFolder:FindFirstChild(k.Name) then
                        Instance.new("StringValue", killersFolder).Name = k.Name
                    end
                end
            end
            local sAssets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Survivors")
            if sAssets then
                for _, s in ipairs(sAssets:GetChildren()) do
                    if not survivorsFolder:FindFirstChild(s.Name) then
                        Instance.new("StringValue", survivorsFolder).Name = s.Name
                    end
                end
            end
            local skinsRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Skins")
            if skinsRoot then
                for _, skin in ipairs(skinsRoot:GetDescendants()) do
                    if (skin:IsA("Folder") or skin:IsA("Model")) and not skinsFolder:FindFirstChild(skin.Name) then
                        Instance.new("StringValue", skinsFolder).Name = skin.Name
                    end
                end
            end
        end)
    end)
end

local function _unlockAllEmotes()
    task.spawn(function()
        pcall(function()
            local purchased = lp:WaitForChild("PlayerData"):WaitForChild("Purchased")
            local emotesFolder = purchased:FindFirstChild("Emotes") or Instance.new("Folder", purchased)
            emotesFolder.Name = "Emotes"
            local emotesAssets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Emotes")
            if emotesAssets then
                for _, module in ipairs(emotesAssets:GetDescendants()) do
                    if module:IsA("ModuleScript") and not emotesFolder:FindFirstChild(module.Name) then
                        Instance.new("StringValue", emotesFolder).Name = module.Name
                    end
                end
            end
        end)
    end)
end

local function _unlockVIP()
    pcall(function()
        lp:SetAttribute("VIP", true)
        local pData = lp:WaitForChild("PlayerData")
        local vVal = pData:FindFirstChild("VIP")
        if not vVal then
            vVal = Instance.new("BoolValue"); vVal.Name = "VIP"; vVal.Parent = pData
        end
        vVal.Value = true
    end)
end

local function _setStat(statName, value)
    pcall(function()
        local stats = lp:FindFirstChild("PlayerData") and lp.PlayerData:FindFirstChild("Stats")
        if not stats then return end
        local statObj = stats:FindFirstChild(statName, true)
        if statObj and (statObj:IsA("NumberValue") or statObj:IsA("IntValue") or statObj:IsA("FloatValue")) then
            statObj.Value = value
        end
    end)
end

-- ==========================================
-- 自动格挡快捷悬浮按钮
-- ==========================================
local function createAutoBlockQuickButton()
    if lp.PlayerGui:FindFirstChild("SwesakenQuickBtn") then return end
    local sg = Instance.new("ScreenGui")
    sg.Name = "SwesakenQuickBtn"; sg.ResetOnSpawn = false
    sg.Parent = lp.PlayerGui
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local btn = Instance.new("TextButton")
    btn.Name = "AutoBlockBtn"
    btn.Size = UDim2.new(0, 80, 0, 80)
    btn.Position = UDim2.new(0, 20, 0.5, -40)
    btn.BackgroundColor3 = Color3.fromRGB(150, 45, 45)
    btn.BackgroundTransparency = 0.2
    btn.BorderSizePixel = 0
    btn.Text = "AutoBlock\nOFF"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = false
    btn.Parent = sg
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(255, 80, 80); stroke.Thickness = 2; stroke.Transparency = 0.3

    local active = false
    local isDragging = false
    local dragStart = nil
    local startPos = nil

    btn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = false; dragStart = i.Position; startPos = btn.Position
        end
    end)
    btn.InputChanged:Connect(function(i)
        if dragStart and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = i.Position - dragStart
            if delta.Magnitude > 20 then
                isDragging = true
                btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
    btn.InputEnded:Connect(function(i)
        if dragStart and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1) then
            local delta = i.Position - dragStart
            if not isDragging or delta.Magnitude < 20 then
                active = not active
                SwesakenAutoBlockEnabled = active
                if active then
                    SwesakenLastAbilityLastUsed, SwesakenLastAbilitiesUsed, SwesakenBlockLocked = nil, nil, false
                    btn.Text = "AutoBlock\nON"
                    btn.BackgroundColor3 = Color3.fromRGB(45, 150, 45)
                    stroke.Color = Color3.fromRGB(80, 255, 80)
                else
                    btn.Text = "AutoBlock\nOFF"
                    btn.BackgroundColor3 = Color3.fromRGB(150, 45, 45)
                    stroke.Color = Color3.fromRGB(255, 80, 80)
                end
            end
            dragStart = nil; isDragging = false
        end
    end)
end
createAutoBlockQuickButton()

-- ==========================================
-- WindUI 面板
-- ==========================================
print("[Swesaken] Creating Window...")
local Window = WindUI:CreateWindow({
    Title = "Swesaken",
    Icon = "shield",
    Author = "by Swesaken & Meowsaken",
    Folder = "Swesaken",
    Size = UDim2.fromOffset(600, 460),
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 200,
    HideSearchBar = true,
    ScrollBarEnabled = false,
    Background = nil,
    BackgroundImageTransparency = 1,
})
print("[Swesaken] Window created!")
task.wait(0.2)

local ConfigManager = Window.ConfigManager
pcall(function() ConfigManager:SetAutoSave(true) end)
local SwesakenConfig = ConfigManager:CreateConfig("SwesakenConfig")
task.wait(0.2)

print("[Swesaken] Building Tabs...")
local Tabs = {
    Home = Window:Tab({ Title = "Home", Icon = "home" }),
    Server = Window:Tab({ Title = "Server (服务器)", Icon = "globe" }),
    AutoBlock = Window:Tab({ Title = "Auto Block (自动格挡)", Icon = "shield" }),
    HDT = Window:Tab({ Title = "Hitbox Drag (拖拽)", Icon = "move" }),
    PunchAim = Window:Tab({ Title = "Punch Aim (出拳自瞄)", Icon = "crosshair" }),
    Aim = Window:Tab({ Title = "Aim (自瞄)", Icon = "target" }),
    Killers = Window:Tab({ Title = "Killers (杀手)", Icon = "swords" }),
    Player = Window:Tab({ Title = "Player (玩家)", Icon = "user" }),
    ESP = Window:Tab({ Title = "ESP (透视)", Icon = "eye" }),
    Generator = Window:Tab({ Title = "Generator (发电机)", Icon = "zap" }),
    Backstab = Window:Tab({ Title = "Backstab (背刺)", Icon = "zap" }),
    AntiBackstab = Window:Tab({ Title = "Anti-Backstab (防背刺)", Icon = "shield-off" }),
    Stealth = Window:Tab({ Title = "Stealth (隐身)", Icon = "eye-off" }),
    Hitbox = Window:Tab({ Title = "Hitbox (判定框)", Icon = "move" }),
    Parry = Window:Tab({ Title = "Parry (自动格挡)", Icon = "shield-check" }),
    Miscellaneous = Window:Tab({ Title = "Miscellaneous (杂项)", Icon = "settings" }),
    InfiniteStamina = Window:Tab({ Title = "Infinite Stamina (无限体力)", Icon = "battery" }),
    Unlock = Window:Tab({ Title = "Unlock (解锁, 风险)", Icon = "unlock" }),
    Config = Window:Tab({ Title = "Config (配置)", Icon = "save" }),
}
task.wait(0.2)
print("[Swesaken] Tabs OK, adding controls...")

Tabs.Home:Paragraph({ Title = "About", Desc = "Combined features + optimized ESP + soft cute text" })

-- ==========================================
-- Server Tab
-- ==========================================
Tabs.Server:Section({ Title = "Server Browser (服务器浏览器)" })
Tabs.Server:Button({ Title = "Open Server Browser (打开浏览器)", Callback = function() _openServerBrowser() end })
Tabs.Server:Button({ Title = "Rejoin Current Server (重连当前服)", Callback = function() _rejoinServer() end })
Tabs.Server:Button({ Title = "Join Low Ping Server (加入低延迟服)", Callback = function()
    local id = _findLowPingServer()
    if id then pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, id, lp) end) end
end })
Tabs.Server:Button({ Title = "Join Beginner Server (加入新手服)", Callback = function()
    local id = _findBeginnerServer()
    if id then pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, id, lp) end) end
end })

-- ==========================================
-- AutoBlock Tab
-- ==========================================
Tabs.AutoBlock:Toggle({ Title = "Enable Swesaken AutoBlock (启用自动格挡)", Value = false, Flag = "AutoBlock",
    Callback = function(v)
        SwesakenAutoBlockEnabled = v
        if v then SwesakenLastAbilityLastUsed, SwesakenLastAbilitiesUsed, SwesakenBlockLocked = nil, nil, false end
    end })
Tabs.AutoBlock:Slider({ Title = "Hitbox Size (判定框大小)", Value = { Min = 0.2, Max = 3.0, Default = 1.0 }, Step = 0.1, Flag = "HBSize", Callback = function(v) SwesakenHitboxScale = v end })
Tabs.AutoBlock:Slider({ Title = "Hitbox Offset (Z) (Z偏移)", Value = { Min = -10, Max = 0, Default = -1.4 }, Step = 0.1, Flag = "HBOffset", Callback = function(v) SwesakenHitboxOffset = v end })
Tabs.AutoBlock:Slider({ Title = "Hitbox Fwd/Back (前后偏移)", Value = { Min = -10, Max = 10, Default = 0 }, Step = 0.1, Flag = "HBFwdBack", Tooltip = "Positive = forward, Negative = backward", Callback = function(v) SwesakenHitboxFrontBackOffset = v end })
Tabs.AutoBlock:Slider({ Title = "Hitbox Width (判定框宽度)", Value = { Min = 0.2, Max = 3.0, Default = 1.0 }, Step = 0.1, Flag = "HBWidth", Callback = function(v) SwesakenHitboxWidthScale = v end })
Tabs.AutoBlock:Slider({ Title = "Hitbox Duration (持续时间)", Value = { Min = 0.1, Max = 5.0, Default = 1.5 }, Step = 0.1, Flag = "HBDur", Callback = function(v) SwesakenHitboxDuration = v end })
Tabs.AutoBlock:Slider({ Title = "Block Delay (格挡延迟)", Value = { Min = 0, Max = 1, Default = 0 }, Step = 0.01, Flag = "BkDelay", Callback = function(v) SwesakenBlockDelay = v end })
Tabs.AutoBlock:Slider({ Title = "Hitbox Transparency (判定框透明)", Value = { Min = 0, Max = 1, Default = 0.5 }, Step = 0.05, Flag = "HBTrans", Callback = function(v) SwesakenHitboxTransparency = v end })

-- ==========================================
-- HDT Tab
-- ==========================================
Tabs.HDT:Toggle({ Title = "Enable HDT (启用拖拽)", Value = false, Flag = "HDT_Toggle", Callback = function(v) hitboxDraggingTech = v end })
Tabs.HDT:Slider({ Title = "HDT Speed (拖拽速度)", Value = { Min = 1, Max = 30, Default = 7.5 }, Step = 0.1, Flag = "HDT_Spd", Callback = function(v) Dspeed = v end })
Tabs.HDT:Slider({ Title = "HDT Delay (拖拽延迟)", Value = { Min = 0, Max = 1, Default = 0 }, Step = 0.01, Flag = "HDT_Dly", Callback = function(v) Ddelay = v end })
Tabs.HDT:Slider({ Title = "HDT Duration (拖拽时长)", Value = { Min = 0.1, Max = 3.0, Default = 1.2 }, Step = 0.1, Flag = "HDT_Dur", Callback = function(v) HDT_Duration = v end })
Tabs.HDT:Slider({ Title = "HDT Stop Distance (停止距离)", Value = { Min = 0.5, Max = 5.0, Default = 2.5 }, Step = 0.1, Flag = "HDT_SD", Callback = function(v) HDT_StopDistance = v end })
Tabs.HDT:Slider({ Title = "Turn Smoothness (转头平滑)", Value = { Min = 0.3, Max = 20, Default = 5 }, Step = 0.1, Flag = "HDT_TurnSmooth", Callback = function(v) HDT_TurnSmoothness = v end })
Tabs.HDT:Slider({ Title = "Trigger Range (触发范围)", Value = { Min = 5, Max = 100, Default = 30 }, Step = 1, Flag = "HDT_TrigRange", Callback = function(v) HDT_DetectRange = v end })

-- ==========================================
-- PunchAim Tab
-- ==========================================
Tabs.PunchAim:Toggle({ Title = "Enable Punch Aim (启用出拳自瞄)", Value = false, Flag = "PA_Main", Callback = function(v) MyAnimLockOn = v end })
Tabs.PunchAim:Slider({ Title = "Aim Lock Duration (锁定时长)", Value = { Min = 0.1, Max = 2, Default = 0.8 }, Step = 0.05, Flag = "PA_Dur", Callback = function(v) AIM_WINDOW = v end })
Tabs.PunchAim:Slider({ Title = "Prediction (Studs) (预测偏移)", Value = { Min = 0, Max = 20, Default = 4 }, Step = 0.5, Flag = "PA_Pred", Callback = function(v) predictionValue = v end })
Tabs.PunchAim:Toggle({ Title = "Character Lock (角色锁定)", Value = true, Flag = "PA_CL", Callback = function(v) aimPunchToggles["Character Lock"] = v end })
Tabs.PunchAim:Toggle({ Title = "Camera Lock (相机锁定)", Value = false, Flag = "PA_CamL", Callback = function(v) aimPunchToggles["Camera Lock"] = v end })
Tabs.PunchAim:Toggle({ Title = "Enable Auto Punch (自动出拳)", Value = false, Flag = "AutoPunch", Callback = function(v) autoPunchEventEnabled = v end })

-- ==========================================
-- Aim Tab
-- ==========================================
local AimTab = Tabs.Aim
AimTab:Section({ Title = "Noli Aim (Noli自瞄)" })
AimTab:Toggle({ Title = "Star Bomb Aim (星弹自瞄)", Value = false, Flag = "Noli_Star", Callback = function(v) VX_NoilStarAim(v) end })
AimTab:Toggle({ Title = "Void Rush Aim (虚空自瞄)", Value = false, Flag = "Noli_Void", Callback = function(v) VX_NoilVoidAim(v) end })
AimTab:Section({ Title = "General Aim (通用自瞄)" })
AimTab:Toggle({ Title = "General Aim (Camera Lock Nearest) (通用自瞄)", Value = false, Flag = "GeneralAim",
    Callback = function(v)
        _generalAimEnabled = v
        if _generalAimConn then _generalAimConn:Disconnect(); _generalAimConn = nil end
        if v then
            _generalAimConn = RunService.RenderStepped:Connect(function()
                if not _generalAimEnabled then return end
                local target = _aimAtNearest(_getAllPlayerCharacters())
                if not target then return end
                local tgtHRP = target:FindFirstChild("HumanoidRootPart")
                if not tgtHRP then return end
                local cc = Camera.CFrame
                local targetPos = Vector3.new(tgtHRP.Position.X, cc.Position.Y, tgtHRP.Position.Z)
                local tl = (targetPos - cc.Position).Unit
                local cl = cc.LookVector
                local nl = cl:Lerp(tl, _generalAimSmoothness / 100)
                Camera.CFrame = CFrame.lookAt(cc.Position, cc.Position + nl * 100)
            end)
        end
    end })
AimTab:Slider({ Title = "Aim Smoothness (自瞄平滑)", Value = { Min = 1, Max = 100, Default = 20 }, Step = 1, Flag = "GA_Smooth", Callback = function(v) _generalAimSmoothness = v end })
AimTab:Section({ Title = "Silent Aim (静默自瞄)" })
AimTab:Toggle({ Title = "Silent Aim (Killer) (杀手静默自瞄)", Value = false, Flag = "SilentAim",
    Callback = function(v)
        _silentAimEnabled = v
        if _silentAimConn then _silentAimConn:Disconnect(); _silentAimConn = nil end
        if v then
            _silentAimConn = RunService.Heartbeat:Connect(function()
                if not _silentAimEnabled then return end
                local char = lp.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if not root then return end
                local best, bd = nil, math.huge
                for _, m in ipairs(SurvivorsFolder:GetChildren()) do
                    if m:IsA("Model") then
                        local hrp = m:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local d = (hrp.Position - root.Position).Magnitude
                            if d < bd and d <= _silentAimDistance then bd = d; best = hrp end
                        end
                    end
                end
                if best then
                    root.CFrame = CFrame.new(root.Position, Vector3.new(best.Position.X, root.Position.Y, best.Position.Z))
                end
            end)
        end
    end })
AimTab:Slider({ Title = "Silent Aim Distance (静默距离)", Value = { Min = 10, Max = 500, Default = 100 }, Step = 1, Flag = "SA_Dist", Callback = function(v) _silentAimDistance = v end })

-- ==========================================
-- Killers Tab
-- ==========================================
local KTab = Tabs.Killers
KTab:Section({ Title = "Azure (Azure)" })
KTab:Toggle({ Title = "Azure Auto QTE (Azure自动QTE)", Value = false, Flag = "AzureQTE",
    Callback = function(v) if v then VX_enableAzureQTE() else VX_disableAzureQTE() end end })
KTab:Section({ Title = "Noli (Noli)" })
KTab:Toggle({ Title = "Star Bomb Aim (星弹自瞄)", Value = false, Flag = "K_Star", Callback = function(v) VX_NoilStarAim(v) end })
KTab:Toggle({ Title = "Void Rush Aim (虚空自瞄)", Value = false, Flag = "K_Void", Callback = function(v) VX_NoilVoidAim(v) end })
KTab:Toggle({ Title = "Delete Fake Noli (删除假Noli)", Value = false, Flag = "DeleteFakeNoli", Callback = function(v) _deleteFakeNoliEnabled = v end })
KTab:Section({ Title = "c00lkidd (c00lkidd)" })
KTab:Toggle({ Title = "c00lkidd Dash Turn (冲刺转向)", Value = false, Flag = "DashTurn",
    Callback = function(v) if v then VX_enableC00lkiddDashTurn() else VX_disableC00lkiddDashTurn() end end })
KTab:Section({ Title = "Nosferatu (吸血鬼)" })
KTab:Toggle({ Title = "Auto Break Free (自动挣脱)", Value = false, Flag = "BreakFree",
    Callback = function(v)
        _autoBreakFreeEnabled = v
        if v then VX_startBreakFree()
        else if _autoBreakFreeTask then task.cancel(_autoBreakFreeTask); _autoBreakFreeTask = nil end end
    end })
KTab:Toggle({ Title = "Auto Pull Rope (自动拉绳)", Value = false, Flag = "PullRope",
    Callback = function(v)
        _autoPullRopeEnabled = v
        if v then VX_startPullRope()
        else if _autoPullRopeTask then task.cancel(_autoPullRopeTask); _autoPullRopeTask = nil end end
    end })

-- ==========================================
-- Player Tab
-- ==========================================
local PTab = Tabs.Player
PTab:Section({ Title = "Movement (移动)" })
PTab:Toggle({ Title = "Enable Speed (启用加速)", Value = false, Flag = "SpeedToggle", Callback = function(v)
    _speedEnabled = v
    if not v and lp.Character then
        local hum = lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end
end })
PTab:Slider({ Title = "Speed (速度)", Value = { Min = 1, Max = 500, Default = 16 }, Step = 1, Flag = "SpeedVal", Callback = function(v) _speedValue = v end })
PTab:Toggle({ Title = "Enable Flight (启用飞行)", Value = false, Flag = "FlightToggle",
    Callback = function(v) _flightEnabled = v; if v then VX_startFlight() else VX_stopFlight() end end })
PTab:Slider({ Title = "Flight Speed (飞行速度)", Value = { Min = 1, Max = 200, Default = 50 }, Step = 1, Flag = "FlightSpd", Callback = function(v) _flightSpeed = v end })

-- ==========================================
-- ESP Tab
-- ==========================================
Tabs.ESP:Toggle({ Title = "Killer ESP (杀手透视)", Value = false, Flag = "KillerESP", Callback = onKillerESPToggle })
Tabs.ESP:Toggle({ Title = "Survivor ESP (幸存者透视)", Value = false, Flag = "SurvivorESP", Callback = onSurvivorESPToggle })
Tabs.ESP:Toggle({ Title = "Fake Noli ESP (假Noli透视)", Value = false, Flag = "FakeNoliESP", Callback = onFakeNoliToggle })
Tabs.ESP:Toggle({ Title = "Medkit ESP (医疗包透视)", Value = false, Flag = "MedkitESP", Callback = onMedkitToggle })
Tabs.ESP:Toggle({ Title = "BloxyCola ESP (可乐透视)", Value = false, Flag = "BloxyESP", Callback = onBloxyToggle })
Tabs.ESP:Toggle({ Title = "Generators ESP (发电机透视)", Value = false, Flag = "GenESP", Callback = onGenToggle })
Tabs.ESP:Toggle({ Title = "Graffiti ESP (涂鸦透视)", Value = false, Flag = "GraffitiESP", Callback = function(v) espGraffitiEnabled = v end })
Tabs.ESP:Toggle({ Title = "Folders ESP (文件夹透视)", Value = false, Flag = "FoldersESP", Callback = function(v) espFoldersEnabled = v end })
Tabs.ESP:Toggle({ Title = "Plant Traps ESP (植物陷阱透视)", Value = false, Flag = "PlantTrapsESP", Callback = function(v) espPlantTrapsEnabled = v end })
Tabs.ESP:Toggle({ Title = "Golem & Azure ESP (魔像透视)", Value = false, Flag = "GolemAzureESP", Callback = function(v) espGolemAzureEnabled = v end })
Tabs.ESP:Toggle({ Title = "Sentry & Dispenser ESP (哨戒透视)", Value = false, Flag = "SentryDispESP", Callback = function(v) espSentryDispEnabled = v end })
Tabs.ESP:Toggle({ Title = "Minions / Zombie ESP (小兵透视)", Value = false, Flag = "MinionsESP", Callback = function(v) espMinionsEnabled = v end })
Tabs.ESP:Toggle({ Title = "Device ESP (设备透视)", Value = false, Flag = "DeviceESP",
    Callback = function(v)
        espDeviceEnabled = v
        if v then for _, p in ipairs(Players:GetPlayers()) do VX_bindDevice(p) end
        else
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character then
                    local h = p.Character:FindFirstChild("Head")
                    if h and h:FindFirstChild("DeviceESP") then h.DeviceESP:Destroy() end
                end
            end
        end
    end })
Tabs.ESP:Toggle({ Title = "Enable Text ESP (文字透视)", Value = false, Flag = "EnableTextESP",
    Callback = function(v)
        enableTextESP = v
        for _, m in ipairs(KillersFolder:GetChildren()) do
            local rec = espCache[m]
            if rec then
                if rec.nameLbl then rec.nameLbl.Visible = v end
                if rec.hpLbl then rec.hpLbl.Visible = v end
            end
        end
        for _, m in ipairs(SurvivorsFolder:GetChildren()) do
            local rec = espCache[m]
            if rec then
                if rec.nameLbl then rec.nameLbl.Visible = v end
                if rec.hpLbl then rec.hpLbl.Visible = v end
            end
        end
    end })
Tabs.ESP:Section({ Title = "2D Box (2D方框)" })
Tabs.ESP:Toggle({ Title = "Enable 2D Box (启用2D框)", Value = false, Flag = "Box2D_Enable",
    Callback = function(v) _2dBoxEnabled = v end })
Tabs.ESP:Toggle({ Title = "Show Survivor Box (幸存者框)", Value = true, Flag = "Box2D_Surv",
    Callback = function(v) _2dBoxShowSurvivor = v end })
Tabs.ESP:Toggle({ Title = "Show Killer Box (杀手框)", Value = true, Flag = "Box2D_Kill",
    Callback = function(v) _2dBoxShowKiller = v end })
Tabs.ESP:Toggle({ Title = "Show Name (显示名字)", Value = true, Flag = "Box2D_Name",
    Callback = function(v) _2dBoxShowName = v end })
Tabs.ESP:Toggle({ Title = "Show HP (显示血量)", Value = true, Flag = "Box2D_HP",
    Callback = function(v) _2dBoxShowHP = v end })
Tabs.ESP:Toggle({ Title = "Show Distance (显示距离)", Value = true, Flag = "Box2D_Dist",
    Callback = function(v) _2dBoxShowDist = v end })
Tabs.ESP:Toggle({ Title = "Show Status (显示状态)", Value = false, Flag = "Box2D_Status",
    Callback = function(v) _2dBoxShowStatus = v end })

-- ==========================================
-- Generator Tab
-- ==========================================
Tabs.Generator:Toggle({ Title = "Auto Solve (自动解谜)", Value = false, Flag = "FlowAutoSolve", Callback = function(v) flow.on = v end })
Tabs.Generator:Slider({ Title = "Auto Solve Speed (解谜速度)", Value = { Min = 0.01, Max = 0.5, Default = 0.04 }, Step = 0.01, Flag = "FlowSpeed", Callback = function(v) flow.nodeDelay = v end })

-- ==========================================
-- Backstab Tab
-- ==========================================
Tabs.Backstab:Toggle({ Title = "Enable Auto Backstab (启用背刺)", Value = false, Flag = "BS_Enable",
    Callback = function(v) _bsEnabled = v; if v then task.spawn(_bsLoop) end end })
Tabs.Backstab:Dropdown({ Title = "Backstab Mode (背刺模式)", Values = {"Lerp","Teleport","Aim"}, Default = "Lerp", Flag = "BS_Mode",
    Callback = function(v) _bsMode = v end })
Tabs.Backstab:Slider({ Title = "Detection Range (检测范围)", Value = { Min = 1, Max = 30, Default = 8 }, Step = 0.5, Flag = "BS_Range",
    Callback = function(v) _bsRange = v end })
Tabs.Backstab:Slider({ Title = "Behind Distance (背后距离)", Value = { Min = 0.5, Max = 10, Default = 3.5 }, Step = 0.5, Flag = "BS_BehindDist",
    Callback = function(v) _bsBehindDist = v end })
Tabs.Backstab:Slider({ Title = "Behind Cone Angle (背后锥角)", Value = { Min = 10, Max = 180, Default = 70 }, Step = 5, Flag = "BS_Cone",
    Callback = function(v) _bsCone = v end })
Tabs.Backstab:Slider({ Title = "Cooldown (冷却)", Value = { Min = 0.5, Max = 15, Default = 5 }, Step = 0.5, Flag = "BS_Cooldown",
    Callback = function(v) _bsCooldown = v end })

-- ==========================================
-- Anti-Backstab Tab
-- ==========================================
Tabs.AntiBackstab:Toggle({ Title = "Enable Anti-Backstab (启用防背刺)", Value = false, Flag = "Abs_Enable",
    Callback = function(v)
        _absEnabled = v
        if v then _absStart() else _absStop() end
    end })
Tabs.AntiBackstab:Slider({ Title = "Detection Range (检测范围)", Value = { Min = 10, Max = 120, Default = 40 }, Step = 1, Flag = "Abs_Range",
    Callback = function(v)
        _absRange = v
        _absResizeRings()
    end })
Tabs.AntiBackstab:Slider({ Title = "Lock Duration (锁定时间)", Value = { Min = 0.3, Max = 5.0, Default = 1.5 }, Step = 0.1, Flag = "Abs_Dur",
    Callback = function(v) _absDuration = v end })

-- ==========================================
-- Stealth Tab
-- ==========================================
Tabs.Stealth:Section({ Title = "Invisibility (隐身)" })
Tabs.Stealth:Toggle({ Title = "Enable Invisibility (启用隐身)", Value = false, Flag = "Inv_Enable",
    Callback = function(v)
        if v then
            if not _invInstall() then
                WindUI:Notify({ Title = "Invisibility (隐身)", Content = "Hook failed (失败)", Duration = 3 })
                return
            end
        end
        _invEnabled = v
    end })
Tabs.Stealth:Slider({ Title = "Invisibility Y Offset (Y偏移)", Value = { Min = 1000, Max = 10000, Default = 5000 }, Step = 100, Flag = "Inv_Offset",
    Callback = function(v) _invOffset = v end })

Tabs.Stealth:Section({ Title = "Suction (吸力)" })
Tabs.Stealth:Toggle({ Title = "Enable Suction (启用吸力)", Value = false, Flag = "Suction_Enable",
    Callback = function(v)
        _suctionEnabled = v
        if v then _suctionTick() else
            if _suctionConn then _suctionConn:Disconnect(); _suctionConn = nil end
        end
    end })
Tabs.Stealth:Slider({ Title = "Suction Strength (吸力强度)", Value = { Min = 5, Max = 150, Default = 50 }, Step = 1, Flag = "Suction_Strength",
    Callback = function(v) _suctionStrength = v end })
Tabs.Stealth:Slider({ Title = "Suction Range (吸力范围)", Value = { Min = 20, Max = 200, Default = 100 }, Step = 1, Flag = "Suction_Range",
    Callback = function(v) _suctionRange = v end })

-- ==========================================
-- Hitbox Tab
-- ==========================================
Tabs.Hitbox:Section({ Title = "Hitbox Extender (判定框扩展)" })
Tabs.Hitbox:Toggle({ Title = "Enable Hitbox Extender (启用判定框扩展)", Value = false, Flag = "HBE_Enable",
    Callback = function(v)
        _hbeEnabled = v
        if v then
            task.spawn(function()
                while _hbeEnabled do
                    RunService.Heartbeat:Wait()
                    local char = lp.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local hb = Workspace:FindFirstChild("Hitboxes")
                        local myName = char:GetAttribute("Username") or lp.Name
                        local myHitbox = hb and hb:FindFirstChild(myName .. "Hitbox")
                        if myHitbox and (myHitbox.Position - hrp.Position).Magnitude <= 15 then
                            local vel = hrp.AssemblyLinearVelocity
                            if vel.Magnitude >= 0.5 then
                                local boosted = vel + vel.Unit * (_hbeRange * 6)
                                hrp.AssemblyLinearVelocity = Vector3.new(boosted.X, vel.Y, boosted.Z)
                                RunService.RenderStepped:Wait()
                                if hrp.Parent then hrp.AssemblyLinearVelocity = vel end
                            end
                        end
                    end
                end
            end)
        end
    end })
Tabs.Hitbox:Slider({ Title = "Extend Range (延伸距离)", Value = { Min = 0, Max = 50, Default = 10 }, Step = 1, Flag = "HBE_Range",
    Callback = function(v) _hbeRange = v end })

Tabs.Hitbox:Section({ Title = "Hitbox Tracker (判定框追踪)" })
Tabs.Hitbox:Toggle({ Title = "Enable Hitbox Tracker (启用判定框追踪)", Value = false, Flag = "HBT_Enable",
    Callback = function(v)
        _hbtEnabled = v
        if v then
            task.spawn(function()
                while _hbtEnabled do
                    RunService.Heartbeat:Wait()
                    local char = lp.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if hrp and hum then
                        local attacking = false
                        for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                            if track.Animation and track.Length > 0 and track.TimePosition / track.Length < 0.75 then
                                attacking = true; break
                            end
                        end
                        if attacking then
                            local best, bd = nil, _hbtRange
                            for _, m in ipairs(SurvivorsFolder:GetChildren()) do
                                if m:IsA("Model") and m ~= char then
                                    local tHRP = m:FindFirstChild("HumanoidRootPart")
                                    local tHum = m:FindFirstChildOfClass("Humanoid")
                                    if tHRP and tHum and tHum.Health > 0 then
                                        local d = (tHRP.Position - hrp.Position).Magnitude
                                        if d < bd then bd = d; best = tHRP end
                                    end
                                end
                            end
                            if best then
                                local ping = 0.05
                                pcall(function()
                                    local Stats = game:GetService("Stats")
                                    ping = tonumber(Stats.PerformanceStats.Ping:GetValue()) / 1000
                                end)
                                if ping <= 0 then ping = 0.05 end
                                local offset = Vector3.new(_hbtRandom:NextNumber(-1.5, 1.5), 0, _hbtRandom:NextNumber(-1.5, 1.5))
                                local targetPos = best.Position + offset + best.Velocity * (ping * 1.25)
                                local newVel = (targetPos - hrp.Position) / (ping * 2)
                                local origVel = hrp.Velocity
                                hrp.Velocity = newVel
                                RunService.RenderStepped:Wait()
                                if hrp.Parent then hrp.Velocity = origVel end
                            end
                        end
                    end
                end
            end)
        end
    end })
Tabs.Hitbox:Slider({ Title = "Tracker Range (追踪范围)", Value = { Min = 10, Max = 200, Default = 60 }, Step = 1, Flag = "HBT_Range",
    Callback = function(v) _hbtRange = v end })

-- ==========================================
-- Parry Tab
-- ==========================================
Tabs.Parry:Section({ Title = "Slasher (斩首者)" })
Tabs.Parry:Toggle({ Title = "Enable Slasher Auto Parry (斩首者格挡)", Value = false, Flag = "Parry_Slasher",
    Callback = function(v) _slasherEnabled = v end })
Tabs.Parry:Slider({ Title = "Slasher Parry Range (斩首者范围)", Value = { Min = 5, Max = 40, Default = 15 }, Step = 1, Flag = "Parry_SlasherRange",
    Callback = function(v) _slasherRange = v end })

Tabs.Parry:Section({ Title = "JohnDoe (约翰多)" })
Tabs.Parry:Toggle({ Title = "Enable JohnDoe Auto Parry (约翰多格挡)", Value = false, Flag = "Parry_JohnDoe",
    Callback = function(v) _jdEnabled = v end })
Tabs.Parry:Slider({ Title = "JohnDoe Parry Range (约翰多范围)", Value = { Min = 5, Max = 40, Default = 15 }, Step = 1, Flag = "Parry_JDRange",
    Callback = function(v) _jdRange = v end })

-- ==========================================
-- Miscellaneous Tab
-- ==========================================
Tabs.Miscellaneous:Slider({ Title = "FOV (视场角)", Value = { Min = 40, Max = 120, Default = 70 }, Step = 1, Flag = "FovSlider", Callback = function(v) _fovValue = v; if _fovEnabled and _fovSetting then pcall(function() _fovSetting.Value = v end) end; if _fovEnabled then pcall(function() Camera.FieldOfView = v end) end end })
Tabs.Miscellaneous:Toggle({ Title = "Enable FOV (启用视场)", Value = false, Flag = "FovToggle", Callback = function(v) _fovEnabled = v end })
Tabs.Miscellaneous:Toggle({ Title = "Free Zoom (自由缩放)", Value = false, Flag = "FreeZoom", Callback = function(v) if v then lp.CameraMaxZoomDistance = 1000; lp.CameraMinZoomDistance = 0.5 else lp.CameraMaxZoomDistance = 128; lp.CameraMinZoomDistance = 0.5 end end })
Tabs.Miscellaneous:Toggle({ Title = "Camera Noclip (相机穿墙)", Value = false, Flag = "CameraNoclip", Callback = function(v) lp.DevCameraOcclusionMode = v and Enum.DevCameraOcclusionMode.Invisicam or Enum.DevCameraOcclusionMode.Zoom end })
Tabs.Miscellaneous:Toggle({ Title = "Show Chat Window (显示聊天框)", Value = false, Flag = "ShowChat",
    Callback = function(v)
        _showChatEnabled = v
        pcall(function()
            local cfg = TextChatService:FindFirstChild("ChatWindowConfiguration")
            if cfg then cfg.Enabled = v end
            local inp = TextChatService:FindFirstChild("ChatInputBarConfiguration")
            if inp then inp.Enabled = v end
        end)
    end })
Tabs.Miscellaneous:Toggle({ Title = "Anti Lag (反卡顿)", Value = false, Flag = "AntiLag", Callback = function(v) setAntiLag(v) end })
Tabs.Miscellaneous:Toggle({ Title = "Anti-Acid (防酸液)", Value = false, Flag = "AntiAcid", Callback = function(v) _antiAcid = v end })
Tabs.Miscellaneous:Toggle({ Title = "Hide Injured UI (隐藏受伤UI)", Value = true, Flag = "HideInjury", Callback = function(v) _applyHideInjury(v) end })
Tabs.Miscellaneous:Toggle({ Title = "Disable Blindness (禁用失明)", Value = true, Flag = "DisableBlind", Callback = function(v) _applyDisableBlindness(v) end })

Tabs.Miscellaneous:Toggle({ Title = "Show Hidden Info (显示隐藏信息)", Value = false, Flag = "ShowHiddenInfo",
    Callback = function(v)
        _hiddenInfoEnabled = v
        _hiddenInfoApply(v)
        if v then
            if not _hiddenInfoConn then
                _hiddenInfoConn = Players.PlayerAdded:Connect(function(p)
                    task.wait(1)
                    if _hiddenInfoEnabled then _hiddenInfoSave(p); _hiddenInfoReveal(p) end
                end)
            end
        else
            if _hiddenInfoConn then _hiddenInfoConn:Disconnect(); _hiddenInfoConn = nil end
        end
    end })

Tabs.Miscellaneous:Toggle({ Title = "Low Graphics Mode (低画质模式)", Value = false, Flag = "LowGfx",
    Callback = function(v)
        _lowGfxEnabled = v
        _setLowGraphics(v)
    end })

Tabs.Miscellaneous:Button({ Title = "Suicide (自杀)",
    Callback = function() _suicide() end })

Tabs.Miscellaneous:Section({ Title = "Device Spoof (设备伪装)" })
Tabs.Miscellaneous:Toggle({
    Title = "Enable Device Spoof (启用设备伪装)",
    Value = false,
    Flag  = "DeviceSpoofToggle",
    Callback = function(v)
        if v then
            installDeviceSpoof()
            sendDeviceSpoofToServer(_deviceSpoofTarget)
        else
            if NetworkModule then
                pcall(function()
                    NetworkModule:FireServerConnection("SetDevice", "REMOTE_EVENT", "Unknown")
                end)
            end
        end
        _deviceSpoofEnabled = v
    end,
})
Tabs.Miscellaneous:Dropdown({
    Title = "Spoof Target (伪装目标)",
    Values = { "PC", "Mobile", "Tablet", "Console", "VR" },
    Default = "Mobile",
    Flag = "DeviceSpoofTarget",
    Callback = function(v)
        if DeviceSpoofProfiles[v] then
            _deviceSpoofTarget = v
            if _deviceSpoofEnabled then
                sendDeviceSpoofToServer(v)
            end
        end
    end,
})

-- ==========================================
-- InfiniteStamina Tab
-- ==========================================
Tabs.InfiniteStamina:Toggle({ Title = "Unlimited Stamina (无限体力)", Value = false, Flag = "UnlimStam", Callback = function(v) _unlimitedStamina = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Toggle({ Title = "Enable Max Stamina (启用最大体力)", Value = false, Flag = "EnMaxStam", Callback = function(v) _enableMaxStamina = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Slider({ Title = "Max Stamina (最大体力)", Value = { Min = 1, Max = 1000, Default = 100 }, Step = 1, Flag = "MaxStamVal", Callback = function(v) _maxStaminaVal = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Toggle({ Title = "Enable Min Stamina (启用最小体力)", Value = false, Flag = "EnMinStam", Callback = function(v) _enableMinStamina = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Slider({ Title = "Min Stamina (最小体力)", Value = { Min = 0, Max = 100, Default = 0 }, Step = 1, Flag = "MinStamVal", Callback = function(v) _minStaminaVal = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Toggle({ Title = "Enable Stamina Gain (启用恢复)", Value = false, Flag = "EnStamGain", Callback = function(v) _enableStaminaGain = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Slider({ Title = "Stamina Gain (恢复速度)", Value = { Min = 0, Max = 1000, Default = 20 }, Step = 1, Flag = "StamGainVal", Callback = function(v) _staminaGainVal = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Toggle({ Title = "Enable Stamina Loss (启用消耗)", Value = false, Flag = "EnStamLoss", Callback = function(v) _enableStaminaLoss = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Slider({ Title = "Stamina Loss (消耗速度)", Value = { Min = 0, Max = 1000, Default = 10 }, Step = 1, Flag = "StamLossVal", Callback = function(v) _staminaLossVal = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Toggle({ Title = "Enable Sprint Speed (启用冲刺速度)", Value = false, Flag = "EnSprSpd", Callback = function(v) _enableSprintSpeed = v; _updateStaminaCallbacks() end })
Tabs.InfiniteStamina:Slider({ Title = "Sprint Speed (冲刺速度)", Value = { Min = 1, Max = 100, Default = 26 }, Step = 1, Flag = "SprSpdVal", Callback = function(v) _sprintSpeedVal = v; _updateStaminaCallbacks() end })

-- ==========================================
-- Unlock (RISK) Tab
-- ==========================================
Tabs.Unlock:Section({ Title = "Privilege (RISK) (解锁特权, 风险)" })
Tabs.Unlock:Button({ Title = "Unlock All Characters & Skins (解锁全部角色皮肤)",
    Callback = function() _unlockAllChars() end })
Tabs.Unlock:Button({ Title = "Unlock All Emotes (解锁全部表情)",
    Callback = function() _unlockAllEmotes() end })
Tabs.Unlock:Button({ Title = "Unlock VIP (解锁VIP)",
    Callback = function() _unlockVIP() end })

Tabs.Unlock:Section({ Title = "Stats Modify (RISK) (修改统计, 风险)" })
Tabs.Unlock:Input({ Title = "Money (钱)", Placeholder = "输入数值",
    Callback = function(v) local n = tonumber(v); if n then _setStat("Money", n) end end })
Tabs.Unlock:Input({ Title = "Net Worth (净资产)", Placeholder = "输入数值",
    Callback = function(v) local n = tonumber(v); if n then _setStat("NetWorth", n) end end })
Tabs.Unlock:Input({ Title = "Killer Chance (杀手几率)", Placeholder = "输入数值",
    Callback = function(v) local n = tonumber(v); if n then _setStat("KillerChance", n) end end })
Tabs.Unlock:Input({ Title = "Time Played (游玩时间)", Placeholder = "输入数值",
    Callback = function(v) local n = tonumber(v); if n then _setStat("TimePlayed", n) end end })
Tabs.Unlock:Input({ Title = "Killer Wins (杀手胜场)", Placeholder = "输入数值",
    Callback = function(v) local n = tonumber(v); if n then _setStat("KillerWins", n) end end })
Tabs.Unlock:Input({ Title = "Kills (击杀数)", Placeholder = "输入数值",
    Callback = function(v) local n = tonumber(v); if n then _setStat("Kills", n) end end })
Tabs.Unlock:Input({ Title = "Survivor Wins (幸存者胜场)", Placeholder = "输入数值",
    Callback = function(v) local n = tonumber(v); if n then _setStat("SurvivorWins", n) end end })
Tabs.Unlock:Input({ Title = "Objectives Completed (任务完成)", Placeholder = "输入数值",
    Callback = function(v) local n = tonumber(v); if n then _setStat("ObjectivesCompleted", n) end end })

-- ==========================================
-- Config Tab
-- ==========================================
Tabs.Config:Section({ Title = "Configuration Management (配置管理)" })
Tabs.Config:Button({ Title = "Save Config (保存配置)", Callback = function() pcall(function() SwesakenConfig:Save() end); WindUI:Notify({ Title = "Config (配置)", Content = "Saved! (已保存)", Duration = 3 }) end })
Tabs.Config:Button({ Title = "Load Config (加载配置)", Callback = function() pcall(function() SwesakenConfig:Load() end); WindUI:Notify({ Title = "Config (配置)", Content = "Loaded! (已加载)", Duration = 3 }) end })
Tabs.Config:Button({ Title = "Delete Config (删除配置)", Callback = function() pcall(function() SwesakenConfig:Delete() end); WindUI:Notify({ Title = "Config (配置)", Content = "Deleted! (已删除)", Duration = 3 }) end })
pcall(function() SwesakenConfig:Load() end)

print("[Swesaken] === ALL FEATURES LOADED SUCCESSFULLY ===")