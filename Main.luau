
--	Functions.Notify({Title = "Used For Notifications."})
-- 	Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage
-- 	Risky = Floor ~= "Mines" (Means it only works on mines)

local LoadStart = tick()

if shared.Hastelepasta then
    return 
end

shared.Hastelepasta = true


getgenv().Abysall = {
    Legit = true
}


local BaseUrl = "https://cdn.jsdelivr.net/gh/minescartop1/amr-components@main/"

-- boot logger + fast loader (single table on purpose: Luau caps a function at 200 locals)
local Boot = { Log = {}, Start = LoadStart, Rewrite = true, Inflight = {} }

function Boot.Print(Message)
    local Line = string.format("[AMR +%.2fs] %s", tick() - Boot.Start, Message)
    Boot.Log[#Boot.Log + 1] = Line
    print(Line)
end

-- own backup of the components: nothing from the authors' live repos is loaded any more
Boot.MirrorRoot = "https://cdn.jsdelivr.net/gh/minescartop1/amr-components@main/"
-- where Settings > Reload / language change fetches Main from (first one that answers wins)
Boot.MainUrls = { Boot.MirrorRoot .. "Main.luau", "https://gist.githubusercontent.com/minescartop1/8ce36218105a35db0bf47c064009f470/raw/Main.luau" }

function Boot.ToMirror(Url)
    if Url:find("therealcookiemonsterof1966", 1, true) and Url:find("Main.luau", 1, true) then
        -- Settings > Reload used to load the authors' Main; point it at our own gist
        return "https://gist.githubusercontent.com/minescartop1/8ce36218105a35db0bf47c064009f470/raw/Main.luau"
    end
    -- third-party libs, pinned copies in ext/ (Molto is dead: its forwarder points at molto.pages.dev, stubbed)
    if Url:find("molto.pages.dev", 1, true) then return Boot.MirrorRoot .. "ext/Molto/source.lua" end
    for _, E in {
        {"deividcomsono", "Obsidian", "ext/Obsidian/"},
        {"notpoiu", "lucide-roblox-direct", "ext/lucide/"},
        {"notpoiu", "Molto", "ext/Molto/"},
    } do
        local U, R = E[1]:gsub("[%-%.]", "%%%0"), E[2]:gsub("[%-%.]", "%%%0")
        local Sub = Url:match("^https://cdn%.jsdelivr%.net/gh/" .. U .. "/" .. R .. "@[^/]+/(.+)$")
            or Url:match("^https://raw%.githubusercontent%.com/" .. U .. "/" .. R .. "/refs/heads/[^/]+/(.+)$")
            or Url:match("^https://raw%.githubusercontent%.com/" .. U .. "/" .. R .. "/[^/]+/(.+)$")
        if Sub then return Boot.MirrorRoot .. E[3] .. Sub end
    end
    local Path = Url:match("^https://raw%.githubusercontent%.com/coolcookiebusiness/AbysallHubContinued/refs/heads/[^/]+/(.+)$")
        or Url:match("^https://raw%.githubusercontent%.com/coolcookiebusiness/AbysallHubContinued/[^/]+/(.+)$")
        or Url:match("^https://cdn%.jsdelivr%.net/gh/coolcookiebusiness/AbysallHubContinued@[^/]+/(.+)$")
    if Path then return Boot.MirrorRoot .. Path end
    local Other = Url:match("^https://raw%.githubusercontent%.com/bocaj111004/Abysall/refs/heads/[^/]+/(.+)$")
        or Url:match("^https://raw%.githubusercontent%.com/bocaj111004/Abysall/[^/]+/(.+)$")
        or Url:match("^https://cdn%.jsdelivr%.net/gh/bocaj111004/Abysall@[^/]+/(.+)$")
    if Other then return Boot.MirrorRoot .. "bocaj/" .. Other end
    return nil
end

-- raw.githubusercontent.com/<u>/<r>/(refs/heads/)<branch>/<path> -> jsDelivr
function Boot.ToCdn(Url)
    local Mirrored = Boot.ToMirror(Url)
    if Mirrored then return Mirrored end
    local User, Repo, Rest = Url:match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/(.+)$")
    if not User then return Url end
    local Branch, Path = Rest:match("^refs/heads/([^/]+)/(.+)$")
    if not Branch then Branch, Path = Rest:match("^([^/]+)/(.+)$") end
    if not Branch then return Url end
    return string.format("https://cdn.jsdelivr.net/gh/%s/%s@%s/%s", User, Repo, Branch, Path)
end

Boot.RawGet = game.HttpGet

-- HttpGet has a hard ~60s timeout on dead hosts; give up after N seconds instead
Boot.Timeout = 8
function Boot.Race(Function, ...)
    local Arguments = table.pack(...)
    local Finished, Ok, Result = false, false, nil
    task.spawn(function()
        Ok, Result = pcall(Function, table.unpack(Arguments, 1, Arguments.n))
        Finished = true
    end)
    local Began = tick()
    while not Finished and tick() - Began < Boot.Timeout do task.wait(0.05) end
    if not Finished then return false, "timeout" end
    return Ok, Result
end

-- jsDelivr is multi-CDN: if one hostname is blocked or dead, walk the others and remember the one that worked
Boot.CdnHosts = { "cdn.jsdelivr.net", "gcore.jsdelivr.net", "testingcf.jsdelivr.net", "fastly.jsdelivr.net" }
Boot.CdnIndex = 1
function Boot.GetCdn(Target)
    local Path = Target:match("^https://[%w%-]+%.jsdelivr%.net(/.+)$")
    if not Path then return Boot.Race(Boot.RawGet, game, Target) end
    local Count, Ok, Body = #Boot.CdnHosts, false, nil
    for Step = 0, Count - 1 do
        local Index = (Boot.CdnIndex - 1 + Step) % Count + 1
        Ok, Body = Boot.Race(Boot.RawGet, game, "https://" .. Boot.CdnHosts[Index] .. Path)
        if Ok and type(Body) == "string" and #Body > 0 then
            if Index ~= Boot.CdnIndex then Boot.Print("jsDelivr host switched to " .. Boot.CdnHosts[Index]) end
            Boot.CdnIndex = Index
            return Ok, Body
        end
    end
    return Ok, Body
end

function Boot.Get(Url)
    local Target = Boot.Rewrite and Boot.ToCdn(Url) or Url
    local Name = Url:match("([^/]+)$") or Url
    local T0 = tick()
    Boot.Inflight[Url] = true
    local Ok, Body = Boot.GetCdn(Target)
    if (not Ok or type(Body) ~= "string" or #Body == 0) and Target ~= Url and string.sub(Target, 1, #Boot.MirrorRoot) ~= Boot.MirrorRoot then
        Boot.Print(string.format("%s: cdn failed after %.2fs, trying original", Name, tick() - T0))
        T0 = tick()
        Ok, Body = Boot.Race(Boot.RawGet, game, Url)
    end
    Boot.Inflight[Url] = nil
    if Ok and type(Body) == "string" and #Body > 0 then
        Boot.Print(string.format("downloaded %s (%d KB) in %.2fs", Target, math.floor(#Body / 1024), tick() - T0))
        return Body
    end
    Boot.Print(string.format("FAILED %s after %.2fs (%s)", Target, tick() - T0, tostring(Body)))
    error("download failed: " .. Url)
end

-- catch every HttpGet made while loading (components loading their own deps too)
do
    local Wrap = newcclosure or function(Function) return Function end
    local Ok, Original = pcall(hookfunction, Boot.RawGet, Wrap(function(Self, Url, ...)
        if not Boot.Rewrite or type(Url) ~= "string" then
            return Boot.RawGet(Self, Url, ...)
        end
        return Boot.Get(Url)
    end))
    if Ok and Original then
        Boot.RawGet = Original
        Boot.Print("HttpGet hook active (all loads go through jsDelivr + timing)")
    else
        Boot.Print("HttpGet hook unavailable, only main components are timed")
    end
end

-- game:HttpGet is a namecall, the function hook above does not see it: hook the namecall too
do
    local Wrap = newcclosure or function(Function) return Function end
    local Ok = pcall(function()
        local Old
        Old = hookmetamethod(game, "__namecall", Wrap(function(Self, ...)
            local Method = getnamecallmethod()
            if Method == "Kick" and Self == game:GetService("Players").LocalPlayer then
                -- diagnostics only: record who kicks us and with what message, then let it happen
                Boot.Print("KICK called with: " .. tostring((...)))
                Boot.Print(debug.traceback("kick source:", 2))
                local CopyNow = setclipboard or toclipboard
                if CopyNow then pcall(CopyNow, table.concat(Boot.Log, "\n")) end
            end
            if Boot.Rewrite and Self == game and (Method == "HttpGet" or Method == "HttpGetAsync") then
                local Url = ...
                if type(Url) == "string" then
                    return Boot.Get(Url)
                end
            end
            return Old(Self, ...)
        end))
    end)
    Boot.Print(Ok and "namecall hook active (game:HttpGet is timed and rerouted)" or "namecall hook unavailable")
end

-- executor request() calls: log host + time, reroute raw.githubusercontent GETs
for _, Name in {"request", "http_request"} do
    pcall(function()
        local Env = getgenv()
        local Original = Env[Name]
        if type(Original) ~= "function" then return end
        Env[Name] = function(Options)
            local Url = type(Options) == "table" and Options.Url
            local Host = type(Url) == "string" and (Url:match("^https?://([^/]+)") or Url) or "?"
            if type(Url) == "string" and string.find(Url, "discord.com/api/webhooks", 1, true) then
                -- privacy guard: no component gets to send your data to a webhook
                Boot.Print("blocked a Discord webhook request")
                return { Success = false, StatusCode = 0, StatusMessage = "blocked", Body = "", Headers = {} }
            end
            if Boot.Rewrite and type(Url) == "string" and string.upper(Options.Method or "GET") == "GET" then
                Options = table.clone(Options)
                Options.Url = Boot.ToCdn(Url)
            end
            local T0 = tick()
            Boot.Inflight[tostring(Url)] = true
            local Ok, Result = pcall(Original, Options)
            Boot.Inflight[tostring(Url)] = nil
            Boot.Print(string.format("%s %s in %.2fs", Name, tostring(Url), tick() - T0))
            if not Ok then error(Result, 0) end
            return Result
        end
    end)
end

function Boot.Fetch(Paths)
    local Results, Pending = {}, #Paths
    for Index, Path in Paths do
        task.spawn(function()
            local Ok, Body = pcall(Boot.Get, BaseUrl .. Path)
            Results[Index] = Ok and Body or false
            Pending -= 1
        end)
    end
    while Pending > 0 do task.wait() end
    for Index, Path in Paths do
        if not Results[Index] then error("fetch failed: " .. Path) end
    end
    return Results
end

function Boot.Run(Name, Source)
    local T0 = tick()
    local Done = false
    task.spawn(function()
        local Waited = 0
        while not Done do
            task.wait(10)
            Waited += 10
            if Done then break end
            local List = {}
            for Host in Boot.Inflight do List[#List + 1] = Host:match("^https?://([^/]+)") or Host end
            Boot.Print(string.format("still initializing %s (%ds), waiting on: %s", Name, Waited, #List > 0 and table.concat(List, ", ") or "unknown"))
        end
    end)
    local Result = loadstring(Source)()
    Done = true
    Boot.Print(string.format("initialized %s in %.2fs", Name, tick() - T0))
    return Result
end

Boot.Print("downloading components (parallel)...")
Boot.Sources = Boot.Fetch({
    "Components/Environment.luau",
    "Components/ESP.luau",
    "Components/16Notice.luau",
    "Components/Interface.luau",
})
Boot.Print("downloads done")

getgenv().Abysall = {
    Environment = Boot.Run("Environment", Boot.Sources[1]),
    ESPLibrary = Boot.Run("ESP", Boot.Sources[2]),
    ["16Notice"] = Boot.Run("16Notice", Boot.Sources[3]),
    Legit = true
}

local Abysall = getgenv().Abysall

local function CloneReference(Object)
    if Abysall and Abysall.Environment.cloneref then
        return Abysall.Environment.cloneref(Object)
    end
    return Object
end

local Services = setmetatable({}, {
    __index = function(Self, Name)
        return CloneReference(game:GetService(Name))
    end
})

if Abysall.Environment.writefile and Abysall.Environment.readfile then
    if not Abysall.Environment.isfile("Abysall/UserData.json") then
        local Data = {
            TotalExecutions = 0,
            UILibrary = "Obsidian"
        }

        Abysall.Environment.writefile(
            "Abysall/UserData.json",
            Services.HttpService:JSONEncode(Data)
        )
    end

    local UserData = Abysall.Environment.readfile("Abysall/UserData.json")
    local Decoded = Services.HttpService:JSONDecode(UserData)

    if not Decoded.TotalExecutions then
        Decoded.TotalExecutions = 0
    end

    Decoded.TotalExecutions = Decoded.TotalExecutions + 1

    if not Decoded.UILibrary then
        Decoded.UILibrary = "Obsidian"
    end

    Abysall.TotalExecutions = Decoded.TotalExecutions
    Abysall.UILibrary = Decoded.UILibrary

    Abysall.Environment.writefile(
        "Abysall/UserData.json",
        Services.HttpService:JSONEncode(Decoded)
    )
end

Abysall.Interface = Boot.Run("Interface", Boot.Sources[4])
-- Analytics removed: it sent username, user id, executor and HWID to a Discord webhook on every run.
-- Nothing in this script uses it, so a harmless stub stands in for anything that still asks for it.
Abysall.Analytics = setmetatable({}, { __index = function() return function() end end })
Boot.Print("components ready, building UI / hooking game...")


Abysall.SavePath = "Doors/Game"

local Library = Abysall.Interface.Library
local SaveManager = Abysall.Interface.SaveManager
local ThemeManager = Abysall.Interface.ThemeManager

local Toggles = Library.Toggles
local Options = Library.Options

local function CloneReference(Object)
	if Abysall and Abysall.Environment.cloneref then
		return Abysall.Environment.cloneref(Object)
	end
	return Object
end

local Services = setmetatable({}, {
	__index = function(Self, Name)
		return CloneReference(game:GetService(Name))
	end
})



-- archives and stairwell locals
local TimeShowerSourceLabel
local TimeShowerToken = 0
local TimeShowerConnection
local BypassDronesStampedeConnection
local HonchoCorrectBoxConnection
local HonchoAutoDepositConnection
local HonchoESPObjects = {}
local HonchoProcessedRooms = {}
local HonchoDepositCache = {}
local AntiClosetTrash_Connection
local AntiRansom_Connection
local ForgetMeNotConnection
local ForgetMeNotRunning = false
local ForgetMeNotProcessing = {}
local ForgetMeNotNotified = {}
local WaterBypassConnection
local WaterParts = {}
local AlmaConnection
local AntiScribbles_Connection
local DroneConnection
local DroneWalkedIntoParents = {}
local OrbitDroppedItemsConnection
local OrbitDroppedItemsAngle = 0
local OrbitDroppedItemsLastTeleport = 0
local OrbitDroppedItemsPauseUntil = 0
local droppedItemsIntervalRunning = false
local Connections = {}



local Globals = {}
local Connections = {}
local ESPConnections = {}
local Groupboxes = {}
local FakePrompts = {}
local Functions = {}
local PartProperties = {}

local Objects = {
	Prompts = {},
	Objectives = {},
	Doors = {},
	HidingSpots = {},
	Entities = {},
	SeekObstructions = {},
	Items = {},
	Chests = {},
	Currency = {},
	Ladders = {},
	Misc = {},
	Obstructions = {},
	EventTriggers = {},
	JumpscareModules = {},
	SeekHighlights = {},
	EyestalkHighlights = {},
	SeekNodes = {},
	SeekDuckBoards = {},
	SeekBridges = {},
	PathLights = {}
}

Globals.IncompatibleMessage = "Your executor doesn't support this feature."

Functions.CheckCompatability = function(Array)
	for _, Name in Array do
		if not Abysall.Environment[Name] then
			return false
		end
	end
	return true
end


-- DontGroup
local LocalPlayer = Services.Players.LocalPlayer



local PortraitName = "MirrorRig_Portrait_" .. LocalPlayer.Name


local Entities = {
	["Weaveling"] = {
		Alias = "Weaveling",
		NotifyMessage = { Title = "Weaveling has spawned", Body = "Try to grab it" }
	},
	["Creak-HALLOWEEN26"] = {
		Alias = "CreakHalloween",
		NotifyMessage = { Title = "Sir Abraham Creakstopher II spawned", Body = "He scary"}
	},
	["TV_Stand"] = {
		Alias = "Noise_TV",
		NotifyMessage = { Title = "Noise tv spawned.", Body = "Dont get near it" }
	},
	[PortraitName] = {
		Alias = "Portrait",
		NotifyMessage = { Title = "Portrait' has spawned.", Body = "Use him to duplicate items." }
	},
	["StemsEntity"] = {
	    Alias = 'Balls',
		NotifyMessage = { Title = "Balls", Body = "Balls."}
	},
	["NoiseModel"] = {
		Alias = 'Noise',
		NotifyMessage = { Title = "Entity 'Noise' has spawned.", Body = "Dont let it touch you." }
	},
	["Creak"] = {
		Alias = "Creak",
		NotifyMessage = { Title = "Entity 'Creak' has spawned.", Body = "Dont touch him." }
	},
	["DronesStampede"] = {
		Alias = "DronesStampede",
		NotifyMessage = { Title = "Entity 'Drones Stampede' has spawned.", Body = "Find a hiding spot." }
	},
	["TellerRig"] = {
		Alias = "Teller",
		NotifyMessage = { Title = "Entity 'Teller' has spawned.", Body = "Dont worry, hes only annoying." }
	},
	["Scribbles"] = {
		Alias = "Scribbles",
		NotifyMessage = { Title = "Entity 'Scribbles' has spawned.", Body = "Find a hiding spot." }
	},
	["BashMoving"] = {
		Alias = "Bash",
		NotifyMessage = { Title = "Entity 'Bash' has spawned.", Body = "Find a hiding spot."}
	},
	["RushMoving"] = {
		Alias = "Rush",
		NotifyMessage = { Title = "Entity 'Rush' has spawned.", Body = "Find a hiding spot." }
	},
	["AmbushMoving"] = {
		Alias = "Ambush",
		NotifyMessage = { Title = "Entity 'Ambush' has spawned.", Body = "Find a hiding spot." }
	},
	["Eyes"] = {
		Alias = "Eyes",
		NotifyMessage = { Title = "Entity 'Eyes' has spawned.", Body = "Avoid looking at it." }
	},
	["Lookman"] = {
		Alias = "Eyes",
		NotifyMessage = { Title = "Entity 'Eyes' has spawned.", Body = "Avoid looking at it." }
	},
	["BackdoorRush"] = {
		Alias = "Blitz",
		NotifyMessage = { Title = "Entity 'Blitz' has spawned.", Body = "Find a hiding spot." }
	},
	["BackdoorLookman"] = {
		Alias = "Lookman",
		NotifyMessage = { Title = "Entity 'Lookman' has spawned.", Body = "Avoid looking at its eyes." }
	},
	["Groundskeeper"] = {
		Alias = "Groundskeeper",
		NotifyMessage = { Title = "Entity 'Groundskeeper' has spawned.", Body = "Avoid stepping on the grass." }
	},
	["A60"] = {
		Alias = "A-60",
		NotifyMessage = { Title = "Entity 'A-60' has spawned.", Body = "Find a hiding spot." }
	},
	["A120"] = {
		Alias = "A-120",
		NotifyMessage = { Title = "Entity 'A-120' has spawned.", Body = "Find a hiding spot." }
	},
	["GloombatSwarm"] = {
		Alias = "Gloombat Swarm",
		NotifyMessage = { Title = "Entity 'Gloombat Swarm' has spawned.", Body = "Keep all light sources turned off." }
	},
	["GlitchRush"] = {
		Alias = "RNIUSHCG==",
		NotifyMessage = { Title = "Entity 'RNIUSHCG==' has spawned.", Body = "Find a hiding spot." }
	},
	["GlitchAmbush"] = {
		Alias = "AR0xMBUSH",
		NotifyMessage = { Title = "Entity 'AR0xMBUSH' has spawned.", Body = "Find a hiding spot." }
	},
	["MonumentEntity"] = {
		Alias = "Monument",
		NotifyMessage = { Title = "Entity 'Monument' has spawned.", Body = "It can't move while you are looking at it." }
	},
	["JeffTheKiller"] = {
		Alias = "Jeff the Killer",
		NotifyMessage = { Title = "Entity 'Jeff the Killer' has spawned.", Body = "Avoid touching him." }
	},
	["CustomEntity"] = {
		Alias = "Custom Entity",
		NotifyMessage = { Title = "Entity 'Custom Entity' has spawned.", Body = "Find a hiding spot." }
	},
	["FrozenAmbush"] = {
		Alias = "Frozen Ambush",
		NotifyMessage = { Title = "Entity 'Frozen Ambush' has spawned.", Body = "Find a hiding spot." }
	},
	["SallyMoving"] = {
		Alias = "Sally",
		NotifyMessage = { Title = "Entity 'Sally' has spawned.", Body = "Find her horse and rop it." }
	}
}

local EntityIcons = {
	["RushMoving"]      = "rbxassetid://10716032262",
	["AmbushMoving"]    = "rbxassetid://10110576663",
	["A60"]             = "rbxassetid://12571092295",
	["A120"]            = "rbxassetid://12711591665",
	["BackdoorRush"]    = "rbxassetid://16602023490",
	["Eyes"]            = "rbxassetid://10183704772",
	["Lookman"]         = "rbxassetid://10183704772",
	["BackdoorLookman"] = "rbxassetid://16764872677",
	["GloombatSwarm"]   = "rbxassetid://79221203116470",
	["Halt"]            = "rbxassetid://11331795398",
	["JeffTheKiller"]   = "rbxassetid://94479432156278",
	["GlitchRush"]      = "rbxassetid://73859273102919",
	["GlitchAmbush"]    = "rbxassetid://88369678433359",
	["SallyMoving"]     = "rbxassetid://10840888070",
	["MonumentEntity"]  = "rbxassetid://88933556873017",
	["Groundskeeper"]   = "rbxassetid://114991380115557"
}

local ItemNames = {
    ["AbrahamHat"]       = "Hat",
    ["LargeScrew"]       = "Screw",
    ["KeyJewelry"]       = "Jewerly Key",
    ["Leftovers"]        = "Lunch Box",
    ["Haybale"]          = "Haybale",
    ["WizardHat"]        = "Wizard Hat",
    ["CandyBasket"]      = "Candy Basket",
    ["BrokenHeadstone"]  = "Broken Headstone",
    ["GiantGummyworm"]   = "Giant Gummyworm",
    ["ChocolateCrate"]   = "Crate of Chocolate",
    ["CandyBucket"]      = "Candy Bucket",
    ["LargeCandyBag"]    = "Large Candy Bag",
    ["SmallCauldron"]    = "Small Cauldron",
    ["ObjectScanner"]    = "Scanner",
    ["Drive"]            = "Drive",
	["DinkyLamp"]         = "Lamp",
	["BottleCrate"]       = "18+ Bottles",
	["GweenSodaPack"]     = "Gween Soda Pack",
	["BrokenMonitor"]     = "Broken Monitor",
	["JerryCan"]          = "Jerry Can",
 	["SallyToyObtain"]    = "Sally Toy",
	["Leftovers"]         = "Lunch Box",
	["HoneyPot"]          = "Honey Pot",
	["FihFlakes"]         = "Fih Food",
	["SecretCD"]          = "CD Disc",
	["Pizza"]             = "Pizza",
	["PaperPlanePickup"]  = "Paper Plane",
	["Lighter"]           = "Lighter",
	["Flashlight"]        = "Flashlight",
	["Lockpick"]          = "Lockpicks",
	["Vitamins"]          = "Vitamins",
	["Bandage"]           = "Bandage",
	["StarVial"]          = "Starlight Vial",
	["StarBottle"]        = "Starlight Bottle",
	["StarJug"]           = "Starlight Barrel",
	["Shakelight"]        = "Gummy Flashlight",
	["Straplight"]        = "Straplight",
	["Bulklight"]         = "Spotlight",
	["Battery"]           = "Battery",
	["Candle"]            = "Candle",
	["Crucifix"]          = "Crucifix",
	["CrucifixWall"]      = "Crucifix",
	["Glowsticks"]        = "Glowstick",
	["SkeletonKey"]       = "Skeleton Key",
	["Candy"]             = "Candy",
	["ShieldMini"]        = "Mini Shield Potion",
	["ShieldBig"]         = "Big Shield Potion",
	["BandagePack"]       = "Bandage Pack",
	["BatteryPack"]       = "Battery Pack",
	["RiftCandle"]        = "Moonlight Candle",
	["LaserPointer"]      = "Laser Pointer",
	["HolyGrenade"]       = "Holy Hand Grenade",
	["Shears"]            = "Shears",
	["Smoothie"]          = "Smoothie",
	["Cheese"]            = "Cheese",
	["Bread"]             = "Bread",
	["AlarmClock"]        = "Alarm Clock",
	["RiftSmoothie"]      = "Moonlight Smoothie",
	["GweenSoda"]         = "Gween Soda",
	["GlitchCube"]        = "Glitch Fragment",
	["Scanner"]           = "Tablet",
	["Bomb"]              = "Bomb",
	["Knockbomb"]         = "Knockbomb",
	["Nanner"]            = "Nanner",
	["BigBomb"]           = "Big Bomb",
	["SnakeBox"]          = "Hiding Box",
	["GoldGun"]           = "Golden Gun",
	["StopSign"]          = "Stop Sign",
	["TipJar"]            = "Tip Jar",
	["Lantern"]           = "Lantern",
	["IronKey"]           = "Iron Key",
	["LotusPetal"]        = "Lotus Petal",
	["Compass"]           = "Compass",
	["LotusPetalPickup"]  = "Lotus Petal",
	["LanternLitItem"]    = "Lantern",
	["KeyIron"]           = "Iron Key",
	["IronKeyForCrypt"]   = "Iron Key",
	["LotusHolder"]       = "Lotus Petal",
	["Multitool"]         = "Multitool",
	["RiftJar"]           = "Rift Jar",
	["AloeVera"]          = "Aloe Vera",
	["Donut"]             = "Donut",
	["Lotus"]             = "Lotus",
	["BoxingGloves"]      = "Boxing Gloves",
	["CoinRoll"]          = "Coin Roll",
	["CoinRollPickup"]    = "Coin Roll",
	["CoinRollObtain"]    = "Coin Roll",
	["Coin Roll"]         = "Coin Roll",
	["Coin_Roll"]         = "Coin Roll"
}

local CutsceneNames = {
    "Figure",
    "FigureEnd",
    "FigureHotelEnd",
    "FigureHotelFire",
    "SeekIntroFools",
    "SeekIntroHotel",
    "SeekIntroMines",
    "SeekIntroMines2",
    "SerewSeekDrain",
    "SewerSeekLower",
    "GrumbleNestEnd",
    "EyestalkIntro",
}

local Character
local Humanoid
local RootPart

local Collision
local CollisionClone
local CollisionPart
local CollisionPartClone

local Camera = workspace:FindFirstChild("Camera")

local RemotesFolder   = Services.ReplicatedStorage:FindFirstChild("RemotesFolder")
local LiveModifiers   = Services.ReplicatedStorage:FindFirstChild("LiveModifiers")
local FloorReplicated = Services.ReplicatedStorage:FindFirstChild("FloorReplicated")

local CurrentRooms    = Services.Workspace:FindFirstChild("CurrentRooms")

local Drops           = Services.Workspace:FindFirstChild("Drops")
local GameData        = Services.ReplicatedStorage:WaitForChild("GameData")
local Floor           = GameData:WaitForChild("Floor").Value
local LatestRoom      = GameData:WaitForChild("LatestRoom")
local FinishedLoadingRoom = GameData:FindFirstChild("FinishedLoadingRoom")
local RunService = game:GetService("RunService")

if FinishedLoadingRoom then
	FinishedLoadingRoom:Destroy()
end

local function GetHiddenContainer()
	if Functions.CheckCompatability({"gethui"}) then
		return Abysall.Environment.gethui()
	end
	return Services.CoreGui
end

local NotificationLibrary = {
	LiveNotifications = 0,
	Notifications = 1
}

local Container = Instance.new("ScreenGui")
Container.Name = Abysall.ESPLibrary:GenerateRandomString()
Container.Parent = GetHiddenContainer()
Container.DisplayOrder = 32767
Container.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

if not Library.Scheme then
	Library.Scheme = setmetatable({}, {
		__index = function(Self, Name)
			return Library[Name]
		end
	})
end

-- Language is chosen before the main window is built so tab names are stable for the whole session.
do
	local HttpService = Services.HttpService
	local Env = getgenv()
	local function Fs(Name)
		return Env[Name] or (Abysall.Environment and Abysall.Environment[Name])
	end
	local function EnsureFolder()
		local MakeFolder, IsFolder = Fs("makefolder"), Fs("isfolder")
		if not MakeFolder then return end
		if IsFolder then
			local Ok, Exists = pcall(IsFolder, "AMR")
			if Ok and Exists then return end
		end
		pcall(MakeFolder, "AMR")
	end

	function Boot.LoadJSON(Name)
		local ReadFile, IsFile = Fs("readfile"), Fs("isfile")
		if not ReadFile then return nil end
		local Path = "AMR/" .. Name
		if IsFile then
			local Ok, Exists = pcall(IsFile, Path)
			if Ok and not Exists then return nil end
		end
		local Ok, Text = pcall(ReadFile, Path)
		if not Ok or type(Text) ~= "string" or Text == "" then return nil end
		local Decoded, Data = pcall(HttpService.JSONDecode, HttpService, Text)
		return Decoded and Data or nil
	end

	function Boot.SaveJSON(Name, Data)
		local WriteFile = Fs("writefile")
		if not WriteFile then return false end
		EnsureFolder()
		local Encoded, Text = pcall(HttpService.JSONEncode, HttpService, Data)
		if not Encoded then return false end
		return pcall(WriteFile, "AMR/" .. Name, Text)
	end

	local Packs = {
		en = { picker = "Choose language", search = "Search country or language", select = "Select", sure = "Are you sure?", confirm = "Confirm", back = "Back", close = "Close", current = "Current language", tab_general = "General", tab_exploits = "Exploits", tab_visuals = "Visuals", tab_floors = "Floors", tab_archives = "Archives", tab_stairwell = "Stairwell", tab_halloween = "New - Halloween", pet = "Tamagochi" },
		ru = { picker = "Выберите язык", search = "Поиск страны или языка", select = "Выбрать", sure = "Вы уверены?", confirm = "Подтвердить", back = "Назад", close = "Закрыть", current = "Текущий язык", tab_general = "Основное", tab_exploits = "Эксплойты", tab_visuals = "Визуал", tab_floors = "Этажи", tab_archives = "Архивы", tab_stairwell = "Лестница", tab_halloween = "Новое - Хэллоуин", pet = "Пиздёныш" },
		es = { picker = "Elige idioma", search = "Buscar país o idioma", select = "Elegir", sure = "¿Estás seguro?", confirm = "Confirmar", back = "Atrás", close = "Cerrar", current = "Idioma actual", tab_general = "General", tab_exploits = "Trucos", tab_visuals = "Visuales", tab_floors = "Pisos", tab_archives = "Archivos", tab_stairwell = "Escaleras", pet = "Tamagochi" },
		de = { picker = "Sprache wählen", search = "Land oder Sprache suchen", select = "Auswählen", sure = "Bist du sicher?", confirm = "Bestätigen", back = "Zurück", close = "Schließen", current = "Aktuelle Sprache", tab_general = "Allgemein", tab_exploits = "Exploits", tab_visuals = "Anzeige", tab_floors = "Etagen", tab_archives = "Archive", tab_stairwell = "Treppenhaus", pet = "Tamagochi" },
		fr = { picker = "Choisir la langue", search = "Rechercher un pays ou une langue", select = "Choisir", sure = "Êtes-vous sûr ?", confirm = "Confirmer", back = "Retour", close = "Fermer", current = "Langue actuelle", tab_general = "Général", tab_exploits = "Exploits", tab_visuals = "Visuels", tab_floors = "Étages", tab_archives = "Archives", tab_stairwell = "Escalier", pet = "Tamagochi" },
		it = { picker = "Scegli la lingua", search = "Cerca paese o lingua", select = "Seleziona", sure = "Sei sicuro?", confirm = "Conferma", back = "Indietro", close = "Chiudi", current = "Lingua attuale", tab_general = "Generale", tab_exploits = "Exploit", tab_visuals = "Grafica", tab_floors = "Piani", tab_archives = "Archivi", tab_stairwell = "Scale", pet = "Tamagochi" },
		pt = { picker = "Escolha o idioma", search = "Buscar país ou idioma", select = "Selecionar", sure = "Tem certeza?", confirm = "Confirmar", back = "Voltar", close = "Fechar", current = "Idioma atual", tab_general = "Geral", tab_exploits = "Exploits", tab_visuals = "Visuais", tab_floors = "Andares", tab_archives = "Arquivos", tab_stairwell = "Escadaria", pet = "Tamagochi" },
		pl = { picker = "Wybierz język", search = "Szukaj kraju lub języka", select = "Wybierz", sure = "Czy na pewno?", confirm = "Potwierdź", back = "Wstecz", close = "Zamknij", current = "Obecny język", tab_general = "Ogólne", tab_exploits = "Exploity", tab_visuals = "Wizualne", tab_floors = "Piętra", tab_archives = "Archiwa", tab_stairwell = "Klatka schodowa", pet = "Tamagochi" },
		tr = { picker = "Dil seç", search = "Ülke veya dil ara", select = "Seç", sure = "Emin misiniz?", confirm = "Onayla", back = "Geri", close = "Kapat", current = "Geçerli dil", tab_general = "Genel", tab_exploits = "Exploitler", tab_visuals = "Görsel", tab_floors = "Katlar", tab_archives = "Arşivler", tab_stairwell = "Merdiven", pet = "Tamagochi" },
		uk = { picker = "Оберіть мову", search = "Пошук країни або мови", select = "Обрати", sure = "Ви впевнені?", confirm = "Підтвердити", back = "Назад", close = "Закрити", current = "Поточна мова", tab_general = "Основне", tab_exploits = "Експлойти", tab_visuals = "Візуал", tab_floors = "Поверхи", tab_archives = "Архіви", tab_stairwell = "Сходи", pet = "Tamagochi" },
		zh = { picker = "选择语言", search = "搜索国家或语言", select = "选择", sure = "你确定吗？", confirm = "确认", back = "返回", close = "关闭", current = "当前语言", tab_general = "常规", tab_exploits = "功能", tab_visuals = "视觉", tab_floors = "楼层", tab_archives = "档案馆", tab_stairwell = "楼梯间", pet = "Tamagochi" },
		ja = { picker = "言語を選択", search = "国または言語を検索", select = "選択", sure = "よろしいですか？", confirm = "確認", back = "戻る", close = "閉じる", current = "現在の言語", tab_general = "一般", tab_exploits = "機能", tab_visuals = "表示", tab_floors = "フロア", tab_archives = "アーカイブ", tab_stairwell = "階段", pet = "Tamagochi" },
		ko = { picker = "언어 선택", search = "국가 또는 언어 검색", select = "선택", sure = "확실합니까?", confirm = "확인", back = "뒤로", close = "닫기", current = "현재 언어", tab_general = "일반", tab_exploits = "기능", tab_visuals = "시각", tab_floors = "층", tab_archives = "기록 보관소", tab_stairwell = "계단", pet = "Tamagochi" },
		ar = { picker = "اختر اللغة", search = "ابحث عن دولة أو لغة", select = "اختيار", sure = "هل أنت متأكد؟", confirm = "تأكيد", back = "رجوع", close = "إغلاق", current = "اللغة الحالية", tab_general = "عام", tab_exploits = "الأدوات", tab_visuals = "المرئيات", tab_floors = "الطوابق", tab_archives = "الأرشيف", tab_stairwell = "الدرج", pet = "Tamagochi" },
		hi = { picker = "भाषा चुनें", search = "देश या भाषा खोजें", select = "चुनें", sure = "क्या आप निश्चित हैं?", confirm = "पुष्टि करें", back = "वापस", close = "बंद करें", current = "वर्तमान भाषा", tab_general = "सामान्य", tab_exploits = "उपकरण", tab_visuals = "दृश्य", tab_floors = "मंजिलें", tab_archives = "अभिलेख", tab_stairwell = "सीढ़ियाँ", pet = "Tamagochi" },
		id = { picker = "Pilih bahasa", search = "Cari negara atau bahasa", select = "Pilih", sure = "Apakah Anda yakin?", confirm = "Konfirmasi", back = "Kembali", close = "Tutup", current = "Bahasa saat ini", tab_general = "Umum", tab_exploits = "Eksploit", tab_visuals = "Visual", tab_floors = "Lantai", tab_archives = "Arsip", tab_stairwell = "Tangga", pet = "Tamagochi" },
		vi = { picker = "Chọn ngôn ngữ", search = "Tìm quốc gia hoặc ngôn ngữ", select = "Chọn", sure = "Bạn có chắc không?", confirm = "Xác nhận", back = "Quay lại", close = "Đóng", current = "Ngôn ngữ hiện tại", tab_general = "Chung", tab_exploits = "Công cụ", tab_visuals = "Hình ảnh", tab_floors = "Tầng", tab_archives = "Lưu trữ", tab_stairwell = "Cầu thang", pet = "Tamagochi" },
		th = { picker = "เลือกภาษา", search = "ค้นหาประเทศหรือภาษา", select = "เลือก", sure = "คุณแน่ใจหรือไม่?", confirm = "ยืนยัน", back = "กลับ", close = "ปิด", current = "ภาษาปัจจุบัน", tab_general = "ทั่วไป", tab_exploits = "เครื่องมือ", tab_visuals = "ภาพ", tab_floors = "ชั้น", tab_archives = "เอกสาร", tab_stairwell = "บันได", pet = "Tamagochi" },
		nl = { picker = "Kies taal", search = "Zoek land of taal", select = "Selecteren", sure = "Weet je het zeker?", confirm = "Bevestigen", back = "Terug", close = "Sluiten", current = "Huidige taal", tab_general = "Algemeen", tab_exploits = "Exploits", tab_visuals = "Beeld", tab_floors = "Verdiepingen", tab_archives = "Archieven", tab_stairwell = "Trappenhuis", pet = "Tamagochi" },
		sv = { picker = "Välj språk", search = "Sök land eller språk", select = "Välj", sure = "Är du säker?", confirm = "Bekräfta", back = "Tillbaka", close = "Stäng", current = "Nuvarande språk", tab_general = "Allmänt", tab_exploits = "Verktyg", tab_visuals = "Visuellt", tab_floors = "Våningar", tab_archives = "Arkiv", tab_stairwell = "Trapphus", pet = "Tamagochi" },
		fi = { picker = "Valitse kieli", search = "Hae maata tai kieltä", select = "Valitse", sure = "Oletko varma?", confirm = "Vahvista", back = "Takaisin", close = "Sulje", current = "Nykyinen kieli", tab_general = "Yleiset", tab_exploits = "Työkalut", tab_visuals = "Näkymä", tab_floors = "Kerrokset", tab_archives = "Arkistot", tab_stairwell = "Portaikko", pet = "Tamagochi" },
		cs = { picker = "Vyberte jazyk", search = "Hledat zemi nebo jazyk", select = "Vybrat", sure = "Jste si jisti?", confirm = "Potvrdit", back = "Zpět", close = "Zavřít", current = "Aktuální jazyk", tab_general = "Obecné", tab_exploits = "Nástroje", tab_visuals = "Vzhled", tab_floors = "Patra", tab_archives = "Archivy", tab_stairwell = "Schodiště", pet = "Tamagochi" },
		ro = { picker = "Alege limba", search = "Caută țara sau limba", select = "Selectează", sure = "Ești sigur?", confirm = "Confirmă", back = "Înapoi", close = "Închide", current = "Limba curentă", tab_general = "General", tab_exploits = "Instrumente", tab_visuals = "Vizual", tab_floors = "Etaje", tab_archives = "Arhive", tab_stairwell = "Scări", pet = "Tamagochi" },
		hu = { picker = "Nyelv választása", search = "Ország vagy nyelv keresése", select = "Kiválasztás", sure = "Biztos vagy benne?", confirm = "Megerősítés", back = "Vissza", close = "Bezárás", current = "Jelenlegi nyelv", tab_general = "Általános", tab_exploits = "Eszközök", tab_visuals = "Vizuális", tab_floors = "Emeletek", tab_archives = "Archívum", tab_stairwell = "Lépcsőház", pet = "Tamagochi" },
		el = { picker = "Επιλέξτε γλώσσα", search = "Αναζήτηση χώρας ή γλώσσας", select = "Επιλογή", sure = "Είστε σίγουροι;", confirm = "Επιβεβαίωση", back = "Πίσω", close = "Κλείσιμο", current = "Τρέχουσα γλώσσα", tab_general = "Γενικά", tab_exploits = "Εργαλεία", tab_visuals = "Οπτικά", tab_floors = "Όροφοι", tab_archives = "Αρχεία", tab_stairwell = "Σκάλα", pet = "Tamagochi" },
		he = { picker = "בחירת שפה", search = "חיפוש מדינה או שפה", select = "בחירה", sure = "האם אתה בטוח?", confirm = "אישור", back = "חזרה", close = "סגירה", current = "שפה נוכחית", tab_general = "כללי", tab_exploits = "כלים", tab_visuals = "חזותי", tab_floors = "קומות", tab_archives = "ארכיון", tab_stairwell = "חדר מדרגות", pet = "Tamagochi" },
	}
	local Countries = {
		{ "US", "en", "United States", "English" }, { "GB", "en", "United Kingdom", "English" }, { "CA", "en", "Canada", "English" }, { "AU", "en", "Australia", "English" }, { "NZ", "en", "New Zealand", "English" },
		{ "RU", "ru", "Россия", "Русский" }, { "BY", "ru", "Беларусь", "Русский" }, { "KZ", "ru", "Казахстан", "Русский" }, { "UA", "uk", "Україна", "Українська" },
		{ "ES", "es", "España", "Español" }, { "MX", "es", "México", "Español" }, { "AR", "es", "Argentina", "Español" }, { "CL", "es", "Chile", "Español" }, { "CO", "es", "Colombia", "Español" }, { "PE", "es", "Perú", "Español" }, { "VE", "es", "Venezuela", "Español" },
		{ "DE", "de", "Deutschland", "Deutsch" }, { "AT", "de", "Österreich", "Deutsch" }, { "CH", "de", "Schweiz", "Deutsch" },
		{ "FR", "fr", "France", "Français" }, { "BE", "fr", "Belgique", "Français" }, { "CA", "fr", "Canada", "Français" },
		{ "IT", "it", "Italia", "Italiano" }, { "SM", "it", "San Marino", "Italiano" },
		{ "BR", "pt", "Brasil", "Português" }, { "PT", "pt", "Portugal", "Português" }, { "AO", "pt", "Angola", "Português" }, { "MZ", "pt", "Moçambique", "Português" },
		{ "PL", "pl", "Polska", "Polski" }, { "TR", "tr", "Türkiye", "Türkçe" }, { "CY", "tr", "Kıbrıs", "Türkçe" },
		{ "CN", "zh", "中国", "简体中文" }, { "TW", "zh", "台灣", "繁體中文" }, { "HK", "zh", "香港", "中文" }, { "SG", "zh", "Singapore", "中文" },
		{ "JP", "ja", "日本", "日本語" }, { "KR", "ko", "대한민국", "한국어" },
		{ "SA", "ar", "السعودية", "العربية" }, { "AE", "ar", "الإمارات", "العربية" }, { "EG", "ar", "مصر", "العربية" }, { "MA", "ar", "المغرب", "العربية" }, { "DZ", "ar", "الجزائر", "العربية" }, { "IQ", "ar", "العراق", "العربية" },
		{ "IN", "hi", "भारत", "हिन्दी" }, { "NP", "hi", "नेपाल", "हिन्दी" },
		{ "ID", "id", "Indonesia", "Bahasa Indonesia" }, { "MY", "id", "Malaysia", "Bahasa Melayu" },
		{ "VN", "vi", "Việt Nam", "Tiếng Việt" }, { "TH", "th", "ประเทศไทย", "ภาษาไทย" },
		{ "NL", "nl", "Nederland", "Nederlands" }, { "BE", "nl", "België", "Nederlands" },
		{ "SE", "sv", "Sverige", "Svenska" }, { "FI", "fi", "Suomi", "Suomi" }, { "CZ", "cs", "Česko", "Čeština" }, { "SK", "cs", "Slovensko", "Čeština" },
		{ "RO", "ro", "România", "Română" }, { "MD", "ro", "Moldova", "Română" }, { "HU", "hu", "Magyarország", "Magyar" },
		{ "GR", "el", "Ελλάδα", "Ελληνικά" }, { "CY", "el", "Κύπρος", "Ελληνικά" }, { "IL", "he", "ישראל", "עברית" },
		{ "NO", "sv", "Norge", "Norsk fallback" }, { "DK", "sv", "Danmark", "Dansk fallback" }, { "IS", "en", "Ísland", "English fallback" },
		{ "IE", "en", "Ireland", "English" }, { "ZA", "en", "South Africa", "English" }, { "PH", "en", "Philippines", "English" }, { "PK", "en", "Pakistan", "English" }, { "BD", "en", "Bangladesh", "English" },
	}

	Abysall.Localization = { Code = "en", Country = "US", Packs = Packs }
	local function SetLanguage(Code, Country)
		if not Packs[Code] then Code = "en" end
		Abysall.Localization.Code = Code
		Abysall.Localization.Country = Country or "US"
	end
	function Boot.T(Key, Fallback)
		local Pack = Packs[Abysall.Localization.Code] or Packs.en
		return Pack[Key] or Packs.en[Key] or Fallback or Key
	end
	Abysall.Localization.T = Boot.T

	function Boot.OpenLanguagePicker(ChangeMode)
		if Boot.LanguagePickerOpen then return nil end
		Boot.LanguagePickerOpen = true
		local Result = nil
		local Accent = Library.Scheme.AccentColor or Color3.fromRGB(170, 85, 255)
		local Background = Library.Scheme.BackgroundColor or Color3.fromRGB(18, 18, 24)
		local Main = Library.Scheme.MainColor or Color3.fromRGB(28, 28, 36)
		local FontColor = Library.Scheme.FontColor or Color3.new(1, 1, 1)
		local function Make(Class, Props, Parent)
			local Object = Instance.new(Class)
			for Key, Value in Props do Object[Key] = Value end
			Object.Parent = Parent
			return Object
		end
		local function Corner(Object, Radius)
			Make("UICorner", { CornerRadius = UDim.new(0, Radius or 8) }, Object)
		end

		local Gui = Make("ScreenGui", { Name = "AMRLanguagePicker", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 32766, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, GetHiddenContainer())
		Make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.2, BorderSizePixel = 0, Active = true }, Gui)
		local Panel = Make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.9, 0, 0.86, 0), BackgroundColor3 = Background, BorderSizePixel = 0 }, Gui)
		Corner(Panel, 12)
		Make("UISizeConstraint", { MinSize = Vector2.new(300, 400), MaxSize = Vector2.new(560, 650) }, Panel)
		local Title = Make("TextLabel", { Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -72, 0, 34), BackgroundTransparency = 1, Text = Boot.T("picker"), TextColor3 = FontColor, Font = Enum.Font.GothamBold, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left }, Panel)
		if ChangeMode then
			local Close = Make("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(36, 34), BackgroundColor3 = Main, Text = "×", TextColor3 = FontColor, Font = Enum.Font.GothamBold, TextSize = 24, BorderSizePixel = 0 }, Panel)
			Corner(Close, 8)
			Close.Activated:Connect(function() Result = false Gui:Destroy() end)
		end
		local Search = Make("TextBox", { Position = UDim2.new(0, 16, 0, 56), Size = UDim2.new(1, -32, 0, 38), BackgroundColor3 = Main, Text = "", PlaceholderText = Boot.T("search"), PlaceholderColor3 = Color3.fromRGB(150, 150, 160), TextColor3 = FontColor, Font = Enum.Font.Gotham, TextSize = 14, ClearTextOnFocus = false, BorderSizePixel = 0 }, Panel)
		Corner(Search, 8)
		local List = Make("ScrollingFrame", { Position = UDim2.new(0, 16, 0, 104), Size = UDim2.new(1, -32, 1, -164), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = Accent, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, Panel)
		Make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, List)
		local Select = Make("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -32, 0, 42), BackgroundColor3 = Accent, BackgroundTransparency = 0.55, Text = Boot.T("select"), TextColor3 = FontColor, Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = false, BorderSizePixel = 0 }, Panel)
		Corner(Select, 9)

		local Selected, SelectedButton
		local Rows = {}
		for Index, Entry in Countries do
			local Row = Make("TextButton", { LayoutOrder = Index, Size = UDim2.new(1, -6, 0, 44), BackgroundColor3 = Main, BackgroundTransparency = 0.18, Text = "", AutoButtonColor = false, BorderSizePixel = 0 }, List)
			Corner(Row, 8)
			local Stroke = Make("UIStroke", { Color = Accent, Thickness = 1, Transparency = 1 }, Row)
			Make("TextLabel", { Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(38, 30), BackgroundColor3 = Accent, BackgroundTransparency = 0.25, Text = Entry[1], TextColor3 = FontColor, Font = Enum.Font.GothamBold, TextSize = 13, BorderSizePixel = 0 }, Row)
			Make("TextLabel", { Position = UDim2.fromOffset(55, 0), Size = UDim2.new(1, -62, 1, 0), BackgroundTransparency = 1, Text = Entry[3] .. "  ·  " .. Entry[4], TextColor3 = FontColor, Font = Enum.Font.Gotham, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left }, Row)
			local RowData = { Button = Row, Entry = Entry, Stroke = Stroke, Search = string.lower(Entry[1] .. " " .. Entry[2] .. " " .. Entry[3] .. " " .. Entry[4]) }
			Rows[#Rows + 1] = RowData
			Row.Activated:Connect(function()
				if SelectedButton then SelectedButton.Stroke.Transparency = 1 end
				Selected, SelectedButton = Entry, RowData
				Stroke.Transparency = 0
				Select.BackgroundTransparency = 0
				Select.AutoButtonColor = true
			end)
		end
		Search:GetPropertyChangedSignal("Text"):Connect(function()
			local Query = string.lower(Search.Text)
			for _, Row in Rows do Row.Button.Visible = Query == "" or string.find(Row.Search, Query, 1, true) ~= nil end
		end)

		local ConfirmPanel = Make("Frame", { Position = UDim2.new(0, 16, 0, 56), Size = UDim2.new(1, -32, 1, -72), BackgroundTransparency = 1, Visible = false }, Panel)
		local Question = Make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.new(1, -20, 0, 80), BackgroundTransparency = 1, Text = "", TextColor3 = FontColor, Font = Enum.Font.GothamBold, TextSize = 24, TextWrapped = true }, ConfirmPanel)
		local Confirm = Make("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -58), Size = UDim2.new(1, -20, 0, 42), BackgroundColor3 = Accent, TextColor3 = FontColor, Font = Enum.Font.GothamBold, TextSize = 16, BorderSizePixel = 0 }, ConfirmPanel)
		Corner(Confirm, 9)
		local Back = Make("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -20, 0, 38), BackgroundColor3 = Main, TextColor3 = FontColor, Font = Enum.Font.Gotham, TextSize = 14, BorderSizePixel = 0 }, ConfirmPanel)
		Corner(Back, 9)
		local Pending
		Select.Activated:Connect(function()
			if not Selected then return end
			Pending = Selected
			local Pack = Packs[Pending[2]] or Packs.en
			Question.Text = (Pack.sure or Packs.en.sure) .. "\n" .. Pending[3] .. " · " .. Pending[4]
			Confirm.Text = Pack.confirm or Packs.en.confirm
			Back.Text = Pack.back or Packs.en.back
			Title.Text = Pack.picker or Packs.en.picker
			Search.Visible, List.Visible, Select.Visible, ConfirmPanel.Visible = false, false, false, true
		end)
		Back.Activated:Connect(function()
			Pending = nil
			Title.Text = Boot.T("picker")
			Search.Visible, List.Visible, Select.Visible, ConfirmPanel.Visible = true, true, true, false
		end)
		Confirm.Activated:Connect(function()
			if not Pending then return end
			SetLanguage(Pending[2], Pending[1])
			Boot.LanguagePersisted = Boot.SaveJSON("Language.json", { version = 1, country = Pending[1], language = Pending[2] })
			Result = Pending
			Gui:Destroy()
		end)
		while Result == nil and Gui.Parent do task.wait() end
		Boot.LanguagePickerOpen = false
		return Result
	end

	local Saved = Boot.LoadJSON("Language.json")
	if type(Saved) == "table" and Packs[Saved.language] then
		SetLanguage(Saved.language, Saved.country)
	else
		Boot.OpenLanguagePicker(false)
	end
end

function NotificationLibrary:Notify(TitleText, Desc, Delay)
	task.spawn(function()
		local Notification = Instance.new("Frame")
		local Line = Instance.new("Frame")
		local Warning = Instance.new("ImageLabel")
		local UICorner = Instance.new("UICorner")
		local UICorner2 = Instance.new("UICorner")
		local Title = Instance.new("TextLabel")
		local Description = Instance.new("TextLabel")

		Notification.Name = "Notification"
		Notification.Parent = Container
		Notification.BackgroundColor3 = Library.Scheme.BackgroundColor
		Notification.BackgroundTransparency = 0.4
		Notification.BorderSizePixel = 0
		Notification.Position = UDim2.new(1, 5, 0, 60 + (60 * NotificationLibrary.LiveNotifications))
		Notification.Size = UDim2.new(0, 420, 0, 50)
		Notification:SetAttribute("ID", NotificationLibrary.Notifications)
		Notification:SetAttribute("CurrentPosition", Notification.Position)

		Line.Name = "Line"
		Line.Parent = Notification
		Line.BackgroundColor3 = Library.Scheme.AccentColor
		Line.BorderSizePixel = 0
		Line.Position = UDim2.new(0, 0, 1, -3)
		Line.Size = UDim2.new(0, 0, 0, 3)

		Warning.Name = "Warning"
		Warning.Parent = Notification
		Warning.BackgroundTransparency = 1
		Warning.Position = UDim2.new(0, 10, 0, 5)
		Warning.Size = UDim2.new(0, 40, 0, 40)
		Warning.Image = "rbxassetid://3944668821"
		Warning.ImageColor3 = Library.Scheme.AccentColor
		Warning.ScaleType = Enum.ScaleType.Fit

		UICorner.CornerRadius = UDim.new(0, 20)
		UICorner.Parent = Warning

		UICorner2.CornerRadius = UDim.new(0, 4)
		UICorner2.Parent = Notification

		Title.Name = "Title"
		Title.Parent = Notification
		Title.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Title.BackgroundTransparency = 1
		Title.Position = UDim2.new(0, 60, 0.155, 0)
		Title.Size = UDim2.new(0, 205, 0, 15)
		Title.Text = TitleText or "..."
		Title.TextColor3 = Library.Scheme.FontColor
		Title.TextSize = 10
		Title.TextStrokeTransparency = 0.75
		Title.TextXAlignment = Enum.TextXAlignment.Left

		Description.Name = "Description"
		Description.Parent = Notification
		Description.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Description.BackgroundTransparency = 1
		Description.Position = UDim2.new(0, 60, 0.483, 0)
		Description.Size = UDim2.new(0, 205, 0, 18)
		Description.Text = Desc or "..."
		Description.TextColor3 = Library.Scheme.FontColor
		Description.TextTransparency = 0.1
		Description.TextSize = 10
		Description.TextStrokeTransparency = 0.75
		Description.TextXAlignment = Enum.TextXAlignment.Left

		NotificationLibrary.LiveNotifications += 1
		NotificationLibrary.Notifications += 1

		Services.TweenService:Create(
			Notification,
			TweenInfo.new(1, Enum.EasingStyle.Exponential),
			{ Position = UDim2.new(1, -370, 0, Notification.Position.Y.Offset) }
		):Play()

		task.wait(0.25)
		if typeof(Delay) == "Instance" then
			Delay.Destroying:Wait()
		else
			Services.TweenService:Create(
				Line,
				TweenInfo.new(Delay - 0.25, Enum.EasingStyle.Linear),
				{ Size = UDim2.new(0, 400, 0, 3) }
			):Play()
			task.wait(Delay - 0.25)
		end

		Notification:SetAttribute("Destroying", true)

		Services.TweenService:Create(
			Notification,
			TweenInfo.new(0.75, Enum.EasingStyle.Exponential, Enum.EasingDirection.In),
			{ Position = UDim2.new(1, 5, 0, Notification.Position.Y.Offset) }
		):Play()

		NotificationLibrary.LiveNotifications -= 1

		local NotifId = Notification:GetAttribute("ID")
		local NotifY = Notification:GetAttribute("CurrentPosition").Y.Offset

		for _, Object in Container:GetChildren() do
			if Object.Name == "Notification"
				and Object:GetAttribute("ID")
				and Object:GetAttribute("ID") > NotifId
				and Object:GetAttribute("Destroying") ~= true
				and Object.Position.Y.Offset ~= 60
			then
				local NewY = Object:GetAttribute("CurrentPosition").Y.Offset - 60
				Object:SetAttribute("CurrentPosition", UDim2.new(1, -450, 0, NewY))
				Services.TweenService:Create(
					Object,
					TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut),
					{ Position = UDim2.new(1, -370, 0, NewY) }
				):Play()
			end
		end

		task.wait(0.75)
		Notification:Destroy()
	end)
end

Globals.DoorsNotify = function(NotifyOptions)
	local function PlaySound(Parent, SoundId, Volume)
		local Sound = Instance.new("Sound")
		Sound.SoundId = SoundId
		Sound.Volume = Volume or 1
		Sound.Parent = Parent
		task.spawn(function()
			task.wait(0.1)
			Sound:Play()
			Sound.Ended:Wait()
			Sound:Destroy()
		end)
	end

	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
	local UIContainer = PlayerGui:FindFirstChild("GlobalUI") or PlayerGui:FindFirstChild("MainUI")
	if not UIContainer then return end

	local AchievementsHolder = UIContainer:FindFirstChild("AchievementsHolder")
	if not AchievementsHolder then return end

	local Achievement = AchievementsHolder.Achievement:Clone()
	Achievement.Size = UDim2.new(0, 0, 0, 0)
	Achievement.Frame.Position = UDim2.new(1.1, 0, 0, 0)
	Achievement.Name = "LiveAchievement"
	Achievement.Visible = true

	Achievement.Frame.TextLabel.Text = NotifyOptions.Style or "NOTIFICATION"
	Achievement.Frame.Details.Title.Text = NotifyOptions.Title or "Sem Título"
	Achievement.Frame.Details.Desc.Text = NotifyOptions.Description or "Sem Descrição"
	Achievement.Frame.Details.Reason.Text = NotifyOptions.Reason or ""
	Achievement.Frame.ImageLabel.Image = (NotifyOptions.Image ~= "" and NotifyOptions.Image) or "rbxassetid://6023426923"

	local Color = NotifyOptions.Color or Color3.new(1, 1, 1)
	Achievement.Frame.TextLabel.TextColor3 = Color
	Achievement.Frame.UIStroke.Color = Color
	Achievement.Frame.Glow.ImageColor3 = Color
	Achievement.Parent = AchievementsHolder

	PlaySound(AchievementsHolder, "rbxassetid://10469938989", 1)

	task.spawn(function()
		Achievement:TweenSize(UDim2.new(1, 0, 0.2, 0), "In", "Quad", 0.8, true)
		task.wait(0.8)
		Achievement.Frame:TweenPosition(UDim2.new(0, 0, 0, 0), "Out", "Quad", 0.5, true)
		Services.TweenService:Create(
			Achievement.Frame.Glow,
			TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ ImageTransparency = 1 }
		):Play()

		if typeof(NotifyOptions.Time) == "Instance" then
			NotifyOptions.Time.Destroying:Wait()
		else
			task.wait(NotifyOptions.Time or 5)
		end

		Achievement.Frame:TweenPosition(UDim2.new(1.1, 0, 0, 0), "In", "Quad", 0.5, true)
		task.wait(0.5)
		Achievement:TweenSize(UDim2.new(1, 0, -0.1, 0), "InOut", "Quad", 0.5, true)
		task.wait(0.5)
		Achievement:Destroy()
	end)
end

Globals.STX = loadstring(game:HttpGet(Boot.MirrorRoot .. "bocaj/Components/STX.luau"))()
Functions.Notify = function(Settings)
	local HiddenContainer = GetHiddenContainer()

	if not Settings.Body then
		Settings.Body = "..."
	end

	if not Options.NotifyStyle or Options.NotifyStyle.Value == "Abysall" then
		local Sound = Instance.new("Sound", HiddenContainer)
		Sound.SoundId = "rbxassetid://8784885431"
		Sound.Volume = (Toggles.NotifyPlaySound and Toggles.NotifyPlaySound.Value and Options.NotifySoundVolume.Value) or (Toggles.NotifyPlaySound and 0 or 3)
		Sound.PlayOnRemove = true
		Sound:Destroy()
		NotificationLibrary:Notify(Settings.Title, Settings.Body, Settings.Time or 5)
	elseif Options.NotifyStyle.Value == "Doors" then
		local IsEntity = false
		local EntityName = ""
		for Index, Object in pairs(Entities) do
			if Object.NotifyMessage.Title == Settings.Title or Object.NotifyMessage.Body == Settings.Body then
				IsEntity = true
				EntityName = Index
			end
		end
		Globals.DoorsNotify({
			Title = "Abyssal Massive Recode",
			Description = Settings.Title,
			Reason = Settings.Body,
			Style = IsEntity and "WARNING" or "NOTIFICATION",
			Color = IsEntity and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 222, 189),
			Image = Settings.Image,
			Time = Settings.Time
		})
	elseif Options.NotifyStyle.Value == "STX" then
		local Sound = Instance.new("Sound", HiddenContainer)
		Sound.SoundId = "rbxassetid://4590657391"
		Sound.Volume = (Toggles.NotifyPlaySound and Toggles.NotifyPlaySound.Value and Options.NotifySoundVolume.Value) or (Toggles.NotifyPlaySound and 0 or 3)
		Sound.PlayOnRemove = true
		Sound:Destroy()

		if Settings.Image then
			Globals.STX:Notify(
				{Title = "Abyssal Massive Recode", Description = Settings.Title .. "\n" .. Settings.Body},
				{OutlineColor = Library.Scheme.AccentColor,Time = Settings.Time or 5, Type = "image"},
				{Image = Settings.Image, ImageColor = Color3.fromRGB(255, 255, 255)}
			)
		else
			Globals.STX:Notify(
				{Title = "Abyssal Massive Recode", Description = Settings.Title .. "\n" .. Settings.Body},
				{OutlineColor = Library.Scheme.AccentColor,Time = Settings.Time or 5, Type = "default"}
			)
		end
	else
		local Sound = Instance.new("Sound", HiddenContainer)
		Sound.SoundId = "rbxassetid://4590662766"
		Sound.Volume = (Toggles.NotifyPlaySound and Toggles.NotifyPlaySound.Value and Options.NotifySoundVolume.Value) or (Toggles.NotifyPlaySound and 0 or 3)
		Sound.PlayOnRemove = true
		Sound:Destroy()
		Library:OldNotify({ Title = Settings.Title, Description = Settings.Body, Time = Settings.Time })
	end
end

Functions.Caption = function(Text, PlaySound)
	if typeof(PlaySound) ~= "boolean" then
		PlaySound = true
	end
	local CaptionValue = Instance.new("NumberValue")
	local Caption = Globals.MainUI:WaitForChild("MainFrame"):WaitForChild("Caption"):Clone()
	local CaptionSound = Globals.MainUI:WaitForChild("Initiator"):WaitForChild("Main_Game"):WaitForChild("Reminder"):WaitForChild("Caption")
	local CaptionSoundClone = CaptionSound:Clone()
	CaptionSoundClone.Parent = CaptionSound.Parent
	CaptionSoundClone.Volume = 0.1

	Caption.Destroying:Connect(function()
		CaptionValue:Destroy()
	end)

	for _, Child in Globals.MainUI:GetChildren() do
		if Child.Name == "LiveCaption" then
			Child:Destroy()
		end
	end

	Caption.Parent = Globals.MainUI
	Caption.Visible = true
	Caption.Name = "LiveCaption"
	Caption.Text = Text

	if PlaySound then
		CaptionSoundClone:Play()
	end

	Services.Debris:AddItem(CaptionSoundClone, 5)

	local HolderTween = Services.TweenService:Create(CaptionValue, TweenInfo.new(3), { Value = 100 })
	HolderTween:Play()
	HolderTween.Completed:Connect(function()
		CaptionValue:Destroy()
		Services.TweenService:Create(Caption, TweenInfo.new(4, Enum.EasingStyle.Linear), { TextTransparency = 1 }):Play()
		Services.TweenService:Create(Caption, TweenInfo.new(4, Enum.EasingStyle.Linear), { TextStrokeTransparency = 1 }):Play()
	end)
end

Functions.GetHasteTime = function()
	local TimeRemaining = FloorReplicated.DigitalTimer.Value
	local Minutes = math.floor(TimeRemaining / 60)
	local Seconds = TimeRemaining - (Minutes * 60)
	local MinutesText = Minutes < 10 and ("0" .. tostring(Minutes)) or tostring(Minutes)
	local SecondsText = Seconds < 10 and ("0" .. tostring(Seconds)) or tostring(Seconds)
	return MinutesText .. ":" .. SecondsText
end

Library.OldNotify = Library.Notify
Library.Notify = function(Data, Body, Time)
	Functions.Notify({ Title = Body, Time = Time or 5 })
end

if not LocalPlayer.Character or not CurrentRooms:FindFirstChildOfClass("Model") then
	Functions.Notify({ Title = "Waiting for the game to load..." })
	while not LocalPlayer.Character or not CurrentRooms:FindFirstChildOfClass("Model") do
		task.wait()
	end
	task.wait(4)
end

if not RemotesFolder then
	if Services.ReplicatedStorage:FindFirstChild("EntityInfo") then
		RemotesFolder = Services.ReplicatedStorage:FindFirstChild("EntityInfo")
	elseif Services.ReplicatedStorage:FindFirstChild("Bricks") then
		RemotesFolder = Services.ReplicatedStorage:FindFirstChild("Bricks")
	end
end

if Floor == "Hotel" and RemotesFolder.Name == "Bricks" then
	Floor = "OldHotel"
end

if not LiveModifiers then
	LiveModifiers = Instance.new("Folder")
end

if not FloorReplicated then
	FloorReplicated = Instance.new("Folder")
end

local FakeEvents = {
	Screech = Instance.new("RemoteEvent"),
	Shade   = Instance.new("RemoteEvent"),
	A90     = Instance.new("RemoteEvent"),
	Surge   = Instance.new("RemoteEvent"),
}

FakeEvents.Screech.Name  = "Screech"
FakeEvents.Shade.Name    = "ShadeResult"
FakeEvents.A90.Name      = "A90"
FakeEvents.Surge.Name    = "SurgeRemote"

FakeEvents.Screech_Real = RemotesFolder:WaitForChild("Screech")
FakeEvents.Shade_Real   = RemotesFolder:WaitForChild("ShadeResult")
FakeEvents.A90_Real     = RemotesFolder:FindFirstChild("A90")
FakeEvents.Surge_Real   = RemotesFolder:FindFirstChild("SurgeRemote")

if RemotesFolder:FindFirstChild("FootstepRemoteThatWeNeed") then
    local RealRemote = RemotesFolder:FindFirstChild("FootstepRemoteThatWeNeed")
    RealRemote:Destroy()

    local FakeRemote = Instance.new("RemoteEvent", RemotesFolder)
    FakeRemote.Name = "FootstepRemoteThatWeNeed"
end

Globals.FogInstances = {}
Globals.OldFog = Services.Lighting.FogEnd

for _, Object in Services.Lighting:GetChildren() do
	if Object:IsA("Atmosphere") then
		Object:SetAttribute("Density_Old", Object.Density)

		local AtmoConnection = Object:GetPropertyChangedSignal("Density"):Connect(function()
			if Object.Density ~= 0 then
				Object:SetAttribute("Density_Old", Object.Density)
			end
			if Toggles.RemoveCameraFog.Value then
				Object.Density = 0
			end
		end)

		Object.Destroying:Once(function()
			AtmoConnection:Disconnect()
		end)

		table.insert(Connections, AtmoConnection)
		table.insert(Globals.FogInstances, Object)
	end
end

Globals.SeekNodesFolder = Instance.new("Folder", Services.Workspace)
Globals.SeekNodesFolder.Name = Abysall.ESPLibrary:GenerateRandomString()

Globals.RoomsNodesFolder = Instance.new("Folder", Services.Workspace)
Globals.RoomsNodesFolder.Name = Abysall.ESPLibrary:GenerateRandomString()

Functions.SendChat = function(Message)
	local Folder = Services.ReplicatedStorage:FindFirstChild("DefaultChatSystemEvents") or Instance.new("Folder")
	local Event = Folder:FindFirstChild("SayMessageRequest") or Instance.new("RemoteEvent")
	Event:FireServer(Message, "All")
	local Channel = (Services.TextChatService:FindFirstChild("TextChannels") and Services.TextChatService.TextChannels:FindFirstChild("RBXGeneral")) or Instance.new("TextChannel")
	Channel:SendAsync(Message)
end

Functions.IsCrouching = function()
	if Floor == "Fools" or Floor == "OldHotel" then
		return Character:GetAttribute("Crouching")
	end
	return CollisionPart.CollisionGroup == "PlayerCrouching"
end

Functions.GetInjuriesSpeed = function()
	return 0.075 * (Humanoid.MaxHealth - Humanoid.Health)
end

Functions.GetCurrentSpeed = function()
	local Speed = 15
	Speed += Character:GetAttribute("SpeedBoost") or 0
	Speed += Character:GetAttribute("SpeedBoostBehind") or 0
	Speed += Character:GetAttribute("SpeedBoostExtra") or 0
	Speed += (Floor == "Party" and 10 or 0)
	Speed += (LiveModifiers:FindFirstChild("PlayerFast") and 3 or 0)
	Speed += (LiveModifiers:FindFirstChild("PlayerFaster") and 6 or 0)
	Speed += (LiveModifiers:FindFirstChild("PlayerFastest") and 20 or 0)
	Speed -= (LiveModifiers:FindFirstChild("PlayerSlow") and 3 or 0)
	Speed -= (LiveModifiers:FindFirstChild("PlayerSlowHealth") and Functions.GetInjuriesSpeed() or 0)
	if Functions.IsCrouching() then
		if LiveModifiers:FindFirstChild("PlayerCrouchSlow") then
			Speed -= 8
		elseif LiveModifiers:FindFirstChild("PlayerSlow") then
			Speed -= 8
		else
			Speed -= 5
		end
	end
	return Speed
end

Functions.GetMousePosition = function()
	if Library.IsMobile then
		return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	end
	local MouseLocation = Services.UserInputService:GetMouseLocation()
	return Vector2.new(MouseLocation.X, MouseLocation.Y)
end

Functions.FormatOxygen = function(Oxygen)
	return "Oxygen: " .. (math.floor(Oxygen * 10) / 10) .. "%"
end

Functions.IsHidePersistent = function()
	return Floor == "Mines"
		or Floor == "Ripple"
		or Floor == "Party"
		or LiveModifiers:FindFirstChild("HideLevel2") ~= nil
end

Functions.GetPlayerFromMouse = function(TargetPart, MaxDistance)
	local Closest
	local ClosestDistance = math.huge

	for _, Player in Services.Players:GetPlayers() do
		local Char = Player.Character
		if Char then
			local Target = Char:FindFirstChild(TargetPart)
			if Target then
				local Result = Camera:WorldToViewportPoint(Target.Position)
				local ScreenPos = Vector2.new(Result.X, Result.Y)
				local Distance = (Functions.GetMousePosition() - ScreenPos).Magnitude
				if Player.Name ~= LocalPlayer.Name and Distance < ClosestDistance and Distance < MaxDistance then
					Closest = Target
					ClosestDistance = Distance
				end
			end
		end
	end
	return Closest
end

local EntityDistances = {
	["RushMoving"]    = 85,
	["Scribbles"]	  = 100,
	["BashMoving"]    = 150,
	["DronesStampede"] = 100,
	["AmbushMoving"]  = 150,
	["A60"]           = 125,
	["A120"]          = 85,
	["GlitchRush"]    = 90,
	["GlitchAmbush"]  = 175,
	["BackdoorRush"]  = 85,
	["CustomEntity"]  = 85,
}

Functions.GetNearestEntity = function(CheckDisabled, List, UseRaycasting)
	local Nearest = { Distance = math.huge, Object = nil }

	for _, Entity in Objects.Entities do
		if not Entity or not Entity:IsA("Model") or not Entity:IsDescendantOf(Services.Workspace) then continue end
		if not EntityDistances[Entity.Name] or not Entity.PrimaryPart then continue end

		local EntityData = Entities[Entity.Name]
		if not EntityData then continue end
		if List and List[EntityData.Alias] then continue end

		local Distance = LocalPlayer:DistanceFromCharacter(Entity.PrimaryPart.Position)
		if Distance < EntityDistances[Entity.Name] and Distance < Nearest.Distance then
			if not CheckDisabled or Entity:GetAttribute("Inactive") ~= true then
				Nearest.Distance = Distance
				Nearest.Object = Entity
			end
		end
	end
	return Nearest.Object
end

Functions.GetNearestFigure = function()
	local Nearest = { Distance = math.huge, Object = nil }
	local FigureNames = { FigureRig = true, FigureRagdoll = true, Figure = true }

	for _, Object in Objects.Entities do
		if Object:IsA("Model") and Object.PrimaryPart and FigureNames[Object.Name] then
			local Distance = LocalPlayer:DistanceFromCharacter(Object.PrimaryPart.Position)
			if Distance < Nearest.Distance and Distance < 25 then
				Nearest.Distance = Distance
				Nearest.Object = Object
			end
		end
	end
	return Nearest.Object
end

Functions.GetNearestHidingSpot = function()
	local Nearest = { Distance = math.huge, Object = nil }
	local LastHideSpot = Character:FindFirstChild("LastHideSpot")

	local function IsHidingSpotName(Name)
		if typeof(Name) ~= "string" then return false end
		return string.find(string.lower(Name), "hidingspot") or string.find(string.lower(Name), "hiding_spot")
	end

	local function GetHidePrompt(Object)
	if not Object then return nil end

	local Prompt = Object:FindFirstChild("HidePrompt") or Object:FindFirstChild("HidingPrompt")
	if Prompt then return Prompt end

	for _, Child in Object:GetDescendants() do
		if (Child:IsA("ProximityPrompt") or Child:IsA("InteractPrompt"))
			and (Child.Name == "HidePrompt" or Child.Name == "HidingPrompt" or IsHidingSpotName(Child.Name))
		then
			return Child
		end
	end

	if IsHidingSpotName(Object.Name) or IsHidingSpotName(Object.Parent and Object.Parent.Name) then
		return Object:FindFirstChild("HidePrompt") or Object:FindFirstChild("HidingPrompt")
	end

	return nil
	end

	local function TryObject(Object)
		if not Object or not Object:IsDescendantOf(Services.Workspace) then return end
		if not Object.PrimaryPart and not Object:FindFirstChildOfClass("BasePart") then return end
		local Prompt = GetHidePrompt(Object)
		if not Prompt then return end
		local PrimaryPart = Object.PrimaryPart or Object:FindFirstChildOfClass("BasePart")
		if not PrimaryPart then return end
		local Distance = LocalPlayer:DistanceFromCharacter(PrimaryPart.Position)
		if Distance < Prompt.MaxActivationDistance and Distance < Nearest.Distance then
			local Persistent = Functions.IsHidePersistent()
			if not Persistent or (LastHideSpot and LastHideSpot.Value ~= Object) or not LastHideSpot then
				Nearest.Distance = Distance
				Nearest.Object = Object
			end
		end
	end

	for _, Object in Objects.HidingSpots do
		TryObject(Object)
	end

	return Nearest.Object
end

Functions.GetNearestTurnNode = function()
	local Nearest = { Distance = math.huge, Object = nil }

	for _, Node in Objects.SeekNodes do
		local Distance = LocalPlayer:DistanceFromCharacter(Node.Position)
		if Distance < Options.AutoSteerMinecartTurnDistance.Value and Distance < Nearest.Distance then
			Nearest.Distance = Distance
			Nearest.Object = Node
		end
	end
	return Nearest.Object
end

Functions.GetNearestDuckBoard = function()
	local Nearest = { Distance = math.huge, Object = nil }

	for _, Board in Objects.SeekDuckBoards do
		if Board.PrimaryPart then
			local Distance = LocalPlayer:DistanceFromCharacter(Board.PrimaryPart.Position)
			if Distance < Options.AutoSteerMinecartDuckDistance.Value and Distance < Nearest.Distance then
				Nearest.Distance = Distance
				Nearest.Object = Board
			end
		end
	end
	return Nearest.Object
end

Functions.GetCurrentAnchor = function()
	local AnchorCode = Globals.MainUI.AnchorHintFrame.AnchorCode.Text
	for _, Anchor in Objects.Objectives do
		if Anchor.Name == "MinesAnchor" and Anchor:FindFirstChild("Sign") then
			if Anchor.Sign.TextLabel.Text == AnchorCode then
				return Anchor
			end
		end
	end
end

Functions.GetMinecart = function()
	return Camera:FindFirstChild("MinecartRig") ~= nil
end

Functions.HasItem = function(Name, OnlyCharacter)
	if not OnlyCharacter and LocalPlayer.Backpack:FindFirstChild(Name) then
		return LocalPlayer.Backpack:FindFirstChild(Name)
	elseif Character:FindFirstChild(Name) then
		return Character:FindFirstChild(Name)
	end
end

Functions.GetFlyVelocity = function()
	if Humanoid.MoveDirection == Vector3.zero then
		if Globals.AutoFly and Globals.AutoFlyDirection then return Globals.AutoFlyDirection end
		return Humanoid.MoveDirection
	end
	local LookFlat = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z)
	local FlatFrame = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + LookFlat)
	local Velocity = (Camera.CFrame * CFrame.new(FlatFrame:VectorToObjectSpace(Humanoid.MoveDirection))).Position - Camera.CFrame.Position
	if Velocity == Vector3.zero then
		return Velocity
	end
	if Globals.AutoFly then
		local Flat = Vector3.new(Velocity.X, 0, Velocity.Z)
		if Flat.Magnitude > 0.01 then Globals.AutoFlyDirection = Flat.Unit end
	end
	return Velocity.Unit
end

Globals.PromptContainer = Instance.new("Folder")
Globals.PromptContainer.Name = "PromptContainer"
Globals.PromptContainer.Parent = GetHiddenContainer()

local ESPBlacklist = {}

Functions.AddESP = function(ESPOptions, RoomBased)
	local Object = ESPOptions.Object

	if table.find(ESPBlacklist, Object) then
		return
	end

	if RoomBased then
		local CurrentRoom = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
		local ObjectRoom = tonumber(Object:GetAttribute("ParentRoom"))

		if ObjectRoom == CurrentRoom or (table.find(Objects.Doors, Object) and ObjectRoom == CurrentRoom + 1) then
			Abysall.ESPLibrary:AddESP(ESPOptions)
		end

		local RoomConnection = LocalPlayer:GetAttributeChangedSignal("CurrentRoom"):Connect(function()
			if Abysall.ESPLibrary.ColorTable[Object] then
				ESPOptions.Color = Abysall.ESPLibrary.ColorTable[Object]
			end

			local NewCurrentRoom = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
			local ObjRoom = tonumber(Object:GetAttribute("ParentRoom"))

			if ObjRoom == NewCurrentRoom or (table.find(Objects.Doors, Object) and ObjRoom == NewCurrentRoom + 1) then
				Abysall.ESPLibrary:AddESP(ESPOptions)
			else
				Abysall.ESPLibrary:RemoveESP(Object)
			end
		end)

		table.insert(Connections, RoomConnection)
		ESPConnections[Object] = RoomConnection

		Object.Destroying:Once(function()
			RoomConnection:Disconnect()
			if Abysall then
				Abysall.ESPLibrary:RemoveESP(Object)
			end
			local Pos = table.find(Connections, RoomConnection)
			if Pos then table.remove(Connections, Pos) end
		end)
	else
		Abysall.ESPLibrary:AddESP(ESPOptions)
	end
end

Functions.RemoveESP = function(Object)
	local Conn = ESPConnections[Object]
	if Conn then
		Conn:Disconnect()
		ESPConnections[Object] = nil
		local Pos = table.find(Connections, Conn)
		if Pos then table.remove(Connections, Pos) end
	end
	Abysall.ESPLibrary:RemoveESP(Object)
end

Functions.BlacklistESP = function(Object)
	table.insert(ESPBlacklist, Object)
end

Functions.GetDoorNumber = function(Object)
	local DoorNumber = tonumber(Object.Parent.Name) or tonumber(Object.Parent.Parent.Name)
	if DoorNumber then
		DoorNumber = DoorNumber + 1
	end
	if Floor == "Mines" then
		DoorNumber = DoorNumber + 100
	end
	if Floor == "Backdoor" then
		DoorNumber = DoorNumber - 50
	end

	return tostring(DoorNumber)
end

Functions.GetLibraryCode = function()
	local Paper = Character:FindFirstChild("LibraryHintPaper")
		or Character:FindFirstChild("LibraryHintPaperHard")
		or LocalPlayer.Backpack:FindFirstChild("LibraryHintPaper")
		or LocalPlayer.Backpack:FindFirstChild("LibraryHintPaperHard")

	if Paper and Paper:FindFirstChild("UI") then
		local Code = {}
		local CodeLength = Floor == "Fools" and 10 or 5
		for I = 1, CodeLength do Code[I] = "_" end

		local HintChildren = LocalPlayer.PlayerGui.PermUI.Hints:GetChildren()
		local UIChildren = Paper.UI:GetChildren()

		for _, Hint in HintChildren do
			for _, UIChild in UIChildren do
				if Hint:IsA("ImageLabel") and UIChild:IsA("ImageLabel")
					and Hint.ImageRectOffset == UIChild.ImageRectOffset
					and Code[tonumber(UIChild.Name)]
				then
					Code[tonumber(UIChild.Name)] = Hint.TextLabel.Text
				end
			end
		end
		return table.concat(Code)
	end
	return Floor == "Fools" and "__________" or "_____"
end

Globals.UsedRandomCodes = {}
Functions.GetRandomCode = function()
    local CodeTemplate = Functions.GetLibraryCode()
    if not CodeTemplate then
        return nil
    end

    local NewCode
    local Tries = 0
    repeat
        NewCode = CodeTemplate:gsub("_", function()
            return tostring(math.random(0, 9))
        end)
        Tries = Tries + 1
    until not Globals.UsedRandomCodes[NewCode] or Tries >= 10

    Globals.UsedRandomCodes[NewCode] = true
    return NewCode
end

local Window = Library:CreateWindow({
	Title = "Abyssal Massive Recode",
	Footer = "discord.gg/an2h2MXED",
	NotifySide = "Right",
	ShowCustomCursor = false,
	AutoShow = true,
	Center = true,
	TabPadding = 3,
	MenuFadeTime = 0,
	CornerRadius = 6,
})

-- the window title can be cut off ("Abyssal Massive..."): shrink it to fit instead of truncating
task.spawn(function()
	for _ = 1, 8 do
		task.wait(0.5)
		pcall(function()
			for _, Label in Library.ScreenGui:GetDescendants() do
				if Label:IsA("TextLabel") and Label.Text == "Abyssal Massive Recode" and not Label.TextScaled then
					local Limit = Label.AbsoluteSize.X
					local Parent = Label.Parent
					if Parent and Parent:IsA("GuiObject") then
						Limit = math.min(Limit, Parent.AbsoluteSize.X - (Label.AbsolutePosition.X - Parent.AbsolutePosition.X))
					end
					if Label.TextBounds.X > Limit - 1 and Limit > 20 then
						local Constraint = Instance.new("UITextSizeConstraint")
						Constraint.MaxTextSize = Label.TextSize
						Constraint.Parent = Label
						Label.TextTruncate = Enum.TextTruncate.None
						if Label.AutomaticSize ~= Enum.AutomaticSize.None then
							Label.AutomaticSize = Enum.AutomaticSize.None
							Label.Size = UDim2.fromOffset(Limit, math.max(14, Label.AbsoluteSize.Y))
						end
						Label.TextScaled = true
					end
				end
			end
		end)
	end
end)


Abysall.Interface.ApplyInfoTab(Window)

local Tabs = {
	General = Window:AddTab(Boot.T("tab_general", "General"), "house"),
	Exploits = Window:AddTab(Boot.T("tab_exploits", "Exploits"), "shield"),
	Visuals = Window:AddTab(Boot.T("tab_visuals", "Visuals"), "eye"),
	Floors = Window:AddTab(Boot.T("tab_floors", "Floors"), "earth"),
	Archives = Window:AddTab(Boot.T("tab_archives", "Archives"), "rbxassetid://104508835882225"),
	Stairwell = Window:AddTab(Boot.T("tab_stairwell", "Stairwell"), "rbxassetid://80017304328364"),
	Halloween = Window:AddTab(Boot.T("tab_halloween", "New - Halloween"), "rbxassetid://101034055693026"),
	Tamagochi = Window:AddTab(Boot.T("pet", "Tamagochi"), "heart"),
}


Groupboxes.General_Character = Tabs.General:AddLeftGroupbox("Character")
Groupboxes.General_Character:AddSlider("SpeedBoostSlider", {
	Text = "Speed Boost", Min = 0, Max = 100, Default = 0, Rounding = 0, Compact = true
})
Groupboxes.General_Character:AddToggle("SpeedBoostToggle", {
	Text = "Enable Speed Boost", Default = false, Tooltip = "Increases your walkspeed by the specified amount."
})
Groupboxes.General_Character:AddToggle("FlyToggle", {
	Text = "Fly", Default = false, Tooltip = "Allows you to freely fly around the map."
})
Toggles.FlyToggle:AddKeyPicker("FlyKeybind", {
	Text = "Fly", Default = "F", Mode = "Toggle", SyncToggleState = true
})
Groupboxes.General_Character:AddSlider("FlySpeed", {
	Text = "Fly Speed", Min = 0, Max = 115, Default = 20, Rounding = 0, Compact = true
})
Groupboxes.General_Character:AddDivider()
Groupboxes.General_Character:AddToggle("NoclipToggle", {
	Text = "Noclip", Default = false, Tooltip = "Allows your character to pass through solid objects."
})
Groupboxes.General_Character:AddToggle("RemoveClosetDelay", {
	Text = "Remove Closet Delay", Default = false,
	Tooltip = "Removes the short window where you can't exit out of a closet after the animation finishes."
})
Groupboxes.General_Character:AddToggle("RemoveAcceleration", {
	Text = "Remove Acceleration", Default = false, Tooltip = "Prevents your character from sliding while moving."
})

local CustomPhysics

Options.SpeedBoostSlider:OnChanged(function(Value)
	if RemotesFolder:FindFirstChild("Crouch") then
		RemotesFolder.Crouch:FireServer(Value and true or Functions.IsCrouching(), true)
	end
end)

Toggles.NoclipToggle:AddKeyPicker("NoclipKeybind", {
	Text = "Noclip", Default = "N", Mode = "Toggle", SyncToggleState = true
})
Toggles.RemoveAcceleration:OnChanged(function(Value)
	for Index, Old in PartProperties do
		Index.CustomPhysicalProperties = Value and CustomPhysics or Old
	end
end)

Groupboxes.General_Character:AddDivider()
Groupboxes.General_Character:AddToggle("EnableCharacterJump", {
	Text = "Enable Jumping", Default = false, Tooltip = "Allows your character to jump."
})
Groupboxes.General_Character:AddToggle("EnableCharacterSlide", {
	Text = "Enable Sliding", Default = false, Tooltip = "Allows your character to slide."
})
Groupboxes.General_Character:AddToggle("InfiniteJumps", {
	Text = "Infinite Jumps", Default = false, Tooltip = "Allows you to jump while in the air."
})

local OldJump = false
local OldSlide = false

Toggles.SpeedBoostToggle:OnChanged(function(Value)
	if Humanoid then
		Humanoid.WalkSpeed = Functions.GetCurrentSpeed() + (Value and Options.SpeedBoostSlider.Value or 0)
	end
end)
Toggles.EnableCharacterJump:OnChanged(function(Value)
	if Character and not Globals.JumpLock then
		Character:SetAttribute("CanJump", Value and true or OldJump)
	end
end)
Toggles.EnableCharacterSlide:OnChanged(function(Value)
	if Character then
		Character:SetAttribute("CanSlide", Value and true or OldSlide)
	end
end)

Groupboxes.General_Self = Tabs.General:AddLeftGroupbox("Self")
Groupboxes.General_Self:AddToggle("DoorReachToggle", {
	Text = "Door Reach", Default = false, Tooltip = "Allows you to open doors from further away."
})
Groupboxes.General_Self:AddToggle("DisableIdleKick", {
	Text = "Disable Idle Kick", Default = false, Tooltip = "Prevents the kick from being idle for 20 minutes."
})
Toggles.DisableIdleKick:OnChanged(function(Value)
	if Functions.CheckCompatability({"getconnections"}) then
		for _, Conn in Abysall.Environment.getconnections(LocalPlayer.Idled) do
			if Value then Conn:Disable() else Conn:Enable() end
		end
	end
end)
LocalPlayer.Idled:Connect(function()
	if Toggles.DisableIdleKick.Value then
		Services.VirtualUser:CaptureController()
		Services.VirtualUser:ClickButton2(Vector2.new())
	end
end)

Groupboxes.General_Self:AddDivider()
Groupboxes.General_Self:AddSlider("PromptReachSlider", {
	Text = "Prompt Reach Multiplier", Min = 1, Max = 2, Default = 1, Rounding = 1, Compact = true
})
Groupboxes.General_Self:AddToggle("InstantPrompts", {
	Text = "Instant Prompts", Default = false, Tooltip = "Allows you to trigger all prompts instantly."
})
Groupboxes.General_Self:AddToggle("PromptClip", {
	Text = "Prompt Clip", Default = false, Tooltip = "Allows you to interact with prompts through walls."
})

Options.PromptReachSlider:OnChanged(function(Value)
	for _, Prompt in Objects.Prompts do
		Prompt.MaxActivationDistance = Prompt:GetAttribute("MaxActivationDistance_Old") * Value
	end
end)
Toggles.InstantPrompts:OnChanged(function(Value)
	for _, Prompt in Objects.Prompts do
		Prompt.HoldDuration = Value and 0 or Prompt:GetAttribute("HoldDuration_Old")
	end
end)
Toggles.PromptClip:OnChanged(function(Value)
	for _, Prompt in Objects.Prompts do
		Prompt.RequiresLineOfSight = Value and false or Prompt:GetAttribute("RequiresLineOfSight_Old")
	end
end)

Groupboxes.Self_Automation = Tabs.General:AddRightGroupbox("Automation")
Groupboxes.Self_Automation:AddToggle("AutoBreakerBox", {
	Text = "Auto Breaker Box", Default = false, Tooltip = "Automatically solves the breaker box."
})
Groupboxes.Self_Automation:AddToggle("AutoSolveAnchors", {
	Text = "Auto Solve Anchors", Default = false,
	Tooltip = "Automatically enters the correct code into anchors when you are near them."
})
Toggles.AutoBreakerBox:OnChanged(function(Value)
	if Value and CurrentRooms:FindFirstChild("ElevatorBreaker", true) then
		if not Globals.BreakerBoxInteracted then
			if not Globals.BreakerBoxNotified then
				Functions.Notify({ Title = "Interact with the breaker box.", Body = "It will be automatically solved." })
				Globals.BreakerBoxInteracted = true
			end
		else
			RemotesFolder.EBF:FireServer()
		end
	end
end)

Groupboxes.Self_Automation:AddToggle("AutoHeartbeatMinigame", { Text = "Auto Heartbeat Minigame", Default = false, Tooltip = "Prevents the 'Figure' minigame from ever failing.", Disabled = not Functions.CheckCompatability({"hookmetamethod", "newcclosure", "getnamecallmethod"}), DisabledTooltip = Globals.IncompatibleMessage })
Groupboxes.Self_Automation:AddDivider()
Groupboxes.Self_Automation:AddToggle("AutoUnlockPadlockToggle", {
	Text = "Auto Unlock Padlock", Default = false, Tooltip = "Automatically enters the code into the library padlock."
})
Groupboxes.Self_Automation:AddSlider("AutoUnlockPadlockSlider", {
	Text = "Unlock Distance", Min = 1, Max = 50, Default = 10, Rounding = 0, Compact = true
})
Groupboxes.Self_Automation:AddToggle("AutoLibraryGuessCode", {
	Text = "Guess Library Code", Default = false,
	Tooltip = "Attempts to guess the library code, but collecting some books is also necessary."
})
Groupboxes.Self_Automation:AddDivider()
Groupboxes.Self_Automation:AddToggle("AutoLibrary", {
	Text = "Auto Library", Default = false,
	Tooltip = "Automatically gets books and paper."
})
Groupboxes.Self_Automation:AddToggle("SkipSeekHotel", {
	Text = "Skip Seek (Hotel)",
	Default = false,
	Tooltip = "Skips the entire Seek sections.",
})
Groupboxes.Self_Automation:AddToggle("AutoBreakerRoom", {
	Text = "Auto Breaker Room",
	Default = false,
	Tooltip = "Automatically completes the breaker sequence in Hotel Room 100.",
})
Groupboxes.Self_Automation:AddDivider()
Toggles.AutoHotel = Groupboxes.Self_Automation:AddToggle("AutoHotel", {
	Text = "Auto Hotel",
	Tooltip = "Automatically progresses through the hotel floor.",
	Risky = Floor ~= "Ballz",
	Default = false
})
Toggles.AutoHotelIgnoreEntities = Groupboxes.Self_Automation:AddToggle("AutoHotelIgnoreEntities", {
	Text = "Ignore Entities",
	Tooltip = "Skip all entity waits and pauses.",
	Default = false
})
Groupboxes.Self_Automation:AddDivider()
Groupboxes.Self_Automation:AddToggle("AutoInteractToggle", {
	Text = "Auto Interact", Default = false, Tooltip = "Automatically triggers nearby prompts."
})
Toggles.AutoInteractToggle:AddKeyPicker("AutoInteractKeybind", {
    Text = "Auto Interact",
    Default = "R",
    Mode = "Toggle",
    SyncToggleState = true
})
Groupboxes.Self_Automation:AddDropdown("AutoInteractIgnoreList", {
	Text = "Ignore List",
	Values = { "Glitch Fragments", "Jeff Items", "Dropped Items", "Currency", "Minecarts", "Locks" },
	Default = { "Glitch Fragments", "Jeff Items", "Dropped Items" },
	Multi = true, AllowNull = true
})
Groupboxes.Self_Automation:AddDivider()
Groupboxes.Self_Automation:AddToggle("AutoClosetToggle", {
	Text = "Auto Closet", Default = false,
	Tooltip = "Automatically hides in a nearby closet when an entity is near."
})
Toggles.AutoClosetToggle:AddKeyPicker("AutoClosetKeybind", {
	Text = "Auto Closet", Default = "Q", Mode = "Toggle", SyncToggleState = true
})
Groupboxes.Self_Automation:AddDropdown("AutoClosetEntityList", {
	Text = "Ignore List",
	Values = { "Rush", "Ambush", "Blitz", "DronesStampede", "Scribbles", "A-60", "A-120", "AR0xMBUSH", "RNIUSHCG==" },
	Multi = true, AllowNull = true
})
Groupboxes.Self_Automation:AddToggle("SpectateEntityToggle", {
	Text = "Spectate Entity",
	Default = false,
	Tooltip = "Spectates the entity while auto hiding."
})
Groupboxes.Self_Automation:AddDropdown("SpecateEntityMode", {
	Values = {"Player to Entity", "Entity to Player"},
	Default = 1,
	AllowNull = true
})

Groupboxes.Self_Misc = Tabs.General:AddRightGroupbox("Miscellaneous")
Groupboxes.Self_Misc:AddButton({
	Text = "Play Again", Tooltip = "Makes you join a new run, click again to cancel.", DoubleClick = true,
	Func = function() RemotesFolder.PlayAgain:FireServer() end
})
Groupboxes.Self_Misc:AddButton({
	Text = "Return to Lobby", Tooltip = "Makes you teleport back to the lobby.", DoubleClick = true,
	Func = function() RemotesFolder.Lobby:FireServer() end
})
Groupboxes.Self_Misc:AddButton({
	Text = "Revive",
	Tooltip = "Makes you revive, if you have a revive and haven't already revived in this run.",
	DoubleClick = true,
	Func = function() RemotesFolder.Revive:FireServer() end
})
Groupboxes.Self_Misc:AddButton({
	Text = "Reset Character",
	Tooltip = "Kills your character on the server. (takes around 20 seconds if replicatesignal isn't supported)",
	DoubleClick = true,
	Func = function()
		Globals.SelfKilled = true
		if Functions.CheckCompatability({"replicatesignal"}) then
			Abysall.Environment.replicatesignal(LocalPlayer.Kill)
		else
			if RemotesFolder:FindFirstChild("Underwater") then
				RemotesFolder.Underwater:FireServer(true)
			else
				Humanoid.Health = 0
			end
		end
	end
})


Tabs.General:UpdateWarningBox({
	Visible = true,
	Title = "Risk Warning",
	Text = "Features highlighted in red are risky.",
})


Toggles.SkipSeekHotel:OnChanged(function(Value)
	if not Value then return end
	if Floor ~= "Hotel" then return end

	task.spawn(function()
		print("started")

		local currentRooms

		repeat
			if not Toggles.SkipSeekHotel.Value or Floor ~= "Hotel" then
				return
			end
			currentRooms = workspace:FindFirstChild("CurrentRooms")
			task.wait()
		until currentRooms

		print("got currentrooms")

		local lastTriggerRoom = nil

		while Toggles.SkipSeekHotel.Value and Floor == "Hotel" do
			local triggerRoom = nil

			print("waiting for trigger")

			repeat
				if not Toggles.SkipSeekHotel.Value or Floor ~= "Hotel" then
					return
				end

				currentRooms = workspace:FindFirstChild("CurrentRooms")
				local currentRoomNum = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))

				if currentRoomNum and currentRoomNum ~= lastTriggerRoom then
					local room = currentRooms and currentRooms:FindFirstChild(tostring(currentRoomNum))
					if room then
						local trigger = room:WaitForChild("TriggerEventCollision", 0.5)
						if trigger then
							triggerRoom = currentRoomNum
							print("found trigger in", triggerRoom)
						end
					end
				end

				task.wait()
			until triggerRoom

			lastTriggerRoom = triggerRoom

			local roomNum = triggerRoom

			while Toggles.SkipSeekHotel.Value and Floor == "Hotel" do
				roomNum += 1
				print("looking for room", roomNum)

				local room
				repeat
					if not Toggles.SkipSeekHotel.Value or Floor ~= "Hotel" then
						return
					end
					currentRooms = workspace:FindFirstChild("CurrentRooms")
					room = currentRooms and currentRooms:FindFirstChild(tostring(roomNum))
					task.wait()
				until room

				print("found room", roomNum)

				local hasSeekArm = false
				local assets = room:FindFirstChild("Assets")
				if assets then
					for _, child in ipairs(assets:GetChildren()) do
						if child.Name == "Seek_Arm" then
							hasSeekArm = true
							print("found seek arm")
							break
						end
					end
				end

				local door
				repeat
					if not Toggles.SkipSeekHotel.Value or Floor ~= "Hotel" then
						return
					end
					door = room:FindFirstChild("Door", true)
					task.wait()
				until door

				print("found door, teleporting")

				repeat
					if not Toggles.SkipSeekHotel.Value or Floor ~= "Hotel" then
						return
					end
					if Character then
						Character:PivotTo(door:GetPivot())
					end
					task.wait()
				until door:GetAttribute("Opened") == true

				print("door opened")

				if hasSeekArm then
					if not Character then
						return
					end

					print("voiding")

					local voidCFrame = Character:GetPivot() + Vector3.new(0, -2500, 0)

					task.wait(0.25)

					for _ = 1, 20 do
						Character:PivotTo(voidCFrame)
						task.wait()
					end

					task.wait(0.3)

					for _ = 1, 15 do
						Character:PivotTo(voidCFrame)
						task.wait()
					end

					task.wait(0.2)

					for _ = 1, 10 do
						Character:PivotTo(voidCFrame)
						task.wait()
					end

					print("done voiding")
					break
				end
			end
		end
	end)
end)

Toggles.AutoLibrary:OnChanged(function(AutoLibraryEnabled)
	if AutoLibraryConnection then
		task.cancel(AutoLibraryConnection)
		AutoLibraryConnection = nil
	end

	if AutoLibraryRoomConnection then
		AutoLibraryRoomConnection:Disconnect()
		AutoLibraryRoomConnection = nil
	end

	if not AutoLibraryEnabled then
		return
	end

	AutoLibraryConnection = task.spawn(function()
		local AutoLibraryPlayers = game:GetService("Players")
		local AutoLibraryLocalPlayer = AutoLibraryPlayers.LocalPlayer
		local AutoLibraryCharacter = AutoLibraryLocalPlayer.Character or AutoLibraryLocalPlayer.CharacterAdded:Wait()
		local AutoLibraryHumanoidRootPart = AutoLibraryCharacter:WaitForChild("HumanoidRootPart")

		local AutoLibraryCurrentRooms = workspace:WaitForChild("CurrentRooms")
		local AutoLibraryRoom50 = AutoLibraryCurrentRooms:WaitForChild("50")
		local AutoLibraryLiveHintBooks = {}
		local AutoLibraryHintPaperObtained = false

		local function AutoLibraryIsInRoom50(AutoLibraryObject)
			return AutoLibraryObject
				and AutoLibraryObject:IsDescendantOf(AutoLibraryRoom50)
				and AutoLibraryObject:IsDescendantOf(AutoLibraryCurrentRooms)
				and AutoLibraryObject:IsDescendantOf(workspace)
		end

		local function AutoLibraryIsActuallyInRoom50()
			return tonumber(AutoLibraryLocalPlayer:GetAttribute("CurrentRoom")) == 50
		end

		while AutoLibraryEnabled and not AutoLibraryIsActuallyInRoom50() do
			task.wait(0.05)
		end

		if not AutoLibraryEnabled then
			return
		end

		local function AutoLibraryHasHintPaper()
			AutoLibraryCharacter = AutoLibraryLocalPlayer.Character

			if not AutoLibraryCharacter then
				return false
			end

			local AutoLibraryBackpackPaper = AutoLibraryLocalPlayer.Backpack:FindFirstChild("LibraryHintPaper", true)
			local AutoLibraryCharacterPaper = AutoLibraryCharacter:FindFirstChild("LibraryHintPaper", true)

			return AutoLibraryBackpackPaper ~= nil or AutoLibraryCharacterPaper ~= nil
		end

		local function AutoLibraryGetObjectCFrame(AutoLibraryObject)
			if not AutoLibraryIsActuallyInRoom50() then
				return nil
			end

			if not AutoLibraryIsInRoom50(AutoLibraryObject) then
				return nil
			end

			if AutoLibraryObject:IsA("Model") then
				return AutoLibraryObject:GetPivot()
			elseif AutoLibraryObject:IsA("BasePart") then
				return AutoLibraryObject.CFrame
			end

			local AutoLibraryObjectPart = AutoLibraryObject:FindFirstChildWhichIsA("BasePart", true)

			if AutoLibraryObjectPart then
				return AutoLibraryObjectPart.CFrame
			end

			return nil
		end

		local function AutoLibraryFindBooks(AutoLibraryObject)
			if not AutoLibraryIsActuallyInRoom50() then
				return
			end

			if not AutoLibraryIsInRoom50(AutoLibraryObject) then
				return
			end

			if AutoLibraryObject.Name == "LiveHintBook" then
				if not table.find(AutoLibraryLiveHintBooks, AutoLibraryObject) then
					table.insert(AutoLibraryLiveHintBooks, AutoLibraryObject)
				end
			end

			for _, AutoLibraryDescendant in ipairs(AutoLibraryObject:GetDescendants()) do
				if AutoLibraryDescendant.Name == "LiveHintBook"
					and AutoLibraryIsInRoom50(AutoLibraryDescendant) then

					if not table.find(AutoLibraryLiveHintBooks, AutoLibraryDescendant) then
						table.insert(AutoLibraryLiveHintBooks, AutoLibraryDescendant)
					end
				end
			end
		end

		for _, AutoLibraryDescendant in ipairs(AutoLibraryRoom50:GetDescendants()) do
			if not AutoLibraryEnabled or not AutoLibraryIsActuallyInRoom50() then
				return
			end

			if AutoLibraryDescendant.Name == "LiveHintBook"
				and AutoLibraryIsInRoom50(AutoLibraryDescendant) then

				if not table.find(AutoLibraryLiveHintBooks, AutoLibraryDescendant) then
					table.insert(AutoLibraryLiveHintBooks, AutoLibraryDescendant)
				end
			end
		end

		AutoLibraryRoomConnection = AutoLibraryRoom50.DescendantAdded:Connect(function(AutoLibraryAddedObject)
			if not AutoLibraryEnabled then
				return
			end

			if not AutoLibraryIsActuallyInRoom50() then
				return
			end

			if not AutoLibraryIsInRoom50(AutoLibraryAddedObject) then
				return
			end

			AutoLibraryFindBooks(AutoLibraryAddedObject)
		end)

		while AutoLibraryEnabled
			and AutoLibraryIsActuallyInRoom50()
			and #AutoLibraryLiveHintBooks < 3 do

			for _, AutoLibraryDescendant in ipairs(AutoLibraryRoom50:GetDescendants()) do
				if not AutoLibraryEnabled or not AutoLibraryIsActuallyInRoom50() then
					return
				end

				if AutoLibraryDescendant.Name == "LiveHintBook"
					and AutoLibraryIsInRoom50(AutoLibraryDescendant)
					and not table.find(AutoLibraryLiveHintBooks, AutoLibraryDescendant) then

					table.insert(AutoLibraryLiveHintBooks, AutoLibraryDescendant)
				end
			end

			if #AutoLibraryLiveHintBooks >= 3 then
				break
			end

			task.wait(0.05)
		end

		while AutoLibraryEnabled
			and AutoLibraryIsActuallyInRoom50()
			and not AutoLibraryHintPaperObtained do

			if AutoLibraryHasHintPaper() then
				AutoLibraryHintPaperObtained = true
				break
			end

			for AutoLibraryIndex = #AutoLibraryLiveHintBooks, 1, -1 do
				if not AutoLibraryIsActuallyInRoom50() then
					return
				end

				local AutoLibraryLiveHintBook = AutoLibraryLiveHintBooks[AutoLibraryIndex]

				if not AutoLibraryIsInRoom50(AutoLibraryLiveHintBook) then
					table.remove(AutoLibraryLiveHintBooks, AutoLibraryIndex)
					continue
				end

				while AutoLibraryEnabled
					and AutoLibraryIsActuallyInRoom50()
					and not AutoLibraryHintPaperObtained
					and AutoLibraryLiveHintBook.Parent
					and AutoLibraryIsInRoom50(AutoLibraryLiveHintBook) do

					if AutoLibraryHasHintPaper() then
						AutoLibraryHintPaperObtained = true
						break
					end

					AutoLibraryCharacter = AutoLibraryLocalPlayer.Character or AutoLibraryLocalPlayer.CharacterAdded:Wait()
					AutoLibraryHumanoidRootPart = AutoLibraryCharacter:FindFirstChild("HumanoidRootPart")

					if not AutoLibraryHumanoidRootPart then
						task.wait()
						continue
					end

					local AutoLibraryBookCFrame = AutoLibraryGetObjectCFrame(AutoLibraryLiveHintBook)

					if AutoLibraryBookCFrame
						and AutoLibraryIsActuallyInRoom50()
						and AutoLibraryIsInRoom50(AutoLibraryLiveHintBook) then

						AutoLibraryHumanoidRootPart.CFrame = AutoLibraryBookCFrame
					end

					for _, AutoLibraryPromptDescendant in ipairs(AutoLibraryLiveHintBook:GetDescendants()) do
						if AutoLibraryPromptDescendant:IsA("ProximityPrompt")
							and AutoLibraryIsInRoom50(AutoLibraryPromptDescendant)
							and AutoLibraryIsActuallyInRoom50() then

							fireproximityprompt(AutoLibraryPromptDescendant)
						end
					end

					task.wait(0.05)
				end

				if AutoLibraryHintPaperObtained then
					break
				end
			end

			if AutoLibraryHasHintPaper() then
				AutoLibraryHintPaperObtained = true
				break
			end

			local AutoLibraryHintPaper = AutoLibraryRoom50:FindFirstChild("LibraryHintPaper", true)

			if AutoLibraryHintPaper
				and AutoLibraryIsInRoom50(AutoLibraryHintPaper)
				and AutoLibraryIsActuallyInRoom50() then

				while AutoLibraryEnabled
					and AutoLibraryIsActuallyInRoom50()
					and not AutoLibraryHintPaperObtained
					and AutoLibraryHintPaper.Parent
					and AutoLibraryIsInRoom50(AutoLibraryHintPaper) do

					if AutoLibraryHasHintPaper() then
						AutoLibraryHintPaperObtained = true
						break
					end

					AutoLibraryCharacter = AutoLibraryLocalPlayer.Character or AutoLibraryLocalPlayer.CharacterAdded:Wait()
					AutoLibraryHumanoidRootPart = AutoLibraryCharacter:FindFirstChild("HumanoidRootPart")

					if not AutoLibraryHumanoidRootPart then
						task.wait()
						continue
					end

					local AutoLibraryPaperCFrame = AutoLibraryGetObjectCFrame(AutoLibraryHintPaper)

					if AutoLibraryPaperCFrame
						and AutoLibraryIsActuallyInRoom50()
						and AutoLibraryIsInRoom50(AutoLibraryHintPaper) then

						AutoLibraryHumanoidRootPart.CFrame = AutoLibraryPaperCFrame * CFrame.new(0, 5, 0)
					end

					for _, AutoLibraryPromptDescendant in ipairs(AutoLibraryHintPaper:GetDescendants()) do
						if AutoLibraryPromptDescendant:IsA("ProximityPrompt")
							and AutoLibraryIsInRoom50(AutoLibraryPromptDescendant)
							and AutoLibraryIsActuallyInRoom50() then

							fireproximityprompt(AutoLibraryPromptDescendant)
						end
					end

					task.wait(0.05)
				end
			end

			task.wait(0.05)
		end
	end)
end)

Toggles.AutoBreakerRoom:OnChanged(function(AutoBreakerRoomEnabled)
	if AutoBreakerRoomConnection then
		task.cancel(AutoBreakerRoomConnection)
		AutoBreakerRoomConnection = nil
	end

	if AutoBreakerRoomRoomConnection then
		AutoBreakerRoomRoomConnection:Disconnect()
		AutoBreakerRoomRoomConnection = nil
	end

	if not AutoBreakerRoomEnabled then
		return
	end

	local AutoBreakerRoomGateFireTime = 5
	local AutoBreakerRoomWaitAfterLever = 5
	local AutoBreakerRoomBreakerSecondTime = 10
	local AutoBreakerRoomWaitBeforeWeb = 4
	local AutoBreakerRoomWebDuration = 20

	AutoBreakerRoomConnection = task.spawn(function()
		local AutoBreakerRoomPlayers = game:GetService("Players")
		local AutoBreakerRoomCurrentRooms = workspace:WaitForChild("CurrentRooms")
		local AutoBreakerRoom100 = AutoBreakerRoomCurrentRooms:WaitForChild("100")

		local function AutoBreakerRoomIsActuallyInRoom100()
			return tonumber(AutoBreakerRoomPlayers.LocalPlayer:GetAttribute("CurrentRoom")) == 100
		end

		local function AutoBreakerRoomIsInRoom100(AutoBreakerRoomObject)
			return AutoBreakerRoomObject
				and AutoBreakerRoomObject.Parent
				and AutoBreakerRoomObject:IsDescendantOf(AutoBreakerRoom100)
				and AutoBreakerRoomObject:IsDescendantOf(AutoBreakerRoomCurrentRooms)
		end

		local function AutoBreakerRoomGetObjectCFrame(AutoBreakerRoomObject)
			if not AutoBreakerRoomIsActuallyInRoom100() or not AutoBreakerRoomIsInRoom100(AutoBreakerRoomObject) then
				return nil
			end

			if AutoBreakerRoomObject:IsA("Model") then
				return AutoBreakerRoomObject:GetPivot()
			elseif AutoBreakerRoomObject:IsA("BasePart") then
				return AutoBreakerRoomObject.CFrame
			end

			local AutoBreakerRoomPart = AutoBreakerRoomObject:FindFirstChildWhichIsA("BasePart", true)
			return AutoBreakerRoomPart and AutoBreakerRoomPart.CFrame
		end

		local function AutoBreakerRoomGetHRP()
			local AutoBreakerRoomCharacter = AutoBreakerRoomPlayers.LocalPlayer.Character
			return AutoBreakerRoomCharacter and AutoBreakerRoomCharacter:FindFirstChild("HumanoidRootPart")
		end

		local function AutoBreakerRoomActivate(AutoBreakerRoomObject)
			if not AutoBreakerRoomObject then
				return
			end

			if AutoBreakerRoomObject:IsA("ProximityPrompt") then
				fireproximityprompt(AutoBreakerRoomObject)
				return
			end

			for _, AutoBreakerRoomDescendant in ipairs(AutoBreakerRoomObject:GetDescendants()) do
				if AutoBreakerRoomDescendant:IsA("ProximityPrompt") then
					fireproximityprompt(AutoBreakerRoomDescendant)
				end
			end
		end

		local function AutoBreakerRoomConstantTPAndActivate(AutoBreakerRoomTarget, AutoBreakerRoomDuration, AutoBreakerRoomInterval, AutoBreakerRoomOffset)
			AutoBreakerRoomInterval = AutoBreakerRoomInterval or 0.04
			AutoBreakerRoomOffset = AutoBreakerRoomOffset or CFrame.new()
			local AutoBreakerRoomEndTime = os.clock() + (AutoBreakerRoomDuration or 3)

			while AutoBreakerRoomEnabled
				and AutoBreakerRoomIsActuallyInRoom100()
				and AutoBreakerRoomIsInRoom100(AutoBreakerRoomTarget)
				and os.clock() < AutoBreakerRoomEndTime do

				local AutoBreakerRoomHRP = AutoBreakerRoomGetHRP()
				local AutoBreakerRoomCF = AutoBreakerRoomGetObjectCFrame(AutoBreakerRoomTarget)

				if AutoBreakerRoomHRP and AutoBreakerRoomCF then
					AutoBreakerRoomHRP.CFrame = AutoBreakerRoomCF * AutoBreakerRoomOffset
				end

				AutoBreakerRoomActivate(AutoBreakerRoomTarget)
				task.wait(AutoBreakerRoomInterval)
			end
		end

		while AutoBreakerRoomEnabled do
			while AutoBreakerRoomEnabled and not AutoBreakerRoomIsActuallyInRoom100() do
				task.wait(0.1)
			end

			if not AutoBreakerRoomEnabled then
				return
			end

			local AutoBreakerRoomPoles = {}

			while AutoBreakerRoomEnabled and AutoBreakerRoomIsActuallyInRoom100() do
				AutoBreakerRoomPoles = {}

				for _, AutoBreakerRoomDescendant in ipairs(AutoBreakerRoom100:GetDescendants()) do
					if AutoBreakerRoomDescendant.Name == "LiveBreakerPolePickup" and AutoBreakerRoomIsInRoom100(AutoBreakerRoomDescendant) then
						if not table.find(AutoBreakerRoomPoles, AutoBreakerRoomDescendant) then
							table.insert(AutoBreakerRoomPoles, AutoBreakerRoomDescendant)
						end
					end
				end

				if #AutoBreakerRoomPoles == 0 then
					break
				end

				for _, AutoBreakerRoomPole in ipairs(AutoBreakerRoomPoles) do
					if not AutoBreakerRoomEnabled or not AutoBreakerRoomIsActuallyInRoom100() then
						break
					end

					if AutoBreakerRoomIsInRoom100(AutoBreakerRoomPole) then
						AutoBreakerRoomConstantTPAndActivate(AutoBreakerRoomPole, 2.8, 0.03)
						task.wait(0.12)
					end
				end

				task.wait(0.05)
			end

			if not AutoBreakerRoomEnabled or not AutoBreakerRoomIsActuallyInRoom100() then
				continue
			end

			local AutoBreakerRoomIndustrialGate = AutoBreakerRoom100:FindFirstChild("IndustrialGate")
			local AutoBreakerRoomBox = AutoBreakerRoomIndustrialGate and AutoBreakerRoomIndustrialGate:FindFirstChild("Box")
			local AutoBreakerRoomLever = AutoBreakerRoomBox and AutoBreakerRoomBox:FindFirstChild("Lever")
			local AutoBreakerRoomActivateEventPrompt = AutoBreakerRoomBox and AutoBreakerRoomBox:FindFirstChild("ActivateEventPrompt")

			if AutoBreakerRoomActivateEventPrompt and AutoBreakerRoomLever then
				local function AutoBreakerRoomGetLeverCFrame()
					if AutoBreakerRoomLever:IsA("Model") then
						return AutoBreakerRoomLever:GetPivot()
					elseif AutoBreakerRoomLever:IsA("BasePart") then
						return AutoBreakerRoomLever.CFrame
					end
					local AutoBreakerRoomPart = AutoBreakerRoomLever:FindFirstChildWhichIsA("BasePart", true)
					return AutoBreakerRoomPart and AutoBreakerRoomPart.CFrame
				end

				local AutoBreakerRoomInitialLeverCFrame = AutoBreakerRoomGetLeverCFrame()
				local AutoBreakerRoomLeverEndTime = os.clock() + 10

				while AutoBreakerRoomEnabled
					and AutoBreakerRoomIsActuallyInRoom100()
					and AutoBreakerRoomIsInRoom100(AutoBreakerRoomLever)
					and os.clock() < AutoBreakerRoomLeverEndTime do

					local AutoBreakerRoomCurrentLeverCFrame = AutoBreakerRoomGetLeverCFrame()

					if AutoBreakerRoomCurrentLeverCFrame and AutoBreakerRoomInitialLeverCFrame
						and AutoBreakerRoomCurrentLeverCFrame ~= AutoBreakerRoomInitialLeverCFrame then
						break
					end

					local AutoBreakerRoomHRP = AutoBreakerRoomGetHRP()
					local AutoBreakerRoomCF = AutoBreakerRoomGetObjectCFrame(AutoBreakerRoomBox)

					if AutoBreakerRoomHRP and AutoBreakerRoomCF then
						AutoBreakerRoomHRP.CFrame = AutoBreakerRoomCF
					end

					AutoBreakerRoomActivate(AutoBreakerRoomActivateEventPrompt)
					task.wait(0.04)
				end
			end

			if not AutoBreakerRoomEnabled or not AutoBreakerRoomIsActuallyInRoom100() then
				continue
			end

			task.wait(AutoBreakerRoomWaitAfterLever)

			if not AutoBreakerRoomEnabled or not AutoBreakerRoomIsActuallyInRoom100() then
				continue
			end

			local AutoBreakerRoomElevatorBreakerEmpty = AutoBreakerRoom100:FindFirstChild("ElevatorBreakerEmpty")
			if not AutoBreakerRoomElevatorBreakerEmpty then
				continue
			end

			local AutoBreakerRoomBreakerPrompt = AutoBreakerRoomElevatorBreakerEmpty:FindFirstChild("Prompt")
			if not AutoBreakerRoomBreakerPrompt then
				continue
			end

			local AutoBreakerRoomBreakerOffset = CFrame.new(0, -1.8, 0)

			while AutoBreakerRoomEnabled and AutoBreakerRoomIsActuallyInRoom100() do
				if AutoBreakerRoomElevatorBreakerEmpty:FindFirstChild("BreakerSwitchInBox") then
					break
				end

				local AutoBreakerRoomHRP = AutoBreakerRoomGetHRP()
				local AutoBreakerRoomCF = AutoBreakerRoomGetObjectCFrame(AutoBreakerRoomElevatorBreakerEmpty)

				if AutoBreakerRoomHRP and AutoBreakerRoomCF then
					AutoBreakerRoomHRP.CFrame = AutoBreakerRoomCF * AutoBreakerRoomBreakerOffset
				end

				AutoBreakerRoomActivate(AutoBreakerRoomBreakerPrompt)
				task.wait(0.04)
			end

			if not AutoBreakerRoomEnabled or not AutoBreakerRoomIsActuallyInRoom100() then
				continue
			end

			task.wait(10)

			AutoBreakerRoomConstantTPAndActivate(
				AutoBreakerRoomElevatorBreakerEmpty,
				AutoBreakerRoomBreakerSecondTime,
				0.04,
				AutoBreakerRoomBreakerOffset
			)

			task.wait(AutoBreakerRoomWaitBeforeWeb)

			if not AutoBreakerRoomEnabled or not AutoBreakerRoomIsActuallyInRoom100() then
				continue
			end

			local AutoBreakerRoomElevatorCar = AutoBreakerRoom100:FindFirstChild("ElevatorCar")
			local AutoBreakerRoomWeb = AutoBreakerRoomElevatorCar and AutoBreakerRoomElevatorCar:FindFirstChild("Web", true)

			if AutoBreakerRoomWeb then
				local AutoBreakerRoomEndTime = os.clock() + AutoBreakerRoomWebDuration

				while AutoBreakerRoomEnabled and AutoBreakerRoomIsActuallyInRoom100() and os.clock() < AutoBreakerRoomEndTime do
					local AutoBreakerRoomHRP = AutoBreakerRoomGetHRP()
					local AutoBreakerRoomCF = AutoBreakerRoomGetObjectCFrame(AutoBreakerRoomWeb)

					if AutoBreakerRoomHRP and AutoBreakerRoomCF then
						AutoBreakerRoomHRP.CFrame = AutoBreakerRoomCF
					end

					task.wait(0.04)
				end
			end

			while AutoBreakerRoomEnabled and AutoBreakerRoomIsActuallyInRoom100() do
				task.wait(0.5)
			end
		end
	end)
end)



local AutoHotelConnection
local AutoHotelLibraryConnection
local AutoHotelLibraryRoomConnection
local AutoHotelSeekConnection
local AutoHotelEntityPause = false
local AutoHotelRoomProcessTime = 0.5
local AutoHotelProcessedRooms = {}

local AutoHotelEntityNames = {
	["RushMoving"] = true,
	["Scribbles"] = true,
	["BashMoving"] = true,
	["DronesStampede"] = true,
	["AmbushMoving"] = true,
	["A60"] = true,
	["A120"] = true,
	["GlitchRush"] = true,
	["GlitchAmbush"] = true,
	["BackdoorRush"] = true,
	["CustomEntity"] = true,
}

local function AutoHotelIsEntityPresent()
	if Toggles.AutoHotelIgnoreEntities and Toggles.AutoHotelIgnoreEntities.Value then
		return false
	end
	for _, AutoHotelChild in ipairs(workspace:GetChildren()) do
		if AutoHotelEntityNames[AutoHotelChild.Name] then
			return true
		end
	end
	return false
end

local function AutoHotelWaitForEntities(AutoHotelSeconds)
	if Toggles.AutoHotelIgnoreEntities and Toggles.AutoHotelIgnoreEntities.Value then
		return
	end

	task.wait(AutoHotelSeconds or 5)

	while AutoHotelIsEntityPresent() do
		task.wait(0.15)
	end
end

local function AutoHotelGetNextClosedDoor()
	if not Character then return nil, nil end

	local AutoHotelGameData = game:GetService("ReplicatedStorage"):FindFirstChild("GameData")
	if not AutoHotelGameData then return nil, nil end

	local AutoHotelLatestRoom = AutoHotelGameData:FindFirstChild("LatestRoom")
	if not AutoHotelLatestRoom then return nil, nil end

	local AutoHotelStartRoom = AutoHotelLatestRoom.Value
	local AutoHotelBestDoor, AutoHotelBestNumber = nil, math.huge
	local AutoHotelCurrentRooms = workspace:FindFirstChild("CurrentRooms")

	if AutoHotelCurrentRooms then
		for _, AutoHotelRoom in ipairs(AutoHotelCurrentRooms:GetChildren()) do
			local AutoHotelRoomNum = tonumber(AutoHotelRoom.Name)
			if AutoHotelRoomNum and AutoHotelRoomNum ~= 100 and AutoHotelRoomNum >= AutoHotelStartRoom and AutoHotelRoomNum < AutoHotelBestNumber then
				local AutoHotelDoor = AutoHotelRoom:FindFirstChild("Door")
				if AutoHotelDoor and AutoHotelDoor:IsA("Model") then
					local AutoHotelOpenAttr = AutoHotelDoor:GetAttribute("Open")
					if AutoHotelOpenAttr == false or AutoHotelOpenAttr == nil then
						AutoHotelBestNumber = AutoHotelRoomNum
						AutoHotelBestDoor = AutoHotelDoor
					end
				end
			end
		end
	end

	return AutoHotelBestDoor, AutoHotelBestNumber
end

local function AutoHotelFindKeyObtain(AutoHotelRoom)
	local AutoHotelFound = nil
	local function AutoHotelScan(AutoHotelParent)
		if AutoHotelFound then return end
		for _, AutoHotelChild in ipairs(AutoHotelParent:GetChildren()) do
			if AutoHotelChild.Name == "KeyObtain" then
				AutoHotelFound = AutoHotelChild
				return
			end
			AutoHotelScan(AutoHotelChild)
			if AutoHotelFound then return end
		end
	end
	AutoHotelScan(AutoHotelRoom)
	return AutoHotelFound
end

local function AutoHotelHandleKey(AutoHotelRoomNum)
	local AutoHotelCurrentRooms = workspace:FindFirstChild("CurrentRooms")
	if not AutoHotelCurrentRooms then return false end

	local AutoHotelRoom = AutoHotelCurrentRooms:FindFirstChild(tostring(AutoHotelRoomNum))
	if not AutoHotelRoom then return false end

	local AutoHotelDoor = AutoHotelRoom:FindFirstChild("Door")
	if not AutoHotelDoor or not AutoHotelDoor:FindFirstChild("Lock") then
		return false
	end

	local AutoHotelKeyObtain = AutoHotelFindKeyObtain(AutoHotelRoom)
	if not AutoHotelKeyObtain then return false end

	local AutoHotelStart = tick()
	while tick() - AutoHotelStart < 12 do
		if LocalPlayer.Backpack:FindFirstChild("Key") or (Character and Character:FindFirstChild("Key")) then
			return true
		end

		if Character then
			Character:PivotTo(AutoHotelKeyObtain:GetPivot())
		end

		for _, AutoHotelDesc in ipairs(AutoHotelKeyObtain:GetDescendants()) do
			if AutoHotelDesc:IsA("ProximityPrompt") then
				fireproximityprompt(AutoHotelDesc)
			end
		end

		task.wait(0.12)
	end
	return false
end

local function AutoHotelProcessRoom(AutoHotelRoomNum)
	if AutoHotelProcessedRooms[AutoHotelRoomNum] then
		return
	end
	task.wait(AutoHotelRoomProcessTime)
	AutoHotelProcessedRooms[AutoHotelRoomNum] = true
end

local function AutoHotelRunLibrary()
	local AutoHotelCurrentRooms = workspace:WaitForChild("CurrentRooms")
	local AutoHotelRoom50 = AutoHotelCurrentRooms:WaitForChild("50")
	local AutoHotelLiveHintBooks = {}
	local AutoHotelHintPaperObtained = false

	local function AutoHotelIsInRoom50(AutoHotelObj)
		return AutoHotelObj and AutoHotelObj:IsDescendantOf(AutoHotelRoom50)
	end

	local function AutoHotelIsActuallyInRoom50()
		return tonumber(LocalPlayer:GetAttribute("CurrentRoom")) == 50
	end

	while Toggles.AutoHotel.Value and not AutoHotelIsActuallyInRoom50() do
		task.wait(0.1)
	end
	if not Toggles.AutoHotel.Value then return end

	AutoHotelWaitForEntities(5)

	local function AutoHotelHasHintPaper()
		local AutoHotelChar = LocalPlayer.Character
		if not AutoHotelChar then return false end
		return LocalPlayer.Backpack:FindFirstChild("LibraryHintPaper", true) or AutoHotelChar:FindFirstChild("LibraryHintPaper", true)
	end

	local function AutoHotelGetCFrame(AutoHotelObj)
		if not AutoHotelIsActuallyInRoom50() or not AutoHotelIsInRoom50(AutoHotelObj) then return nil end
		if AutoHotelObj:IsA("Model") then return AutoHotelObj:GetPivot() end
		if AutoHotelObj:IsA("BasePart") then return AutoHotelObj.CFrame end
		local AutoHotelPart = AutoHotelObj:FindFirstChildWhichIsA("BasePart", true)
		return AutoHotelPart and AutoHotelPart.CFrame
	end

	local function AutoHotelCollectBooks()
		for _, AutoHotelDesc in ipairs(AutoHotelRoom50:GetDescendants()) do
			if AutoHotelDesc.Name == "LiveHintBook" and AutoHotelIsInRoom50(AutoHotelDesc) and not table.find(AutoHotelLiveHintBooks, AutoHotelDesc) then
				table.insert(AutoHotelLiveHintBooks, AutoHotelDesc)
			end
		end
	end

	AutoHotelCollectBooks()

	AutoHotelLibraryRoomConnection = AutoHotelRoom50.DescendantAdded:Connect(function(AutoHotelAdded)
		if Toggles.AutoHotel.Value and AutoHotelIsActuallyInRoom50() and AutoHotelIsInRoom50(AutoHotelAdded) then
			if AutoHotelAdded.Name == "LiveHintBook" and not table.find(AutoHotelLiveHintBooks, AutoHotelAdded) then
				table.insert(AutoHotelLiveHintBooks, AutoHotelAdded)
			end
		end
	end)

	while Toggles.AutoHotel.Value and AutoHotelIsActuallyInRoom50() and #AutoHotelLiveHintBooks < 3 do
		AutoHotelCollectBooks()
		if #AutoHotelLiveHintBooks >= 3 then break end
		task.wait(0.1)
	end

	while Toggles.AutoHotel.Value and AutoHotelIsActuallyInRoom50() and not AutoHotelHintPaperObtained do
		if AutoHotelHasHintPaper() then
			AutoHotelHintPaperObtained = true
			break
		end

		for AutoHotelIndex = #AutoHotelLiveHintBooks, 1, -1 do
			local AutoHotelBook = AutoHotelLiveHintBooks[AutoHotelIndex]
			if not AutoHotelIsInRoom50(AutoHotelBook) then
				table.remove(AutoHotelLiveHintBooks, AutoHotelIndex)
				continue
			end

			while Toggles.AutoHotel.Value and AutoHotelIsActuallyInRoom50() and not AutoHotelHintPaperObtained and AutoHotelBook.Parent and AutoHotelIsInRoom50(AutoHotelBook) do
				if AutoHotelHasHintPaper() then
					AutoHotelHintPaperObtained = true
					break
				end

				local AutoHotelChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
				local AutoHotelHRP = AutoHotelChar:FindFirstChild("HumanoidRootPart")
				if not AutoHotelHRP then
					task.wait()
					continue
				end

				local AutoHotelCF = AutoHotelGetCFrame(AutoHotelBook)
				if AutoHotelCF then
					AutoHotelHRP.CFrame = AutoHotelCF
				end

				for _, AutoHotelPrompt in ipairs(AutoHotelBook:GetDescendants()) do
					if AutoHotelPrompt:IsA("ProximityPrompt") then
						fireproximityprompt(AutoHotelPrompt)
					end
				end
				task.wait(0.08)
			end
			if AutoHotelHintPaperObtained then break end
		end

		if AutoHotelHasHintPaper() then
			AutoHotelHintPaperObtained = true
			break
		end

		local AutoHotelPaper = AutoHotelRoom50:FindFirstChild("LibraryHintPaper", true)
		if AutoHotelPaper and AutoHotelIsInRoom50(AutoHotelPaper) then
			while Toggles.AutoHotel.Value and AutoHotelIsActuallyInRoom50() and not AutoHotelHintPaperObtained and AutoHotelPaper.Parent do
				if AutoHotelHasHintPaper() then
					AutoHotelHintPaperObtained = true
					break
				end

				local AutoHotelChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
				local AutoHotelHRP = AutoHotelChar:FindFirstChild("HumanoidRootPart")
				if AutoHotelHRP then
					local AutoHotelCF = AutoHotelGetCFrame(AutoHotelPaper)
					if AutoHotelCF then
						AutoHotelHRP.CFrame = AutoHotelCF * CFrame.new(0, 5, 0)
					end
				end

				for _, AutoHotelPrompt in ipairs(AutoHotelPaper:GetDescendants()) do
					if AutoHotelPrompt:IsA("ProximityPrompt") then
						fireproximityprompt(AutoHotelPrompt)
					end
				end
				task.wait(0.08)
			end
		end
		task.wait(0.1)
	end
end

local function AutoHotelHandleSeek()
	local AutoHotelLastTriggerRoom = nil

	while Toggles.AutoHotel.Value do
		local AutoHotelCurrentRooms = workspace:FindFirstChild("CurrentRooms")
		if not AutoHotelCurrentRooms then
			task.wait(0.2)
			continue
		end

		local TriggerRoomNum = nil

		for _, Room in ipairs(AutoHotelCurrentRooms:GetChildren()) do
			local Num = tonumber(Room.Name)
			if Num and Num ~= AutoHotelLastTriggerRoom then
				local Trigger = Room:FindFirstChild("TriggerEventCollision")
					or Room:FindFirstChild("TriggerEventCollision", true)

				if Trigger then
					TriggerRoomNum = Num
					break
				end
			end
		end

		if not TriggerRoomNum then
			task.wait(0.15)
			continue
		end

		AutoHotelLastTriggerRoom = TriggerRoomNum

		AutoHotelEntityPause = true
		AutoHotelWaitForEntities(10)
		AutoHotelEntityPause = false
	end
end

Toggles.AutoHotel:OnChanged(function(AutoHotelEnabled)
	if AutoHotelConnection then
		task.cancel(AutoHotelConnection)
		AutoHotelConnection = nil
	end
	if AutoHotelLibraryConnection then
		task.cancel(AutoHotelLibraryConnection)
		AutoHotelLibraryConnection = nil
	end
	if AutoHotelLibraryRoomConnection then
		AutoHotelLibraryRoomConnection:Disconnect()
		AutoHotelLibraryRoomConnection = nil
	end
	if AutoHotelSeekConnection then
		task.cancel(AutoHotelSeekConnection)
		AutoHotelSeekConnection = nil
	end

	AutoHotelEntityPause = false
	table.clear(AutoHotelProcessedRooms)

	if not AutoHotelEnabled then return end

	if Options.AutoHotelRoomProcess then
		AutoHotelRoomProcessTime = Options.AutoHotelRoomProcess.Value
		Options.AutoHotelRoomProcess:OnChanged(function(Value)
			AutoHotelRoomProcessTime = Value
		end)
	end

	local AutoHotelCurrentRooms = workspace:FindFirstChild("CurrentRooms")
	if AutoHotelCurrentRooms then
		AutoHotelCurrentRooms.ChildAdded:Connect(function(AutoHotelChild)
			local AutoHotelNum = tonumber(AutoHotelChild.Name)
			if AutoHotelNum then
				AutoHotelProcessRoom(AutoHotelNum)
			end
		end)
	end

	AutoHotelSeekConnection = task.spawn(AutoHotelHandleSeek)

	task.spawn(function()
		while Toggles.AutoHotel.Value do
			if AutoHotelIsEntityPresent() then
				AutoHotelEntityPause = true
				while AutoHotelIsEntityPresent() and Toggles.AutoHotel.Value do
					task.wait(0.15)
				end
				AutoHotelEntityPause = false
			end
			task.wait(0.2)
		end
	end)

	AutoHotelConnection = task.spawn(function()
		while Toggles.AutoHotel.Value do
			if AutoHotelEntityPause then
				task.wait(0.1)
				continue
			end

			local AutoHotelDoor, AutoHotelRoomNum = AutoHotelGetNextClosedDoor()

			if AutoHotelDoor and AutoHotelRoomNum and Character then
				if AutoHotelRoomNum == 50 then
					if not AutoHotelLibraryConnection then
						AutoHotelLibraryConnection = task.spawn(function()
							AutoHotelRunLibrary()
							AutoHotelLibraryConnection = nil
						end)
					end
					task.wait(0.4)
				else
					AutoHotelProcessRoom(AutoHotelRoomNum)
					AutoHotelHandleKey(AutoHotelRoomNum)
					if Character and not AutoHotelEntityPause then
						Character:PivotTo(AutoHotelDoor:GetPivot() * CFrame.new(0, -1, 0))
					end
				end
			end
			task.wait(0.15)
		end
	end)
end)


Groupboxes.Debug = Tabs.General:AddRightGroupbox("Debug")
Groupboxes.Debug:AddButton({
	Text = "Ladder Softlock Fix",
	Tooltip = "Ladder Softlock Fix.",
	Func = function()
   		LocalPlayer:SetAttribute("Climbing", false)
	end
})
Groupboxes.Debug:AddButton({
	Text = "Get Current Floor",
	Tooltip = "Prints the current floor to the console.",
	Func = function()
		print("Current Floor:", GameData:WaitForChild("Floor").Value)
	end
})
Groupboxes.Debug:AddButton({
	Text = "Get Current Room",
	Tooltip = "Prints the current room number to the console.",
	Func = function()
		print("Current Room:", LocalPlayer:GetAttribute("CurrentRoom"))
	end
})
Groupboxes.Debug:AddButton({
	Text = "Void",
	Tooltip = "Teleports your character to Y -120.",
	Func = function()
		if not Character then return end
		local Pivot = Character:GetPivot()
		-- Too lazy to loop this
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
		Character:PivotTo(Pivot + Vector3.new(0, -120 - Pivot.Position.Y, 0))
	end
})
Groupboxes.Debug:AddButton({
	Text = "Death",
	Tooltip = "Death",
	Func = function()
		Globals.Deathing = true
		LocalPlayer.Character.Humanoid.Health = 0
	end
})
Groupboxes.Debug:AddButton({
	Text = "Exit Closet",
	Tooltip = "Exits the current closet.",
	Func = function()
		if RemotesFolder and RemotesFolder:FindFirstChild("CamLock") then
			RemotesFolder.CamLock:FireServer()
		end
	end
})
local TpNextDoorConnection

local function getNextClosedDoor()
	if not Character then return nil end

	local GameData = game:GetService("ReplicatedStorage"):FindFirstChild("GameData")
	if not GameData then return nil end

	local LatestRoom = GameData:FindFirstChild("LatestRoom")
	if not LatestRoom then return nil end

	local startRoom = LatestRoom.Value
	local bestDoor = nil
	local bestNumber = math.huge

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj.Name == "Door" and obj:IsA("Model") then
			local openAttr = obj:GetAttribute("Open")
			if openAttr == false or openAttr == nil then
				local roomModel = obj.Parent
				local roomNum = tonumber(roomModel and roomModel.Name)

				if roomNum and roomNum >= startRoom and roomNum < bestNumber then
					bestNumber = roomNum
					bestDoor = obj
				end
			end
		end
	end

	return bestDoor
end

Groupboxes.Debug:AddButton({
	Text = "Tp Next Door",
	Tooltip = "Teleports you to the next sequential unopened door.",
	Func = function()
		local door = getNextClosedDoor()
		if door then
			Character:PivotTo(door:GetPivot() * CFrame.new(0, -1, 0))
		end
	end
})

Toggles.TpNextDoor = Groupboxes.Debug:AddToggle("TpNextDoor", {
	Text = "Auto Tp Next Door",
	Tooltip = "Continuously teleports you to the next sequential unopened door.",
	Default = false
})

Toggles.TpNextDoor:OnChanged(function(TpNextDoorEnabled)
	if TpNextDoorConnection then
		task.cancel(TpNextDoorConnection)
		TpNextDoorConnection = nil
	end

	if not TpNextDoorEnabled then
		return
	end

	TpNextDoorConnection = task.spawn(function()
		while Toggles.TpNextDoor.Value do
			local door = getNextClosedDoor()
			if door and Character then
				Character:PivotTo(door:GetPivot() * CFrame.new(0, -1, 0))
			end
			task.wait(0.15)
		end
		TpNextDoorConnection = nil
	end)
end)


Groupboxes.Exploits_Bypass = Tabs.Exploits:AddLeftGroupbox("Bypass / Solve")

Groupboxes.Exploits_Bypass:AddToggle("BypassGiggle",         { Text = "Bypass Giggle",           Default = false, Tooltip = "Prevents 'Giggle' from attacking you." })
Groupboxes.Exploits_Bypass:AddToggle("BypassDupe",           { Text = "Bypass Dupe",             Default = false, Tooltip = "Prevents you from open 'Dupe' fake doors." })
Groupboxes.Exploits_Bypass:AddToggle("BypassEyes",           { Text = "Bypass Eyes",             Default = false, Tooltip = "Prevents 'Eyes' from hurting you." })
Groupboxes.Exploits_Bypass:AddToggle("BypassLookman",        { Text = "Bypass Lookman",          Default = false, Tooltip = "Prevents 'Lookman' from hurting you." })
Groupboxes.Exploits_Bypass:AddToggle("BypassGloombatEggs",   { Text = "Bypass Gloombat Eggs",    Default = false, Tooltip = "Prevents taking damage from stepping on 'Gloombat' eggs." })
Groupboxes.Exploits_Bypass:AddToggle("BypassSeekObstructions", { Text = "Bypass Seek Obstructions", Default = false, Tooltip = "Prevents obstacles in the 'Seek' chase from harming you." })
Groupboxes.Exploits_Bypass:AddToggle("BypassVacuum",         { Text = "Bypass Vacuum",           Default = false, Tooltip = "Prevents you from falling into 'Vacuum' fake doors." })
Groupboxes.Exploits_Bypass:AddToggle("BypassKillbricks",     { Text = "Bypass Killbricks",       Default = false, Tooltip = "Prevents 'Lava' from hurting you." })
Groupboxes.Exploits_Bypass:AddToggle("BypassSeekingWall",    { Text = "Bypass Seeking Wall",     Default = false, Tooltip = "Prevents 'ScaryWall' from hurting you." })
Groupboxes.Exploits_Bypass:AddToggle("BypassSnare",          { Text = "Bypass Snare",            Default = false, Tooltip = "Prevents 'Snare' from trapping you." })
Groupboxes.Exploits_Bypass:AddToggle("BypassBanana",         { Text = "Bypass Banana",           Default = false, Tooltip = "Prevents 'Banana Peel' from slipping you up (sometimes doesn't work)." })
Groupboxes.Exploits_Bypass:AddToggle("BypassJeff",           { Text = "Bypass Jeff",             Default = false, Tooltip = "Prevents 'Jeff the Killer' from stabbing you (sometimes doesn't work)." })


Toggles.BypassGiggle:OnChanged(function(Value)
	for _, Object in Objects.Entities do
		if Object.Name == "GiggleCeiling" then
			Object:WaitForChild("Hitbox").CanTouch = not Value
		end
	end
end)
Toggles.BypassDupe:OnChanged(function(Value)
	for _, Object in Objects.Entities do
		if Object.Name == "DoorFake" or Object.Name == "FakeDoor" then
			Object:WaitForChild("Hidden").CanTouch = not Value
			if Object:FindFirstChild("Lock") then
				Object.Lock.UnlockPrompt.Enabled = not Value
			end
		end
	end
end)
Toggles.BypassEyes:OnChanged(function(Value)
	if Value and Globals.IsEyes then
		if Floor == "Fools" or Floor == "OldHotel" then
			RemotesFolder.MotorReplication:FireServer(0, (Globals.SpoofOffset == 200 and 65 or -65), 0, false)
		else
			RemotesFolder.MotorReplication:FireServer(-650)
		end
	end
end)
Toggles.BypassLookman:OnChanged(function(Value)
	if Value and Globals.IsLookman then
		if Floor == "Fools" or Floor == "OldHotel" then
			RemotesFolder.MotorReplication:FireServer(0, (Globals.SpoofOffset == 200 and 65 or -65), 0, false)
		else
			RemotesFolder.MotorReplication:FireServer(-650)
		end
	end
end)
Toggles.BypassGloombatEggs:OnChanged(function(Value)
	for _, Object in Objects.Entities do
		for _, Part in Object:GetDescendants() do
			if Part:IsA("BasePart") then
				Part.CanTouch = not Value
			end
		end
	end
end)
Toggles.BypassSeekObstructions:OnChanged(function(Value)
	for _, Object in Objects.SeekObstructions do
		Object.CanTouch = not Value
		if Object.Name == "SeekFloodline" then
			Object.CanCollide = Value
		end
	end
	for _, Object in Objects.SeekBridges do
		Object.CanCollide = Value
		Object.Transparency = Value and 0 or 1
	end
end)
Toggles.BypassVacuum:OnChanged(function(Value)
	for _, Object in Objects.Entities do
		if Object.Name == "SideroomSpace" then
			Object:WaitForChild("Collision").CanCollide = Value
			Object:WaitForChild("Collision").CanTouch = not Value
		end
	end
end)
Toggles.BypassKillbricks:OnChanged(function(Value)
	for _, Object in Objects.Obstructions do
		if Object.Name == "Lava" then Object.CanTouch = not Value end
	end
end)
Toggles.BypassSeekingWall:OnChanged(function(Value)
	for _, Object in Objects.Obstructions do
		if Object.Name == "ScaryWall" then
			for _, Part in Object:GetDescendants() do
				if Part:IsA("BasePart") then
					Part.CanTouch = not Value
					Part.CanCollide = not Value
				end
			end
		end
	end
end)
Toggles.BypassSnare:OnChanged(function(Value)
	for _, Object in Objects.Entities do
		if Object.Name == "Snare" then
			for _, Part in Object:GetDescendants() do
				if Part:IsA("BasePart") then Part.CanTouch = not Value end
			end
		end
	end
end)
Toggles.BypassBanana:OnChanged(function(Value)
	for _, Object in Objects.Entities do
		if Object.Name == "BananaPeel" then Object.CanTouch = not Value end
	end
end)
Toggles.BypassJeff:OnChanged(function(Value)
	for _, Object in Objects.Entities do
		if Object.Name == "JeffTheKiller" then
			for _, Part in Object:GetDescendants() do
				if Part:IsA("BasePart") then
					Part.CanCollide = not Value
					Part.CanTouch = not Value
				end
			end
			Object:WaitForChild("Humanoid").Health = 0
		end
	end
end)







-- Archives

Groupboxes.Archives_Misc = Tabs.Archives:AddRightGroupbox("Exploits / Anti")
Groupboxes.Archives_Misc:AddToggle("AntiRansom", { Text = "Anti Ransom", Default = false, Tooltip = "Prevents 'Ransom' from attacking you." })
Groupboxes.Archives_Misc:AddToggle("AntiClosetTrash", { Text = "Anti Closet Trash", Default = false, Tooltip = "Prevents 'Closet Trash' from spawning." })
Groupboxes.Archives_Misc:AddToggle("ForgetMeNotSolver", { Text = "Forget Me Not Skipper", Default = false, Tooltip = "Automatically Skippes Forget Me Not doors." })
Groupboxes.Archives_Misc:AddToggle("TimeShower", { Text = "Time Shower", Default = false, Tooltip = "Shows the Archives clock time." })
Groupboxes.Archives_Misc:AddToggle("BypassDronesStampede", { Text = "Stop Time/Anti Stampede", Default = false, Tooltip = "Prevents 'The Drones Stampede' from attacking you." })
Groupboxes.Archives_Misc:AddToggle("HonchoCorrectBoxESP", { Text = "Correct Box ESP/Auto Interact", Default = false, Tooltip = "ESP correct Archives boxes in the Honcho sequence and automatically interact with the correct deposit." })

TimeShowerLabel = Instance.new("TextLabel")
TimeShowerLabel.Name = "TimeShower"
TimeShowerLabel.AnchorPoint = Vector2.new(0, 1)
TimeShowerLabel.Position = UDim2.new(0, 12, 1, -12)
TimeShowerLabel.Size = UDim2.new(0, 180, 0, 32)
TimeShowerLabel.BackgroundTransparency = 1
TimeShowerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TimeShowerLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
TimeShowerLabel.TextStrokeTransparency = 0.35
TimeShowerLabel.Font = Enum.Font.GothamBold
TimeShowerLabel.TextSize = 18
TimeShowerLabel.TextXAlignment = Enum.TextXAlignment.Left
TimeShowerLabel.Text = "Time: --:--"
TimeShowerLabel.Visible = false
TimeShowerLabel.Parent = Container



local function GetArchivesClockLabel(Room)
	local Assets = Room and Room:FindFirstChild("Assets", true)
	local Clock = Assets and Assets:FindFirstChild("ArchivesClock", true)
	local Time = Clock and Clock:FindFirstChild("Time", true)
	local TextLabel = Time and Time:FindFirstChild("TextLabel")
	return (TextLabel and TextLabel:IsA("TextLabel")) and TextLabel or nil
end

local function ResolveClockLabel()
	if TimeShowerSourceLabel and TimeShowerSourceLabel.Parent and TimeShowerSourceLabel:IsDescendantOf(game) then
		return TimeShowerSourceLabel
	end
	local currentRooms = workspace:FindFirstChild("CurrentRooms")
	if not currentRooms then return nil end
	local rooms = {}
	for _, room in ipairs(currentRooms:GetChildren()) do
		local num = tonumber(room.Name)
		if num then
			rooms[#rooms + 1] = { room = room, num = num }
		end
	end
	table.sort(rooms, function(a, b) return a.num > b.num end)
	for i = 1, math.min(6, #rooms) do
		local label = GetArchivesClockLabel(rooms[i].room)
		if label then
			TimeShowerSourceLabel = label
			return label
		end
	end
	return nil
end

local function ResolveClockRemote()
	local label = ResolveClockLabel()
	if not label then return nil end
	local clock = label:FindFirstAncestor("ArchivesClock")
	if not clock then return nil end
	local remote = clock:FindFirstChild("LookedAtRemote", true)
	return (remote and remote:IsA("RemoteEvent")) and remote or nil
end

task.spawn(function()
	local lastCheckedRoomCount = 0
	while game:IsLoaded() do
		local currentRooms = workspace:FindFirstChild("CurrentRooms")
		if currentRooms then
			local roomCount = 0
			for _, child in ipairs(currentRooms:GetChildren()) do
				if tonumber(child.Name) then
					roomCount += 1
				end
			end
			if roomCount > 0 and (lastCheckedRoomCount == 0 or roomCount - lastCheckedRoomCount >= 10) then
				ResolveClockLabel()
				lastCheckedRoomCount = roomCount
			end
		end
		task.wait(0.5)
	end
end)

local function StopTimeShower()
	TimeShowerToken += 1
	if TimeShowerConnection then
		TimeShowerConnection:Disconnect()
		TimeShowerConnection = nil
	end
	if TimeShowerLabel then
		TimeShowerLabel.Visible = false
		TimeShowerLabel.Text = "Time: --:--"
	end
end

Toggles.TimeShower:OnChanged(function(Value)
	StopTimeShower()
	if not Value then return end
	local Token = TimeShowerToken
	TimeShowerLabel.Visible = true
	TimeShowerConnection = Services.RunService.Heartbeat:Connect(function()
		if Token ~= TimeShowerToken then return end
		local TextLabel = ResolveClockLabel()
		TimeShowerLabel.Text = TextLabel and ("Time: " .. TextLabel.Text) or "Time: --:--"
	end)
end)

Toggles.BypassDronesStampede:OnChanged(function(enabled)
	if BypassDronesStampedeConnection then
		task.cancel(BypassDronesStampedeConnection)
		BypassDronesStampedeConnection = nil
	end
	if not enabled then return end
	BypassDronesStampedeConnection = task.spawn(function()
		while Toggles.BypassDronesStampede.Value do
			local remote = ResolveClockRemote()
			if remote then
				remote:FireServer()
				task.wait(0.5)
			else
				task.wait(0.25)
			end
		end
	end)
end)

local function ClearHonchoESP()
	if HonchoCorrectBoxConnection then
		HonchoCorrectBoxConnection:Disconnect()
		HonchoCorrectBoxConnection = nil
	end
	if HonchoAutoDepositConnection then
		HonchoAutoDepositConnection:Disconnect()
		HonchoAutoDepositConnection = nil
	end
	for _, Object in pairs(HonchoESPObjects) do
		if Object and Object.Parent then
			Functions.RemoveESP(Object)
		end
	end
	table.clear(HonchoESPObjects)
	table.clear(HonchoProcessedRooms)
	table.clear(HonchoDepositCache)
end

Toggles.HonchoCorrectBoxESP:OnChanged(function(Value)
	ClearHonchoESP()
	if not Value then return end
	-- DontGroup
	local CurrentRooms = workspace:FindFirstChild("CurrentRooms")
	if not CurrentRooms then return end

	local function GetESPColor()
		return (Options.ObjectiveESPColor and Options.ObjectiveESPColor.Value) or Color3.fromRGB(0, 255, 0)
	end

	local function AddHonchoESP(Object, Text)
		Functions.AddESP({ Object = Object, Text = Text, Color = GetESPColor() }, true)
		HonchoESPObjects[#HonchoESPObjects + 1] = Object
		Object.Destroying:Once(function()
			Functions.RemoveESP(Object)
			local pos = table.find(HonchoESPObjects, Object)
			if pos then table.remove(HonchoESPObjects, pos) end
		end)
	end

	local function ProcessHonchoRoom(Room)
		if not tonumber(Room.Name) or not Room.Parent or HonchoProcessedRooms[Room] then return end
		HonchoProcessedRooms[Room] = true
		task.wait(3)
		if not Toggles.HonchoCorrectBoxESP.Value or not Room.Parent then
			HonchoProcessedRooms[Room] = nil
			return
		end
		local HonchoRoom = Room:FindFirstChild("ArchivesHonchoRoom", true)
		if not HonchoRoom then
			HonchoProcessedRooms[Room] = nil
			return
		end
		local BoxIDs = {}
		local RoomNumber = tonumber(Room.Name)
		for _, Desc in ipairs(Room:GetDescendants()) do
			local name = Desc.Name
			if name == "ArchivesPackageDeposit" or name:match("^ArchivesPackageDeposit") then
				local id = Desc:GetAttribute("BoxID")
				if id ~= nil then
					local idStr = tostring(id)
					BoxIDs[idStr] = true
					HonchoDepositCache[idStr] = Desc
					AddHonchoESP(Desc, "Deposit (" .. idStr .. ")")
					Desc.Destroying:Once(function()
						if HonchoDepositCache[idStr] == Desc then
							HonchoDepositCache[idStr] = nil
						end
					end)
				end
			end
		end
		if not next(BoxIDs) then
			HonchoProcessedRooms[Room] = nil
			return
		end
		for _, Child in ipairs(HonchoRoom:GetDescendants()) do
			if Child.Name == "ArchivesStorageBox" then
				local ToolBoxID = Child:GetAttribute("Tool_BoxID")
				if ToolBoxID ~= nil and BoxIDs[tostring(ToolBoxID)] then
					if not Child:GetAttribute("ParentRoom") then
						Child:SetAttribute("ParentRoom", RoomNumber)
					end
					Child.Name = "ArchivesStorageBoxCorrect"
					AddHonchoESP(Child, "Correct Box (" .. tostring(ToolBoxID) .. ")")
				end
			end
		end
	end

	for _, Room in ipairs(CurrentRooms:GetChildren()) do
		task.spawn(ProcessHonchoRoom, Room)
	end

	HonchoCorrectBoxConnection = CurrentRooms.ChildAdded:Connect(function(Room)
		task.spawn(ProcessHonchoRoom, Room)
	end)

	local lastCheck = 0
	HonchoAutoDepositConnection = game:GetService("RunService").Heartbeat:Connect(function()
		if not Toggles.HonchoCorrectBoxESP.Value then return end
		local now = os.clock()
		if now - lastCheck < 0.1 then return end
		lastCheck = now
		local Character = LocalPlayer and LocalPlayer.Character
		local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
		if not Character or not HumanoidRootPart then return end
		local BoxCandidates = {}
		for _, Object in ipairs(Character:GetChildren()) do
			if (Object:IsA("Tool") or Object:IsA("Model")) and (Object.Name == "ArchivesStorageBox" or Object.Name == "ArchivesStorageBoxCorrect") then
				BoxCandidates[#BoxCandidates + 1] = Object
			end
		end
		local Drops = workspace:FindFirstChild("Drops")
		if Drops then
			for _, Object in ipairs(Drops:GetChildren()) do
				if Object.Name == "ArchivesStorageBox" or Object.Name == "ArchivesStorageBoxCorrect" then
					BoxCandidates[#BoxCandidates + 1] = Object
				end
			end
		end
		for _, Box in ipairs(BoxCandidates) do
			if not (Box and Box.Parent) then continue end
			local BoxID = Box:GetAttribute("Tool_BoxID") or Box:GetAttribute("BoxID")
			if BoxID == nil then continue end
			local Deposit = HonchoDepositCache[tostring(BoxID)]
			if not Deposit or not Deposit.Parent then continue end
			if Box.Parent == Drops and not Box:GetAttribute("HonchoCorrectESP") then
				Box:SetAttribute("HonchoCorrectESP", true)
				AddHonchoESP(Box, "Correct Box (" .. tostring(BoxID) .. ")")
			end
			if Box.Parent == Character then
				local DepositPart = Deposit:IsA("BasePart") and Deposit or Deposit:FindFirstChildWhichIsA("BasePart", true)
				if DepositPart and (HumanoidRootPart.Position - DepositPart.Position).Magnitude <= 10 then
					local Prompt = Deposit:FindFirstChildWhichIsA("ProximityPrompt", true)
					if Prompt then
						fireproximityprompt(Prompt)
					end
				end
			end
		end
	end)
end)


Groupboxes.Archives_Bypasses = Tabs.Archives:AddLeftGroupbox("Bypasses")
Groupboxes.Archives_Bypasses:AddToggle("BypassWater", { Text = "Bypass Electric Water", Default = false, Tooltip = "Prevents electric water from hurting you." })
Groupboxes.Archives_Bypasses:AddToggle("BypassAlma", { Text = "Bypass Alma", Default = false, Tooltip = "Prevents 'Alma' from spawning." })
Groupboxes.Archives_Bypasses:AddToggle("BypassDrones", { Text = "Bypass Drones", Default = false, Tooltip = "Prevents 'Drones' from attacking you." })
Groupboxes.Archives_Bypasses:AddToggle("AntiScribbles", { Text = "Bypass Scribbles", Default = false, Tooltip = "Prevents 'Scribbles' from attacking you." })

Groupboxes.Archives_Experimental = Tabs.Archives:AddLeftGroupbox("Experimental")

Toggles.AntiClosetTrash:OnChanged(function(Value)
	if AntiClosetTrash_Connection then
		AntiClosetTrash_Connection:Disconnect()
		AntiClosetTrash_Connection = nil
	end
	if not Value then return end
	AntiClosetTrash_Connection = workspace.ChildAdded:Connect(function(Child)
		if not Toggles.AntiClosetTrash.Value then return end
		local Name = Child.Name
		if Name:sub(1, 6) == "Binder" or Name:sub(1, 4) == "Shoe" or Name:sub(1, 5) == "Shelf" then
			Child:Destroy()
		end
	end)
end)

Toggles.AntiRansom:OnChanged(function(Value)
	if AntiRansom_Connection then
		AntiRansom_Connection:Disconnect()
		AntiRansom_Connection = nil
	end
	if not Value then return end
	AntiRansom_Connection = workspace.ChildAdded:Connect(function(Child)
		if Child.Name == "Ransom" and Toggles.AntiRansom.Value then
			Child:Destroy()
			print("Ransom gone hehehehehehehehe")
		end
	end)
end)

Toggles.ForgetMeNotSolver:OnChanged(function(Value)
	if ForgetMeNotConnection then
		ForgetMeNotConnection:Disconnect()
		ForgetMeNotConnection = nil
	end
	ForgetMeNotRunning = false
	table.clear(ForgetMeNotProcessing)
	table.clear(ForgetMeNotNotified)
	if not Value then return end
	ForgetMeNotRunning = true

	local function GetCharacter()
		return game.Players.LocalPlayer.Character or game.Players.LocalPlayer.CharacterAdded:Wait()
	end

	local function GetNextRoom(Number)
		while ForgetMeNotRunning do
			for RoomNumber = Number + 1, Number + 5 do
				local NextRoom = workspace.CurrentRooms:FindFirstChild(tostring(RoomNumber))
				if NextRoom then return NextRoom end
			end
			task.wait(0.1)
		end
		return nil
	end

	local function FireLookAts(Room)
		for i = 1, 6 do
			local Obj = Room:FindFirstChild(tostring(i))
			if Obj then
				local LookAt = Obj:FindFirstChild("LookAt")
				if LookAt then
					pcall(function() LookAt:FireServer() end)
				end
			end
		end
	end

	local function VoidCharacter()
		local Character = GetCharacter()
		if not Character then return end

		local voidCF = CFrame.new(0, -120, 0)
		local start = tick()
		while ForgetMeNotRunning and tick() - start < 2 do
			Character:PivotTo(voidCF)
			task.wait(0.1)
		end
	end

	local function Run(Room)
		local RoomNumber = tonumber(Room.Name)
		if not RoomNumber or not ForgetMeNotRunning or ForgetMeNotProcessing[RoomNumber] then return end

		if not Room:FindFirstChild("ForgetMeNotVineDoors", true) then
			return
		end

		ForgetMeNotProcessing[RoomNumber] = true

		while ForgetMeNotRunning and Room.Parent do
			FireLookAts(Room)

			local NextRoom = GetNextRoom(RoomNumber)
			if not NextRoom then
				task.wait(0.4)
				continue
			end

			local Door = NextRoom:FindFirstChild("Door")

			if not Door then
				local Character = GetCharacter()
				if Character then
					local Target = NextRoom:FindFirstChildWhichIsA("BasePart") or NextRoom
					if Target:IsA("BasePart") then
						Character:PivotTo(Target.CFrame + Vector3.new(0, 3, 0))
					elseif Target:IsA("Model") then
						Character:PivotTo(Target:GetPivot() + Vector3.new(0, 3, 0))
					else
						Character:PivotTo(CFrame.new(NextRoom:GetPivot().Position + Vector3.new(0, 5, 0)))
					end
				end
				break
			end

			if Door:GetAttribute("Opened") == true then
				VoidCharacter()
				break
			end

			local Hidden = Door:FindFirstChild("Hidden") or Door:WaitForChild("Hidden", 2)
			if not Hidden then
				task.wait(0.3)
				continue
			end

			while ForgetMeNotRunning and Room.Parent and NextRoom.Parent and Door.Parent and Door:GetAttribute("Opened") ~= true do
				local Character = GetCharacter()
				if Character then
					if Hidden:IsA("BasePart") then
						Character:PivotTo(Hidden.CFrame)
					elseif Hidden:IsA("Model") then
						Character:PivotTo(Hidden:GetPivot())
					end
				end
				pcall(function() Door.ClientOpen:Fire() end)
				pcall(function() Door.ClientOpen:FireServer() end)
				task.wait()
			end

			if ForgetMeNotRunning and Door.Parent and Door:GetAttribute("Opened") == true then
				VoidCharacter()
			end

			break
		end

		ForgetMeNotProcessing[RoomNumber] = nil
	end

	local function CheckRooms()
		local LatestRoomNumber = tonumber(LatestRoom.Value) or 0
		local FirstRoomNumber = math.max(0, LatestRoomNumber - 3)
		for RoomNumber = FirstRoomNumber, LatestRoomNumber do
			if not ForgetMeNotRunning then return end
			local Room = workspace.CurrentRooms:FindFirstChild(tostring(RoomNumber))
			if Room and not ForgetMeNotProcessing[RoomNumber] then
				task.spawn(Run, Room)
			end
		end
	end

	ForgetMeNotConnection = workspace.CurrentRooms.ChildAdded:Connect(function(Room)
		if not tonumber(Room.Name) then return end
		task.spawn(function()
			task.wait(1)
			if ForgetMeNotRunning and Room.Parent then
				task.spawn(Run, Room)
			end
		end)
	end)

	task.spawn(function()
		while ForgetMeNotRunning do
			CheckRooms()
			task.wait(1)
		end
	end)

	CheckRooms()
end)

Toggles.BypassWater:OnChanged(function(Value)
	if Value then Functions.Notify({ Title = "Position Spoof is switched off automatically near electric water" }) end

	if WaterBypassConnection then
		WaterBypassConnection:Disconnect()
		WaterBypassConnection = nil
	end

	if not Value then
		for _, WaterBypassPart in pairs(WaterParts) do
			if WaterBypassPart then
				WaterBypassPart:Destroy()
			end
		end
		table.clear(WaterParts)
		return
	end
	-- DontGroup
	local CurrentRooms = workspace.CurrentRooms

	local function ProcessWaterBypassRoom(WaterBypassRoom)
		if not tonumber(WaterBypassRoom.Name) then return end

		task.wait(3)

		local WaterBypassWater = WaterBypassRoom:FindFirstChild("Water")
		if not WaterBypassWater or WaterParts[WaterBypassWater] then return end

		local WaterBypassPart = Instance.new("Part")
		WaterBypassPart.Name = "WaterBypass"
		WaterBypassPart.Anchored = true
		WaterBypassPart.CanCollide = true
		WaterBypassPart.CanTouch = false
		WaterBypassPart.CanQuery = false
		WaterBypassPart.Transparency = 0.25
		WaterBypassPart.Color = Color3.fromRGB(0, 150, 255)
		WaterBypassPart.Material = Enum.Material.ForceField

		local WaterBypassSize, WaterBypassCFrame
		if WaterBypassWater:IsA("BasePart") then
			WaterBypassSize = WaterBypassWater.Size
			WaterBypassCFrame = WaterBypassWater.CFrame
		elseif WaterBypassWater:IsA("Model") then
			WaterBypassCFrame, WaterBypassSize = WaterBypassWater:GetBoundingBox()
		else
			WaterBypassSize = Vector3.new(10, 1.5, 10)
			WaterBypassCFrame = WaterBypassWater:GetPivot()
		end

		WaterBypassPart.Size = WaterBypassSize + Vector3.new(0, 0.5, 0)
		WaterBypassPart.CFrame = WaterBypassCFrame * CFrame.new(0, 0.25, 0)

		if WaterBypassPart.Size.Y > 3 then
			WaterBypassPart:Destroy()
			Functions.Notify({ Title = "Water Bypass removed: Softlock." })
			return
		end

		WaterBypassPart.Parent = WaterBypassRoom
		WaterParts[WaterBypassWater] = WaterBypassPart
	end

	local WaterBypassLatestRoomNumber = tonumber(LatestRoom.Value) or 0
	for WaterBypassRoomNumber = math.max(0, WaterBypassLatestRoomNumber - 4), WaterBypassLatestRoomNumber do
		local WaterBypassRoom = CurrentRooms:FindFirstChild(tostring(WaterBypassRoomNumber))
		if WaterBypassRoom then
			task.spawn(ProcessWaterBypassRoom, WaterBypassRoom)
		end
	end

	WaterBypassConnection = CurrentRooms.ChildAdded:Connect(function(WaterBypassRoom)
		task.spawn(ProcessWaterBypassRoom, WaterBypassRoom)
	end)
end)

Toggles.BypassAlma:OnChanged(function(Value)
	if AlmaConnection then
		AlmaConnection:Disconnect()
		AlmaConnection = nil
	end
	if Value then
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name == "Alma" then child:Destroy() end
		end
		AlmaConnection = workspace.ChildAdded:Connect(function(child)
			if child.Name == "Alma" then child:Destroy() end
		end)
	end
end)

Toggles.AntiScribbles:OnChanged(function(Value)
	if AntiScribbles_Connection then
		AntiScribbles_Connection:Disconnect()
		AntiScribbles_Connection = nil
	end
	if not Value then return end
	AntiScribbles_Connection = workspace.ChildAdded:Connect(function(Child)
		if Child.Name == "Scribbles" and Toggles.AntiScribbles.Value then
			local ExploitSribbleWarning = Child:FindFirstChild("IfYoureExploitingDeleteThis")
			if ExploitSribbleWarning then ExploitSribbleWarning:Destroy() end
		end
	end)
end)

Toggles.BypassDrones:OnChanged(function(Value)
	local RS = game:GetService("ReplicatedStorage")
	local function ProcessDrones(drones)
		local WalkedInto = drones:FindFirstChild("WalkedInto") or drones:WaitForChild("WalkedInto", 3)
		if WalkedInto and not DroneWalkedIntoParents[WalkedInto] then
			DroneWalkedIntoParents[WalkedInto] = drones
			WalkedInto.Parent = RS
		end
	end
	if Value then
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name == "Drones" then ProcessDrones(child) end
		end
		if DroneConnection then DroneConnection:Disconnect() end
		DroneConnection = workspace.ChildAdded:Connect(function(child)
			if child.Name == "Drones" then ProcessDrones(child) end
		end)
	else
		for WalkedInto, originalParent in pairs(DroneWalkedIntoParents) do
			if WalkedInto and WalkedInto.Parent and originalParent and originalParent.Parent then
				WalkedInto.Parent = originalParent
			end
		end
		table.clear(DroneWalkedIntoParents)
		if DroneConnection then
			DroneConnection:Disconnect()
			DroneConnection = nil
		end
	end
end)

Groupboxes.Stairwell_Misc = Tabs.Stairwell:AddLeftGroupbox("Exploits / Anti / Misc")



Groupboxes.Stairwell_Misc:AddDivider()
Groupboxes.Stairwell_Misc:AddToggle("BypassNoise", { Text = "Noise Tv Breaker", Default = false, Tooltip = "Breaks the tv of noise while holding it." })
Groupboxes.Stairwell_Misc:AddToggle("AntiNoise", { Text = "Anti Noise", Default = false, Tooltip = "Prevents the game from making noise when moving (Visual studio auto ai lmfao ✌)." })
Groupboxes.Stairwell_Misc:AddToggle("AntiHeavilyItems", {
	Text = "Anti Heavily Items",
	Default = false,
	Tooltip = "Returns forced DontUnequip tools that did not come from your Backpack."
})

do
	local CharacterConnections = {}

	local function DisconnectCharacterConnections()
		for _, Connection in CharacterConnections do
			pcall(function() Connection:Disconnect() end)
		end
		table.clear(CharacterConnections)
	end

	local function SetupCharacter(NewCharacter)
		DisconnectCharacterConnections()
		if Library.Unloaded or not Toggles.AntiHeavilyItems.Value then return end

		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
		if not NewCharacter or not Backpack then return end

		local CameFromBackpack = {}
		local function MarkBackpackTool(Child)
			if Child:IsA("Tool") then CameFromBackpack[Child] = true end
		end

		for _, Child in Backpack:GetChildren() do MarkBackpackTool(Child) end
		CharacterConnections[#CharacterConnections + 1] = Backpack.ChildAdded:Connect(MarkBackpackTool)
		CharacterConnections[#CharacterConnections + 1] = Backpack.ChildRemoved:Connect(function(Child)
			task.delay(0.5, function()
				CameFromBackpack[Child] = nil
			end)
		end)
		CharacterConnections[#CharacterConnections + 1] = NewCharacter.ChildAdded:Connect(function(Child)
			if Library.Unloaded or Globals.FPVChairActive or not Toggles.AntiHeavilyItems.Value then return end
			if not Child:IsA("Tool") or not Child:GetAttribute("DontUnequip") then return end
			if CameFromBackpack[Child] then
				CameFromBackpack[Child] = nil
				return
			end

			task.defer(function()
				if not Library.Unloaded and Toggles.AntiHeavilyItems.Value and Child.Parent == NewCharacter then
					Child.Parent = Backpack
				end
			end)
		end)
	end

	Toggles.AntiHeavilyItems:OnChanged(function(Value)
		if Value then
			SetupCharacter(LocalPlayer.Character)
		else
			DisconnectCharacterConnections()
		end
	end)
	Connections.AntiHeavilyItemsCharacterHandler = LocalPlayer.CharacterAdded:Connect(function(NewCharacter)
		if Toggles.AntiHeavilyItems.Value then SetupCharacter(NewCharacter) end
	end)
	Library:OnUnload(DisconnectCharacterConnections)
end


Groupboxes.Stairwell_Misc:AddToggle("DroppedItemValue", { Text = "Item Number", Default = false, Tooltip = "Shows the number of dropped items." })

Groupboxes.Stairwell_Misc:AddToggle("KillAllWithCart", {
	Text = "Kill All (Requires ≥1 Cart)",
	Default = false,
})
Groupboxes.Stairwell_Misc:AddToggle("FlingCreak", {
	Text = "Bug Out Creak (Requires ≥5 Cart)",
	Default = false,
	ToolTip = "DONT TOUCH THE CARTS URSELF, U WILL DIE"
})
Groupboxes.Stairwell_Misc:AddToggle("CreakAggressionMeter", {
    Text = "Creak Aggression Meter",
    Default = false,
    Tooltip = "Shows Creak's aggression above its head."
})

local CreakAggressionMetersTable = {}
local CreakAggressionCamera = Workspace.CurrentCamera
local CreakAggressionChildAddedConnection = nil

local function CleanupCreakAggressionMeter(CreakModel)
    local CreakMeterData = CreakAggressionMetersTable[CreakModel]
    if not CreakMeterData then return end

    CreakAggressionMetersTable[CreakModel] = nil

    if CreakMeterData.RenderConnection then
        CreakMeterData.RenderConnection:Disconnect()
    end
    if CreakMeterData.DestroyConnection then
        CreakMeterData.DestroyConnection:Disconnect()
    end

    for _, CreakDrawingObject in ipairs(CreakMeterData.Drawings) do
        pcall(function() CreakDrawingObject:Remove() end)
    end
end

local function GetCreakAggressionValue(CreakModel)
    local CreakAnimator = CreakModel:FindFirstChildOfClass("Animator")
        or (CreakModel:FindFirstChild("AnimationController") and CreakModel.AnimationController:FindFirstChildOfClass("Animator"))
        or CreakModel:FindFirstChildOfClass("AnimationController")

    if not CreakAnimator then return nil end

    for _, CreakAnimationTrack in ipairs(CreakAnimator:GetPlayingAnimationTracks()) do
        if CreakAnimationTrack.Name == "CreakGraph" or (CreakAnimationTrack.Animation and CreakAnimationTrack.Animation.Name == "CreakGraph") then
            local CreakSuccess, CreakAggressionValue = pcall(CreakAnimationTrack.GetParameter, CreakAnimationTrack, "Aggression")
            if CreakSuccess and typeof(CreakAggressionValue) == "number" then
                return math.clamp(CreakAggressionValue, 0, 1)
            end
        end
    end
    return nil
end

local function CreateCreakAggressionDrawings()
    local CreakDrawingList = {}

    local function CreateCreakDrawing(CreakDrawingType)
        local CreakNewDrawing = Drawing.new(CreakDrawingType)
        table.insert(CreakDrawingList, CreakNewDrawing)
        return CreakNewDrawing
    end

    local CreakTitleText = CreateCreakDrawing("Text")
    CreakTitleText.Text = "Aggression --%"
    CreakTitleText.Size = 16
    CreakTitleText.Font = Drawing.Fonts.Plex
    CreakTitleText.Color = Color3.fromRGB(255, 255, 255)
    CreakTitleText.Center = true
    CreakTitleText.Outline = true
    CreakTitleText.Visible = false

    local CreakBarBackground = CreateCreakDrawing("Square")
    CreakBarBackground.Size = Vector2.new(112, 6)
    CreakBarBackground.Filled = true
    CreakBarBackground.Color = Color3.fromRGB(58, 58, 64)
    CreakBarBackground.Transparency = 0.15
    CreakBarBackground.Visible = false

    local CreakBarFill = CreateCreakDrawing("Square")
    CreakBarFill.Size = Vector2.new(0, 6)
    CreakBarFill.Filled = true
    CreakBarFill.Visible = false

    return {
        Drawings = CreakDrawingList,
        TitleText = CreakTitleText,
        BarBackground = CreakBarBackground,
        BarFill = CreakBarFill
    }
end

local function AddCreakAggressionMeter(CreakModel)
    if not Toggles.CreakAggressionMeter.Value or CreakModel.Name ~= "Creak" or CreakAggressionMetersTable[CreakModel] then
        return
    end

    local CreakHeadPart = CreakModel:FindFirstChild("Head")
    if not CreakHeadPart or not CreakHeadPart:IsA("BasePart") then return end

    local CreakMeterData = CreateCreakAggressionDrawings()
    CreakAggressionMetersTable[CreakModel] = CreakMeterData

    CreakMeterData.RenderConnection = RunService.RenderStepped:Connect(function()
        if not Toggles.CreakAggressionMeter.Value or not CreakModel.Parent or not CreakHeadPart.Parent then
            CleanupCreakAggressionMeter(CreakModel)
            return
        end

        if not CreakAggressionCamera or not CreakAggressionCamera.Parent then
            CreakAggressionCamera = Workspace.CurrentCamera
            if not CreakAggressionCamera then return end
        end

        local CreakScreenPosition, CreakIsOnScreen = CreakAggressionCamera:WorldToViewportPoint(CreakHeadPart.Position + Vector3.new(0, 1.85, 0))
        if not (CreakIsOnScreen and CreakScreenPosition.Z > 0) then
            CreakMeterData.TitleText.Visible = false
            CreakMeterData.BarBackground.Visible = false
            CreakMeterData.BarFill.Visible = false
            return
        end

        CreakMeterData.TitleText.Position = Vector2.new(CreakScreenPosition.X, CreakScreenPosition.Y - 28)
        CreakMeterData.BarBackground.Position = Vector2.new(CreakScreenPosition.X - 56, CreakScreenPosition.Y - 6)
        CreakMeterData.BarFill.Position = CreakMeterData.BarBackground.Position

        local CreakAggressionValue = GetCreakAggressionValue(CreakModel)

        if not CreakAggressionValue then
            CreakMeterData.TitleText.Text = "Aggression --%"
            CreakMeterData.TitleText.Color = Color3.fromRGB(200, 200, 200)
            CreakMeterData.BarFill.Size = Vector2.new(0, 6)
            CreakMeterData.TitleText.Visible = true
            CreakMeterData.BarBackground.Visible = true
            CreakMeterData.BarFill.Visible = false
            return
        end

        CreakMeterData.TitleText.Text = "Aggression " .. math.floor(CreakAggressionValue * 100 + 0.5) .. "%"
        CreakMeterData.TitleText.Color = Color3.fromRGB(255, 255, 255)
        CreakMeterData.BarFill.Size = Vector2.new(112 * CreakAggressionValue, 6)
        CreakMeterData.BarFill.Color = Color3.fromRGB(70, 220, 100):Lerp(Color3.fromRGB(255, 55, 55), CreakAggressionValue)
        CreakMeterData.TitleText.Visible = true
        CreakMeterData.BarBackground.Visible = true
        CreakMeterData.BarFill.Visible = true
    end)

    CreakMeterData.DestroyConnection = CreakModel.Destroying:Connect(function()
        CleanupCreakAggressionMeter(CreakModel)
    end)
end

local function StartCreakAggressionListener()
    if CreakAggressionChildAddedConnection then return end

    local CreakLiveEntitiesFolder = Workspace:FindFirstChild("LiveEntities")
    if not CreakLiveEntitiesFolder then return end

    CreakAggressionChildAddedConnection = CreakLiveEntitiesFolder.ChildAdded:Connect(function(CreakNewChild)
        if CreakNewChild.Name == "Creak" then
            AddCreakAggressionMeter(CreakNewChild)
        end
    end)
end

local function StopCreakAggressionListener()
    if CreakAggressionChildAddedConnection then
        CreakAggressionChildAddedConnection:Disconnect()
        CreakAggressionChildAddedConnection = nil
    end
end

Toggles.CreakAggressionMeter:OnChanged(function(CreakToggleEnabled)
    if CreakToggleEnabled then
        for _, CreakEntityModel in ipairs(Objects.Entities or {}) do
            AddCreakAggressionMeter(CreakEntityModel)
        end

        local CreakLiveEntitiesFolder = Workspace:FindFirstChild("LiveEntities")
        local CreakExistingModel = CreakLiveEntitiesFolder and CreakLiveEntitiesFolder:FindFirstChild("Creak")
        if CreakExistingModel then
            AddCreakAggressionMeter(CreakExistingModel)
        end

        StartCreakAggressionListener()
    else
        StopCreakAggressionListener()

        for CreakEntityModel in pairs(CreakAggressionMetersTable) do
            CleanupCreakAggressionMeter(CreakEntityModel)
        end
    end
end)

Toggles.KillAllWithCart:OnChanged(function(KillAllWithCartState)
	if not KillAllWithCartState then return end

	local KillAllWithCartIndex = 1

	task.spawn(function()
		while Toggles.KillAllWithCart.Value do
			local KillAllWithCartCarts = {}
			for _, KillAllWithCartModel in ipairs(workspace.Misc:GetChildren()) do
				if KillAllWithCartModel.Name == "ShoppingCart" and KillAllWithCartModel:IsA("Model") then
					KillAllWithCartCarts[#KillAllWithCartCarts + 1] = KillAllWithCartModel
				end
			end

			local KillAllWithCartAlivePlayers = {}
			for _, KillAllWithCartPlayer in ipairs(game.Players:GetPlayers()) do
				if KillAllWithCartPlayer ~= game.Players.LocalPlayer and KillAllWithCartPlayer.Character then
					local KillAllWithCartHumanoid = KillAllWithCartPlayer.Character:FindFirstChildOfClass("Humanoid")
					if KillAllWithCartHumanoid and KillAllWithCartHumanoid.Health > 0 then
						KillAllWithCartAlivePlayers[#KillAllWithCartAlivePlayers + 1] = KillAllWithCartPlayer
					end
				end
			end

			if #KillAllWithCartCarts > 0 and #KillAllWithCartAlivePlayers > 0 then
				if KillAllWithCartIndex > #KillAllWithCartAlivePlayers then
					KillAllWithCartIndex = 1
				end
				local KillAllWithCartTarget = KillAllWithCartAlivePlayers[KillAllWithCartIndex]
				local KillAllWithCartTargetCFrame = KillAllWithCartTarget.Character:GetPivot()
				for KillAllWithCartCartIndex = 1, #KillAllWithCartCarts do
					KillAllWithCartCarts[KillAllWithCartCartIndex]:PivotTo(KillAllWithCartTargetCFrame)
				end
				KillAllWithCartIndex = KillAllWithCartIndex + 1
			end
			task.wait(0)
		end
	end)
end)

Toggles.FlingCreak:OnChanged(function(FlingCreakState)
	if not FlingCreakState then return end

	task.spawn(function()
		while Toggles.FlingCreak.Value do
			local creak = workspace:FindFirstChild("LiveEntities") and workspace.LiveEntities:FindFirstChild("Creak")
			if creak then
				local targetCFrame = creak:GetPivot()
				for _, model in ipairs(workspace.Misc:GetChildren()) do
					if model.Name == "ShoppingCart" and model:IsA("Model") then
						model:PivotTo(targetCFrame)
					end
				end
			end
			task.wait(0.10)
		end
	end)
end)




Groupboxes.Stairwell_Misc:AddDivider()


Groupboxes.Stairwell_Misc:AddToggle("DisableStairwellCrusherCollision", {
	Text = "Disable Crushers",
	Default = false,
})
Groupboxes.Stairwell_Misc:AddToggle("DeleteStairwellCrusherExceptBasicWall", {
	Text = "Delete Crushers",
	Default = false,
})
Groupboxes.Stairwell_Misc:AddToggle("MeldRemover", {
	Text = "Remove Meld",
	Default = false,
})

Groupboxes.Stairwell_Misc:AddToggle("StairwellLandingSpam", {
	Text = "TP to trash and drop trash.",
	Tooltip = "Combine with orbit, or bring all dropped items.",
	Default = false,
})

Toggles.DisableStairwellCrusherCollision:OnChanged(function(DisableStairwellCrusherCollisionState)
	if not DisableStairwellCrusherCollisionState then return end

	task.spawn(function()
		while Toggles.DisableStairwellCrusherCollision.Value do
			for _, DisableStairwellCrusherRoom in ipairs(workspace.CurrentRooms:GetChildren()) do
				local DisableStairwellCrusherAssets = DisableStairwellCrusherRoom:FindFirstChild("Assets")
				if DisableStairwellCrusherAssets then
					for _, DisableStairwellCrusherContainer in ipairs(DisableStairwellCrusherAssets:GetChildren()) do
						if DisableStairwellCrusherContainer.Name == "StairwellCrusherContainer1" then
							for _, DisableStairwellCrusherDescendant in ipairs(DisableStairwellCrusherContainer:GetDescendants()) do
								if DisableStairwellCrusherDescendant:IsA("BasePart") and DisableStairwellCrusherDescendant.CanCollide then
									local DisableStairwellCrusherUnderBasicWall = false
									local DisableStairwellCrusherParent = DisableStairwellCrusherDescendant.Parent
									while DisableStairwellCrusherParent and DisableStairwellCrusherParent ~= DisableStairwellCrusherContainer do
										if DisableStairwellCrusherParent.Name == "BasicWall" then
											DisableStairwellCrusherUnderBasicWall = true
											break
										end
										DisableStairwellCrusherParent = DisableStairwellCrusherParent.Parent
									end
									if not DisableStairwellCrusherUnderBasicWall then
										DisableStairwellCrusherDescendant.CanCollide = false
									end
								end
							end
						end

						local DisableStairwellCrusher = DisableStairwellCrusherContainer:FindFirstChild("StairwellCrusher")
						if DisableStairwellCrusher then
							local DisableStairwellCrusherOuterTrigger = DisableStairwellCrusher:FindFirstChild("OuterTrigger")
							local DisableStairwellCrusherCoreTrigger = DisableStairwellCrusher:FindFirstChild("CoreTrigger")
							if DisableStairwellCrusherOuterTrigger then
								DisableStairwellCrusherOuterTrigger:Destroy()
							end
							if DisableStairwellCrusherCoreTrigger then
								DisableStairwellCrusherCoreTrigger:Destroy()
							end
						end
					end
				end
			end
			task.wait(0.5)
		end
	end)
end)
Toggles.DeleteStairwellCrusherExceptBasicWall:OnChanged(function(DeleteStairwellCrusherExceptBasicWallState)
	if not DeleteStairwellCrusherExceptBasicWallState then return end

	task.spawn(function()
		while Toggles.DeleteStairwellCrusherExceptBasicWall.Value do
			for _, DeleteStairwellCrusherRoom in ipairs(workspace.CurrentRooms:GetChildren()) do
				local DeleteStairwellCrusherAssets = DeleteStairwellCrusherRoom:FindFirstChild("Assets")
				if DeleteStairwellCrusherAssets then
					for _, DeleteStairwellCrusherContainer in ipairs(DeleteStairwellCrusherAssets:GetChildren()) do
						if DeleteStairwellCrusherContainer.Name == "StairwellCrusherContainer1" then
							local DeleteStairwellCrusherToDestroy = {}
							for _, DeleteStairwellCrusherDescendant in ipairs(DeleteStairwellCrusherContainer:GetDescendants()) do
								local DeleteStairwellCrusherUnderBasicWall = false
								local DeleteStairwellCrusherParent = DeleteStairwellCrusherDescendant.Parent
								while DeleteStairwellCrusherParent and DeleteStairwellCrusherParent ~= DeleteStairwellCrusherContainer do
									if DeleteStairwellCrusherParent.Name == "BasicWall" then
										DeleteStairwellCrusherUnderBasicWall = true
										break
									end
									DeleteStairwellCrusherParent = DeleteStairwellCrusherParent.Parent
								end
								if not DeleteStairwellCrusherUnderBasicWall and DeleteStairwellCrusherDescendant.Name ~= "BasicWall" then
									DeleteStairwellCrusherToDestroy[#DeleteStairwellCrusherToDestroy + 1] = DeleteStairwellCrusherDescendant
								end
							end
							for _, DeleteStairwellCrusherInstance in ipairs(DeleteStairwellCrusherToDestroy) do
								if DeleteStairwellCrusherInstance and DeleteStairwellCrusherInstance.Parent then
									DeleteStairwellCrusherInstance:Destroy()
								end
							end
						end
					end
				end
			end
			task.wait(0.5)
		end
	end)
end)

Toggles.MeldRemover:OnChanged(function(State)
	if not State then return end
	task.spawn(function()
		while Toggles.MeldRemover.Value do
			for _, room in pairs(workspace.CurrentRooms:GetChildren()) do
				for _, folderName in ipairs({"Assets", "Parts"}) do
					local folder = room:FindFirstChild(folderName)
					if folder then
						for _, child in ipairs(folder:GetChildren()) do
							if child.Name == "MeldWall"
								or child.Name == "Boleahghth29tdgfhy2thuy2htuu259uhh3u" -- no qeustions asked
							then
								child:Destroy()
							end
						end
					end
				end
				for _, name in ipairs({"MeldData", "MeldPads", "Meldview", "Meld"}) do
					local obj = room:FindFirstChild(name)
					if obj and obj:IsA("Folder") then
						obj:Destroy()
					end
				end
			end
			task.wait(0.5)
		end
	end)
end)




local StairwellLandingToken = 0

Toggles.StairwellLandingSpam:OnChanged(function(Value)
	StairwellLandingToken += 1

	if not Value then
		return
	end

	local CurrentToken = StairwellLandingToken

	task.spawn(function()
		-- DontGroup
		local CurrentRooms = workspace.CurrentRooms
		local LocalPlayer = Services.Players.LocalPlayer

		while Toggles.StairwellLandingSpam.Value and CurrentToken == StairwellLandingToken do
			local StairwellModels = {}

			for _, Room in ipairs(CurrentRooms:GetChildren()) do
				local StairwellLandingLogic = Room:FindFirstChild("StairwellLandingLogic")

				if StairwellLandingLogic then
					for _, Model in ipairs(StairwellLandingLogic:GetChildren()) do
						if Model:IsA("Model") then
							local Prompts = {}

							for _, Object in ipairs(Model:GetDescendants()) do
								if Object:IsA("ProximityPrompt") then
									Prompts[#Prompts + 1] = Object
								end
							end

							if #Prompts > 0 then
								StairwellModels[#StairwellModels + 1] = {
									Model = Model,
									Prompts = Prompts,
								}
							end
						end
					end
				end
			end

			table.sort(StairwellModels, function(First, Second)
				local FirstRoom = First.Model.Parent and First.Model.Parent.Parent
				local SecondRoom = Second.Model.Parent and Second.Model.Parent.Parent

				return (tonumber(FirstRoom and FirstRoom.Name) or math.huge) <
					(tonumber(SecondRoom and SecondRoom.Name) or math.huge)
			end)

			for _, Data in ipairs(StairwellModels) do
				if not Toggles.StairwellLandingSpam.Value or CurrentToken ~= StairwellLandingToken then
					break
				end

				local Model = Data.Model

				while Model.Parent
					and Model:IsDescendantOf(workspace)
					and Toggles.StairwellLandingSpam.Value
					and CurrentToken == StairwellLandingToken do

					local Character = LocalPlayer.Character
					local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")

					if HumanoidRootPart then
						HumanoidRootPart.CFrame = Model:GetPivot() + Vector3.new(0, 5, 0)

						for Index = 1, #Data.Prompts do
							local Prompt = Data.Prompts[Index]

							if Prompt.Parent and Prompt.Enabled and fireproximityprompt then
								fireproximityprompt(Prompt)
							end
						end

						if keypress and keyrelease then
							keypress(0x58)
							task.wait(0.03)
							keyrelease(0x58)
						elseif Abysall
							and Abysall.Environment
							and Abysall.Environment.keypress
							and Abysall.Environment.keyrelease then

							Abysall.Environment.keypress(0x58)
							task.wait(0.03)
							Abysall.Environment.keyrelease(0x58)
						end
					end

					Services.RunService.Heartbeat:Wait()
				end
			end

			Services.RunService.Heartbeat:Wait()
		end
	end)
end)


Groupboxes.Stairwell_Misc:AddDivider()

Groupboxes.Stairwell_Misc:AddButton("TP Shopping Carts To Player", function()
	local ShoppingCartTargetName = Options.ShoppingCartTarget.Value
	local ShoppingCartTargetPlayer = game.Players:FindFirstChild(ShoppingCartTargetName)
	if not ShoppingCartTargetPlayer or not ShoppingCartTargetPlayer.Character then return end
	local ShoppingCartTargetCFrame = ShoppingCartTargetPlayer.Character:GetPivot()
	for _, ShoppingCartModel in ipairs(workspace.Misc:GetChildren()) do
		if ShoppingCartModel.Name == "ShoppingCart" and ShoppingCartModel:IsA("Model") then
			ShoppingCartModel:PivotTo(ShoppingCartTargetCFrame)
		end
	end
end)

Groupboxes.Stairwell_Misc:AddDropdown("ShoppingCartTarget", {
	Text = "Shopping Cart Target",
	Values = (function()
		local ShoppingCartPlayerNames = {}
		for _, ShoppingCartPlayer in ipairs(game.Players:GetPlayers()) do
			ShoppingCartPlayerNames[#ShoppingCartPlayerNames + 1] = ShoppingCartPlayer.Name
		end
		return ShoppingCartPlayerNames
	end)(),
	Default = game.Players.LocalPlayer.Name,
})

Groupboxes.Stairwell_Misc:AddButton("Refresh Players", function()
	local ShoppingCartPlayerNames = {}
	for _, ShoppingCartPlayer in ipairs(game.Players:GetPlayers()) do
		ShoppingCartPlayerNames[#ShoppingCartPlayerNames + 1] = ShoppingCartPlayer.Name
	end
	Options.ShoppingCartTarget:SetValues(ShoppingCartPlayerNames)
end)

Groupboxes.Stairwell_Experimental = Tabs.Stairwell:AddRightGroupbox("Experimental")


local function TPDropsToNearestGrinder()
    local TPDropsToNearestGrinderDropsFolder =
        workspace:FindFirstChild("Drops")

    local TPDropsToNearestGrinderRootPart =
        Character and Character:FindFirstChild("HumanoidRootPart")

    if not TPDropsToNearestGrinderDropsFolder
        or not TPDropsToNearestGrinderRootPart
        or not CurrentRooms then
        return
    end

    local TPDropsToNearestGrinderPlayerPosition =
        TPDropsToNearestGrinderRootPart.Position

    local TPDropsToNearestGrinderNearestGrinder = nil
    local TPDropsToNearestGrinderNearestDistance = math.huge

    for _, TPDropsToNearestGrinderRoom in
        ipairs(CurrentRooms:GetChildren()) do

        local TPDropsToNearestGrinderScrapper =
            TPDropsToNearestGrinderRoom:FindFirstChild(
                "StairwellScrapper",
                true
            )

        if TPDropsToNearestGrinderScrapper then
            for _, TPDropsToNearestGrinderObject in
                ipairs(TPDropsToNearestGrinderScrapper:GetDescendants()) do

                if TPDropsToNearestGrinderObject.Name == "Grinder1"
                    and (
                        TPDropsToNearestGrinderObject:IsA("Model")
                        or TPDropsToNearestGrinderObject:IsA("BasePart")
                    ) then

                    local TPDropsToNearestGrinderPosition =
                        TPDropsToNearestGrinderObject:GetPivot().Position

                    local TPDropsToNearestGrinderDistance =
                        (
                            TPDropsToNearestGrinderPlayerPosition
                            - TPDropsToNearestGrinderPosition
                        ).Magnitude

                    if TPDropsToNearestGrinderDistance
                        < TPDropsToNearestGrinderNearestDistance then

                        TPDropsToNearestGrinderNearestDistance =
                            TPDropsToNearestGrinderDistance

                        TPDropsToNearestGrinderNearestGrinder =
                            TPDropsToNearestGrinderObject
                    end
                end
            end
        end
    end

    if not TPDropsToNearestGrinderNearestGrinder then
        return
    end

    local TPDropsToNearestGrinderCFrame =
        TPDropsToNearestGrinderNearestGrinder:GetPivot()

    for _, TPDropsToNearestGrinderDropItem in
        ipairs(TPDropsToNearestGrinderDropsFolder:GetChildren()) do

        if TPDropsToNearestGrinderDropItem:IsA("Model")
            or TPDropsToNearestGrinderDropItem:IsA("BasePart") then

            TPDropsToNearestGrinderDropItem:PivotTo(
                TPDropsToNearestGrinderCFrame
            )
        end
    end
end

Groupboxes.Stairwell_Experimental:AddButton({
    Text = "TP All Drops to Nearest Grinder",
    Func = TPDropsToNearestGrinder,
    DoubleClick = false,
    Tooltip = "Teleports every dropped item to the grinder closest to you",
})

local function BringDroppedItems()
	local workspaceDropsFolder = workspace:FindFirstChild("Drops")
	if LocalPlayer and LocalPlayer.Character then
		local playerHumanoidRootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if playerHumanoidRootPart and workspaceDropsFolder then
			for _, itemToBring in ipairs(workspaceDropsFolder:GetChildren()) do
				if itemToBring:IsA("Model") then
					itemToBring:PivotTo(playerHumanoidRootPart.CFrame)
				elseif itemToBring:IsA("BasePart") then
					itemToBring.CFrame = playerHumanoidRootPart.CFrame
				end
			end
		end
	end
end

Groupboxes.Stairwell_Experimental:AddButton({
	Text = "Bring Dropped Items",
	Func = function() BringDroppedItems() end,
	DoubleClick = false,
	Tooltip = "Brings all dropped items."
})

Groupboxes.Stairwell_Experimental:AddToggle("EnableDroppedItemsInterval", {
	Text = "Enable Interval",
	Default = false,
	Tooltip = "Automatically brings dropped items at the selected interval."
})

Groupboxes.Stairwell_Experimental:AddSlider("DroppedItemsInterval", {
	Text = "Interval",
	Default = 1,
	Min = 0,
	Max = 60,
	Rounding = 1,
	Compact = false,
	Tooltip = "How often dropped items are brought."
})

Toggles.EnableDroppedItemsInterval:OnChanged(function(enabled)
	if enabled then
		if droppedItemsIntervalRunning then return end
		droppedItemsIntervalRunning = true
		task.spawn(function()
			while Toggles.EnableDroppedItemsInterval.Value do
				BringDroppedItems()
				local interval = Options.DroppedItemsInterval.Value
				if interval <= 0 then
					task.wait()
				else
					task.wait(interval)
				end
			end
			droppedItemsIntervalRunning = false
		end)
	end
end)

Groupboxes.Stairwell_Experimental:AddDivider()

Groupboxes.Stairwell_Experimental:AddToggle("OrbitDroppedItems", {
	Text = "Orbit Dropped Items",
	Default = false,
	Tooltip = "Orbits dropped items around you. Teleports them to you every 10s to prevent despawn."
})

Groupboxes.Stairwell_Experimental:AddSlider("OrbitDroppedItemsHeight", {
	Text = "Height",
	Default = 2,
	Min = -20,
	Max = 20,
	Rounding = 1,
	Compact = false,
	Tooltip = "The height of the orbit."
})

Groupboxes.Stairwell_Experimental:AddSlider("OrbitDroppedItemsDistance", {
	Text = "Distance",
	Default = 5,
	Min = 0,
	Max = 50,
	Rounding = 1,
	Compact = false,
	Tooltip = "The distance of the orbit."
})

Groupboxes.Stairwell_Experimental:AddSlider("OrbitDroppedItemsSpeed", {
	Text = "Speed",
	Default = 2,
	Min = 0,
	Max = 20,
	Rounding = 1,
	Compact = false,
	Tooltip = "The speed of the orbit."
})

Toggles.OrbitDroppedItems:OnChanged(function(OrbitDroppedItemsEnabled)
	if OrbitDroppedItemsConnection then
		OrbitDroppedItemsConnection:Disconnect()
		OrbitDroppedItemsConnection = nil
	end
	if not OrbitDroppedItemsEnabled then
		if Boot.Orbit and Boot.Orbit.Abort then pcall(Boot.Orbit.Abort) end
		local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		local DropsFolder = workspace:FindFirstChild("Drops")
		if Root and DropsFolder then
			for _, Object in DropsFolder:GetChildren() do
				if Object:IsA("Model") then Object:PivotTo(Root.CFrame)
				elseif Object:IsA("BasePart") then Object.CFrame = Root.CFrame end
			end
		end
		return
	end
	if Boot.Orbit then Boot.Orbit.Dead = false end
	OrbitDroppedItemsAngle = 0
	OrbitDroppedItemsLastTeleport = tick()
	OrbitDroppedItemsPauseUntil = 0
	OrbitDroppedItemsConnection = RunService.Heartbeat:Connect(function(OrbitDroppedItemsDeltaTime)
		if not LocalPlayer or not LocalPlayer.Character then return end
		local OrbitDroppedItemsHumanoidRootPart = Boot.OrbitRoot and Boot.OrbitRoot() or LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		local OrbitDroppedItemsDropsFolder = workspace:FindFirstChild("Drops")
		if not OrbitDroppedItemsHumanoidRootPart or not OrbitDroppedItemsDropsFolder then return end
		local OrbitDroppedItemsHeightValue = Options.OrbitDroppedItemsHeight.Value
		local OrbitDroppedItemsDistanceValue = Options.OrbitDroppedItemsDistance.Value
		local OrbitDroppedItemsSpeedValue = Options.OrbitDroppedItemsSpeed.Value
		local OrbitDroppedItemsCurrentTime = tick()
		local OrbitDroppedItemsList = {}
		for _, OrbitDroppedItemsObject in ipairs(OrbitDroppedItemsDropsFolder:GetChildren()) do
			if OrbitDroppedItemsObject:IsA("Model") or OrbitDroppedItemsObject:IsA("BasePart") then
				OrbitDroppedItemsList[#OrbitDroppedItemsList + 1] = OrbitDroppedItemsObject
			end
		end
		local OrbitDroppedItemsCount = #OrbitDroppedItemsList
		if Boot.OrbitStep then
			local OrbitStepOk, OrbitStepHandled = pcall(Boot.OrbitStep, OrbitDroppedItemsList, OrbitDroppedItemsHumanoidRootPart, OrbitDroppedItemsDeltaTime, tick())
			if OrbitStepOk then
				if OrbitStepHandled then return end
			else
				if Boot.Orbit and Boot.Orbit.Abort then pcall(Boot.Orbit.Abort) end
				if Boot.Orbit then Boot.Orbit.Dead = true end
				warn("[AMR] orbit effects error, back to plain ring: " .. tostring(OrbitStepHandled))
			end
		end
		if OrbitDroppedItemsCount == 0 then return end
		if OrbitDroppedItemsCurrentTime - OrbitDroppedItemsLastTeleport >= 10 then
			OrbitDroppedItemsLastTeleport = OrbitDroppedItemsCurrentTime
			OrbitDroppedItemsPauseUntil = OrbitDroppedItemsCurrentTime + 2
			local OrbitDroppedItemsCenterPosition = OrbitDroppedItemsHumanoidRootPart.Position
			for _, OrbitDroppedItemsObject in ipairs(OrbitDroppedItemsList) do
				if OrbitDroppedItemsObject:IsA("Model") then
					OrbitDroppedItemsObject:PivotTo(CFrame.new(OrbitDroppedItemsCenterPosition))
				else
					OrbitDroppedItemsObject.CFrame = CFrame.new(OrbitDroppedItemsCenterPosition)
				end
			end
		end
		if OrbitDroppedItemsCurrentTime < OrbitDroppedItemsPauseUntil then return end
		OrbitDroppedItemsAngle += OrbitDroppedItemsDeltaTime * OrbitDroppedItemsSpeedValue
		for OrbitDroppedItemsIndex, OrbitDroppedItemsObject in ipairs(OrbitDroppedItemsList) do
			local OrbitDroppedItemsObjectAngle = OrbitDroppedItemsAngle + ((OrbitDroppedItemsIndex - 1) / OrbitDroppedItemsCount) * math.pi * 2
			local OrbitDroppedItemsOffset = Vector3.new(
				math.cos(OrbitDroppedItemsObjectAngle) * OrbitDroppedItemsDistanceValue,
				OrbitDroppedItemsHeightValue,
				math.sin(OrbitDroppedItemsObjectAngle) * OrbitDroppedItemsDistanceValue
			)
			local OrbitDroppedItemsPosition = OrbitDroppedItemsHumanoidRootPart.Position + OrbitDroppedItemsOffset
			if OrbitDroppedItemsObject:IsA("Model") then
				OrbitDroppedItemsObject:PivotTo(CFrame.new(OrbitDroppedItemsPosition))
			else
				OrbitDroppedItemsObject.CFrame = CFrame.new(OrbitDroppedItemsPosition)
			end
		end
	end)
end)

Toggles.AntiNoise:OnChanged(function(value)
	for i = #Connections, 1, -1 do
		local conn = Connections[i]
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
		table.remove(Connections, i)
	end
	if not value then return end
	local okControls, Controls = pcall(function()
		return require(LocalPlayer.PlayerScripts.PlayerModule):GetControls()
	end)
	if not okControls or not Controls then return end
	local antiNoiseConn = RunService.PreSimulation:Connect(function(dt)
		if not value then return end
		if not LocalPlayer:GetAttribute("Alive") then return end
		local character = LocalPlayer.Character
		if not character then return end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local camera = workspace.CurrentCamera
		if not rootPart or not humanoid or not camera then return end
		if humanoid.Health <= 0 then return end
		if rootPart.Anchored then return end
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Dead
			or state == Enum.HumanoidStateType.Ragdoll
			or state == Enum.HumanoidStateType.Climbing
			or state == Enum.HumanoidStateType.Swimming then
			return
		end
		humanoid.AutoRotate = false
		humanoid:Move(Vector3.zero, false)
		local inputVector = Controls:GetMoveVector()
		local inputMagnitude = inputVector.Magnitude
		if inputMagnitude <= 0 then
			rootPart.AssemblyLinearVelocity = Vector3.zero
			return
		end
		local cameraCFrame = camera.CFrame
		local cameraForward = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z)
		local cameraRight = Vector3.new(cameraCFrame.RightVector.X, 0, cameraCFrame.RightVector.Z)
		if cameraForward.Magnitude < 0.001 or cameraRight.Magnitude < 0.001 then return end
		cameraForward = cameraForward.Unit
		cameraRight = cameraRight.Unit
		local worldDirection = (cameraRight * inputVector.X) + (cameraForward * -inputVector.Z)
		if worldDirection.Magnitude <= 0 then return end
		worldDirection = worldDirection.Unit
		local finalSpeed = humanoid.WalkSpeed * math.clamp(inputMagnitude, 0, 1)
		local clampedDt = math.clamp(dt, 0, 1 / 30)
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.CFrame = rootPart.CFrame + (worldDirection * finalSpeed * clampedDt)
		rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + worldDirection)
	end)
	Connections[#Connections + 1] = antiNoiseConn
end)

Toggles.BypassNoise:OnChanged(function(value)
	for i = #Connections, 1, -1 do
		local existingConnection = Connections[i]
		if existingConnection and existingConnection.Disconnect then
			existingConnection:Disconnect()
		end
		table.remove(Connections, i)
	end

	if not value then return end

	local function checkBypassNoiseTvStand(targetTvStand)
		if not targetTvStand:IsA("Model") then return end
		if targetTvStand.Name ~= "TV_Stand" then return end

		local tvStandCurrentCFrame = targetTvStand:GetPivot()

		if tvStandCurrentCFrame.Position.Y > -119 then
			targetTvStand:PivotTo(CFrame.new(
				tvStandCurrentCFrame.Position.X,
				-120,
				tvStandCurrentCFrame.Position.Z
			))
		end
	end

	local bypassNoiseMiscFolder = workspace:FindFirstChild("Misc")
	if not bypassNoiseMiscFolder then return end

	local bypassNoiseMiscChildAddedConnection = bypassNoiseMiscFolder.ChildAdded:Connect(function(bypassNoiseNewChild)
		checkBypassNoiseTvStand(bypassNoiseNewChild)
	end)

	Connections[#Connections + 1] = bypassNoiseMiscChildAddedConnection

	for _, bypassNoiseMiscChild in ipairs(bypassNoiseMiscFolder:GetChildren()) do
		checkBypassNoiseTvStand(bypassNoiseMiscChild)
	end
end)

Toggles.DroppedItemValue:OnChanged(function(DroppedItemValue)
	local DroppedItemValueScreenGui = game:GetService("CoreGui"):FindFirstChild("DropsCoinCounter")
	if not DroppedItemValue then
		if DroppedItemValueScreenGui then DroppedItemValueScreenGui:Destroy() end
		return
	end
	local DroppedItemValueWorkspaceDrops = workspace:WaitForChild("Drops")
	if DroppedItemValueScreenGui then DroppedItemValueScreenGui:Destroy() end
	DroppedItemValueScreenGui = Instance.new("ScreenGui")
	DroppedItemValueScreenGui.Name = "DropsCoinCounter"
	DroppedItemValueScreenGui.ResetOnSpawn = false
	DroppedItemValueScreenGui.Parent = game:GetService("CoreGui")
	local DroppedItemValueCoinText = Instance.new("TextLabel")
	DroppedItemValueCoinText.Name = "CoinText"
	DroppedItemValueCoinText.AnchorPoint = Vector2.new(0.5, 0)
	DroppedItemValueCoinText.Position = UDim2.new(0.5, 0, 0.02, 0)
	DroppedItemValueCoinText.Size = UDim2.new(0, 250, 0, 40)
	DroppedItemValueCoinText.BackgroundTransparency = 1
	DroppedItemValueCoinText.Text = "Items: 0"
	DroppedItemValueCoinText.TextSize = 24
	DroppedItemValueCoinText.Font = Enum.Font.GothamBold
	DroppedItemValueCoinText.TextColor3 = Color3.fromRGB(255, 255, 255)
	DroppedItemValueCoinText.TextStrokeTransparency = 0.5
	DroppedItemValueCoinText.Parent = DroppedItemValueScreenGui
	local DroppedItemValueCountedDrops = {}
	task.spawn(function()
		while Toggles.DroppedItemValue.Value do
			for _, DroppedItemValueDrop in ipairs(DroppedItemValueWorkspaceDrops:GetChildren()) do
				if DroppedItemValueDrop:IsA("Model") and not DroppedItemValueCountedDrops[DroppedItemValueDrop] then
					DroppedItemValueDrop:SetAttribute("CoinsChecked", true)
					DroppedItemValueCountedDrops[DroppedItemValueDrop] = true
				end
			end
			for DroppedItemValueDrop in pairs(DroppedItemValueCountedDrops) do
				if not DroppedItemValueDrop.Parent or DroppedItemValueDrop.Parent ~= DroppedItemValueWorkspaceDrops then
					DroppedItemValueCountedDrops[DroppedItemValueDrop] = nil
				end
			end
			local DroppedItemValueTotalItems = 0
			for DroppedItemValueDrop in pairs(DroppedItemValueCountedDrops) do
				if DroppedItemValueDrop.Parent == DroppedItemValueWorkspaceDrops then
					DroppedItemValueTotalItems += 1
				end
			end
			DroppedItemValueCoinText.Text = "Items: " .. DroppedItemValueTotalItems
			task.wait(1)
		end
		if DroppedItemValueScreenGui and DroppedItemValueScreenGui.Parent then
			DroppedItemValueScreenGui:Destroy()
		end
	end)
end)

-- Halloween
Groupboxes.Halloween_Misc = Tabs.Halloween:AddLeftGroupbox("Exploits / Anti")
--[[
 Groupboxes.Halloween_Misc:AddButton({
	Text = "Candy Farm",
	Func = function() loadstring(game:HttpGet(Boot.MirrorRoot .. "Games/Doors/verity's%20auto%20farm.txt")) end,
	DoubleClick = false,
	Tooltip = "By Indexell."
}) 
--]]
Groupboxes.Halloween_Misc:AddToggle("SkipCutsenesHalloween", {
	Text = "Skip Cutsenes", Default = false,
	Tooltip = "Skip cutsenes."
})
Groupboxes.Halloween_Misc:AddToggle("RemoveFogHalloween", {
    Text = "Remove Extra Fog",
    Default = false,
    Tooltip = "Removes The extra fog."
})
Groupboxes.Halloween_Misc:AddButton({
	Text = "Bring Dropped Candy",
	Func = function() BringDroppedItems() end,
	DoubleClick = false,
	Tooltip = "Brings all dropped Candy (use for the depot)."
})

Groupboxes.Halloween_Misc:AddToggle("EnableDroppedItemsIntervalHalloween", {
	Text = "Enable Interval",
	Default = false,
	Tooltip = "Automatically brings candy items at the selected interval."
})

Groupboxes.Halloween_Misc:AddSlider("DroppedItemsIntervalHalloween", {
	Text = "Interval",
	Default = 1,
	Min = 0,
	Max = 60,
	Rounding = 1,
	Compact = false,
	Tooltip = "How often dropped items are brought."
})

Toggles.EnableDroppedItemsIntervalHalloween:OnChanged(function(enabled)
	if enabled then
		if droppedItemsIntervalRunning then return end
		droppedItemsIntervalRunning = true
		task.spawn(function()
			while Toggles.EnableDroppedItemsIntervalHalloween.Value do
				BringDroppedItems()
				local interval = Options.DroppedItemsIntervalHalloween.Value
				if interval <= 0 then
					task.wait()
				else
					task.wait(interval)
				end
			end
			droppedItemsIntervalRunning = false
		end)
	end
end)

Toggles.SkipCutsenesHalloween:OnChanged(function(Value)
    if Value then
        task.spawn(function()
            local Event = game:GetService("ReplicatedStorage").FloorReplicated.ClientRemote.SkipCutscene.Remote

            while Toggles.SkipCutsenesHalloween.Value do
                Event:FireServer(1, true)
                Event:FireServer(2, true)


                task.wait(0.5)
            end
        end)
    end
end)
Toggles.RemoveFogHalloween:OnChanged(function(Value)
    if Value then
        task.spawn(function()
            while Toggles.RemoveFogHalloween.Value do
                for _, v in ipairs(workspace:GetDescendants()) do
                    if v.Name == "FogScout" or v.Name == "FogHolder" then
                        v:Destroy()
                    end
                end

                task.wait(0.5)
            end
        end)
    end
end)
-- hi

Groupboxes.Exploits_BypassRight = Tabs.Exploits:AddRightGroupbox("Bypass")
Groupboxes.Exploits_BypassRight:AddToggle("DisableAnticheat", {
	Text = "Anticheat Bypass", Default = false,
	Tooltip = "Disables the anticheat after interacting with a ladder, Stairwell shopping cart, or Archives office chair."
})
Groupboxes.Exploits_BypassRight:AddToggle("AutoChairBypass", {
	Text = "Auto Chair Bypass (Archives)", Default = false,
	Tooltip = "Needs Anticheat Bypass. In Archives it walks behind the nearest office chair, grabs it, then stows the held chair tool into your backpack by itself. Retries a few times."
})
Groupboxes.Exploits_BypassRight:AddToggle("VelocityManipulationToggle", {
	Text = "Velocity Manipulation", Default = false,
	Tooltip = "Moves your character forward slowly, mitigating the game's anti-noclip."
})
Toggles.DisableAnticheat:OnChanged(function(Value)
	if Globals.AnticheatDisabled == true and not Value then
		RemotesFolder.ClimbLadder:FireServer()
		Globals.AnticheatDisabled = false
	end
end)
Toggles.VelocityManipulationToggle:AddKeyPicker("VelocityManipulationKeybind", {
	Text = "Velocity Manipulation", Default = "V",
	Mode = Library.IsMobile and "Toggle" or "Hold", SyncToggleState = true
})
Groupboxes.Exploits_BypassRight:AddDropdown("VelocityManipulationMode", {
	Values = {"Velocity", "Pivot"}, Text = "Manipulation Method",
	Default = 1,
})

Groupboxes.Exploits_BypassRight:AddDivider()
Groupboxes.Exploits_BypassRight:AddToggle("InfiniteItemsToggle", {
	Text = "Infinite Items", Default = false,
	Tooltip = "Allows certain items to be used without draining their uses.",
	Disabled = not Functions.CheckCompatability({"fireproximityprompt"}),
	DisabledTooltip = Globals.IncompatibleMessage
})
Groupboxes.Exploits_BypassRight:AddDropdown("InfiniteItemsList", {
	Text = "Item List",
	Values = { "Lockpicks", "Skeleton Key", "Shears", "Multitool" },
	Multi = true, AllowNull = true,
	Disabled = not Functions.CheckCompatability({"fireproximityprompt"}),
	DisabledTooltip = Globals.IncompatibleMessage
})

Groupboxes.Exploits_BypassRight:AddToggle("InfiniteCoinRoll", {
	Text = "Infinite Coin Roll", Default = false,
	Tooltip = "EXPERIMENTAL, probably blocked by the server (it refuses a drop while the roll is being used). Use Auto Use / Auto Collect Coin Rolls instead."
})
Groupboxes.Exploits_BypassRight:AddToggle("InfiniteCoinRollAuto", {
	Text = "Coin Roll Auto Use", Default = true,
	Tooltip = "The script itself equips the roll, uses it, drops it, picks it up and repeats. Off = you use it by hand and the script only drops/picks it up."
})
Groupboxes.Exploits_BypassRight:AddDropdown("InfiniteCoinRollOrder", {
	Text = "Coin Roll Order", Values = { "Drop, Then Use", "Use, Then Drop" }, Default = 1,
	Tooltip = "Drop, Then Use: the roll is dropped first, the use still lands (the server deletes the held copy a moment later) and the dropped copy keeps full durability. Use, Then Drop: durability is spent first."
})
Groupboxes.Exploits_BypassRight:AddSlider("InfiniteCoinRollInterval", {
	Text = "Coin Roll Cycle (s)", Default = 1, Min = 0.3, Max = 5, Rounding = 1, Compact = true,
	Tooltip = "Pause between two auto cycles."
})
Groupboxes.Exploits_BypassRight:AddButton({
	Text = "Coin Roll Probe (copy)",
	Func = function() if Boot.CoinProbe then Boot.CoinProbe() end end,
	Tooltip = "Scans use/drop timings on your Coin Roll (each trial spends one use!) until the server accepts a drop, then copies the timeline to the clipboard."
})
Groupboxes.Exploits_BypassRight:AddSlider("InfiniteCoinRollPickup", {
	Text = "Coin Roll Pickup Wait (s)", Default = 0.65, Min = 0.2, Max = 2, Rounding = 2, Compact = true,
	Tooltip = "Dropped items cannot be picked up for a moment. The script waits this long, then keeps trying to pick the roll up."
})
Groupboxes.Exploits_BypassRight:AddSlider("InfiniteCoinRollDelay", {
	Text = "Coin Roll Gap (s)", Default = 0, Min = 0, Max = 1.6, Rounding = 2, Compact = true,
	Tooltip = "Pause between the two steps (use / drop) of the cycle. The server seems to refuse a drop while the use is running (~1 s), so try values from 0.1 to 1.5 together with the probe."
})

do
	local HookedTools = setmetatable({}, { __mode = "k" })
	local Said = {}
	local function Say(Key, Body)
		if Said[Key] and tick() - Said[Key] < 5 then return end
		Said[Key] = tick()
		Functions.Notify({ Title = "Infinite Coin Roll", Body = Body })
	end

	local function IsCoinRoll(Tool)
		if not Tool:IsA("Tool") then return false end
		if ItemNames[Tool.Name] == "Coin Roll" then return true end
		local Name = string.gsub(string.lower(Tool.Name), "[^%w]", "")
		return string.find(Name, "coin", 1, true) ~= nil
	end

	local function FindRoll()
		for _, Container in { LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") } do
			if Container then
				for _, Tool in Container:GetChildren() do
					if IsCoinRoll(Tool) then return Tool end
				end
			end
		end
		return nil
	end

	-- takes the dropped roll back through its ModulePrompt. A fresh drop cannot be picked up for a moment, so wait, then retry
	local function TakeBack(Name, Dropped)
		task.wait(Options.InfiniteCoinRollPickup.Value)
		local Until = tick() + 4
		local Attempts = 0
		while tick() < Until do
			local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
			if (Backpack and Backpack:FindFirstChild(Name)) or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild(Name)) then return true end
			local ModulePrompt = Dropped.Parent and Dropped:FindFirstChild("ModulePrompt")
			if ModulePrompt then
				Attempts += 1
				Functions.FirePrompt(ModulePrompt)
			end
			task.wait(0.5)
		end
		local Prompt = Dropped:FindFirstChild("ModulePrompt")
		local Attrs = {}
		for Key, Value in Dropped:GetAttributes() do Attrs[#Attrs + 1] = Key .. "=" .. tostring(Value) end
		return false, string.format("tries %d, dropped alive %s, prompt %s, action '%s', attrs [%s]", Attempts, tostring(Dropped.Parent ~= nil),
			Prompt and ("enabled " .. tostring(Prompt.Enabled)) or "missing", Prompt and Prompt.ActionText or "", table.concat(Attrs, ", "))
	end

	local Running = false
	local NextCycle = 0

	-- one full cycle. Manual = the player already used the roll, only drop it
	local function Cycle(Tool, Manual)
		local Name = Tool.Name
		local DropItem = RemotesFolder and RemotesFolder:FindFirstChild("DropItem")
		local DropsFolder = workspace:FindFirstChild("Drops")
		local Character = LocalPlayer.Character
		local Hum = Character and Character:FindFirstChildOfClass("Humanoid")
		if not DropItem or not DropsFolder or not Hum then return false end

		if not Manual and Tool.Parent ~= Character then
			Hum:EquipTool(Tool)
			local Until = tick() + 1.5
			while Tool.Parent ~= Character and tick() < Until do task.wait(0.05) end
			if Tool.Parent ~= Character then Say("equip", "Could not equip the roll.") return false end
			task.wait(0.3) -- the server must have the roll in your hand before it accepts the drop
		end

		local Dropped
		local DropConnection = DropsFolder.ChildAdded:Connect(function(New)
			if not Dropped and (New.Name == Name or string.find(string.lower(New.Name), "coin", 1, true)) then Dropped = New end
		end)
		local Sent = false
		local function SendDrop(Why)
			if Sent then return end
			Sent = true
			DropItem:FireServer(Tool)
		end
		-- if the game deletes the roll on this client when it is used, the drop still goes out in that very moment
		local DestroyConnection = Tool.Destroying:Connect(function() SendDrop("destroying") end)

		local Remote = Tool:FindFirstChild("Remote")
		local Order = Options.InfiniteCoinRollOrder.Value
		local function UseNow()
			-- the real use is the roll's own Remote (Tool:Activate() does not spend anything)
			if Remote and Remote:IsA("RemoteEvent") then Remote:FireServer() else Tool:Activate() end
		end
		if Manual then
			SendDrop("manual")
		elseif Order == "Drop, Then Use" then
			SendDrop("before")
			local Delay = Options.InfiniteCoinRollDelay.Value
			if Delay > 0 then task.wait(Delay) end
			UseNow()
		else
			UseNow()
			local Delay = Options.InfiniteCoinRollDelay.Value
			if Delay > 0 then task.wait(Delay) end
			SendDrop("after")
		end
		local ParentAfter = Tool.Parent and Tool.Parent.Name or "nil"

		local Until = tick() + 3
		while not Dropped and tick() < Until do task.wait(0.05) end
		DropConnection:Disconnect()
		DestroyConnection:Disconnect()

		if not Dropped then
			Say("nodrop", string.format("No drop (%s / parent %s / sent %s). Press Coin Roll Probe.", Order, ParentAfter, tostring(Sent)))
			return false
		end
		local Back, Why = TakeBack(Name, Dropped)
		if not Back then Say("noback", "Dropped, not picked up. Press Coin Roll Probe. " .. string.sub(tostring(Why), 1, 90)) return false end
		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
		local Again = Backpack and Backpack:FindFirstChild(Name)
		if Manual and Again then Hum:EquipTool(Again) end
		return true
	end

	-- timeline probe + gap scan: tries use/drop timings one after another until a drop is accepted, logs everything, copies it
	function Boot.CoinProbe()
		if Running then Say("busy", "A cycle is running, wait.") return end
		Running = true
		task.spawn(function()
			local Lines, T0 = {}, tick()
			local function Log(Text) Lines[#Lines + 1] = string.format("[%.2f] %s", tick() - T0, Text) end
			local Conns = {}
			local function Show(Value)
				local Kind = typeof(Value)
				if Kind == "string" then return '"' .. string.sub(Value, 1, 80) .. '"' end
				if Kind == "Instance" then return Value.ClassName .. ":" .. string.sub(Value:GetFullName(), -70) end
				if Kind == "number" or Kind == "boolean" or Kind == "nil" then return tostring(Value) end
				if Kind == "table" then return "{table}" end
				return Kind
			end
			local function Describe(Object)
				local Children, Attrs = {}, {}
				for _, Child in Object:GetChildren() do Children[#Children + 1] = Child.Name .. ":" .. Child.ClassName end
				for Key, Value in Object:GetAttributes() do Attrs[#Attrs + 1] = Key .. "=" .. tostring(Value) end
				return string.format("%s [%s] children {%s} attrs {%s}", Object.Name, Object.ClassName, table.concat(Children, ", "), table.concat(Attrs, ", "))
			end
			local Ok, Err = pcall(function()
				local Character = LocalPlayer.Character
				local Hum = Character and Character:FindFirstChildOfClass("Humanoid")
				local DropItem = RemotesFolder and RemotesFolder:FindFirstChild("DropItem")
				local DropsFolder = workspace:FindFirstChild("Drops")
				if not (Hum and DropItem and DropsFolder and FindRoll()) then Log("missing humanoid / DropItem / Drops / a Coin Roll") return end

				local Dropped
				for _, Remote in RemotesFolder:GetChildren() do
					if Remote:IsA("RemoteEvent") and Remote.Name ~= "Ping" then
						Conns[#Conns + 1] = Remote.OnClientEvent:Connect(function(...)
							local Args = {}
							for Index, Value in { ... } do if Index <= 6 then Args[#Args + 1] = Show(Value) end end
							Log("server -> client " .. Remote.Name .. "(" .. table.concat(Args, ", ") .. ")")
						end)
					end
				end
				Conns[#Conns + 1] = DropsFolder.ChildAdded:Connect(function(New)
					Log("DROPS +" .. Describe(New))
					if string.find(string.lower(New.Name), "coin", 1, true) then Dropped = Dropped or New end
				end)

				-- {order, gap}: cheap/likely first, every trial spends one use of the roll
				local Trials = { { "Drop", 0.12 }, { "Drop", 0.22 }, { "Use", 0.1 }, { "Use", 0.4 }, { "Use", 0.8 }, { "Use", 1.3 } }
				local Chosen = Options.InfiniteCoinRollOrder.Value == "Drop, Then Use" and "Drop" or "Use"
				local Gap = Options.InfiniteCoinRollDelay.Value
				if Gap > 0 then table.insert(Trials, 1, { Chosen, Gap }) end

				for Index, Trial in Trials do
					local Tool = FindRoll()
					if not Tool then Log("no roll left, scan stops") return end
					local Remote = Tool:FindFirstChild("Remote")
					if Tool.Parent ~= Character then
						Hum:EquipTool(Tool)
						local Until = tick() + 1.5
						while Tool.Parent ~= Character and tick() < Until do task.wait(0.05) end
						task.wait(0.4)
					end
					Dropped = nil
					Log(string.format("--- trial %d: %s first, gap %.2f, durability %s", Index, Trial[1], Trial[2], tostring(Tool:GetAttribute("Durability"))))
					local function DoUse() if Remote then Remote:FireServer() Log("use sent") end end
					local function DoDrop() DropItem:FireServer(Tool) Log("drop sent, parent=" .. tostring(Tool.Parent and Tool.Parent.Name)) end
					if Trial[1] == "Drop" then DoDrop() task.wait(Trial[2]) DoUse() else DoUse() task.wait(Trial[2]) DoDrop() end

					local Until = tick() + 2.5
					while not Dropped and tick() < Until do task.wait(0.05) end
					if Dropped then
						Log("DROP ACCEPTED -> WORKS: order " .. Trial[1] .. " first, gap " .. Trial[2])
						task.wait(Options.InfiniteCoinRollPickup.Value)
						local Prompt = Dropped:FindFirstChild("ModulePrompt")
						for Try = 1, 4 do
							if Prompt then Functions.FirePrompt(Prompt) end
							task.wait(0.8)
							local Back = LocalPlayer:FindFirstChildOfClass("Backpack")
							local Got = (Back and Back:FindFirstChild(Tool.Name)) or Character:FindFirstChild(Tool.Name)
							if Got then Log("PICKED UP, durability now = " .. tostring(Got:GetAttribute("Durability"))) return end
						end
						Log("dropped but not picked up")
						return
					end
					Log("no drop; tool parent now = " .. tostring(Tool.Parent and Tool.Parent.Name) .. ", durability " .. tostring(Tool:GetAttribute("Durability")))
					task.wait(1.6) -- let the use finish before the next trial
				end
				Log("scan finished: no timing got a drop accepted")
			end)
			if not Ok then Log("error: " .. tostring(Err)) end
			for _, Connection in Conns do Connection:Disconnect() end
			Running = false
			local Text = table.concat(Lines, "\n")
			local Copied = Boot.Copy and Boot.Copy(Text)
			if not Copied then
				local Fn = setclipboard or toclipboard
				Copied = Fn and pcall(Fn, Text)
			end
			print("[AMR coin probe]\n" .. Text)
			Functions.Notify({ Title = "Coin Roll Probe", Body = Copied and "Scan done, timeline copied to the clipboard." or "Clipboard unavailable, timeline is in the console." })
		end)
	end

	-- auto mode: the script uses and drops the roll itself, over and over
	task.spawn(function()
		while not Library.Unloaded do
			task.wait(0.2)
			if Toggles.InfiniteCoinRoll.Value and Toggles.InfiniteCoinRollAuto.Value and not Running and tick() >= NextCycle
				and LocalPlayer.Character and not LocalPlayer:GetAttribute("Hiding") then
				local Tool = FindRoll()
				if Tool then
					Running = true
					local Ok, Result = pcall(Cycle, Tool, false)
					Running = false
					if not Ok then Say("err", "Error: " .. tostring(Result)) end
					if not (Ok and Result) then
						-- the roll was not looped back: stop here instead of burning the rest of its durability
						Toggles.InfiniteCoinRoll:SetValue(false)
						Functions.Notify({ Title = "Infinite Coin Roll", Body = "Stopped: the cycle did not bring the roll back. Run Coin Roll Probe." })
					end
					NextCycle = tick() + Options.InfiniteCoinRollInterval.Value + ((Ok and Result) and 0 or 2)
				end
			end
		end
	end)

	-- manual mode hooks
	local function TriggerManual(Tool)
		if not Toggles.InfiniteCoinRoll.Value or Toggles.InfiniteCoinRollAuto.Value or Running then return end
		if Tool.Parent ~= LocalPlayer.Character then return end
		Running = true
		task.spawn(function()
			pcall(Cycle, Tool, true)
			Running = false
		end)
	end

	local function HookCoinRoll(Tool)
		if HookedTools[Tool] or not IsCoinRoll(Tool) then return end
		local ActivatedConnection = Tool.Activated:Connect(function() TriggerManual(Tool) end)
		HookedTools[Tool] = ActivatedConnection
		table.insert(Connections, ActivatedConnection)
	end

	local function WatchContainer(Key, Container)
		if Connections[Key] then Connections[Key]:Disconnect() end
		for _, Tool in Container:GetChildren() do HookCoinRoll(Tool) end
		Connections[Key] = Container.ChildAdded:Connect(HookCoinRoll)
	end

	-- the Backpack is a new instance after every respawn, so watch both again each time
	local function WatchPlayer()
		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
		if Backpack then WatchContainer("InfiniteCoinRollBackpackHandler", Backpack) end
		if LocalPlayer.Character then WatchContainer("InfiniteCoinRollToolHandler", LocalPlayer.Character) end
	end
	WatchPlayer()
	Connections.InfiniteCoinRollCharacterHandler = LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.5)
		WatchPlayer()
	end)
	Connections.InfiniteCoinRollPlayerHandler = LocalPlayer.ChildAdded:Connect(function(Child)
		if Child:IsA("Backpack") then WatchContainer("InfiniteCoinRollBackpackHandler", Child) end
	end)
	Toggles.InfiniteCoinRoll:OnChanged(function(Value)
		if not Value then return end
		local Tool = FindRoll()
		if Tool then
			Functions.Notify({ Title = "Infinite Coin Roll", Body = "Found: " .. Tool.Name .. (Toggles.InfiniteCoinRollAuto.Value and ". Auto cycle starts." or ". Use it by hand.") })
		else
			local Names = {}
			for _, Container in { LocalPlayer:FindFirstChildOfClass("Backpack"), LocalPlayer.Character } do
				if Container then
					for _, Child in Container:GetChildren() do
						if Child:IsA("Tool") then Names[#Names + 1] = Child.Name end
					end
				end
			end
			Functions.Notify({ Title = "Infinite Coin Roll", Body = "No Coin Roll tool found. Your tools: " .. (#Names > 0 and table.concat(Names, ", ") or "none") })
		end
	end)
end

Groupboxes.Exploits_BypassRight:AddToggle("AutoUseCoinRoll", {
	Text = "Auto Use Coin Rolls", Default = false,
	Tooltip = "Equips and uses every Coin Roll you hold, one after another (50 Gold per use, 4 uses per roll)."
})
Groupboxes.Exploits_BypassRight:AddToggle("AutoCollectCoinRolls", {
	Text = "Auto Collect Coin Rolls", Default = false,
	Tooltip = "Picks up every Coin Roll lying in the level, from any distance. Pair it with Auto Use Coin Rolls to farm Gold."
})

do
	local function IsRollName(Name)
		return string.find(string.lower(Name), "coinroll", 1, true) ~= nil or string.find(string.lower(Name), "coin_roll", 1, true) ~= nil
	end

	-- use: equip, wait for the server to have it in hand, fire its Remote, wait until the use is paid (durability changes / roll is gone)
	task.spawn(function()
		while not Library.Unloaded do
			task.wait(0.3)
			if Toggles.AutoUseCoinRoll.Value and LocalPlayer.Character then
				local Character = LocalPlayer.Character
				local Hum = Character:FindFirstChildOfClass("Humanoid")
				local Roll
				for _, Container in { Character, LocalPlayer:FindFirstChildOfClass("Backpack") } do
					if Container then
						for _, Tool in Container:GetChildren() do
							if Tool:IsA("Tool") and IsRollName(Tool.Name) then Roll = Tool break end
						end
					end
					if Roll then break end
				end
				if Roll and Hum and Hum.Health > 0 and not (Toggles.InfiniteCoinRoll and Toggles.InfiniteCoinRoll.Value) then
					if Roll.Parent ~= Character then
						Hum:EquipTool(Roll)
						local Until = tick() + 1.5
						while Roll.Parent ~= Character and tick() < Until do task.wait(0.05) end
						task.wait(0.35)
					end
					local Remote = Roll:FindFirstChild("Remote")
					if Remote and Remote:IsA("RemoteEvent") and Roll.Parent == Character then
						local Before = Roll:GetAttribute("Durability")
						Remote:FireServer()
						local Until = tick() + 3
						while Roll.Parent and Roll:GetAttribute("Durability") == Before and tick() < Until do task.wait(0.1) end
						task.wait(0.25)
					end
				end
			end
		end
	end)

	-- collect: every world Coin Roll with a ModulePrompt, one prompt at a time
	local Rolls = {}
	local Watch
	local function Track(Object)
		if Object:IsA("Model") and IsRollName(Object.Name) then Rolls[Object] = true end
	end
	Toggles.AutoCollectCoinRolls:OnChanged(function(Value)
		if Watch then Watch:Disconnect() Watch = nil end
		table.clear(Rolls)
		if not Value then return end
		for _, Object in workspace:GetDescendants() do Track(Object) end
		Watch = workspace.DescendantAdded:Connect(Track)
		table.insert(Connections, Watch)
	end)
	task.spawn(function()
		while not Library.Unloaded do
			task.wait(0.6)
			if Toggles.AutoCollectCoinRolls.Value then
				for Roll in Rolls do
					if not Roll.Parent then
						Rolls[Roll] = nil
					else
						local Prompt = Roll:FindFirstChild("ModulePrompt")
						if Prompt then
							Functions.FirePrompt(Prompt)
							break
						end
					end
				end
			end
		end
	end)
end

Groupboxes.Exploits_BypassRight:AddToggle("InfCrucifix", {
	Text = "Infinite Crucifix",
	Default = false,
	Tooltip = "Risky! You can die or lose the Crucifix. Recommended to have low ping and stable fps.",
	Risky = Floor ~= "Ballz",
})


local InfCrucifixDropTable = {
	RushMoving   = 54,
	AmbushMoving = 67,
	A60          = 70,
	GlitchRush   = 120,
	GlitchAmbush = 155,
	A120         = 75,

}



Toggles.InfCrucifix:OnChanged(function(Value)
	-- (old version looked for CollisionPart / the Tool on the Player object instead of the Character, so it never fired)
	Globals.InfCrucifixToken = (Globals.InfCrucifixToken or 0) + 1
	if not Value then return end
	local Token = Globals.InfCrucifixToken
	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	local LastDrop = 0

	local Connection
	Connection = RunService.RenderStepped:Connect(function()
		if not Toggles.InfCrucifix.Value or Token ~= Globals.InfCrucifixToken then
			Connection:Disconnect()
			return
		end
		if tick() - LastDrop < 1.2 then return end

		local Char = LocalPlayer.Character
		local Collision = Char and (Char:FindFirstChild("CollisionPart") or Char:FindFirstChild("HumanoidRootPart"))
		local Tool = Char and Char:FindFirstChildOfClass("Tool")
		if not Collision or not Tool or Tool.Name ~= "Crucifix" then return end
		Params.FilterDescendantsInstances = { Char }

		for _, Entity in ipairs(workspace:GetChildren()) do
			local MaxDistance = InfCrucifixDropTable[Entity.Name]
			if MaxDistance and Entity.PrimaryPart then
				Entity.PrimaryPart.CanCollide = true
				Entity.PrimaryPart.CanQuery = true
				local Origin = Collision.Position
				local Ray = workspace:Raycast(Origin, Entity.PrimaryPart.Position - Origin, Params)
				local Distance = (Origin - Entity.PrimaryPart.Position).Magnitude
				if Ray and Ray.Instance:IsDescendantOf(Entity) and Distance < MaxDistance then
					LastDrop = tick()
					task.spawn(function()
						RemotesFolder.DropItem:FireServer(Tool)
						task.wait(0.54)
						local Drops = workspace:FindFirstChild("Drops")
						local Dropped = Drops and Drops:FindFirstChild("Crucifix")
						local Prompt = Dropped and Dropped:FindFirstChildOfClass("ProximityPrompt")
						if Prompt then fireproximityprompt(Prompt) end
						-- put it back in your hands
						task.wait(0.25)
						local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
						local Again = Backpack and Backpack:FindFirstChild("Crucifix")
						local Hum = Char:FindFirstChildOfClass("Humanoid")
						if Again and Hum then Hum:EquipTool(Again) end
					end)
					break
				end
			end
		end
	end)
end)


Groupboxes.Exploits_BypassRight:AddDivider()
Groupboxes.Exploits_BypassRight:AddToggle("PositionSpoof", {
	Text = "Position Spoof", Default = false,
	Tooltip = "Makes your character appear underground on the server, protecting you from rush-like entities."
})
Groupboxes.Exploits_BypassRight:AddToggle("CrouchSpoof", {
	Text = "Crouch Spoof", Default = false, Tooltip = "Makes the game think you are always crouching."
})
Toggles.PositionSpoof:OnChanged(function(Value)
	if Floor ~= "Fools" and Floor ~= "OldHotel" then
		if Value then
			RootPart.CFrame = RootPart.CFrame * CFrame.new(0, -2.346, 0)
			Humanoid.HipHeight = 0.05
			RemotesFolder.Crouch:FireServer(true, true)
		else
			RootPart.CFrame = RootPart.CFrame * CFrame.new(0, 2.346, 0)
			Humanoid.HipHeight = 2.396
		end
	end
end)
Toggles.PositionSpoof:AddKeyPicker("PositionSpoof", {
	Text = "Position Spoof", Default = "B", Mode = "Toggle", SyncToggleState = true
})
Toggles.CrouchSpoof:OnChanged(function(Value)
	if RemotesFolder:FindFirstChild("Crouch") then
		RemotesFolder.Crouch:FireServer(Value and true or Functions.IsCrouching(), true)
	end
end)

Groupboxes.Exploits_Remove = Tabs.Exploits:AddRightGroupbox("Remove")
Groupboxes.Exploits_Remove:AddToggle("RemoveScreech", { Text = "Remove Screech",  Default = false, Tooltip = "Prevents 'Screech' from spawning." })
Groupboxes.Exploits_Remove:AddToggle("RemoveHalt",    { Text = "Remove Halt",     Default = false, Tooltip = "Prevents 'Halt' from spawning." })
Groupboxes.Exploits_Remove:AddToggle("RemoveA90",     { Text = "Remove A-90",     Default = false, Tooltip = "Prevents 'A-90' from spawning." })
Groupboxes.Exploits_Remove:AddToggle("RemoveDread",   { Text = "Remove Dread",    Default = false, Tooltip = "Prevents 'Dread' from spawning." })
Groupboxes.Exploits_Remove:AddToggle("RemoveSurge", { Text = "Remove Surge", Default = false, Tooltip = "Prevents 'Surge' from spawning."})
Groupboxes.Exploits_Remove:AddDivider()
Groupboxes.Exploits_Remove:AddToggle("NoScreechDamage", { Text = "No Screech Damage", Default = false, Tooltip = "Prevents 'Screech' from hurting you." })
Groupboxes.Exploits_Remove:AddToggle("NoHaltDamage",    { Text = "No Halt Damage",    Default = false, Tooltip = "Prevents 'Halt' from hurting you." })
Groupboxes.Exploits_Remove:AddToggle("NoA90Damage",     { Text = "No A-90 Damage",    Default = false, Tooltip = "Prevents 'A-90' from hurting you." })
Groupboxes.Exploits_Remove:AddToggle("NoSurgeDamage",   { Text = "No Surge Damage",   Default = false, Tooltip = "Prevents 'Surge' from hurting you." })

Toggles.NoScreechDamage:OnChanged(function(Value)
	if Value then
		FakeEvents.Screech.Parent = RemotesFolder
		FakeEvents.Screech_Real.Parent = nil
	else
		FakeEvents.Screech_Real.Parent = RemotesFolder
		FakeEvents.Screech.Parent = nil
	end
end)
Toggles.NoHaltDamage:OnChanged(function(Value)
	if Value then
		FakeEvents.Shade.Parent = RemotesFolder
		FakeEvents.Shade_Real.Parent = nil
	else
		FakeEvents.Shade_Real.Parent = RemotesFolder
		FakeEvents.Shade.Parent = nil
	end
end)
Toggles.NoA90Damage:OnChanged(function(Value)
	if RemotesFolder:FindFirstChild("A90") then
		if Value then
			FakeEvents.A90.Parent = RemotesFolder
			FakeEvents.A90_Real.Parent = nil
		else
			FakeEvents.A90_Real.Parent = RemotesFolder
			FakeEvents.A90.Parent = nil
		end
	end
end)
Toggles.NoSurgeDamage:OnChanged(function(Value)
	if RemotesFolder:FindFirstChild("SurgeRemote") then
		if Value then
			FakeEvents.Surge.Parent = RemotesFolder
			FakeEvents.Surge_Real.Parent = nil
		else
			FakeEvents.Surge_Real.Parent = RemotesFolder
			FakeEvents.Surge.Parent = nil
		end
	end
end)

local Modules = {}

Toggles.RemoveScreech:OnChanged(function(Value)
	if Value then
		task.spawn(function()
			while Toggles.RemoveScreech.Value do
				local Camera = workspace:FindFirstChild("Camera")

				if Camera then
					local Screech = Camera:FindFirstChild("Screech")

					if Screech and not Screech:GetAttribute("AbysallHidden") then
						-- hide, don't destroy: the game's Screech render-step reads Camera.Screech.CFrame every frame
						Screech:SetAttribute("AbysallHidden", true)
						for _, Part in Screech:GetDescendants() do
							if Part:IsA("BasePart") or Part:IsA("Decal") or Part:IsA("Texture") then
								Part.Transparency = 1
							elseif Part:IsA("Sound") then
								Part.Volume = 0
							elseif Part:IsA("ParticleEmitter") or Part:IsA("Light") then
								Part.Enabled = false
							end
						end
					end
				end

				task.wait()
			end
		end)
	end
end)
Toggles.RemoveHalt:OnChanged(function(Value)
	Modules.Shade.Name = Value and "Shade_Disabled" or "Shade"
end)
Toggles.RemoveA90:OnChanged(function(Value)
	if Modules.A90 then
		Modules.A90.Name = Value and "A90_Disabled" or "A90"
	end
end)
Toggles.RemoveDread:OnChanged(function(Value)
	if Modules.Dread then
		Modules.Dread.Name = Value and "Dread_Disabled" or "Dread"
	end
end)
Toggles.RemoveSurge:OnChanged(function(Value)
	if Globals.SurgeFrame then
		Globals.SurgeFrame.Name = (Value and "SurgeVignette_Disabled" or "SurgeVignette")
	end
end)

Groupboxes.Exploits_Audio = Tabs.Exploits:AddLeftGroupbox("Audio")
Globals.JamMuffle = Services.SoundService:WaitForChild("Main"):FindFirstChild("Jamming") or Instance.new("EqualizerSoundEffect")

Groupboxes.Exploits_Audio:AddToggle("RemoveFootstepSounds",    { Text = "Remove Footstep Sounds",    Default = false, Tooltip = "Removes the sounds when walking." })
Groupboxes.Exploits_Audio:AddToggle("RemoveJamminMusic",       { Text = "Remove Jammin Music",       Default = false, Tooltip = "Removes the music and muffle effect from the 'Jammin' modifier." })
Groupboxes.Exploits_Audio:AddToggle("RemoveInteractingSounds", { Text = "Remove Interacting Sounds", Default = false, Tooltip = "Removes the sounds when interacting with proximity prompts." })

Toggles.RemoveJamminMusic:OnChanged(function(Value)
	local Jam = Globals.MainUI.Initiator.Main_Game.Health:FindFirstChild("Jam")
	if Jam then
		Jam.Volume = Value and 0 or 0.45
		Globals.JamMuffle.Enabled = LiveModifiers:FindFirstChild("Jammin") and not Value or false
	end
end)
Toggles.RemoveInteractingSounds:OnChanged(function(Value)
	local Game = Globals.MainUI.Initiator.Main_Game
	local PS = Game:FindFirstChild("PromptService")
	if PS then
		for Name, Volume in { Triggered = 0.04, Holding = 0.1, Notification = 0.03 } do
			local Sound = PS:FindFirstChild(Name)
			if Sound then Sound.Volume = Value and 0 or Volume end
		end
	end
	local Caption = Game:FindFirstChild("Reminder") and Game.Reminder:FindFirstChild("Caption")
	if Caption then Caption.Volume = Value and 0 or 0.1 end
end)

Groupboxes.Visuals_LeftTab = Tabs.Visuals:AddLeftTabbox("Camera / Effects")
Groupboxes.Visuals_Camera = Groupboxes.Visuals_LeftTab:AddTab("Camera")
Groupboxes.Visuals_Camera:AddToggle("AmbientToggle", { Text = "Ambient", Default = false, Tooltip = "Changes the lighting color to the specified value." })
Groupboxes.Visuals_Camera:AddSlider("FieldOfView", { Text = "Field of View", Min = 1, Max = 120, Default = 70, Rounding = 0 })
Groupboxes.Visuals_Camera:AddToggle("FOVToggle", {    Text = "Custom FOV",    Default = false,    Tooltip = "Only applies the Field of View slider when enabled." })
Toggles.FOVToggle:AddKeyPicker("FovToggle", {Text = "Custom Fov", Default = "O", Mode = "Toggle", SyncToggleState = true})
Groupboxes.Visuals_Camera:AddDivider()
Groupboxes.Visuals_Camera:AddToggle("RemoveCameraShake", {
	Text = "Remove Camera Shake", Default = false, Tooltip = "Prevents the camera from shaking.",
	Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage
})
Groupboxes.Visuals_Camera:AddToggle("RemoveCameraBobbing", {
	Text = "Remove Camera Bobbing", Default = false, Tooltip = "Prevents the camera from bobbing when moving.",
	Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage
})
Groupboxes.Visuals_Camera:AddToggle("RemoveCutscenes", { Text = "Remove Cutscenes", Default = false, Tooltip = "Removes all non-necessary cutscenes." })
Groupboxes.Visuals_Camera:AddToggle("RemoveCameraFog", { Text = "Remove Fog", Default = false, Tooltip = "Removes all fog effects from the camera." })
Groupboxes.Visuals_Camera:AddDivider()
Groupboxes.Visuals_Camera:AddToggle("ThirdPersonToggle", { Text = "Third Person", Default = false, Tooltip = "Zooms out your camera, allowing you to see your character from behind." })
Toggles.ThirdPersonToggle:AddKeyPicker("ThirdPersonKeybind", { Text = "Third Person", Default = "T", Mode = "Toggle", SyncToggleState = true })
Groupboxes.Visuals_Camera:AddSlider("ThirdPersonOffsetX", { Text = "X Offset", Min = -10, Max = 10, Default = 1.5, Rounding = 1, Compact = true })
Groupboxes.Visuals_Camera:AddSlider("ThirdPersonOffsetY", { Text = "Y Offset", Min = -10, Max = 10, Default = 1,   Rounding = 1, Compact = true })
Groupboxes.Visuals_Camera:AddSlider("ThirdPersonOffsetZ", { Text = "Z Offset", Min = -10, Max = 10, Default = 5,   Rounding = 1, Compact = true })
Groupboxes.Visuals_Camera:AddToggle("ThirdPersonWallCheck", { Text = "Wall Check", Default = false, Tooltip = "Prevents third person from going through walls." })
Groupboxes.Visuals_Camera:AddDivider()
Groupboxes.Visuals_Camera:AddToggle("ViewmodelOffsetToggle", {
	Text = "Viewmodel Offset", Default = false, Tooltip = "Changes the offset of your viewmodel while holding an item.",
	Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage
})
Groupboxes.Visuals_Camera:AddSlider("ViewmodelOffsetX", { Text = "X Offset", Min = -10, Max = 10, Default = 0, Rounding = 1, Compact = true, Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage })
Groupboxes.Visuals_Camera:AddSlider("ViewmodelOffsetY", { Text = "Y Offset", Min = -10, Max = 10, Default = 0, Rounding = 1, Compact = true, Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage })
Groupboxes.Visuals_Camera:AddSlider("ViewmodelOffsetZ", { Text = "Z Offset", Min = -10, Max = 10, Default = 0, Rounding = 1, Compact = true, Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage })

Toggles.AmbientToggle:AddColorPicker("AmbientColor", { Text = "Ambient", Default = Color3.fromRGB(255, 255, 255), Transparency = 0 })
Toggles.AmbientToggle:OnChanged(function(Value)
	local OldAmbient = CurrentRooms:FindFirstChild(tostring(LocalPlayer:GetAttribute("CurrentRoom"))):GetAttribute("Ambient")
	Services.TweenService:Create(Services.Lighting, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {
		Ambient = Value and Options.AmbientColor.Value or OldAmbient
	}):Play()
end)

local Main_Game
local ClientModules

Toggles.RemoveCameraBobbing:OnChanged(function(Value)
	if Main_Game then Main_Game.spring.Speed = Value and 9e9 or 8 end
end)
Toggles.RemoveCameraFog:OnChanged(function(Value)
	Services.Lighting.FogEnd = Value and 10000000 or Globals.OldFog
	for _, Object in Globals.FogInstances do
		Object.Density = Value and 0 or Object:GetAttribute("Density_Old")
	end
end)
Toggles.RemoveCutscenes:OnChanged(function(Value)
    local Cutscenes = Globals.MainUI.Initiator.Main_Game.RemoteListener.Cutscenes
    for _, Object in pairs(Cutscenes:GetChildren()) do
        if table.find(CutsceneNames, Object.Name) and Object:IsA("ModuleScript") or table.find(CutsceneNames, Object:GetAttribute("OriginalName")) and Object:IsA("ModuleScript") then
            Object.Name = (Value and Object.Name .. "_Disabled" or Object:GetAttribute("OriginalName"))
        end
    end
    for _, Object in pairs(FloorReplicated:GetChildren()) do
        if table.find(CutsceneNames, Object.Name) and Object:IsA("ModuleScript") or table.find(CutsceneNames, Object:GetAttribute("OriginalName")) and Object:IsA("ModuleScript") then
            Object.Name = (Value and Object.Name .. "_Disabled" or Object:GetAttribute("OriginalName"))
        end
    end
end)

Groupboxes.Visuals_Effects = Groupboxes.Visuals_LeftTab:AddTab("Effects")
Groupboxes.Visuals_Effects:AddToggle("TransparentHidingSpotsToggle", { Text = "Transparent Hiding Spots", Default = false, Tooltip = "Makes a hiding spot transparent when you enter it." })
Groupboxes.Visuals_Effects:AddSlider("TransparentHidingSpotsSlider", { Text = "Transparency", Min = 0, Max = 1, Default = 0.5, Rounding = 2, Compact = true })

local function ApplyHidingTransparency(Value, SliderValue)
	for _, Object in Objects.HidingSpots do
		local IsHiding = false
		for _, Child in Object:GetDescendants() do
			if Child.Name == "HiddenPlayer" and Child.Value == Character then
				IsHiding = true
				break
			end
		end
		for _, Part in Object:GetDescendants() do
			if Part:IsA("BasePart") and Part:GetAttribute("Transparency_Old") then
				Services.TweenService:Create(Part, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {
					Transparency = (Value and IsHiding) and SliderValue or Part:GetAttribute("Transparency_Old")
				}):Play()
			end
		end
	end
end

Toggles.TransparentHidingSpotsToggle:OnChanged(function(Value)
	ApplyHidingTransparency(Value, Options.TransparentHidingSpotsSlider.Value)
end)
Options.TransparentHidingSpotsSlider:OnChanged(function(Value)
	ApplyHidingTransparency(Toggles.TransparentHidingSpotsToggle.Value, Value)
end)

Groupboxes.Visuals_Effects:AddDivider()
Groupboxes.Visuals_Effects:AddToggle("DisableGlitchJumpscare",   { Text = "Disable Glitch Jumpscare",   Default = false, Tooltip = "Disables the jumpscare from 'Glitch'" })
Groupboxes.Visuals_Effects:AddToggle("DisableTimothyJumpscare",  { Text = "Disable Timothy Jumpscare",  Default = false, Tooltip = "Disables the jumpscare from 'Timothy'" })
Groupboxes.Visuals_Effects:AddToggle("DisableVoidJumpscare",     { Text = "Disable Void Jumpscare",     Default = false, Tooltip = "Disables the jumpscare from 'Void'" })
Groupboxes.Visuals_Effects:AddDivider()
Groupboxes.Visuals_Effects:AddToggle("DisableHideVignette",      { Text = "Disable Hide Vignette",      Default = false, Tooltip = "Disables the hiding screen effect." })
Groupboxes.Visuals_Effects:AddToggle("DisableFiredampEffect",    { Text = "Disable Firedamp Effect",    Default = false, Tooltip = "Disables the firedamp screen effect." })
Groupboxes.Visuals_Effects:AddToggle("DisableEntityJumpscares",  { Text = "Disable Entity Jumpscares",  Default = false, Tooltip = "Disables jumpscares from entities like Rush and Ambush." })

Toggles.DisableGlitchJumpscare:OnChanged(function(Value)
	Modules.Glitch.Name = Value and "Glitch_Disabled" or "Glitch"
end)
Toggles.DisableTimothyJumpscare:OnChanged(function(Value)
	Modules.SpiderJumpscare.Name = Value and "SpiderJumpscare_Disabled" or "SpiderJumpscare"
end)
Toggles.DisableVoidJumpscare:OnChanged(function(Value)
	if Modules.Void then Modules.Void.Name = Value and "Void_Disabled" or "Void" end
end)
Toggles.DisableHideVignette:OnChanged(function(Value)
	local Vignette = Globals.MainUI:FindFirstChild("HideVignette") or Globals.MainUI.MainFrame:FindFirstChild("HideVignette")
	if Vignette then Vignette.Image = Value and "Disabled" or "rbxassetid://6100076320" end
end)
Toggles.DisableFiredampEffect:OnChanged(function(Value)
	for _, Object in CurrentRooms:GetChildren() do
		if Value then
			Object:SetAttribute("Firedamp", false)
			for _, FiredampObj in Camera:GetChildren() do
				if FiredampObj.Name == "LiveFiredamp" then FiredampObj:Destroy() end
			end
		else
			Object:SetAttribute("Firedamp", Object:GetAttribute("Firedamp_Old"))
		end
	end
	local Old = LocalPlayer:GetAttribute("CurrentRoom")
	LocalPlayer:SetAttribute("CurrentRoom", 0)
	task.wait()
	LocalPlayer:SetAttribute("CurrentRoom", Old)
end)
Toggles.DisableEntityJumpscares:OnChanged(function(Value)
	local Jumpscares = Globals.MainUI.Initiator.Main_Game.RemoteListener:FindFirstChild("Jumpscares")
		or Globals.MainUI.Initiator.Main_Game.RemoteListener:FindFirstChild("Jumpscares_Disabled")
	if Jumpscares then
		Jumpscares.Name = Value and "Jumpscares_Disabled" or "Jumpscares"
		for _, Object in Objects.JumpscareModules do
			Object.Name = Value and (Object:GetAttribute("OriginalName") .. "_Disabled") or Object:GetAttribute("OriginalName")
		end
	end
end)

Groupboxes.Visuals_RightTab     = Tabs.Visuals:AddRightTabbox("Entities / Settings / Entity Nodes")
Groupboxes.Visuals_Entities     = Groupboxes.Visuals_RightTab:AddTab("Entities")
Groupboxes.Visuals_EntitySettings = Groupboxes.Visuals_RightTab:AddTab("Settings")

Groupboxes.Visuals_Entities:AddDropdown("EntityList", {
	Text = "Entity List",
	Values = { "Rush","Bash","Scribbles","Teller","DronesStampede","Creak","Noise","Noise_TV","Balls","Portrait","CreakHalloween","Weaveling","Ambush","Eyes","Halt","Blitz","Lookman","Gloombat Swarm","A-60","A-120","Sally","Jeff the Killer","Groundskeeper","Monument","AR0xMBUSH","RNIUSHCG==" },
	Multi = true, AllowNull = true
})
Groupboxes.Visuals_Entities:AddToggle("NotifyEntities",    { Text = "Notify Entities",    Default = false, Tooltip = "Sends a notification when an entity spawns." })
Groupboxes.Visuals_Entities:AddDivider()
Groupboxes.Visuals_Entities:AddToggle("ShowEntityPath", {
    Text = "Show Entity Path",
    Default = false,
    Tooltip = "Shows the path of entitys."
})


Groupboxes.Visuals_Entities:AddSlider("ShowEntityPathNodeTransparency", {
    Text = "Node Transparency",
    Default = 0,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Compact = false,
    Tooltip = "Transparency of the path nodes when shown"
})

Groupboxes.Visuals_Entities:AddSlider("ShowEntityPathLineTransparency", {
    Text = "Line Transparency",
    Default = 0.15,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Compact = false,
    Tooltip = "Transparency of the path lines"
})

Groupboxes.Visuals_Entities:AddSlider("ShowEntityPathLineThickness", {
    Text = "Line Thickness",
    Default = 0.3,
    Min = 0.08,
    Max = 1.2,
    Rounding = 2
})

local ShowEntityPathLines = {}

local function ShowEntityPathClearAllLines()
    for _, ShowEntityPathRoomLines in pairs(ShowEntityPathLines) do
        for _, ShowEntityPathLine in ipairs(ShowEntityPathRoomLines) do
            if ShowEntityPathLine and ShowEntityPathLine.Parent then
                ShowEntityPathLine:Destroy()
            end
        end
    end
    table.clear(ShowEntityPathLines)
end

local function ShowEntityPathCreateLine(ShowEntityPathPoint1, ShowEntityPathPoint2, ShowEntityPathTransparency, ShowEntityPathThickness, ShowEntityPathParent)
    local ShowEntityPathDistance = (ShowEntityPathPoint1 - ShowEntityPathPoint2).Magnitude
    if ShowEntityPathDistance < 0.05 then
        return nil
    end

    local ShowEntityPathLinePart = Instance.new("Part")
    ShowEntityPathLinePart.Name = "PathLine"
    ShowEntityPathLinePart.Anchored = true
    ShowEntityPathLinePart.CanCollide = false
    ShowEntityPathLinePart.CanQuery = false
    ShowEntityPathLinePart.CanTouch = false
    ShowEntityPathLinePart.CastShadow = false
    ShowEntityPathLinePart.Material = Enum.Material.ForceField
    ShowEntityPathLinePart.Color = Color3.fromRGB(0, 255, 210)
    ShowEntityPathLinePart.Transparency = ShowEntityPathTransparency
    ShowEntityPathLinePart.Size = Vector3.new(ShowEntityPathThickness, ShowEntityPathThickness, ShowEntityPathDistance)
    ShowEntityPathLinePart.CFrame = CFrame.lookAt(ShowEntityPathPoint1, ShowEntityPathPoint2) * CFrame.new(0, 0, -ShowEntityPathDistance / 2)
    ShowEntityPathLinePart.Parent = ShowEntityPathParent
    return ShowEntityPathLinePart
end

local function ShowEntityPathGetSortedNodes(ShowEntityPathNodes)
    local ShowEntityPathSortedNodes = {}
    for _, ShowEntityPathNode in ipairs(ShowEntityPathNodes:GetChildren()) do
        if ShowEntityPathNode:IsA("BasePart") then
            local ShowEntityPathNodeNumber = tonumber(ShowEntityPathNode.Name)
            if ShowEntityPathNodeNumber then
                table.insert(ShowEntityPathSortedNodes, {
                    Part = ShowEntityPathNode,
                    Number = ShowEntityPathNodeNumber
                })
            end
        end
    end
    table.sort(ShowEntityPathSortedNodes, function(a, b)
        return a.Number < b.Number
    end)
    return ShowEntityPathSortedNodes
end

local function ShowEntityPathSetNodeTransparency(ShowEntityPathTransparency)
    for _, ShowEntityPathRoom in ipairs(workspace.CurrentRooms:GetChildren()) do
        local ShowEntityPathNodes = ShowEntityPathRoom:FindFirstChild("PathfindNodes")
        if ShowEntityPathNodes then
            for _, ShowEntityPathNode in ipairs(ShowEntityPathNodes:GetChildren()) do
                if ShowEntityPathNode:IsA("BasePart") then
                    ShowEntityPathNode.Transparency = ShowEntityPathTransparency
                end
            end
        end
    end
end

local function ShowEntityPathSetLineTransparency(ShowEntityPathTransparency)
    for _, ShowEntityPathRoomLines in pairs(ShowEntityPathLines) do
        for _, ShowEntityPathLine in ipairs(ShowEntityPathRoomLines) do
            if ShowEntityPathLine and ShowEntityPathLine.Parent then
                ShowEntityPathLine.Transparency = ShowEntityPathTransparency
            end
        end
    end
end

local function ShowEntityPathUpdateAll()
    local ShowEntityPathShow = Toggles.ShowEntityPath.Value
    local ShowEntityPathNodeTransparency = ShowEntityPathShow and Options.ShowEntityPathNodeTransparency.Value or 1
    local ShowEntityPathLineTransparency = Options.ShowEntityPathLineTransparency.Value
    local ShowEntityPathLineThickness = Options.ShowEntityPathLineThickness.Value

    ShowEntityPathClearAllLines()

    if not ShowEntityPathShow then
        ShowEntityPathSetNodeTransparency(1)
        return
    end

    ShowEntityPathSetNodeTransparency(ShowEntityPathNodeTransparency)

    local ShowEntityPathValidRooms = {}
    for _, ShowEntityPathRoom in ipairs(workspace.CurrentRooms:GetChildren()) do
        if ShowEntityPathRoom:FindFirstChild("PathfindNodes") then
            table.insert(ShowEntityPathValidRooms, ShowEntityPathRoom)
        end
    end

    table.sort(ShowEntityPathValidRooms, function(a, b)
        return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
    end)

    for _, ShowEntityPathRoom in ipairs(ShowEntityPathValidRooms) do
        local ShowEntityPathNodes = ShowEntityPathRoom.PathfindNodes
        local ShowEntityPathSortedNodes = ShowEntityPathGetSortedNodes(ShowEntityPathNodes)

        if #ShowEntityPathSortedNodes > 0 then
            local ShowEntityPathRoomLines = {}

            for i = 1, #ShowEntityPathSortedNodes - 1 do
                local ShowEntityPathFrom = ShowEntityPathSortedNodes[i].Part
                local ShowEntityPathTo = ShowEntityPathSortedNodes[i + 1].Part

                local ShowEntityPathLine = ShowEntityPathCreateLine(
                    ShowEntityPathFrom.Position,
                    ShowEntityPathTo.Position,
                    ShowEntityPathLineTransparency,
                    ShowEntityPathLineThickness,
                    ShowEntityPathRoom
                )
                if ShowEntityPathLine then
                    table.insert(ShowEntityPathRoomLines, ShowEntityPathLine)
                end
            end

            if #ShowEntityPathRoomLines > 0 then
                ShowEntityPathLines[ShowEntityPathRoom] = ShowEntityPathRoomLines
            end
        end
    end
end

Toggles.ShowEntityPath:OnChanged(function()
    if ShowEntityPathChildAddedConnection then
        ShowEntityPathChildAddedConnection:Disconnect()
        ShowEntityPathChildAddedConnection = nil
    end

    ShowEntityPathUpdateAll()

    if Toggles.ShowEntityPath.Value then
        ShowEntityPathChildAddedConnection = workspace.CurrentRooms.ChildAdded:Connect(function(ShowEntityPathRoom)
            if ShowEntityPathRoom:WaitForChild("PathfindNodes", 5) then
                task.wait(0.1)
                ShowEntityPathUpdateAll()
            end
        end)
    end
end)

Options.ShowEntityPathNodeTransparency:OnChanged(function()
    if Toggles.ShowEntityPath.Value then
        ShowEntityPathSetNodeTransparency(Options.ShowEntityPathNodeTransparency.Value)
    end
end)

Options.ShowEntityPathLineTransparency:OnChanged(function()
    if Toggles.ShowEntityPath.Value then
        ShowEntityPathSetLineTransparency(Options.ShowEntityPathLineTransparency.Value)
    end
end)

Options.ShowEntityPathLineThickness:OnChanged(function()
    if Toggles.ShowEntityPath.Value then
        ShowEntityPathUpdateAll()
    end
end)


Groupboxes.Visuals_Entities:AddDivider()

local ItemsToNotify = {}
for Index, Name in pairs(ItemNames) do
	if not table.find(ItemsToNotify, Name) then
		table.insert(ItemsToNotify, Name)
	end
end
table.sort(ItemsToNotify)

Groupboxes.Visuals_Entities:AddDropdown("NotifyItemList", {
	Text = "Item List",
	Values = ItemsToNotify,
	Multi = true, AllowNull = true
})
Groupboxes.Visuals_Entities:AddToggle("NotifyItemsToggle",    { Text = "Notify Items",    Default = false, Tooltip = "Sends a notification when an item spawns." })
Groupboxes.Visuals_Entities:AddToggle("NotifyItemsShowDistance",    { Text = "Show Distance",    Default = false, Tooltip = "Shows how far away the item is in the notification." })
Groupboxes.Visuals_Entities:AddDivider()
Groupboxes.Visuals_Entities:AddToggle("NotifyLibraryCode", { Text = "Notify Library Code", Default = false, Tooltip = "Automatically solves the code for the library padlock." })
Groupboxes.Visuals_Entities:AddToggle("NotifyOxygen",      { Text = "Notify Oxygen Level", Default = false, Tooltip = "Shows how much oxygen you have remaining." })
Groupboxes.Visuals_Entities:AddToggle("NotifyHasteTime",   { Text = "Notify Haste Time",   Default = false, Tooltip = "Shows how much time you have remaining before 'Haste' spawns." })

Globals.LibraryCodeFound = false
Toggles.NotifyLibraryCode:OnChanged(function(Value)
	if Value then
		local Code = Functions.GetLibraryCode()
		if Code and not Code:find("_") and not Globals.LibraryCodeFound and CurrentRooms:FindFirstChild("50") then
			local Lock = Services.Workspace:FindFirstChild("Padlock", true)
			Functions.Notify({ Title = "Padlock code found!", Body = "The code is: '" .. Code .. "'", Time = Toggles.NotifyKeepNotifications.Value and Lock or 15 })
			Globals.LibraryCodeFound = true
		end
	end
end)

Groupboxes.Visuals_EntitySettings:AddToggle("EntityChatToggle", { Text = "Notify Chat", Default = false, Tooltip = "Sends a message in the chat when an entity spawns." })
Groupboxes.Visuals_EntitySettings:AddInput("EntityChatMessage", { Text = "Message", Default = "spawned!", Numeric = false, Placeholder = "Message" })
Groupboxes.Visuals_EntitySettings:AddDivider()
Groupboxes.Visuals_EntitySettings:AddDropdown("NotifyStyle", { Text = "Notify Style", Values = { "Abysall", "Doors", "STX", "Library" }, Default = 1 })
Groupboxes.Visuals_EntitySettings:AddSlider("NotifySoundVolume", { Text = "Sound Volume", Min = 0, Max = 10, Default = 3, Rounding = 1 })
Groupboxes.Visuals_EntitySettings:AddToggle("NotifyPlaySound", { Text = "Play Sound", Default = true, Tooltip = "Makes notifications play an alert sound." })
Groupboxes.Visuals_EntitySettings:AddToggle("NotifyKeepNotifications", { Text = "Keep Notifications", Default = false, Tooltip = "Certain notifications will stay on screen until they are no longer needed." })
Groupboxes.Visuals_EntitySettings:AddButton({ Text = "Test Notification", DoubleClick = false, Tooltip = "Sends a test notifcation, so you can see how your settings look.", Func = function()
	Functions.Notify({Title = "This is a test."})
end})

Groupboxes.Visuals_ESP          = Tabs.Visuals:AddRightTabbox("ESP/Settings")
Groupboxes.Visuals_ESP_Toggles  = Groupboxes.Visuals_ESP:AddTab("ESP")
Groupboxes.Visuals_ESP_Settings = Groupboxes.Visuals_ESP:AddTab("Settings")

local function MakeESPToggle(ToggleKey, ColorKey, Text, Tooltip, ObjectsTable, LabelFunc, RoomBased)
	Groupboxes.Visuals_ESP_Toggles:AddToggle(ToggleKey, { Text = Text, Default = false, Tooltip = Tooltip })
	Toggles[ToggleKey]:AddColorPicker(ColorKey, { Text = Text, Default = Options[ColorKey] and Options[ColorKey].Value or Color3.new(1,1,1), Transparency = 0 })
	Toggles[ToggleKey]:OnChanged(function(Value)
		for _, Object in ObjectsTable do
			if Value then
				local Label, UseRoom = LabelFunc(Object)
				if Label then
					Functions.AddESP({ Object = Object, Text = Label, Color = Options[ColorKey].Value }, UseRoom ~= nil and UseRoom or RoomBased)
				end
			else
				Functions.RemoveESP(Object)
			end
		end
	end)
	Options[ColorKey]:OnChanged(function(Value)
		for _, Object in ObjectsTable do
			Abysall.ESPLibrary:UpdateObjectColor(Object, Value)
		end
	end)
end

Groupboxes.Visuals_ESP_Toggles:AddToggle("ObjectiveESPToggle", { Text = "Objectives", Default = false, Tooltip = "Highlights all objects required to progress." })
Toggles.ObjectiveESPToggle:AddColorPicker("ObjectiveESPColor", { Text = "Objectives", Default = Color3.fromRGB(0, 255, 0), Transparency = 0 })

local ObjectiveLabels = {
	["DepotHalloween"] 		   = "Candy Magic",
	["StairwellLockpickDoor"]  = "Garage Door",
	["Mirror"]				   = "Mirror",
	["ShoppingCart"]		   = "Shopping Cart",
	["StairwellFireAlarm"]     = "Fire Alarm",
	["StairwellScrapper"]	   = "Scrapper",
	["ArchivesPackageDeposit"] = "BoxDeposit",
	["Cellar"] 				   = "Cellar",
	["ArchivesFihTank"]        = "Fih Tank",
	["KeyObtain"]              = "Door Key",
	["ElectricalKeyObtain"]    = "Electrical Key",
	["MinesGenerator"]         = "Generator",
	["FuseObtain"]             = "Generator Fuse",
	["LiveHintBook"]           = "Hint Book",
	["LiveBreakerPolePickup"]  = "Fuse Breaker",
	["LibraryHintPaper"]       = "Hint Paper",
	["PickupItem"]             = "Hint Paper",
	["CringlePresent"]         = "Present",
	["LeverForGate"]           = "Gate Lever",
	["MinesGateButton"]        = "Gate Button",
	["GardenGateButton"]       = "Gate Button",
}

Toggles.ObjectiveESPToggle:OnChanged(function(Value)
	for _, Object in Objects.Objectives do
		if Value then
			local Label = ObjectiveLabels[Object.Name]
			if Object.Name == "TimerLever" then
				Label = "Time Lever [+" .. Object:GetAttribute("AddTime") .. "s]"
			elseif Object.Name == "MinesAnchor" then
				Label = "Anchor [" .. Object:WaitForChild("Sign").TextLabel.Text .. "]"
			elseif Object.Name == "WaterPump" then
				Functions.AddESP({ Object = Object.Wheel, Text = "Water Pump", Color = Options.ObjectiveESPColor.Value }, true)
			elseif Object.Name == "VineGuillotine" then
				Functions.AddESP({ Object = Object.Lever, Text = "Vine Lever", Color = Options.ObjectiveESPColor.Value }, true)
			end
			if Label then
				Functions.AddESP({ Object = Object, Text = Label, Color = Options.ObjectiveESPColor.Value }, true)
			end
		else
			Functions.RemoveESP(Object)
		end
	end
end)
Options.ObjectiveESPColor:OnChanged(function(Value)
	for _, Object in Objects.Objectives do
		Abysall.ESPLibrary:UpdateObjectColor(Object, Value)
	end
end)

Groupboxes.Visuals_ESP_Toggles:AddToggle("DoorESPToggle",       { Text = "Doors",        Default = false, Tooltip = "Highlights the next door." })
Groupboxes.Visuals_ESP_Toggles:AddToggle("HidingSpotESPToggle", { Text = "Hiding Spots", Default = false, Tooltip = "Highlights places where you can hide from entities" })
Groupboxes.Visuals_ESP_Toggles:AddToggle("PlayerESPToggle",     { Text = "Players",      Default = false, Tooltip = "Highlights other players." })
Groupboxes.Visuals_ESP_Toggles:AddToggle("ChestESPToggle",      { Text = "Chests",       Default = false, Tooltip = "Highlights objects that can contain loot." })
Groupboxes.Visuals_ESP_Toggles:AddToggle("ItemESPToggle",       { Text = "Items",        Default = false, Tooltip = "Highlights all collectable items/consumables." })
Groupboxes.Visuals_ESP_Toggles:AddToggle("CurrencyESPToggle",   { Text = "Currency",     Default = false, Tooltip = "Highlights all currency that spawns." })
Groupboxes.Visuals_ESP_Toggles:AddToggle("LadderESPToggle",     { Text = "Ladders",      Default = false, Tooltip = "Highlights ladders that can be used to disable the anticheat." })
Groupboxes.Visuals_ESP_Toggles:AddToggle("MiscESPToggle",       { Text = "Misc",         Default = false, Tooltip = "Highlights miscellaneous objects that can be used to disable the anticheat." })
Groupboxes.Visuals_ESP_Toggles:AddDivider()
Groupboxes.Visuals_ESP_Toggles:AddDropdown("EntityESPOptions",     { 
	Text = "Entity List",
	Values = { "Rush","Bash","Scribbles","Teller","DronesStampede","Creak","Noise","Noise_TV","Balls","Portrait","CreakHalloween","Weaveling","Ambush","Eyes","Dupe","Figure","Blitz","Lookman","Snare","Giggle","Gloombat Eggs","Grumble","A-60","A-120","Sally","Jeff the Killer","Groundskeeper","Mandrake Hole","Monument","Bramble","AR0xMBUSH","RNIUSHCG==" },
	Multi = true,
	AllowNull = true
})
Groupboxes.Visuals_ESP_Toggles:AddToggle("EntityESPToggle",     { Text = "Entities",      Default = false, Tooltip = "Highlights all entities that spawn." })

Toggles.DoorESPToggle:AddColorPicker("DoorESPColor",           { Text = "Doors",        Default = Color3.fromRGB(0, 200, 255),  Transparency = 0 })
Toggles.HidingSpotESPToggle:AddColorPicker("HidingSpotESPColor", { Text = "Hiding Spots", Default = Color3.fromRGB(255, 170, 0),  Transparency = 0 })
Toggles.PlayerESPToggle:AddColorPicker("PlayerESPColor",       { Text = "Players",      Default = Color3.fromRGB(255, 255, 255), Transparency = 0 })
Toggles.ChestESPToggle:AddColorPicker("ChestESPColor",         { Text = "Chests",       Default = Color3.fromRGB(255, 255, 0),   Transparency = 0 })
Toggles.ItemESPToggle:AddColorPicker("ItemESPColor",           { Text = "Items",        Default = Color3.fromRGB(170, 0, 255),   Transparency = 0 })
Toggles.CurrencyESPToggle:AddColorPicker("CurrencyESPColor",   { Text = "Currency",     Default = Color3.fromRGB(255, 255, 0),   Transparency = 0 })
Toggles.LadderESPToggle:AddColorPicker("LadderESPColor",       { Text = "Ladders",      Default = Color3.fromRGB(3, 67, 71), Transparency = 0 })
Toggles.MiscESPToggle:AddColorPicker("MiscESPColor",           { Text = "Misc",         Default = Color3.fromRGB(255, 255, 255), Transparency = 0 })
Toggles.EntityESPToggle:AddColorPicker("EntityESPColor",       { Text = "Entities",     Default = Color3.fromRGB(255, 0, 0),     Transparency = 0 })

local HidingSpotLabels = {
	Wardrobe = "Closet", ["Backdoor_Wardrobe"] = "Closet", Toolshed = "Closet",
	RetroWardrobe = "Closet", ["Wardrobe-FOOLS26"] = "Closet",
	Locker_Large = "Locker", Rooms_Locker = "Hiding_Spot", Rooms_Locker_Fridge = "Locker",
	Bed = "Bed", Double_Bed = "Double Bed", CircularVent = "Vent", Dumpster = "Dumpster"
}
local ChestLabels = {
	ChestBox = true, ChestBoxLocked = true, Toolbox = true, Toolbox_Locked = true,
	Chest_Vine = "Vine Chest", Toolshed_Small = "Toolshed", Locker_Small_Locked = "Locked Item Locker", MouseHole = "Mouse"
}
local EntityESPLabels = {
	JeffTheKiller = "Jeff the Killer", GiggleCeiling = "Giggle",
	Snare = "Snare", GrumbleRig = "Grumble",
	Drakobloxxer = "Drakobloxxer", Hole = "Mandrake Hole", Groundskeeper = "Groundskeeper",
	LiveEntityBramble = "Bramble", Figure = "Figure", FigureRig = "Figure", FigureRagdoll = "Figure",
	FakeDoor = "Dupe", DoorFake = "Dupe"
}

local NodeEntities = {
	Rush = true, Bash = true, Scribbles = true, DronesStampede = true, Ambush = true, Eyes = true, Blitz = true, Lookman = true, ["A-60"] = true, ["A-120"] = true, Sally = true, ["Jeff The Killer"] = true, Monument = true, ["AR0xMBUSH"] = true, ["RNIUSHCG=="] = true
}

Toggles.DoorESPToggle:OnChanged(function(Value)
	for _, Object in Objects.Doors do
		if Value then Functions.AddESP({ Object = Object, Text = "Door " .. Functions.GetDoorNumber(Object), Color = Options.DoorESPColor.Value }, true)
		else Functions.RemoveESP(Object) end
	end
end)
Options.DoorESPColor:OnChanged(function(Value)
	for _, Object in Objects.Doors do Abysall.ESPLibrary:UpdateObjectColor(Object, Value) end
end)

Toggles.HidingSpotESPToggle:OnChanged(function(Value)
	for _, Object in Objects.HidingSpots do
		local Label = HidingSpotLabels[Object.Name]
		if Value and Label then Functions.AddESP({ Object = Object, Text = Label, Color = Options.HidingSpotESPColor.Value }, true)
		elseif not Value then Functions.RemoveESP(Object) end
	end
end)
Options.HidingSpotESPColor:OnChanged(function(Value)
	for _, Object in Objects.HidingSpots do Abysall.ESPLibrary:UpdateObjectColor(Object, Value) end
end)

Toggles.PlayerESPToggle:OnChanged(function(Value)
	task.wait()
	for _, Player in Services.Players:GetPlayers() do
		if Player.Character and Player ~= LocalPlayer then
			if Value and Player:GetAttribute("Alive") == true then
				Functions.AddESP({ Object = Player.Character, Text = Player.Name, Color = Options.PlayerESPColor.Value })
			else
				Functions.RemoveESP(Player.Character)
			end
		end
	end
end)
Options.PlayerESPColor:OnChanged(function(Value)
	for _, Player in Services.Players:GetPlayers() do
		if Player.Character and Player ~= LocalPlayer then
			Abysall.ESPLibrary:UpdateObjectColor(Player.Character, Value)
		end
	end
end)

Toggles.ChestESPToggle:OnChanged(function(Value)
	for _, Object in Objects.Chests do
		if Value then
			local Label
			if Object.Name == "ChestBox" or Object.Name == "ChestBoxLocked" then
				Label = Object:GetAttribute("Locked") and "Locked Chest" or "Chest"
			elseif Object.Name == "Toolbox" or Object.Name == "Toolbox_Locked" then
				Label = Object:GetAttribute("Locked") and "Locked Toolbox" or "Toolbox"
			elseif ChestLabels[Object.Name] and ChestLabels[Object.Name] ~= true then
				Label = ChestLabels[Object.Name]
			end
			if Label then Functions.AddESP({ Object = Object, Text = Label, Color = Options.ChestESPColor.Value }, true) end
		else
			Functions.RemoveESP(Object)
		end
	end
end)

Options.ChestESPColor:OnChanged(function(Value)
	for _, Object in Objects.Chests do Abysall.ESPLibrary:UpdateObjectColor(Object, Value) end
end)

Toggles.ItemESPToggle:OnChanged(function(Value)
	for _, Object in Objects.Items do
		if Value then
			local Label = ItemNames[Object.Name] or (Object.Name == "Green_Herb" and "Green Herb")
			if Label then
				Functions.AddESP({ Object = Object, Text = Label, Color = Options.ItemESPColor.Value }, Object:GetAttribute("ParentRoom") ~= nil)
			end
		else
			Functions.RemoveESP(Object)
		end
	end
end)
Options.ItemESPColor:OnChanged(function(Value)
	for _, Object in Objects.Items do Abysall.ESPLibrary:UpdateObjectColor(Object, Value) end
end)

Toggles.CurrencyESPToggle:OnChanged(function(Value)
	for _, Object in Objects.Currency do
		if Value then
			local Label
			if Object.Name == "GoldPile" and Object:GetAttribute("GoldValue") then
				Label = "Gold Pile [" .. Object:GetAttribute("GoldValue") .. "]"
			elseif Object.Name == "StardustPickup" then
				Label = "Stardust Pile"
			end
			if Label then Functions.AddESP({ Object = Object, Text = Label, Color = Options.CurrencyESPColor.Value }, true) end
		else
			Functions.RemoveESP(Object)
		end
	end
end)
Options.CurrencyESPColor:OnChanged(function(Value)
	for _, Object in Objects.Currency do Abysall.ESPLibrary:UpdateObjectColor(Object, Value) end
end)

Toggles.EntityESPToggle:OnChanged(function(Value)
	for _, Object in Objects.Entities do
		if Value then
			local Label = EntityESPLabels[Object.Name]
			if not Label and Entities[Object.Name] then Label = Entities[Object.Name].Alias end
			if Label and Options.EntityESPOptions.Value[Label] then
				Functions.AddESP({ Object = Object, Text = Label, Color = Options.EntityESPColor.Value }, NodeEntities[Label] ~= true)
			else
				Functions.RemoveESP(Object)
			end
		else
			Functions.RemoveESP(Object)
		end
	end
end)

Options.EntityESPOptions:OnChanged(function(Value)
	for _, Object in Objects.Entities do
		if Toggles.EntityESPToggle.Value then
			local Label = EntityESPLabels[Object.Name]
			if not Label and Entities[Object.Name] then Label = Entities[Object.Name].Alias end
			if Label and Options.EntityESPOptions.Value[Label] then
				Functions.AddESP({ Object = Object, Text = Label, Color = Options.EntityESPColor.Value }, NodeEntities[Label] ~= true)
			else
				Functions.RemoveESP(Object)
			end
		else
			Functions.RemoveESP(Object)
		end
	end
end)

Options.EntityESPColor:OnChanged(function(Value)
	for _, Object in Objects.Entities do Abysall.ESPLibrary:UpdateObjectColor(Object, Value) end
end)

Toggles.LadderESPToggle:OnChanged(function(Value)
	for _, Object in Objects.Ladders do
		if Value then Functions.AddESP({ Object = Object, Text = "Ladder", Color = Options.LadderESPColor.Value }, true)
		else Functions.RemoveESP(Object) end
	end
end)
Options.LadderESPColor:OnChanged(function(Value)
	for _, Object in Objects.Ladders do Abysall.ESPLibrary:UpdateObjectColor(Object, Value) end
end)

Toggles.MiscESPToggle:OnChanged(function(Value)
	for _, Object in Objects.Misc do
		if Value then
			local Label = Object.Name
			if Object.Name == "StairwellLockpickDoor" or Object.Name == "StiarwellLockpickDoor" then
				Label = "Garage Door"
			elseif Object.Name == "StairwellFireAlarm" then
				Label = "Fire Alarm"
			elseif Object.Name == "ShoppingCart" then
				Label = "Shopping Cart"
			elseif Object.Name == "ArchivesFihTank" or Object.Name == "ArchivesFishTank" then
				Label = "Fish Tank"
			end
			Functions.AddESP({ Object = Object, Text = Label, Color = Options.MiscESPColor.Value }, true)
		else
			Functions.RemoveESP(Object)
		end
	end
end)
Options.MiscESPColor:OnChanged(function(Value)
	for _, Object in Objects.Misc do Abysall.ESPLibrary:UpdateObjectColor(Object, Value) end
end)

Groupboxes.Visuals_ESP_Settings:AddToggle("ESPRainbow",     { Text = "Rainbow Effect", Default = false, Tooltip = "Makes the esp objects change colour like a rainbow." })
Groupboxes.Visuals_ESP_Settings:AddToggle("ESPShowDistance",{ Text = "Show Distance",  Default = true,  Tooltip = "Shows how far away your character is from the object." })
Groupboxes.Visuals_ESP_Settings:AddDivider()
Groupboxes.Visuals_ESP_Settings:AddSlider("ESPFillTransparency",        { Text = "Fill Transparency",         Min = 0, Max = 1, Default = 0.75, Rounding = 2, Compact = true })
Groupboxes.Visuals_ESP_Settings:AddSlider("ESPOutlineTransparency",     { Text = "Outline Transparency",      Min = 0, Max = 1, Default = 0,    Rounding = 2, Compact = true })
Groupboxes.Visuals_ESP_Settings:AddSlider("ESPTextTransparency",        { Text = "Text Transparency",         Min = 0, Max = 1, Default = 0,    Rounding = 2, Compact = true })
Groupboxes.Visuals_ESP_Settings:AddSlider("ESPTextOutlineTransparency", { Text = "Text Outline Transparency", Min = 0, Max = 1, Default = 0,    Rounding = 2, Compact = true })
Groupboxes.Visuals_ESP_Settings:AddSlider("ESPFadeTime",                { Text = "Fade Time",                 Min = 0, Max = 1, Default = 0.25, Rounding = 2, Compact = true })
Groupboxes.Visuals_ESP_Settings:AddSlider("ESPRenderLimit",             { Text = "Render Limit",              Min = 30, Max = 240, Default = 240, Rounding = 0, Compact = true })
Groupboxes.Visuals_ESP_Settings:AddSlider("ESPTextSize",                { Text = "Text Size",                 Min = 12, Max = 24, Default = 20, Rounding = 0, Compact = true })
Groupboxes.Visuals_ESP_Settings:AddDropdown("ESPTextFont", {
	Text = "Text Font",
	Values = { "Legacy","Arial","ArialBold","SourceSans","SourceSansBold","SourceSansLight","SourceSansItalic","Bodoni","Garamond","Cartoon","Code","Highway","SciFi","Arcade","Fantasy","Antique","SourceSansSemibold","Gotham","GothamMedium","GothamBold","GothamBlack","AmaticSC","Bangers","Creepster","DenkOne","Fondamento","FredokaOne","GrenzeGotisch","IndieFlower","JosefinSans","Jura","Kalam","LuckiestGuy","Merriweather","Michroma","Nunito","Oswald","PatrickHand","PermanentMarker","Roboto","RobotoCondensed","RobotoMono","Sarpanch","SpecialElite","TitilliumWeb","Ubuntu","BuilderSans","BuilderSansMedium","BuilderSansBold","BuilderSansExtraBold","Arimo","ArimoBold" },
	Default = 12
})
Groupboxes.Visuals_ESP_Settings:AddDivider()
Groupboxes.Visuals_ESP_Settings:AddDropdown("ESPTracersOrigin",  { Text = "Tracer Origin", Values = { "Bottom","Center","Top","Mouse" }, Default = 1 })
Groupboxes.Visuals_ESP_Settings:AddSlider("ESPTracerThickness",  { Text = "Tracer Thickness", Min = 0.5, Max = 2, Default = 0.75, Rounding = 2, Compact = true })
Groupboxes.Visuals_ESP_Settings:AddToggle("ESPTracersToggle",    { Text = "Enable Tracers", Default = false, Tooltip = "Draws a line to highlighted objects." })
Groupboxes.Visuals_ESP_Settings:AddDivider()
Groupboxes.Visuals_ESP_Settings:AddSlider("ESPArrowsRadius",     { Text = "Arrow Radius", Min = 100, Max = 500, Default = 250, Rounding = 0, Compact = true })
Groupboxes.Visuals_ESP_Settings:AddToggle("ESPArrowsToggle",     { Text = "Enable Arrows", Default = false, Tooltip = "Shows arrow that point to off-screen objects." })

Abysall.ESPLibrary:SetRainbow(false)
Abysall.ESPLibrary:SetShowDistance(true)
Abysall.ESPLibrary:SetFillTransparency(0.75)
Abysall.ESPLibrary:SetOutlineTransparency(0)
Abysall.ESPLibrary:SetTextTransparency(0)
Abysall.ESPLibrary:SetTextOutlineTransparency(0)
Abysall.ESPLibrary:SetRenderLimit(240)
Abysall.ESPLibrary:SetFadeTime(0.25)
Abysall.ESPLibrary:SetTextSize(20)
Abysall.ESPLibrary:SetFont(Enum.Font.Highway)
Abysall.ESPLibrary:SetTracers(false)
Abysall.ESPLibrary:SetTracerSize(0.75)
Abysall.ESPLibrary:SetTracerOrigin("Bottom")
Abysall.ESPLibrary:SetArrows(false)
Abysall.ESPLibrary:SetArrowRadius(250)
Abysall.ESPLibrary:SetDistanceSizeRatio(0.8)

Toggles.ESPRainbow:OnChanged(function(V)        Abysall.ESPLibrary:SetRainbow(V) end)
Toggles.ESPShowDistance:OnChanged(function(V)   Abysall.ESPLibrary:SetShowDistance(V) end)
Options.ESPFillTransparency:OnChanged(function(V)        Abysall.ESPLibrary:SetFillTransparency(V) end)
Options.ESPOutlineTransparency:OnChanged(function(V)     Abysall.ESPLibrary:SetOutlineTransparency(V) end)
Options.ESPTextTransparency:OnChanged(function(V)        Abysall.ESPLibrary:SetTextTransparency(V) end)
Options.ESPTextOutlineTransparency:OnChanged(function(V) Abysall.ESPLibrary:SetTextOutlineTransparency(V) end)
Options.ESPFadeTime:OnChanged(function(V)        Abysall.ESPLibrary:SetFadeTime(V) end)
Options.ESPRenderLimit:OnChanged(function(V)     Abysall.ESPLibrary:SetRenderLimit(V) end)
Options.ESPTextSize:OnChanged(function(V)        Abysall.ESPLibrary:SetTextSize(V) end)
Options.ESPTextFont:OnChanged(function(V)        Abysall.ESPLibrary:SetFont(Enum.Font[V]) end)
Toggles.ESPTracersToggle:OnChanged(function(V)   Abysall.ESPLibrary:SetTracers(V) end)
Options.ESPTracersOrigin:OnChanged(function(V)   Abysall.ESPLibrary:SetTracerOrigin(V) end)
Options.ESPTracerThickness:OnChanged(function(V) Abysall.ESPLibrary:SetTracerSize(V) end)
Toggles.ESPArrowsToggle:OnChanged(function(V)    Abysall.ESPLibrary:SetArrows(V) end)
Options.ESPArrowsRadius:OnChanged(function(V)    Abysall.ESPLibrary:SetArrowRadius(V) end)

Tabs.Floors:UpdateWarningBox({
	Visible = true,
	Title = "Compatability/Risk Warning",
	Text = "Features highlighted in red are risky / dont work in the current floor.",
})
Groupboxes.Floors_Automation = Tabs.Floors:AddRightGroupbox("Automation")

Groupboxes.Floors_Automation:AddToggle("SkipSeekMines", {
	Text = "Skip Seek (Mines)",
	Default = false,
	Tooltip = "Skips the entire Seek sections.",
	Risky = Floor ~= "Mines"
})

Toggles.SkipSeekMines:OnChanged(function(Value)
	if Value then
		if Floor ~= "Mines" then
			return
		end
		task.spawn(function()
			local MinesSkipSeekCurrentRooms

			repeat
				if not Toggles.SkipSeekMines.Value then
					return
				end

				MinesSkipSeekCurrentRooms = workspace:FindFirstChild("CurrentRooms")
				task.wait()
			until MinesSkipSeekCurrentRooms

			local MinesSkipSeekStartRoom

			repeat
				if not Toggles.SkipSeekMines.Value then
					return
				end

				MinesSkipSeekCurrentRooms = workspace:FindFirstChild("CurrentRooms")

				if MinesSkipSeekCurrentRooms then
					MinesSkipSeekStartRoom = MinesSkipSeekCurrentRooms:FindFirstChild("42")
				end

				task.wait()
			until MinesSkipSeekStartRoom

			local MinesSkipSeekStartDoor

			repeat
				if not Toggles.SkipSeekMines.Value then
					return
				end

				MinesSkipSeekStartDoor = MinesSkipSeekStartRoom:FindFirstChild("Door", true)
				task.wait()
			until MinesSkipSeekStartDoor

			repeat
				if not Toggles.SkipSeekMines.Value then
					return
				end

				task.wait()
			until MinesSkipSeekStartDoor:GetAttribute("Opened") == true

			if Character and Character:GetAttribute("Minecarting") == true then
				Character:SetAttribute("Minecarting", false)
			end

			for _, MinesSkipSeekRoomNumber in ipairs({
				43, 44, 45, 46, 47, 48, 49,
				78, 79, 80, 81, 82, 83
			}) do
				if not Toggles.SkipSeekMines.Value then
					return
				end

				local MinesSkipSeekRoom

				repeat
					if not Toggles.SkipSeekMines.Value then
						return
					end

					MinesSkipSeekCurrentRooms = workspace:FindFirstChild("CurrentRooms")

					if MinesSkipSeekCurrentRooms then
						MinesSkipSeekRoom = MinesSkipSeekCurrentRooms:FindFirstChild(
							tostring(MinesSkipSeekRoomNumber)
						)
					end

					task.wait()
				until MinesSkipSeekRoom

				local MinesSkipSeekDoor

				repeat
					if not Toggles.SkipSeekMines.Value then
						return
					end

					MinesSkipSeekDoor = MinesSkipSeekRoom:FindFirstChild("Door", true)
					task.wait()
				until MinesSkipSeekDoor

				repeat
					if not Toggles.SkipSeekMines.Value then
						return
					end

					if Character then
						Character:PivotTo(MinesSkipSeekDoor:GetPivot())
					end

					task.wait()
				until MinesSkipSeekDoor:GetAttribute("Opened") == true

				if MinesSkipSeekRoomNumber == 49 or MinesSkipSeekRoomNumber == 83 then
					if not Character then
						return
					end

					local MinesSkipSeekVoidPivot = Character:GetPivot()
					MinesSkipSeekVoidPivot = MinesSkipSeekVoidPivot + Vector3.new(0, -1000, 0)

					task.wait(0.3)

					for MinesSkipSeekVoidCount = 1, 12 do
						Character:PivotTo(MinesSkipSeekVoidPivot)
					end

					for MinesSkipSeekVoidCount = 1, 12 do
						Character:PivotTo(MinesSkipSeekVoidPivot)
					end

					for MinesSkipSeekVoidCount = 1, 12 do
						Character:PivotTo(MinesSkipSeekVoidPivot)
					end

					task.wait(0.3)

					for MinesSkipSeekVoidCount = 1, 6 do
						Character:PivotTo(MinesSkipSeekVoidPivot)
					end
				end

				if MinesSkipSeekRoomNumber == 83 then
					return
				end
			end
		end)
	end
end)

Groupboxes.Floors_Automation:AddToggle("AutoSteerMinecart", {
	Text = "Auto Steer Minecart", Default = false, Tooltip = "Automatically completes the minecart chase.",
	Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage
})
Groupboxes.Floors_Automation:AddSlider("AutoSteerMinecartTurnDistance", {
	Text = "Turn Distance", Min = 20, Max = 40, Default = 30, Rounding = 0,
	Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage
})
Groupboxes.Floors_Automation:AddSlider("AutoSteerMinecartDuckDistance", {
	Text = "Crouch Distance", Min = 20, Max = 40, Default = 30, Rounding = 0,
	Disabled = not Functions.CheckCompatability({"require"}), DisabledTooltip = Globals.IncompatibleMessage
})
Groupboxes.Floors_Automation:AddDivider()
Groupboxes.Floors_Automation:AddToggle("RoomsAutoWalk",             { Text = "Auto Rooms",       Default = false, Tooltip = "Automatically moves and hides from entities in The Rooms." })
Groupboxes.Floors_Automation:AddSlider("RoomsAutoWalkPathfindTimeout", { Text = "Pathfind Timeout", Min = 0.5, Max = 3, Default = 1, Rounding = 1 })
Groupboxes.Floors_Automation:AddToggle("RoomsAutoWalkIgnoreA60",    { Text = "Ignore A-60",      Default = false, Tooltip = "Continues to walk if entity 'A-60' is present, enables position spoof automatically." })
Groupboxes.Floors_Automation:AddToggle("RoomsAutoWalkShowPathToggle", { Text = "Show Path",       Default = false, Tooltip = "Shows the current path of rooms auto-walk." })
Groupboxes.Floors_Automation:AddToggle("RoomsAutoWalkSpoofFootsteps", {
    Text = "Spoof Footsteps", Default = false, Tooltip = "Makes it appear as if your character is walking normally.",
    Disabled = not Functions.CheckCompatability({"hookmetamethod", "newcclosure", "getnamecallmethod"}), DisabledTooltip = Globals.IncompatibleMessage
})

Toggles.RoomsAutoWalk:OnChanged(function()
	for _, Object in Globals.RoomsNodesFolder:GetChildren() do
		if Object.Name == "PathNode" then Object:Destroy() end
	end
end)
Toggles.RoomsAutoWalkShowPathToggle:AddColorPicker("RoomsAutoWalkShowPathColor", { Text = "Path", Default = Color3.fromRGB(0, 255, 0), Transparency = 0 })
Toggles.RoomsAutoWalkShowPathToggle:OnChanged(function(Value)
	for _, Object in Globals.RoomsNodesFolder:GetChildren() do
		if Object.Name == "PathNode" then Object.Transparency = Value and 0.5 or 1 end
	end
end)
Options.RoomsAutoWalkShowPathColor:OnChanged(function(Value)
	for _, Object in Globals.RoomsNodesFolder:GetChildren() do
		if Object.Name == "PathNode" then Object.Color = Value end
	end
end)

Functions.RoomsAutoWalk = {}
Functions.RoomsAutoWalk.GetNearestHidingSpot = function()
	local Nearest = { Distance = math.huge, Object = nil }
	for _, Object in Objects.HidingSpots do
		if Object.PrimaryPart and Object:FindFirstChild("HidePrompt") then
			local Distance = LocalPlayer:DistanceFromCharacter(Object.PrimaryPart.Position)
			if Distance < Nearest.Distance and Object.PrimaryPart.Position.Y > -10 then
				local HiddenPlayer = Object:FindFirstChild("HiddenPlayer", true)
				if HiddenPlayer and not HiddenPlayer.Value then
					Nearest.Distance = Distance
					Nearest.Object = Object
				end
			end
		end
	end
	return Nearest.Object
end

local RoomsEntityList = { "RushMoving","AmbushMoving","BackdoorRush","A60","A120","CustomEntity","GlitchRush","GlitchAmbush" }
Functions.RoomsAutoWalk.GetPathfindTarget = function()
	for _, Object in Services.Workspace:GetChildren() do
		if table.find(RoomsEntityList, Object.Name) and Object.PrimaryPart then
			local Y = Object.PrimaryPart.Position.Y
			if Y > -10 and Y < 150 then
				if Object.Name == "A60" and not Toggles.RoomsAutoWalkIgnoreA60.Value or Object.Name ~= "A60" then
					return Functions.RoomsAutoWalk.GetNearestHidingSpot() or CurrentRooms[tostring(LatestRoom.Value)]:FindFirstChild("RoomExit")
				end
			end
		end
	end
	return CurrentRooms[tostring(LatestRoom.Value)]:FindFirstChild("RoomExit")
end

Connections.RoomsAutoWalkHandler = Services.RunService.Heartbeat:Connect(function()
	if Floor ~= "Rooms" or not Toggles.RoomsAutoWalk.Value or Globals.RoomsAutoWalkActive or Globals.RoomsNudge or not CollisionPart or LatestRoom.Value >= 1000 then return end
	Globals.RoomsAutoWalkActive = true

	local Path = Services.PathfindingService:CreatePath({
		AgentCanJump = true, AgentCanClimb = false, WaypointSpacing = 4,
		AgentRadius = 1.5, AgentHeight = 1.5, Costs = { StuckPart = 8 }
	})

	if Toggles.RoomsAutoWalkIgnoreA60.Value and not Toggles.PositionSpoof.Value then
		Toggles.PositionSpoof:SetValue(true)
	end

	local TargetPart = Functions.RoomsAutoWalk.GetPathfindTarget()
	if not TargetPart then
		Globals.RoomsAutoWalkActive = false
		return
	end

	local TargetPosition
	if TargetPart.Name == "RoomExit" then
		TargetPosition = TargetPart.Position
	elseif TargetPart:FindFirstChild("HidePrompt") then
		for _, Part in TargetPart:GetDescendants() do
			if Part:IsA("BasePart") then Part.CanCollide = false end
		end
		TargetPosition = TargetPart.PrimaryPart.Position
	end

	if CollisionPart.Anchored and not TargetPart:FindFirstChild("HidePrompt") then
		Character:SetAttribute("Hiding", true)
		RemotesFolder.CamLock:FireServer()
		Character:SetAttribute("Hiding", false)
	end
	-- DontGroup
	local CurrentRoom = CurrentRooms[tostring(LatestRoom.Value)]
	if CurrentRoom:FindFirstChild("Door") then
		CurrentRoom.Door.Door.CanCollide = false
	end

	if not TargetPosition or LocalPlayer:DistanceFromCharacter(TargetPosition) >= 750 then
		Globals.RoomsAutoWalkActive = false
		return
	end

	Path:ComputeAsync(CollisionPart.Position, TargetPosition)
	local Waypoints = Path:GetWaypoints()

	if #Waypoints == 0 then
		local RoomExit = CurrentRoom:FindFirstChild("RoomExit")
		if RoomExit then Humanoid:MoveTo(RoomExit.Position) end
		Globals.RoomsAutoWalkActive = false
		return
	end

	for _, Node in Globals.RoomsNodesFolder:GetChildren() do
		if Node.Name == "PathNode" then Node:Destroy() end
	end

	for _, Waypoint in Waypoints do
		local Block = Instance.new("Part", Globals.RoomsNodesFolder)
		Block.Transparency = Toggles.RoomsAutoWalkShowPathToggle.Value and 0.5 or 1
		Block.Size = Vector3.one
		Block.Position = Waypoint.Position
		Block.Shape = Enum.PartType.Ball
		Block.CanCollide = false
		Block.Anchored = true
		Block.Name = "PathNode"
		Block.Color = Options.RoomsAutoWalkShowPathColor.Value
		Block.Material = Enum.Material.Neon
	end

	local Stuck = false
	for _, Waypoint in Waypoints do
		if Stuck or not Toggles.RoomsAutoWalk.Value then break end

		local Finished = false
		local Start = tick()

		local StepConnection = Services.RunService.RenderStepped:Connect(function()
			if Stuck or not Toggles.RoomsAutoWalk.Value then Finished = true return end

			local NewTarget = Functions.RoomsAutoWalk.GetPathfindTarget()
			if NewTarget and NewTarget:FindFirstChild("HidePrompt") and not TargetPart:FindFirstChild("HidePrompt") then
				Finished = true return
			end
			if TargetPart:FindFirstChild("HidePrompt") then
				local HidePrompt = TargetPart:FindFirstChild("HidePrompt")
				if LocalPlayer:DistanceFromCharacter(TargetPosition) < HidePrompt.MaxActivationDistance
					and Character:GetAttribute("Hiding") ~= true
				then
					Functions.ForceFirePrompt(HidePrompt)
				end
			end
			local FlatPos = Vector3.new(Waypoint.Position.X, RootPart.Position.Y, Waypoint.Position.Z)
			if LocalPlayer:DistanceFromCharacter(FlatPos) < 5 then Finished = true end
			Humanoid:MoveTo(Waypoint.Position)
		end)

		while not Finished do
			if tick() - Start > Options.RoomsAutoWalkPathfindTimeout.Value then
				local StuckBlock = Instance.new("Part", Globals.RoomsNodesFolder)
				StuckBlock.Transparency = 1
				StuckBlock.Size = Vector3.one
				StuckBlock.CFrame = Collision.CFrame
				StuckBlock.Shape = Enum.PartType.Ball
				StuckBlock.CanCollide = false
				StuckBlock.Anchored = true
				StuckBlock.Name = "StuckPart"
				local Modifier = Instance.new("PathfindingModifier", StuckBlock)
				Modifier.Label = "StuckPart"
				Stuck = true
				break
			end
			task.wait()
		end
		StepConnection:Disconnect()
		Humanoid:MoveTo(RootPart.Position)
	end

	Globals.RoomsAutoWalkActive = false
end)

Connections.RoomsHandler = CurrentRooms.ChildAdded:Connect(function(Room)
	for _, Object in Globals.RoomsNodesFolder:GetChildren() do
		if Object.Name == "StuckPart" then Object:Destroy() end
	end

	if Room:GetAttribute("RawName") and string.find(Room:GetAttribute("RawName"), "Eyestalk") then
        local PreviousNode = nil

		local function CreateEyestalkNode(WaypointPos)
			local NewNode = Instance.new("Part")
			NewNode.Size = Vector3.one
			NewNode.Transparency = 1
			NewNode.Parent = Globals.SeekNodesFolder
			NewNode.Anchored = true
			NewNode.Position = WaypointPos
			NewNode.CanCollide = false
			NewNode.Name = "SeekLightNode"

			local PrevNode = PreviousNode or NewNode
			PreviousNode = NewNode

			local NewBeam = Instance.new("Beam")
			NewBeam.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Options.ShowEyestalkPathColor.Value), ColorSequenceKeypoint.new(1, Options.ShowEyestalkPathColor.Value) })
			NewBeam.FaceCamera = true
			NewBeam.Width0 = 0.2
			NewBeam.Width1 = 0.2
			NewBeam.Brightness = 10
			NewBeam.LightInfluence = 0
			NewBeam.LightEmission = 0
			NewBeam.Enabled = true

			local Vis = Toggles.ShowEyestalkPathToggle.Value and 0 or 1
			NewBeam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, Vis), NumberSequenceKeypoint.new(1, Vis) })
			NewBeam.Parent = Globals.SeekNodesFolder

			local A0 = Instance.new("Attachment", NewNode)
			local A1 = Instance.new("Attachment", PrevNode)
			NewBeam.Attachment0 = A0
			NewBeam.Attachment1 = A1

			table.insert(Objects.EyestalkHighlights, NewBeam)
		end

		Room:WaitForChild("RoomEntrance", 9e9)
		Room:WaitForChild("RoomExit", 9e9)

		while not Room:GetAttribute("PathFound") do
			if Toggles.ShowEyestalkPathToggle.Value then
				local EyePath = game:GetService("PathfindingService"):CreatePath({
					AgentCanJump = false, AgentCanClimb = false, WaypointSpacing = 2, AgentRadius = 1, AgentHeight = 1
				})
				EyePath:ComputeAsync(RootPart.Position, Room.RoomExit.Position)
				if EyePath.Status == Enum.PathStatus.Success then
					Room:SetAttribute("PathFound", true)
					for _, Waypoint in EyePath:GetWaypoints() do
						CreateEyestalkNode(Waypoint.Position)
						task.wait()
					end
                    break
				end
			end
			task.wait(0.25)
		end
	end
end)

Groupboxes.Floors_Completion = Tabs.Floors:AddRightGroupbox("Completion")
Groupboxes.Floors_Completion:AddButton({
    Text = "Auto Complete Dam Seek",
    Tooltip = "Automatically teleports to and interacts with each water pump.",
    Func = function()
        if LatestRoom.Value < 100 or Floor ~= "Mines" then
            Functions.Notify({Title = "You must be in Room 200 to do this."})
            return
        end

		local IsCutscene = false
		local CutsceneConnection = RemotesFolder.Cutscene.OnClientEvent:Connect(function()
			IsCutscene = true
			task.wait(7)
			IsCutscene = false
		end)

        local function GetNextPump()
            local Highest = {
                Height = -69420,
                Object = nil
            }
            for _, Object in pairs(Objects.Objectives) do
                if Object.Name == "WaterPump" and Object:GetAttribute("Abysall_Completed") ~= true then
                    if Object.PrimaryPart and Object.PrimaryPart.Position.Y > Highest.Height then
                        Highest.Object = Object
                        Highest.Height = Object.PrimaryPart.Position.Y
                    end
                end
            end
            return Highest.Object
        end

        local function HandlePump(Pump)

            while task.wait(0.1) do
				if IsCutscene then
					continue
				end

                Character:PivotTo(Pump:GetPivot())

                local Prompt = Pump:FindFirstChild("ValvePrompt", true)
                if Prompt then
                    Functions.ForceFirePrompt(Prompt)
                end

                if Pump:GetAttribute("Abysall_Completed") then
                    break
                end
            end
        end

        Functions.Notify({Title = "Attempting to complete the valves.", Body = "Please wait."})
        while task.wait(0.1) do
            local Pump = GetNextPump()
            if Pump then
                HandlePump(Pump)
            else
                break
            end
        end
        Functions.Notify({Title = "Successfully completed the valves."})
    end
})

Groupboxes.Floors_Completion:AddButton({
    Text = "Auto Complete Cringle",
    Tooltip = "Instantly completes the quest.",
    Func = function()
        local TouchPart = CurrentRooms:FindFirstChild("RippleExitDoor", true)
        if TouchPart then
            Character:PivotTo(TouchPart:GetPivot())
        end
    end
})

Groupboxes.Floors_Visuals = Tabs.Floors:AddLeftGroupbox("Visuals")
Groupboxes.Floors_Visuals:AddToggle("ShowSeekPathToggle", {
	Text = "Show Seek Path", Default = false, Tooltip = "Shows you the correct path in seek chases.",
	Risky = Floor ~= "Mines"
})
Toggles.ShowSeekPathToggle:AddColorPicker("ShowSeekPathColor", { Text = "Seek Path", Default = Color3.fromRGB(0, 255, 0), Transparency = 0 })

local function UpdateBeamVisibility(BeamTable, ColorKey, Visible)
	local Vis = Visible and 0 or 1
	local Seq = NumberSequence.new({ NumberSequenceKeypoint.new(0, Vis), NumberSequenceKeypoint.new(1, Vis) })
	for _, Beam in BeamTable do Beam.Transparency = Seq end
end
local function UpdateBeamColor(BeamTable, Value)
	local Seq = ColorSequence.new({ ColorSequenceKeypoint.new(0, Value), ColorSequenceKeypoint.new(1, Value) })
	for _, Beam in BeamTable do Beam.Color = Seq end
end

Toggles.ShowSeekPathToggle:OnChanged(function(V)  UpdateBeamVisibility(Objects.SeekHighlights, "ShowSeekPathColor", V) end)
Options.ShowSeekPathColor:OnChanged(function(V)   UpdateBeamColor(Objects.SeekHighlights, V) end)

Groupboxes.Floors_Visuals:AddToggle("ShowEyestalkPathToggle", {
	Text = "Show Eyestalk Path", Default = false, Tooltip = "Shows you the correct path in the eyestalk chase.",
	Risky = Floor ~= "Garden"
})
Toggles.ShowEyestalkPathToggle:AddColorPicker("ShowEyestalkPathColor", { Text = "Eyestalk Path", Default = Color3.fromRGB(0, 255, 0), Transparency = 0 })
Toggles.ShowEyestalkPathToggle:OnChanged(function(V) UpdateBeamVisibility(Objects.EyestalkHighlights, "ShowEyestalkPathColor", V) end)
Options.ShowEyestalkPathColor:OnChanged(function(V)  UpdateBeamColor(Objects.EyestalkHighlights, V) end)

Groupboxes.Floors_Bypass = Tabs.Floors:AddLeftGroupbox("Bypass")
Groupboxes.Floors_Bypass:AddToggle("RemoveSeekTrigger", {
	Text = "Delete Seek Trigger", Default = false, Tooltip = "Diables the 'Seek' chase trigger.",
	Risky = not (Floor == "Fools" or Floor == "OldHotel"),
	Disabled = not Functions.CheckCompatability({"firetouchinterest"}), DisabledTooltip = Globals.IncompatibleMessage
})
Groupboxes.Floors_Bypass:AddToggle("RemoveFigure", {
	Text = "Delete Figure", Default = false, Tooltip = "Completely removes the entity 'Figure' (doesn't always work).",
	Risky = not (Floor == "Fools" or Floor == "OldHotel" or Floor == "Mines"),
	Disabled = not Functions.CheckCompatability({"isnetworkowner"}), DisabledTooltip = Globals.IncompatibleMessage
})
Groupboxes.Floors_Bypass:AddToggle("AutoRevive", {
	Text = "Infinite Revives", Default = false, Tooltip = "Automatically revives after dying, with unlimited respawns.",
	Risky = not (Floor == "Fools" or Floor == "OldHotel")
})
Groupboxes.Floors_Bypass:AddToggle("FigureGodmode", {
	Text = "Figure Godmode", Default = false, Tooltip = "Prevents 'Figure' from hurting you.",
	Risky = not (Floor == "Fools" or Floor == "OldHotel")
})
Groupboxes.Floors_Bypass:AddDivider()
Groupboxes.Floors_Bypass:AddToggle("RemoveBasementGate",  { Text = "Remove Basement Gate",   Default = false, Tooltip = "Removes the gate from basement rooms.",            Risky = not (Floor == "Fools" or Floor == "OldHotel") })
Groupboxes.Floors_Bypass:AddToggle("RemovePaintingsDoor", { Text = "Remove Paintings Door",  Default = false, Tooltip = "Removes the fireplace doors from painting rooms.", Risky = not (Floor == "Fools" or Floor == "OldHotel") })
Groupboxes.Floors_Bypass:AddToggle("RemoveSkeletonDoor",  { Text = "Remove Skeleton Door",   Default = false, Tooltip = "Removes the skeleton door from the infirmary.",    Risky = Floor ~= "Fools" })

local ObstructionNames = { ThingToOpen = "RemoveBasementGate", MovingDoor = "RemovePaintingsDoor", Wax_Door = "RemoveSkeletonDoor" }
for ObjName, ToggleName in ObstructionNames do
	Toggles[ToggleName]:OnChanged(function(Value)
		for _, Object in Objects.Obstructions do
			if Object.Name == ObjName then
				Object:PivotTo(Value and CFrame.new(-10000, -10000, -10000) or Object:GetAttribute("OriginalPosition"))
			end
		end
	end)
end

Groupboxes.Floors_Farming = Tabs.Floors:AddLeftGroupbox("Farming")
Groupboxes.Floors_Farming:AddToggle("KnobFarm", {
    Text = "Knob Farm",
    Default = false,
    Tooltip = "Automatically gains knobs for you, dies and revives repeatedly.",
	Risky = Floor ~= "Ballz",
})

Groupboxes.Floors_Farming:AddButton({
    Text = "Start Knob Farm",
    Tooltip = "Starts farming knobs, click this when you have enough gold.",
    Func = function()
		if LatestRoom.Value ~= 0 then
			Functions.Notify({Title = "You must be in Room 0 to use this."})
			return
		end

		if LocalPlayer.PlayerGui:FindFirstChild("TopbarUI") then 
			local GoldCount = LocalPlayer.PlayerGui.TopbarUI.Topbar.StatsTopbarHandler.StatModules.Gold.GoldVal
			if GoldCount.Value <= 0 then
				Functions.Notify({Title = "You must have gold to do this."})
				return
			end
		end

        Globals.KnobFarmStarted = true
    end
})

Groupboxes.Floors_Farming:AddDivider()
Groupboxes.Floors_Farming:AddButton({
	Text = "Start Death Farm",
	DoubleClick = true,
	Tooltip = "Automatically farms deaths, joining new runs.",
	Func = function()
		loadstring(game:HttpGet(Boot.MirrorRoot .. "bocaj/Scripts/DeathFarm.luau"))()
	end,

	Disabled = not Functions.CheckCompatability({"fireproximityprompt", "firesignal"}),
	DisabledTooltip = Globals.ImcompatibleMessage
})
Groupboxes.Floors_Farming:AddButton({
	Text = "Copy Death Farm Loadstring",
	DoubleClick = false,
	Tooltip = "Copies the death farm loadstring to your clipboard.",
	Func = function()
		toclipboard([==[
			loadstring(game:HttpGet(Boot.MirrorRoot .. "bocaj/Scripts/DeathFarm.luau"))()
		]==])
		Library:Notify("Loadstring has been copied to your clipboard.")
	end,

	Disabled = not Functions.CheckCompatability({"fireproximityprompt", "firesignal"}),
	DisabledTooltip = Globals.ImcompatibleMessage
})

Toggles.KnobFarm:OnChanged(function(Value)
    if Value then
        Functions.Notify({Title = "Please collect some gold to earn knobs.", Body = "Click 'Start Knob Farm' when you're ready."})
	else
		Globals.KnobFarmStarted = false
    end
end)

Globals.KnobFarmActive = false
Globals.KnobFarmStarted = false
Connections.KnobFarm = Services.RunService.Heartbeat:Connect(function()
	if Toggles.KnobFarm.Value and Globals.KnobFarmStarted then
		if not Globals.KnobFarmActive then
			Globals.KnobFarmActive = true
			if Functions.CheckCompatability({"replicatesignal"}) then
				Abysall.Environment.replicatesignal(LocalPlayer.Kill)
			else
				LocalPlayer.Character.Humanoid.Health = 0
			end
			while task.wait() do
				if LocalPlayer:GetAttribute("Alive") then
					break
				end
			end
			RemotesFolder.Statistics:FireServer()
			task.wait(0.25)
			Globals.KnobFarmActive = false
		end
	end
end)

local MainHook
local OtherHook
if Functions.CheckCompatability({"hookmetamethod", "newcclosure", "getnamecallmethod"}) then
	MainHook = Abysall.Environment.hookmetamethod(game, "__namecall", Abysall.Environment.newcclosure(function(Self, ...)
		local Args = { ... }
		if Abysall and Abysall.Environment then
			local Method = Abysall.Environment.getnamecallmethod()

			if Self.Name == "Crouch" and Method == "FireServer" then
				if Toggles.CrouchSpoof.Value or Toggles.PositionSpoof.Value then
					Args[1] = true
				end
				Args[2] = true
			end

			if Self.Name == "ClutchHeartbeat" and Method == "FireServer" and Toggles.AutoHeartbeatMinigame.Value or Self.Name == "HideMonster" and Method == "FireServer" and Toggles.AutoHeartbeatMinigame.Value then
				return
			end

			if Self.Name == "MotorReplication" and Method == "FireServer" then
				local DoBypass = (Toggles.BypassEyes.Value and Globals.IsEyes) or (Toggles.BypassLookman.Value and Globals.IsLookman)
				local DoMonument = Toggles.ImportedBypassMonument and Toggles.ImportedBypassMonument.Value
				if DoMonument and RootPart then
					local Target, BestDistance
					for _, Entity in Objects.Entities do
						if Entity and Entity:IsA("Model") and Entity.PrimaryPart and (Entity.Name == "MonumentEntity" or Entity.Name == "Monument") then
							local Distance = (Entity.PrimaryPart.Position - RootPart.Position).Magnitude
							if not BestDistance or Distance < BestDistance then Target, BestDistance = Entity.PrimaryPart, Distance end
						end
					end
					local CameraNow = workspace.CurrentCamera
					if Target and CameraNow then
						local Delta = Target.Position - CameraNow.CFrame.Position
						local TargetYaw = math.deg(math.atan2(-Delta.X, -Delta.Z))
						local Look = CameraNow.CFrame.LookVector
						local CameraYaw = math.deg(math.atan2(-Look.X, -Look.Z))
						local Index = #Args >= 4 and type(Args[4]) == "boolean" and 2 or 1
						local Existing = tonumber(Args[Index])
						local Difference = (TargetYaw - CameraYaw + 180) % 360 - 180
						Args[Index] = Existing and Existing + Difference or TargetYaw
					end
				elseif DoBypass then
					if Floor == "Fools" or Floor == "OldHotel" then
						Args[1] = 0 Args[2] = (Globals.SpoofOffset == 200 and 65 or -65) Args[3] = 0 Args[4] = false
					else
						Args[1] = -650
					end
				end
			end
		end
		return MainHook(Self, table.unpack(Args))
	end))

    OtherHook = Abysall.Environment.hookmetamethod(game, "__index", Abysall.Environment.newcclosure(function(Self, Property)
        local Real = OtherHook(Self, Property)

        if Property == "MoveDirection" and Self == Humanoid and Globals.RoomsAutoWalkActive and Toggles.RoomsAutoWalkSpoofFootsteps.Value and Floor == "Rooms" and not Character:GetAttribute("Hiding") then
            return RootPart.CFrame.LookVector
        end
        
        return Real
    end))
end

if Services.ReplicatedStorage:FindFirstChild("ModulesClient") then
	ClientModules = Services.ReplicatedStorage.ModulesClient
else
	ClientModules = Services.ReplicatedStorage.ClientModules
end

Modules = {
	Glitch         = ClientModules.EntityModules.Glitch,
	Shade          = ClientModules.EntityModules.Shade,
	Void           = ClientModules.EntityModules:FindFirstChild("Void"),
	SpiderJumpscare = nil,
	A90            = nil,
	Screech        = nil,
	Dread          = nil,
	GlitchScreech  = nil,
}

local CharacterOldConnectionKeys = {
	"MainHandler", "JumpHandler", "SlideHandler", "LibraryCodeHandler1", "LibraryCodeHandler2",
	"OxygenConnection", "AnimationHandler", "AutoHideConnection", "AutoReviveHandler",
	"SHMFixer", "AnticheatDisabler", "AnticheatObjectDisabler", "AnticheatHeavyToolWatcher", "AnticheatEnableDetector1", "AnticheatEnableDetector2",
	"AutoSteerMinecartDuckHandler", "AutoSolveAnchorsConnection", "InfiniteJumpsConnection1", "InfiniteJumpsConnection2",
	"FootstepHandler"
}

Globals.IsTyping = false
Connections.TextBoxConnection1 = Services.UserInputService.TextBoxFocused:Connect(function()
	Globals.IsTyping = true
end)
Connections.TextBoxConnection2 = Services.UserInputService.TextBoxFocusReleased:Connect(function()
	Globals.IsTyping = false
end)

Functions.HandleCharacter = function(NewCharacter)
	for _, Key in CharacterOldConnectionKeys do
		if Connections[Key] then
			Connections[Key]:Disconnect()
			Connections[Key] = nil
		end
	end

	while not LocalPlayer.PlayerGui:FindFirstChild("MainUI") do
		task.wait()
	end

	Character = NewCharacter
	Humanoid = NewCharacter:WaitForChild("Humanoid", 9e9)
	RootPart = NewCharacter:FindFirstChild("HumanoidRootPart")
	Camera   = Services.Workspace.CurrentCamera

	Globals.OldCamera = Camera
	Globals.MainUI = LocalPlayer.PlayerGui.MainUI

	Collision = NewCharacter:WaitForChild("Collision")
	CollisionPart  = NewCharacter:FindFirstChild("CollisionPart") or NewCharacter:FindFirstChild("Collision")
	CollisionClone = Collision:Clone()
	CollisionClone.Parent = NewCharacter
	CollisionClone.Name = "CollisionClone"
	CollisionClone.Massless = true

	CollisionPartClone = CollisionPart:Clone()
	CollisionPartClone.Parent = NewCharacter
	CollisionPartClone.Name = "CollisionPartClone"
	CollisionPartClone.CanCollide = false
	CollisionPartClone.Massless = true

	if CollisionPartClone:FindFirstChild("CollisionCrouch") then
		CollisionPartClone.CollisionCrouch:Destroy()
	end

	Character:SetAttribute("SpeedBoost", 0)
	Character:SetAttribute("SpeedBoostBehind", 0)
	Character:SetAttribute("SpeedBoostExtra", 0)

	OldJump  = NewCharacter:GetAttribute("CanJump")
	OldSlide = NewCharacter:GetAttribute("CanSlide")

	if Toggles.EnableCharacterJump.Value  then Character:SetAttribute("CanJump",  true) end
	if Toggles.EnableCharacterSlide.Value then Character:SetAttribute("CanSlide", true) end

	if Functions.CheckCompatability({"require"}) then
		Main_Game = Abysall.Environment.require(Globals.MainUI.Initiator.Main_Game)
	end

	if Main_Game and Toggles.RemoveCameraBobbing.Value then
		Main_Game.spring.Speed = 9e9
	end

	if Main_Game and Functions.CheckCompatability({"require"}) then
		local Controls = require(LocalPlayer.PlayerScripts.PlayerModule):GetControls()
		local OriginalGetMoveVector = Globals.OriginalGetMoveVector or Controls.GetMoveVector
		Globals.OriginalGetMoveVector = OriginalGetMoveVector
		Controls.GetMoveVector = function(...)
			if Toggles.AutoSteerMinecart.Value and Floor == "Mines" then
				local Node = Globals.NearestTurnNode
				if Node and Functions.GetMinecart() then
					local Turn = Node:GetAttribute("Turn")
					if Turn ~= "Left" and Turn ~= "Right" then return Vector3.zero end

					-- cart heading from actual movement (flat), not from where the camera looks
					local Root = Character and Character:FindFirstChild("HumanoidRootPart")
					if Root then
						local Position = Root.Position
						local Last = Globals.CartLastPos
						if not Last then
							Globals.CartLastPos = Position
						else
							local Delta = Vector3.new(Position.X - Last.X, 0, Position.Z - Last.Z)
							if Delta.Magnitude > 0.5 then
								Globals.CartForward = Delta.Unit
								Globals.CartLastPos = Position
							end
						end
					end

					local Forward = Globals.CartForward
					local CurrentCamera = workspace.CurrentCamera
					if Forward and CurrentCamera then
						local CartRight = Forward:Cross(Vector3.yAxis)
						local World = Turn == "Right" and CartRight or -CartRight

						-- GetMoveVector is camera-relative: convert the world direction into camera space
						local Look = CurrentCamera.CFrame.LookVector
						local FlatLook = Vector3.new(Look.X, 0, Look.Z)
						if FlatLook.Magnitude > 0.001 then
							FlatLook = FlatLook.Unit
							local CameraRight = FlatLook:Cross(Vector3.yAxis)
							return Vector3.new(World:Dot(CameraRight), 0, -World:Dot(FlatLook))
						end
					end
					-- heading unknown yet (cart hasn't moved): old camera-relative behaviour
					return Turn == "Left" and Vector3.new(-1, 0, 0) or Vector3.new(1, 0, 0)
				end
			end
			if not Functions.GetMinecart() then Globals.CartLastPos = nil Globals.CartForward = nil end
			local Move = OriginalGetMoveVector(...)
			local Transform = Globals.AMRChallengeMoveVector
			if Transform then
				local Ok, Result = pcall(Transform, Move)
				if Ok and typeof(Result) == "Vector3" then Move = Result end
			end
			return Move
		end
	end

	Globals.AutoMinecartDucked = false
	Globals.LastDuck = tick()
	Connections.AutoSteerMinecartDuckHandler = Services.RunService.Heartbeat:Connect(function()
		if not Toggles.AutoSteerMinecart.Value or not Functions.GetMinecart() or tick() - Globals.LastDuck < 0.1 then return end
		Globals.NearestTurnNode = Functions.GetNearestTurnNode()

		if not Globals.AutoMinecartDucked and Functions.GetNearestDuckBoard() then
			Main_Game.crouch(true)
			Globals.AutoMinecartDucked = true
		elseif not Functions.GetNearestDuckBoard() and Globals.AutoMinecartDucked then
			Main_Game.crouch(false)
			Globals.AutoMinecartDucked = false
		end
		if Main_Game then
			Main_Game.fovtarget = Options.FieldOfView.Value
		else
			Camera.FieldOfView = Options.FieldOfView.Value
		end
		Globals.LastDuck = tick()
	end)

	Globals.AnticheatDisabled = false
	Globals.AnticheatObjectPending = false

	local UIModules = Globals.MainUI.Initiator.Main_Game.RemoteListener.Modules
	Modules.A90             = UIModules:FindFirstChild("A90")
	Modules.Screech         = UIModules.Screech
	Modules.Dread           = UIModules:FindFirstChild("Dread")
	Modules.SpiderJumpscare = UIModules.SpiderJumpscare

	if Toggles.RemoveScreech.Value    then Modules.Screech.Name = "Screech_Disabled" print ("screech gone") end
	if Toggles.RemoveA90.Value and Modules.A90   then Modules.A90.Name = "A90_Disabled" end
	if Toggles.RemoveDread.Value and Modules.Dread then Modules.Dread.Name = "Dread_Disabled" end
	if Toggles.DisableTimothyJumpscare.Value then Modules.SpiderJumpscare.Name = "SpiderJumpscare_Disabled" end

	if Toggles.DisableHideVignette.Value then
		local Vignette = Globals.MainUI:FindFirstChild("HideVignette") or Globals.MainUI.MainFrame:FindFirstChild("HideVignette")
		if Vignette then Vignette.Image = "Disabled" end
	end
	if Toggles.RemoveInteractingSounds.Value then
		local Game = Globals.MainUI.Initiator.Main_Game
		local PS = Game:FindFirstChild("PromptService")
		if PS then
			for _, Name in { "Triggered", "Holding", "Notification" } do
				local Sound = PS:FindFirstChild(Name)
				if Sound then Sound.Volume = 0 end
			end
		end
		local Caption = Game:FindFirstChild("Reminder") and Game.Reminder:FindFirstChild("Caption")
		if Caption then Caption.Volume = 0 end
	end
	if Toggles.DisableEntityJumpscares.Value then
		local JS = Globals.MainUI.Initiator.Main_Game.RemoteListener:FindFirstChild("Jumpscares")
		if JS then JS.Name = "Jumpscares_Disabled" end
	end
    local Cutscenes = Globals.MainUI.Initiator.Main_Game.RemoteListener.Cutscenes
    for _, Object in pairs(Cutscenes:GetChildren()) do
        if table.find(CutsceneNames, Object.Name) and Object:IsA("ModuleScript") then
            Object:SetAttribute("OriginalName", Object.Name)
            if Toggles.RemoveCutscenes.Value then
                Object.Name = Object.Name .. "_Disabled"
            end
        end
    end
    for _, Object in pairs(FloorReplicated:GetChildren()) do
        if table.find(CutsceneNames, Object.Name) and Object:IsA("ModuleScript") then
            Object:SetAttribute("OriginalName", Object.Name)
            if Toggles.RemoveCutscenes.Value then
                Object.Name = Object.Name .. "_Disabled"
            end
        end
    end

	CustomPhysics = PhysicalProperties.new(
		100,
		RootPart.CustomPhysicalProperties.Friction,
		RootPart.CustomPhysicalProperties.Elasticity,
		RootPart.CustomPhysicalProperties.FrictionWeight,
		RootPart.CustomPhysicalProperties.ElasticityWeight
	)
	for _, Part in NewCharacter:GetDescendants() do
		if Part:IsA("BasePart") then
			PartProperties[Part] = Part.CustomPhysicalProperties
			if Toggles.RemoveAcceleration.Value then
				Part.CustomPhysicalProperties = CustomPhysics
			end
		end
	end

	Connections.LibraryCodeHandler1 = LocalPlayer.PlayerGui.PermUI.Hints.ChildAdded:Connect(function()
		if Toggles.NotifyLibraryCode.Value then
			local Code = Functions.GetLibraryCode()
			if Code and not Code:find("_") and not Globals.LibraryCodeFound then
				local Lock = Services.Workspace:FindFirstChild("Padlock", true)
				Functions.Notify({ Title = "Padlock code found!", Body = "The code is: '" .. Code .. "'", Time = Toggles.NotifyKeepNotifications.Value and Lock or 15 })
				Globals.LibraryCodeFound = true
			end
		end
	end)

	Connections.LibraryCodeHandler2 = Character.ChildAdded:Connect(function(Child)
		if (Child.Name == "LibraryHintPaper" or Child.Name == "LibraryHintPaperHard") and Toggles.NotifyLibraryCode.Value then
			local Code = Functions.GetLibraryCode()
			if Code and not Code:find("_") and not Globals.LibraryCodeFound then
				local Lock = Services.Workspace:FindFirstChild("Padlock", true)
				Functions.Notify({ Title = "Padlock code found!", Body = "The code is: '" .. Code .. "'", Time = Toggles.NotifyKeepNotifications.Value and Lock or 15 })
				Globals.LibraryCodeFound = true
			end
		end
	end)

	Connections.FootstepHandler = Character.ChildAdded:Connect(function(Object)
		if Object:IsA("Sound") and Object.Name == "Sound" and Toggles.RemoveFootstepSounds.Value then
			Object.Volume = 0
		end
	end)

	Globals.OldOxygen = Character:GetAttribute("Oxygen")
	Connections.OxygenConnection = Character:GetAttributeChangedSignal("Oxygen"):Connect(function()
		local NewOxy = Character:GetAttribute("Oxygen")
		if NewOxy < Globals.OldOxygen and Toggles.NotifyOxygen.Value then
			Functions.Caption(Functions.FormatOxygen(NewOxy), true)
		end
		Globals.OldOxygen = NewOxy
	end)

	Connections.AutoReviveHandler = LocalPlayer:GetAttributeChangedSignal("Alive"):Connect(function()
		if LocalPlayer:GetAttribute("Alive") == false and Toggles.AutoRevive.Value then
			if Floor == "Fools" or Floor == "OldHotel" then
				while LocalPlayer:GetAttribute("Alive") ~= true do
					RemotesFolder.Revive:FireServer()
					task.wait(0.5)
				end
			end
		end
	end)

	Connections.SHMFixer = RootPart:GetPropertyChangedSignal("Anchored"):Connect(function()
		task.wait()
		if Floor == "Fools" and RootPart.Anchored and Character:GetAttribute("Hiding") ~= true then
			RootPart.Anchored = false
		end
	end)

	Connections.AnticheatDisabler = Character:GetAttributeChangedSignal("Climbing"):Connect(function()
		if Character:GetAttribute("Climbing") == true and Toggles.DisableAnticheat.Value and not Globals.AnticheatDisabled then
			task.wait(0.25)
			Character:SetAttribute("Climbing", false)
			Functions.Notify({ Title = "Successfully disabled the anticheat.", Body = "It will be re-enabled after a cutscene or halt room." })
			Globals.AnticheatDisabled = true
		end
	end)

	do
		local function AncestorNamed(Object, Name)
			local Node = Object
			while Node and Node ~= workspace do
				if Node.Name == Name then return Node end
				Node = Node.Parent
			end
			return nil
		end
		local function OwningRoom(Object)
			local Rooms = workspace:FindFirstChild("CurrentRooms")
			local Node = Object
			while Node and Node.Parent do
				if Node.Parent == Rooms then return tonumber(Node.Name) end
				Node = Node.Parent
			end
			return tonumber(Object:GetAttribute("ParentRoom"))
		end
		local RecentForcedTools = setmetatable({}, { __mode = "k" })
		Connections.AnticheatHeavyToolWatcher = Character.ChildAdded:Connect(function(Child)
			if not Child:IsA("Tool") then return end
			task.spawn(function()
				local Deadline = tick() + 3
				repeat
					if Child:GetAttribute("DontUnequip") then RecentForcedTools[Child] = tick() return end
					task.wait(0.05)
				until tick() >= Deadline or not Child.Parent
			end)
		end)

		local function BeginRelease(SourceName)
			if Globals.AnticheatObjectPending then return false end
			Globals.AnticheatObjectPending = true
			local SourceCharacter = Character
			local SourceHumanoid = Humanoid
			local Started = tick()
			task.spawn(function()
				local Deadline = tick() + 3
				local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
				local Released = false
				repeat
					task.wait(0.05)
					if Backpack then
						for Tool, AddedAt in RecentForcedTools do
							if AddedAt >= Started - 0.75 and Tool.Parent then
								if Tool.Parent == SourceCharacter then
									pcall(function() SourceHumanoid:UnequipTools() end)
									if Tool.Parent == SourceCharacter then Tool.Parent = Backpack end
								end
								if Tool.Parent == Backpack then Released = true end
							end
						end
					end
				until tick() >= Deadline or not SourceCharacter.Parent or (Released and tick() - Started >= 0.25)
				Globals.AnticheatObjectPending = false
				if Released and SourceCharacter == LocalPlayer.Character and SourceCharacter.Parent and Toggles.DisableAnticheat.Value then
					Globals.AnticheatDisabled = true
					Functions.Notify({
						Title = "Successfully disabled the anticheat.",
						Body = "Source: " .. SourceName .. ". It will reset after a cutscene or halt room."
					})
				elseif SourceCharacter == LocalPlayer.Character and Toggles.DisableAnticheat.Value then
					local Seen = {}
					for _, Child in SourceCharacter:GetChildren() do
						if Child:IsA("Tool") then
							local Parts = {}
							for Key, Value in Child:GetAttributes() do Parts[#Parts + 1] = Key .. "=" .. tostring(Value) end
							Seen[#Seen + 1] = Child.Name .. "{" .. table.concat(Parts, ",") .. "}"
						end
					end
					warn("[AMR] chair/cart bypass not confirmed. Tools on character: " .. (#Seen > 0 and table.concat(Seen, " ") or "none"))
					Functions.Notify({ Title = "Anticheat bypass not confirmed", Body = "No DontUnequip tool appeared (see console)." })
				end
			end)
			return true
		end

		Connections.AnticheatObjectDisabler = Services.ProximityPromptService.PromptTriggered:Connect(function(Prompt)
			if Globals.FPVChairActive or not Toggles.DisableAnticheat.Value or Globals.AnticheatDisabled or Globals.AnticheatObjectPending then return end
			local Chair = AncestorNamed(Prompt, "ArchivesOfficeChair")
			local Cart = AncestorNamed(Prompt, "ShoppingCart")
			if not Chair and not Cart then return end
			if Chair and Prompt.Name ~= "CartPrompt" then return end
			if Cart and Prompt.Name ~= "CartPrompt" and Prompt.Name ~= "PushPrompt" and Prompt.Name ~= "LongPushPrompt" and Prompt.Name ~= "BigPropPrompt" then return end

			local LiveFloor = GameData:FindFirstChild("Floor")
			local FloorName = tostring(LiveFloor and LiveFloor.Value or Floor)
			if Chair and FloorName ~= "Archives" then return end
			if Cart and not string.find(string.lower(FloorName), "stair", 1, true) then return end
			local Owner = OwningRoom(Chair or Cart)
			local Current = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
			if Owner and Current and Owner ~= Current then return end
			BeginRelease(Chair and "Archives office chair" or "Stairwell shopping cart")
		end)

		-- auto mode: walk behind the nearest chair, grab it, stow the held tool
		local function PromptPosition(Prompt)
			local Parent = Prompt.Parent
			if Parent and Parent:IsA("Attachment") then return Parent.WorldPosition end
			if Parent and Parent:IsA("BasePart") then return Parent.Position end
			local Model = Parent and Parent:FindFirstAncestorOfClass("Model")
			return Model and Model:GetPivot().Position
		end
		local LastAutoAttempt, AutoAttempts = 0, 0
		task.spawn(function()
			while not Library.Unloaded do
				task.wait(1)
				if Library.Unloaded then break end
				pcall(function()
					if not (Toggles.AutoChairBypass and Toggles.AutoChairBypass.Value) or not Toggles.DisableAnticheat.Value then return end
					if Globals.AnticheatDisabled then AutoAttempts = 0 return end
					if Globals.AnticheatObjectPending or tick() - LastAutoAttempt < 6 then return end
					local LiveFloor = GameData:FindFirstChild("Floor")
					if tostring(LiveFloor and LiveFloor.Value or Floor) ~= "Archives" then return end
					if not Character or not Humanoid or Humanoid.Health <= 0 or not RootPart then return end
					if Character:GetAttribute("Hiding") or LocalPlayer:GetAttribute("Alive") == false then return end

					local Rooms = workspace:FindFirstChild("CurrentRooms")
					local Current = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
					local Scope = Rooms and ((Current and Rooms:FindFirstChild(tostring(Current))) or Rooms)
					if not Scope then return end
					local List = {}
					for _, Object in Scope:GetDescendants() do
						if Object:IsA("ProximityPrompt") and Object.Name == "CartPrompt" and not Object:GetAttribute("FakePrompt") then
							local Chair = AncestorNamed(Object, "ArchivesOfficeChair")
							local Position = Chair and PromptPosition(Object)
							if Position then
								local Distance = (Position - RootPart.Position).Magnitude
								if Distance <= 150 then List[#List + 1] = { Prompt = Object, Chair = Chair, Position = Position, Distance = Distance, Push = Object:GetAttribute("GateSector") == "Push" } end
							end
						end
					end
					if #List == 0 then return end
					table.sort(List, function(A, B)
						if A.Push ~= B.Push then return A.Push end
						return A.Distance < B.Distance
					end)

					LastAutoAttempt = tick()
					AutoAttempts += 1
					if AutoAttempts > 4 then
						AutoAttempts = 0
						Toggles.AutoChairBypass:SetValue(false)
						Functions.Notify({ Title = "Auto Chair Bypass", Body = "Gave up after 4 tries. Grab a chair by hand once and send me the console line." })
						return
					end
					local Pick = List[((AutoAttempts - 1) % #List) + 1]
					local ChairCenter = Pick.Chair:GetPivot().Position
					local Out = Vector3.new(Pick.Position.X - ChairCenter.X, 0, Pick.Position.Z - ChairCenter.Z)
					Out = Out.Magnitude > 0.1 and Out.Unit or Vector3.zero
					local Goal = Vector3.new(Pick.Position.X, RootPart.Position.Y, Pick.Position.Z) + Out * 2.5
					if (RootPart.Position - Pick.Position).Magnitude > 9 then
						local Began = tick()
						repeat
							Humanoid:MoveTo(Goal)
							task.wait(0.1)
						until tick() - Began > 6 or Library.Unloaded or Humanoid.Health <= 0 or (RootPart.Position - Pick.Position).Magnitude <= 7
					end
					if Library.Unloaded or not Pick.Prompt:IsDescendantOf(workspace) then return end
					if BeginRelease("Archives office chair (auto)") then
						Functions.FirePrompt(Pick.Prompt)
					end
				end)
			end
		end)
	end

	Connections.AnticheatEnableDetector1 = RemotesFolder:WaitForChild("Cutscene").OnClientEvent:Connect(function(CutsceneName)
		if Globals.AnticheatDisabled and not CutsceneName:find("SewerSeek") then
			Globals.AnticheatDisabled = false
			Functions.Notify({ Title = "The anticheat has been re-enabled.", Body = "Use a ladder, Stairwell cart, or Archives office chair to disable it again." })
		end
	end)

	Connections.AnticheatEnableDetector2 = RemotesFolder:WaitForChild("UseEnemyModule").OnClientEvent:Connect(function(ModuleName)
		if ModuleName == "Void" or ModuleName == "Glitch" then
			if Globals.AnticheatDisabled then
				Globals.AnticheatDisabled = false
				Functions.Notify({ Title = "The anticheat has been re-enabled.", Body = "Use a ladder, Stairwell cart, or Archives office chair to disable it again." })
			end
			LocalPlayer:SetAttribute("CurrentRoom", LatestRoom.Value)
		end
	end)

	Connections.AnimationHandler = Character.ChildAdded:Connect(function()
		local ToolNames = { "Lockpick","Shears","SkeletonKey","Key","GeneratorFuse","KeyElectrical","KeyBackdoor","KeyIron", "Multitool" }
		local Tool
		for _, Name in ToolNames do
			Tool = Character:FindFirstChild(Name)
			if Tool then break end
		end
		if not Tool then return end

		local UseAnim = Tool:FindFirstChild("use", true) or Tool:FindFirstChild("promptanim", true)
		if UseAnim then
			UseAnim = Humanoid:LoadAnimation(UseAnim)
			UseAnim.Priority = Enum.AnimationPriority.Action4
			Globals.UseAnimation = UseAnim
		end
		local UseAnimBreak = Tool:FindFirstChild("usefinish", true) or Tool:FindFirstChild("promptanimend", true) or Tool:FindFirstChild("lockpickuse", true)
		if UseAnimBreak then
			UseAnimBreak = Humanoid:LoadAnimation(UseAnimBreak)
			UseAnimBreak.Priority = Enum.AnimationPriority.Action4
			Globals.UseAnimationBreak = UseAnimBreak
		end
	end)

	Connections.JumpHandler = Character:GetAttributeChangedSignal("CanJump"):Connect(function()
		local Val = Character:GetAttribute("CanJump")
		local Mine = Globals.JumpSelfWrite
		if Mine and Mine.Value == Val and tick() - Mine.Time < 0.5 then return end
		if Globals.JumpLock then
			-- the game wrote while our lock holds: remember its value for the unlock, keep the lock
			OldJump = Val
			if Globals.WriteJump then Globals.WriteJump(false) else Character:SetAttribute("CanJump", false) end
			return
		end
		if Toggles.EnableCharacterJump.Value and Val ~= true or not Toggles.EnableCharacterJump.Value then
			OldJump = Val
		end
		if Toggles.EnableCharacterJump.Value then Character:SetAttribute("CanJump", true) end
	end)

	Connections.SlideHandler = Character:GetAttributeChangedSignal("CanSlide"):Connect(function()
		local Val = Character:GetAttribute("CanSlide")
		if Toggles.EnableCharacterSlide.Value and Val ~= true or not Toggles.EnableCharacterSlide.Value then
			OldSlide = Val
		end
		if Toggles.EnableCharacterSlide.Value then Character:SetAttribute("CanSlide", true) end
	end)

	Connections.InfiniteJumpsConnection1 = Services.UserInputService.InputBegan:Connect(function(Input)
		if Input.KeyCode == Enum.KeyCode.Space and Toggles.InfiniteJumps.Value and not Globals.IsTyping and not Globals.JumpLock then
			Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)

	local JumpButton = Globals.MainUI.MainFrame.MobileButtons:FindFirstChild("JumpButton")
	if JumpButton then
		Connections.InfiniteJumpsConnection2 = JumpButton.MouseButton1Down:Connect(function()
			if Toggles.InfiniteJumps.Value and not Globals.JumpLock and tick() - (Globals.LastPromptTime or 0) > 0.5 then
				Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)
	end

	Globals.SpoofOffset = 0
	Globals.LastAutoHide = tick()
	Connections.AutoHideConnection = Services.RunService.Heartbeat:Connect(function()
		if not Toggles.AutoClosetToggle.Value or tick() - Globals.LastAutoHide <= 0.1 then
			Globals.AutoClosetActive = false
			return
		end
		local Entity = Functions.GetNearestEntity(true, Options.AutoClosetEntityList.Value)
		local EntityNearby = Entity and LocalPlayer:DistanceFromCharacter(Entity.PrimaryPart.Position) <= (EntityDistances[Entity.Name] or 150)
		if Character:GetAttribute("Hiding") == true then
			Globals.AutoClosetActive = false
			Globals.SpectateEntity = nil
			if not EntityNearby then
				RemotesFolder.CamLock:FireServer()
			end
			Globals.LastAutoHide = tick()
			return
		end
		if not Entity then
			Globals.SpectateEntity = nil
			Globals.AutoClosetActive = false
			Globals.LastAutoHide = tick()
			return
		end
		if not EntityNearby then
			Globals.SpectateEntity = nil
			Globals.AutoClosetActive = false
			Globals.LastAutoHide = tick()
			return
		end
		local Closet = Functions.GetNearestHidingSpot()
		if Character:GetAttribute("Hiding") ~= true and Closet then
			local Prompt = Closet:FindFirstChild("HidePrompt")
				or Closet:FindFirstChild("HidingPrompt")
				or Closet:FindFirstChild("HidePrompt", true)
				or Closet:FindFirstChild("HidingPrompt", true)

			if not Prompt then
				for _, Child in Closet:GetDescendants() do
					if (Child:IsA("ProximityPrompt") or Child:IsA("InteractPrompt"))
						and (Child.Name == "HidePrompt" or Child.Name == "HidingPrompt")
					then
						Prompt = Child
						break
					end
				end
			end

			if Prompt then
				Globals.AutoClosetActive = true
				Functions.ForceFirePrompt(Prompt)
			end
		end
		if Character:GetAttribute("Hiding") then
			if Toggles.SpectateEntityToggle.Value and Entity.PrimaryPart then
				Globals.SpectateEntity = Entity
			end
		end
		Globals.LastAutoHide = tick()
	end)

	Globals.LastAutoAnchor = tick()
	Connections.AutoSolveAnchorsConnection = Services.RunService.Heartbeat:Connect(function()
		if not Toggles.AutoSolveAnchors.Value then return end
		if not Globals.MainUI:FindFirstChild("AnchorHintFrame") then return end
		if tick() - Globals.LastAutoAnchor <= 0.1 then return end
		local Anchor = Functions.GetCurrentAnchor()
		if Anchor and LocalPlayer:DistanceFromCharacter(Anchor.PrimaryPart.Position) < Anchor.ActivateEventPrompt.MaxActivationDistance and not Anchor:GetAttribute("Activated") then
			Anchor:WaitForChild("AnchorRemote"):InvokeServer(Globals.MainUI.AnchorHintFrame.Code.Text)
		end
		Globals.LastAutoAnchor = tick()
	end)

	Globals.ManipulateBody = Instance.new("BodyVelocity")
	Globals.ManipulateBody.MaxForce = Vector3.new(9e9, 9e9, 9e9)

	Globals.FlyBody = Instance.new("BodyVelocity")
	Globals.FlyBody.MaxForce = Vector3.new(9e9, 9e9, 9e9)

	Globals.SelfKilled = false
	Globals.ThirdPersonParts = {}
	for _, Object in Character:GetDescendants() do
		if Object:IsA("Accessory") and Object:FindFirstChild("Handle") then
			table.insert(Globals.ThirdPersonParts, Object.Handle)
		end
	end
	table.insert(Globals.ThirdPersonParts, Character:WaitForChild("Head"))

	Globals.LastAnimationCheck = tick()
	Globals.LastCrouchFire = tick()
	Globals.OriginalC1 = Character.LowerTorso.Root.C1

	local RayParams = RaycastParams.new()
	RayParams.FilterType = Enum.RaycastFilterType.Exclude

	local MainFrame = Globals.MainUI:FindFirstChild("MainFrame")
	if MainFrame and MainFrame:FindFirstChild("SurgeVignette") then
		Globals.SurgeFrame = MainFrame.SurgeVignette
		if Toggles.RemoveSurge.Value then
			Globals.SurgeFrame.Name = "SurgeVignette_Disabled"
		end
	end

	Connections.MainHandler = Services.RunService.RenderStepped:Connect(function()
		if Services.Workspace:FindFirstChild("Camera") then
			Camera = Services.Workspace:FindFirstChild("Camera")
		end

		if Toggles.SpeedBoostToggle.Value then
			Humanoid.WalkSpeed = Functions.GetCurrentSpeed() + Options.SpeedBoostSlider.Value
		end

		if Globals.Lagging or (Options.SpeedBoostSlider.Value <= 6 and Options.FlySpeed.Value <= 21) then
			CollisionPartClone.Massless = true
		end

		Globals.IsEyes    = Services.Workspace:FindFirstChild("Eyes") ~= nil or Services.Workspace:FindFirstChild("Lookman") ~= nil
		Globals.IsLookman = Services.Workspace:FindFirstChild("BackdoorLookman") ~= nil

		if Toggles.AmbientToggle.Value then
			Services.TweenService:Create(Services.Lighting, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), { Ambient = Options.AmbientColor.Value }):Play()
		end

		if Main_Game then
			if Toggles.RemoveCameraShake.Value     then Main_Game.csgo = CFrame.new() end
			if Toggles.ViewmodelOffsetToggle.Value then
				Main_Game.tooloffset = Vector3.new(Options.ViewmodelOffsetX.Value, Options.ViewmodelOffsetY.Value, Options.ViewmodelOffsetZ.Value)
			else
				Main_Game.tooloffset = Vector3.zero
			end
		end

		if Globals.SelfKilled and Globals.MainUI:FindFirstChild("Statistics") then
			Globals.MainUI.Statistics.Death.Text = "Died to Abyssal Massive Recode"
		end

		if Globals.Deathing and Globals.MainUI:FindFirstChild("Statistics") then
			Globals.MainUI.Statistics.Death.Text = "Died to Verity"
		end

		local MainFrame = Globals.MainUI:FindFirstChild("MainFrame")
		if MainFrame then
			local Effects = MainFrame.Healthbar:FindFirstChild("Effects")
			if Effects and Effects:FindFirstChild("Crouching") then
				Effects.Crouching.Visible = Functions.IsCrouching()
			end
		end

		if (Toggles.CrouchSpoof.Value or Toggles.PositionSpoof.Value) and RemotesFolder:FindFirstChild("Crouch") then
			RemotesFolder.Crouch:FireServer(true, true)
		end

		if Floor ~= "Fools" and Floor ~= "OldHotel" and not Camera:FindFirstChild("MinecartRig") then
			RootPart.CanCollide = false
		end

		for _, Part in Character:GetChildren() do
			if Part:IsA("BasePart") then Part.CanCollide = false end
		end

		if LocalPlayer:GetAttribute("Alive") == true then
			Services.SoundService:WaitForChild("Main").Volume = 1
		end

		if Floor == "OldHotel" or Floor == "Fools" then
			local SpoofOffset = Toggles.PositionSpoof.Value and Functions.GetNearestEntity() and 200 or Toggles.FigureGodmode.Value and Functions.GetNearestFigure() and 200 or 0
			Globals.SpoofOffset = SpoofOffset
			Collision.Position = RootPart.Position + Vector3.new(0, SpoofOffset, 0)
			Collision.CanCollide = false
			if Floor == "Fools" then
				Collision.CollisionCrouch.CanCollide = false
				CollisionClone.CollisionCrouch.CanCollide = false
			end
			RootPart.CanCollide = not (Toggles.NoclipToggle.Value or Toggles.VelocityManipulationToggle.Value)
		else
			Collision.CanCollide = false
			if Collision:FindFirstChild("CollisionCrouch") then Collision.CollisionCrouch.CanCollide = false end

			if CollisionClone:FindFirstChild("CollisionCrouch") then
				local IsCrouch = Functions.IsCrouching()
				CollisionClone.CanCollide = not (Toggles.NoclipToggle.Value or Toggles.VelocityManipulationToggle.Value or IsCrouch)
				CollisionClone.CollisionCrouch.CanCollide = not (Toggles.NoclipToggle.Value or Toggles.VelocityManipulationToggle.Value or not IsCrouch)
			else
				RootPart.CanCollide = not (Toggles.NoclipToggle.Value or Toggles.VelocityManipulationToggle.Value)
			end

			local SpoofY = Toggles.PositionSpoof.Value and 2.328 or 0.18
			Collision.Position     = RootPart.Position + Vector3.new(0, SpoofY, 0)
			CollisionPart.Position = RootPart.Position + Vector3.new(0, SpoofY, 0)

			if Collision:FindFirstChild("CollisionCrouch") and CollisionClone:FindFirstChild("CollisionCrouch") then
				local CrouchY = Toggles.PositionSpoof.Value and 1.328 or -0.982
				Collision.CollisionCrouch.Position = RootPart.Position + Vector3.new(0, CrouchY, 0)
				CollisionClone.CollisionCrouch.CollisionGroup = Collision.CollisionCrouch.CollisionGroup
			end
			if CollisionClone:FindFirstChild("CollisionCrouch") then
				CollisionClone.CollisionCrouch.Position = RootPart.Position + Vector3.new(0, Toggles.PositionSpoof.Value and 0.75 or -0.982, 0)
			end
		end

		CollisionClone.CollisionGroup = Collision.CollisionGroup
		CollisionClone.Position = RootPart.Position + Vector3.new(0, Toggles.PositionSpoof.Value and 1.75 or 0.18, 0)

		if Toggles.VelocityManipulationToggle.Value and Options.VelocityManipulationMode.Value == "Velocity" then
			Globals.ManipulateBody.Parent = RootPart
			Globals.ManipulateBody.Velocity = RootPart.CFrame.LookVector * 2.25
		else
			Globals.ManipulateBody.Parent = nil
		end

		if Toggles.VelocityManipulationToggle.Value and Options.VelocityManipulationMode.Value == "Pivot" and Floor ~= "Fools" and Floor ~= "OldHotel" then
			Character:PivotTo(Camera:GetPivot() * CFrame.new(0, 0, 2560))
		end

		if Toggles.FlyToggle.Value then
			Globals.FlyBody.Parent = RootPart
			Globals.FlyBody.Velocity = Functions.GetFlyVelocity() * Options.FlySpeed.Value
		else
			Globals.FlyBody.Parent = nil
		end

		local DoEyesBypass = (Toggles.BypassEyes.Value and Globals.IsEyes) or (Toggles.BypassLookman.Value and Globals.IsLookman)
		if DoEyesBypass then
			if Floor == "Fools" or Floor == "OldHotel" then
				RemotesFolder.MotorReplication:FireServer(0, (Globals.SpoofOffset == 200 and 65 or -65), 0, false)
			else
				RemotesFolder.MotorReplication:FireServer(-650)
			end
		end

		if RemotesFolder:FindFirstChild("Crouch") and tick() - Globals.LastCrouchFire > 0.1 then
			local IsCrouch = Functions.IsCrouching()
			if Toggles.CrouchSpoof.Value or Toggles.PositionSpoof.Value then IsCrouch = true end
			RemotesFolder.Crouch:FireServer(IsCrouch, true)
			Globals.LastCrouchFire = tick()
		end

		if tick() - Globals.LastAnimationCheck > 0.1 then
			local Sliding = false
			for _, Anim in Humanoid:GetPlayingAnimationTracks() do
				if Anim.Name == "Slide" then Sliding = true break end
			end
			Globals.Sliding = Sliding
			Globals.LastAnimationCheck = tick()
		end

		Character:SetAttribute("Sliding", Globals.Sliding)
		if Character:GetAttribute("Crouching") ~= Functions.IsCrouching() then
			Character:SetAttribute("Crouching", Functions.IsCrouching())
		end

		RayParams.FilterDescendantsInstances = { Character }
		local TPOffset = CFrame.new(Options.ThirdPersonOffsetX.Value, Options.ThirdPersonOffsetY.Value, Options.ThirdPersonOffsetZ.Value)
		local Direction = (Camera.CFrame * TPOffset).Position - Camera.CFrame.Position
		local WallResult = Services.Workspace:Spherecast(Camera.CFrame.Position, 0.2, Direction, RayParams)

		if Toggles.ThirdPersonToggle.Value then
			if Toggles.ThirdPersonWallCheck.Value and WallResult and WallResult.Instance.CanCollide then
				local NewPos = Camera.CFrame.Position + Direction.Unit * WallResult.Distance
				Camera.CFrame = CFrame.new(NewPos, NewPos + Camera.CFrame.LookVector)
			else
				Camera.CFrame = Camera.CFrame * TPOffset
			end
		end

		for _, Part in Globals.ThirdPersonParts do
			Part.Transparency = Toggles.ThirdPersonToggle.Value and 0 or 1
			Part.LocalTransparencyModifier = Toggles.ThirdPersonToggle.Value and 0 or 1
		end

		if Globals.SpectateEntity and Toggles.AutoClosetToggle.Value and Toggles.SpectateEntityToggle.Value then
			local Entity = Globals.SpectateEntity

			local CamPosition
			if Options.SpecateEntityMode.Value == "Player to Entity" then
				CamPosition = CFrame.lookAt(Character.Head.Position, Entity.PrimaryPart.Position)
			else
				CamPosition = CFrame.lookAt(Entity.PrimaryPart.Position, Character.Head.Position)
			end

			Camera.CFrame = CamPosition
		end

		if Toggles.FOVToggle.Value then
			if Main_Game then
				task.wait()
				Main_Game.fovtarget = Options.FieldOfView.Value
			else
				Camera.FieldOfView = Options.FieldOfView.Value
			end
		end

		if Toggles.RemoveClosetDelay.Value
			and Humanoid.MoveDirection ~= Vector3.zero
			and (CollisionPart.Anchored or RootPart.Anchored)
			and Character:GetAttribute("AnimatingClient") ~= true
			and Character:GetAttribute("Hiding") == true
		then
			RemotesFolder.CamLock:FireServer()
		end

		local ClosestPlayer = { Distance = math.huge, Object = nil }
		for _, Player in Services.Players:GetPlayers() do
			if Player.Character and Player ~= LocalPlayer then
				local Root = Player.Character:FindFirstChild("HumanoidRootPart")
				if Root then
					local D = (Camera.CFrame.Position - Root.Position).Magnitude
					if D < ClosestPlayer.Distance then
						ClosestPlayer.Distance = D
						ClosestPlayer.Object = Player
					end
				end
			end
		end
		if ClosestPlayer.Object and LocalPlayer:GetAttribute("Alive") ~= true then
			LocalPlayer:SetAttribute("CurrentRoom", ClosestPlayer.Object:GetAttribute("CurrentRoom"))
		end
	end)

	task.wait(1)
	if Toggles.PositionSpoof.Value and Floor ~= "Fools" and Floor ~= "OldHotel" then
		RootPart.CFrame = RootPart.CFrame * CFrame.new(0, -2.346, 0)
		Humanoid.HipHeight = 0.05
		RemotesFolder.Crouch:FireServer(true, true)
	end

	local Jam = Globals.MainUI.Initiator.Main_Game.Health:FindFirstChild("Jam")
	if Jam and Toggles.RemoveJamminMusic.Value then
		Jam.Volume = 0
		Globals.JamMuffle.Enabled = false
	end
end

Functions.HandleHidingTransparency = function(Model)
	local Parts = {}
	for _, Part in Model:GetDescendants() do
		if Part:IsA("BasePart") then
			Part:SetAttribute("Transparency_Old", Part.Transparency)
			table.insert(Parts, Part)
		end
		if Part.Name == "HiddenPlayer" then
			local HideConn = Part:GetPropertyChangedSignal("Value"):Connect(function()
				for _, P in Parts do
					if P:GetAttribute("Transparency_Old") then
						Services.TweenService:Create(P, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {
							Transparency = (Part.Value == Character and Toggles.TransparentHidingSpotsToggle.Value)
								and Options.TransparentHidingSpotsSlider.Value
								or P:GetAttribute("Transparency_Old")
						}):Play()
					end
				end
			end)
			table.insert(Connections, HideConn)
			Model.Destroying:Once(function()
				HideConn:Disconnect()
				local Pos = table.find(Connections, HideConn)
				if Pos then table.remove(Connections, Pos) end
			end)
		end
	end
end

Functions.HandleObject = function(Object)
	for _, Room in CurrentRooms:GetChildren() do
		if Object:IsDescendantOf(Room) then
			Object:SetAttribute("ParentRoom", tonumber(Room.Name))
			break
		end
		task.wait()
	end

	if Object.Parent == CurrentRooms then
		local FiredampVal = Object:GetAttribute("Firedamp")
		Object:SetAttribute("Firedamp_Old", FiredampVal ~= nil and FiredampVal or false)
		if Toggles.DisableFiredampEffect.Value then
			Object:SetAttribute("Firedamp", false)
		end
	end

	local Name = Object.Name

	if Name == "KeyObtain" then
		task.spawn(function()
			task.wait(0.5)
			if Object.Parent then
				if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Door Key", Color = Options.ObjectiveESPColor.Value }, true) end
				table.insert(Objects.Objectives, Object)
			end
		end)
	elseif Name == "ElectricalKeyObtain" then
		task.spawn(function()
			task.wait(0.5)
			if Object.Parent then
				if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Electrical Key", Color = Options.ObjectiveESPColor.Value }, true) end
				table.insert(Objects.Objectives, Object)
			end
		end)
	elseif Name == "TimerLever" then
		task.spawn(function()
			task.wait(0.5)
			if Object.Parent then
				Object:SetAttribute("AddTime", Object.TakeTimer.TextLabel.Text == "01:00" and 60 or 30)
				if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Time Lever [+" .. Object:GetAttribute("AddTime") .. "s]", Color = Options.ObjectiveESPColor.Value }, true) end
				Object:WaitForChild("Main").SoundToPlay.Played:Once(function()
					Functions.RemoveESP(Object)
					Functions.BlacklistESP(Object)
				end)
				table.insert(Objects.Objectives, Object)
			end
		end)
	elseif Name == "DepotHalloween" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Candy Magic", Color = Options.ObjectiveESPColor.Value }, true) end
		table.insert(Objects.Objectives, Object)
	elseif Name == "StairwellLockpickDoor" then
		if Toggles.MiscESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Garage Door", Color = Options.MiscESPColor.Value }, true) end
		table.insert(Objects.Misc, Object)
	elseif Name == "Mirror" then
		if Toggles.MiscESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Mirror", Color = Options.MiscESPColor.Value }, true) end
		table.insert(Objects.Misc, Object)
	elseif Name == "StairwellFireAlarm" then
		if Toggles.MiscESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Fire Alarm", Color = Options.MiscESPColor.Value }, true) end
		table.insert(Objects.Misc, Object)
	elseif Name == "ShoppingCart" then
		if Toggles.MiscESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Shopping Cart", Color = Options.MiscESPColor.Value }, true) end
		table.insert(Objects.Misc, Object)
	elseif Name == "StairwellScrapper" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Scrapper", Color = Options.ObjectiveESPColor.Value }, true) end
		table.insert(Objects.Objectives, Object)
	elseif Name == "ArchivesPackageDeposit" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Package Deposit", Color = Options.ObjectiveESPColor.Value }, true) end
		table.insert(Objects.Objectives, Object)
	elseif Name == "Cellar" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Cellar", Color = Options.ObjectiveESPColor.Value }, true) end
		table.insert(Objects.Objectives, Object)
	elseif Name == "ArchivesFihTank" then
		if Toggles.MiscESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Fih Tank", Color = Options.MiscESPColor.Value }, true) end
		table.insert(Objects.Misc, Object)
	elseif Name == "LiveHintBook" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Hint Book", Color = Options.ObjectiveESPColor.Value }, true) end
		table.insert(Objects.Objectives, Object)
	elseif Name == "LiveBreakerPolePickup" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Fuse Breaker", Color = Options.ObjectiveESPColor.Value }, true) end
		for _, Child in Object:GetChildren() do
			if Child.Name == "ActivateEventPrompt" and (Child.MaxActivationDistance == 5 or Child:GetAttribute("MaxActivationDistance_Old") == 5) then
				Child:Destroy()
			end
		end
		table.insert(Objects.Objectives, Object)
	elseif Name == "LibraryHintPaper" or Name == "PickupItem" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Hint Paper", Color = Options.ObjectiveESPColor.Value }, true) end
		table.insert(Objects.Objectives, Object)
	elseif Name == "MinesAnchor" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Anchor [" .. Object:WaitForChild("Sign").TextLabel.Text .. "]", Color = Options.ObjectiveESPColor.Value }, true) end
		Object:GetAttributeChangedSignal("Activated"):Once(function()
			Functions.RemoveESP(Object)
			Functions.BlacklistESP(Object)
		end)
		table.insert(Objects.Objectives, Object)
	elseif Name == "WaterPump" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object:WaitForChild("Wheel"), Text = "Water Pump", Color = Options.ObjectiveESPColor.Value }, true) end
		Object:WaitForChild("Wheel").Sound.Played:Once(function()
			Object:SetAttribute("Abysall_Completed", true)

			Functions.RemoveESP(Object.Wheel)
			Functions.BlacklistESP(Object.Wheel)
		end)
		table.insert(Objects.Objectives, Object)
	elseif Name == "CringlePresent" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Present", Color = Options.ObjectiveESPColor.Value }, true) end
		Object:WaitForChild("ToolProp").Highlight:Destroy()
		table.insert(Objects.Objectives, Object)
	elseif Name == "LeverForGate" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Gate Lever", Color = Options.ObjectiveESPColor.Value }, true) end
		Object:WaitForChild("Main").SoundToPlay.Played:Once(function()
			Functions.RemoveESP(Object)
			Functions.BlacklistESP(Object)
		end)
		table.insert(Objects.Objectives, Object)
	elseif Name == "VineGuillotine" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object.Lever, Text = "Vine Lever", Color = Options.ObjectiveESPColor.Value }, true) end
		Object.Lever:WaitForChild("ActivateEventPrompt"):GetAttributeChangedSignal("Interactions"):Once(function()
			Functions.RemoveESP(Object)
			Functions.BlacklistESP(Object)
		end)
		table.insert(Objects.Objectives, Object)
	elseif Name == "MandrakeLive" then
		if Toggles.ObjectiveESPToggle.Value and Options.EntityESPOptions.Value["Mandrake Hole"] then Functions.AddESP({ Object = Object.Hole, Text = "Mandrake Hole", Color = Options.EntityESPColor.Value }, true) end
		table.insert(Objects.Entities, Object.Hole)
	elseif Name == "MinesGenerator" then
		task.spawn(function()
			task.wait(0.75)
			if Object.Parent then
				if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Generator", Color = Options.ObjectiveESPColor.Value }, true) end
				Object:WaitForChild("Lever").Sound.Played:Once(function()
					Functions.RemoveESP(Object)
					Functions.BlacklistESP(Object)
				end)
				table.insert(Objects.Objectives, Object)
			end
		end)
	elseif Name == "FuseObtain" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Generator Fuse", Color = Options.ObjectiveESPColor.Value }, true) end
		Object:WaitForChild("Hitbox").FuseModel:GetPropertyChangedSignal("LocalTransparencyModifier"):Once(function()
			Functions.RemoveESP(Object)
			Functions.BlacklistESP(Object)
		end)
		table.insert(Objects.Objectives, Object)
	elseif Name == "MinesGateButton" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Gate Button", Color = Options.ObjectiveESPColor.Value }, true) end
		Object.Parent:WaitForChild("MinesGate").Main.SoundOpen.Played:Once(function()
			Functions.RemoveESP(Object)
			Functions.BlacklistESP(Object)
		end)
		table.insert(Objects.Objectives, Object)
	elseif Name == "GardenGateButton" then
		if Toggles.ObjectiveESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Gate Button", Color = Options.ObjectiveESPColor.Value }, true) end
		Object.Parent:WaitForChild("GardenGate").Collision.Sound.Played:Once(function()
			Functions.RemoveESP(Object)
			Functions.BlacklistESP(Object)
		end)
		table.insert(Objects.Objectives, Object)
	elseif Name == "Ladder" then
		if Toggles.LadderESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Ladder", Color = Options.LadderESPColor.Value }, true) end
		table.insert(Objects.Ladders, Object)
	elseif Name == "Door" and Object.Parent and tonumber(Object.Parent.Name) then
		local DoorParts = {}
		for _, Child in Object:GetChildren() do
			if Child.Name == "Door" and Child:IsA("BasePart") then
				table.insert(DoorParts, Child)
			end
		end

		if #DoorParts == 2 then
			local HighlightModel = Instance.new("Model", Object)
			HighlightModel.Name = "HighlightModel"
			Instance.new("Humanoid", HighlightModel).Name = "HighlightHumanoid"
			HighlightModel:SetAttribute("ParentRoom", tonumber(Object.Parent.Name))

			for _, DoorPart in DoorParts do
				local HP = Instance.new("Part", HighlightModel)
				HP.Transparency = 0.999
				HP.Size = DoorPart.Size
				HP.CanCollide = false
				HP.CFrame = DoorPart.CFrame
				HP.Name = "HighlightPart"
				HP.Material = Enum.Material.Plastic
				HP:SetAttribute("ParentRoom", tonumber(Object.Parent.Name))
				local W = Instance.new("WeldConstraint", HP)
				W.Part0 = HP W.Part1 = DoorPart W.Enabled = true
			end
			table.insert(Objects.Doors, HighlightModel)
			if Toggles.DoorESPToggle.Value then Functions.AddESP({ Object = HighlightModel, Text = "Door " .. Functions.GetDoorNumber(Object), Color = Options.DoorESPColor.Value }, true) end
		else
			local Root = Object:WaitForChild("Door", 9e9)
			local HP = Instance.new("Part", Object)
			HP.Transparency = 0.999
			HP.Size = Root.Size
			HP.CanCollide = false
			HP.CFrame = Root.CFrame
			HP.Name = "HighlightPart"
			HP.Material = Enum.Material.Plastic
			HP:SetAttribute("ParentRoom", tonumber(Object.Parent.Name))
			local W = Instance.new("WeldConstraint", HP)
			W.Part0 = HP W.Part1 = Root W.Enabled = true
			Instance.new("Humanoid", Object).Name = "HighlightHumanoid"
			table.insert(Objects.Doors, HP)
			if Toggles.DoorESPToggle.Value then Functions.AddESP({ Object = HP, Text = "Door " .. Functions.GetDoorNumber(Object), Color = Options.DoorESPColor.Value }, true) end
		end

		local LastDoorFire = tick()
		local DoorConn = Services.RunService.Heartbeat:Connect(function()
			if Object:FindFirstChild("Door") and Object:FindFirstChild("ClientOpen") then
				if LocalPlayer:DistanceFromCharacter(Object.Door.Position) < 75
					and tick() - LastDoorFire > 0.1
					and (Toggles.DoorReachToggle.Value or Functions.GetMinecart())
				then
					Object.ClientOpen:FireServer()
					LastDoorFire = tick()
				end
			end
		end)
		Object.Destroying:Once(function()
			DoorConn:Disconnect()
		end)
		Object:WaitForChild("Door"):WaitForChild("Open").Played:Once(function()
			DoorConn:Disconnect()
		end)
		table.insert(Connections, DoorConn)

	elseif Name == "PathLights" then
		local ObjectsToHighlight = {}
		local PLConn = Object.ChildAdded:Connect(function(Child)
			table.insert(ObjectsToHighlight, Child)
		end)
		for _, Child in Object:GetChildren() do
			table.insert(ObjectsToHighlight, Child)
		end

		local function CreateSeekNode(Light)
			if Light.Name ~= "SeekGuidingLight" or Light:GetAttribute("Highlighted") then return end
			Light:SetAttribute("Highlighted", true)

			local NewNode = Instance.new("Part")
			NewNode.Size = Vector3.one
			NewNode.Transparency = 1
			NewNode.Parent = Globals.SeekNodesFolder
			NewNode.Anchored = true
			NewNode.CFrame = Light.CFrame
			NewNode.CanCollide = false
			NewNode.Name = "SeekLightNode"

			local PrevNode2 = PreviousNode or NewNode
			PreviousNode = NewNode

			local Beam = Instance.new("Beam")
			Beam.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Options.ShowSeekPathColor.Value), ColorSequenceKeypoint.new(1, Options.ShowSeekPathColor.Value) })
			Beam.FaceCamera = true
			Beam.Width0 = 0.2
			Beam.Width1 = 0.2
			Beam.Brightness = 10
			Beam.LightInfluence = 0
			Beam.LightEmission = 0
			Beam.Enabled = true
			local Vis = Toggles.ShowSeekPathToggle.Value and 0 or 1
			Beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, Vis), NumberSequenceKeypoint.new(1, Vis) })
			Beam.Parent = Globals.SeekNodesFolder
			local A0 = Instance.new("Attachment", NewNode)
			local A1 = Instance.new("Attachment", PrevNode2)
			Beam.Attachment0 = A0
			Beam.Attachment1 = A1
			table.insert(Objects.SeekHighlights, Beam)
			Light:Destroy()
		end

		task.spawn(function()
			while task.wait() do
				local Light = table.remove(ObjectsToHighlight, 1)
				if Light then CreateSeekNode(Light) end
			end
		end)

		table.insert(Connections, PLConn)
		table.insert(Objects.PathLights, Object)
		Object.Destroying:Once(function() PLConn:Disconnect() end)
	elseif Name == "SeekMovingNewClone" then
		local Connection = Object.Destroying:Connect(function()
			for _, Folder in pairs(Objects.PathLights) do
				Folder:ClearAllChildren()
			end
			Globals.SeekNodesFolder:ClearAllChildren()
		end)
		table.insert(Connections, Connection)
	elseif Name == "Bridge" then
		for _, Child in Object:GetChildren() do
			if Child.Name == "PlayerBarrier" and Child.Size.Y == 2.75 and (Child.Rotation.X == 0 or Child.Rotation.X == 180) then
				local NewBridge = Child:Clone()
				NewBridge.CFrame = NewBridge.CFrame * CFrame.new(0, 0, -5)
				NewBridge.Name = Abysall.ESPLibrary:GenerateRandomString()
				NewBridge.Size = Vector3.new(NewBridge.Size.X, NewBridge.Size.Y, 11)
				NewBridge.Parent = Object
				NewBridge.CanCollide = Toggles.BypassSeekObstructions.Value
				NewBridge.Color = Color3.fromRGB(0, 255, 255)
				NewBridge.Transparency = Toggles.BypassSeekObstructions.Value and 0 or 1
				NewBridge.Material = Enum.Material.ForceField
				table.insert(Objects.SeekBridges, NewBridge)
			end
			task.wait()
		end
    elseif Name == "MinecartRig" then
        Globals.Minecart = Object
	elseif Name == "RunnerNodes" then
		local function IsBehind(Part1, Part2)
			local P1 = (Part1.CFrame + Part1.CFrame.LookVector).Position
			local P2 = (Part1.CFrame + Part1.CFrame.LookVector * -1).Position
			return (P1 - Part2.Position).Magnitude > (P2 - Part2.Position).Magnitude
		end
		local function GetDirection(Part1, Part2)
			local RightDist = Part1.CFrame.RightVector:Dot(Part1.Position - Part2.Position)
			if RightDist > 0.5    then return IsBehind(Part1, Part2) and "Right" or "Left" end
			if RightDist < -0.5   then return IsBehind(Part1, Part2) and "Left" or "Right" end
			return "Straight"
		end
		local function GetClosestNode(Node)
			local Best, BestDist = nil, math.huge
			local NodeID2 = tonumber(Node.Name:split("MinecartNode")[2])
			for _, OtherNode in Object:GetChildren() do
				local OtherID = tonumber(OtherNode.Name:split("MinecartNode")[2])
				if OtherNode ~= Node and OtherID and NodeID2 and OtherID > NodeID2 then
					local D = (Node.Position - OtherNode.Position).Magnitude
					if D < BestDist and OtherNode:GetAttribute("DistanceBlacklist") ~= true then
						BestDist = D Best = OtherNode
					end
				end
			end
			return Best
		end

		for _, Node in Object:GetChildren() do
			local NodeID = tonumber(Node.Name:split("MinecartNode")[2])
			if Node:GetAttribute("DeathType") then Node:SetAttribute("DistanceBlacklist", true) end
			for I = 1, 20 do
				local NextNode = NodeID and Object:FindFirstChild("MinecartNode" .. NodeID + I)
				if NextNode and NextNode:GetAttribute("DeathType") ~= nil then
					Node:SetAttribute("DistanceBlacklist", true)
				end
			end
			local PrevNode3 = NodeID and Object:FindFirstChild("MinecartNode" .. NodeID - 1)
			if PrevNode3 and PrevNode3:GetAttribute("ForceConnect") then
				Node:SetAttribute("DistanceBlacklist", nil)
			end
			task.wait()
		end

		for _, Node in Object:GetChildren() do
			if Node:GetAttribute("ForceConnect") then
				local NextNode = GetClosestNode(Node)
				if NextNode then
					Node:SetAttribute("Turn", GetDirection(Node, NextNode))
					table.insert(Objects.SeekNodes, Node)
				end
			end
			task.wait()
		end

	elseif Name == "EyestalkEndCutscene" then
		Object.Name = "_EyestalkEndCutscene"
	elseif Name == "DuckBoard" then
		table.insert(Objects.SeekDuckBoards, Object)
	elseif HidingSpotLabels[Name] or string.find(string.lower(Name), "hidingspot") then
		local Label = HidingSpotLabels[Name] or (string.find(string.lower(Name), "hidingspot") and "Hiding Spot" or nil)
		if Label and Toggles.HidingSpotESPToggle.Value then Functions.AddESP({ Object = Object, Text = Label, Color = Options.HidingSpotESPColor.Value }, true) end
		Functions.HandleHidingTransparency(Object)
		table.insert(Objects.HidingSpots, Object)
	elseif Object:FindFirstChild("HidingPrompt") or Object:FindFirstChild("HidePrompt") then
		Functions.HandleHidingTransparency(Object)
		table.insert(Objects.HidingSpots, Object)
	elseif Name == "Lava" then
		if Toggles.BypassKillbricks.Value then Object.CanTouch = false end
		table.insert(Objects.Obstructions, Object)
	elseif Name == "ScaryWall" then
		for _, Part in Object:GetDescendants() do
			if Part:IsA("BasePart") then
				Part.CanTouch = not Toggles.BypassSeekingWall.Value
				Part.CanCollide = not Toggles.BypassSeekingWall.Value

                local Connection1 = Part:GetPropertyChangedSignal("CanTouch"):Connect(function()
                    if Part.CanTouch == Toggles.BypassSeekingWall.Value then
                        Part.CanTouch = not Toggles.BypassSeekingWall.Value
                    end
                end)
                local Connection2 = Part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                    if Part.CanCollide == Toggles.BypassSeekingWall.Value then
                        Part.CanCollide = not Toggles.BypassSeekingWall.Value
                    end
                end)

                table.insert(Connections, Connection1)
                table.insert(Connections, Connection2)
            end
		end
		table.insert(Objects.Obstructions, Object)
	elseif Name == "ChestBox" or Name == "ChestBoxLocked" then
		if Toggles.ChestESPToggle.Value then Functions.AddESP({ Object = Object, Text = Object:GetAttribute("Locked") and "Locked Chest" or "Chest", Color = Options.ChestESPColor.Value }, true) end
		table.insert(Objects.Chests, Object)
	elseif Name == "Toolbox" or Name == "Toolbox_Locked" then
		if Toggles.ChestESPToggle.Value then Functions.AddESP({ Object = Object, Text = Object:GetAttribute("Locked") and "Locked Toolbox" or "Toolbox", Color = Options.ChestESPColor.Value }, true) end
		table.insert(Objects.Chests, Object)
	elseif Name == "Chest_Vine" then
		if Toggles.ChestESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Vine Chest", Color = Options.ChestESPColor.Value }, true) end
		table.insert(Objects.Chests, Object)
	elseif Name == "Toolshed_Small" then
		if Toggles.ChestESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Toolshed", Color = Options.ChestESPColor.Value }, true) end
		table.insert(Objects.Chests, Object)
	elseif Name == "Locker_Small_Locked" then
		if Toggles.ChestESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Locked Item Locker", Color = Options.ChestESPColor.Value }, true) end
		table.insert(Objects.Chests, Object)
	elseif Name == "MouseHole" then
		if Toggles.ChestESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Mouse", Color = Options.ChestESPColor.Value }, true) end
		table.insert(Objects.Chests, Object)
	elseif ItemNames[Name] and Object:FindFirstChild("ModulePrompt") then
		if Toggles.ItemESPToggle.Value then Functions.AddESP({ Object = Object, Text = ItemNames[Name], Color = Options.ItemESPColor.Value }, Object:GetAttribute("ParentRoom") ~= nil) end
		if Name == "LotusHolder" or Name == "LotusPetalPickup" then
			Object.Handle:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
				Abysall.ESPLibrary:RemoveESP(Object)
				Functions.BlacklistESP(Object)
			end)
		end

		if Toggles.NotifyItemsToggle.Value and Options.NotifyItemList.Value[ItemNames[Name]] and Object.Parent.Name ~= "Drops" then
			if Toggles.NotifyItemsShowDistance.Value then
				Functions.Notify({ Title = "Item '" .. ItemNames[Name] .. "' has spawned.", Body = "It is '" .. math.round(LocalPlayer:DistanceFromCharacter(Object.PrimaryPart.Position)) .. "' studs away from you." })
			else
				Functions.Notify({ Title = "Item '" .. ItemNames[Name] .. "' has spawned."})
			end
		end
		if Toggles.ImportedItemChat and Toggles.ImportedItemChat.Value and Options.NotifyItemList.Value[ItemNames[Name]] and Object.Parent.Name ~= "Drops" then
			local Message = tostring(Options.ImportedItemChatMessage.Value or "Item: {item}")
			Functions.SendChat((string.gsub(Message, "{item}", ItemNames[Name])))
		end

		table.insert(Objects.Items, Object)
	elseif Name == "Green_Herb" then
		if Toggles.ItemESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Green Herb", Color = Options.ItemESPColor.Value }, true) end
		table.insert(Objects.Items, Object)
	elseif Name == "GoldPile" and Object:GetAttribute("GoldValue") then
		if Toggles.CurrencyESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Gold Pile [" .. Object:GetAttribute("GoldValue") .. "]", Color = Options.CurrencyESPColor.Value }, true) end
		table.insert(Objects.Currency, Object)
	elseif Name == "StardustPickup" then
		if Toggles.CurrencyESPToggle.Value then Functions.AddESP({ Object = Object, Text = "Stardust Pile", Color = Options.CurrencyESPColor.Value }, true) end
		table.insert(Objects.Currency, Object)
	elseif Name == "GiggleCeiling" then
		if Toggles.EntityESPToggle.Value and Options.EntityESPOptions.Value["Giggle"] then Functions.AddESP({ Object = Object, Text = "Giggle", Color = Options.EntityESPColor.Value }, true) end
		if Toggles.BypassGiggle.Value then Object:WaitForChild("Hitbox").CanTouch = false end
		table.insert(Objects.Entities, Object)
	elseif Name == "GloomPile" then
		if Toggles.BypassGloombatEggs.Value then
			for _, Part in Object:GetDescendants() do
				if Part:IsA("BasePart") then Part.CanTouch = false
				end
			end
		end
		local Connection = Object.DescendantAdded:Connect(function(Part)
			if Part:IsA("BasePart") then Part.CanTouch = false end
		end)

		if Toggles.EntityESPToggle.Value and Options.EntityESPOptions.Value["Gloombat Eggs"] then
			Functions.AddESP({ Object = Object, Text = "Gloombat Eggs", Color = Options.EntityESPColor.Value })
		end

		table.insert(Connections, Connection)
		table.insert(Objects.Entities, Object)
	elseif Name == "TriggerEventCollision" and Functions.CheckCompatability({"firetouchinterest"}) then
		if (Floor == "Fools" or Floor == "OldHotel") and Toggles.RemoveSeekTrigger.Value then
			task.spawn(function()
				while Object:IsDescendantOf(game) do
					for _, Part in Object:GetChildren() do
						if Part:IsA("BasePart") then
							Abysall.Environment.firetouchinterest(RootPart, Part, 0)
							task.wait()
							Abysall.Environment.firetouchinterest(RootPart, Part, 1)
						end
					end
					task.wait()
				end
			end)
		end
		table.insert(Objects.EventTriggers, Object)
	elseif Name == "DoorFake" or Name == "FakeDoor" then
		if Object.Parent and Object:FindFirstChild("Hidden") then
			if Toggles.BypassDupe.Value then
				Object:WaitForChild("Hidden").CanTouch = false
				local Lock = Object:FindFirstChild("Lock")
				if Lock and Lock:FindFirstChild("UnlockPrompt") then Lock.UnlockPrompt.Enabled = false end
			end
			if Toggles.EntityESPToggle.Value and Options.EntityESPOptions.Value["Dupe"] then
				Functions.AddESP({ Object = Object, Text = "Dupe", Color = Options.EntityESPColor.Value }, true)
			end
			table.insert(Objects.Entities, Object)
		end
	elseif Name == "SideroomSpace" then
		if Toggles.BypassVacuum.Value then
			Object:WaitForChild("Collision").CanCollide = true
			Object:WaitForChild("Collision").CanTouch = false
		end
		table.insert(Objects.Entities, Object)
	elseif Name == "Snare" then
		if Toggles.EntityESPToggle.Value and Options.EntityESPOptions.Value["Snare"] then Functions.AddESP({ Object = Object, Text = "Snare", Color = Options.EntityESPColor.Value }, true) end
		for _, Part in Object:GetDescendants() do
			if Part:IsA("BasePart") then Part.CanTouch = not Toggles.BypassSnare.Value end
		end
		local Connection = Object.DescendantAdded:Connect(function(Part)
			if Part:IsA("BasePart") then Part.CanTouch = not Toggles.BypassSnare.Value end
		end)
		table.insert(Connections, Connection)
		table.insert(Objects.Entities, Object)

		if Object:FindFirstChild("Snare") then
			Object:WaitForChild("Snare"):WaitForChild("Roots").Transparency = 1
			Object:WaitForChild("Snare"):WaitForChild("SnareBase").Transparency = 1
		end
		if Object:FindFirstChild("Void") then
			Object.Void.Transparency = 0
			Object.Void.Color = Color3.fromRGB(76, 67, 55)
		end
	elseif Name == "Seek_Arm" or Name == "ChandelierObstruction" then
		for _, Part in Object:GetDescendants() do
			if Part:IsA("BasePart") then
				Part.CanTouch = not Toggles.BypassSeekObstructions.Value
				table.insert(Objects.SeekObstructions, Part)
			end
		end
	elseif Name == "SeekFloodline" then
		Object.CanCollide = Toggles.BypassSeekObstructions.Value
		local FloodConn = Object:GetPropertyChangedSignal("CanCollide"):Connect(function()
			if Object.CanCollide ~= Toggles.BypassSeekObstructions.Value then
				Object.CanCollide = Toggles.BypassSeekObstructions.Value
			end
		end)
		Object.Destroying:Once(function() FloodConn:Disconnect() end)
		table.insert(Objects.SeekObstructions, Object)
	elseif Object:GetAttribute("RawName") and Object:GetAttribute("RawName"):find("Halt") or Object:GetAttribute("Shade") == true then
		if Toggles.NotifyEntities.Value and Options.EntityList.Value["Halt"] then
			Functions.Notify({ Title = "Entity 'Halt' will spawn in the next room.", Image = EntityIcons["Halt"] })
			if Toggles.EntityChatToggle.Value then Functions.SendChat("Halt next room!") end
		end
		local HaltLogConn
		HaltLogConn = Services.LogService.MessageOut:Connect(function(Message)
			if Message == "client teleporting" then
				if Globals.AnticheatDisabled then
					Globals.AnticheatDisabled = false
					Functions.Notify({ Title = "The anticheat has been re-enabled.", Body = "Use a ladder, Stairwell cart, or Archives office chair to disable it again." })
				end
				HaltLogConn:Disconnect()
			end
		end)
	elseif Name == "BananaPeel" then
		if Toggles.BypassBanana.Value then Object.CanTouch = false end
		table.insert(Objects.Entities, Object)
	elseif Name == "JeffTheKiller" then
		if Toggles.BypassJeff.Value then
			for _, Part in Object:GetDescendants() do
				if Part:IsA("BasePart") then Part.CanCollide = false Part.CanTouch = false end
			end
			Object:WaitForChild("Humanoid").Health = 0
		end
	elseif Name == "GrumbleRig" then
		if Toggles.EntityESPToggle.Value and Options.EntityESPOptions.Value["Grumble"] then Functions.AddESP({ Object = Object, Text = "Grumble", Color = Options.EntityESPColor.Value }, true) end
		table.insert(Objects.Entities, Object)
	elseif Name == "LiveEntityBramble" then
		if Toggles.EntityESPToggle.Value and Options.EntityESPOptions.Value["Bramble"] then Functions.AddESP({ Object = Object, Text = "Bramble", Color = Options.EntityESPColor.Value }, true) end
		table.insert(Objects.Entities, Object)
	elseif Name == "Groundskeeper" then
		if Toggles.EntityESPToggle.Value and Options.EntityESPOptions.Value["Groundskeeper"] then Functions.AddESP({ Object = Object, Text = "Groundskeeper", Color = Options.EntityESPColor.Value }, true) end
		if Toggles.NotifyEntities.Value and Options.EntityList.Value["Groundskeeper"] then
			local ED = Entities["Groundskeeper"]
			Functions.Notify({ Title = ED.NotifyMessage.Title, Body = ED.NotifyMessage.Body, Image = EntityIcons["Groundskeeper"] })
		end
		table.insert(Objects.Entities, Object)
	elseif Name == "Figure" or Name == "FigureRig" or Name == "FigureRagdoll" then
		for _, Part in Object:GetDescendants() do
			if Part:IsA("BasePart") then
				Part.CanTouch = false
			end
		end
		if Toggles.EntityESPToggle.Value and Options.EntityESPOptions.Value["Figure"] then Functions.AddESP({ Object = Object, Text = "Figure", Color = Options.EntityESPColor.Value }, true) end
		table.insert(Objects.Entities, Object)
		if Toggles.RemoveFigure.Value and Functions.CheckCompatability({"isnetworkowner"}) then
			if Floor == "Mines" then
				for _, Part in Object:GetDescendants() do
					if Part:IsA("BasePart") then
						task.spawn(function()
							if Abysall.Environment.isnetworkowner(Part) then
								Part.Position = Vector3.new(-49999, -49999, -49999)
							end
						end)
					end
				end
			elseif Floor == "OldHotel" or Floor == "Fools" then
				CurrentRooms.ChildAdded:Wait()
				for _, Part in Object:GetDescendants() do
					if Part:IsA("BasePart") then
						Part.CanCollide = false
						task.spawn(function()
							while Abysall.Environment.isnetworkowner(Part) do
								Part.Position = Vector3.new(math.random(-29999,29999), math.random(-29999,29999), math.random(-29999,29999))
								task.wait()
							end
						end)
					end
				end
			end
		end
	elseif (Name == "ThingToOpen" or Name == "MovingDoor") and (Floor == "Fools" or Floor == "OldHotel")
		or Name == "Wax_Door" and Floor == "Fools"
	then
		Object:SetAttribute("OriginalPosition", Object:GetPivot())
		local ToggleMap = { ThingToOpen = "RemoveBasementGate", MovingDoor = "RemovePaintingsDoor", Wax_Door = "RemoveSkeletonDoor" }
		if ToggleMap[Name] and Toggles[ToggleMap[Name]].Value then
			Object:PivotTo(CFrame.new(-10000, -10000, -10000))
		end
		table.insert(Objects.Obstructions, Object)
	elseif Name == "ElevatorBreaker" then
		if Toggles.AutoBreakerBox.Value and not Globals.BreakerBoxNotified then
			Functions.Notify({ Title = "Interact with the breaker box.", Body = "It will be automatically solved." })
			Globals.BreakerBoxNotified = true
		end
		Connections.BreakerConnection = Object:WaitForChild("SurfaceGui").Frame.Code:GetPropertyChangedSignal("Text"):Connect(function()
			if Toggles.AutoBreakerBox.Value then
				if not Globals.BreakerBoxStartNotified and (Floor == "Fools" or Floor == "OldHotel") then
					Functions.Notify({ Title = "Attempting to solve the breaker box.", Body = "Please wait." })
					Globals.BreakerBoxStartNotified = true
				end
				RemotesFolder.EBF:FireServer()
			end
			Globals.BreakerBoxInteracted = true
		end)
	elseif Name == "ElevatorCar" then
		local ElevConn = Object.DescendantAdded:Connect(function(Desc)
			if Toggles.AutoBreakerBox.Value and Desc.Name == "TouchInterest" and not Globals.BreakerBoxFinishedNotified then
				Functions.Notify({ Title = "Successfully solved the breaker box.", Body = "Try going to the elevator!" })
				Globals.BreakerBoxFinishedNotified = true
			end
		end)
		Object.Destroying:Once(function() ElevConn:Disconnect() end)
	elseif Object.ClassName == "ProximityPrompt" and not Object:GetAttribute("FakePrompt") then
		if not Object.Parent then return end -- prompt was destroyed/unparented while queued
		if Object:HasTag("DisableWhenEnabledOnClient") then Object:RemoveTag("DisableWhenEnabledOnClient") end

		Object:SetAttribute("HoldDuration_Old", Object.HoldDuration)
		Object:SetAttribute("RequiresLineOfSight_Old", Object.RequiresLineOfSight)
		Object:SetAttribute("MaxActivationDistance_Old", Object.MaxActivationDistance)

		if Toggles.InstantPrompts.Value    then Object.HoldDuration = 0 end
		if Toggles.PromptClip.Value        then Object.RequiresLineOfSight = false end
		Object.MaxActivationDistance = Object:GetAttribute("MaxActivationDistance_Old") * Options.PromptReachSlider.Value

		local LockPromptNames = { UnlockPrompt=true, SkullPrompt=true, LockPrompt=true, ThingToEnable=true, FusesPrompt=true }

		if Functions.CheckCompatability({"fireproximityprompt"}) and Floor ~= "OldHotel" and Floor ~= "Fools" then
			local IsLockPrompt = LockPromptNames[Object.Name] and Object.Parent.Name ~= "Handle" and Object.Parent.Name ~= "LockHolder"
				or (Object.Parent and Object.Parent:GetAttribute("Locked") == true)
				or (Object.Parent and Object.Parent.Parent and Object.Parent.Parent.Name == "Locker_Small_Locked" and Object.Name == "ActivateEventPrompt")

			if IsLockPrompt then
				local FakePrompt = Object:Clone()
				FakePrompt:SetAttribute("FakePrompt", true)
				task.wait()
				FakePrompt.Parent = Object.Parent

				FakePrompt:SetAttribute("HoldDuration_Old", Object:GetAttribute("HoldDuration_Old"))
				FakePrompt:SetAttribute("RequiresLineOfSight_Old", Object:GetAttribute("RequiresLineOfSight_Old"))
				FakePrompt:SetAttribute("MaxActivationDistance_Old", Object:GetAttribute("MaxActivationDistance_Old"))

				FakePrompt.HoldDuration = Object.HoldDuration
				FakePrompt.RequiresLineOfSight = Object.RequiresLineOfSight
				FakePrompt.MaxActivationDistance = Object.MaxActivationDistance

				if Toggles.InstantPrompts.Value    then FakePrompt.HoldDuration = 0 end
				if Toggles.PromptClip.Value        then FakePrompt.RequiresLineOfSight = false end
				FakePrompt.MaxActivationDistance = FakePrompt:GetAttribute("MaxActivationDistance_Old") * Options.PromptReachSlider.Value

				FakePrompts[FakePrompt] = Object
				pcall(function() Object.Parent = Globals.PromptContainer end)

				local FPEnabledConn = Object:GetPropertyChangedSignal("Enabled"):Connect(function()
					FakePrompt.Enabled = Object.Enabled
				end)
				Object:GetPropertyChangedSignal("ActionText"):Once(function()
					Object.Parent = FakePrompt.Parent
					FakePrompt:Destroy()
					FPEnabledConn:Disconnect()
				end)
				Object.Destroying:Once(function()
					FakePrompt:Destroy()
					FPEnabledConn:Disconnect()
				end)
				table.insert(Connections, FPEnabledConn)
				table.insert(Objects.Prompts, FakePrompt)

				FakePrompt.Enabled = false
				task.wait()
				FakePrompt.Enabled = Object.Enabled
			end
		end
		table.insert(Objects.Prompts, Object)
	elseif Name == "Padlock" then
		local PadlockConn = Services.RunService.Heartbeat:Connect(function()
			if Object.PrimaryPart then
				local Distance = LocalPlayer:DistanceFromCharacter(Object.PrimaryPart.Position)
				if Toggles.AutoUnlockPadlockToggle.Value then
					local Code = Functions.GetLibraryCode()
					if Code and tonumber(Code) and Distance < Options.AutoUnlockPadlockSlider.Value then
						RemotesFolder.PL:FireServer(Code)
					end
				end
				if Toggles.AutoLibraryGuessCode.Value and LatestRoom.Value == 50 then
					local Code = Functions.GetRandomCode()
					if Code then RemotesFolder.PL:FireServer(Code) end
				end
			end
		end)
		Object.Destroying:Once(function()
			PadlockConn:Disconnect()
		end)
	end
end

Connections.PromptAnimationFixer1 = Services.ProximityPromptService.PromptButtonHoldBegan:Connect(function(Object)
	if not Object:GetAttribute("FakePrompt") then return end
	local ToolNames = { "Lockpick","Shears","SkeletonKey","Key","GeneratorFuse","KeyElectrical","KeyBackdoor","KeyIron", "Multitool" }
	local AnimateToolNames = { "Lockpick","Shears","SkeletonKey","Key","KeyElectrical","KeyBackdoor","KeyIron", "Multitool" }
	local Tool
	for _, N in ToolNames do Tool = Character:FindFirstChild(N) if Tool then break end end

	local Prompt = Object
	local LockPromptNames = { UnlockPrompt=true, SkullPrompt=true, LockPrompt=true, ThingToEnable=true, FusesPrompt=true }
	local IsLockPrompt = LockPromptNames[Object.Name]
		or (Object.Parent and Object.Parent:GetAttribute("Locked") == true)
		or (Object.Parent and Object.Parent.Parent and Object.Parent.Parent.Name == "Locker_Small_Locked" and Object.Name == "ActivateEventPrompt")
	if IsLockPrompt then
		if Options.AutoInteractIgnoreList.Value["Locks"] then return end
		local KeyItems = { "Key","GeneratorFuse","KeyBackdoor","KeyElectrical","KeyIron","Lockpick","SkeletonKey","Shears","Multitool" }
		local OffhandKeyItems = { "Key","GeneratorFuse","KeyElectrical","KeyIron" }
		local HasKey = false
		for _, K in KeyItems do if Functions.HasItem(K, true) then HasKey = true break end end
		for _, K in OffhandKeyItems do if Functions.HasItem(K) then HasKey = true break end end
		if not HasKey then return end
	end

	if Prompt.Parent.Name == "CuttableVines" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Chest_Vine" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Cellar" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) then return end
	if Prompt.Parent.Name == "SkullLock" and not Functions.HasItem("SkeletonKey", true) then return end
	if Prompt.Parent.Name == "Lock1" and not Functions.HasItem("Lockpick", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Lock2" and not Functions.HasItem("Lockpick", true) and not Functions.HasItem("Multitool", true) then return end
	if Functions.HasItem("Shears", true) and IsLockPrompt and Prompt.Parent.Name ~= "CuttableVines" and Prompt.Parent.Name ~= "Chest_Vine" and Prompt.Parent.Name ~= "Cellar" then return end
	
	if Tool and table.find(AnimateToolNames, Tool.Name) and Globals.UseAnimation then
		Globals.UseAnimationBreak:Stop()
		Globals.UseAnimation:Stop()
		Globals.UseAnimation:Play()
		if Tool.Name == "Shears" then Tool:WaitForChild("Handle"):WaitForChild("sound_prompt"):Play() end
	end
end)

Globals.ObjectQueue = {}
local AllowedInstances = {
	Lava=true, GoldPile=true, KeyObtain=true, Drakobloxxer=true, FuseObtain=true,
	MinesGenerator=true, JeffTheKiller=true, Snare=true, FakeDoor=true, DoorFake=true, SideroomSpace=true,
	ChestBox=true, ChestBoxLocked=true, Chest_Vine=true, Locker_Small_Locked=true, Toolbox=true,
	Toolbox_Locked=true, Wardrobe=true, ["Wardrobe-FOOLS26"]=true, Toolshed=true, Toolshed_Small=true,
	Bed=true, MinesAnchor=true, Double_Bed=true, RetroWardrobe=true, Backdoor_Wardrobe=true,
	Rooms_Locker=true, Rooms_Locker_Fridge=true, Locker_Large=true, FigureRig=true, FigureRagdoll=true,
	TimerLever=true, Lever=true, Seek_Arm=true, ChandelierObstruction=true, ScaryWall=true, Ladder=true,
	CircularVent=true, Dumpster=true, SquareGrate=true, TriggerEventCollision=true, GrumbleRig=true,
	GiggleCeiling=true, MinesGateButton=true, ElectricalKeyObtain=true, LibraryHintPaper=true,
	WaterPump=true, CringlePresent=true, Wheel=true, PickupItem=true, LiveHintBook=true,
	LiveBreakerPolePickup=true, LeverForGate=true, GloomPile=true, SeekFloodline=true, Door=true,
	Green_Herb=true, Bridge=true, MouseHole=true, BananaPeel=true, NannerPeel=true, PowerupPad=true,
	IndustrialGate=true, CollisionFloor=true, ElevatorCar=true, Wax_Door=true, ThingToOpen=true,
	MovingDoor=true, StardustPickup=true, Hole=true, Groundskeeper=true, MandrakeLive=true,
	GardenGateButton=true, LotusPetalPickup=true, VineGuillotine=true, LiveEntityBramble=true, ArchivesFihTank=true,
	RiftSpawn=true, ElevatorBreaker=true, RunnerNodes=true, PathLights=true, DuckBoard=true,
	Padlock=true, EyestalkEndCutscene=true, MinecartRig=true, SeekMovingNewClone=true, Cellar=true, ArchivesPackageDeposit=true, StairwellScrapper=true,
	StairwellFireAlarm=true, ShoppingCart=true, Mirror=true, StairwellLockpickDoor=true, DepotHalloween=true
}

Functions.QueueObject = function(Object)
	if TimeShowerClone and Object:IsDescendantOf(TimeShowerClone) then
		return
	end
	local IsHidingSpot = typeof(Object.Name) == "string" and string.find(string.lower(Object.Name), "hidingspot")
	if not AllowedInstances[Object.Name] and not IsHidingSpot and Object.ClassName ~= "ProximityPrompt" and Object.Parent ~= CurrentRooms and not ItemNames[Object.Name] then
		return
	end
	table.insert(Globals.ObjectQueue, Object)
end

Globals.QueueDone = true
Connections.QueueConnection = Services.RunService.RenderStepped:Connect(function()
	local Object = table.remove(Globals.ObjectQueue, 1)
	if Object then
		Functions.HandleObject(Object)
	end
end)

for _, Object in Services.Workspace:GetDescendants() do
	task.spawn(function() Functions.QueueObject(Object) end)
end

Connections.InstanceHandler = Services.Workspace.DescendantAdded:Connect(function(Object)
	Functions.QueueObject(Object)
end)

for _, Player in Services.Players:GetPlayers() do
	if Player ~= LocalPlayer then
		if Player.Character and Toggles.PlayerESPToggle.Value then
			Functions.AddESP({ Object = Player.Character, Text = Player.Name, Color = Options.PlayerESPColor.Value })
		end
		local CharConn = Player.CharacterAdded:Connect(function(NewCharacter)
			if Toggles.PlayerESPToggle.Value then
				Functions.AddESP({ Object = NewCharacter, Text = Player.Name, Color = Options.PlayerESPColor.Value })
			end
		end)
		local DeadConn = Player:GetAttributeChangedSignal("Alive"):Connect(function()
			if Player:GetAttribute("Alive") ~= true and Player.Character then
				Functions.RemoveESP(Player.Character)
			end
		end)
		table.insert(Connections, CharConn)
		table.insert(Connections, DeadConn)
		Player.Destroying:Once(function()
			CharConn:Disconnect()
			DeadConn:Disconnect()
		end)
	end
end

Connections.PlayerHandler = Services.Players.PlayerAdded:Connect(function(Player)
	if Player == LocalPlayer then return end
	if Player.Character and Toggles.PlayerESPToggle.Value then
		Functions.AddESP({ Object = Player.Character, Text = Player.Name, Color = Options.PlayerESPColor.Value })
	end
	local CharConn = Player.CharacterAdded:Connect(function(NewCharacter)
		if Toggles.PlayerESPToggle.Value then
			Functions.AddESP({ Object = NewCharacter, Text = Player.Name, Color = Options.PlayerESPColor.Value })
		end
	end)
	local DeadConn = Player:GetAttributeChangedSignal("Alive"):Connect(function()
		if Player:GetAttribute("Alive") ~= true and Player.Character then
			Functions.RemoveESP(Player.Character)
		end
	end)
	table.insert(Connections, CharConn)
	table.insert(Connections, DeadConn)
	Player.Destroying:Once(function()
		CharConn:Disconnect()
		DeadConn:Disconnect()
	end)
end)

local PromptsToFire = {}
local PromptCooldown = {}

Functions.FirePrompt      = Abysall.Environment.fireproximityprompt
Functions.ForceFirePrompt = Abysall.Environment.fireproximityprompt

if not Functions.FirePrompt then
	Functions.FirePrompt = function(Prompt)
		if not Prompt:IsA("ProximityPrompt") or PromptCooldown[Prompt] or table.find(PromptsToFire, Prompt) or not Camera then return end
		table.insert(PromptsToFire, Prompt)
	end
	Functions.ForceFirePrompt = Functions.FirePrompt

	task.spawn(function()
		while task.wait() do
			local Prompt = table.remove(PromptsToFire, 1)
			if not Prompt then continue end
			PromptCooldown[Prompt] = true

			local OldDist   = Prompt.MaxActivationDistance
			local OldEnable = Prompt.Enabled
			local OldParent = Prompt.Parent
			local OldHold   = Prompt.HoldDuration
			local OldLOS    = Prompt.RequiresLineOfSight

			Prompt.MaxActivationDistance = 99999
			Prompt.Enabled = true
			Prompt.HoldDuration = 0
			Prompt.RequiresLineOfSight = false

			local TempPart = Instance.new("Part")
			TempPart.Parent = Services.Workspace
			TempPart.CanCollide = false TempPart.CanQuery = false TempPart.CanTouch = false
			TempPart.Anchored = true TempPart.Transparency = 1
			TempPart.Size = Vector3.new(0.001, 0.001, 0.001)
			TempPart.Position = Camera.CFrame:ToWorldSpace(CFrame.new(0, 0, -0.1)).Position

			if not Prompt or not OldParent then
				TempPart:Destroy()
				PromptCooldown[Prompt] = nil
				continue
			end

			pcall(function() Prompt.Parent = TempPart end)

			local Shown, Fired = false, false

			local ShownConn = Services.ProximityPromptService.PromptShown:Connect(function(P)
				if P == Prompt then Shown = true end
			end)
			local FiredConn = Prompt.Triggered:Connect(function() Fired = true end)

			local T1 = 0
			while not Shown and T1 < 5 do T1 += 1 task.wait() end

			local T2 = 0
			while not Fired and T2 < 5 do
				Prompt:InputHoldBegin()
				Prompt:InputHoldEnd()
				T2 += 1 task.wait()
			end

			Prompt.MaxActivationDistance = OldDist
			Prompt.Enabled = OldEnable
			Prompt.HoldDuration = OldHold
			Prompt.RequiresLineOfSight = OldLOS
			pcall(function() Prompt.Parent = OldParent end)
			task.wait()
			PromptCooldown[Prompt] = nil
			TempPart:Destroy()
			ShownConn:Disconnect()
			FiredConn:Disconnect()
		end
	end)
end

local AutoInteractBlacklist = {
	HidePrompt=true, RiftPrompt=true, StarRiftPrompt=true, InteractPrompt=true, ClimbPrompt=true,
	DonatePrompt=true, DialoguePrompt=true, RevivePrompt=true, EnterPrompt=true, AnimatePrompt=true,
	ToolEventPrompt=true, Prompt=true, PropPrompt=true
}

local TriggerDebounce = false

local function GetHidingSpotModel(Prompt)
	if not Prompt or not Prompt.Parent then return false end
	local Model = Prompt.Parent
	while Model and not Model:IsA("Model") do
		Model = Model.Parent
	end
	if not Model then return nil end

	local Name = string.lower(Model.Name)
	if not string.find(Name, "hidingspot") and not string.find(Name, "hiding_spot") then
		return nil
	end
	return Model
end

local function HasHidePrompt(Model)
	return Model and (Model:FindFirstChild("HidePrompt") or Model:FindFirstChild("HidingPrompt")) ~= nil
end

local function IsHidingSpotPrompt(Prompt)
	if not Prompt or not Prompt.Parent then return false end
	if Prompt.Name ~= "HidePrompt" and Prompt.Name ~= "HidingPrompt" then return false end
	return HasHidePrompt(GetHidingSpotModel(Prompt))
end

Functions.TriggerPrompt = function(Prompt)
	if not Prompt or not Prompt.Parent then return end
	if Character:GetAttribute("Hiding") == true then return end
	local HidingSpot = GetHidingSpotModel(Prompt)
	if HidingSpot and Prompt.Name ~= "InteractPrompt" then return end
	local IsHidingSpotInteractPrompt = HidingSpot and Prompt.Name == "InteractPrompt"
	if AutoInteractBlacklist[Prompt.Name] and not IsHidingSpotPrompt(Prompt) and not IsHidingSpotInteractPrompt then return end
	if (Prompt.Name == "HidePrompt" or Prompt.Name == "HidingPrompt") and not IsHidingSpotPrompt(Prompt) then return end
	if (Prompt.Name == "HidePrompt" or Prompt.Name == "HidingPrompt" or IsHidingSpotPrompt(Prompt)) then
		if not Toggles.AutoClosetToggle.Value then return end
		local Entity = Functions.GetNearestEntity(true, Options.AutoClosetEntityList.Value)
		if not Entity then return end
		local EntityDistance = LocalPlayer:DistanceFromCharacter(Entity.PrimaryPart.Position)
		if EntityDistance > (EntityDistances[Entity.Name] or 150) then return end
	end
	if TriggerDebounce then return end

	local ParentItem = Functions.HasItem(Prompt.Parent.Name)
	if ParentItem and ParentItem:GetAttribute("Durability") and ParentItem:GetAttribute("DurabilityMax")
		and ParentItem:GetAttribute("Durability") >= ParentItem:GetAttribute("DurabilityMax")
	then return end

	local LockPromptNames = { UnlockPrompt=true, SkullPrompt=true, LockPrompt=true, ThingToEnable=true, FusesPrompt=true }
	local IsLockPrompt = LockPromptNames[Prompt.Name]
		or (Prompt.Parent and Prompt.Parent:GetAttribute("Locked") == true)
		or (Prompt.Parent and Prompt.Parent.Parent and Prompt.Parent.Parent.Name == "Locker_Small_Locked" and Prompt.Name == "ActivateEventPrompt")

	if IsLockPrompt then
		if Options.AutoInteractIgnoreList.Value["Locks"] then return end
		local KeyItems = { "Key","GeneratorFuse","KeyBackdoor","KeyElectrical","KeyIron","Lockpick","SkeletonKey","Shears","Multitool" }
		local OffhandKeyItems = { "Key","GeneratorFuse","KeyElectrical","KeyIron" }
		local HasKey = false
		for _, K in KeyItems do if Functions.HasItem(K, true) then HasKey = true break end end
		for _, K in OffhandKeyItems do if Functions.HasItem(K) then HasKey = true break end end
		if not HasKey then return end
	end

	if Prompt.Parent.Name == "CuttableVines" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Chest_Vine" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Cellar" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) then return end
	if Prompt.Parent.Name == "SkullLock" and not Functions.HasItem("SkeletonKey", true) then return end
	if Prompt.Parent.Name == "Lock1" and not Functions.HasItem("Lockpick", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Lock2" and not Functions.HasItem("Lockpick", true) and not Functions.HasItem("Multitool", true) then return end
	if Functions.HasItem("Shears", true) and IsLockPrompt and Prompt.Parent.Name ~= "CuttableVines" and Prompt.Parent.Name ~= "Chest_Vine" and Prompt.Parent.Name ~= "Cellar" then return end

	if Prompt.Parent.Name == "GlitchCube" and Options.AutoInteractIgnoreList.Value["Glitch Fragments"] then return end

	if (Prompt.Parent.Name == "KeyObtain" and (Functions.HasItem("Key") or Functions.HasItem("KeyBackdoor")))
		or (Prompt.Parent.Name == "ElectricalKeyObtain" and Functions.HasItem("KeyElectrical"))
	then return end

	if Prompt:IsDescendantOf(Drops) and Options.AutoInteractIgnoreList.Value["Dropped Items"] then return end
	if Prompt.Parent.Name == "TrackLever" then return end
	if Prompt.Name == "ActivateEventPrompt" and (Prompt.ActionText == "Close"
		or Prompt.Parent.Name == "ElevatorBreaker"
		or (Prompt.Parent.Parent and Prompt.Parent.Parent.Name == "IndustrialGate"))
	then return end
	if Prompt.Name == "ActivateEventPrompt" and (Prompt.Parent.Name == "Padlock" or Prompt.Parent.Name == "MinesAnchor") then return end
	if Prompt.Parent.Name == "LeverForGate" and Prompt:GetAttribute("Interactions") then return end
	if Prompt.Parent.Parent and (Prompt.Parent.Parent.Name == "DoorFake" or Prompt.Parent.Parent.Name == "FakeDoor") then return end
	if Prompt.Parent:GetAttribute("JeffShop") and Options.AutoInteractIgnoreList.Value["Jeff Items"] then return end
	if Prompt:GetAttribute("AutoInteractIgnore") then return end
	if Prompt.Name == "PushPrompt" and Options.AutoInteractIgnoreList.Value["Minecarts"] then return end
	if (Prompt.Parent.Name == "GoldPile" or Prompt.Parent.Name == "StardustPickup") and Options.AutoInteractIgnoreList.Value["Currency"] then return end

	if Prompt.Parent.Name == "Bandage" then
		local BPack = Functions.HasItem("BandagePack")
		if Humanoid.Health >= Humanoid.MaxHealth and not BPack then return end
		if BPack and BPack:GetAttribute("Durability") >= BPack:GetAttribute("DurabilityMax") then return end
	end

	if Prompt.Parent.Name == "Battery" then
		local Tool = Character:FindFirstChildOfClass("Tool")
		local BPack = Functions.HasItem("BatteryPack")
		if not Tool and not BPack then return end
		if Tool and Tool:GetAttribute("LightSource") then
			if Tool:GetAttribute("Durability") and Tool:GetAttribute("DurabilityMax")
				and Tool:GetAttribute("Durability") > Tool:GetAttribute("DurabilityMax")
			then return end
		elseif not BPack then
			return
		end
		if BPack and BPack:GetAttribute("Durability") >= BPack:GetAttribute("DurabilityMax") then return end
	end

	if Prompt.Name == "HerbPrompt" then
		local Effects = Globals.MainUI.MainFrame.Healthbar:FindFirstChild("Effects")
		if Effects and Effects.HerbGreenEffect.Visible then return end
	end

	if (Prompt.Parent.Name == "LibraryHintPaper" or Prompt.Parent.Name == "PickupItem") and (Functions.HasItem("LibraryHintPaper") or Functions.HasItem("LibraryHintPaperHard")) then return end
	if Prompt.Parent.Name == "AlarmClock" and Functions.HasItem("AlarmClock") then return end
	if Prompt.Parent.Name == "KeyObtainFake" or Prompt.Parent.Name == "TithingPlate" then return end
	if Prompt.Parent.Name == "StarBottle" then return end
    -- archives
	if Prompt.parent.Name == "ArchivesStorageBox" then return end
	if Prompt.Parent.Name == "Briefcase" then return end
	if Prompt.Name == "SinkPrompt" or Prompt.Parent.Name == "Faucet" then return end
	if Prompt.Parent.Name == "PaperPlanePickup" or Prompt.Parent.Name == "PaperPlane" then return end
	if Prompt.Name == "ManualOpenPrompt" or Prompt.Name == "EntryPrompt" then return end
	if Prompt.Parent.Parent.Name == "ArchivesLargePrinter" then return end
	if Prompt.Name == "TrashcanPrompt" then return end
	if Prompt.Parent.Name == "Keyboard" then return end
	do
		local Node = Prompt.Parent
		while Node and Node ~= workspace do
			if Node.Name == "ArchivesOfficeChair" or Node.Name == "ShoppingCart" or Node.Name == "OneWayTwoHandDoor" then return end
			Node = Node.Parent
		end
	end
	if Prompt.Name == "CartPrompt" then return end
	if Prompt.Parent.Name == "ArchivesTerminal" then return end
	if Prompt.Name == "VendorPrompt" then return end
    if Prompt.Parent.Name == "SeatPart" or Prompt.Name == "SeatPrompt" then return end


	-- Stairwell
	if Prompt.Parent.Parent.Parent.Parent.Name == "CandyVault" then return end
	if Prompt.Parent.Name == "StairwellScrapper" then return end
	if Prompt.Name == "PortraitDupePrompt" or Prompt.Parent.Name == "MirrorTool" then return end
	if Prompt.Name == "LaptopPrompt" or Prompt.Parent.Name == "SecretLaptop" then return end
	if Prompt.Parent.Name == "StairwellFireAlarm" or Prompt.Parent.Parent.Name == "StairwellFireAlarm" then return end
	if Prompt.Parent.name == "CobblerFriendly" then return end
	if Prompt.Parent.Name == "StairwellTerminal" then return end
	if Prompt.Parent.Parent.Name == "MeldChord" then return end

	Functions.FirePrompt(Prompt)
	TriggerDebounce = true
	if Floor == "OldHotel" then task.wait() end
	TriggerDebounce = false
end

Globals.LastAutoInteractFire = tick()
Connections.AutoInteract = Services.RunService.Heartbeat:Connect(function()
	local Active = Toggles.AutoInteractToggle.Value or Options.AutoInteractKeybind:GetState()
    if not Active then return end
    if tick() - Globals.LastAutoInteractFire < 1/60 then return end

	for _, Prompt in Objects.Prompts do
        if Prompt:GetAttribute("ParentRoom") and tonumber(Prompt:GetAttribute("ParentRoom")) ~= tonumber(LocalPlayer:GetAttribute("CurrentRoom")) then continue end

		if Prompt.Parent and (Prompt.Parent:IsA("BasePart") or Prompt.Parent:IsA("Model")) then
			local Distance
			if Prompt.Parent:IsA("BasePart") then
				Distance = LocalPlayer:DistanceFromCharacter(Prompt.Parent.Position)
			else
				Distance = LocalPlayer:DistanceFromCharacter(Prompt.Parent:GetPivot().Position)
			end
			if Distance <= Prompt.MaxActivationDistance and Prompt.Enabled or Distance <= Prompt.MaxActivationDistance and Prompt.Name == "LongPushPrompt" or Distance <= Prompt.MaxActivationDistance and Prompt.Name == "BigPropPrompt" then
				task.spawn(Functions.TriggerPrompt, Prompt)
			end
		end
	end
    Globals.LastAutoInteractFire = tick()
end)

Connections.InfiniteItemsHandler = Services.ProximityPromptService.PromptTriggered:Connect(function(Object)
	if not Object:GetAttribute("FakePrompt") then return end

	local ToolNames = { "Lockpick","Shears","SkeletonKey","Key","GeneratorFuse","KeyElectrical","KeyBackdoor","KeyIron", "Multitool" }
	local AnimateToolNames = { "Lockpick","Shears","SkeletonKey","Key","KeyElectrical","KeyBackdoor","KeyIron", "Multitool" }
	local Tool
	for _, N in ToolNames do Tool = Character:FindFirstChild(N) if Tool then break end end

	local Prompt = Object
	local LockPromptNames = { UnlockPrompt=true, SkullPrompt=true, LockPrompt=true, ThingToEnable=true, FusesPrompt=true }
	local IsLockPrompt = LockPromptNames[Object.Name]
		or (Object.Parent and Object.Parent:GetAttribute("Locked") == true)
		or (Object.Parent and Object.Parent.Parent and Object.Parent.Parent.Name == "Locker_Small_Locked" and Object.Name == "ActivateEventPrompt")
	if IsLockPrompt then
		if Options.AutoInteractIgnoreList.Value["Locks"] then return end
		local KeyItems = { "Key","GeneratorFuse","KeyBackdoor","KeyElectrical","KeyIron","Lockpick","SkeletonKey","Shears","Multitool" }
		local OffhandKeyItems = { "Key","GeneratorFuse","KeyElectrical","KeyIron" }
		local HasKey = false
		for _, K in KeyItems do if Functions.HasItem(K, true) then HasKey = true break end end
		for _, K in OffhandKeyItems do if Functions.HasItem(K) then HasKey = true break end end
		if not HasKey then return end
	end

	if Prompt.Parent.Name == "CuttableVines" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Chest_Vine" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Cellar" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) then return end
	if Prompt.Parent.Name == "SkullLock" and not Functions.HasItem("SkeletonKey", true) then return end
	if Prompt.Parent.Name == "Lock1" and not Functions.HasItem("Lockpick", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Lock2" and not Functions.HasItem("Lockpick", true) and not Functions.HasItem("Multitool", true) then return end
	if Functions.HasItem("Shears", true) and IsLockPrompt and Prompt.Parent.Name ~= "CuttableVines" and Prompt.Parent.Name ~= "Chest_Vine" and Prompt.Parent.Name ~= "Cellar" then return end

	if Tool and table.find(AnimateToolNames, Tool.Name) and Globals.UseAnimation and Globals.UseAnimationBreak then
		Globals.UseAnimation:Stop()
		Globals.UseAnimationBreak:Stop()
		Globals.UseAnimationBreak:Play()
		if Tool.Name == "Shears" then
			-- was a blocking WaitForChild: it delayed the drop below and the use got consumed first
			task.spawn(function()
				local Handle = Tool:WaitForChild("Handle", 2)
				local Sound = Handle and Handle:WaitForChild("sound_prompt", 2)
				if Sound then Sound:Play() end
			end)
		end
	end

	-- identify the held item and drop it in the same step
	local AnyTool = Character:FindFirstChildOfClass("Tool")
	local ToolData = AnyTool and ItemNames[AnyTool.Name]
	local DropsFolder = Drops or workspace:FindFirstChild("Drops")
	if AnyTool and ToolData and DropsFolder and Toggles.InfiniteItemsToggle.Value and Options.InfiniteItemsList.Value[ToolData] then
		local DroppedName = AnyTool.Name
		local RealPrompt = FakePrompts[Object]
		local Handled = false
		local DropConnection
		-- listen first, then drop, so the new drop can't be missed
		DropConnection = DropsFolder.ChildAdded:Connect(function(NewTool)
			if Handled or NewTool.Name ~= DroppedName then return end
			Handled = true
			DropConnection:Disconnect()
			task.spawn(function()
				local ModulePrompt = NewTool:WaitForChild("ModulePrompt", 3)
				if ModulePrompt then Functions.FirePrompt(ModulePrompt) end
				if RealPrompt and RealPrompt.Parent then Functions.FirePrompt(RealPrompt) end
			end)
		end)
		task.delay(5, function() if DropConnection.Connected then DropConnection:Disconnect() end end)
		if DroppedName == "Shears" then
			local EndConnection
			EndConnection = Character.ChildAdded:Connect(function(NewTool)
				if NewTool.Name ~= "Shears" then return end
				EndConnection:Disconnect()
				task.spawn(function()
					local Handle = NewTool:WaitForChild("Handle", 2)
					local Sound = Handle and Handle:WaitForChild("sound_promptend", 2)
					if Sound then Sound:Play() end
				end)
			end)
			task.delay(5, function() if EndConnection.Connected then EndConnection:Disconnect() end end)
		end
		RemotesFolder.DropItem:FireServer(AnyTool)
	else
		local RealPrompt = FakePrompts[Object]
		if RealPrompt then Functions.FirePrompt(RealPrompt) end
	end
end)

Connections.FloorReplicatedHandler = FloorReplicated.DescendantAdded:Connect(function(Object)
	if Object.Name == "GlitchScreech" then
		Modules.GlitchScreech = Object
		if Toggles.RemoveScreech.Value then Object.Name = "GlitchScreech_Disabled" end
	end
	if Object.Name:find("Jumpscare") and Object:IsA("ModuleScript")
		and not Object.Name:find("Eyestalk") and not Object.Name:find("Groundskeeper") and not Object.Name:find("Monument")
	then
		Object:SetAttribute("OriginalName", Object.Name)
		if Toggles.DisableEntityJumpscares.Value then Object.Name = Object.Name .. "_Disabled" end
		table.insert(Objects.JumpscareModules, Object)
	end
end)

if FloorReplicated:FindFirstChild("DigitalTimer") then
	Connections.HasteTimerConnection = FloorReplicated.DigitalTimer:GetPropertyChangedSignal("Value"):Connect(function()
		if Toggles.NotifyHasteTime.Value then Functions.Caption(Functions.GetHasteTime(), true) end
	end)
end

Connections.FogHandler = Services.Lighting:GetPropertyChangedSignal("FogEnd"):Connect(function()
	if Services.Lighting.FogEnd ~= 10000000 then
		Globals.OldFog = Services.Lighting.FogEnd
	end
	if Toggles.RemoveCameraFog.Value then
		Services.Lighting.FogEnd = 10000000
	end
end)

Connections.FogHandler2 = Services.Lighting.DescendantAdded:Connect(function(Object)
	if not Object:IsA("Atmosphere") then return end
	Object:SetAttribute("Density_Old", Object.Density)
	if Toggles.RemoveCameraFog.Value then Object.Density = 0 end

	local AtmoConn2 = Object:GetPropertyChangedSignal("Density"):Connect(function()
		if Object.Density ~= 0 then Object:SetAttribute("Density_Old", Object.Density) end
		if Toggles.RemoveCameraFog.Value then Object.Density = 0 end
	end)
	Object.Destroying:Once(function() AtmoConn2:Disconnect() end)
	table.insert(Connections, AtmoConn2)
	table.insert(Globals.FogInstances, Object)
end)

local RusherAliases = { Rush=true, Bash=true, Scribbles=true, DronesStampede=true, Ambush=true, Eyes=true, Lookman=true, Blitz=true, ["A-60"]=true, ["A-120"]=true, AR0xMBUSH=true, ["RNIUSHCG=="]=true, ["Custom Entity"]=true }

local function HandleEntitySpawn(Entity)
	if not Entity or typeof(Entity) ~= "Instance" then return end

	local Model = Entity
	if Entity:IsA("Humanoid") then
		Model = Entity.Parent
	end
	if not Model or not Model:IsA("Model") then return end

	local EntityData = Entities[Model.Name]
	if not EntityData then return end
	if Model:GetAttribute("Abysall_EntityHandled") then return end
	Model:SetAttribute("Abysall_EntityHandled", true)

	while not Model.PrimaryPart do
		for _, Child in Model:GetChildren() do
			if Child:IsA("BasePart") then Model.PrimaryPart = Child end
		end
		if not Model.PrimaryPart then task.wait() end
	end
	task.wait(0.1)

	if not Model.PrimaryPart or LocalPlayer:DistanceFromCharacter(Model.PrimaryPart.Position) >= 10000 then return end

	local Alias = EntityData.Alias
	local RealAlias = Alias
	if Options.EntityList.Value[Alias] and Toggles.NotifyEntities.Value then
		local NotifyTitle = EntityData.NotifyMessage.Title
		local NotifyBody  = EntityData.NotifyMessage.Body
		local NotifyImage = EntityIcons[Model.Name]

		if Model.Name == "RushMoving" and Model.PrimaryPart.Name ~= "RushNew" then
			NotifyTitle = NotifyTitle:gsub("Rush", Model.PrimaryPart.Name)
			NotifyImage = Model.PrimaryPart:WaitForChild("Attachment").ParticleEmitter.Texture
			Alias = Model.PrimaryPart.Name
		end

		Functions.Notify({ Title = NotifyTitle, Body = NotifyBody, Image = NotifyImage, Time = Toggles.NotifyKeepNotifications.Value and Model or nil })

		if Toggles.EntityChatToggle.Value then
			Functions.SendChat(Alias .. " " .. Options.EntityChatMessage.Value)
		end
	end

	if Model.Name ~= "GloombatSwarm" then
		if Toggles.EntityESPToggle.Value and Options.EntityESPOptions.Value[RealAlias] then
			if Model.Name == "MonumentEntity" then
				Functions.AddESP({ Object = Model.Top, Text = Alias, Color = Options.EntityESPColor.Value })
			else
				Functions.AddESP({ Object = Model, Text = Alias, Color = Options.EntityESPColor.Value })
			end
		end
		table.insert(Objects.Entities, Model)
	end

	if RusherAliases[EntityData.Alias] then
		Instance.new("Humanoid", Model).Name = "HighlightHumanoid"
		local Root = Model.PrimaryPart
		if Root then Root.Transparency = 0.999 Root.Material = Enum.Material.Plastic end
	end

	if Model.Name == "Lookman" then
		CurrentRooms.ChildAdded:Wait()
		task.wait(10)
		Model:Destroy()
	end
end

Connections.EntityHandler = Services.Workspace.ChildAdded:Connect(HandleEntitySpawn)
Connections.EntityDescendantHandler = Services.Workspace.DescendantAdded:Connect(function(Descendant)
	local EntityModel = Descendant:IsA("Humanoid") and Descendant.Parent or Descendant
	if EntityModel and EntityModel:IsA("Model") and Entities[EntityModel.Name] then
		task.defer(function()
			HandleEntitySpawn(Descendant)
		end)
	end
end)

local LastClean = tick()
Connections.Cleaner = Services.RunService.Heartbeat:Connect(function()
	if tick() - LastClean <= 0.5 then return end
	LastClean = tick()

	for ArrayName, Array in Objects do
		local I = #Array
		while I >= 1 do
			local Object = Array[I]
			if Object == nil or not Object:IsDescendantOf(Services.Workspace) then
				table.remove(Array, I)
				local Conn = ESPConnections[Object]
				if Conn then
					Conn:Disconnect()
					ESPConnections[Object] = nil
					local Pos = table.find(Connections, Conn)
					if Pos then table.remove(Connections, Pos) end
				end
			end
			I -= 1
		end
	end
end)

local LastPromptFix = tick()
Connections.PromptFixer = Services.RunService.Heartbeat:Connect(function()
	if tick() - LastPromptFix <= 0.5 then return end
	LastPromptFix = tick()
	for _, Prompt in Objects.Prompts do
		if Prompt:HasTag("DisableWhenEnabledOnClient") then
			Prompt:RemoveTag("DisableWhenEnabledOnClient")
		end
	end
end)

if LocalPlayer.Character then
	task.spawn(function() Functions.HandleCharacter(LocalPlayer.Character) end)
end

Connections.CharacterAddedHandler = LocalPlayer.CharacterAdded:Connect(function(NewCharacter)
	if Connections.MainHandler then
		Connections.MainHandler:Disconnect()
		Connections.MainHandler = nil
	end
	task.wait(0.5)
	Functions.HandleCharacter(NewCharacter)
end)

Library:OnUnload(function()
	shared.Hastelepasta = false
	StopTimeShower(true)
	if OrbitDroppedItemsConnection then
		OrbitDroppedItemsConnection:Disconnect()
		OrbitDroppedItemsConnection = nil
	end
	for Key, Connection in Connections do
		if type(Key) == "string" then
			pcall(function() Connection:Disconnect() end)
		else
			pcall(function() Key:Disconnect() end)
			pcall(function() Connection:Disconnect() end)
		end
	end

	for _, Object in Objects.Entities do
		if Object.Name == "Snare" or Object.Name == "GiggleCeiling" then
			local Hitbox = Object:FindFirstChild("Hitbox")
			if Hitbox then Hitbox.CanTouch = true end
		end
		if Object.Name == "GloomPile" then
			for _, Part in Object:GetDescendants() do
				if Part:IsA("BasePart") then Part.CanTouch = true end
			end
		end
		if Object.Name == "FakeDoor" or Object.Name == "DoorFake" then
			local Hidden = Object:FindFirstChild("Hidden")
			if Hidden then Hidden.CanTouch = true end
			local Lock = Object:FindFirstChild("Lock")
			if Lock and Lock:FindFirstChild("UnlockPrompt") then Lock.UnlockPrompt.Enabled = true end
		end
		if Object.Name == "SideroomSpace" then
			local Coll = Object:FindFirstChild("Collision")
			if Coll then Coll.CanCollide = false Coll.CanTouch = true end
		end
	end

	for _, Object in Objects.SeekBridges do Object:Destroy() end

	for _, Fog in Globals.FogInstances do
		Fog.Density = Fog:GetAttribute("Density_Old")
	end
	Services.Lighting.FogEnd = Globals.OldFog

	local Vignette = Globals.MainUI:FindFirstChild("HideVignette") or Globals.MainUI.MainFrame:FindFirstChild("HideVignette")
	if Vignette then Vignette.Image = "rbxassetid://6100076320" end

	local ModuleRestores = {
		Screech = "Screech", Glitch = "Glitch", Shade = "Shade",
		SpiderJumpscare = "SpiderJumpscare", A90 = "A90", Dread = "Dread", Void = "Void"
	}
	for Key, OriginalName in ModuleRestores do
		if Modules[Key] then Modules[Key].Name = OriginalName end
	end

	FakeEvents.Screech:Destroy()
	FakeEvents.Screech_Real.Parent = RemotesFolder
	FakeEvents.Shade:Destroy()
	FakeEvents.Shade_Real.Parent = RemotesFolder

	if FakeEvents.A90_Real then
		FakeEvents.A90:Destroy()
		FakeEvents.A90_Real.Parent = RemotesFolder
	end
	if FakeEvents.Surge_Real then
		FakeEvents.Surge:Destroy()
		FakeEvents.Surge_Real.Parent = RemotesFolder
	end

	Globals.SeekNodesFolder:Destroy()
	Globals.RoomsNodesFolder:Destroy()
	Globals.ManipulateBody:Destroy()

	local OldAmbient = CurrentRooms:FindFirstChild(tostring(LocalPlayer:GetAttribute("CurrentRoom"))):GetAttribute("Ambient")
	Services.TweenService:Create(Services.Lighting, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), { Ambient = OldAmbient }):Play()

	for _, Prompt in Objects.Prompts do
		if FakePrompts[Prompt] then
			FakePrompts[Prompt].Parent = Prompt.Parent
			Prompt:Destroy()
		end
		if Prompt.Parent then
			Prompt.HoldDuration = Prompt:GetAttribute("HoldDuration_Old") or Prompt.HoldDuration
			Prompt.RequiresLineOfSight = Prompt:GetAttribute("RequiresLineOfSight_Old") or Prompt.RequiresLineOfSight
			Prompt.MaxActivationDistance = Prompt:GetAttribute("MaxActivationDistance_Old") or Prompt.MaxActivationDistance
		end
	end

	Character:SetAttribute("CanJump",  OldJump)
	Character:SetAttribute("CanSlide", OldSlide)

	for _, Object in Services.Workspace:GetDescendants() do
		task.spawn(function() Functions.RemoveESP(Object) end)
	end

	Humanoid.WalkSpeed  = Functions.GetCurrentSpeed()
	Humanoid.JumpPower  = 5
	Humanoid.HipHeight  = 2.367

	local BaseY = 0.18
	Collision.Position          = RootPart.Position + Vector3.new(0, BaseY, 0)
	CollisionPart.Position      = RootPart.Position + Vector3.new(0, BaseY, 0)
	CollisionPartClone.Position = RootPart.Position + Vector3.new(0, BaseY, 0)

	if Character:FindFirstChild("LowerTorso") and Character.LowerTorso:FindFirstChild("Root") then
		Character.LowerTorso.Root.C1 = Globals.OriginalC1
	end
	if Collision:FindFirstChild("CollisionCrouch") then
		Collision.CollisionCrouch.Position = RootPart.Position + Vector3.new(0, -0.982, 0)
	end

	CollisionClone:Destroy()
	CollisionPartClone:Destroy()
	Abysall.ESPLibrary:Unload()

	if Main_Game then
		Main_Game.fovtarget   = 70
		Main_Game.spring.Speed = 8
		Main_Game.tooloffset   = Vector3.zero
	end

	if Globals.OriginalGetMoveVector then 
		local Controls = require(LocalPlayer.PlayerScripts.PlayerModule):GetControls()
		Controls.GetMoveVector = Globals.OriginalGetMoveVector
	end

	getgenv().Abysall = nil
	shared.Hastelepasta = false
end)



-- ===== Anti Lag =====
do
    local Lighting = Services.Lighting
    local function Weak() return setmetatable({}, { __mode = "k" }) end
    local Saved = { Particles = Weak(), Shadows = Weak(), Effects = Weak(), Fidelity = Weak(), Reflect = Weak() }
    local Connection
    local LightingSaved, TerrainSaved
    local function Hard() return Toggles.AntiLagHard ~= nil and Toggles.AntiLagHard.Value end

    local function Optimize(Object)
        if Object:IsA("ParticleEmitter") or Object:IsA("Smoke") or Object:IsA("Fire") or Object:IsA("Sparkles") or Object:IsA("Trail")
            or (Hard() and Object:IsA("Beam")) then
            if Saved.Particles[Object] == nil then Saved.Particles[Object] = Object.Enabled end
            Object.Enabled = false
        elseif Object:IsA("BasePart") then
            if Saved.Shadows[Object] == nil then Saved.Shadows[Object] = Object.CastShadow end
            Object.CastShadow = false
            if Hard() then
                if Saved.Reflect[Object] == nil then Saved.Reflect[Object] = Object.Reflectance end
                Object.Reflectance = 0
                if Object:IsA("MeshPart") then
                    if Saved.Fidelity[Object] == nil then Saved.Fidelity[Object] = Object.RenderFidelity end
                    Object.RenderFidelity = Enum.RenderFidelity.Performance
                end
            end
        elseif Object:IsA("BloomEffect") or Object:IsA("BlurEffect") or Object:IsA("SunRaysEffect") or Object:IsA("DepthOfFieldEffect") then
            if Saved.Effects[Object] == nil then Saved.Effects[Object] = Object.Enabled end
            Object.Enabled = false
        end
    end

    -- engine flags (executor must support setfflag; many only take effect after a rejoin)
    local FlagList = {
        FIntRenderShadowIntensity = "0",
        FIntFRMMinGrassDistance = "0", FIntFRMMaxGrassDistance = "0", FIntRenderGrassDetailStrands = "0",
        DFIntTextureQualityOverride = "1", DFFlagTextureQualityOverrideEnabled = "True",
        DFIntCSGLevelOfDetailSwitchingDistance = "0", DFIntCSGLevelOfDetailSwitchingDistanceL12 = "0",
        DFIntCSGLevelOfDetailSwitchingDistanceL23 = "0", DFIntCSGLevelOfDetailSwitchingDistanceL34 = "0",
        DFIntDebugFRMQualityLevelOverride = "1",
    }
    local FlagsOld = {}
    local function ApplyFlags(On)
        local Set, Get = getgenv().setfflag, getgenv().getfflag
        if not Set then return 0, 0 end
        local Done, Total = 0, 0
        for Name, Value in FlagList do
            Total += 1
            if On then
                if Get and FlagsOld[Name] == nil then
                    local Ok, Old = pcall(Get, Name)
                    if Ok and Old ~= nil and Old ~= "" then FlagsOld[Name] = Old end
                end
                if pcall(Set, Name, Value) then Done += 1 end
            elseif FlagsOld[Name] ~= nil then
                pcall(Set, Name, FlagsOld[Name])
                FlagsOld[Name] = nil
            end
        end
        return Done, Total
    end

    Groupboxes.Self_Misc:AddToggle("AntiLag", {
        Text = "Anti Lag", Default = false,
        Tooltip = "Lowers graphics quality, disables shadows, particles and blur/bloom effects to raise FPS."
    })
    Groupboxes.Self_Misc:AddToggle("AntiLagHard", {
        Text = "Anti Lag: Hard Mode", Default = true,
        Tooltip = "Also: no reflections, lowest mesh detail, flat lighting, no terrain water waves / decoration, no beams."
    })
    Groupboxes.Self_Misc:AddToggle("AntiLagFlags", {
        Text = "Anti Lag: Engine Flags", Default = true,
        Tooltip = "Tries to set engine fast flags (grass, texture quality, mesh LOD, shadows). Needs setfflag; some only apply after a rejoin."
    })

    local function Apply()
        pcall(function()
            Saved.Quality = Saved.Quality or settings().Rendering.QualityLevel
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
        if not LightingSaved then
            LightingSaved = {
                GlobalShadows = Lighting.GlobalShadows, ShadowSoftness = Lighting.ShadowSoftness,
                Diffuse = Lighting.EnvironmentDiffuseScale, Specular = Lighting.EnvironmentSpecularScale,
            }
        end
        Lighting.GlobalShadows = false
        if Hard() then
            pcall(function()
                Lighting.ShadowSoftness = 0
                Lighting.EnvironmentDiffuseScale = 0
                Lighting.EnvironmentSpecularScale = 0
            end)
        end
        pcall(function()
            local Terrain = workspace.Terrain
            if not TerrainSaved then
                TerrainSaved = { Decoration = Terrain.Decoration, WaveSize = Terrain.WaterWaveSize, WaveSpeed = Terrain.WaterWaveSpeed, Reflectance = Terrain.WaterReflectance }
            end
            Terrain.Decoration = false
            if Hard() then
                Terrain.WaterWaveSize = 0
                Terrain.WaterWaveSpeed = 0
                Terrain.WaterReflectance = 0
            end
        end)
        if Toggles.AntiLagFlags.Value then
            local Done, Total = ApplyFlags(true)
            Functions.Notify({ Title = "Anti Lag", Body = Done .. "/" .. Total .. " engine flags set" .. (Done == 0 and " (setfflag missing or blocked)" or ""), Time = 4 })
        end
    end

    Toggles.AntiLag:OnChanged(function(Value)
        if Connection then Connection:Disconnect() Connection = nil end

        if Value then
            Apply()
            task.spawn(function()
                local Count = 0
                for _, Object in workspace:GetDescendants() do
                    if not Toggles.AntiLag.Value then return end
                    Optimize(Object)
                    Count += 1
                    if Count % 400 == 0 then task.wait() end
                end
                for _, Object in Lighting:GetDescendants() do Optimize(Object) end
            end)
            Connection = workspace.DescendantAdded:Connect(Optimize)
        else
            pcall(function() if Saved.Quality then settings().Rendering.QualityLevel = Saved.Quality end end)
            Saved.Quality = nil
            if LightingSaved then
                pcall(function()
                    Lighting.GlobalShadows = LightingSaved.GlobalShadows
                    Lighting.ShadowSoftness = LightingSaved.ShadowSoftness
                    Lighting.EnvironmentDiffuseScale = LightingSaved.Diffuse
                    Lighting.EnvironmentSpecularScale = LightingSaved.Specular
                end)
                LightingSaved = nil
            end
            if TerrainSaved then
                pcall(function()
                    local Terrain = workspace.Terrain
                    Terrain.Decoration = TerrainSaved.Decoration
                    Terrain.WaterWaveSize = TerrainSaved.WaveSize
                    Terrain.WaterWaveSpeed = TerrainSaved.WaveSpeed
                    Terrain.WaterReflectance = TerrainSaved.Reflectance
                end)
                TerrainSaved = nil
            end
            ApplyFlags(false)
            for Object, Value in Saved.Particles do pcall(function() Object.Enabled = Value end) end
            for Object, Value in Saved.Shadows do pcall(function() Object.CastShadow = Value end) end
            for Object, Value in Saved.Effects do pcall(function() Object.Enabled = Value end) end
            for Object, Value in Saved.Fidelity do pcall(function() Object.RenderFidelity = Value end) end
            for Object, Value in Saved.Reflect do pcall(function() Object.Reflectance = Value end) end
        end
    end)
end

-- ===== Players: friend orbit, give item, rare pickup alerts =====
do
    local Players = Services.Players
    local Social = { ToolMap = {} }

    Groupboxes.Players = Tabs.General:AddRightGroupbox("Players")

    local function OtherPlayers()
        local List = {}
        for _, Player in Players:GetPlayers() do
            if Player ~= LocalPlayer then List[#List + 1] = Player.Name end
        end
        table.sort(List)
        return List
    end

    Groupboxes.Players:AddDropdown("SocialTarget", {
        Text = "Friend", Values = OtherPlayers(), Default = nil, AllowNull = true,
        Tooltip = "Player used by Orbit Items, FPV Drone and Give Item."
    })
    local function RefreshPlayers()
        Options.SocialTarget:SetValues(OtherPlayers())
    end
    Connections.SocialPlayerAdded = Players.PlayerAdded:Connect(RefreshPlayers)
    Connections.SocialPlayerRemoving = Players.PlayerRemoving:Connect(function() task.defer(RefreshPlayers) end)

    local function GetFriendRoot()
        local Name = Options.SocialTarget.Value
        local Friend = Name and Players:FindFirstChild(Name)
        local Root = Friend and Friend.Character and Friend.Character:FindFirstChild("HumanoidRootPart")
        return Friend, Root
    end
    Boot.GetSocialTarget = GetFriendRoot

    -- orbit: existing "Orbit Dropped Items" loop, centred on the friend instead of you
    function Boot.OrbitRoot()
        if Toggles.OrbitFriend and Toggles.OrbitFriend.Value then
            local _, Root = GetFriendRoot()
            if Root then return Root end
        end
        return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    end

    Groupboxes.Players:AddToggle("OrbitFriend", {
        Text = "Orbit Items Around Friend", Default = false,
        Tooltip = "Dropped items orbit the selected friend (uses the Orbit Dropped Items sliders in Stairwell > Experimental)."
    })
    Toggles.OrbitFriend:OnChanged(function(Value)
        local _, FriendRoot = GetFriendRoot()
        if Value and not FriendRoot then
            Functions.Notify({ Title = "Pick a friend first", Body = "Orbit will use you until a friend is selected." })
        end
        if Value then Toggles.OrbitDroppedItems:SetValue(true) end
    end)

    -- give item
    Groupboxes.Players:AddDivider()
    Groupboxes.Players:AddDropdown("GiveItem", {
        Text = "Item To Give", Values = {}, Default = nil, AllowNull = true,
        Tooltip = "Items from your inventory. Press Refresh after picking something up."
    })
    local function RefreshTools()
        local Display, Map = {}, {}
        for _, Container in { LocalPlayer.Backpack, LocalPlayer.Character } do
            if Container then
                for _, Tool in Container:GetChildren() do
                    if Tool:IsA("Tool") then
                        local Label = ItemNames[Tool.Name] or Tool.Name
                        if not Map[Label] then Display[#Display + 1] = Label end
                        Map[Label] = Tool.Name
                    end
                end
            end
        end
        table.sort(Display)
        Social.ToolMap = Map
        Options.GiveItem:SetValues(Display)
    end
    Groupboxes.Players:AddButton({ Text = "Refresh Items", Func = RefreshTools })

    Groupboxes.Players:AddButton({
        Text = "Drop Item Next To Friend",
        Tooltip = "Drops the selected item and places it right next to the selected friend.",
        Func = function()
            local Friend, FriendRoot = GetFriendRoot()
            if not FriendRoot then Functions.Notify({ Title = "Pick a friend first" }) return end
            local ToolName = Options.GiveItem.Value and Social.ToolMap[Options.GiveItem.Value]
            local Tool = ToolName and Functions.HasItem(ToolName)
            if not Tool then Functions.Notify({ Title = "Item not found", Body = "Press Refresh Items." }) return end
            local DropsFolder = workspace:FindFirstChild("Drops")
            local Character = LocalPlayer.Character
            local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
            if not DropsFolder or not Humanoid then return end

            if Tool.Parent ~= Character then
                Humanoid:EquipTool(Tool)
                local Began = tick()
                while Tool.Parent ~= Character and tick() - Began < 1.5 do task.wait() end
            end

            local Placed = false
            local Connection
            Connection = DropsFolder.ChildAdded:Connect(function(NewItem)
                if Placed or NewItem.Name ~= ToolName then return end
                Placed = true
                Connection:Disconnect()
                task.spawn(function()
                    -- keep re-placing for a moment while the item settles
                    for _ = 1, 10 do
                        local Root = Friend.Character and Friend.Character:FindFirstChild("HumanoidRootPart")
                        if not Root or not NewItem.Parent then break end
                        local Target = Root.CFrame * CFrame.new(0, 0, -3)
                        if NewItem:IsA("Model") then NewItem:PivotTo(Target) else NewItem.CFrame = Target end
                        task.wait(0.1)
                    end
                end)
            end)
            task.delay(5, function() if Connection.Connected then Connection:Disconnect() end end)

            RemotesFolder.DropItem:FireServer(Tool)
            Functions.Notify({ Title = "Dropped " .. Options.GiveItem.Value, Body = "Next to " .. Friend.Name })
        end
    })

    -- rare pickup alerts
    Groupboxes.Players:AddDivider()
    local RareValues, Seen = {}, {}
    for _, Display in pairs(ItemNames) do
        if not Seen[Display] then Seen[Display] = true RareValues[#RareValues + 1] = Display end
    end
    table.sort(RareValues)
    Groupboxes.Players:AddDropdown("RareItems", {
        Text = "Rare Items", Values = RareValues, Multi = true, AllowNull = true, Default = nil
    })
    local DefaultRare = {}
    for _, Name in {
        "Crucifix", "Skeleton Key", "Donut", "Starlight Vial", "Starlight Bottle", "Starlight Barrel",
        "Moonlight Candle", "Moonlight Smoothie", "Rift Jar", "Holy Hand Grenade", "Golden Gun",
        "Big Shield Potion", "Lotus", "Glitch Fragment", "Multitool", "Compass",
    } do
        if Seen[Name] then DefaultRare[Name] = true end
    end
    Options.RareItems:SetValue(DefaultRare)

end

-- ===== Abyssal Massive Recode: experimental features =====
do
local function BuildAMR()
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local Env = getgenv()
    local Alive = true
    pcall(function() Library:OnUnload(function()
        Alive = false
        for _, Gui in GetHiddenContainer():GetChildren() do
            if Gui.Name == "AMRHotbar" or Gui.Name == "AMROverlay" or Gui.Name == "AMRHotbarSearch" then Gui:Destroy() end
        end
    end) end)

    local function New(Class, Props, Parent)
        local Object = Instance.new(Class)
        for Key, Value in Props do Object[Key] = Value end
        Object.Parent = Parent
        return Object
    end

    local function Round(Object, Radius)
        New("UICorner", { CornerRadius = UDim.new(0, Radius or 6) }, Object)
    end

    local function Copy(Text)
        local Fn = setclipboard or toclipboard or Env.setclipboard or Env.toclipboard
        if not Fn then return false end
        return (pcall(Fn, Text))
    end
    Boot.Copy = Copy

    local function Save(Path, Data)
        pcall(function()
            if Env.makefolder and Env.isfolder and not Env.isfolder("AMR") then Env.makefolder("AMR") end
            Env.writefile("AMR/" .. Path, HttpService:JSONEncode(Data))
        end)
    end

    local function Load(Path)
        local Ok, Result = pcall(function()
            if Env.isfile and Env.isfile("AMR/" .. Path) then
                return HttpService:JSONDecode(Env.readfile("AMR/" .. Path))
            end
            return nil
        end)
        if Ok then return Result end
        return nil
    end

    local function Clock(Seconds)
        local Minutes = math.floor(Seconds / 60)
        return string.format("%d:%04.1f", Minutes, Seconds - Minutes * 60)
    end

    local function FindTool(Display)
        for _, Container in { LocalPlayer:FindFirstChildOfClass("Backpack"), Character } do
            if Container then
                for _, Tool in Container:GetChildren() do
                    if Tool:IsA("Tool") and (Tool.Name == Display or ItemNames[Tool.Name] == Display) then
                        return Tool
                    end
                end
            end
        end
        return nil
    end

    -- groupboxes
    Groupboxes.General_Experimental = Tabs.General:AddRightGroupbox("Experimental")
    Groupboxes.Exploits_Experimental = Tabs.Exploits:AddRightGroupbox("Experimental")
    Groupboxes.Visuals_Experimental = Tabs.Visuals:AddRightGroupbox("Experimental")
    Groupboxes.Floors_Experimental = Tabs.Floors:AddRightGroupbox("Experimental")
    -- features spread over the tabs where they belong
    Groupboxes.Visuals_Arrows = Tabs.Visuals:AddLeftGroupbox("Arrows")
    Groupboxes.Visuals_Warnings = Tabs.Visuals:AddLeftGroupbox("Entity Warnings")
    Groupboxes.Visuals_HUD = Tabs.Visuals:AddLeftGroupbox("HUD")
    Groupboxes.General_Safety = Tabs.General:AddLeftGroupbox("Safety")
    Groupboxes.Exploits_Garden = Tabs.Exploits:AddLeftGroupbox("Garden")

    -- guis
    for _, Old in GetHiddenContainer():GetChildren() do
        if Old.Name == "AMRHotbar" or Old.Name == "AMROverlay" or Old.Name == "AMRHotbarSearch" then Old:Destroy() end
    end
    local HotbarGui = New("ScreenGui", { Name = "AMRHotbar", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50 }, GetHiddenContainer())
    -- search panel lives in its own gui ABOVE the menu (Obsidian menu is DisplayOrder 999, the old panel was hidden behind it)
    local SearchGui = New("ScreenGui", {
        Name = "AMRHotbarSearch", ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = math.max(2000, (Library.ScreenGui and Library.ScreenGui.DisplayOrder or 0) + 10),
    }, GetHiddenContainer())
    local OverlayGui = New("ScreenGui", { Name = "AMROverlay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40 }, GetHiddenContainer())

    ---------------------------------------------------------------------
    -- Noclip auto-fly
    ---------------------------------------------------------------------
    Groupboxes.General_Experimental:AddToggle("NoclipAutoFly", {
        Text = "Noclip Auto-Fly", Default = true,
        Tooltip = "Turning Noclip on also turns on Fly at speed 3 and moves you straight ahead by itself. Turning it off restores your old Fly settings."
    })
    Toggles.NoclipToggle:OnChanged(function(Value)
        if not Toggles.NoclipAutoFly.Value then return end
        if Value then
            Globals.PreNoclipFly = Toggles.FlyToggle.Value
            Globals.PreNoclipFlySpeed = Options.FlySpeed.Value
            local Root = Character and Character:FindFirstChild("HumanoidRootPart")
            local Look = Root and Root.CFrame.LookVector or Camera.CFrame.LookVector
            local Flat = Vector3.new(Look.X, 0, Look.Z)
            Globals.AutoFlyDirection = Flat.Magnitude > 0.01 and Flat.Unit or nil
            Globals.AutoFly = true
            Options.FlySpeed:SetValue(3)
            Toggles.FlyToggle:SetValue(true)
        else
            Globals.AutoFly = false
            Toggles.FlyToggle:SetValue(Globals.PreNoclipFly or false)
            Options.FlySpeed:SetValue(Globals.PreNoclipFlySpeed or 20)
        end
    end)

    ---------------------------------------------------------------------
    -- Hotbar with fuzzy search
    ---------------------------------------------------------------------
    local Aliases = {
        ["godmode"] = "PositionSpoof", ["god mode"] = "PositionSpoof", ["god"] = "PositionSpoof",
        ["invincible"] = "PositionSpoof", ["годмод"] = "PositionSpoof", ["бог"] = "PositionSpoof",
        ["fog"] = "RemoveCameraFog", ["nofog"] = "RemoveCameraFog", ["no fog"] = "RemoveCameraFog", ["туман"] = "RemoveCameraFog",
        ["fly"] = "FlyToggle", ["флай"] = "FlyToggle", ["полет"] = "FlyToggle",
        ["clip"] = "NoclipToggle", ["noclip"] = "NoclipToggle", ["ноклип"] = "NoclipToggle",
        ["speed"] = "SpeedBoostToggle", ["скорость"] = "SpeedBoostToggle",
        ["steer"] = "AutoSteerMinecart", ["cart"] = "AutoSteerMinecart", ["minecart"] = "AutoSteerMinecart",
        ["lag"] = "AntiLag", ["fps"] = "AntiLag", ["антилаг"] = "AntiLag",
        ["jump"] = "InfiniteJumps", ["infinite items"] = "InfiniteItemsToggle", ["infinity items"] = "InfiniteItemsToggle",
        ["heal"] = "AutoHeal", 
    }

    local function Normalize(Text)
        Text = string.lower(tostring(Text))
        local Ok, Result = pcall(function()
            local Out = {}
            for _, Code in utf8.codes(Text) do
                if Code >= 0x410 and Code <= 0x42F then Code += 32 elseif Code == 0x401 then Code = 0x451 end
                local Char = utf8.char(Code)
                if Code > 127 or string.match(Char, "%w") then Out[#Out + 1] = Char end
            end
            return table.concat(Out)
        end)
        if Ok then return Result end
        return (string.gsub(Text, "[^%w]", ""))
    end

    local function Distance(A, B)
        local LengthA, LengthB = #A, #B
        if LengthA == 0 then return LengthB end
        if LengthB == 0 then return LengthA end
        local Previous = {}
        for J = 0, LengthB do Previous[J] = J end
        for I = 1, LengthA do
            local Current = { [0] = I }
            for J = 1, LengthB do
                local Cost = (string.byte(A, I) == string.byte(B, J)) and 0 or 1
                Current[J] = math.min(Previous[J] + 1, Current[J - 1] + 1, Previous[J - 1] + Cost)
            end
            Previous = Current
        end
        return Previous[LengthB]
    end

    -- lower is better, nil = no match; tolerates typos
    local function Score(Query, Candidate)
        if Candidate == "" then return nil end
        if Candidate == Query then return 0 end
        local Start = string.find(Candidate, Query, 1, true)
        if Start then return 1 + (Start - 1) * 0.1 + (#Candidate - #Query) * 0.01 end
        local Prefix = string.sub(Candidate, 1, #Query + 1)
        local Best = math.min(Distance(Query, Prefix), Distance(Query, Candidate))
        local Allowed = math.max(1, math.floor(#Query * 0.34))
        if Best <= Allowed then return 3 + Best end
        return nil
    end

    local function BuildIndex()
        local Index = {}
        for Name, Toggle in Toggles do
            local Label = Toggle.Text or Name
            local Entry = { Id = "t:" .. Name, Label = Label, Keys = {} }
            Entry.Keys[#Entry.Keys + 1] = { Text = Normalize(Label) }
            Entry.Keys[#Entry.Keys + 1] = { Text = Normalize(Name) }
            for Alias, Target in Aliases do
                if Target == Name then Entry.Keys[#Entry.Keys + 1] = { Text = Normalize(Alias), Alias = Alias } end
            end
            Index[#Index + 1] = Entry
        end
        local SeenItems = {}
        for _, Display in pairs(ItemNames) do
            if not SeenItems[Display] then
                SeenItems[Display] = true
                Index[#Index + 1] = { Id = "i:" .. Display, Label = Display .. " (item)", Keys = { { Text = Normalize(Display) } } }
            end
        end
        return Index
    end

    local function Search(Query)
        Query = Normalize(Query)
        local Index = BuildIndex()
        local Results = {}
        for _, Entry in Index do
            local Best, Hint
            if Query == "" then
                Best = 5
            else
                for _, Key in Entry.Keys do
                    local Value = Score(Query, Key.Text)
                    if Value and (not Best or Value < Best) then Best, Hint = Value, Key.Alias end
                end
            end
            if Best then Results[#Results + 1] = { Entry = Entry, Score = Best, Hint = Hint } end
        end
        table.sort(Results, function(A, B)
            if A.Score ~= B.Score then return A.Score < B.Score end
            return A.Entry.Label < B.Entry.Label
        end)
        local Top = {}
        for Index2 = 1, math.min(30, #Results) do Top[Index2] = Results[Index2] end
        return Top
    end

    do
        local UserInputService = game:GetService("UserInputService")
        local TweenService = game:GetService("TweenService")

        local Fallback = {
            BackgroundColor = Color3.fromRGB(15, 15, 15), MainColor = Color3.fromRGB(25, 25, 25),
            AccentColor = Color3.fromRGB(125, 85, 255), OutlineColor = Color3.fromRGB(40, 40, 40),
            FontColor = Color3.new(1, 1, 1), DarkColor = Color3.new(0, 0, 0), RedColor = Color3.fromRGB(255, 50, 50),
        }
        local function Col(Key)
            local Ok, Value = pcall(function() return Library.Scheme[Key] end)
            if Ok and typeof(Value) == "Color3" then return Value end
            return Fallback[Key]
        end
        local function Mobile()
            return (Library.IsMobile == true) or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
        end

        -- everything follows the menu theme (colours + font)
        local Themed, FontLabels = {}, {}
        local function Reg(Object, Prop, Key)
            Themed[#Themed + 1] = { Object, Prop, Key }
            Object[Prop] = Col(Key)
            return Object
        end
        local function SetFont(Label)
            local Ok, Font = pcall(function() return Library.Scheme.Font end)
            if Ok and typeof(Font) == "Font" then
                Label.FontFace = Font
            elseif Ok and typeof(Font) == "EnumItem" then
                Label.Font = Font
            else
                Label.Font = Enum.Font.Code
            end
        end
        local function Lbl(Class, Props, Parent)
            local Object = New(Class, Props, Parent)
            FontLabels[#FontLabels + 1] = Object
            SetFont(Object)
            Reg(Object, "TextColor3", "FontColor")
            return Object
        end
        local function Skin()
            for I = #Themed, 1, -1 do
                local Item = Themed[I]
                if not Item[1].Parent then table.remove(Themed, I) else Item[1][Item[2]] = Col(Item[3]) end
            end
            for I = #FontLabels, 1, -1 do
                if not FontLabels[I].Parent then table.remove(FontLabels, I) else SetFont(FontLabels[I]) end
            end
        end
        -- same frame look as a menu groupbox: background, 1px outline + dark shadow stroke, rounded
        local function Framed(Object, Fill)
            Reg(Object, "BackgroundColor3", Fill)
            New("UICorner", { CornerRadius = UDim.new(0, 6) }, Object)
            Reg(New("UIStroke", { Thickness = 1, ZIndex = 2 }, Object), "Color", "OutlineColor")
            Reg(New("UIStroke", { Thickness = 1.5, ZIndex = 1 }, Object), "Color", "DarkColor")
        end

        local Slots = Load("Hotbar.json")
        if type(Slots) ~= "table" then Slots = {} end
        for I = #Slots, 1, -1 do
            if Slots[I] == "t:NightVision" then table.remove(Slots, I) end
        end
        local State = Load("HotbarState.json")
        if type(State) ~= "table" then State = {} end

        local W, RowH = Mobile() and 142 or 158, Mobile() and 22 or 18

        local Hotbar = New("Frame", {
            Name = "Hotbar", Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BorderSizePixel = 0, Visible = State.Hidden ~= true,
        }, HotbarGui)
        Framed(Hotbar, "BackgroundColor")
        New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, Hotbar)

        local Top = New("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, Hotbar)
        Lbl("TextLabel", {
            Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -80, 1, 0), BackgroundTransparency = 1,
            Text = "Hotbar", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
        }, Top)
        local Buttons = New("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(0, 20),
            AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
        }, Top)
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
            SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
        }, Buttons)

        local function HeadButton(Text, Order, Parent)
            local Button = Lbl("TextButton", {
                LayoutOrder = Order, Size = UDim2.fromOffset(20, 20), Text = Text, TextSize = 14,
                AutoButtonColor = false, BorderSizePixel = 0,
            }, Parent)
            Reg(Button, "BackgroundColor3", "MainColor")
            New("UICorner", { CornerRadius = UDim.new(0, 4) }, Button)
            Reg(New("UIStroke", {}, Button), "Color", "OutlineColor")
            return Button
        end
        local AddButton = HeadButton("+", 1, Buttons)
        local EditButton = HeadButton("x", 2, Buttons)
        local CollapseButton = HeadButton("^", 3, Buttons)

        local Line = New("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0 }, Hotbar)
        Reg(Line, "BackgroundColor3", "OutlineColor")
        local Container = New("Frame", {
            LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        }, Hotbar)
        New("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, Container)
        New("UIPadding", {
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7),
        }, Container)

        local function ApplyCollapse()
            Container.Visible = not State.Collapsed
            Line.Visible = not State.Collapsed
            CollapseButton.Text = State.Collapsed and "v" or "^"
        end
        ApplyCollapse()

        -- position (saved as a fraction of the screen so it survives other screen sizes)
        local function View()
            return workspace.CurrentCamera.ViewportSize
        end
        local PosX, PosY = 0, 0
        -- only the title bar has to stay on screen, so the panel can sit anywhere, also low
        local function Place(X, Y)
            local V = View()
            PosX = math.clamp(X, 0, math.max(V.X - 44, 0))
            PosY = math.clamp(Y, 0, math.max(V.Y - 30, 0))
            Hotbar.Position = UDim2.fromOffset(PosX, PosY)
        end
        local function SaveState()
            local V = View()
            State.X, State.Y = PosX / V.X, PosY / V.Y
            Save("HotbarState.json", State)
        end
        Place((State.X or 0.012) * View().X, (State.Y or 0.3) * View().Y)

        local Dragging, DragStart, StartX, StartY, DragInput = false, nil, 0, 0, nil
        Top.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                Dragging, DragStart, StartX, StartY, DragInput = true, Input.Position, PosX, PosY, Input
                Input.Changed:Connect(function()
                    if Input.UserInputState == Enum.UserInputState.End then
                        Dragging = false
                        SaveState()
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(Input)
            if not Dragging then return end
            -- touch: follow only the finger that started the drag (the move stick is another touch)
            if Input == DragInput or (Input.UserInputType == Enum.UserInputType.MouseMovement and DragInput.UserInputType == Enum.UserInputType.MouseButton1) then
                local Delta = Input.Position - DragStart
                Place(StartX + Delta.X, StartY + Delta.Y)
            end
        end)

        CollapseButton.MouseButton1Click:Connect(function()
            State.Collapsed = not State.Collapsed
            ApplyCollapse()
            Save("HotbarState.json", State)
        end)

        local function SlotLabel(Id)
            local Kind, Name = string.sub(Id, 1, 1), string.sub(Id, 3)
            if Kind == "t" then
                local Toggle = Toggles[Name]
                return Toggle and (Toggle.Text or Name) or Name
            end
            return Name
        end

        local function SlotActive(Id)
            local Kind, Name = string.sub(Id, 1, 1), string.sub(Id, 3)
            if Kind == "t" then
                local Toggle = Toggles[Name]
                return Toggle ~= nil and Toggle.Value == true
            end
            local Tool = FindTool(Name)
            return Tool ~= nil and Tool.Parent == Character
        end

        local function Activate(Id)
            local Kind, Name = string.sub(Id, 1, 1), string.sub(Id, 3)
            if Kind == "t" then
                local Toggle = Toggles[Name]
                if Toggle then Toggle:SetValue(not Toggle.Value) end
            else
                local Tool = FindTool(Name)
                if not Tool then
                    Functions.Notify({ Title = Name .. " is not in your inventory" })
                elseif Tool.Parent == Character then
                    Humanoid:UnequipTools()
                else
                    Humanoid:EquipTool(Tool)
                end
            end
        end

        local Rows, Editing = {}, false
        local Empty

        local function Refresh()
            EditButton.TextColor3 = Editing and Col("RedColor") or Col("FontColor")
            for _, Row in Rows do
                local On = SlotActive(Row.Id)
                Row.Remove.Visible = Editing
                Row.Switch.Visible = not Editing
                Row.Label.TextColor3 = Editing and Col("RedColor") or Col("FontColor")
                Row.Label.TextTransparency = (Editing or On) and 0 or 0.4
                if Row.On ~= On then
                    Row.On = On
                    TweenService:Create(Row.Ball, TweenInfo.new(0.12), {
                        AnchorPoint = Vector2.new(On and 1 or 0, 0), Position = UDim2.fromScale(On and 1 or 0, 0),
                    }):Play()
                end
                Row.Switch.BackgroundColor3 = On and Col("AccentColor") or Col("MainColor")
                Row.SwitchStroke.Color = On and Col("AccentColor") or Col("OutlineColor")
                Row.Ball.BackgroundColor3 = Col("FontColor")
            end
        end

        local function Rebuild()
            for _, Row in Rows do Row.Row:Destroy() end
            Rows = {}
            if Empty then Empty:Destroy() Empty = nil end
            if #Slots == 0 then
                Empty = Lbl("TextLabel", {
                    LayoutOrder = 1, Size = UDim2.new(1, 0, 0, RowH), BackgroundTransparency = 1,
                    Text = "empty, tap +", TextSize = 14, TextTransparency = 0.5, TextXAlignment = Enum.TextXAlignment.Left,
                }, Container)
            end
            for Order, Id in Slots do
                local Row = New("TextButton", {
                    LayoutOrder = Order, Size = UDim2.new(1, 0, 0, RowH), BackgroundTransparency = 1,
                    Text = "", AutoButtonColor = false,
                }, Container)
                local Label = New("TextLabel", {
                    Size = UDim2.new(1, -40, 1, 0), BackgroundTransparency = 1, Text = SlotLabel(Id), TextSize = 14,
                    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
                }, Row)
                FontLabels[#FontLabels + 1] = Label
                SetFont(Label)
                local Switch = New("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(32, 18), BorderSizePixel = 0,
                }, Row)
                New("UICorner", { CornerRadius = UDim.new(1, 0) }, Switch)
                New("UIPadding", {
                    PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2),
                }, Switch)
                local SwitchStroke = New("UIStroke", {}, Switch)
                local Ball = New("Frame", {
                    Size = UDim2.fromScale(1, 1), SizeConstraint = Enum.SizeConstraint.RelativeYY, BorderSizePixel = 0,
                }, Switch)
                New("UICorner", { CornerRadius = UDim.new(1, 0) }, Ball)
                local Remove = New("TextLabel", {
                    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(32, 18),
                    BackgroundTransparency = 1, Text = "x", TextSize = 15, Visible = false,
                }, Row)
                FontLabels[#FontLabels + 1] = Remove
                SetFont(Remove)
                Reg(Remove, "TextColor3", "RedColor")
                Row.MouseButton1Click:Connect(function()
                    if Editing then
                        local At = table.find(Slots, Id)
                        if At then table.remove(Slots, At) end
                        Save("Hotbar.json", Slots)
                        Rebuild()
                    else
                        Activate(Id)
                        Refresh()
                    end
                end)
                Rows[#Rows + 1] = { Id = Id, Row = Row, Label = Label, Switch = Switch, SwitchStroke = SwitchStroke, Ball = Ball, Remove = Remove }
            end
            Refresh()
        end

        EditButton.MouseButton1Click:Connect(function()
            Editing = not Editing
            Refresh()
        end)

        -- search panel, same look
        local Panel = New("Frame", {
            Name = "Search", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.05, 0),
            Size = UDim2.fromOffset(Mobile() and 280 or 320, 330), BorderSizePixel = 0, Visible = false, Active = true,
        }, SearchGui)
        Framed(Panel, "BackgroundColor")
        Lbl("TextLabel", {
            Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -50, 0, 22), BackgroundTransparency = 1,
            Text = "Add to hotbar", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
        }, Panel)
        local CloseButton = HeadButton("x", 1, Panel)
        CloseButton.Position, CloseButton.Size = UDim2.new(1, -28, 0, 7), UDim2.fromOffset(20, 20)
        local SearchBox = Lbl("TextBox", {
            PlaceholderText = "type a function or item name...", Text = "", ClearTextOnFocus = false,
            Position = UDim2.fromOffset(8, 36), Size = UDim2.new(1, -16, 0, 30), TextSize = 14, BorderSizePixel = 0,
            PlaceholderColor3 = Color3.fromRGB(140, 140, 150), TextXAlignment = Enum.TextXAlignment.Left,
        }, Panel)
        Reg(SearchBox, "BackgroundColor3", "MainColor")
        New("UICorner", { CornerRadius = UDim.new(0, 4) }, SearchBox)
        New("UIPadding", { PaddingLeft = UDim.new(0, 8) }, SearchBox)
        Reg(New("UIStroke", {}, SearchBox), "Color", "OutlineColor")
        local Results = New("ScrollingFrame", {
            Position = UDim2.fromOffset(8, 74), Size = UDim2.new(1, -16, 1, -82), CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, BackgroundTransparency = 1, BorderSizePixel = 0,
        }, Panel)
        New("UIListLayout", { Padding = UDim.new(0, 4) }, Results)

        local function RefreshResults()
            for _, Child in Results:GetChildren() do
                if Child:IsA("TextButton") then Child:Destroy() end
            end
            local Found = Search(SearchBox.Text)
            if #Found == 0 then
                local None = Lbl("TextButton", {
                    Size = UDim2.new(1, -6, 0, 28), Text = "no matches", TextSize = 14, AutoButtonColor = false, BorderSizePixel = 0,
                }, Results)
                Reg(None, "BackgroundColor3", "MainColor")
                New("UICorner", { CornerRadius = UDim.new(0, 4) }, None)
                return
            end
            for Order, Result in Found do
                local Text = Result.Entry.Label
                if Result.Hint then Text = Text .. "   (" .. Result.Hint .. ")" end
                local Button = Lbl("TextButton", {
                    LayoutOrder = Order, Size = UDim2.new(1, -6, 0, 28), Text = Text, TextSize = 14,
                    TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, BorderSizePixel = 0,
                }, Results)
                Reg(Button, "BackgroundColor3", "MainColor")
                New("UICorner", { CornerRadius = UDim.new(0, 4) }, Button)
                New("UIPadding", { PaddingLeft = UDim.new(0, 8) }, Button)
                Reg(New("UIStroke", {}, Button), "Color", "OutlineColor")
                Button.MouseButton1Click:Connect(function()
                    if not table.find(Slots, Result.Entry.Id) then
                        Slots[#Slots + 1] = Result.Entry.Id
                        Save("Hotbar.json", Slots)
                        Rebuild()
                    end
                    Functions.Notify({ Title = "Added to hotbar", Body = Result.Entry.Label, Time = 2 })
                end)
            end
        end

        SearchBox:GetPropertyChangedSignal("Text"):Connect(RefreshResults)
        CloseButton.MouseButton1Click:Connect(function() Panel.Visible = false end)
        local function OpenSearch()
            Panel.Visible = true
            RefreshResults()
        end
        AddButton.MouseButton1Click:Connect(OpenSearch)

        Rebuild()
        task.spawn(function()
            while Alive do
                task.wait(0.25)
                Skin()
                Refresh()
                if Hotbar.Visible and not Dragging then Place(PosX, PosY) end
            end
        end)

        Groupboxes.General_Experimental:AddToggle("ShowHotbar", {
            Text = "Show Hotbar", Default = State.Hidden ~= true,
            Tooltip = "Draggable panel in the menu style. Drag it by its title, ^ collapses it, x = remove mode, + = add.",
        })
        Toggles.ShowHotbar:OnChanged(function(Value)
            Hotbar.Visible = Value
            if not Value then Panel.Visible = false end
            State.Hidden = not Value
            Save("HotbarState.json", State)
        end)
        Groupboxes.General_Experimental:AddButton({ Text = "Add To Hotbar (search)", Func = OpenSearch,
            Tooltip = "Type a name (typos are fine). Example: godmode finds Position Spoof." })
    end

    ---------------------------------------------------------------------
    -- Config code
    ---------------------------------------------------------------------
    local Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local function Encode(Data)
        local Out = {}
        for I = 1, #Data, 3 do
            local A, B, C = string.byte(Data, I, I + 2)
            local N = A * 65536 + (B or 0) * 256 + (C or 0)
            local C1 = math.floor(N / 262144) % 64
            local C2 = math.floor(N / 4096) % 64
            local C3 = math.floor(N / 64) % 64
            local C4 = N % 64
            Out[#Out + 1] = string.sub(Alphabet, C1 + 1, C1 + 1) .. string.sub(Alphabet, C2 + 1, C2 + 1)
                .. (B and string.sub(Alphabet, C3 + 1, C3 + 1) or "=") .. (C and string.sub(Alphabet, C4 + 1, C4 + 1) or "=")
        end
        return table.concat(Out)
    end
    local function Decode(Text)
        Text = string.gsub(Text, "[^%w%+/=]", "")
        local Out = {}
        for I = 1, #Text, 4 do
            local Group = string.sub(Text, I, I + 3)
            local N, Pads = 0, 0
            for J = 1, 4 do
                local Char = string.sub(Group, J, J)
                if Char == "=" or Char == "" then
                    N = N * 64
                    Pads += 1
                else
                    N = N * 64 + (string.find(Alphabet, Char, 1, true) - 1)
                end
            end
            local Bytes = string.char(math.floor(N / 65536) % 256, math.floor(N / 256) % 256, N % 256)
            Out[#Out + 1] = string.sub(Bytes, 1, 3 - Pads)
        end
        return table.concat(Out)
    end

    Groupboxes.General_Experimental:AddDivider()
    Groupboxes.General_Experimental:AddButton({
        Text = "Copy Config Code",
        Tooltip = "Copies all your toggles and sliders as one short code you can send to a friend.",
        Func = function()
            local Data = { T = {}, O = {} }
            for Name, Toggle in Toggles do Data.T[Name] = Toggle.Value end
            for Name, Option in Options do
                local Kind = Option.Type
                if Name ~= "ConfigCodeInput" and (Kind == "Slider" or Kind == "Dropdown" or Kind == "Input") and Option.Value ~= nil then
                    Data.O[Name] = Option.Value
                end
            end
            local Code = "AMR1:" .. Encode(HttpService:JSONEncode(Data))
            Functions.Notify({ Title = Copy(Code) and "Config code copied" or "Clipboard unavailable", Time = 3 })
        end
    })
    Groupboxes.General_Experimental:AddInput("ConfigCodeInput", { Text = "Config Code", Default = "", Placeholder = "paste a code here", Finished = false })
    Groupboxes.General_Experimental:AddButton({
        Text = "Apply Config Code",
        Func = function()
            local Raw = tostring(Options.ConfigCodeInput.Value or "")
            Raw = string.gsub(Raw, "%s", "")
            if string.sub(Raw, 1, 5) ~= "AMR1:" then
                Functions.Notify({ Title = "Not a config code" })
                return
            end
            local Ok, Data = pcall(function() return HttpService:JSONDecode(Decode(string.sub(Raw, 6))) end)
            if not Ok or type(Data) ~= "table" then
                Functions.Notify({ Title = "Config code is broken" })
                return
            end
            local Applied = 0
            for Name, Value in Data.O or {} do
                if Options[Name] and Name ~= "ConfigCodeInput" and pcall(function() Options[Name]:SetValue(Value) end) then Applied += 1 end
            end
            for Name, Value in Data.T or {} do
                if Toggles[Name] and pcall(function() Toggles[Name]:SetValue(Value) end) then Applied += 1 end
            end
            Functions.Notify({ Title = "Config applied", Body = Applied .. " settings", Time = 3 })
        end
    })

    ---------------------------------------------------------------------
    -- Auto heal
    ---------------------------------------------------------------------
    Groupboxes.Exploits_Experimental:AddToggle("AutoHeal", {
        Text = "Auto Heal", Default = false,
        Tooltip = "Uses Bandage / Vitamins / Smoothie from your inventory when health drops below the threshold."
    })
    Groupboxes.Exploits_Experimental:AddSlider("AutoHealThreshold", {
        Text = "Heal Below (%)", Min = 10, Max = 90, Default = 50, Rounding = 0, Compact = true
    })
    task.spawn(function()
        local LastUse = 0
        while Alive do
            task.wait(0.5)
            if Toggles.AutoHeal.Value and Humanoid and Humanoid.Health > 0 and tick() - LastUse > 4 then
                local Percent = Humanoid.Health / math.max(Humanoid.MaxHealth, 1) * 100
                if Percent < Options.AutoHealThreshold.Value then
                    for _, Name in { "Bandage", "BandagePack", "Vitamins", "Smoothie" } do
                        local Tool = FindTool(Name)
                        if Tool then
                            Humanoid:EquipTool(Tool)
                            task.wait(0.35)
                            pcall(function() Tool:Activate() end)
                            LastUse = tick()
                            Functions.Notify({ Title = "Auto Heal", Body = "Used " .. (ItemNames[Name] or Name), Time = 2 })
                            break
                        end
                    end
                end
            end
        end
    end)

    ---------------------------------------------------------------------
    -- Run tracking: death log, run summary, split timer, challenges
    ---------------------------------------------------------------------
    local RunStart = tick()
    local Events, EntityCounts, Deaths = {}, {}, 0
    local Violations = { Crucifix = 0, Closet = 0, Light = 0 }
    local LightTools = { Lighter = true, Flashlight = true, Shakelight = true, Candle = true, Lantern = true, LanternLitItem = true, RiftCandle = true }
    local EntityNames = { Eyes = true, Lookman = true, BackdoorLookman = true, A60 = true, A120 = true }

    local function LogEvent(Text)
        Events[#Events + 1] = { tick(), Text }
        if #Events > 300 then table.remove(Events, 1) end
    end

    local BestSplits = Load("Splits_" .. tostring(Floor) .. ".json")
    if type(BestSplits) ~= "table" then BestSplits = {} end
    local RunSplits = {}
    local RoomStart = tick()
    local LastDelta
    local RoomValue = GameData:FindFirstChild("LatestRoom")
    local PreviousRoom = RoomValue and RoomValue.Value or 0

    local function Summary()
        local Lines = {
            "Abyssal Massive Recode - run summary",
            string.format("Floor: %s | Room: %s | Time: %s | Deaths: %d", tostring(Floor), RoomValue and tostring(RoomValue.Value) or "?", Clock(tick() - RunStart), Deaths),
        }
        local Names = {}
        for Name, Count in EntityCounts do Names[#Names + 1] = Name .. " x" .. Count end
        table.sort(Names)
        Lines[#Lines + 1] = "Entities: " .. (#Names > 0 and table.concat(Names, ", ") or "none")
        Lines[#Lines + 1] = string.format("Challenge breaks: crucifix %d, closet %d, light %d", Violations.Crucifix, Violations.Closet, Violations.Light)
        local Slow = {}
        for Room, Seconds in RunSplits do Slow[#Slow + 1] = { Room, Seconds } end
        table.sort(Slow, function(A, B) return A[2] > B[2] end)
        for Index = 1, math.min(3, #Slow) do
            Lines[#Lines + 1] = string.format("Slow room %s: %s", Slow[Index][1], Clock(Slow[Index][2]))
        end
        return table.concat(Lines, "\n")
    end

    local function DeathReport()
        local Lines = { "Last 10s before death:" }
        local Cutoff = tick() - 10
        for _, Event in Events do
            if Event[1] >= Cutoff then Lines[#Lines + 1] = string.format("[-%.1fs] %s", tick() - Event[1], Event[2]) end
        end
        return table.concat(Lines, "\n") .. "\n\n" .. Summary()
    end

    Groupboxes.Floors_Experimental:AddToggle("SplitTimer", {
        Text = "Split Timer", Default = false,
        Tooltip = "Shows run time, current room time and how you compare to your best time for that room."
    })
    Groupboxes.Floors_Experimental:AddToggle("SplitNotify", { Text = "Notify Room Splits", Default = false })
    Groupboxes.Floors_Experimental:AddButton({ Text = "Reset Split Timer", Func = function()
        RunStart, RoomStart, RunSplits = tick(), tick(), {}
        Functions.Notify({ Title = "Split timer reset", Time = 2 })
    end })
    Groupboxes.Floors_Experimental:AddButton({ Text = "Reset Best Splits", Func = function()
        BestSplits = {}
        Save("Splits_" .. tostring(Floor) .. ".json", BestSplits)
        Functions.Notify({ Title = "Best splits cleared", Time = 2 })
    end })
    Groupboxes.Floors_Experimental:AddDivider()
    Groupboxes.Floors_Experimental:AddButton({ Text = "Copy Run Summary", Func = function()
        Functions.Notify({ Title = Copy(Summary()) and "Run summary copied" or "Clipboard unavailable", Time = 3 })
    end })
    Groupboxes.Floors_Experimental:AddButton({ Text = "Copy Death Log (last 10s)", Func = function()
        Functions.Notify({ Title = Copy(DeathReport()) and "Death log copied" or "Clipboard unavailable", Time = 3 })
    end })
    Groupboxes.Floors_Experimental:AddToggle("AutoDeathLog", {
        Text = "Auto Copy Death Log", Default = true, Tooltip = "Copies the last 10 seconds and the run summary when you die."
    })
    Groupboxes.Floors_Experimental:AddDivider()
    Groupboxes.Floors_Experimental:AddToggle("ChallengeCrucifix", { Text = "Challenge: No Crucifix", Default = false })
    Groupboxes.Floors_Experimental:AddToggle("ChallengeCloset", { Text = "Challenge: No Closets", Default = false })
    Groupboxes.Floors_Experimental:AddToggle("ChallengeLight", { Text = "Challenge: No Light", Default = false })
    local ChallengeLabel = Groupboxes.Floors_Experimental:AddLabel("Breaks: 0")
    Groupboxes.Floors_Experimental:AddDivider()
    Groupboxes.Floors_Experimental:AddLabel("Local Challenge Modes")
    Groupboxes.Floors_Experimental:AddToggle("ChallengeDrunkMode", {
        Text = "Challenge: Drunk Mode", Default = false,
        Tooltip = "Camera sway, breathing FOV, blur and drifting movement. Local only."
    })
    Groupboxes.Floors_Experimental:AddSlider("ChallengeDrunkIntensity", {
        Text = "Drunk Intensity", Default = 55, Min = 5, Max = 100, Rounding = 0, Compact = true
    })
    Groupboxes.Floors_Experimental:AddToggle("ChallengeMirrorWorld", {
        Text = "Challenge: Mirror World", Default = false,
        Tooltip = "Mirrors left/right movement, camera yaw, HUD layout and (with Mirror Render) the 3D picture itself."
    })
    Groupboxes.Floors_Experimental:AddToggle("ChallengeMirrorRender", {
        Text = "Mirror Render (experimental)", Default = true,
        Tooltip = "Flips the camera matrix so the whole 3D picture is mirrored. If the world looks inside-out or broken on your executor, turn this off."
    })

    local function Violation(Kind, Text)
        if not Toggles["Challenge" .. Kind].Value then return end
        Violations[Kind] += 1
        LogEvent("challenge broken: " .. Text)
        Functions.Notify({ Title = "Challenge broken", Body = Text .. " (" .. (Violations.Crucifix + Violations.Closet + Violations.Light) .. ")", Time = 3 })
        pcall(function()
            ChallengeLabel:SetText(string.format("Breaks: crucifix %d, closet %d, light %d", Violations.Crucifix, Violations.Closet, Violations.Light))
        end)
    end

    if RoomValue then
        RoomValue.Changed:Connect(function(NewRoom)
            local Elapsed = tick() - RoomStart
            RoomStart = tick()
            LogEvent("room " .. tostring(NewRoom))
            if NewRoom > PreviousRoom and Elapsed < 1800 then
                local Key = tostring(PreviousRoom)
                RunSplits[Key] = Elapsed
                local Best = BestSplits[Key]
                LastDelta = Best and (Elapsed - Best) or nil
                if not Best or Elapsed < Best then
                    BestSplits[Key] = Elapsed
                    Save("Splits_" .. tostring(Floor) .. ".json", BestSplits)
                end
                if Toggles.SplitNotify.Value then
                    Functions.Notify({
                        Title = "Room " .. Key .. ": " .. Clock(Elapsed),
                        Body = LastDelta and string.format("%+.1fs vs best", LastDelta) or "first time",
                        Time = 3,
                    })
                end
            end
            PreviousRoom = NewRoom
        end)
    end

    workspace.ChildAdded:Connect(function(Object)
        if string.find(Object.Name, "Moving$") or EntityNames[Object.Name] then
            EntityCounts[Object.Name] = (EntityCounts[Object.Name] or 0) + 1
            LogEvent("entity spawned: " .. Object.Name)
        end
    end)

    local Overlay = New("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.new(0, 330, 0, 24),
        BackgroundColor3 = Color3.fromRGB(15, 15, 20), BackgroundTransparency = 0.35, TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamMedium, TextSize = 13, Visible = false, BorderSizePixel = 0, Text = "",
    }, OverlayGui)
    Round(Overlay, 6)

    local HookedCharacter, HookedHumanoid, LastDeath = nil, nil, 0
    local function OnDeath()
        if tick() - LastDeath < 5 then return end
        LastDeath = tick()
        Deaths += 1
        LogEvent("died")
        if Toggles.AutoDeathLog.Value then
            Copy(DeathReport())
            Functions.Notify({ Title = "Death log copied to clipboard", Time = 4 })
        end
    end

    task.spawn(function()
        while Alive do
            task.wait(0.5)
            if Character and Character ~= HookedCharacter then
                HookedCharacter = Character
                Character.ChildAdded:Connect(function(Child)
                    if not Child:IsA("Tool") then return end
                    if ItemNames[Child.Name] == "Crucifix" then Violation("Crucifix", "used Crucifix") end
                    if LightTools[Child.Name] then Violation("Light", "equipped " .. (ItemNames[Child.Name] or Child.Name)) end
                end)
                Character:GetAttributeChangedSignal("Hiding"):Connect(function()
                    if Character:GetAttribute("Hiding") == true then
                        LogEvent("hid in closet")
                        Violation("Closet", "hid in a closet")
                    end
                end)
            end
            if Humanoid and Humanoid ~= HookedHumanoid then
                HookedHumanoid = Humanoid
                local Last = Humanoid.Health
                Humanoid.HealthChanged:Connect(function(Health)
                    if Health < Last then LogEvent(string.format("hp %d -> %d", Last, Health)) end
                    Last = Health
                    if Health <= 0 then OnDeath() end
                end)
                Humanoid.Died:Connect(OnDeath)
            end
        end
    end)

    ---------------------------------------------------------------------
    -- Arrows to the door and to rare items
    ---------------------------------------------------------------------
    Groupboxes.Visuals_Arrows:AddToggle("DoorArrow", { Text = "Door Arrow", Default = false, Tooltip = "Arrow pointing to the door of the current room." })
    Groupboxes.Visuals_Arrows:AddToggle("RareArrow", { Text = "Rare Item Arrow", Default = false, Tooltip = "Arrow to the nearest item selected in Players > Rare Items." })
    Groupboxes.Visuals_Arrows:AddToggle("ObjectiveArrow", { Text = "Objective Arrow", Default = false, Tooltip = "Arrows to the nearest objectives (the green highlighted things: keys, levers, fuses, books...). Works without Objective ESP." })
    Groupboxes.Visuals_Arrows:AddSlider("ObjectiveArrowCount", { Text = "Objective Arrows", Min = 1, Max = 4, Default = 2, Rounding = 0, Compact = true })
    Groupboxes.Visuals_Arrows:AddSlider("ArrowRooms", { Text = "Arrow Range (rooms ahead)", Min = 1, Max = 5, Default = 2, Rounding = 0, Compact = true,
        Tooltip = "Arrows show only targets in your room and up to this many rooms ahead. Passed rooms are dropped, nothing ahead = no arrow." })
    Groupboxes.Visuals_Arrows:AddSlider("ArrowSize", { Text = "Arrow Size (%)", Min = 60, Max = 220, Default = 130, Rounding = 0, Compact = true })
    Groupboxes.Visuals_Arrows:AddSlider("ArrowMax", { Text = "Max Arrows On Screen", Min = 1, Max = 8, Default = 5, Rounding = 0, Compact = true,
        Tooltip = "When more arrows want the screen, the priority category below wins and the farthest of the rest are hidden." })
    Groupboxes.Visuals_Arrows:AddDropdown("ArrowPriority", { Text = "Arrow Priority", Values = { "Doors", "Objectives", "Hazards", "Rare" }, Default = 1,
        Tooltip = "Which arrows are kept first when there are more than Max Arrows." })

    local UserInputService = game:GetService("UserInputService")
    local function ArrowScale()
        local Mobile = (Library.IsMobile == true) or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
        return Mobile and 0.78 or 1
    end

    -- big glowing arrow with black outline that orbits the screen centre and points at the target
    local function MakeArrow(Color, Radius)
        local Holder = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Visible = false,
        }, OverlayGui)
        local Glow = New("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(104, 104), BackgroundTransparency = 1,
            Text = "▲", TextColor3 = Color, TextTransparency = 0.35, Font = Enum.Font.GothamBlack, TextSize = 84,
        }, Holder)
        local GlowStroke = New("UIStroke", { Color = Color, Thickness = 5, Transparency = 0.55 }, Glow)
        local Arrow = New("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(64, 64), BackgroundTransparency = 1,
            Text = "▲", TextColor3 = Color, Font = Enum.Font.GothamBlack, TextSize = 50,
        }, Holder)
        New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3 }, Arrow)
        local Info = New("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(160, 20), BackgroundTransparency = 1,
            Text = "", TextColor3 = Color, Font = Enum.Font.GothamBlack, TextSize = 15,
        }, Holder)
        New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, Info)
        return { Holder = Holder, Arrow = Arrow, Glow = Glow, GlowStroke = GlowStroke, Info = Info, Radius = Radius }
    end
    local DoorArrow = MakeArrow(Color3.fromRGB(255, 210, 80), 120)
    local RareArrow = MakeArrow(Color3.fromRGB(90, 220, 255), 150)
    local TellerArrow = MakeArrow(Color3.fromRGB(255, 150, 60), 170)
    local ObjectiveArrows = {}
    for Index = 1, 4 do ObjectiveArrows[Index] = MakeArrow(Color3.fromRGB(0, 255, 0), 182) end
    local DoorTarget, RareTarget, RareName
    local ObjectiveTargets = {}

    local function PositionOf(Object)
        if Object:IsA("Model") then return Object:GetPivot().Position end
        return Object.Position
    end

    -- arrows only look at the current room and the next few rooms ahead
    local function CurrentRoomNumber()
        local Attribute = LocalPlayer:GetAttribute("CurrentRoom")
        if type(Attribute) == "number" then return Attribute end
        local Value = GameData:FindFirstChild("LatestRoom")
        return Value and Value.Value or 0
    end
    local function RoomNumber(Object)
        local Rooms = workspace:FindFirstChild("CurrentRooms")
        local Node = Object
        while Node and Node.Parent do
            if Node.Parent == Rooms then return tonumber(Node.Name) end
            Node = Node.Parent
        end
        return nil
    end

    task.spawn(function()
        while Alive do
            task.wait(1.2)
            DoorTarget, RareTarget = nil, nil
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            local Value = GameData:FindFirstChild("LatestRoom")
            local Room = Rooms and Value and Rooms:FindFirstChild(tostring(Value.Value))
            if Toggles.DoorArrow.Value and Room then
                local Door = Room:FindFirstChild("Door")
                if Door then DoorTarget = PositionOf(Door) end
            end
            if Toggles.RareArrow.Value and RootPart then
                local Best, BestDistance
                local Current, Range = CurrentRoomNumber(), math.floor(Options.ArrowRooms.Value)
                local function Check(Object)
                    local Display = ItemNames[Object.Name]
                    local Number = Display and RoomNumber(Object)
                    if Display and Options.RareItems.Value[Display] and (Object:IsA("Model") or Object:IsA("BasePart"))
                        and (not Number or (Number >= Current and Number <= Current + Range)) then
                        local Position = PositionOf(Object)
                        local Distance2 = (Position - RootPart.Position).Magnitude
                        if not BestDistance or Distance2 < BestDistance then Best, BestDistance, RareName = Position, Distance2, Display end
                    end
                end
                if Rooms then
                    for Number = Current, Current + Range do
                        local Folder = Rooms:FindFirstChild(tostring(Number))
                        if Folder then
                            for _, Object in Folder:GetDescendants() do Check(Object) end
                        end
                    end
                end
                local DropsFolder = workspace:FindFirstChild("Drops")
                if DropsFolder then
                    for _, Object in DropsFolder:GetChildren() do Check(Object) end
                end
                RareTarget = Best
            end
        end
    end)

    -- an objective is finished once its prompt is switched off (collected / pulled / used)
    local function ObjectiveDone(Object)
        local Prompt = Object:FindFirstChildWhichIsA("ProximityPrompt", true)
        return Prompt ~= nil and Prompt.Enabled == false
    end
    local ObjectiveNames = {
        TimerLever = "Time Lever", MinesAnchor = "Anchor", WaterPump = "Water Pump", VineGuillotine = "Vine Lever",
    }
    task.spawn(function()
        while Alive do
            task.wait(0.5)
            local Found = {}
            if Toggles.ObjectiveArrow.Value and RootPart then
                local Current, Range = CurrentRoomNumber(), math.floor(Options.ArrowRooms.Value)
                for _, Object in Objects.Objectives do
                    if typeof(Object) == "Instance" and Object.Parent and not ObjectiveDone(Object) then
                        local Target = Object
                        if Object.Name == "WaterPump" and Object:FindFirstChild("Wheel") then Target = Object.Wheel
                        elseif Object.Name == "VineGuillotine" and Object:FindFirstChild("Lever") then Target = Object.Lever end
                        local Ok, Position = pcall(function()
                            if Target:IsA("Model") then return Target:GetPivot().Position end
                            if Target:IsA("BasePart") then return Target.Position end
                            return nil
                        end)
                        local Number = Ok and RoomNumber(Object)
                        local Inside = Number and Number >= Current and Number <= Current + Range
                        if Ok and Position and (Inside or (not Number and (Position - RootPart.Position).Magnitude < 120)) then
                            Found[#Found + 1] = {
                                Position = Position,
                                Label = ObjectiveNames[Object.Name] or ObjectiveLabels[Object.Name] or Object.Name,
                                Distance = (Position - RootPart.Position).Magnitude,
                            }
                        end
                    end
                end
                table.sort(Found, function(A, B) return A.Distance < B.Distance end)
            end
            ObjectiveTargets = Found
        end
    end)

    local function PointArrow(Widget, Target, Label, Color)
        if not Target or not RootPart or not Camera then
            Widget.Holder.Visible = false
            return
        end
        local Offset = Target - Camera.CFrame.Position
        local Look = Camera.CFrame.LookVector
        local Forward = Vector3.new(Look.X, 0, Look.Z)
        if Forward.Magnitude < 0.01 then
            Widget.Holder.Visible = false
            return
        end
        Forward = Forward.Unit
        local Right = Forward:Cross(Vector3.yAxis)
        local Angle = math.atan2(Offset:Dot(Right), Offset:Dot(Forward))
        local Scale = ArrowScale()
        local Size = Scale * (Options.ArrowSize.Value / 100)
        local Pulse = 1 + 0.08 * math.sin(tick() * 6)
        if Color then
            Widget.Arrow.TextColor3, Widget.Glow.TextColor3, Widget.Info.TextColor3 = Color, Color, Color
            Widget.GlowStroke.Color = Color
        end
        local ArrowSize, GlowSize = 64 * Size * Pulse, 104 * Size * Pulse
        Widget.Arrow.TextSize, Widget.Glow.TextSize = math.floor(50 * Size * Pulse), math.floor(84 * Size * Pulse)
        Widget.Arrow.Size, Widget.Glow.Size = UDim2.fromOffset(ArrowSize, ArrowSize), UDim2.fromOffset(GlowSize, GlowSize)
        Widget.Info.TextSize = math.floor(15 * math.clamp(Size, 0.8, 1.4))
        local Dir = Vector2.new(math.sin(Angle), -math.cos(Angle))
        local Distance = Widget.Radius * Scale * math.max(0.85, Options.ArrowSize.Value / 130)
        local Position = UDim2.fromOffset(Dir.X * Distance, Dir.Y * Distance)
        Widget.Arrow.Position, Widget.Glow.Position = Position, Position
        Widget.Arrow.Rotation, Widget.Glow.Rotation = math.deg(Angle), math.deg(Angle)
        local Gap = Distance + 34 * Size
        Widget.Info.Position = UDim2.fromOffset(Dir.X * Gap, Dir.Y * Gap)
        Widget.Info.Text = string.format("%s %dm", Label, math.floor((Target - RootPart.Position).Magnitude))
        Widget.Holder.Visible = true
    end

    ---------------------------------------------------------------------
    -- Shared helpers: prompt timing, freeze manager, motion tracker, rusher list
    ---------------------------------------------------------------------
    Globals.Freeze = Globals.Freeze or {}
    Globals.JumpLock = false
    Globals.LastPromptTime = 0
    Globals.JumpWindow = 0
    do
        local PromptService = game:GetService("ProximityPromptService")
        -- any prompt press (e.g. opening a door) opens a short window in which unrequested jumps are cancelled
        local function Stamp()
            Globals.LastPromptTime = tick()
            Globals.JumpWindow = tick() + 3
        end
        PromptService.PromptButtonHoldBegan:Connect(Stamp)
        PromptService.PromptButtonHoldEnded:Connect(Stamp)
        PromptService.PromptTriggered:Connect(Stamp)
    end

    -- freeze = anchor the root while any reason is set (we never touch an anchor the game set itself)
    task.spawn(function()
        local Owned
        while Alive do
            RunService.Heartbeat:Wait()
            local Hiding = Character ~= nil and Character:GetAttribute("Hiding") == true
            if next(Globals.Freeze) ~= nil and RootPart and not Hiding then
                if not RootPart.Anchored then
                    RootPart.Anchored = true
                    Owned = RootPart
                end
            elseif Owned then
                if not Hiding and Owned.Parent then Owned.Anchored = false end
                Owned = nil
            end
        end
        if Owned and Owned.Parent then Owned.Anchored = false end
    end)

    -- speed / closing speed measured over a 0.6 s window (entity positions replicate in steps, per-frame deltas are noise)
    local function Motion(Data, Position, Reference)
        local History = Data.History
        if not History then
            History = {}
            Data.History = History
        end
        local Now = tick()
        local Distance = (Position - Reference).Magnitude
        local Last = History[#History]
        if Last and ((Position - Last.Position).Magnitude > 400 or Now - Last.Time > 1) then table.clear(History) end
        History[#History + 1] = { Time = Now, Position = Position, Distance = Distance }
        while #History > 2 and Now - History[1].Time > 0.6 do table.remove(History, 1) end
        local First = History[1]
        local Span = Now - First.Time
        if Span >= 0.12 then
            Data.Speed = (Position - First.Position).Magnitude / Span
            Data.Closing = (First.Distance - Distance) / Span
        end
        return Data.Speed or 0, Data.Closing or 0, Distance
    end

    local RusherNames = {
        RushMoving = "Rush", AmbushMoving = "Ambush", BashMoving = "Bash", A60 = "A-60", A120 = "A-120",
        GlitchRush = "Glitch Rush", GlitchAmbush = "Glitch Ambush", BackdoorRush = "Blitz", Scribbles = "Scribbles",
        DronesStampede = "Stampede", CustomEntity = "Entity",
    }
    local function RushersBuild()
        local List, Seen = {}, {}
        local function Consider(Object)
            if Seen[Object] or typeof(Object) ~= "Instance" then return end
            local Display = RusherNames[Object.Name]
            if Display and Object:IsA("Model") and Object:IsDescendantOf(workspace) and Object:GetAttribute("Inactive") ~= true then
                local Part = Object.PrimaryPart or Object:FindFirstChildWhichIsA("BasePart", true)
                if Part then
                    Seen[Object] = true
                    List[#List + 1] = { Model = Object, Part = Part, Name = Display }
                end
            end
        end
        for _, Object in workspace:GetChildren() do Consider(Object) end
        for _, Object in Objects.Entities do Consider(Object) end
        return List
    end
    -- cache: the world is walked at most every 0.05 s, everyone else reads the list (re-validated on every read)
    local function Rushers()
        local Now = tick()
        local Cache = Globals.RushersCache
        if not Cache or Now - (Globals.RushersStamp or 0) >= 0.05 then
            Cache = RushersBuild()
            Globals.RushersCache, Globals.RushersStamp = Cache, Now
        end
        local Bad = false
        for _, Info in Cache do
            if not Info.Model.Parent or not Info.Part.Parent or Info.Model:GetAttribute("Inactive") == true then Bad = true break end
        end
        if not Bad then return Cache end
        local Clean = {}
        for _, Info in Cache do
            if Info.Model.Parent and Info.Part.Parent and Info.Model:GetAttribute("Inactive") ~= true then Clean[#Clean + 1] = Info end
        end
        return Clean
    end

    ---------------------------------------------------------------------
    -- Danger engine: one pass per frame. ETA label, red screen, stick to floor, closet leave, water freeze,
    -- stats HUD and the Groundskeeper guard all read Globals.Danger() instead of measuring on their own.
    -- Returns { Level 0..3, Intensity 0..1, Eta, Nearest = {Name, Dist, Bps, Eta}, List = rushers, Seek, Keeper }
    ---------------------------------------------------------------------
    do
        local Tracked = setmetatable({}, { __mode = "k" })
        local State = { Level = 0, Intensity = 0, Eta = nil, Nearest = nil, List = {}, Seek = nil, Keeper = nil }
        local Dirty = true
        local SeekList, SeekStamp = {}, 0
        local Beat
        Beat = RunService.Heartbeat:Connect(function()
            if not Alive then Beat:Disconnect() return end
            Dirty = true
        end)
        local function DataFor(Model)
            local Data = Tracked[Model]
            if not Data then
                Data = {}
                Tracked[Model] = Data
            end
            return Data
        end
        local function PartOf(Model, Data)
            local Part = Data.Part
            if not Part or not Part.Parent then
                Part = Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart", true)
                Data.Part = Part
            end
            return Part
        end
        local function Measure(Name, Model, Data, Part, Origin, MinClosing)
            local Speed, Closing, Distance = Motion(Data, Part.Position, Origin)
            return {
                Name = Name, Model = Model, Part = Part, Data = Data, Dist = Distance, Bps = Speed, Closing = Closing,
                Eta = Closing > MinClosing and Distance / Closing or nil,
            }
        end

        Globals.Danger = function()
            if not Dirty then return State end
            Dirty = false
            local Warn = Options.EtaWarn and Options.EtaWarn.Value or 4
            local List, Level, Intensity, Eta, Nearest = {}, 0, 0, nil, nil
            State.Seek, State.Keeper = nil, nil
            if RootPart and RootPart.Parent then
                local Origin = RootPart.Position
                local function Consider(Item)
                    if not Nearest or Item.Dist < Nearest.Dist then Nearest = Item end
                    if Item.Eta then Eta = Eta and math.min(Eta, Item.Eta) or Item.Eta end
                end
                for _, Info in Rushers() do
                    local Item = Measure(Info.Name, Info.Model, DataFor(Info.Model), Info.Part, Origin, 3)
                    List[#List + 1] = Item
                    Consider(Item)
                    if Item.Eta then
                        Intensity = math.max(Intensity, math.clamp(1 - Item.Eta / (Warn * 2), 0, 1))
                        Level = math.max(Level, Item.Eta <= Warn and 3 or Item.Eta <= Warn * 2 and 2 or 1)
                    end
                    if Item.Closing > 3 and Item.Dist < 160 then
                        Intensity = math.max(Intensity, math.clamp(1 - Item.Dist / 160, 0, 1) * 0.7)
                        Level = math.max(Level, 1)
                    end
                end
                -- Seek (the chase model, found every 0.25 s)
                local Now = tick()
                if Now - SeekStamp >= 0.25 then
                    SeekStamp = Now
                    table.clear(SeekList)
                    for _, Object in workspace:GetChildren() do
                        if Object:IsA("Model") and string.find(Object.Name, "^SeekMoving") then SeekList[#SeekList + 1] = Object end
                    end
                end
                for _, Model in SeekList do
                    if Model.Parent then
                        local Data = DataFor(Model)
                        local Part = PartOf(Model, Data)
                        if Part then
                            local Item = Measure("Seek", Model, Data, Part, Origin, 3)
                            if not State.Seek or Item.Dist < State.Seek.Dist then State.Seek = Item end
                            Consider(Item)
                            Level = math.max(Level, Item.Dist < 40 and 3 or Item.Dist < 100 and 2 or Item.Dist < 160 and 1 or 0)
                            if Item.Dist < 160 then Intensity = math.max(Intensity, math.clamp(1 - Item.Dist / 160, 0, 1) * 0.6) end
                        end
                    end
                end
                -- Groundskeeper (model is found by the Garden code)
                local Keeper = Globals.KeeperModel
                if Keeper and Keeper.Parent then
                    local Data = DataFor(Keeper)
                    local Part = PartOf(Keeper, Data)
                    if Part then
                        local Item = Measure("Groundskeeper", Keeper, Data, Part, Origin, 1)
                        State.Keeper = Item
                        Consider(Item)
                        Level = math.max(Level, Item.Dist < 15 and 3 or Item.Dist < 40 and 2 or Item.Dist < 80 and 1 or 0)
                        if Item.Dist < 80 then Intensity = math.max(Intensity, math.clamp(1 - Item.Dist / 80, 0, 1) * 0.6) end
                    end
                end
                -- Brumble light on and close (set by Anti Brumble)
                if Globals.BrumbleLit then
                    Level = 3
                    Intensity = math.max(Intensity, 0.5)
                end
            end
            State.Level, State.Intensity, State.Eta, State.Nearest, State.List = Level, Intensity, Eta, Nearest, List
            return State
        end
    end

    ---------------------------------------------------------------------
    -- Seek ESP: distance, speed (bps = studs per second) and time to reach you
    ---------------------------------------------------------------------
    Groupboxes.Visuals_Warnings:AddToggle("SeekESP", {
        Text = "Seek ESP", Default = false,
        Tooltip = "Highlights Seek in the chase and shows how far he is, how fast he moves (bps) and when he reaches you."
    })
    Toggles.SeekESP:AddColorPicker("SeekESPColor", { Text = "Seek", Default = Color3.fromRGB(255, 70, 70), Transparency = 0 })
    local SeekFolder = New("Folder", { Name = "AMRSeekESP" }, GetHiddenContainer())
    local SeekTracked = {}

    local function DropSeek(Model)
        local Data = SeekTracked[Model]
        if Data then
            Data.Highlight:Destroy()
            Data.Billboard:Destroy()
            SeekTracked[Model] = nil
        end
    end
    local function TrackSeek(Model)
        local Part = Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart", true)
        if not Part then return end
        local Highlight = New("Highlight", {
            Adornee = Model, FillTransparency = 0.55, OutlineTransparency = 0,
            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        }, SeekFolder)
        local Billboard = New("BillboardGui", {
            Adornee = Part, AlwaysOnTop = true, Size = UDim2.fromOffset(240, 54),
            StudsOffset = Vector3.new(0, 5, 0), LightInfluence = 0,
        }, SeekFolder)
        local Label = New("TextLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
            TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Text = "",
        }, Billboard)
        New("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0) }, Label)
        SeekTracked[Model] = { Part = Part, Highlight = Highlight, Billboard = Billboard, Label = Label }
        Boot.Print("seek esp: tracking " .. Model.Name)
    end

    task.spawn(function()
        while Alive do
            RunService.Heartbeat:Wait()
            if Toggles.SeekESP.Value and RootPart then
                for _, Object in workspace:GetChildren() do
                    if Object:IsA("Model") and string.find(Object.Name, "^SeekMoving") and not SeekTracked[Object] then
                        TrackSeek(Object)
                    end
                end
                local Color = Options.SeekESPColor.Value
                for Model, Data in SeekTracked do
                    if not Model.Parent or not Data.Part.Parent then
                        DropSeek(Model)
                    else
                        local Speed, Closing, Distance = Motion(Data, Data.Part.Position, RootPart.Position)
                        local Level, Tint = "far", Color
                        if Distance < 40 then Level, Tint = "VERY CLOSE", Color3.fromRGB(255, 40, 40)
                        elseif Distance < 100 then Level, Tint = "close", Color3.fromRGB(255, 150, 40) end
                        local Line2 = string.format("%d bps", math.floor(Speed + 0.5))
                        if Closing > 3 then
                            Line2 ..= string.format("  |  reaches you in %.1fs", Distance / Closing)
                        elseif Speed > 3 then
                            Line2 ..= "  |  moving away"
                        end
                        Data.Label.Text = string.format("SEEK  %d studs (%s)\n%s", math.floor(Distance), Level, Line2)
                        Data.Label.TextColor3 = Tint
                        Data.Highlight.FillColor, Data.Highlight.OutlineColor = Tint, Tint
                    end
                end
            else
                for Model in SeekTracked do DropSeek(Model) end
            end
        end
        SeekFolder:Destroy()
    end)

    ---------------------------------------------------------------------
    -- Entity ETA + red screen + crosshair + stats HUD
    ---------------------------------------------------------------------
    Groupboxes.Visuals_Warnings:AddToggle("EntityETA", {
        Text = "Entity ETA", Default = false,
        Tooltip = "Distance, speed (bps) and seconds until Rush / Ambush / Bash / Scribbles / A-60 type entities reach you, plus a warning."
    })
    Groupboxes.Visuals_Warnings:AddSlider("EtaWarn", { Text = "Warn At (s)", Min = 1, Max = 10, Default = 4, Rounding = 1, Compact = true })
    Groupboxes.Visuals_Warnings:AddToggle("DangerVignette", {
        Text = "Red Screen (danger)", Default = false, Tooltip = "Red tint and screen edges that get stronger the closer a rushing entity is to hitting you."
    })
    Groupboxes.Visuals_HUD:AddToggle("Crosshair", { Text = "Crosshair", Default = false })
    Toggles.Crosshair:AddColorPicker("CrosshairColor", { Text = "Crosshair", Default = Color3.fromRGB(255, 255, 255), Transparency = 0 })
    Groupboxes.Visuals_HUD:AddSlider("CrosshairSize", { Text = "Crosshair Size", Min = 4, Max = 40, Default = 12, Rounding = 0, Compact = true })
    Groupboxes.Visuals_HUD:AddToggle("StatsHUD", { Text = "Stats HUD", Default = false, Tooltip = "FPS, ping and current room in the corner." })

    do
        local EtaGui = New("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 72), Size = UDim2.fromOffset(360, 60),
            BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 17, TextColor3 = Color3.new(1, 1, 1),
            Text = "", Visible = false,
        }, OverlayGui)
        New("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0) }, EtaGui)

        local Tint = New("Frame", {
            Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 0, 0), BorderSizePixel = 0,
            BackgroundTransparency = 1, Visible = false, Active = false,
        }, OverlayGui)
        local Edges = {}
        for _, Spec in {
            { UDim2.new(1, 0, 0.28, 0), UDim2.fromScale(0, 0), 90 },
            { UDim2.new(1, 0, 0.28, 0), UDim2.fromScale(0, 0.72), 270 },
            { UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
            { UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(0.82, 0), 180 },
        } do
            local Edge = New("Frame", {
                Size = Spec[1], Position = Spec[2], BackgroundColor3 = Color3.fromRGB(255, 0, 0),
                BorderSizePixel = 0, BackgroundTransparency = 1, Visible = false, Active = false,
            }, OverlayGui)
            New("UIGradient", {
                Rotation = Spec[3],
                Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
            }, Edge)
            Edges[#Edges + 1] = Edge
        end

        local CrossH = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 2),
            BorderSizePixel = 0, Visible = false,
        }, OverlayGui)
        local CrossV = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(2, 12),
            BorderSizePixel = 0, Visible = false,
        }, OverlayGui)
        New("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0) }, CrossH)
        New("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0) }, CrossV)

        local StatsLabel = New("TextLabel", {
            Position = UDim2.fromOffset(8, 58), Size = UDim2.fromOffset(260, 18), BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
            Text = "", Visible = false,
        }, OverlayGui)
        New("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0) }, StatsLabel)

        local Danger = 0
        task.spawn(function()
            while Alive do
                local Dt = RunService.Heartbeat:Wait()
                local State = Globals.Danger()
                local Lines, Worst = {}, State.Intensity
                if Toggles.EntityETA.Value and RootPart then
                    local Warn = Options.EtaWarn.Value
                    for _, Item in State.List do
                        if Item.Eta and Item.Eta <= Warn and not Item.Data.Warned then
                            Item.Data.Warned = true
                            Functions.Notify({ Title = Item.Name .. " reaches you in " .. string.format("%.1f", Item.Eta) .. "s", Time = 2 })
                        end
                        Lines[#Lines + 1] = string.format("%s  %d studs  %d bps%s", Item.Name, math.floor(Item.Dist),
                            math.floor(Item.Bps + 0.5), Item.Eta and string.format("  ETA %.1fs", Item.Eta) or "")
                    end
                end
                Danger += (Worst - Danger) * math.min(1, Dt * 8)
                EtaGui.Visible = Toggles.EntityETA.Value and #Lines > 0
                if EtaGui.Visible then
                    EtaGui.Text = table.concat(Lines, "\n")
                    EtaGui.TextColor3 = Danger > 0.4 and Color3.fromRGB(255, 80, 80) or Color3.new(1, 1, 1)
                end
                local Show = Toggles.DangerVignette.Value and Danger > 0.02
                local Pulse = 0.8 + 0.2 * math.sin(tick() * 10)
                Tint.Visible = Show
                Tint.BackgroundTransparency = 1 - math.clamp(Danger * Pulse * 0.4, 0, 0.5)
                for _, Edge in Edges do
                    Edge.Visible = Show
                    Edge.BackgroundTransparency = 1 - math.clamp(Danger * Pulse * 1.2, 0, 0.95)
                end
            end
        end)

        task.spawn(function()
            local Frames, Accum = 0, 0
            local Conn
            Conn = RunService.RenderStepped:Connect(function(Dt)
                if not Alive then Conn:Disconnect() return end
                Frames += 1
                Accum += Dt
            end)
            while Alive do
                task.wait(0.25)
                local Size = math.floor(Options.CrosshairSize.Value)
                local Color = Options.CrosshairColor.Value
                for _, Bar in { CrossH, CrossV } do
                    Bar.Visible = Toggles.Crosshair.Value
                    Bar.BackgroundColor3 = Color
                end
                CrossH.Size, CrossV.Size = UDim2.fromOffset(Size, 2), UDim2.fromOffset(2, Size)
                StatsLabel.Visible = Toggles.StatsHUD.Value
                if StatsLabel.Visible then
                    local Fps = Accum > 0 and math.floor(Frames / Accum + 0.5) or 0
                    Frames, Accum = 0, 0
                    local Ping = 0
                    pcall(function() Ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5) end)
                    StatsLabel.Text = string.format("FPS %d  |  ping %dms  |  room %s  |  danger %d", Fps, Ping, tostring(CurrentRoomNumber()), Globals.Danger().Level)
                else
                    Frames, Accum = 0, 0
                end
            end
        end)
    end

    ---------------------------------------------------------------------
    -- Safety: stick to floor near rushing entities, unwanted jump filter, auto leave closet, anti brumble
    ---------------------------------------------------------------------
    Groupboxes.General_Safety:AddToggle("BlockJumpNearEntities", {
        Text = "Stick To Floor Near Entities", Default = true,
        Tooltip = "While Rush / Ambush / A-60 / A-120 / Bash / Scribbles / Blitz type entities are in range: jumping is locked (also Infinite Jumps) and any upward push is cancelled."
    })
    Groupboxes.General_Safety:AddSlider("JumpBlockRange", { Text = "Stick Range", Min = 50, Max = 400, Default = 200, Rounding = 0, Compact = true })
    Groupboxes.General_Safety:AddToggle("BlockGhostJumps", {
        Text = "Block Unwanted Jumps", Default = true,
        Tooltip = "Cancels the hop you get after opening a door / pressing a prompt. Jumps you press yourself still work."
    })

    -- every CanJump write of ours is stamped, so the attribute handler can tell it from a write by the game
    Globals.WriteJump = function(Value)
        Globals.JumpSelfWrite = { Value = Value, Time = tick() }
        if Character then Character:SetAttribute("CanJump", Value) end
    end
    local function SetJumpLock(Locked)
        if Globals.JumpLock == Locked and Globals.JumpLockHumanoid == Humanoid then return end
        Globals.JumpLock = Locked
        Globals.JumpLockHumanoid = Humanoid
        pcall(function() Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not Locked) end)
        if Character then
            if Locked then
                Globals.WriteJump(false)
            else
                Globals.WriteJump(Toggles.EnableCharacterJump.Value and true or OldJump)
            end
        end
    end

    do
        local UIS = game:GetService("UserInputService")
        local LastRequest = 0
        local function Legit()
            -- a jump press right after a prompt press is the mobile jump button under the prompt button, not a real jump
            if tick() - Globals.LastPromptTime > 0.5 then LastRequest = tick() end
        end
        UIS.JumpRequest:Connect(Legit)
        UIS.InputBegan:Connect(function(Input)
            if Input.KeyCode == Enum.KeyCode.Space or Input.KeyCode == Enum.KeyCode.ButtonA then Legit() end
        end)
        local function OpenJumpWindow() Globals.JumpWindow = tick() + 3 end
        local Latest = GameData:FindFirstChild("LatestRoom")
        if Latest then Latest.Changed:Connect(OpenJumpWindow) end
        pcall(function() LocalPlayer:GetAttributeChangedSignal("CurrentRoom"):Connect(OpenJumpWindow) end)

        local HookedButton
        task.spawn(function()
            while Alive do
                task.wait(0.5)
                local Button = Globals.MainUI and Globals.MainUI:FindFirstChild("MainFrame") and Globals.MainUI.MainFrame:FindFirstChild("MobileButtons")
                Button = Button and Button:FindFirstChild("JumpButton")
                if Button and Button ~= HookedButton then
                    HookedButton = Button
                    Button.InputBegan:Connect(Legit)
                end
            end
        end)

        -- stick to floor / unwanted jump guard, every frame
        task.spawn(function()
            local Near, NextCheck = false, 0
            while Alive do
                RunService.Heartbeat:Wait()
                local Now = tick()
                if Now >= NextCheck then
                    NextCheck = Now + 0.1
                    Near = false
                    if Toggles.BlockJumpNearEntities.Value and RootPart then
                        local Range = Options.JumpBlockRange.Value
                        for _, Item in Globals.Danger().List do
                            if Item.Dist <= Range then Near = true break end
                        end
                    end
                end
                SetJumpLock(Near)
                local Flying = Toggles.FlyToggle.Value or Toggles.NoclipToggle.Value or Toggles.VelocityManipulationToggle.Value
                if RootPart and Humanoid and not Flying then
                    local Velocity = RootPart.AssemblyLinearVelocity
                    local Climbing = Humanoid:GetState() == Enum.HumanoidStateType.Climbing
                    if not Climbing then
                        if Near and Velocity.Y > 1 then
                            RootPart.AssemblyLinearVelocity = Vector3.new(Velocity.X, 0, Velocity.Z)
                            Humanoid.Jump = false
                        elseif Toggles.BlockGhostJumps.Value and Now < Globals.JumpWindow and Now - LastRequest > 0.5 and Now - (Globals.NudgeJump or 0) > 1 and Velocity.Y > 10 then
                            RootPart.AssemblyLinearVelocity = Vector3.new(Velocity.X, 0, Velocity.Z)
                            Humanoid.Jump = false
                        end
                    end
                end
            end
            SetJumpLock(false)
        end)
    end

    Groupboxes.General_Safety:AddToggle("AutoLeaveCloset", {
        Text = "Auto Leave Closet", Default = false,
        Tooltip = "After Auto Closet hid you, leaves the hiding spot when no entity is near any more."
    })
    Groupboxes.General_Safety:AddSlider("AutoLeaveDelay", { Text = "Leave After Clear (s)", Min = 0.5, Max = 6, Default = 1.5, Rounding = 1, Compact = true })
    task.spawn(function()
        local ClearSince, HiddenAuto, WasHiding, LastAuto = nil, false, false, 0
        while Alive do
            task.wait(0.15)
            if Globals.AutoClosetActive then LastAuto = tick() end
            local Hiding = Character ~= nil and Character:GetAttribute("Hiding") == true
            if Hiding and not WasHiding then HiddenAuto = tick() - LastAuto < 2 end
            WasHiding = Hiding
            if not Hiding then
                ClearSince = nil
            elseif Toggles.AutoLeaveCloset.Value and HiddenAuto then
                local Threat = Functions.GetNearestEntity(true) ~= nil
                if not Threat and RootPart then
                    for _, Item in Globals.Danger().List do
                        if Item.Dist < 150 then Threat = true break end
                    end
                end
                if Threat then
                    ClearSince = nil
                else
                    ClearSince = ClearSince or tick()
                    if tick() - ClearSince >= Options.AutoLeaveDelay.Value and Character:GetAttribute("AnimatingClient") ~= true
                        and RemotesFolder and RemotesFolder:FindFirstChild("CamLock") then
                        RemotesFolder.CamLock:FireServer()
                        ClearSince, HiddenAuto = nil, false
                        LogEvent("left closet (auto)")
                    end
                end
            end
        end
    end)

    -- anti brumble: while its light is on and it is close (horizontal distance first, height second) you are frozen completely
    Groupboxes.General_Safety:AddToggle("AntiBrumble", {
        Text = "Anti Brumble (freeze)", Default = false,
        Tooltip = "Freezes your character completely while a Brumble's light is on and it is within range."
    })
    Groupboxes.General_Safety:AddSlider("BrumbleRange", { Text = "Brumble Range", Min = 5, Max = 40, Default = 15, Rounding = 0, Compact = true })
    do
        local BrumbleNames = { LiveEntityBramble = true, Brumble = true, BrumbleRig = true, Bramble = true }
        local Brumbles = setmetatable({}, { __mode = "k" })
        local function Add(Object)
            if BrumbleNames[Object.Name] and Object:IsA("Model") then Brumbles[Object] = true end
        end
        local AddConnection
        AddConnection = workspace.DescendantAdded:Connect(function(Object)
            if not Alive then AddConnection:Disconnect() return end
            Add(Object)
        end)
        task.spawn(function()
            local Count = 0
            for _, Object in workspace:GetDescendants() do
                Add(Object)
                Count += 1
                if Count % 2000 == 0 then task.wait() end
            end
        end)
        local function IsLit(Model)
            local Head = Model:FindFirstChild("Head", true) or Model:FindFirstChildWhichIsA("BasePart", true)
            if not Head then return false end
            for _, Item in Head:GetDescendants() do
                if Item:IsA("Light") and Item.Enabled and Item.Brightness > 0 then return true end
            end
            return false
        end
        task.spawn(function()
            local Frozen, ReleasedAt = false, 0
            while Alive do
                task.wait(0.05)
                local Freeze = false
                if Toggles.AntiBrumble.Value and RootPart then
                    local Range = Options.BrumbleRange.Value
                    for Model in Brumbles do
                        if not Model.Parent then
                            Brumbles[Model] = nil
                        else
                            local Ok, Position = pcall(function() return Model:GetPivot().Position end)
                            if Ok then
                                local Offset = Position - RootPart.Position
                                local Horizontal = math.sqrt(Offset.X * Offset.X + Offset.Z * Offset.Z)
                                if Horizontal <= Range and math.abs(Offset.Y) <= math.max(10, Range) and IsLit(Model) then
                                    Freeze = true
                                    break
                                end
                            end
                        end
                    end
                end
                Globals.BrumbleLit = Freeze
                if Freeze then
                    -- light on -> stand still; after a release the next freeze waits 0.15 s so flicker does not jitter
                    if Frozen or tick() - ReleasedAt >= 0.15 then
                        Globals.Freeze.brumble = true
                        if not Frozen then
                            Frozen = true
                            Functions.Notify({ Title = "Brumble light on - frozen", Time = 2 })
                        end
                    end
                else
                    -- light off -> free at once
                    Globals.Freeze.brumble = nil
                    if Frozen then ReleasedAt = tick() end
                    Frozen = false
                end
            end
            Globals.BrumbleLit = false
            Globals.Freeze.brumble = nil
        end)
    end

    ---------------------------------------------------------------------
    -- Electric water: Position Spoof is switched off while you cross it (frozen with spoof ON when Bash / Scribbles are near)
    ---------------------------------------------------------------------
    Groupboxes.Archives_Bypasses:AddToggle("WaterAutoSpoof", {
        Text = "Auto Position Spoof On Water", Default = true,
        Tooltip = "Near electric water Position Spoof is turned off. If Bash / Scribbles are near, you freeze with Position Spoof ON until they are gone. After the water it comes back on."
    })
    Groupboxes.Archives_Bypasses:AddSlider("WaterEntityRange", { Text = "Water Entity Range", Min = 40, Max = 300, Default = 120, Rounding = 0, Compact = true })
    do
        local function NearWater()
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            if not Rooms or not RootPart then return false end
            local Current = CurrentRoomNumber()
            for Number = Current - 1, Current + 1 do
                local Room = Rooms:FindFirstChild(tostring(Number))
                local Water = Room and Room:FindFirstChild("Water")
                if Water then
                    local Ok, Result = pcall(function()
                        local CFrameBox, Size
                        if Water:IsA("BasePart") then
                            CFrameBox, Size = Water.CFrame, Water.Size
                        elseif Water:IsA("Model") then
                            CFrameBox, Size = Water:GetBoundingBox()
                        else
                            return false
                        end
                        local Local = CFrameBox:PointToObjectSpace(RootPart.Position)
                        return math.abs(Local.X) <= Size.X / 2 + 8 and math.abs(Local.Z) <= Size.Z / 2 + 8 and Local.Y > -12 and Local.Y < 14
                    end)
                    if Ok and Result then return true end
                end
            end
            return false
        end

        task.spawn(function()
            local InWater, WasOn, HoldUntil = false, false, 0
            while Alive do
                task.wait(0.1)
                local Active = Toggles.BypassWater.Value and Toggles.WaterAutoSpoof.Value and NearWater()
                if Active then
                    if not InWater then
                        InWater = true
                        WasOn = Toggles.PositionSpoof.Value
                    end
                    local Close = false
                    local Range = Options.WaterEntityRange.Value
                    for _, Info in Globals.Danger().List do
                        if (Info.Name == "Bash" or Info.Name == "Scribbles") and Info.Dist <= Range then
                            Close = true
                            break
                        end
                    end
                    if Close then HoldUntil = tick() + 1.5 end
                    if tick() < HoldUntil then
                        Globals.Freeze.water = true
                        if not Toggles.PositionSpoof.Value then Toggles.PositionSpoof:SetValue(true) end
                    else
                        Globals.Freeze.water = nil
                        if Toggles.PositionSpoof.Value then Toggles.PositionSpoof:SetValue(false) end
                    end
                elseif InWater then
                    InWater = false
                    Globals.Freeze.water = nil
                    if WasOn and not Toggles.PositionSpoof.Value then Toggles.PositionSpoof:SetValue(true) end
                end
            end
            Globals.Freeze.water = nil
        end)
    end

    ---------------------------------------------------------------------
    -- Auto Rooms anti-stuck: no progress for 5 s -> re-route, then a short jump, then give up and say so
    ---------------------------------------------------------------------
    do
        Groupboxes.Floors_Experimental:AddToggle("RoomsAntiStuck", {
            Text = "Auto Rooms Anti-Stuck", Default = true,
            Tooltip = "If Auto Rooms hasn't moved you more than 3 studs in 5 s (and you are not hiding or frozen on purpose): re-routes to the exit, then tries a short jump if jumping is allowed, then tells you. 10 s between tries, 3 tries per room."
        })
        local Samples = {}
        local Stuck = { Room = nil, Tries = 0, Next = 0, GaveUp = false }

        local function Nudge(Try)
            Globals.RoomsNudge = true   -- the Auto Rooms handler waits while this is set
            local Deadline = tick() + 3
            while Globals.RoomsAutoWalkActive and tick() < Deadline do task.wait() end
            local Ok, Error = pcall(function()
                local Room = CurrentRooms[tostring(LatestRoom.Value)]
                if not Room or not RootPart or not Humanoid then return end
                -- old stuck marks can wall off the only way through
                for _, Object in Globals.RoomsNodesFolder:GetChildren() do
                    if Object.Name == "StuckPart" or Object.Name == "PathNode" then Object:Destroy() end
                end
                local CanJump = not Globals.JumpLock and (Toggles.EnableCharacterJump.Value or (Character and Character:GetAttribute("CanJump") == true))
                if Try >= 2 and CanJump then
                    Globals.NudgeJump = tick()
                    Humanoid.Jump = true
                    task.wait(0.35)
                end
                local Exit = Room:FindFirstChild("RoomExit")
                if not Exit then return end
                local Target = Exit:IsA("BasePart") and Exit.Position or Exit:GetPivot().Position
                local Path = game:GetService("PathfindingService"):CreatePath({
                    AgentCanJump = CanJump == true, AgentCanClimb = false, WaypointSpacing = 4, AgentRadius = 1, AgentHeight = 3,
                })
                local Start = CollisionPart and CollisionPart.Position or RootPart.Position
                Path:ComputeAsync(Start, Target)
                local Waypoints = Path.Status == Enum.PathStatus.Success and Path:GetWaypoints() or {}
                if #Waypoints == 0 then
                    Humanoid:MoveTo(Target)
                    task.wait(1)
                    return
                end
                local Began = tick()
                for _, Waypoint in Waypoints do
                    if tick() - Began > 4 or not Toggles.RoomsAutoWalk.Value then break end
                    local Done = false
                    local Connection = Humanoid.MoveToFinished:Connect(function() Done = true end)
                    Humanoid:MoveTo(Waypoint.Position)
                    local Until = tick() + 1.2
                    while not Done and tick() < Until do task.wait() end
                    Connection:Disconnect()
                end
            end)
            Globals.RoomsNudge = false
            if not Ok then Boot.Print("anti-stuck error: " .. tostring(Error)) end
        end

        task.spawn(function()
            while Alive do
                task.wait(0.5)
                local Watching = Floor == "Rooms" and Toggles.RoomsAntiStuck.Value and Toggles.RoomsAutoWalk.Value
                    and RootPart and Humanoid and Humanoid.Health > 0 and Character and Character:GetAttribute("Hiding") ~= true
                    and next(Globals.Freeze) == nil and not Globals.JumpLock and LatestRoom.Value < 1000
                if not Watching then
                    table.clear(Samples)
                else
                    local Now = tick()
                    local Room = LatestRoom.Value
                    if Stuck.Room ~= Room then
                        Stuck.Room, Stuck.Tries, Stuck.GaveUp = Room, 0, false
                        table.clear(Samples)
                    end
                    Samples[#Samples + 1] = { Time = Now, Position = RootPart.Position }
                    while #Samples > 1 and Now - Samples[1].Time > 5.5 do table.remove(Samples, 1) end
                    if not Stuck.GaveUp and Now >= Stuck.Next and Now - Samples[1].Time >= 5 then
                        local Farthest = 0
                        for _, Sample in Samples do
                            Farthest = math.max(Farthest, (Sample.Position - RootPart.Position).Magnitude)
                        end
                        if Farthest < 3 then
                            table.clear(Samples)
                            Stuck.Next = Now + 10
                            if Stuck.Tries >= 3 then
                                Stuck.GaveUp = true
                                Functions.Notify({ Title = "Auto Rooms: stuck", Body = "Gave up in room " .. tostring(Room), Time = 5 })
                            else
                                Stuck.Tries += 1
                                Functions.Notify({
                                    Title = "Auto Rooms: no progress",
                                    Body = (Stuck.Tries == 1 and "re-routing" or Stuck.Tries == 2 and "jump + re-route" or "last try") .. " (" .. Stuck.Tries .. "/3)",
                                    Time = 3,
                                })
                                Nudge(Stuck.Tries)
                                table.clear(Samples)
                            end
                        end
                    end
                end
            end
            Globals.RoomsNudge = false
        end)
    end

    ---------------------------------------------------------------------
    -- Garden: anti touch grass / groundskeeper, hazard arrows (see Garden Dump)
    ---------------------------------------------------------------------
    do
        Groupboxes.Exploits_Garden:AddToggle("AntiTouchGrass", {
            Text = "Hover Over Grass", Default = false,
            Tooltip = "Puts an invisible walkway under your feet that rides above the grass, so you walk in the air over it. Your character itself is moved, which is what the server sees."
        })
        Groupboxes.Exploits_Garden:AddSlider("HoverHeight", { Text = "Hover Height", Min = 2, Max = 8, Default = 4, Rounding = 1, Compact = true, Tooltip = "Studs between the top of the grass and your feet." })
        Groupboxes.Exploits_Garden:AddToggle("GroundskeeperGuard", {
            Text = "Groundskeeper Guard", Default = false,
            Tooltip = "While the Groundskeeper is out and closing in: turns Hover Over Grass on by itself and warns with distance, speed and time to reach you."
        })
        Groupboxes.Exploits_Garden:AddToggle("GardenProbe", {
            Text = "Garden Probe (log)", Default = false,
            Tooltip = "Logs remotes, attribute changes, floor material, keeper spawns and grass contact (last 200 lines). Turn it on, let the Groundskeeper trigger once, then press Garden Probe (copy)."
        })
        Groupboxes.Visuals_Arrows:AddToggle("HazardArrows", {
            Text = "Hazard Arrows", Default = false,
            Tooltip = "Red arrows to Groundskeeper and to the nearest Mandrake hole, with a warning when you get close."
        })
        Groupboxes.Visuals_Arrows:AddSlider("MandrakeWarn", { Text = "Mandrake Warn Distance", Min = 15, Max = 80, Default = 35, Rounding = 0, Compact = true })

        local function IsGrass(Part)
            return Part:IsA("BasePart") and (Part.Material == Enum.Material.Grass or string.find(string.lower(Part.Name), "grass", 1, true) ~= nil)
        end
        local function TopOf(Part)
            local Frame, Size = Part.CFrame, Part.Size
            return Frame.Position.Y + (math.abs(Frame.RightVector.Y) * Size.X + math.abs(Frame.UpVector.Y) * Size.Y + math.abs(Frame.LookVector.Y) * Size.Z) / 2
        end

        local function Outdoors()
            return Floor == "Garden" or Globals.OutdoorsFloor == Floor
        end

        -- probe: ring buffer of what happens around the Groundskeeper (Garden Probe toggle)
        local Probe = { On = false, Lines = {}, Start = 0, Connections = {}, Seen = setmetatable({}, { __mode = "k" }), Grass = false, Char = nil, LastKeeper = 0 }
        local function ProbeLog(Text)
            if not Probe.On then return end
            local Lines = Probe.Lines
            Lines[#Lines + 1] = string.format("[%7.2f] %s", tick() - Probe.Start, Text)
            if #Lines > 200 then table.remove(Lines, 1) end
        end
        local function ProbeHook(Signal, Callback)
            Probe.Connections[#Probe.Connections + 1] = Signal:Connect(Callback)
        end
        local function ProbeDisconnect()
            for _, Connection in Probe.Connections do pcall(function() Connection:Disconnect() end) end
            table.clear(Probe.Connections)
        end
        local function ArgTypes(...)
            local Out = {}
            for Index = 1, select("#", ...) do
                local Value = select(Index, ...)
                local Kind = typeof(Value)
                if Kind == "Instance" then Kind = "Instance:" .. Value.Name
                elseif Kind == "string" then Kind = "string:" .. string.sub(Value, 1, 24)
                elseif Kind == "number" or Kind == "boolean" then Kind = Kind .. ":" .. tostring(Value) end
                Out[#Out + 1] = Kind
            end
            return table.concat(Out, ", ")
        end
        local function ProbeCharacter()
            local Hooked, Human = Character, Humanoid
            Probe.Char = Hooked
            if not Hooked then return end
            ProbeHook(Hooked.AttributeChanged, function(Name)
                ProbeLog("attr " .. Name .. " = " .. tostring(Hooked:GetAttribute(Name)))
            end)
            for _, Part in Hooked:GetDescendants() do
                if Part:IsA("BasePart") then
                    ProbeHook(Part.Touched, function(Other)
                        if IsGrass(Other) then
                            local Now = tick()
                            if not Probe.Seen[Other] or Now - Probe.Seen[Other] > 2 then
                                Probe.Seen[Other] = Now
                                ProbeLog("touch " .. Other.Name .. " mat=" .. tostring(Other.Material) .. " CanTouch=" .. tostring(Other.CanTouch) .. " by " .. Part.Name)
                            end
                        end
                    end)
                end
            end
            if Human then
                ProbeHook(Human:GetPropertyChangedSignal("FloorMaterial"), function() ProbeLog("floor material -> " .. tostring(Human.FloorMaterial)) end)
                ProbeHook(Human.StateChanged, function(_, State) ProbeLog("humanoid state -> " .. tostring(State)) end)
            end
        end
        local function ProbeStart()
            ProbeDisconnect()
            table.clear(Probe.Lines)
            Probe.On, Probe.Start, Probe.Grass = true, tick(), false
            if RemotesFolder then
                local function HookRemote(Remote)
                    if Remote:IsA("BaseRemoteEvent") then
                        ProbeHook(Remote.OnClientEvent, function(...) ProbeLog("remote " .. Remote.Name .. "(" .. ArgTypes(...) .. ")") end)
                    end
                end
                for _, Remote in RemotesFolder:GetChildren() do HookRemote(Remote) end
                ProbeHook(RemotesFolder.ChildAdded, function(Remote)
                    ProbeLog("remote added " .. Remote.Name)
                    HookRemote(Remote)
                end)
            end
            ProbeHook(LocalPlayer.AttributeChanged, function(Name) ProbeLog("player attr " .. Name .. " = " .. tostring(LocalPlayer:GetAttribute(Name))) end)
            local function Keeperish(Object)
                if string.find(string.lower(Object.Name), "keeper", 1, true) then
                    ProbeLog("spawn " .. Object.ClassName .. " " .. Object:GetFullName())
                end
            end
            ProbeHook(workspace.ChildAdded, Keeperish)
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            if Rooms then ProbeHook(Rooms.DescendantAdded, Keeperish) end
            ProbeCharacter()
            ProbeLog(string.format("probe on | floor=%s room=%s floorMat=%s", tostring(Floor), tostring(CurrentRoomNumber()), Humanoid and tostring(Humanoid.FloorMaterial) or "?"))
        end
        Toggles.GardenProbe:OnChanged(function(Value)
            if Value then
                ProbeStart()
            else
                Probe.On = false
                ProbeDisconnect()
            end
        end)
        Groupboxes.Exploits_Garden:AddButton({
            Text = "Garden Probe (copy)",
            Tooltip = "Copies the probe log (last 200 lines) to the clipboard.",
            Func = function()
                local Text = #Probe.Lines > 0 and table.concat(Probe.Lines, "\n") or "(empty: turn Garden Probe (log) on first)"
                Functions.Notify({ Title = Copy(Text) and "Probe log copied" or "Clipboard unavailable", Body = #Probe.Lines .. " lines", Time = 3 })
            end
        })

        -- hover over grass: the walkway is client side, the character standing on it is not
        local Hover = { Platform = nil :: Part?, Level = 0, Ground = nil :: number?, Group = nil :: string?, GrassTop = nil :: number?, Next = 0, Char = nil :: Model? }
        local OverlapGrass = OverlapParams.new()
        OverlapGrass.FilterType = Enum.RaycastFilterType.Include
        OverlapGrass.MaxParts = 400
        local GroundRay = RaycastParams.new()
        GroundRay.FilterType = Enum.RaycastFilterType.Exclude
        GroundRay.RespectCanCollide = true

        local function HoverStop()
            if Hover.Platform then
                Hover.Platform:Destroy()
                Hover.Platform = nil
                ProbeLog("hover off")
            end
            Hover.Ground, Hover.GrassTop = nil, nil
        end

        local function HoverStep(Dt)
            local Flying = Toggles.FlyToggle.Value or Toggles.NoclipToggle.Value or Toggles.VelocityManipulationToggle.Value
            if not Toggles.AntiTouchGrass.Value or Flying or not Character or not RootPart or not RootPart.Parent or not Humanoid
                or Humanoid.Health <= 0 or Character:GetAttribute("Hiding") == true
                or Humanoid:GetState() == Enum.HumanoidStateType.Climbing then
                HoverStop()
                return
            end
            if Hover.Char ~= Character then
                HoverStop()
                Hover.Char = Character
            end
            local Now = tick()
            if Now >= Hover.Next then
                -- 10 Hz: real floor under you (walkway excluded) and the highest grass top around you
                Hover.Next = Now + 0.1
                local Filter = { Character }
                if Hover.Platform then Filter[#Filter + 1] = Hover.Platform end
                GroundRay.FilterDescendantsInstances = Filter
                local Hit = workspace:Raycast(RootPart.Position, Vector3.new(0, -80, 0), GroundRay)
                if Hit then
                    Hover.Ground, Hover.Group = Hit.Position.Y, Hit.Instance.CollisionGroup
                    local Rooms = workspace:FindFirstChild("CurrentRooms")
                    local Top
                    if Rooms then
                        OverlapGrass.FilterDescendantsInstances = { Rooms }
                        local Box = CFrame.new(RootPart.Position.X, Hover.Ground + 3, RootPart.Position.Z)
                        for _, Part in workspace:GetPartBoundsInBox(Box, Vector3.new(14, 14, 14), OverlapGrass) do
                            if IsGrass(Part) then
                                local PartTop = string.find(string.lower(Part.Name), "region", 1, true) and Hover.Ground or math.clamp(TopOf(Part), Hover.Ground, Hover.Ground + 4)
                                if not Top or PartTop > Top then Top = PartTop end
                            end
                        end
                    end
                    Hover.GrassTop = Top
                end
            end
            if not Hover.Ground then return end
            local Height = Options.HoverHeight.Value
            local Target = Hover.GrassTop and (Hover.GrassTop + Height) or Hover.Ground
            if not Hover.Platform then
                if Target <= Hover.Ground + 0.05 then return end
                local Platform = Instance.new("Part")
                Platform.Name = "AMRGrassWalkway"
                Platform.Size = Vector3.new(12, 1, 12)
                Platform.Anchored = true
                Platform.CanCollide = true
                Platform.CanTouch = false
                Platform.Transparency = 1
                -- same collision group as the floor you stand on, so the character collides with it the same way
                pcall(function() Platform.CollisionGroup = Hover.Group end)
                Hover.Level = Hover.Ground
                Platform.CFrame = CFrame.new(RootPart.Position.X, Hover.Level - 0.5, RootPart.Position.Z)
                Platform.Parent = workspace
                Hover.Platform = Platform
                ProbeLog(string.format("hover on | ground %.1f grass top %.1f height %.1f", Hover.Ground, Hover.GrassTop or Hover.Ground, Height))
            end
            -- ramp: up in about 0.4 s, down a bit faster; the humanoid steps along with the walkway
            local Delta = Target - Hover.Level
            local Speed = Delta > 0 and math.max(10, Height / 0.4) or 14
            local Step = Speed * Dt
            Hover.Level = math.abs(Delta) <= Step and Target or Hover.Level + math.sign(Delta) * Step
            Hover.Platform.CFrame = CFrame.new(RootPart.Position.X, Hover.Level - 0.5, RootPart.Position.Z)
            if not Hover.GrassTop and Hover.Level <= Hover.Ground + 0.02 then HoverStop() end
        end

        Toggles.AntiTouchGrass:OnChanged(function(Value)
            if Value and not Outdoors() then
                local Keeper = workspace:FindFirstChild("Groundskeeper")
                if Keeper then
                    Globals.OutdoorsFloor = Floor
                else
                    Functions.Notify({ Title = "Hover Over Grass", Body = "That's not useful in this floor", Time = 4 })
                    Toggles.AntiTouchGrass:SetValue(false)
                end
            end
        end)

        task.spawn(function()
            local Failed = 0
            while Alive do
                local Dt = RunService.Heartbeat:Wait()
                local Ok, Error = pcall(HoverStep, Dt)
                if not Ok and Failed < 3 then
                    Failed += 1
                    Boot.Print("hover error: " .. tostring(Error))
                end
            end
            HoverStop()
        end)

        -- probe poller: grass under your feet, keeper distance, respawn re-hook
        task.spawn(function()
            while Alive do
                task.wait(0.1)
                if Probe.On then
                    if Probe.Char ~= Character then ProbeCharacter() end
                    if RootPart and Humanoid then
                        local Rooms = workspace:FindFirstChild("CurrentRooms")
                        local Under
                        if Rooms then
                            OverlapGrass.FilterDescendantsInstances = { Rooms }
                            local FeetY = RootPart.Position.Y - (Humanoid.HipHeight + RootPart.Size.Y / 2)
                            local Box = CFrame.new(RootPart.Position.X, FeetY - 0.3, RootPart.Position.Z)
                            for _, Part in workspace:GetPartBoundsInBox(Box, Vector3.new(3, 1.5, 3), OverlapGrass) do
                                if IsGrass(Part) then Under = Part break end
                            end
                        end
                        if Under and not Probe.Grass then
                            ProbeLog("grass enter " .. Under.Name .. " mat=" .. tostring(Under.Material) .. " CanTouch=" .. tostring(Under.CanTouch) .. " CanCollide=" .. tostring(Under.CanCollide))
                        elseif Probe.Grass and not Under then
                            ProbeLog("grass leave")
                        end
                        Probe.Grass = Under ~= nil
                    end
                    local Keeper = Globals.Danger().Keeper
                    if Keeper and tick() - Probe.LastKeeper > 1 then
                        Probe.LastKeeper = tick()
                        ProbeLog(string.format("keeper %d studs %d bps%s", math.floor(Keeper.Dist), math.floor(Keeper.Bps + 0.5), Keeper.Eta and string.format(" eta %.1fs", Keeper.Eta) or ""))
                    end
                end
            end
            ProbeDisconnect()
        end)

        -- groundskeeper guard: its kill is server side, so the only real answer is not touching the grass
        local KeeperCache = { Model = nil, Next = 0 }
        local function FindKeeper()
            local Model = KeeperCache.Model
            if Model and Model.Parent and Model:IsDescendantOf(workspace) then return Model end
            KeeperCache.Model = nil
            local Direct = workspace:FindFirstChild("Groundskeeper")
            if Direct and Direct:IsA("Model") then
                KeeperCache.Model = Direct
                return Direct
            end
            local Now = tick()
            if Now >= KeeperCache.Next then
                KeeperCache.Next = Now + 2
                local Rooms = workspace:FindFirstChild("CurrentRooms")
                local Found = Rooms and Rooms:FindFirstChild("Groundskeeper", true)
                if Found and Found:IsA("Model") then
                    KeeperCache.Model = Found
                    return Found
                end
            end
            return nil
        end
        task.spawn(function()
            local ForcedOn, GoneSince, LastNote = false, nil, 0
            local Window = { Last = nil, Paused = false }
            while Alive do
                task.wait(0.25)
                local Wanted = Toggles.GroundskeeperGuard.Value or Toggles.HazardArrows.Value or Toggles.GardenProbe.Value
                local Passive = workspace:FindFirstChild("Groundskeeper")
                Globals.KeeperModel = Wanted and FindKeeper() or (Passive and Passive:IsA("Model") and Passive or nil)
                if Globals.KeeperModel and Globals.OutdoorsFloor ~= Floor then
                    Globals.OutdoorsFloor = Floor
                    Functions.Notify({ Title = "Groundskeeper found", Body = "This floor counts as outdoors", Time = 3 })
                end
                local Room = tonumber(CurrentRoomNumber()) or 0
                local InWindow = Outdoors() and Room >= 20 and Room < 24
                if Outdoors() then
                    local Was = Window.Last
                    if Room >= 20 and Room < 24 and (Was == nil or Was < 20) then
                        if Toggles.AntiTouchGrass.Value then
                            Window.Paused = true
                            Toggles.AntiTouchGrass:SetValue(false)
                            Functions.Notify({ Title = "Hover Over Grass off", Body = "Door 20: back on at door 24", Time = 4 })
                        end
                    elseif Room >= 24 and (Was == nil or Was < 24) and Window.Paused then
                        Window.Paused = false
                        Toggles.AntiTouchGrass:SetValue(true)
                        Functions.Notify({ Title = "Hover Over Grass on", Body = "Door 24", Time = 3 })
                    end
                    Window.Last = Room
                end
                local Keeper = Globals.Danger().Keeper
                local Chasing = Keeper ~= nil and (Keeper.Closing > 2 or Keeper.Dist < 60)
                if Toggles.GroundskeeperGuard.Value and Chasing then
                    if tick() - LastNote > 4 then
                        LastNote = tick()
                        Functions.Notify({
                            Title = string.format("Groundskeeper %d studs", math.floor(Keeper.Dist)),
                            Body = string.format("%d bps%s", math.floor(Keeper.Bps + 0.5), Keeper.Eta and string.format(", reaches you in %.1fs", Keeper.Eta) or ""),
                            Time = 3,
                        })
                    end
                    GoneSince = nil
                    if not Toggles.AntiTouchGrass.Value and not InWindow then
                        ForcedOn = true
                        Toggles.AntiTouchGrass:SetValue(true)
                    end
                elseif ForcedOn then
                    GoneSince = GoneSince or tick()
                    if tick() - GoneSince > 3 then
                        ForcedOn, GoneSince = false, nil
                        Toggles.AntiTouchGrass:SetValue(false)
                    end
                end
            end
            Globals.KeeperModel = nil
        end)
        -- auto hide in the nearest closet: only after the probe shows that hiding helps against the keeper

        local HazardArrows = { MakeArrow(Color3.fromRGB(255, 60, 60), 215), MakeArrow(Color3.fromRGB(255, 120, 40), 215) }
        local Hazard = {}
        task.spawn(function()
            local LastWarn = { Keeper = 0, Mandrake = 0 }
            while Alive do
                task.wait(0.5)
                Hazard.Keeper, Hazard.Mandrake = nil, nil
                if RootPart then
                    local Keeper = Globals.KeeperModel or workspace:FindFirstChild("Groundskeeper")
                    if Keeper and Keeper:IsA("Model") then
                        local Ok, Position = pcall(function() return Keeper:GetPivot().Position end)
                        if Ok then
                            Hazard.Keeper = Position
                            local Distance = (Position - RootPart.Position).Magnitude
                            if Toggles.HazardArrows.Value and not Toggles.GroundskeeperGuard.Value and Distance < 60 and tick() - LastWarn.Keeper > 6 then
                                LastWarn.Keeper = tick()
                                Functions.Notify({ Title = "Groundskeeper " .. math.floor(Distance) .. " studs away", Body = "Stay off the grass", Time = 3 })
                            end
                        end
                    end
                    local Rooms = workspace:FindFirstChild("CurrentRooms")
                    if Rooms then
                        local Current, Range = CurrentRoomNumber(), math.floor(Options.ArrowRooms.Value)
                        local BestDistance
                        for Number = Current, Current + Range do
                            local Folder = Rooms:FindFirstChild(tostring(Number))
                            local Mandrake = Folder and Folder:FindFirstChild("MandrakeLive", true)
                            local Hole = Mandrake and (Mandrake:FindFirstChild("Hole") or Mandrake)
                            if Hole then
                                local Ok, Position = pcall(function() return Hole:GetPivot().Position end)
                                if Ok then
                                    local Distance = (Position - RootPart.Position).Magnitude
                                    if not BestDistance or Distance < BestDistance then
                                        BestDistance, Hazard.Mandrake = Distance, Position
                                    end
                                end
                            end
                        end
                        if BestDistance and Toggles.HazardArrows.Value and BestDistance < Options.MandrakeWarn.Value and tick() - LastWarn.Mandrake > 6 then
                            LastWarn.Mandrake = tick()
                            Functions.Notify({ Title = "Mandrake hole " .. math.floor(BestDistance) .. " studs away", Body = "Do not walk closer", Time = 3 })
                        end
                    end
                end
            end
        end)
        -- drawn by the central arrow pass (priority + max arrows)
        Globals.GardenArrows = { Widgets = HazardArrows, Hazard = Hazard }

        Groupboxes.Exploits_Garden:AddButton({
            Text = "Garden Dump (copy)",
            Tooltip = "Copies remote names, grass parts, Groundskeeper / Mandrake structure to the clipboard. Use it in the Garden.",
            Func = function()
                local Out = {}
                local function Add(Text) Out[#Out + 1] = Text end
                local function Attributes(Object)
                    for Key, Value in Object:GetAttributes() do Add("  @" .. Key .. " = " .. tostring(Value)) end
                end
                local function Tree(Object, Depth)
                    Add(string.rep("  ", Depth) .. Object.ClassName .. " " .. Object.Name
                        .. (Object:IsA("BasePart") and (" CanTouch=" .. tostring(Object.CanTouch) .. " CanCollide=" .. tostring(Object.CanCollide) .. " Mat=" .. tostring(Object.Material)) or ""))
                    if Depth < 3 then
                        for Index, Child in Object:GetChildren() do
                            if Index > 40 then Add(string.rep("  ", Depth + 1) .. "...") break end
                            Tree(Child, Depth + 1)
                        end
                    end
                end
                Add("== Garden dump == floor=" .. tostring(Floor) .. " room=" .. tostring(CurrentRoomNumber()))
                pcall(function() Add("FloorMaterial = " .. tostring(Humanoid.FloorMaterial)) end)
                Add("-- Character attributes")
                pcall(function() Attributes(Character) end)
                Add("-- RemotesFolder")
                if RemotesFolder then
                    for _, Remote in RemotesFolder:GetChildren() do Add(Remote.ClassName .. " " .. Remote.Name) end
                end
                local Keeper = workspace:FindFirstChild("Groundskeeper")
                if Keeper then
                    Add("-- workspace.Groundskeeper")
                    pcall(Attributes, Keeper)
                    pcall(Tree, Keeper, 0)
                end
                local Rooms = workspace:FindFirstChild("CurrentRooms")
                if Rooms then
                    local Mandrake = Rooms:FindFirstChild("MandrakeLive", true)
                    if Mandrake then
                        Add("-- MandrakeLive " .. Mandrake:GetFullName())
                        pcall(Attributes, Mandrake)
                        pcall(Tree, Mandrake, 0)
                    end
                    Add("-- grass-like parts in CurrentRooms")
                    local ByName, Count = {}, 0
                    for _, Object in Rooms:GetDescendants() do
                        if IsGrass(Object) then
                            Count += 1
                            ByName[Object.Name] = (ByName[Object.Name] or 0) + 1
                        end
                    end
                    Add("total = " .. Count)
                    for Name, Amount in ByName do Add("  " .. Name .. " x" .. Amount) end
                end
                local Text = table.concat(Out, "\n")
                if #Text > 90000 then Text = string.sub(Text, 1, 90000) end
                Functions.Notify({ Title = Copy(Text) and "Garden dump copied" or "Clipboard unavailable", Body = #Out .. " lines", Time = 4 })
            end
        })
    end

    ---------------------------------------------------------------------
    -- Party panel
    ---------------------------------------------------------------------
    Groupboxes.Visuals_Experimental:AddToggle("PartyPanel", { Text = "Party Panel", Default = false, Tooltip = "Health and alive status of everyone in the run." })
    local Party = New("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 150), Size = UDim2.new(0, 180, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(15, 15, 20), BackgroundTransparency = 0.35,
        Visible = false, BorderSizePixel = 0,
    }, OverlayGui)
    Round(Party, 6)
    New("UIListLayout", { Padding = UDim.new(0, 2) }, Party)
    New("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, Party)

    task.spawn(function()
        while Alive do
            task.wait(0.5)
            Party.Visible = Toggles.PartyPanel.Value
            if Party.Visible then
                for _, Child in Party:GetChildren() do
                    if Child:IsA("TextLabel") then Child:Destroy() end
                end
                for Order, Player in Players:GetPlayers() do
                    local Other = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
                    local Text, Color = Player.DisplayName .. "  no character", Color3.fromRGB(150, 150, 150)
                    if Other then
                        if Other.Health <= 0 then
                            Text, Color = Player.DisplayName .. "  dead", Color3.fromRGB(220, 80, 80)
                        else
                            local Ratio = Other.Health / math.max(Other.MaxHealth, 1)
                            Text = string.format("%s  %d/%d", Player.DisplayName, Other.Health, Other.MaxHealth)
                            Color = Ratio > 0.5 and Color3.fromRGB(110, 230, 130) or Ratio > 0.25 and Color3.fromRGB(240, 210, 90) or Color3.fromRGB(240, 110, 90)
                        end
                    end
                    New("TextLabel", {
                        LayoutOrder = Order, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = Text,
                        TextColor3 = Color, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
                    }, Party)
                end
            end
        end
    end)

    -- per-frame overlay update (arrows, split timer)
    do
        local Requests = {}
        local Order = { "Doors", "Objectives", "Hazards", "Rare" }
        local function Ask(Category, Widget, Target, Label, Color)
            if Target and RootPart then
                Requests[#Requests + 1] = {
                    Category = Category, Widget = Widget, Target = Target, Label = Label, Color = Color,
                    Dist = (Target - RootPart.Position).Magnitude,
                }
            else
                Widget.Holder.Visible = false
            end
        end
        -- every arrow asks, then the chosen priority category wins when more than "Max Arrows" want the screen
        local function ArrowFrame()
            table.clear(Requests)
            Ask("Doors", DoorArrow, Toggles.DoorArrow.Value and DoorTarget or nil, "door")
            Ask("Rare", RareArrow, Toggles.RareArrow.Value and RareTarget or nil, RareName or "item")
            Ask("Doors", TellerArrow, Toggles.TellerHUD and Toggles.TellerHUD.Value and Globals.TellerTarget or nil, Globals.TellerLabel or "teller", Color3.fromRGB(255, 150, 60))
            local ObjectiveColor = Options.ObjectiveESPColor and Options.ObjectiveESPColor.Value or Color3.fromRGB(0, 255, 0)
            local Count = Toggles.ObjectiveArrow.Value and math.floor(Options.ObjectiveArrowCount.Value) or 0
            for Index, Widget in ObjectiveArrows do
                local Entry = Index <= Count and ObjectiveTargets[Index] or nil
                Ask("Objectives", Widget, Entry and Entry.Position or nil, Entry and Entry.Label or "", ObjectiveColor)
            end
            local Garden = Globals.GardenArrows
            if Garden then
                local On = Toggles.HazardArrows.Value
                Ask("Hazards", Garden.Widgets[1], On and Garden.Hazard.Keeper or nil, "GROUNDSKEEPER", Color3.fromRGB(255, 60, 60))
                Ask("Hazards", Garden.Widgets[2], On and Garden.Hazard.Mandrake or nil, "MANDRAKE", Color3.fromRGB(255, 120, 40))
            end
            local First = Options.ArrowPriority and Options.ArrowPriority.Value or "Doors"
            local Rank, Next = { [First] = 0 }, 1
            for _, Name in Order do
                if Name ~= First then
                    Rank[Name] = Next
                    Next += 1
                end
            end
            table.sort(Requests, function(A, B)
                if A.Category ~= B.Category then return Rank[A.Category] < Rank[B.Category] end
                return A.Dist < B.Dist
            end)
            local Limit = Options.ArrowMax and math.floor(Options.ArrowMax.Value) or 8
            for Index, Request in Requests do
                if Index <= Limit then
                    PointArrow(Request.Widget, Request.Target, Request.Label, Request.Color)
                else
                    Request.Widget.Holder.Visible = false
                end
            end
        end

    local RenderConnection
    RenderConnection = RunService.RenderStepped:Connect(function()
        if not Alive then RenderConnection:Disconnect() return end
        ArrowFrame()
        Overlay.Visible = Toggles.SplitTimer.Value
        if Overlay.Visible then
            local Delta = LastDelta and string.format("%+.1fs", LastDelta) or "--"
            Overlay.Text = string.format("Room %s  %s  |  Run %s  |  Last %s", tostring(RoomValue and RoomValue.Value or "?"), Clock(tick() - RoomStart), Clock(tick() - RunStart), Delta)
        end
    end)
    end

    ---------------------------------------------------------------------
    -- Local challenge effects: Drunk Mode + Mirror World
    ---------------------------------------------------------------------
    do
        local Blur = New("BlurEffect", { Name = "AMRDrunkBlur", Enabled = false, Size = 0 }, Lighting)
        local SavedHud = setmetatable({}, { __mode = "k" })
        local LastYaw, LastCamera, BaseFOV, LastAppliedFOV, OffsetHumanoid, BaseOffset
        local LastHudScan = 0
        local RenderChecked = false

        local function WrapAngle(Value)
            return (Value + math.pi) % (math.pi * 2) - math.pi
        end

        local function CameraYaw(Frame)
            local Look = Frame.LookVector
            return math.atan2(-Look.X, -Look.Z)
        end

        local function ChallengeAllowed()
            if not Character or not Humanoid or Humanoid.Health <= 0 then return false end
            if LocalPlayer:GetAttribute("Alive") == false or Character:GetAttribute("Hiding") then return false end
            if Globals.RoomsAutoWalkActive or Functions.GetMinecart() then return false end
            return true
        end

        Globals.AMRChallengeMoveVector = function(Move)
            if typeof(Move) ~= "Vector3" or not ChallengeAllowed() then return Move end
            local Magnitude = Move.Magnitude
            if Toggles.ChallengeMirrorWorld.Value then Move = Vector3.new(-Move.X, Move.Y, Move.Z) end
            if Globals.AMREventInvert then Move = Vector3.new(-Move.X, Move.Y, -Move.Z) end
            if Toggles.ChallengeDrunkMode.Value and Magnitude > 0.001 then
                local Intensity = Options.ChallengeDrunkIntensity.Value / 100
                local Now = tick()
                local Drift = (math.sin(Now * 1.45) + math.sin(Now * 3.73) * 0.45) * 0.34 * Intensity
                local StaggerWave = math.max(0, math.sin(Now * 2.17 + math.sin(Now * 0.7) * 1.4))
                local Stagger = 1 - StaggerWave ^ 7 * 0.42 * Intensity
                Move = Vector3.new(Move.X + Drift * Magnitude, Move.Y, Move.Z * Stagger)
                if Move.Magnitude > Magnitude and Move.Magnitude > 0 then Move = Move.Unit * Magnitude end
            end
            return Move
        end

        local function MirrorObject(Object)
            if not Object:IsA("GuiObject") then return end
            local Data = SavedHud[Object]
            if Data then
                local PositionChanged = Object.Position ~= Data.AppliedPosition
                local AnchorChanged = Object.AnchorPoint ~= Data.AppliedAnchorPoint
                if not PositionChanged and not AnchorChanged then return end
                if PositionChanged then Data.Position = Object.Position end
                if AnchorChanged then Data.AnchorPoint = Object.AnchorPoint end
            else
                Data = { Position = Object.Position, AnchorPoint = Object.AnchorPoint }
                SavedHud[Object] = Data
            end
            Data.AppliedAnchorPoint = Vector2.new(1 - Data.AnchorPoint.X, Data.AnchorPoint.Y)
            Data.AppliedPosition = UDim2.new(1 - Data.Position.X.Scale, -Data.Position.X.Offset, Data.Position.Y.Scale, Data.Position.Y.Offset)
            Object.AnchorPoint = Data.AppliedAnchorPoint
            Object.Position = Data.AppliedPosition
        end

        local function MirrorContainer(Container)
            if not Container then return end
            for _, Object in Container:GetChildren() do MirrorObject(Object) end
        end

        local function ApplyMirroredHud()
            local MainUI = Globals.MainUI
            MirrorContainer(MainUI and MainUI:FindFirstChild("MainFrame"))
            MirrorContainer(OverlayGui)
            local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            MirrorContainer(PlayerGui and PlayerGui:FindFirstChild("PermUI"))
            MirrorContainer(PlayerGui and PlayerGui:FindFirstChild("TopbarUI"))
        end

        local function RestoreHud()
            for Object, Data in SavedHud do
                if Object.Parent then
                    if Object.Position == Data.AppliedPosition then Object.Position = Data.Position end
                    if Object.AnchorPoint == Data.AppliedAnchorPoint then Object.AnchorPoint = Data.AnchorPoint end
                end
                SavedHud[Object] = nil
            end
        end

        local function RestoreCameraEffects()
            local CurrentCamera = workspace.CurrentCamera
            if CurrentCamera and LastAppliedFOV and BaseFOV and math.abs(CurrentCamera.FieldOfView - LastAppliedFOV) < 0.75 then
                CurrentCamera.FieldOfView = BaseFOV
            end
            if OffsetHumanoid and OffsetHumanoid.Parent and BaseOffset then OffsetHumanoid.CameraOffset = BaseOffset end
            Blur.Enabled, Blur.Size = false, 0
            LastYaw, LastCamera, BaseFOV, LastAppliedFOV, OffsetHumanoid, BaseOffset = nil, nil, nil, nil, nil, nil
        end

        local function ChallengeFrame()
            if not Alive then return end
            local Drunk = Toggles.ChallengeDrunkMode.Value
            local Mirror = Toggles.ChallengeMirrorWorld.Value
            local CurrentCamera = workspace.CurrentCamera
            if not CurrentCamera then return end

            if Mirror then
                if tick() - LastHudScan > 0.5 then LastHudScan = tick() ApplyMirroredHud() end
            elseif next(SavedHud) then
                RestoreHud()
            end

            local Allowed = ChallengeAllowed() and not (Globals.Freeze and Globals.Freeze.ImportedFreecam)
            if Mirror and Allowed then
                local RawYaw = CameraYaw(CurrentCamera.CFrame)
                if LastCamera == CurrentCamera and LastYaw then
                    local Delta = WrapAngle(RawYaw - LastYaw)
                    if math.abs(Delta) < 0.45 then
                        local Rotation = CFrame.fromAxisAngle(Vector3.yAxis, -2 * Delta)
                        local Focus = CurrentCamera.Focus.Position
                        local Position = Focus + Rotation:VectorToWorldSpace(CurrentCamera.CFrame.Position - Focus)
                        local Orientation = Rotation * (CurrentCamera.CFrame - CurrentCamera.CFrame.Position)
                        CurrentCamera.CFrame = CFrame.new(Position) * Orientation
                    end
                end
                LastYaw, LastCamera = CameraYaw(CurrentCamera.CFrame), CurrentCamera
            else
                LastYaw, LastCamera = nil, CurrentCamera
            end

            if Drunk and Allowed then
                local Intensity = Options.ChallengeDrunkIntensity.Value / 100
                local Now = tick()
                local Roll = math.rad(3.8) * Intensity * (math.sin(Now * 1.25) + 0.35 * math.sin(Now * 3.1))
                local Pitch = math.rad(1.4) * Intensity * math.sin(Now * 1.73 + 0.8)
                CurrentCamera.CFrame = CurrentCamera.CFrame * CFrame.Angles(Pitch, 0, Roll)

                if Humanoid ~= OffsetHumanoid then
                    if OffsetHumanoid and OffsetHumanoid.Parent and BaseOffset then OffsetHumanoid.CameraOffset = BaseOffset end
                    OffsetHumanoid, BaseOffset = Humanoid, Humanoid.CameraOffset
                end
                Humanoid.CameraOffset = BaseOffset + Vector3.new(math.sin(Now * 1.8) * 0.35 * Intensity, math.sin(Now * 2.35) * 0.16 * Intensity, 0)

                local CurrentFOV = CurrentCamera.FieldOfView
                if not LastAppliedFOV or math.abs(CurrentFOV - LastAppliedFOV) > 0.75 then BaseFOV = CurrentFOV end
                if Toggles.FOVToggle and Toggles.FOVToggle.Value then BaseFOV = Options.FieldOfView.Value end
                BaseFOV = BaseFOV or CurrentFOV
                LastAppliedFOV = math.clamp(BaseFOV + math.sin(Now * 1.15) * 4.5 * Intensity, 1, 120)
                CurrentCamera.FieldOfView = LastAppliedFOV

                local AntiLag = Toggles.AntiLag and Toggles.AntiLag.Value
                Blur.Enabled = not AntiLag
                Blur.Size = Blur.Enabled and (5 + 15 * Intensity * (0.75 + 0.25 * math.sin(Now * 1.6))) or 0
            else
                if OffsetHumanoid and OffsetHumanoid.Parent and BaseOffset then OffsetHumanoid.CameraOffset = BaseOffset end
                OffsetHumanoid, BaseOffset = nil, nil
                if LastAppliedFOV and BaseFOV and math.abs(CurrentCamera.FieldOfView - LastAppliedFOV) < 0.75 then CurrentCamera.FieldOfView = BaseFOV end
                BaseFOV, LastAppliedFOV = nil, nil
                Blur.Enabled, Blur.Size = false, 0
            end

            -- true picture flip: negate the camera's Right column (determinant -1), applied last so nothing re-reads it
            if Mirror and Allowed and Toggles.ChallengeMirrorRender and Toggles.ChallengeMirrorRender.Value then
                local X, Y, Z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = CurrentCamera.CFrame:GetComponents()
                CurrentCamera.CFrame = CFrame.new(X, Y, Z, -R00, R01, R02, -R10, R11, R12, -R20, R21, R22)
                if not RenderChecked then
                    RenderChecked = true
                    local Read = CurrentCamera.CFrame
                    local Flipped = Read.RightVector:Dot(Read.LookVector:Cross(Read.UpVector)) < 0
                    Functions.Notify({
                        Title = "Mirror Render",
                        Body = Flipped and "Camera matrix flipped. If the picture looks broken, switch Mirror Render off." or "This executor normalises the camera matrix, the picture cannot be flipped.",
                        Time = 5
                    })
                end
            end
        end

        pcall(function() RunService:UnbindFromRenderStep("AMRChallengeCamera") end)
        RunService:BindToRenderStep("AMRChallengeCamera", Enum.RenderPriority.Last.Value + 100, ChallengeFrame)
        Toggles.ChallengeMirrorWorld:OnChanged(function(Value)
            if Value then
                Functions.Notify({ Title = "Mirror World", Body = "Movement, camera yaw and HUD layout are mirrored. Mirror Render flips the 3D picture.", Time = 5 })
                ApplyMirroredHud()
            else
                RestoreHud()
                LastYaw = nil
                RenderChecked = false
            end
        end)
        Toggles.ChallengeDrunkMode:OnChanged(function(Value)
            if not Value then RestoreCameraEffects() end
        end)
        pcall(function() Library:OnUnload(function()
            Globals.AMRChallengeMoveVector = nil
            pcall(function() RunService:UnbindFromRenderStep("AMRChallengeCamera") end)
            RestoreHud()
            RestoreCameraEffects()
            if Blur then Blur:Destroy() end
        end) end)
    end

    ---------------------------------------------------------------------
    -- Colour filters, photo mode
    ---------------------------------------------------------------------
    Groupboxes.Visuals_Experimental:AddDropdown("ColorFilter", {
        Text = "Colour Filter", Values = { "Off", "High Contrast", "Warm", "Cool", "Grayscale" }, Default = 1,
        Tooltip = "Visual aids. These are simple colour adjustments, not an exact colour-blindness simulation."
    })
    local Filter = New("ColorCorrectionEffect", { Name = "AMRFilter", Enabled = false }, Lighting)

    local function ApplyFilter()
        local Mode = Options.ColorFilter.Value
        Filter.TintColor, Filter.Contrast, Filter.Saturation, Filter.Brightness = Color3.new(1, 1, 1), 0, 0, 0
        if Mode == "High Contrast" then
            Filter.Contrast, Filter.Saturation = 0.4, 0.3
        elseif Mode == "Warm" then
            Filter.TintColor = Color3.fromRGB(255, 235, 205)
        elseif Mode == "Cool" then
            Filter.TintColor = Color3.fromRGB(205, 225, 255)
        elseif Mode == "Grayscale" then
            Filter.Saturation = -1
        end
        Filter.Enabled = Mode ~= "Off"
    end
    Options.ColorFilter:OnChanged(ApplyFilter)
    Groupboxes.Visuals_Experimental:AddToggle("PhotoMode", {
        Text = "Photo Mode", Default = false,
        Tooltip = "Hides the game UI, the hotbar and overlays. Use Custom FOV for any field of view."
    })
    local HiddenGuis = {}
    Toggles.PhotoMode:OnChanged(function(Value)
        HotbarGui.Enabled = not Value
        SearchGui.Enabled = not Value
        OverlayGui.Enabled = not Value
        local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if Value and PlayerGui then
            for _, Gui in PlayerGui:GetChildren() do
                if Gui:IsA("ScreenGui") and Gui.Enabled then
                    HiddenGuis[#HiddenGuis + 1] = Gui
                    Gui.Enabled = false
                end
            end
        else
            for _, Gui in HiddenGuis do
                if Gui.Parent then Gui.Enabled = true end
            end
            HiddenGuis = {}
        end
    end)

    ---------------------------------------------------------------------
    -- Entity sound swap (only changes what you hear)
    ---------------------------------------------------------------------
    Groupboxes.Visuals_Experimental:AddDropdown("EntitySoundSwap", {
        Text = "Entity Sounds", Values = { "Off", "Chipmunk", "Deep", "Mute" }, Default = 1,
        Tooltip = "Changes how entities sound for you only. Applies to entities that spawn after you pick it."
    })
    local function ApplySound(Sound)
        local Mode = Options.EntitySoundSwap.Value
        local Old = Sound:FindFirstChild("AMRPitch")
        if Old then Old:Destroy() end
        if Mode == "Chipmunk" or Mode == "Deep" then
            New("PitchShiftSoundEffect", { Name = "AMRPitch", Octave = Mode == "Chipmunk" and 2 or 0.5 }, Sound)
        elseif Mode == "Mute" then
            Sound.Volume = 0
        end
    end
    workspace.ChildAdded:Connect(function(Object)
        if Options.EntitySoundSwap.Value == "Off" then return end
        if not (string.find(Object.Name, "Moving$") or EntityNames[Object.Name]) then return end
        for _, Descendant in Object:GetDescendants() do
            if Descendant:IsA("Sound") then ApplySound(Descendant) end
        end
        Object.DescendantAdded:Connect(function(Descendant)
            if Descendant:IsA("Sound") then ApplySound(Descendant) end
        end)
    end)

    ---------------------------------------------------------------------
    -- ORBIT EFFECTS: one engine on top of "Orbit Dropped Items".
    -- The old Heartbeat loop (Stairwell > Experimental) builds the drops list and calls Boot.OrbitStep(list, root, dt, now).
    -- Pure Ring with no overlays: OrbitStep returns false and the old loop runs untouched (its own 10 s refresh).
    -- Everything else (Tornado, Cradle, Wave, Singularity, Trail, Text, Door marker, Ghost) runs here: ONE loop, ONE drops list.
    ---------------------------------------------------------------------
    do
        local TweenService = game:GetService("TweenService")
        local TAU = math.pi * 2
        local ZERO = Vector3.new(0, 0, 0)
        local UP = Vector3.new(0, 1, 0)
        local IDENT = CFrame.new()

        local Orbit = {
            Angle = 0, Face = Vector3.new(0, 0, -1), LastRefresh = tick(), Hold = 0,
            Sing = nil, WantPlay = false, NextPlay = nil, ShakeAmp = 0, Warned = {}, Dead = false,
            Wall = nil, WantWall = false, Drone = nil, WantDrone = false,
            Trail = { Points = {}, Sample = 0, Last = nil, Room = nil },
            Roles = { door = {}, ghost = {} }, DoorPos = nil, DoorAt = 0, TextLast = nil,
            G = { Best = {}, Room = nil, T0 = nil, St = {}, Sf = {}, F = 0, E = nil, X = nil, Dirty = false, LastSave = 0, Valid = true },
        }
        Boot.Orbit = Orbit
        local Items = setmetatable({}, { __mode = "k" })
        local Prim = setmetatable({}, { __mode = "k" })
        local PoolSet, FreeSet = {}, {}

        local function Warn(Key, Body)
            local Now = tick()
            if Orbit.Warned[Key] and Now - Orbit.Warned[Key] < 8 then return end
            Orbit.Warned[Key] = Now
            Functions.Notify({ Title = "Orbit Effects", Body = Body })
        end

        ---------------------------------------------------------------- UI
        Groupboxes.Stairwell_Orbit = Tabs.Stairwell:AddRightGroupbox("Orbit Effects")
        local Box = Groupboxes.Stairwell_Orbit
        Box:AddDropdown("OrbitEffect", {
            Text = "Orbit Effect", Values = { "Ring", "Tornado", "Cradle", "Wave", "Singularity", "Wall Slam", "FPV Drone", "Trail", "Text" }, Default = 1,
            Tooltip = "How the dropped items move. Picking anything but Ring turns Orbit Dropped Items on. Needs 3+ drops (FPV 5+, Text 6+)."
        })
        Box:AddSlider("OrbitRefresh", { Text = "Refresh Every (s)", Default = 10, Min = 4, Max = 30, Rounding = 0, Compact = true, Tooltip = "Teleports items onto you for a moment so they do not despawn (effects only; plain Ring keeps its own timer)." })
        Box:AddButton({ Text = "Stop / Reset Effect", Func = function()
            Orbit.Sing, Orbit.WantPlay, Orbit.NextPlay = nil, false, nil
            Orbit.Wall, Orbit.WantWall, Orbit.Drone, Orbit.WantDrone = nil, false, nil, false
            Orbit.Trail.Points = {}
            Orbit.Roles = { door = {}, ghost = {} }
            Orbit.ShakeAmp = 0
            pcall(function() RunService:UnbindFromRenderStep("AMRSingShake") end)
        end })
        Box:AddDivider()
        Box:AddLabel("Singularity")
        Box:AddButton({ Text = "Singularity: play", Func = function() Orbit.Play() end, Tooltip = "Gather, clump, spin up, BOOM, scatter, back to the ring." })
        Box:AddToggle("SingRepeat", { Text = "Repeat", Default = false })
        Box:AddToggle("SingFlash", { Text = "Screen Flash", Default = true })
        Box:AddToggle("SingCam", { Text = "Camera Shake", Default = false })
        Box:AddSlider("SingGather", { Text = "Gather (s)", Default = 4, Min = 1, Max = 12, Rounding = 1, Compact = true })
        Box:AddSlider("SingClump", { Text = "Clump (s)", Default = 1.5, Min = 0.5, Max = 5, Rounding = 1, Compact = true })
        Box:AddSlider("SingSpin", { Text = "Spin-up (s)", Default = 2.5, Min = 0.5, Max = 8, Rounding = 1, Compact = true })
        Box:AddSlider("SingScatter", { Text = "Scatter (s)", Default = 6, Min = 2, Max = 15, Rounding = 1, Compact = true })
        Box:AddSlider("SingPower", { Text = "Explosion Strength", Default = 70, Min = 20, Max = 200, Rounding = 0, Compact = true })
        Box:AddSlider("SingDist", { Text = "Ball Distance", Default = 10, Min = 4, Max = 30, Rounding = 0, Compact = true })
        Box:AddDivider()
        Box:AddLabel("Wall Slam")
        Box:AddButton({ Text = "Wall Slam: play", Func = function() Orbit.PlayWallSlam() end, Tooltip = "Forms every drop into one clump in front of you. Sweep it into a wall to trigger the Singularity explosion." })
        Box:AddSlider("WallSlamGather", { Text = "Gather (s)", Default = 1.2, Min = 0.3, Max = 4, Rounding = 1, Compact = true })
        Box:AddSlider("WallSlamReach", { Text = "Reach", Default = 9, Min = 4, Max = 25, Rounding = 1, Compact = true })
        Box:AddSlider("WallSlamHeight", { Text = "Height", Default = 3.5, Min = 1, Max = 10, Rounding = 1, Compact = true })
        Box:AddSlider("WallSlamSpeed", { Text = "Control Speed", Default = 32, Min = 8, Max = 80, Rounding = 0, Compact = true })
        Box:AddSlider("WallSlamTimeout", { Text = "Timeout (s)", Default = 12, Min = 3, Max = 30, Rounding = 0, Compact = true })
        Box:AddDivider()
        Box:AddLabel("FPV Drone")
        Box:AddButton({ Text = "FPV Drone: launch", Func = function() Orbit.PlayFPVDrone() end, Tooltip = "Forms a dropped-item drone that flies at you and bursts beside you. Visual effect only." })
        Box:AddDropdown("FPVDroneTarget", { Text = "Target", Values = { "Self" }, Default = 1 })
        Box:AddSlider("FPVDroneForm", { Text = "Form (s)", Default = 1.5, Min = 0.5, Max = 5, Rounding = 1, Compact = true })
        Box:AddSlider("FPVDroneSpeed", { Text = "Flight Speed", Default = 35, Min = 8, Max = 100, Rounding = 0, Compact = true })
        Box:AddSlider("FPVDroneScale", { Text = "Drone Size", Default = 2.2, Min = 1, Max = 6, Rounding = 1, Compact = true })
        Box:AddSlider("FPVDroneHeight", { Text = "Target Height", Default = 3, Min = 1, Max = 10, Rounding = 1, Compact = true })
        Box:AddSlider("FPVDroneArrival", { Text = "Burst Distance", Default = 3, Min = 1, Max = 8, Rounding = 1, Compact = true })
        Box:AddSlider("FPVDroneTimeout", { Text = "Timeout (s)", Default = 25, Min = 5, Max = 60, Rounding = 0, Compact = true })
        Box:AddDivider()
        Box:AddLabel("Tornado")
        Box:AddSlider("TornadoHeight", { Text = "Height", Default = 14, Min = 4, Max = 40, Rounding = 0, Compact = true })
        Box:AddSlider("TornadoRadius", { Text = "Top Radius", Default = 10, Min = 3, Max = 40, Rounding = 0, Compact = true })
        Box:AddSlider("TornadoSpeed", { Text = "Speed", Default = 3, Min = 0.5, Max = 12, Rounding = 1, Compact = true })
        Box:AddDivider()
        Box:AddLabel("Newton's Cradle (5 items)")
        Box:AddSlider("CradleSpacing", { Text = "Spacing", Default = 2, Min = 1, Max = 5, Rounding = 1, Compact = true })
        Box:AddSlider("CradleAngle", { Text = "Swing Angle", Default = 40, Min = 10, Max = 80, Rounding = 0, Compact = true })
        Box:AddSlider("CradleSpeed", { Text = "Speed", Default = 3, Min = 0.5, Max = 10, Rounding = 1, Compact = true })
        Box:AddDivider()
        Box:AddLabel("Wave")
        Box:AddDropdown("WaveLayout", { Text = "Layout", Values = { "Grid", "Line" }, Default = 1 })
        Box:AddSlider("WaveAmp", { Text = "Amplitude", Default = 3, Min = 0.5, Max = 12, Rounding = 1, Compact = true })
        Box:AddSlider("WaveLength", { Text = "Wavelength", Default = 10, Min = 3, Max = 40, Rounding = 1, Compact = true })
        Box:AddSlider("WaveSpeed", { Text = "Speed", Default = 3, Min = 0.5, Max = 12, Rounding = 1, Compact = true })
        Box:AddSlider("WaveSpacing", { Text = "Spacing", Default = 2.2, Min = 1, Max = 6, Rounding = 1, Compact = true })
        Box:AddDivider()
        Box:AddLabel("Trail (effect: Trail)")
        Box:AddSlider("TrailLife", { Text = "Tail Lives (s)", Default = 20, Min = 3, Max = 60, Rounding = 0, Compact = true, Tooltip = "Also melts when you enter the next room." })
        Box:AddSlider("TrailSpacing", { Text = "Spacing", Default = 2.5, Min = 1, Max = 8, Rounding = 1, Compact = true })
        Box:AddSlider("TrailHeight", { Text = "Height", Default = 0, Min = -5, Max = 10, Rounding = 1, Compact = true })
        Box:AddDivider()
        Box:AddLabel("Text (effect: Text)")
        Box:AddInput("OrbitText", { Text = "Text", Default = "GG", Placeholder = "A-Z 0-9 ! ? . - + *", Finished = false, Tooltip = "Up to 12 characters, spelled out above you. * is a heart. Needs about 8 drops per letter." })
        Box:AddSlider("TextHeight", { Text = "Height Above You", Default = 7, Min = 2, Max = 20, Rounding = 1, Compact = true })
        Box:AddSlider("TextScale", { Text = "Dot Spacing", Default = 1.2, Min = 0.6, Max = 3, Rounding = 1, Compact = true })
        Box:AddDivider()
        Box:AddLabel("Markers")
        Box:AddToggle("DoorMark", { Text = "Door Marker", Default = false, Tooltip = "A small orbit of items over the correct door (same target as Door Arrow)." })
        Box:AddSlider("DoorMarkCount", { Text = "Marker Items", Default = 4, Min = 3, Max = 6, Rounding = 0, Compact = true })
        Box:AddSlider("DoorMarkHeight", { Text = "Marker Height", Default = 7, Min = 3, Max = 15, Rounding = 1, Compact = true })
        Box:AddToggle("BestRunGhost", { Text = "Best-Run Ghost", Default = false, Tooltip = "Records your time per room (as a fraction along entry door to exit). Next time in that room a ghost of 3 items replays your best run and shows ahead/behind." })

        Box:AddDivider()
        Box:AddLabel("Gold Rain")
        Box:AddToggle("GoldRain", { Text = "Gold Rain", Default = false, Tooltip = "Every time you get currency (GetCurrency from the server) the items shoot up like a fountain and come back." })
        Box:AddSlider("GoldRainPower", { Text = "Fountain Power", Default = 45, Min = 15, Max = 100, Rounding = 0, Compact = true })
        Box:AddSlider("GoldRainTime", { Text = "Fountain Time (s)", Default = 2.5, Min = 1, Max = 6, Rounding = 1, Compact = true })
        Box:AddDivider()
        Box:AddLabel("Presets & Hotkey")
        Box:AddToggle("SingHotkey", { Text = "Singularity Hotkey", Default = false, Tooltip = "Pick a key with the button next to the toggle: pressing it plays the Singularity." })
        Toggles.SingHotkey:AddKeyPicker("SingHotkeyKey", { Text = "Singularity", Default = "None", Mode = "Toggle", SyncToggleState = true })
        Box:AddInput("OrbitPresetName", { Text = "Preset Name", Default = "", Placeholder = "my preset", Finished = false })
        Box:AddDropdown("OrbitPresetList", { Text = "Presets", Values = {}, Default = nil, AllowNull = true })
        local PresetOptions = {
            "OrbitRefresh", "OrbitDroppedItemsHeight", "OrbitDroppedItemsDistance", "OrbitDroppedItemsSpeed",
            "SingGather", "SingClump", "SingSpin", "SingScatter", "SingPower", "SingDist",
            "WallSlamGather", "WallSlamReach", "WallSlamHeight", "WallSlamSpeed", "WallSlamTimeout",
            "FPVDroneTarget", "FPVDroneForm", "FPVDroneSpeed", "FPVDroneScale", "FPVDroneHeight", "FPVDroneArrival", "FPVDroneTimeout",
            "TornadoHeight", "TornadoRadius", "TornadoSpeed", "CradleSpacing", "CradleAngle", "CradleSpeed",
            "WaveLayout", "WaveAmp", "WaveLength", "WaveSpeed", "WaveSpacing", "TrailLife", "TrailSpacing", "TrailHeight",
            "OrbitText", "TextHeight", "TextScale", "DoorMarkCount", "DoorMarkHeight", "GoldRainPower", "GoldRainTime",
        }
        local PresetToggles = { "SingRepeat", "SingFlash", "SingCam", "GoldRain" }
        local Presets = {}
        do
            local Data = Load("OrbitPresets.json")
            if type(Data) == "table" then Presets = Data end
        end
        local function PresetNames()
            local Names = {}
            for Name in Presets do Names[#Names + 1] = Name end
            table.sort(Names)
            return Names
        end
        local function PresetName()
            local Typed = string.sub(string.gsub(tostring(Options.OrbitPresetName.Value or ""), "^%s*(.-)%s*$", "%1"), 1, 24)
            if Typed ~= "" then return Typed end
            return Options.OrbitPresetList.Value
        end
        pcall(function() Options.OrbitPresetList:SetValues(PresetNames()) end)
        Box:AddButton({ Text = "Save Preset", Func = function()
            local Name = PresetName()
            if not Name or Name == "" then Functions.Notify({ Title = "Orbit Presets", Body = "Type a preset name first." }) return end
            local Entry = { Effect = Options.OrbitEffect.Value, Options = {}, Toggles = {} }
            for _, Key in PresetOptions do
                local Option = Options[Key]
                if Option then Entry.Options[Key] = Option.Value end
            end
            for _, Key in PresetToggles do
                if Toggles[Key] then Entry.Toggles[Key] = Toggles[Key].Value end
            end
            Presets[Name] = Entry
            Save("OrbitPresets.json", Presets)
            pcall(function() Options.OrbitPresetList:SetValues(PresetNames()) end)
            Functions.Notify({ Title = "Orbit Presets", Body = "Saved '" .. Name .. "'." })
        end })
        Box:AddButton({ Text = "Load Preset", Func = function()
            local Name = Options.OrbitPresetList.Value
            local Entry = Name and Presets[Name]
            if type(Entry) ~= "table" then Functions.Notify({ Title = "Orbit Presets", Body = "Pick a preset in the list." }) return end
            for Key, Value in Entry.Options or {} do
                if Options[Key] then pcall(function() Options[Key]:SetValue(Value) end) end
            end
            for Key, Value in Entry.Toggles or {} do
                if Toggles[Key] then pcall(function() Toggles[Key]:SetValue(Value) end) end
            end
            if Entry.Effect then pcall(function() Options.OrbitEffect:SetValue(Entry.Effect) end) end
            Functions.Notify({ Title = "Orbit Presets", Body = "Loaded '" .. Name .. "'." })
        end })
        Box:AddButton({ Text = "Delete Preset", Func = function()
            local Name = Options.OrbitPresetList.Value
            if not Name or not Presets[Name] then return end
            Presets[Name] = nil
            Save("OrbitPresets.json", Presets)
            pcall(function() Options.OrbitPresetList:SetValues(PresetNames()) end)
            Functions.Notify({ Title = "Orbit Presets", Body = "Deleted '" .. Name .. "'." })
        end })

        ---------------------------------------------------------------- item helpers
        local function St(Object)
            local State = Items[Object]
            if not State then
                State = { Rot = IDENT, Kind = "", G = 1, GD = 1 }
                Items[Object] = State
            end
            return State
        end
        local function GetPos(Object)
            if Object:IsA("Model") then return Object:GetPivot().Position end
            return Object.Position
        end
        local function Place(Object, Frame)
            if Object:IsA("Model") then
                Object:PivotTo(Frame)
                local Part = Prim[Object]
                if Part == nil or (Part and not Part.Parent) then
                    Part = Object.PrimaryPart or Object:FindFirstChildWhichIsA("BasePart", true) or false
                    Prim[Object] = Part
                end
                if Part then Part.AssemblyLinearVelocity = ZERO Part.AssemblyAngularVelocity = ZERO end
            else
                Object.CFrame = Frame
                Object.AssemblyLinearVelocity = ZERO
                Object.AssemblyAngularVelocity = ZERO
            end
        end
        -- Kind change = glide from where the item really is (0.6 s unless told otherwise) so formations flow into each other
        local function Put(Object, State, Target, Kind, Dt, Rot, Gd)
            if State.Kind ~= Kind then
                State.Kind = Kind
                State.From = GetPos(Object)
                State.G = 0
                State.GD = State.NextGD or Gd or 0.6
                State.NextGD = nil
            end
            local Position = Target
            if State.G < State.GD then
                State.G += Dt
                local A = math.min(State.G / State.GD, 1)
                Position = State.From:Lerp(Target, A * A * (3 - 2 * A))
            end
            if not Rot then
                State.Rot = State.Rot:Lerp(IDENT, 1 - math.exp(-4 * Dt))
                Rot = State.Rot
            end
            State.Last = Position
            Place(Object, CFrame.new(Position) * Rot)
        end

        local function RingPlace(List, Center, Dt)
            local Count = #List
            if Count == 0 then return end
            local Height, Distance = Options.OrbitDroppedItemsHeight.Value, Options.OrbitDroppedItemsDistance.Value
            for Index, Object in ipairs(List) do
                local Angle = Orbit.Angle + (Index - 1) / Count * TAU
                Put(Object, St(Object), Center + Vector3.new(math.cos(Angle) * Distance, Height, math.sin(Angle) * Distance), "ring", Dt)
            end
        end

        ---------------------------------------------------------------- Tornado
        local function Tornado(List, Center, Dt, Now)
            local Count = #List
            local Height, Radius, Speed = Options.TornadoHeight.Value, Options.TornadoRadius.Value, Options.TornadoSpeed.Value
            for Index, Object in ipairs(List) do
                local State = St(Object)
                local U = (Index - 1) / Count
                local F = 0.5 - 0.5 * math.cos(TAU * (U + Now * 0.05)) -- slow rise and fall
                local R = 1.5 + (Radius - 1.5) * F
                State.Ang = (State.Ang or U * TAU * 3) + Dt * Speed * (1.8 - 1.2 * F) -- fast at the bottom
                Put(Object, State, Center + Vector3.new(math.cos(State.Ang) * R, F * Height - 3, math.sin(State.Ang) * R), "tornado", Dt)
            end
        end

        ---------------------------------------------------------------- Cradle (first 5 items, rest ring)
        local function Cradle(List, Center, Dt, Now)
            local Count = math.min(5, #List)
            local Spacing, Angle, Speed = Options.CradleSpacing.Value, math.rad(Options.CradleAngle.Value), Options.CradleSpeed.Value
            local Distance = Options.OrbitDroppedItemsDistance.Value
            local Forward = Orbit.Face
            local Right = Forward:Cross(UP)
            local Length = 6
            local Sine = math.sin(Now * Speed)
            local Left, Rightward = Angle * math.max(0, -Sine), Angle * math.max(0, Sine)
            for Index = 1, Count do
                local Pivot = Center + Forward * Distance + Right * ((Index - (Count + 1) / 2) * Spacing)
                Pivot = Vector3.new(Pivot.X, Center.Y + 1 + Length, Pivot.Z)
                local Swing = 0
                if Index == 1 then Swing = -Left elseif Index == Count then Swing = Rightward end
                local Object = List[Index]
                Put(Object, St(Object), Pivot + Right * (Length * math.sin(Swing)) + Vector3.new(0, -Length * math.cos(Swing), 0), "cradle", Dt)
            end
            local Rest = {}
            for Index = Count + 1, #List do Rest[#Rest + 1] = List[Index] end
            RingPlace(Rest, Center, Dt)
        end

        ---------------------------------------------------------------- Wave
        local function Wave(List, Center, Dt, Now)
            local Count = #List
            local Amp, Length, Speed, Spacing = Options.WaveAmp.Value, Options.WaveLength.Value, Options.WaveSpeed.Value, Options.WaveSpacing.Value
            local Grid = Options.WaveLayout.Value == "Grid"
            local Rows, Cols = 1, Count
            if Grid then
                Rows = math.ceil(math.sqrt(Count))
                Cols = math.ceil(Count / Rows)
            end
            local Forward = Orbit.Face
            local Right = Forward:Cross(UP)
            local Distance, Height = Options.OrbitDroppedItemsDistance.Value, Options.OrbitDroppedItemsHeight.Value
            for Index, Object in ipairs(List) do
                local Zero = Index - 1
                local Row = math.floor(Zero / Cols)
                local Col = Zero % Cols
                local X = (Col - (Cols - 1) / 2) * Spacing
                local Z = Row * Spacing
                local Y
                if Grid then
                    Y = Amp * math.sin(TAU * Z / Length - Now * Speed) + Amp * 0.35 * math.sin(TAU * X / (Length * 1.3) + Now * Speed * 0.6)
                else
                    Y = Amp * math.sin(TAU * X / Length - Now * Speed)
                end
                local Position = Center + Forward * (Distance + Z) + Right * X
                Put(Object, St(Object), Vector3.new(Position.X, Center.Y + Height + Y, Position.Z), "wave", Dt)
            end
        end

        ---------------------------------------------------------------- Text (3x5 dot font)
        local Font = {
            A = ".#.|#.#|###|#.#|#.#", B = "##.|#.#|##.|#.#|##.", C = ".##|#..|#..|#..|.##", D = "##.|#.#|#.#|#.#|##.",
            E = "###|#..|##.|#..|###", F = "###|#..|##.|#..|#..", G = ".##|#..|#.#|#.#|.##", H = "#.#|#.#|###|#.#|#.#",
            I = "###|.#.|.#.|.#.|###", J = "..#|..#|..#|#.#|.#.", K = "#.#|#.#|##.|#.#|#.#", L = "#..|#..|#..|#..|###",
            M = "#.#|###|###|#.#|#.#", N = "###|#.#|#.#|#.#|#.#", O = ".#.|#.#|#.#|#.#|.#.", P = "##.|#.#|##.|#..|#..",
            Q = ".#.|#.#|#.#|.##|..#", R = "##.|#.#|##.|#.#|#.#", S = ".##|#..|.#.|..#|##.", T = "###|.#.|.#.|.#.|.#.",
            U = "#.#|#.#|#.#|#.#|###", V = "#.#|#.#|#.#|#.#|.#.", W = "#.#|#.#|###|###|#.#", X = "#.#|#.#|.#.|#.#|#.#",
            Y = "#.#|#.#|.#.|.#.|.#.", Z = "###|..#|.#.|#..|###",
            ["0"] = "###|#.#|#.#|#.#|###", ["1"] = ".#.|##.|.#.|.#.|###", ["2"] = "##.|..#|.#.|#..|###", ["3"] = "##.|..#|.#.|..#|##.",
            ["4"] = "#.#|#.#|###|..#|..#", ["5"] = "###|#..|##.|..#|##.", ["6"] = ".##|#..|###|#.#|###", ["7"] = "###|..#|.#.|.#.|.#.",
            ["8"] = "###|#.#|###|#.#|###", ["9"] = "###|#.#|###|..#|##.",
            ["!"] = ".#.|.#.|.#.|...|.#.", ["?"] = "##.|..#|.#.|...|.#.", ["."] = "...|...|...|...|.#.", ["-"] = "...|...|###|...|...",
            ["+"] = "...|.#.|###|.#.|...", ["*"] = "#.#|###|###|.#.|...",
        }
        local Banned = { "fuck", "shit", "cunt", "bitch", "nazi", "rape", "porn", "sex", "dick", "cock", "pussy", "nigg", "fag", "hitler", "kys", "slut", "whore" }
        local function CleanText(Raw)
            local Text = string.upper((string.gsub(tostring(Raw or ""), "[^%w!%?%.%-%+%* ]", "")))
            Text = string.sub(Text, 1, 12)
            local Flat = string.lower((string.gsub((string.gsub(Text, "[%s%p]", "")), "0", "o")))
            Flat = (string.gsub((string.gsub((string.gsub(Flat, "1", "i")), "3", "e")), "4", "a"))
            for _, Word in Banned do
                if string.find(Flat, Word, 1, true) then return nil end
            end
            return Text
        end
        local TextCache = {}
        local function TextPoints(Text)
            local Cached = TextCache[Text]
            if Cached then return Cached end
            local Points = {}
            local Length = #Text
            for Index = 1, Length do
                local Glyph = Font[string.sub(Text, Index, Index)]
                if Glyph then
                    local Row = 0
                    for Line in string.gmatch(Glyph, "[^|]+") do
                        Row += 1
                        for Col = 1, 3 do
                            if string.sub(Line, Col, Col) == "#" then
                                Points[#Points + 1] = { (Col - 1) + 4 * (Index - 1) - (4 * Length - 1 - 1) / 2, 5 - Row - 2 }
                            end
                        end
                    end
                end
            end
            TextCache[Text] = Points
            return Points
        end
        local function TextStep(List, Center, Dt, Now)
            local Text = CleanText(Options.OrbitText.Value)
            if not Text then Warn("text", "That text is not allowed.") RingPlace(List, Center, Dt) return end
            local Points = TextPoints(Text)
            local Total, Count = #Points, #List
            if Total == 0 then RingPlace(List, Center, Dt) return end
            if Orbit.TextLast ~= Text then
                Orbit.TextLast = Text
                for _, Object in ipairs(List) do St(Object).Kind = "" end -- glide into the new word
            end
            if Total > Count then Warn("textfit", string.format("Text needs %d drops, have %d. Showing part of it.", Total, Count)) end
            local Forward = Orbit.Face
            local Right = Forward:Cross(UP)
            local Base = Center + Forward * Options.OrbitDroppedItemsDistance.Value + UP * Options.TextHeight.Value
            local Scale = Options.TextScale.Value
            local Used = math.min(Total, Count)
            for Index = 1, Used do
                local Point = Points[Total > Count and (math.floor((Index - 1) * Total / Count) + 1) or Index]
                local Object = List[Index]
                local Position = Base + Right * (Point[1] * Scale) + UP * (Point[2] * Scale + math.sin(Now * 2 + Index) * 0.05)
                Put(Object, St(Object), Position, "text", Dt)
            end
            local Rest = {}
            for Index = Used + 1, Count do Rest[#Rest + 1] = List[Index] end
            RingPlace(Rest, Center, Dt)
        end

        ---------------------------------------------------------------- Trail
        local function TrailStep(List, Center, Dt, Now)
            local T = Orbit.Trail
            local Me = RootPart
            local Room = CurrentRoomNumber()
            if T.Room ~= Room then
                if T.Room then
                    for Index, Point in ipairs(T.Points) do
                        if not Point.Dead then Point.Dead = Now + (Index - 1) * 0.04 end -- next door: the old tail melts
                    end
                end
                T.Room = Room
            end
            if Me and Now - T.Sample >= 0.25 then
                T.Sample = Now
                local Position = Me.Position + Vector3.new(0, Options.TrailHeight.Value, 0)
                if not T.Last or (Position - T.Last).Magnitude >= Options.TrailSpacing.Value then
                    T.Last = Position
                    local Bound = {}
                    for _, Point in ipairs(T.Points) do Bound[Point.Item] = true end
                    local Pick
                    for _, Object in ipairs(List) do
                        if not Bound[Object] then Pick = Object break end
                    end
                    if not Pick and T.Points[1] then
                        local Oldest = table.remove(T.Points, 1) -- out of items: the tail end jumps to the front
                        Pick = Oldest.Item
                        local State = St(Pick)
                        State.Kind = ""
                        State.NextGD = 0.5
                    end
                    if Pick then T.Points[#T.Points + 1] = { Pos = Position, T = Now, Item = Pick } end
                end
            end
            local Life = Options.TrailLife.Value
            local Used = {}
            for Index = #T.Points, 1, -1 do
                local Point = T.Points[Index]
                if not FreeSet[Point.Item] then
                    table.remove(T.Points, Index)
                else
                    if not Point.Dead and Now - Point.T > Life then Point.Dead = Now end
                    local Sink = 0
                    local Gone = false
                    if Point.Dead and Now >= Point.Dead then
                        local Melt = (Now - Point.Dead) / 0.8
                        if Melt >= 1 then Gone = true else Sink = 3 * Melt * Melt end
                    end
                    if Gone then
                        table.remove(T.Points, Index)
                    else
                        Used[Point.Item] = true
                        Put(Point.Item, St(Point.Item), Point.Pos - Vector3.new(0, Sink, 0), "trail", Dt, nil, 0.4)
                    end
                end
            end
            local Rest = {}
            for _, Object in ipairs(List) do
                if not Used[Object] then Rest[#Rest + 1] = Object end
            end
            RingPlace(Rest, Center, Dt)
        end

        ---------------------------------------------------------------- Door marker
        local function DoorTargetNow()
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            local Latest = GameData:FindFirstChild("LatestRoom")
            local Room = Rooms and Latest and Rooms:FindFirstChild(tostring(Latest.Value))
            local Door = Room and Room:FindFirstChild("Door")
            if Door and (Door:IsA("Model") or Door:IsA("BasePart")) then return PositionOf(Door) end
            return nil
        end

        ---------------------------------------------------------------- Best-run ghost
        local G = Orbit.G
        pcall(function()
            local Data = Load("Ghost.json")
            if type(Data) == "table" and type(Data.best) == "table" then
                for Key, Entry in Data.best do
                    if type(Entry) == "table" and type(Entry.T) == "number" and type(Entry.t) == "table" and type(Entry.f) == "table" and #Entry.t >= 2 and #Entry.t == #Entry.f then
                        G.Best[Key] = Entry
                    end
                end
            end
        end)
        local function RoomGeo(Number)
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            local Room = Rooms and Rooms:FindFirstChild(tostring(Number))
            if not Room then return nil end
            local Exit = Room:FindFirstChild("RoomExit") or Room:FindFirstChild("Door")
            local Entry = Room:FindFirstChild("RoomEntrance")
            if not Entry then
                local Previous = Rooms:FindFirstChild(tostring(Number - 1))
                Entry = Previous and (Previous:FindFirstChild("RoomExit") or Previous:FindFirstChild("Door"))
            end
            if not (Entry and Exit) then return nil end
            local function At(Object)
                if Object:IsA("Model") then return Object:GetPivot().Position end
                if Object:IsA("BasePart") then return Object.Position end
                return nil
            end
            return At(Entry), At(Exit)
        end
        local function FracAt(Best, Elapsed)
            local Times, Fracs = Best.t, Best.f
            if Elapsed <= Times[1] then return Fracs[1] end
            for Index = 2, #Times do
                if Elapsed <= Times[Index] then
                    local Span = Times[Index] - Times[Index - 1]
                    local A = Span > 0 and (Elapsed - Times[Index - 1]) / Span or 1
                    return Fracs[Index - 1] + (Fracs[Index] - Fracs[Index - 1]) * A
                end
            end
            return 1
        end
        local function TimeAt(Best, Fraction)
            local Times, Fracs = Best.t, Best.f
            if Fraction <= Fracs[1] then return Times[1] end
            for Index = 2, #Times do
                if Fracs[Index] >= Fraction then
                    local Span = Fracs[Index] - Fracs[Index - 1]
                    local A = Span > 0 and (Fraction - Fracs[Index - 1]) / Span or 1
                    return Times[Index - 1] + (Times[Index] - Times[Index - 1]) * A
                end
            end
            return Best.T
        end
        local function Finalize()
            local Count = #G.St
            if G.Room and G.T0 and G.Valid and Count >= 4 then
                local Total = tick() - G.T0
                if Total >= 1.5 and G.Sf[1] <= 0.35 and G.Sf[Count] >= 0.6 then
                    local Key = Floor .. ":" .. G.Room
                    local Old = G.Best[Key]
                    if not Old or Total < Old.T then
                        local Step = math.max(1, math.ceil(Count / 120))
                        local Times, Fracs = {}, {}
                        for Index = 1, Count, Step do
                            Times[#Times + 1] = math.floor(G.St[Index] * 1000 + 0.5) / 1000
                            Fracs[#Fracs + 1] = math.floor(G.Sf[Index] * 1000 + 0.5) / 1000
                        end
                        Times[#Times + 1] = math.floor(Total * 1000 + 0.5) / 1000
                        Fracs[#Fracs + 1] = 1
                        G.Best[Key] = { T = math.floor(Total * 1000 + 0.5) / 1000, t = Times, f = Fracs }
                        G.Dirty = true
                        if Old then
                            Functions.Notify({ Title = "New best: room " .. G.Room, Body = string.format("%.1fs (was %.1fs)", Total, Old.T) })
                        end
                    end
                end
            end
        end
        task.spawn(function()
            while Alive do
                task.wait(0.2)
                if Toggles.BestRunGhost.Value and RootPart and RootPart.Parent then
                    local Number = CurrentRoomNumber()
                    if G.Room ~= Number then
                        Finalize()
                        G.Room, G.T0, G.St, G.Sf, G.Valid, G.F, G.E, G.X = Number, tick(), {}, {}, true, 0, nil, nil
                    end
                    local Entry, Exit = RoomGeo(Number)
                    if Entry and Exit then
                        G.E, G.X = Entry, Exit
                        local Delta = Exit - Entry
                        local Length2 = Delta:Dot(Delta)
                        if Length2 > 25 then
                            local F = math.clamp((RootPart.Position - Entry):Dot(Delta) / Length2, 0, 1)
                            G.F = F
                            if #G.St < 600 then
                                G.St[#G.St + 1] = tick() - G.T0
                                G.Sf[#G.Sf + 1] = F
                            end
                        else
                            G.Valid = false
                        end
                    end
                else
                    G.Room = nil
                end
                if G.Dirty and tick() - G.LastSave > 5 then
                    G.Dirty = false
                    G.LastSave = tick()
                    Save("Ghost.json", { v = 1, best = G.Best })
                end
            end
        end)
        local GhostGui, GhostLabel
        local function GhostCalc()
            local Number = CurrentRoomNumber()
            if G.Room ~= Number or not G.T0 or not (G.E and G.X) then return nil end
            local Best = G.Best[Floor .. ":" .. Number]
            if not Best then return nil end
            local Elapsed = tick() - G.T0
            local Position = G.E:Lerp(G.X, FracAt(Best, Elapsed))
            local Me = RootPart
            local Delta = TimeAt(Best, G.F) - Elapsed -- ghost needed longer to get where you are = you are ahead
            local Text = Delta >= 0 and string.format("ahead +%.1fs", Delta) or string.format("behind %.1fs", -Delta)
            return Vector3.new(Position.X, (Me and Me.Position.Y or Position.Y) + 0.5, Position.Z), Text
        end

        ---------------------------------------------------------------- Singularity
        local Flash
        local function DoFlash()
            if not Toggles.SingFlash.Value then return end
            pcall(function()
                if Flash then Flash:Destroy() end
                Flash = New("ScreenGui", { Name = "AMRFlash", IgnoreGuiInset = true, DisplayOrder = 1000, ResetOnSpawn = false }, GetHiddenContainer())
                local Frame = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, BackgroundTransparency = 0 }, Flash)
                TweenService:Create(Frame, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
                local Gui = Flash
                task.delay(1, function() if Gui then Gui:Destroy() end if Flash == Gui then Flash = nil end end)
            end)
        end
        local function StopShake()
            Orbit.ShakeAmp = 0
            pcall(function() RunService:UnbindFromRenderStep("AMRSingShake") end)
        end
        local function BindShake()
            pcall(function() RunService:UnbindFromRenderStep("AMRSingShake") end)
            RunService:BindToRenderStep("AMRSingShake", Enum.RenderPriority.Camera.Value + 1, function()
                local Amp = Orbit.ShakeAmp
                local Camera = workspace.CurrentCamera
                if Amp > 0.001 and Camera then
                    Camera.CFrame = Camera.CFrame * CFrame.new((math.random() - 0.5) * Amp, (math.random() - 0.5) * Amp, 0)
                end
            end)
        end

        local AxisA, AxisB = Vector3.new(0.3, 1, 0.2).Unit, Vector3.new(1, 0.2, 0.5).Unit
        local Params = RaycastParams.new()
        Params.FilterType = Enum.RaycastFilterType.Exclude
        Params.RespectCanCollide = true
        local ItemRadius = 0.9

        local function RandomUnit()
            local V = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
            if V.Magnitude < 0.01 then return UP end
            return V.Unit
        end

        local function RefreshCollisionFilter()
            local Filter = { workspace:FindFirstChild("Drops"), workspace.CurrentCamera }
            for _, Player in Players:GetPlayers() do
                if Player.Character then Filter[#Filter + 1] = Player.Character end
            end
            Params.FilterDescendantsInstances = Filter
        end

        local function StartSing(List)
            local Count = #List
            local Dirs = {}
            for Index = 1, Count do
                local Y = 1 - 2 * (Index - 0.5) / Count
                local R = math.sqrt(math.max(0, 1 - Y * Y))
                local Phi = Index * 2.399963
                Dirs[Index] = Vector3.new(math.cos(Phi) * R, Y, math.sin(Phi) * R)
            end
            for Index, Object in ipairs(List) do
                local State = St(Object)
                State.Ang = Orbit.Angle + (Index - 1) / Count * TAU
                State.Rest = false
            end
            RefreshCollisionFilter()
            Orbit.Sing = { Phase = "gather", T = 0, TS = 0, Dirs = Dirs }
            if Toggles.SingCam.Value then BindShake() end
        end

        local function Fly(Object, State, Dt, Gravity)
            if State.Rest then return end
            local Velocity = State.V - Vector3.new(0, Gravity * Dt, 0)
            Velocity *= math.exp(-0.12 * Dt)
            if Velocity.Magnitude > 160 then Velocity = Velocity.Unit * 160 end
            local Position = State.P
            local Step = Velocity * Dt
            local Length = Step.Magnitude
            if Length > 1e-4 then
                local Hit = workspace:Raycast(Position, Step + Step.Unit * ItemRadius, Params)
                if Hit then
                    local Normal = Hit.Normal
                    Position = Hit.Position + Normal * ItemRadius
                    local Along = Velocity:Dot(Normal)
                    Velocity = Velocity - (1.55) * Along * Normal -- restitution 0.55
                    Velocity = Velocity - (Velocity - Velocity:Dot(Normal) * Normal) * 0.12 -- friction
                    State.SpinSpeed = (State.SpinSpeed or 0) * 0.8
                    if Normal.Y > 0.6 and Velocity.Magnitude < 5 then
                        State.Rest = true
                        Velocity = ZERO
                    end
                else
                    Position += Step
                end
            end
            State.P, State.V = Position, Velocity
            if State.SpinAxis then
                State.Rot = State.Rot * CFrame.fromAxisAngle(State.SpinAxis, (State.SpinSpeed or 0) * Dt)
            end
        end

        local function ReleaseScatterItems(List, Glide)
            for _, Object in ipairs(List) do
                local State = St(Object)
                State.Rest, State.SpinAxis, State.P, State.V = false, nil, nil, nil
                State.Kind = "fly"
                State.NextGD = Glide or 1.5
            end
        end

        local function BeginScatter(Action, List, Origin, Now)
            RefreshCollisionFilter()
            Action.Phase = "scatter"
            Action.TS = 0
            Action.BoomAt = Now
            local Power = Options.SingPower.Value
            for _, Object in ipairs(List) do
                local State = St(Object)
                local Position = State.Last or GetPos(Object)
                local Out = Position - Origin
                Out = Out.Magnitude > 0.01 and Out.Unit or RandomUnit()
                State.P = Position
                State.V = Out * Power * (0.75 + 0.5 * math.random()) + RandomUnit() * Power * 0.25 + UP * Power * 0.35
                State.SpinAxis = RandomUnit()
                State.SpinSpeed = 6 + math.random() * 10
                State.Rest = false
            end
            if Toggles.SingCam.Value then BindShake() end
            DoFlash()
        end

        local function ScatterStep(Action, List, Dt, Now, ClockDt)
            Action.TS += ClockDt or Dt
            Orbit.ShakeAmp = math.max(0, 1.2 * (1 - (Now - (Action.BoomAt or Now)) / 0.5))
            local Gravity = workspace.Gravity
            local AllRest = true
            for _, Object in ipairs(List) do
                local State = St(Object)
                if State.P == nil then State.P = State.Last or GetPos(Object) State.V = ZERO State.Rest = true end
                Fly(Object, State, Dt, Gravity)
                if not State.Rest then AllRest = false end
                Put(Object, State, State.P, "fly", Dt, State.Rot, 0)
            end
            if Action.TS >= Options.SingScatter.Value or (AllRest and Action.TS > 1.5) then
                ReleaseScatterItems(List, 1.5)
                StopShake()
                return true
            end
            return false
        end

        local function SingStep(List, Center, Dt, Now, ClockDt)
            local S = Orbit.Sing
            local Count = #List
            local Gather, Clump, Spin, Scatter = Options.SingGather.Value, Options.SingClump.Value, Options.SingSpin.Value, Options.SingScatter.Value
            local Ball = Center + Orbit.Face * Options.SingDist.Value + Vector3.new(0, 3.5, 0)
            local Speed = Options.OrbitDroppedItemsSpeed.Value
            local Height, Distance = Options.OrbitDroppedItemsHeight.Value, Options.OrbitDroppedItemsDistance.Value
            local BallRadius = 0.9 + 0.3 * Count ^ (1 / 3)
            S.T += ClockDt or Dt
            local T = S.T
            if S.Phase == "gather" and T >= Gather then S.Phase = "clump" end
            if S.Phase == "clump" and T >= Gather + Clump then S.Phase = "spin" end

            if S.Phase == "gather" then
                for Index, Object in ipairs(List) do
                    local State = St(Object)
                    local Delay = (Index - 1) / math.max(Count - 1, 1) * Gather * 0.45
                    local P = math.clamp((T - Delay) / (Gather * 0.55), 0, 1)
                    local E = P * P -- ease-in
                    State.Ang = (State.Ang or 0) + Dt * Speed * (1 + 5 * E)
                    local R = Distance + (2.2 - Distance) * E
                    local Middle = (Center + Vector3.new(0, Height, 0)):Lerp(Ball, E)
                    Put(Object, State, Middle + Vector3.new(math.cos(State.Ang) * R, 0, math.sin(State.Ang) * R), "sing", Dt, nil, 0)
                end
                return
            elseif S.Phase == "clump" then
                local C = math.clamp((T - Gather) / Clump, 0, 1)
                local Smooth = C * C * (3 - 2 * C)
                for Index, Object in ipairs(List) do
                    local State = St(Object)
                    State.Ang = (State.Ang or 0) + Dt * Speed * 6
                    local Orb = Vector3.new(math.cos(State.Ang) * 2.2, 0, math.sin(State.Ang) * 2.2)
                    local Sphere = (S.Dirs[Index] or UP) * BallRadius
                    Put(Object, State, Ball + Orb:Lerp(Sphere, Smooth), "sing", Dt, nil, 0)
                end
                return
            elseif S.Phase == "spin" then
                local P = math.clamp((T - Gather - Clump) / Spin, 0, 1)
                local W0, W1 = 3, 50 -- exponential ramp of angular speed
                local Ratio = W1 / W0
                local Phi = W0 * Spin * (Ratio ^ P - 1) / math.log(Ratio)
                local Turn = CFrame.fromAxisAngle(AxisA, Phi) * CFrame.fromAxisAngle(AxisB, Phi * 0.61)
                local Amp = 0.04 + 0.45 * P ^ 3
                Orbit.ShakeAmp = 0.35 * P ^ 3
                for Index, Object in ipairs(List) do
                    local State = St(Object)
                    local Off = Turn:VectorToWorldSpace(S.Dirs[Index] or UP) * BallRadius * (1 - 0.3 * P)
                    local Jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * Amp
                    State.Rot = State.Rot * CFrame.fromAxisAngle(AxisB, (4 + 30 * P) * Dt)
                    Put(Object, State, Ball + Off + Jitter, "sing", Dt, State.Rot, 0)
                    State.P = Ball + Off
                end
                if P >= 1 then
                    BeginScatter(S, List, Ball, Now)
                end
                return
            end

            if ScatterStep(S, List, Dt, Now, ClockDt) then
                Orbit.Sing, Orbit.WantPlay = nil, false
                if Toggles.SingRepeat.Value then Orbit.NextPlay = Now + 2 else Orbit.NextPlay = nil end
            end
        end

        ---------------------------------------------------------------- Wall Slam: a controlled clump detonates only on a side-wall hit
        local function SphereDirections(List)
            local Dirs = {}
            local Count = math.max(#List, 1)
            for Index, Object in ipairs(List) do
                local Y = 1 - 2 * (Index - 0.5) / Count
                local R = math.sqrt(math.max(0, 1 - Y * Y))
                local Phi = Index * 2.399963
                Dirs[Object] = Vector3.new(math.cos(Phi) * R, Y, math.sin(Phi) * R)
            end
            return Dirs
        end

        local function WallCast(Origin, Radius, Direction)
            if Direction.Magnitude < 0.01 then return nil end
            local Ok, Hit = pcall(function()
                return workspace:Spherecast(Origin, Radius, Direction, Params)
            end)
            if not Ok then
                Hit = workspace:Raycast(Origin, Direction, Params)
                if not Hit then
                    local Side = Direction.Unit:Cross(UP)
                    if Side.Magnitude > 0.01 then
                        Side = Side.Unit * Radius * 0.75
                        Hit = workspace:Raycast(Origin + Side, Direction, Params) or workspace:Raycast(Origin - Side, Direction, Params)
                    end
                end
                if not Hit then Hit = workspace:Raycast(Origin + UP * Radius * 0.75, Direction, Params) end
            end
            if Hit and math.abs(Hit.Normal.Y) < 0.6 then return Hit end
            return nil
        end

        local function StartWall(List)
            local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not Root then return false end
            RefreshCollisionFilter()
            local Center = Root.Position + Orbit.Face * Options.WallSlamReach.Value + UP * Options.WallSlamHeight.Value
            Orbit.Wall = {
                Phase = "gather", T = 0, ControlT = 0, C = Center, Dirs = SphereDirections(List),
                SourceCharacter = LocalPlayer.Character,
            }
            return true
        end

        local function WallStep(List, Dt, Now, ClockDt)
            local Wall = Orbit.Wall
            if not Wall then return end
            if Wall.Phase == "scatter" then
                if ScatterStep(Wall, List, Dt, Now, ClockDt) then Orbit.Wall, Orbit.WantWall = nil, false end
                return
            end
            local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not Root or Wall.SourceCharacter ~= LocalPlayer.Character then
                ReleaseScatterItems(List, 0.8)
                Orbit.Wall, Orbit.WantWall = nil, false
                return
            end

            Wall.T += ClockDt or Dt
            local Radius = 0.9 + 0.32 * #List ^ (1 / 3)
            local Desired = Root.Position + Orbit.Face * Options.WallSlamReach.Value + UP * Options.WallSlamHeight.Value
            local Delta = Desired - Wall.C
            local Limit = Options.WallSlamSpeed.Value * Dt
            local Step = Delta.Magnitude > Limit and Delta.Unit * Limit or Delta
            if Wall.Phase == "gather" then
                Wall.C += Step
            else
                Wall.ControlT += ClockDt or Dt
                local Hit = WallCast(Wall.C, Radius, Step)
                if not Hit then
                    local FromPlayer = Root.Position + UP * Options.WallSlamHeight.Value
                    Hit = WallCast(FromPlayer, Radius, Wall.C - FromPlayer)
                end
                if Hit then
                    Wall.C = Hit.Position + Hit.Normal * (Radius + 0.08)
                    for _, Object in ipairs(List) do
                        local Position = Wall.C + (Wall.Dirs[Object] or UP) * Radius
                        Put(Object, St(Object), Position, "wall", Dt, nil, 0)
                    end
                    BeginScatter(Wall, List, Wall.C, Now)
                    return
                end
                Wall.C += Step
            end

            for _, Object in ipairs(List) do
                if not Wall.Dirs[Object] then Wall.Dirs[Object] = RandomUnit() end
                local Position = Wall.C + Wall.Dirs[Object] * Radius
                Put(Object, St(Object), Position, "wall", Dt, nil, Wall.Phase == "gather" and Options.WallSlamGather.Value or 0)
            end
            if Wall.Phase == "gather" and Wall.T >= Options.WallSlamGather.Value then
                Wall.Phase = "control"
                Wall.ControlT = 0
            elseif Wall.Phase == "control" and Wall.ControlT >= Options.WallSlamTimeout.Value then
                ReleaseScatterItems(List, 1)
                Orbit.Wall, Orbit.WantWall = nil, false
                Warn("walltimeout", "Wall Slam timed out without hitting a wall.")
            end
        end

        ---------------------------------------------------------------- FPV Drone: dropped-item formation homes toward the selected target
        local function DroneOffset(Index, Count, Drone, Now)
            local Scale = Options.FPVDroneScale.Value
            local Forward = Drone.Forward
            local Right = Forward:Cross(UP)
            if Right.Magnitude < 0.01 then Right = Vector3.new(1, 0, 0) else Right = Right.Unit end
            local Hubs = {
                Right * Scale + Forward * Scale,
                -Right * Scale + Forward * Scale,
                Right * Scale - Forward * Scale,
                -Right * Scale - Forward * Scale,
            }
            if Index == 1 then return ZERO end
            if Index <= 5 then return Hubs[Index - 1] end
            local Blade = Index - 6
            local Hub = Hubs[Blade % 4 + 1]
            local Ring = math.floor(Blade / 4)
            local Angle = Now * 12 + Ring * 1.7 + (Blade % 4) * math.pi * 0.5
            local Radius = Scale * (0.32 + 0.08 * (Ring % 3))
            return Hub + Right * math.cos(Angle) * Radius + Forward * math.sin(Angle) * Radius + UP * math.sin(Angle * 2) * 0.08
        end

        local function StartDrone(List)
            local Friend, TargetRoot
            if true then
                Friend = LocalPlayer
                TargetRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            elseif Boot.GetSocialTarget then
                Friend, TargetRoot = Boot.GetSocialTarget()
            end
            local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not Friend or not TargetRoot then Warn("dronefriend", "Pick a live target in General > Players first.") return false end
            if not Root then return false end
            RefreshCollisionFilter()
            local Forward = Vector3.new(Root.CFrame.LookVector.X, 0, Root.CFrame.LookVector.Z)
            if Forward.Magnitude < 0.05 then Forward = Orbit.Face else Forward = Forward.Unit end
            local Slots = {}
            for Index, Object in ipairs(List) do Slots[Object] = Index end
            Orbit.Drone = {
                Phase = "form", T = 0, FlightT = 0, C = Root.Position + Forward * 4 + UP * 3,
                Forward = Forward, Target = Friend, Slots = Slots, NextSlot = #List + 1, SourceCharacter = LocalPlayer.Character,
            }
            return true
        end

        local function DroneFormation(List, Drone, Dt, Now)
            local Count = #List
            for _, Object in ipairs(List) do
                if not Drone.Slots[Object] then
                    Drone.Slots[Object] = Drone.NextSlot
                    Drone.NextSlot += 1
                end
                local Offset = DroneOffset(Drone.Slots[Object], Count, Drone, Now)
                local Look = CFrame.lookAt(Vector3.zero, Drone.Forward)
                Put(Object, St(Object), Drone.C + Offset, "drone", Dt, Look - Look.Position, Drone.Phase == "form" and Options.FPVDroneForm.Value or 0)
            end
        end

        local function DroneStep(List, Dt, Now, ClockDt)
            local Drone = Orbit.Drone
            if not Drone then return end
            if Drone.Phase == "scatter" then
                if ScatterStep(Drone, List, Dt, Now, ClockDt) then Orbit.Drone, Orbit.WantDrone = nil, false end
                return
            end
            if Drone.SourceCharacter ~= LocalPlayer.Character then
                ReleaseScatterItems(List, 0.8)
                Orbit.Drone, Orbit.WantDrone = nil, false
                return
            end

            Drone.T += ClockDt or Dt
            if Drone.Phase == "form" then
                local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not Root then Orbit.Drone, Orbit.WantDrone = nil, false return end
                local Desired = Root.Position + Drone.Forward * 4 + UP * 3
                Drone.C = Drone.C:Lerp(Desired, 1 - math.exp(-8 * Dt))
                DroneFormation(List, Drone, Dt, Now)
                if Drone.T >= Options.FPVDroneForm.Value then Drone.Phase, Drone.T = "fly", 0 end
                return
            end

            Drone.FlightT += ClockDt or Dt
            local TargetRoot = Drone.Target and Drone.Target.Character and Drone.Target.Character:FindFirstChild("HumanoidRootPart")
            if not TargetRoot then
                Drone.MissingAt = Drone.MissingAt or Now
                DroneFormation(List, Drone, Dt, Now)
                if Now - Drone.MissingAt > 5 then
                    ReleaseScatterItems(List, 1)
                    Orbit.Drone, Orbit.WantDrone = nil, false
                    Warn("dronelost", "FPV target disappeared.")
                end
                return
            end
            Drone.MissingAt = nil
            local Desired = TargetRoot.Position + UP * Options.FPVDroneHeight.Value
            local Delta = Desired - Drone.C
            local Distance = Delta.Magnitude
            local Arrival = Options.FPVDroneArrival.Value
            local Step = Options.FPVDroneSpeed.Value * Dt
            if Distance <= Arrival + Step then
                if Distance > Arrival and Distance > 0 then Drone.C += Delta.Unit * (Distance - Arrival) end
                DroneFormation(List, Drone, Dt, Now)
                BeginScatter(Drone, List, Drone.C, Now)
                return
            end
            if Distance > 0.01 then
                local Flat = Vector3.new(Delta.X, 0, Delta.Z)
                if Flat.Magnitude > 0.05 then
                    local Blend = Drone.Forward:Lerp(Flat.Unit, 1 - math.exp(-7 * Dt))
                    if Blend.Magnitude > 0.05 then Drone.Forward = Blend.Unit end
                end
                Drone.C += Delta.Unit * math.min(Step, Distance)
            end
            DroneFormation(List, Drone, Dt, Now)
            if Drone.FlightT >= Options.FPVDroneTimeout.Value then
                ReleaseScatterItems(List, 1)
                Orbit.Drone, Orbit.WantDrone = nil, false
                Warn("dronetimeout", "FPV Drone timed out before reaching the friend.")
            end
        end

        ---------------------------------------------------------------- Gold Rain: fountain on GetCurrency
        local function StartRain(List)
            local Filter = { workspace:FindFirstChild("Drops"), workspace.CurrentCamera }
            for _, Player in Players:GetPlayers() do
                if Player.Character then Filter[#Filter + 1] = Player.Character end
            end
            Params.FilterDescendantsInstances = Filter
            local Power = Options.GoldRainPower.Value
            for _, Object in ipairs(List) do
                local State = St(Object)
                local Angle = math.random() * TAU
                local Spread = math.random() * Power * 0.3
                State.P = GetPos(Object)
                State.V = Vector3.new(math.cos(Angle) * Spread, Power * (0.75 + 0.5 * math.random()), math.sin(Angle) * Spread)
                State.SpinAxis = RandomUnit()
                State.SpinSpeed = 4 + math.random() * 8
                State.Rest = false
                State.Kind = "fly"
            end
            Orbit.Rain = { T = 0 }
        end
        local function RainStep(List, Dt, ClockDt)
            local Rain = Orbit.Rain
            Rain.T += ClockDt or Dt
            local Gravity = workspace.Gravity
            for _, Object in ipairs(List) do
                local State = St(Object)
                if State.P == nil then State.P = GetPos(Object) State.V = ZERO State.Rest = true end
                Fly(Object, State, Dt, Gravity)
                Put(Object, State, State.P, "fly", Dt, State.Rot, 0)
            end
            if Rain.T >= Options.GoldRainTime.Value then
                for _, Object in ipairs(List) do
                    local State = St(Object)
                    State.Rest, State.SpinAxis, State.P, State.V = false, nil, nil, nil
                    State.Kind = "fly"
                    State.NextGD = 1.2 -- flows back into the formation
                end
                Orbit.Rain = nil
            end
        end

        function Orbit.Play()
            if Options.OrbitEffect.Value ~= "Singularity" then Options.OrbitEffect:SetValue("Singularity") end
            if not Toggles.OrbitDroppedItems.Value then Toggles.OrbitDroppedItems:SetValue(true) end
            Orbit.WantPlay = true
        end

        function Orbit.PlayWallSlam()
            if Options.OrbitEffect.Value ~= "Wall Slam" then Options.OrbitEffect:SetValue("Wall Slam") end
            if not Toggles.OrbitDroppedItems.Value then Toggles.OrbitDroppedItems:SetValue(true) end
            Orbit.WantWall = true
        end

        function Orbit.PlayFPVDrone()
            if Options.OrbitEffect.Value ~= "FPV Drone" then Options.OrbitEffect:SetValue("FPV Drone") end
            if not Toggles.OrbitDroppedItems.Value then Toggles.OrbitDroppedItems:SetValue(true) end
            Orbit.WantDrone = true
        end

        ---------------------------------------------------------------- allocation of items to roles
        local function Fill(Role, Want, Pool, Taken)
            local Keep = {}
            for _, Object in ipairs(Role) do
                if PoolSet[Object] and not Taken[Object] and #Keep < Want then
                    Keep[#Keep + 1] = Object
                    Taken[Object] = true
                end
            end
            if #Keep < Want then
                for Index = #Pool, 1, -1 do
                    local Object = Pool[Index]
                    if not Taken[Object] then
                        Keep[#Keep + 1] = Object
                        Taken[Object] = true
                        if #Keep >= Want then break end
                    end
                end
            end
            return Keep
        end

        ---------------------------------------------------------------- the step (called from the Orbit Dropped Items loop)
        function Boot.OrbitStep(List, Root, Dt, Now)
            if not Alive or Orbit.Dead then return false end
            local Mode = Options.OrbitEffect.Value
            local WantDoor, WantGhost = Toggles.DoorMark.Value, Toggles.BestRunGhost.Value
            local Exclusive = Orbit.Sing or Orbit.Wall or Orbit.Drone or Orbit.WantPlay or Orbit.WantWall or Orbit.WantDrone
            if Exclusive then
                Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or Root
                WantDoor, WantGhost = false, false
            end
            if Mode == "Ring" and not WantDoor and not WantGhost and not Toggles.GoldRain.Value then
                Orbit.Sing, Orbit.Wall, Orbit.Drone = nil, nil, nil
                return false
            end
            local ClockDt = math.min(Dt, 0.25)
            Dt = math.min(Dt, 0.05)
            local Count = #List
            if Count == 0 then
                Warn("none", "Not enough drops (0).")
                return true
            end
            local Minimum = Mode == "Text" and 6 or Mode == "FPV Drone" and 5 or 3
            local RunningRequestedMode = (Mode == "Singularity" and Orbit.Sing) or (Mode == "Wall Slam" and Orbit.Wall) or (Mode == "FPV Drone" and Orbit.Drone)
            if Mode ~= "Ring" and Count < Minimum and not RunningRequestedMode then
                Warn("few", string.format("Not enough drops for %s (have %d). Showing the ring.", Mode, Count))
                Mode = "Ring"
            end

            local Center = Root.Position
            -- facing: camera for you, root for a friend; smoothed so formations do not whip around
            local Look
            local Camera = workspace.CurrentCamera
            if Camera and Root.Parent == LocalPlayer.Character then Look = Camera.CFrame.LookVector else Look = Root.CFrame.LookVector end
            Look = Vector3.new(Look.X, 0, Look.Z)
            if Look.Magnitude > 0.05 then
                local Blend = Orbit.Face:Lerp(Look.Unit, 1 - math.exp(-8 * Dt))
                if Blend.Magnitude > 0.05 then Orbit.Face = Blend.Unit end
            end
            Orbit.Angle += Dt * Options.OrbitDroppedItemsSpeed.Value

            -- refresh: put everything on you for a moment so the items do not despawn
            local Interval = Options.OrbitRefresh.Value
            local Since = Now - Orbit.LastRefresh
            if not Exclusive and Now >= Orbit.Hold and Since >= Interval then
                Orbit.LastRefresh = Now
                Orbit.Hold = Now + 0.2
            end
            if not Exclusive and Now < Orbit.Hold then
                for _, Object in ipairs(List) do Put(Object, St(Object), Center, "hold", Dt, nil, 0) end
                return true
            end

            table.clear(PoolSet)
            for _, Object in ipairs(List) do PoolSet[Object] = true end

            -- overlays: door marker + ghost take items off the end of the list
            if Now - Orbit.DoorAt >= 1 then
                Orbit.DoorAt = Now
                Orbit.DoorPos = WantDoor and DoorTargetNow() or nil
            end
            local Taken = {}
            local Roles = Orbit.Roles
            local DoorCount, GhostCount = 0, 0
            if WantDoor and Orbit.DoorPos then
                Roles.door = Fill(Roles.door, math.min(math.floor(Options.DoorMarkCount.Value), math.max(0, Count - 2)), List, Taken)
                DoorCount = #Roles.door
            else
                Roles.door = {}
            end
            local GhostPosition, GhostText
            if WantGhost then GhostPosition, GhostText = GhostCalc() end
            if GhostPosition then
                Roles.ghost = Fill(Roles.ghost, math.min(3, math.max(0, Count - DoorCount - 2)), List, Taken)
                GhostCount = #Roles.ghost
            else
                Roles.ghost = {}
            end
            local Free = {}
            table.clear(FreeSet)
            for _, Object in ipairs(List) do
                if not Taken[Object] then
                    Free[#Free + 1] = Object
                    FreeSet[Object] = true
                end
            end

            if DoorCount > 0 then
                local Base = Orbit.DoorPos + Vector3.new(0, Options.DoorMarkHeight.Value, 0)
                for Index, Object in ipairs(Roles.door) do
                    local A = Now * 2.2 + (Index - 1) / DoorCount * TAU
                    Put(Object, St(Object), Base + Vector3.new(math.cos(A) * 1.8, math.sin(Now * 2 + Index) * 0.4, math.sin(A) * 1.8), "door", Dt)
                end
            end
            if GhostCount > 0 then
                for Index, Object in ipairs(Roles.ghost) do
                    local A = Now * 3 + (Index - 1) / GhostCount * TAU
                    Put(Object, St(Object), GhostPosition + Vector3.new(math.cos(A) * 0.9, 0.3 * math.sin(2 * A), math.sin(A) * 0.9), "ghost", Dt)
                end
                if not GhostGui then
                    GhostGui = New("BillboardGui", { Name = "AMRGhostLabel", AlwaysOnTop = true, Size = UDim2.fromOffset(190, 28), StudsOffset = Vector3.new(0, 2.5, 0), LightInfluence = 0 }, GetHiddenContainer())
                    GhostLabel = New("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Text = "" }, GhostGui)
                    New("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0) }, GhostLabel)
                end
                local First = Roles.ghost[1]
                local Anchor = First:IsA("Model") and (First.PrimaryPart or First:FindFirstChildWhichIsA("BasePart", true)) or First
                GhostGui.Adornee = Anchor
                GhostGui.Enabled = true
                GhostLabel.Text = "ghost " .. GhostText
            elseif GhostGui then
                GhostGui.Enabled = false
            end

            if Mode ~= "Singularity" then Orbit.Sing, Orbit.WantPlay, Orbit.NextPlay = nil, false, nil end
            if Mode ~= "Wall Slam" then Orbit.Wall, Orbit.WantWall = nil, false end
            if Mode ~= "FPV Drone" then Orbit.Drone, Orbit.WantDrone = nil, false end
            if #Free == 0 then return true end
            local Busy = Orbit.Sing or Orbit.Wall or Orbit.Drone or Orbit.WantPlay or Orbit.WantWall or Orbit.WantDrone
            if Orbit.RainWant and not Orbit.Rain and not Busy then
                Orbit.RainWant = false
                StartRain(Free)
            end
            if Orbit.Rain and not Busy then
                RainStep(Free, Dt, ClockDt)
                return true
            end

            if Mode == "Tornado" then Tornado(Free, Center, Dt, Now)
            elseif Mode == "Cradle" then Cradle(Free, Center, Dt, Now)
            elseif Mode == "Wave" then Wave(Free, Center, Dt, Now)
            elseif Mode == "Text" then TextStep(Free, Center, Dt, Now)
            elseif Mode == "Trail" then TrailStep(Free, Center, Dt, Now)
            elseif Mode == "Singularity" then
                if Orbit.NextPlay and Now >= Orbit.NextPlay then Orbit.NextPlay = nil Orbit.WantPlay = true end
                if Orbit.WantPlay and not Orbit.Sing then
                    if #Free >= 3 then StartSing(Free) else Warn("few", "Not enough drops for Singularity.") Orbit.WantPlay = false end
                end
                if Orbit.Sing then SingStep(Free, Center, Dt, Now, ClockDt) else RingPlace(Free, Center, Dt) end
            elseif Mode == "Wall Slam" then
                if Orbit.WantWall and not Orbit.Wall then
                    if #Free >= 3 then
                        Orbit.WantWall = not StartWall(Free)
                    else
                        Warn("few", "Not enough drops for Wall Slam.")
                        Orbit.WantWall = false
                    end
                end
                if Orbit.Wall then WallStep(Free, Dt, Now, ClockDt) else RingPlace(Free, Center, Dt) end
            elseif Mode == "FPV Drone" then
                if Orbit.WantDrone and not Orbit.Drone then
                    if #Free >= 5 then
                        StartDrone(Free)
                        Orbit.WantDrone = false
                    else
                        Warn("few", "FPV Drone needs at least 5 drops.")
                        Orbit.WantDrone = false
                    end
                end
                if Orbit.Drone then DroneStep(Free, Dt, Now, ClockDt) else RingPlace(Free, Center, Dt) end
            else
                RingPlace(Free, Center, Dt)
            end
            return true
        end

        local function Engage(Value)
            if Value and not Toggles.OrbitDroppedItems.Value then Toggles.OrbitDroppedItems:SetValue(true) end
        end
        Options.OrbitEffect:OnChanged(function(Value)
            Orbit.Dead = false
            Orbit.Sing, Orbit.WantPlay, Orbit.NextPlay = nil, false, nil
            Orbit.Wall, Orbit.WantWall, Orbit.Drone, Orbit.WantDrone = nil, false, nil, false
            Orbit.Rain, Orbit.RainWant = nil, false
            Orbit.Trail.Points = {}
            Orbit.TextLast = nil
            StopShake()
            Engage(Value ~= "Ring")
        end)
        local RainConnection
        function Orbit.Abort()
            Orbit.Sing, Orbit.WantPlay, Orbit.NextPlay = nil, false, nil
            Orbit.Wall, Orbit.WantWall, Orbit.Drone, Orbit.WantDrone = nil, false, nil, false
            Orbit.Rain, Orbit.RainWant = nil, false
            Orbit.Trail.Points = {}
            Orbit.Roles = { door = {}, ghost = {} }
            for _, State in Items do
                State.Rest, State.SpinAxis, State.P, State.V = false, nil, nil, nil
                State.Kind = ""
                State.NextGD = 0.8
            end
            StopShake()
        end
        Toggles.GoldRain:OnChanged(function(Value)
            if RainConnection then RainConnection:Disconnect() RainConnection = nil end
            Orbit.Rain, Orbit.RainWant = nil, false
            if not Value then return end
            Engage(true)
            local Remote = RemotesFolder and RemotesFolder:FindFirstChild("GetCurrency")
            if not Remote then Functions.Notify({ Title = "Gold Rain", Body = "GetCurrency remote not found." }) return end
            RainConnection = Remote.OnClientEvent:Connect(function(_, Amount)
                if type(Amount) == "number" and Amount > 0 and not (Orbit.Sing or Orbit.Wall or Orbit.Drone or Orbit.Rain) then Orbit.RainWant = true end
            end)
            table.insert(Connections, RainConnection)
        end)
        Toggles.SingHotkey:OnChanged(function(Value)
            if not Value then return end
            Orbit.Play()
            task.defer(function() Toggles.SingHotkey:SetValue(false) end)
        end)
        Toggles.DoorMark:OnChanged(Engage)
        Toggles.BestRunGhost:OnChanged(Engage)

        pcall(function() Library:OnUnload(function()
            Orbit.Dead = true
            Orbit.Abort()
            if RainConnection then RainConnection:Disconnect() RainConnection = nil end
            for _, Gui in { GhostGui, Flash } do pcall(function() Gui:Destroy() end) end
            Boot.OrbitStep = nil
            Boot.GetSocialTarget = nil
            Boot.OrbitRoot = nil
            Boot.Orbit = nil
        end) end)
    end

    ---------------------------------------------------------------------
    -- Honcho / pole diagnostics and floor-aware chair/cart prompt handling
    ---------------------------------------------------------------------
    do
        local Box = Groupboxes.Archives_Experimental
        Box:AddDivider()
        Box:AddLabel("Interaction Diagnostics")
        Box:AddToggle("HonchoProbe", {
            Text = "Honcho Probe (log)", Default = false,
            Tooltip = "Passively records Honcho/pole/door/chair/cart prompts and relevant incoming remotes. It never fires them."
        })
        Box:AddToggle("FloorObjectInteractionFix", {
            Text = "Honcho Door / Chair / Cart Fix", Default = false,
            Tooltip = "Clears Rule1 from the current Archives turnstyle and enables the exact nearby office-chair/cart prompt. It never auto-interacts."
        })

        local ProbeLines, ProbeConnections = {}, {}
        local RemoteConnections = setmetatable({}, { __mode = "k" })
        local function AddProbe(Text)
            ProbeLines[#ProbeLines + 1] = string.format("[%7.2f] %s", tick() - LoadStart, tostring(Text))
            if #ProbeLines > 300 then table.remove(ProbeLines, 1) end
        end
        local function Path(Object)
            local Ok, Result = pcall(function() return Object:GetFullName() end)
            return Ok and Result or tostring(Object)
        end
        local function Relevant(Object)
            local Node = Object
            while Node and Node ~= workspace do
                local Name = string.lower(Node.Name)
                if string.find(Name, "honcho", 1, true) or string.find(Name, "pole", 1, true)
                    or string.find(Name, "door", 1, true) or string.find(Name, "chair", 1, true)
                    or string.find(Name, "cart", 1, true)
                then
                    return true
                end
                Node = Node.Parent
            end
            return false
        end
        local function Ancestor(Object, Name)
            local Node = Object
            while Node and Node ~= workspace do
                if Node.Name == Name then return Node end
                Node = Node.Parent
            end
            return nil
        end
        local function ObjectPosition(Object)
            local Node = Object
            while Node and Node ~= workspace do
                if Node:IsA("Attachment") then return Node.WorldPosition end
                if Node:IsA("BasePart") then return Node.Position end
                if Node:IsA("Model") then return Node:GetPivot().Position end
                Node = Node.Parent
            end
            return nil
        end
        local function Attributes(Object)
            local Parts = {}
            local Ok, Values = pcall(function() return Object:GetAttributes() end)
            if Ok then
                for Key, Value in Values do Parts[#Parts + 1] = Key .. "=" .. tostring(Value) end
                table.sort(Parts)
            end
            return #Parts > 0 and table.concat(Parts, ",") or "-"
        end
        local function Args(...)
            local Values = table.pack(...)
            local Out = {}
            for Index = 1, math.min(Values.n, 8) do
                local Value = Values[Index]
                if typeof(Value) == "Instance" then Out[#Out + 1] = Path(Value)
                elseif type(Value) == "string" then Out[#Out + 1] = string.sub(Value, 1, 80)
                elseif type(Value) == "number" or type(Value) == "boolean" or Value == nil then Out[#Out + 1] = tostring(Value)
                else Out[#Out + 1] = "<" .. typeof(Value) .. ">" end
            end
            return table.concat(Out, " | ")
        end
        local function PromptLine(Prompt)
            local Position = ObjectPosition(Prompt)
            local Distance = Position and RootPart and (Position - RootPart.Position).Magnitude or -1
            local Tags = "-"
            pcall(function() Tags = table.concat(Prompt:GetTags(), ",") end)
            return string.format(
                "PROMPT %s dist=%.1f Enabled=%s Action=%q Object=%q Hold=%.2f Max=%.1f LOS=%s Fake=%s ParentRoom=%s tags=%s attrs=%s",
                Path(Prompt), Distance, tostring(Prompt.Enabled), tostring(Prompt.ActionText), tostring(Prompt.ObjectText),
                Prompt.HoldDuration, Prompt.MaxActivationDistance, tostring(Prompt.RequiresLineOfSight),
                tostring(Prompt:GetAttribute("FakePrompt")), tostring(Prompt:GetAttribute("ParentRoom")), Tags, Attributes(Prompt)
            )
        end
        local function ContextLine()
            local LiveFloor = GameData:FindFirstChild("Floor")
            local Room = CurrentRoomNumber()
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            local Model = Rooms and Rooms:FindFirstChild(tostring(Room))
            local Section = "none"
            if Model and Model:FindFirstChild("ArchivesHonchoRoom", true) then Section = "ArchivesHonchoRoom" end
            if workspace:FindFirstChild("StairwellLandingLogic", true) then Section = Section == "none" and "StairwellLandingLogic" or (Section .. "+StairwellLandingLogic") end
            return string.format("CONTEXT liveFloor=%s cachedFloor=%s room=%s latest=%s roomModel=%s section=%s root=%s",
                tostring(LiveFloor and LiveFloor.Value), tostring(Floor), tostring(Room), tostring(LatestRoom and LatestRoom.Value),
                Model and Path(Model) or "nil", Section, RootPart and tostring(RootPart.Position) or "nil")
        end
        local function Snapshot()
            AddProbe("=== SNAPSHOT ===")
            AddProbe(ContextLine())
            local Count = 0
            for _, Object in workspace:GetDescendants() do
                if Object:IsA("ProximityPrompt") then
                    local Position = ObjectPosition(Object)
                    local Nearby = Position and RootPart and (Position - RootPart.Position).Magnitude <= 70
                    if Relevant(Object) or Nearby then
                        AddProbe(PromptLine(Object))
                        Count += 1
                        if Count >= 140 then AddProbe("prompt snapshot truncated at 140") break end
                    end
                end
            end
            AddProbe("=== END SNAPSHOT ===")
        end
        local function ClearProbeConnections()
            for _, Connection in ProbeConnections do pcall(function() Connection:Disconnect() end) end
            table.clear(ProbeConnections)
            table.clear(RemoteConnections)
        end
        local function WatchRemote(Remote)
            if not Remote:IsA("RemoteEvent") or RemoteConnections[Remote] or not Relevant(Remote) then return end
            local Connection = Remote.OnClientEvent:Connect(function(...)
                AddProbe("REMOTE IN " .. Path(Remote) .. " :: " .. Args(...))
            end)
            RemoteConnections[Remote] = Connection
            ProbeConnections[#ProbeConnections + 1] = Connection
        end
        local function SetProbe(Value)
            ClearProbeConnections()
            if not Value then return end
            table.clear(ProbeLines)
            AddProbe(ContextLine())
            local PromptService = Services.ProximityPromptService
            ProbeConnections[#ProbeConnections + 1] = PromptService.PromptShown:Connect(function(Prompt) if Relevant(Prompt) then AddProbe("SHOWN " .. PromptLine(Prompt)) end end)
            ProbeConnections[#ProbeConnections + 1] = PromptService.PromptHidden:Connect(function(Prompt) if Relevant(Prompt) then AddProbe("HIDDEN " .. Path(Prompt)) end end)
            ProbeConnections[#ProbeConnections + 1] = PromptService.PromptTriggered:Connect(function(Prompt) if Relevant(Prompt) then AddProbe("TRIGGERED " .. PromptLine(Prompt)) end end)
            ProbeConnections[#ProbeConnections + 1] = PromptService.PromptButtonHoldBegan:Connect(function(Prompt) if Relevant(Prompt) then AddProbe("HOLD BEGIN " .. Path(Prompt)) end end)
            ProbeConnections[#ProbeConnections + 1] = PromptService.PromptButtonHoldEnded:Connect(function(Prompt) if Relevant(Prompt) then AddProbe("HOLD END " .. Path(Prompt)) end end)
            ProbeConnections[#ProbeConnections + 1] = workspace.DescendantAdded:Connect(function(Object)
                if Object:IsA("ProximityPrompt") and Relevant(Object) then AddProbe("ADDED " .. PromptLine(Object)) end
                WatchRemote(Object)
            end)
            if LatestRoom then ProbeConnections[#ProbeConnections + 1] = LatestRoom.Changed:Connect(function() AddProbe(ContextLine()) end) end
            local FloorValue = GameData:FindFirstChild("Floor")
            if FloorValue then ProbeConnections[#ProbeConnections + 1] = FloorValue.Changed:Connect(function() AddProbe(ContextLine()) end) end
            for _, Object in workspace:GetDescendants() do WatchRemote(Object) end
            if RemotesFolder then
                for _, Object in RemotesFolder:GetDescendants() do WatchRemote(Object) end
                ProbeConnections[#ProbeConnections + 1] = RemotesFolder.DescendantAdded:Connect(WatchRemote)
            end
        end
        Toggles.HonchoProbe:OnChanged(SetProbe)
        Box:AddButton({ Text = "Honcho Probe (copy)", Tooltip = "Adds a current prompt snapshot and copies the bounded timeline to clipboard.", Func = function()
            Snapshot()
            local Text = table.concat(ProbeLines, "\n")
            local Done = Copy(Text)
            if not Done then print(Text) end
            Functions.Notify({ Title = Done and "Honcho probe copied" or "Clipboard unavailable; printed to console", Body = #ProbeLines .. " lines", Time = 4 })
        end })

        local Managed = setmetatable({}, { __mode = "k" })
        local ManagedDoors = setmetatable({}, { __mode = "k" })
        local FixConnection, CandidateConnection, LastFix = nil, nil, 0
        local Candidates = setmetatable({}, { __mode = "k" })
        local function RestoreManaged(Keep, KeepDoors)
            for Prompt in Managed do
                if not Keep or not Keep[Prompt] then
                    if Prompt:IsDescendantOf(workspace) and Prompt.Enabled then pcall(function() Prompt.Enabled = false end) end
                    Managed[Prompt] = nil
                end
            end
            for Prompt, Data in ManagedDoors do
                if not KeepDoors or not KeepDoors[Prompt] then
                    if Prompt:IsDescendantOf(workspace) then
                        pcall(function()
                            Prompt.Enabled = Data.Enabled
                            Prompt:SetAttribute("_GateDisabled", Data.GateDisabled)
                            Prompt:SetAttribute("_GateReason", Data.GateReason)
                        end)
                    end
                    ManagedDoors[Prompt] = nil
                end
            end
        end
        local function CurrentObjectPrompt(Prompt)
            if not Prompt:IsA("ProximityPrompt") or not Prompt:IsDescendantOf(workspace) or Prompt:GetAttribute("FakePrompt") then return false end
            local Chair = Ancestor(Prompt, "ArchivesOfficeChair")
            local Cart = Ancestor(Prompt, "ShoppingCart")
            local Door = Ancestor(Prompt, "OneWayTwoHandDoor")
            if not Chair and not Cart and not Door then return false end
            if Door then
                if Prompt.Name ~= "InteractPrompt" or Prompt.ActionText ~= "Enter" or Prompt.ObjectText ~= "Turnstyle" then return false end
                local Broken = ManagedDoors[Prompt] ~= nil or (Prompt:GetAttribute("_GateDisabled") == true and Prompt:GetAttribute("_GateReason") == "Rule1")
                if not Broken then return false end
            elseif Chair then
                if Prompt.Name ~= "CartPrompt" or Prompt:GetAttribute("GateSector") ~= "Push" then return false end
            elseif Prompt.Name ~= "CartPrompt" and Prompt.Name ~= "PushPrompt" and Prompt.Name ~= "LongPushPrompt" and Prompt.Name ~= "BigPropPrompt" then
                return false
            end
            local Position = ObjectPosition(Prompt)
            local Distance = Position and RootPart and (Position - RootPart.Position).Magnitude
            if not Distance or Distance > 24 then return false end
            local Current = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
            if Current == nil then return false end
            local RootObject = Door or Chair or Cart
            local Owner = tonumber(Prompt:GetAttribute("ParentRoom")) or tonumber(RootObject:GetAttribute("ParentRoom")) or RoomNumber(RootObject)
            if Door then
                local LiveFloor = GameData:FindFirstChild("Floor")
                if tostring(LiveFloor and LiveFloor.Value or Floor) ~= "Archives" then return false end
                return Owner == Current, Distance, "door"
            end
            if Owner then return Owner == Current, Distance, "object" end
            if Chair then return false end
            local LiveFloor = GameData:FindFirstChild("Floor")
            local FloorName = string.lower(tostring(LiveFloor and LiveFloor.Value or Floor))
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            local Room = Rooms and Rooms:FindFirstChild(tostring(Current))
            local StairwellContext = string.find(FloorName, "stair", 1, true) ~= nil or (Room and Room:FindFirstChild("StairwellLandingLogic", true) ~= nil)
            return StairwellContext, Distance, "object"
        end
        local function StopFix()
            if FixConnection then FixConnection:Disconnect() FixConnection = nil end
            if CandidateConnection then CandidateConnection:Disconnect() CandidateConnection = nil end
            table.clear(Candidates)
            RestoreManaged()
        end
        local function StartFix(Value)
            StopFix()
            if not Value then return end
            local function AddCandidate(Object)
                if Object:IsA("ProximityPrompt") and not Object:GetAttribute("FakePrompt")
                    and (
                        (Object.Name == "CartPrompt" and Ancestor(Object, "ArchivesOfficeChair"))
                        or ((Object.Name == "CartPrompt" or Object.Name == "PushPrompt" or Object.Name == "LongPushPrompt" or Object.Name == "BigPropPrompt") and Ancestor(Object, "ShoppingCart"))
                        or (Object.Name == "InteractPrompt" and Ancestor(Object, "OneWayTwoHandDoor"))
                    )
                then
                    Candidates[Object] = true
                end
            end
            for _, Object in workspace:GetDescendants() do AddCandidate(Object) end
            CandidateConnection = workspace.DescendantAdded:Connect(AddCandidate)
            FixConnection = RunService.Heartbeat:Connect(function()
                if tick() - LastFix < 0.05 then return end
                LastFix = tick()
                local Keep, KeepDoors = {}, {}
                local BestDoor, BestDoorDistance, BestObject, BestObjectDistance
                for Prompt in Candidates do
                    local Valid, Distance, Kind = CurrentObjectPrompt(Prompt)
                    if Valid and Kind == "door" and (not BestDoorDistance or Distance < BestDoorDistance) then
                        BestDoor, BestDoorDistance = Prompt, Distance
                    elseif Valid and Kind == "object" and (not BestObjectDistance or Distance < BestObjectDistance) then
                        BestObject, BestObjectDistance = Prompt, Distance
                    elseif not Prompt:IsDescendantOf(workspace) then
                        Candidates[Prompt] = nil
                    end
                end
                if BestDoor then
                    KeepDoors[BestDoor] = true
                    if not ManagedDoors[BestDoor] then
                        ManagedDoors[BestDoor] = {
                            Enabled = BestDoor.Enabled,
                            GateDisabled = BestDoor:GetAttribute("_GateDisabled"),
                            GateReason = BestDoor:GetAttribute("_GateReason"),
                        }
                    end
                    BestDoor:SetAttribute("_GateDisabled", nil)
                    BestDoor:SetAttribute("_GateReason", nil)
                    if not BestDoor.Enabled then BestDoor.Enabled = true end
                end
                if BestObject then
                    Keep[BestObject] = true
                    if not Managed[BestObject] and not BestObject.Enabled then Managed[BestObject] = true end
                    if Managed[BestObject] and not BestObject.Enabled then BestObject.Enabled = true end
                end
                RestoreManaged(Keep, KeepDoors)
            end)
        end
        Toggles.FloorObjectInteractionFix:OnChanged(StartFix)
        pcall(function() Library:OnUnload(function()
            ClearProbeConnections()
            StopFix()
        end) end)
    end

    ---------------------------------------------------------------------
    -- Safe functions imported from the comparison script (missing only)
    ---------------------------------------------------------------------
    do
        Groupboxes.Imported_Gameplay = Tabs.Exploits:AddLeftGroupbox("Gameplay / Safety v2")
        Groupboxes.Imported_Automation = Tabs.Floors:AddLeftGroupbox("Automation v2")
        Groupboxes.Imported_Visual = Tabs.Visuals:AddRightGroupbox("Camera / ESP v2")
        Groupboxes.Imported_Utility = Tabs.General:AddRightGroupbox("Shop / Utility v2")
        local GameBox, AutoBox, VisualBox, UtilityBox = Groupboxes.Imported_Gameplay, Groupboxes.Imported_Automation, Groupboxes.Imported_Visual, Groupboxes.Imported_Utility

        GameBox:AddToggle("ImportedWalkspeed", { Text = "Walkspeed Override", Default = false })
        GameBox:AddSlider("ImportedWalkspeedValue", { Text = "Walkspeed", Default = 22, Min = 5, Max = 100, Rounding = 0, Compact = true })
        GameBox:AddDropdown("ImportedSpeedMode", { Text = "Speed Method", Values = { "WalkSpeed", "Velocity" }, Default = 1 })
        GameBox:AddToggle("ImportedPhase", { Text = "Phase", Default = false, Tooltip = "Camera-relative movement with collision disabled while active." })
        GameBox:AddSlider("ImportedPhaseSpeed", { Text = "Phase Speed", Default = 22, Min = 5, Max = 60, Rounding = 0, Compact = true })
        GameBox:AddToggle("ImportedSmartGodmode", { Text = "Smart Godmode", Default = false })
        GameBox:AddDropdown("ImportedGodmodeMethod", { Text = "Godmode Method", Values = { "Always", "On Entity Spawn" }, Default = 2 })
        GameBox:AddToggle("ImportedNotifyVulnerable", { Text = "Notify When Vulnerable", Default = false, Tooltip = "Warns when a sudden vertical displacement can expose the real position." })
        GameBox:AddToggle("ImportedAntiCrusher", { Text = "Anti Crusher (all)", Default = false })
        GameBox:AddToggle("ImportedMeldAntiLag", { Text = "Hide Meld (restorable)", Default = false })
        GameBox:AddToggle("ImportedRemoveHasteSound", { Text = "Remove Haste Sound", Default = false })
        GameBox:AddToggle("ImportedDroneTimer", { Text = "Drone Stampede Timer Alerts", Default = false })
        GameBox:AddToggle("ImportedBypassMonument", { Text = "Anti Monument", Default = false, Disabled = not Functions.CheckCompatability({"hookmetamethod", "newcclosure", "getnamecallmethod"}), DisabledTooltip = Globals.IncompatibleMessage })

        AutoBox:AddToggle("ImportedLegitBreaker", { Text = "Legit Breaker Solver", Default = false, Tooltip = "Activates enabled breaker switches one by one." })
        AutoBox:AddToggle("ImportedHotelPath", { Text = "Hotel Pathfinding", Default = false })
        AutoBox:AddToggle("ImportedHotelShowPath", { Text = "Show Hotel Path", Default = false })
        AutoBox:AddSlider("ImportedHotelTimeout", { Text = "Pathfind Timeout v2", Default = 4, Min = 1, Max = 15, Rounding = 1, Compact = true })
        AutoBox:AddToggle("ImportedAutoCharles", { Text = "Auto Charles Minigame", Default = false })

        VisualBox:AddToggle("ImportedFullbright", { Text = "Fullbright", Default = false })
        VisualBox:AddSlider("ImportedFullbrightBrightness", { Text = "Brightness", Default = 3, Min = 1, Max = 10, Rounding = 1, Compact = true })
        VisualBox:AddToggle("ImportedFreecam", { Text = "Freecam v2", Default = false })
        Toggles.ImportedFreecam:AddKeyPicker("ImportedFreecamKey", { Text = "Freecam", Default = "Q", Mode = "Toggle", SyncToggleState = true })
        VisualBox:AddSlider("ImportedFreecamSpeed", { Text = "Freecam Speed", Default = 75, Min = 10, Max = 300, Rounding = 0, Compact = true })
        VisualBox:AddToggle("ImportedESPOutline", { Text = "Custom ESP Outline", Default = false })
        Toggles.ImportedESPOutline:AddColorPicker("ImportedESPOutlineColor", { Text = "ESP Outline", Default = Color3.new(1, 1, 1), Transparency = 0 })
        VisualBox:AddSlider("ImportedESPMaxDistance", { Text = "ESP Max Distance", Default = 5000, Min = 50, Max = 5000, Rounding = 0, Compact = true })
        VisualBox:AddToggle("ImportedItemChat", { Text = "Item Notifications To Chat", Default = false })
        VisualBox:AddInput("ImportedItemChatMessage", { Text = "Item Chat Message", Default = "Item: {item}", Placeholder = "{item}", Finished = false })

        UtilityBox:AddSlider("ImportedBuyCount", { Text = "Purchase Count", Default = 3, Min = 1, Max = 6, Rounding = 0, Compact = true })
        UtilityBox:AddDropdown("ImportedBuyItems", { Text = "Items To Buy", Values = { "Lockpick", "Lighter", "Flashlight", "Vitamins", "Crucifix", "Skeleton Key" }, Multi = true, AllowNull = true })
        UtilityBox:AddButton({ Text = "Buy Selected Items", Func = function()
            local Remote = RemotesFolder and RemotesFolder:FindFirstChild("PreRunShop")
            if not Remote then Functions.Notify({ Title = "Pre-run shop remote not found" }) return end
            local Items = {}
            for Name, Enabled in Options.ImportedBuyItems.Value or {} do
                if Enabled then for _ = 1, Options.ImportedBuyCount.Value do Items[#Items + 1] = Name end end
            end
            if #Items > 0 then Remote:FireServer(Items, false) end
        end })
        UtilityBox:AddToggle("ImportedShowCrucifix", { Text = "Show Shop Crucifix", Default = false })
        UtilityBox:AddToggle("ImportedShowSkeletonKey", { Text = "Show Shop Skeleton Key", Default = false })

        ----------------------------------------------------------------- shared movement / safety loop
        local PhaseCollision = setmetatable({}, { __mode = "k" })
        local GodmodeOwned, LastY, LastVulnerable = false, nil, 0
        Connections.ImportedGameplay = RunService.Heartbeat:Connect(function(Dt)
            if not Alive or not Character or not Humanoid or not RootPart then return end
            if Toggles.ImportedWalkspeed.Value then
                local Speed = Options.ImportedWalkspeedValue.Value
                if Options.ImportedSpeedMode.Value == "WalkSpeed" then
                    Humanoid.WalkSpeed = Speed
                elseif Humanoid.MoveDirection.Magnitude > 0 then
                    local Current = RootPart.AssemblyLinearVelocity
                    local Flat = Humanoid.MoveDirection.Unit * Speed
                    RootPart.AssemblyLinearVelocity = Vector3.new(Flat.X, Current.Y, Flat.Z)
                end
            end
            if Toggles.ImportedPhase.Value then
                for _, Part in Character:GetDescendants() do
                    if Part:IsA("BasePart") then
                        if PhaseCollision[Part] == nil then PhaseCollision[Part] = Part.CanCollide end
                        Part.CanCollide = false
                    end
                end
                local Camera = workspace.CurrentCamera
                local Controls
                pcall(function() Controls = require(LocalPlayer.PlayerScripts.PlayerModule):GetControls() end)
                local Move = Controls and Controls:GetMoveVector() or Vector3.zero
                if Camera then
                    local Forward = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z)
                    Forward = Forward.Magnitude > 0.01 and Forward.Unit or Vector3.new(0, 0, -1)
                    local Right = Forward:Cross(Vector3.yAxis)
                    local World = Right * Move.X + Forward * -Move.Z
                    local Vertical = Services.UserInputService:IsKeyDown(Enum.KeyCode.Space) and 1 or Services.UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and -1 or 0
                    local Direction = World + Vector3.yAxis * Vertical
                    RootPart.AssemblyLinearVelocity = Direction.Magnitude > 0.01 and Direction.Unit * Options.ImportedPhaseSpeed.Value or Vector3.zero
                end
            elseif next(PhaseCollision) then
                for Part, Value in PhaseCollision do if Part.Parent then Part.CanCollide = Value end PhaseCollision[Part] = nil end
            end
            if Toggles.ImportedSmartGodmode.Value then
                local Want = Options.ImportedGodmodeMethod.Value == "Always"
                if not Want then
                    for _, Entity in Objects.Entities do
                        local Part = Entity and Entity:IsA("Model") and Entity.PrimaryPart
                        if Part and (Part.Position - RootPart.Position).Magnitude < 120 then Want = true break end
                    end
                end
                if Want ~= GodmodeOwned then GodmodeOwned = Want Toggles.PositionSpoof:SetValue(Want) end
            elseif GodmodeOwned then
                GodmodeOwned = false Toggles.PositionSpoof:SetValue(false)
            end
            if Toggles.ImportedNotifyVulnerable.Value then
                local Y = RootPart.Position.Y
                if LastY and math.abs(Y - LastY) > 3 and tick() - LastVulnerable > 4 then
                    LastVulnerable = tick()
                    Functions.Notify({ Title = "Position vulnerable", Body = string.format("Vertical change: %.1f studs", Y - LastY), Time = 3 })
                end
                LastY = Y
            else LastY = RootPart.Position.Y end
        end)
        pcall(function() Library:OnUnload(function()
            for Part, Value in PhaseCollision do if Part.Parent then Part.CanCollide = Value end end
            if GodmodeOwned and Toggles.PositionSpoof then Toggles.PositionSpoof:SetValue(false) end
        end) end)

        ----------------------------------------------------------------- crusher / meld / haste
        do
            local CrusherParts, CrusherConnection = setmetatable({}, { __mode = "k" }), nil
            local function UnderBasicWall(Object, Root)
                local Node = Object.Parent
                while Node and Node ~= Root do if Node.Name == "BasicWall" then return true end Node = Node.Parent end
                return false
            end
            local function ProcessCrusher(Object)
                if not Object.Name:match("^StairwellCrusherContainer%d+$") then return end
                for _, Part in Object:GetDescendants() do
                    if Part:IsA("BasePart") and not UnderBasicWall(Part, Object) then
                        if not CrusherParts[Part] then CrusherParts[Part] = { Part.CanCollide, Part.CanTouch } end
                        Part.CanCollide, Part.CanTouch = false, false
                    end
                end
            end
            Toggles.ImportedAntiCrusher:OnChanged(function(Value)
                if CrusherConnection then CrusherConnection:Disconnect() CrusherConnection = nil end
                if not Value then
                    for Part, Old in CrusherParts do if Part.Parent then Part.CanCollide, Part.CanTouch = Old[1], Old[2] end CrusherParts[Part] = nil end
                    return
                end
                for _, Object in workspace:GetDescendants() do ProcessCrusher(Object) end
                CrusherConnection = workspace.DescendantAdded:Connect(function(Object) if Toggles.ImportedAntiCrusher.Value then ProcessCrusher(Object) end end)
            end)

            local MeldNames = { Burnt=true, Feelers=true, MeldData=true, MeldPads=true, Mounds=true, SplotchesBottom=true, SplotchesTop=true, Spots1=true, Spots2=true, Strings=true }
            local MeldSaved, MeldConnection = setmetatable({}, { __mode = "k" }), nil
            local function HideMeld(Object)
                if not MeldNames[Object.Name] then return end
                for _, Desc in { Object, table.unpack(Object:GetDescendants()) } do
                    if Desc:IsA("BasePart") or Desc:IsA("Decal") or Desc:IsA("Texture") then
                        if MeldSaved[Desc] == nil then MeldSaved[Desc] = Desc.Transparency end Desc.Transparency = 1
                    elseif Desc:IsA("ParticleEmitter") or Desc:IsA("Beam") or Desc:IsA("Trail") then
                        if MeldSaved[Desc] == nil then MeldSaved[Desc] = Desc.Enabled end Desc.Enabled = false
                    end
                end
            end
            Toggles.ImportedMeldAntiLag:OnChanged(function(Value)
                if MeldConnection then MeldConnection:Disconnect() MeldConnection = nil end
                if not Value then
                    for Object, Old in MeldSaved do if Object.Parent then if type(Old) == "boolean" then Object.Enabled = Old else Object.Transparency = Old end end MeldSaved[Object] = nil end
                    return
                end
                for _, Object in CurrentRooms:GetDescendants() do HideMeld(Object) end
                MeldConnection = CurrentRooms.DescendantAdded:Connect(function(Object) if Toggles.ImportedMeldAntiLag.Value then HideMeld(Object) end end)
            end)

            local HasteSound, HastePlaying, HasteConnection
            local function ApplyHasteSound()
                local Haste = FloorReplicated and FloorReplicated:FindFirstChild("Haste", true)
                local Sound = Haste and (Haste:FindFirstChild("Ambience", true) or Haste:FindFirstChildWhichIsA("Sound", true))
                if Sound and Sound:IsA("Sound") then
                    if HasteSound ~= Sound then HasteSound, HastePlaying = Sound, Sound.Playing end
                    if Sound.Playing then Sound:Stop() end
                end
            end
            Toggles.ImportedRemoveHasteSound:OnChanged(function(Value)
                if HasteConnection then HasteConnection:Disconnect() HasteConnection = nil end
                if not Value then if HasteSound and HasteSound.Parent and HastePlaying then HasteSound:Play() end HasteSound = nil return end
                ApplyHasteSound()
                HasteConnection = FloorReplicated.DescendantAdded:Connect(function() task.defer(ApplyHasteSound) end)
            end)
            pcall(function() Library:OnUnload(function()
                if CrusherConnection then CrusherConnection:Disconnect() end
                if MeldConnection then MeldConnection:Disconnect() end
                if HasteConnection then HasteConnection:Disconnect() end
                for Part, Old in CrusherParts do if Part.Parent then Part.CanCollide, Part.CanTouch = Old[1], Old[2] end end
                for Object, Old in MeldSaved do if Object.Parent then if type(Old) == "boolean" then Object.Enabled = Old else Object.Transparency = Old end end end
                if HasteSound and HasteSound.Parent and HastePlaying then HasteSound:Play() end
            end) end)
        end

        ----------------------------------------------------------------- automation
        do
            local BreakerConnection, HotelToken, LastBreaker = nil, 0, 0
            Toggles.ImportedLegitBreaker:OnChanged(function(Value)
                if BreakerConnection then BreakerConnection:Disconnect() BreakerConnection = nil end
                if not Value then return end
                BreakerConnection = RunService.Heartbeat:Connect(function()
                    if tick() - LastBreaker < 0.2 then return end
                    LastBreaker = tick()
                    local Breaker = CurrentRooms:FindFirstChild("ElevatorBreaker", true)
                    if not Breaker then return end
                    for _, Switch in Breaker:GetDescendants() do
                        if Switch.Name == "BreakerSwitch" and Switch:GetAttribute("Enabled") ~= false then
                            local Prompt = Switch:FindFirstChildWhichIsA("ProximityPrompt", true)
                            if Prompt and Prompt.Enabled then Functions.FirePrompt(Prompt) break end
                        end
                    end
                end)
            end)

            local PathFolder = New("Folder", { Name = "AMRImportedHotelPath" }, workspace)
            local function ClearPath() PathFolder:ClearAllChildren() end
            Toggles.ImportedHotelPath:OnChanged(function(Value)
                HotelToken += 1
                ClearPath()
                if not Value then return end
                local Token = HotelToken
                task.spawn(function()
                    local Pathfinding = game:GetService("PathfindingService")
                    while Alive and Token == HotelToken and Toggles.ImportedHotelPath.Value do
                        task.wait(0.3)
                        if not RootPart or not Humanoid or Humanoid.Health <= 0 then continue end
                        local Latest = LatestRoom and LatestRoom.Value
                        local Room = CurrentRooms and Latest and CurrentRooms:FindFirstChild(tostring(Latest))
                        local Door = Room and (Room:FindFirstChild("Door") or Room:FindFirstChild("RoomExit"))
                        if not Door then continue end
                        local Goal = Door:IsA("Model") and Door:GetPivot().Position or Door.Position
                        local Path = Pathfinding:CreatePath({ AgentCanJump = true, WaypointSpacing = 4 })
                        local Ok = pcall(Path.ComputeAsync, Path, RootPart.Position, Goal)
                        if not Ok or Path.Status ~= Enum.PathStatus.Success then continue end
                        ClearPath()
                        for _, Waypoint in Path:GetWaypoints() do
                            if Toggles.ImportedHotelShowPath.Value then New("Part", { Size = Vector3.new(0.25, 0.25, 0.25), Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Color3.fromRGB(70, 220, 255), Anchored = true, CanCollide = false, Position = Waypoint.Position }, PathFolder) end
                            Humanoid:MoveTo(Waypoint.Position)
                            if Waypoint.Action == Enum.PathWaypointAction.Jump then Humanoid.Jump = true end
                            local Until = tick() + Options.ImportedHotelTimeout.Value
                            while Token == HotelToken and RootPart and (RootPart.Position - Waypoint.Position).Magnitude > 3 and tick() < Until do RunService.Heartbeat:Wait() end
                            if Token ~= HotelToken or not RootPart or (RootPart.Position - Waypoint.Position).Magnitude > 5 then break end
                        end
                    end
                end)
            end)

            local CharlesConnections, CharlesRun = {}, 0
            local function ClearCharles() for _, C in CharlesConnections do C:Disconnect() end table.clear(CharlesConnections) CharlesRun += 1 end
            local function RunCharles(Tool)
                if Tool.Name ~= "ObjectScanner" then return end
                CharlesRun += 1 local Run = CharlesRun
                task.spawn(function()
                    local Remote = Tool:WaitForChild("Remote", 5)
                    if not Remote then return end
                    for _ = 1, 40 do
                        if Run ~= CharlesRun or Tool.Parent ~= LocalPlayer.Character then return end
                        if string.lower(tostring(Tool:GetAttribute("ScannerMode") or "")) == "egg" then break end
                        Remote:FireServer() task.wait(0.3)
                    end
                    if string.lower(tostring(Tool:GetAttribute("ScannerMode") or "")) ~= "egg" then return end
                    local Egg = RemotesFolder:WaitForChild("EggGame", 10)
                    local Won = Egg and Egg:WaitForChild("WonRound", 10)
                    if Won then Won:FireServer(1) task.wait(0.1) Won:FireServer(2) task.wait(0.1) Won:FireServer(3, true, true) end
                end)
            end
            local function WatchCharles(Char)
                local Tool = Char:FindFirstChild("ObjectScanner") if Tool then RunCharles(Tool) end
                CharlesConnections[#CharlesConnections + 1] = Char.ChildAdded:Connect(RunCharles)
            end
            Toggles.ImportedAutoCharles:OnChanged(function(Value)
                ClearCharles() if not Value then return end
                if LocalPlayer.Character then WatchCharles(LocalPlayer.Character) end
                CharlesConnections[#CharlesConnections + 1] = LocalPlayer.CharacterAdded:Connect(WatchCharles)
            end)
            pcall(function() Library:OnUnload(function()
                HotelToken += 1
                if BreakerConnection then BreakerConnection:Disconnect() BreakerConnection = nil end
                ClearCharles()
                ClearPath()
                if PathFolder then PathFolder:Destroy() end
            end) end)
        end

        ----------------------------------------------------------------- visual / utility callbacks
        do
            local FullbrightSaved, FullbrightConnection
            local function ApplyFullbright()
                Services.Lighting.Ambient = Color3.new(1, 1, 1)
                Services.Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
                Services.Lighting.GlobalShadows = false
                Services.Lighting.Brightness = Options.ImportedFullbrightBrightness.Value
                Services.Lighting.ClockTime = 14
                Services.Lighting.FogEnd = 1e9
            end
            Toggles.ImportedFullbright:OnChanged(function(Value)
                if FullbrightConnection then FullbrightConnection:Disconnect() FullbrightConnection = nil end
                if Value then
                    FullbrightSaved = { Ambient=Services.Lighting.Ambient, OutdoorAmbient=Services.Lighting.OutdoorAmbient, GlobalShadows=Services.Lighting.GlobalShadows, Brightness=Services.Lighting.Brightness, ClockTime=Services.Lighting.ClockTime, FogEnd=Services.Lighting.FogEnd }
                    ApplyFullbright()
                    FullbrightConnection = RunService.Heartbeat:Connect(ApplyFullbright)
                elseif FullbrightSaved then
                    for Key, Old in FullbrightSaved do Services.Lighting[Key] = Old end FullbrightSaved = nil
                end
            end)

            local Freecam
            local function StopFreecam()
                local Current = Freecam Freecam = nil Globals.Freeze.ImportedFreecam = nil
                if not Current then return end
                if Current.Connection then Current.Connection:Disconnect() end
                local Camera = workspace.CurrentCamera
                if Camera then Camera.CameraType = Current.Type Camera.CameraSubject = Current.Subject Camera.CFrame = Current.CFrame end
            end
            Toggles.ImportedFreecam:OnChanged(function(Value)
                StopFreecam() if not Value then return end
                local Camera = workspace.CurrentCamera if not Camera then return end
                Globals.Freeze.ImportedFreecam = true
                local Controls pcall(function() Controls = require(LocalPlayer.PlayerScripts.PlayerModule):GetControls() end)
                local Pitch, Yaw = Camera.CFrame:ToOrientation()
                local Current = { CFrame=Camera.CFrame, Type=Camera.CameraType, Subject=Camera.CameraSubject, Position=Camera.CFrame.Position, Pitch=Pitch, Yaw=Yaw }
                Freecam = Current Camera.CameraType = Enum.CameraType.Scriptable
                Current.Connection = RunService.RenderStepped:Connect(function(Dt)
                    if Freecam ~= Current then return end
                    local Delta = Services.UserInputService:GetMouseDelta()
                    Current.Pitch = math.clamp(Current.Pitch - Delta.Y * 0.003, -1.4, 1.4)
                    Current.Yaw -= Delta.X * 0.003
                    local Frame = CFrame.fromOrientation(Current.Pitch, Current.Yaw, 0)
                    local Move = Controls and Controls:GetMoveVector() or Vector3.zero
                    Current.Position += (Frame.RightVector * Move.X + Frame.LookVector * -Move.Z) * Options.ImportedFreecamSpeed.Value * Dt
                    Camera.CFrame = CFrame.new(Current.Position) * Frame Camera.Focus = Camera.CFrame * CFrame.new(0, 0, -10)
                end)
            end)

            local function ShopItem(Name, Visible)
                local MainUI = LocalPlayer.PlayerGui:FindFirstChild("MainUI")
                local Items = MainUI and MainUI:FindFirstChild("ItemShop") and MainUI.ItemShop:FindFirstChild("Items")
                local Item = Items and Items:FindFirstChild(Name) if Item then Item.Visible = Visible end
            end
            Toggles.ImportedShowCrucifix:OnChanged(function(V) ShopItem("ItemShop_Crucifix", V) end)
            Toggles.ImportedShowSkeletonKey:OnChanged(function(V) ShopItem("ItemShop_Skeleton Key", V) end)
            Toggles.ImportedESPOutline:OnChanged(function(V) Abysall.ESPLibrary:SetMatchColors(not V) if V then Abysall.ESPLibrary:SetOutlineColor(Options.ImportedESPOutlineColor.Value) end end)
            Options.ImportedESPOutlineColor:OnChanged(function(V) if Toggles.ImportedESPOutline.Value then Abysall.ESPLibrary:SetOutlineColor(V) end end)
            Connections.ImportedESPDistance = RunService.RenderStepped:Connect(function()
                local Camera = workspace.CurrentCamera if not Camera then return end
                local Limit = Options.ImportedESPMaxDistance.Value
                if Limit >= 5000 then return end
                for _, Object in Abysall.ESPLibrary.TotalObjects do
                    if Object and Object.Parent then
                        local Far = (Object:GetPivot().Position - Camera.CFrame.Position).Magnitude > Limit
                        local Highlight = Abysall.ESPLibrary.Highlights[Object] if Highlight then Highlight.Enabled = not Far end
                        local Frame = Abysall.ESPLibrary.Frames[Object] if Frame and Far then Frame.Visible = false end
                        local Line = Abysall.ESPLibrary.Lines[Object] if Line and Line[1] and Far then Line[1].Visible = false end
                    end
                end
            end)
            local Alerted60, Alerted30 = false, false
            task.spawn(function()
                while Alive do
                    task.wait(1)
                    if Toggles.ImportedDroneTimer.Value then
                        local Clock = CurrentRooms:FindFirstChild("ArchivesClock", true)
                        local Label = Clock and Clock:FindFirstChildWhichIsA("TextLabel", true)
                        local Minutes, Seconds = Label and string.match(Label.Text, "(%d+):(%d+)")
                        local Left = Minutes and tonumber(Minutes) * 60 + tonumber(Seconds) or nil
                        if Left and Left <= 60 and not Alerted60 then Alerted60 = true Functions.Notify({ Title="Drone Stampede", Body="About 60 seconds remaining." }) end
                        if Left and Left <= 30 and not Alerted30 then Alerted30 = true Functions.Notify({ Title="Drone Stampede", Body="About 30 seconds remaining." }) end
                    else Alerted60, Alerted30 = false, false end
                end
            end)
            pcall(function() Library:OnUnload(function()
                StopFreecam()
                if FullbrightConnection then FullbrightConnection:Disconnect() end
                if FullbrightSaved then for Key, Old in FullbrightSaved do Services.Lighting[Key] = Old end end
                Abysall.ESPLibrary:SetMatchColors(true)
            end) end)
        end
    end

    ---------------------------------------------------------------------
    -- Chair anticheat bypass (ride a dragged office chair through walls) + Minecart bypass
    ---------------------------------------------------------------------
    do
        local UIS = Services.UserInputService
        local Box = Groupboxes.Archives_Experimental
        Box:AddDivider()
        Box:AddLabel("Chair Anticheat Bypass")
        Box:AddToggle("ChairFly", {
            Text = "Chair Anticheat Bypass", Default = false,
            Tooltip = "Drag an office chair (hold the prompt from behind, release), sit in it. Once you are next to it the chair becomes your vehicle: move with stick/WASD, camera aims, jump = up, Shift = down. Turn the toggle off to stop."
        })
        Box:AddSlider("ChairFlySpeed", { Text = "Chair Speed", Default = 55, Min = 15, Max = 150, Rounding = 0, Compact = true })

        local State
        local function ColliderOf(Chair)
            return Chair:FindFirstChild("Collider") or Chair.PrimaryPart or Chair:FindFirstChildWhichIsA("BasePart")
        end
        local function NearestChair()
            if not RootPart then return nil end
            local Best, BestDistance = nil, math.huge
            local function Check(Object)
                if Object:IsA("Model") and (Object.Name == "ArchivesOfficeChair" or Object.Name == "StairwellOfficeChair") then
                    local Collider = ColliderOf(Object)
                    if Collider then
                        local Distance = (RootPart.Position - Collider.Position).Magnitude
                        if Distance < BestDistance then Best, BestDistance = Object, Distance end
                    end
                end
            end
            local Misc = workspace:FindFirstChild("Misc")
            if Misc then for _, Object in Misc:GetDescendants() do Check(Object) end end
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            if Rooms then
                for _, Room in Rooms:GetChildren() do
                    local Assets = Room:FindFirstChild("Assets")
                    if Assets then for _, Object in Assets:GetChildren() do Check(Object) end end
                end
            end
            return Best
        end
        local function StopChair()
            local Current = State
            if not Current then return end
            State = nil
            if Current.Poll then Current.Poll:Disconnect() end
            if Current.Move then Current.Move:Disconnect() end
            for Part, Value in Current.Collision or {} do
                if Part.Parent then Part.CanCollide = Value end
            end
            if Current.Collider and Current.Collider.Parent then
                pcall(function()
                    Current.Collider.AssemblyLinearVelocity = Vector3.zero
                    Current.Collider.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
        local function StartChair(Chair)
            local Collider = ColliderOf(Chair)
            if not Collider then return false end
            local Current = { Chair = Chair, Collider = Collider, Collision = {} }
            State = Current
            for _, Part in Chair:GetDescendants() do
                if Part:IsA("BasePart") then Current.Collision[Part] = Part.CanCollide Part.CanCollide = false end
            end
            Current.Move = RunService.Heartbeat:Connect(function()
                if State ~= Current or not Collider.Parent then return end
                for Part in Current.Collision do if Part.Parent and Part.CanCollide then Part.CanCollide = false end end
                local Camera = workspace.CurrentCamera
                if not Camera or not Humanoid then return end
                local Look = Camera.CFrame.LookVector
                local Right = Vector3.new(Camera.CFrame.RightVector.X, 0, Camera.CFrame.RightVector.Z)
                Right = Right.Magnitude > 0.01 and Right.Unit or Vector3.xAxis
                local FlatLook = Vector3.new(Look.X, 0, Look.Z)
                FlatLook = FlatLook.Magnitude > 0.01 and FlatLook.Unit or Vector3.zAxis * -1
                local Direction = Humanoid.MoveDirection
                local Forward, Side = Direction:Dot(FlatLook), Direction:Dot(Right)
                local Vertical = (Humanoid.Jump and 1 or 0) - ((UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)) and 1 or 0)
                local Velocity = Look * Forward + Right * Side + Vector3.yAxis * Vertical
                Collider.AssemblyLinearVelocity = Velocity.Magnitude > 0.05 and Velocity.Unit * Options.ChairFlySpeed.Value or Vector3.zero
                Collider.AssemblyAngularVelocity = Vector3.zero
            end)
            return true
        end
        Toggles.ChairFly:OnChanged(function(Value)
            StopChair()
            if not Value then return end
            local Waiting = {}
            State = Waiting
            Functions.Notify({ Title = "Chair bypass", Body = "Drag a chair (hold prompt from behind, release), sit in it and stay next to it.", Time = 5 })
            Waiting.Poll = RunService.Heartbeat:Connect(function()
                if State ~= Waiting or not Toggles.ChairFly.Value then Waiting.Poll:Disconnect() return end
                local Chair = NearestChair()
                local Collider = Chair and ColliderOf(Chair)
                if Collider and RootPart and (RootPart.Position - Collider.Position).Magnitude < 8 then
                    Waiting.Poll:Disconnect()
                    if StartChair(Chair) then
                        Functions.Notify({ Title = "Chair bypass", Body = "Active. Turn the toggle off to stop.", Time = 4 })
                    end
                end
            end)
        end)
        pcall(function() Library:OnUnload(StopChair) end)

        do
            Groupboxes.Imported_FPV = Groupboxes.Imported_FPV or Tabs.Archives:AddLeftGroupbox("FPV Chair")
            local FPVBox = Groupboxes.Imported_FPV
            FPVBox:AddToggle("FPVChair", {
                Text = "FPV Chair", Default = false,
                Tooltip = "Hold and release an office-chair Push prompt from behind. Your character freezes; WASD/mobile stick moves only the chair."
            })
            FPVBox:AddDropdown("FPVChairTarget", { Text = "Chair Target", Values = { "Self" }, Default = 1 })
            FPVBox:AddSlider("FPVChairSpeed", { Text = "Chair Flight Speed", Default = 55, Min = 15, Max = 120, Rounding = 0, Compact = true })
            FPVBox:AddToggle("FPVChairCollide", { Text = "Chair Collision", Default = true, Tooltip = "On: the chair collides with floors and walls and cannot fall through. Off: it passes through everything." })
            FPVBox:AddSlider("FPVChairLookSpeed", { Text = "Look Speed", Default = 1.5, Min = 0.3, Max = 4, Rounding = 1, Compact = true })
            FPVBox:AddSlider("FPVChairEyeHeight", { Text = "Camera Height", Default = 1.6, Min = 0, Max = 4, Rounding = 1, Compact = true })

            local FPV = { Token = 0, Connections = {} }
            local function DisconnectFPV()
                for _, Connection in FPV.Connections do pcall(function() Connection:Disconnect() end) end
                table.clear(FPV.Connections)
            end
            local function StopFPVChair()
                FPV.Token += 1
                DisconnectFPV()
                Globals.FPVChairActive = nil
                Globals.Freeze.FPVChair = nil
                local Current = FPV.Current
                FPV.Current, FPV.Pending = nil, nil
                if not Current then return end
                if Current.Humanoid and Current.Humanoid.Parent then Current.Humanoid.AutoRotate = Current.OldAutoRotate end
                local Camera = workspace.CurrentCamera
                if Camera and Current.OldCameraSubject then
                    Camera.CameraSubject = Current.OldCameraSubject
                    Camera.CameraType = Current.OldCameraType or Enum.CameraType.Custom
                end
                if Current.CameraAnchor then Current.CameraAnchor:Destroy() end
                if Current.Gui then Current.Gui:Destroy() end
                pcall(function() Services.UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
                for Part, Value in Current.ChairCollision or {} do
                    if Part.Parent then Part.CanCollide = Value Part.LocalTransparencyModifier = 0 end
                end
                if Current.DrivePart and Current.DrivePart.Parent then
                    Current.DrivePart.AssemblyLinearVelocity = Current.OldLinear or Vector3.zero
                    Current.DrivePart.AssemblyAngularVelocity = Current.OldAngular or Vector3.zero
                end
            end
            local function ChairFromPrompt(Prompt)
                local Node = Prompt
                while Node and Node ~= workspace do
                    if Node:IsA("Model") and (Node.Name == "ArchivesOfficeChair" or Node.Name == "StairwellOfficeChair") then return Node end
                    Node = Node.Parent
                end
                return nil
            end
            local function ChairTarget()
                if true then
                    local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    return LocalPlayer, Root
                end
                if Boot.GetSocialTarget then return Boot.GetSocialTarget() end
                return nil, nil
            end
            local function StartFPVControl(Pending)
                if FPV.Current or not Toggles.FPVChair.Value then return end
                local Chair, DrivePart = Pending.Chair, ColliderOf(Pending.Chair)
                local TargetPlayer, TargetRoot = ChairTarget()
                local SourceCharacter = LocalPlayer.Character
                local SourceHumanoid = SourceCharacter and SourceCharacter:FindFirstChildOfClass("Humanoid")
                if not Chair or not DrivePart or not TargetPlayer or not TargetRoot or not SourceHumanoid then
                    Functions.Notify({ Title = "FPV Chair", Body = "Chair or selected target is unavailable." })
                    Toggles.FPVChair:SetValue(false)
                    return
                end
                if Toggles.ChairFly.Value then Toggles.ChairFly:SetValue(false) end
                local Controls
                pcall(function() Controls = require(LocalPlayer.PlayerScripts.PlayerModule):GetControls() end)
                local Camera = workspace.CurrentCamera
                local CameraAnchor = New("Part", {
                    Name = "AMRFPVChairCamera", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1,
                    Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
                    CFrame = CFrame.new(DrivePart.Position),
                }, workspace)
                local ChairCollision = {}
                for _, Part in Chair:GetDescendants() do
                    if Part:IsA("BasePart") then ChairCollision[Part] = Part.CanCollide Part.CanCollide = Toggles.FPVChairCollide.Value end
                end
                local Current = {
                    ChairCollision = ChairCollision, Chair = Chair, DrivePart = DrivePart, Target = TargetPlayer, SourceCharacter = SourceCharacter,
                    Humanoid = SourceHumanoid, OldAutoRotate = SourceHumanoid.AutoRotate, Controls = Controls,
                    CameraAnchor = CameraAnchor, OldCameraSubject = Camera and Camera.CameraSubject,
                    OldCameraType = Camera and Camera.CameraType, OldLinear = DrivePart.AssemblyLinearVelocity,
                    OldAngular = DrivePart.AssemblyAngularVelocity, StartPosition = DrivePart.Position,
                    Departed = false, ScareAt = nil,
                }
                FPV.Current = Current
                Globals.Freeze.FPVChair = true
                SourceHumanoid.AutoRotate = false
                do
                    local Look = Camera and Camera.CFrame.LookVector or Vector3.new(0, 0, -1)
                    Current.Yaw, Current.Pitch = math.atan2(-Look.X, -Look.Z), math.asin(math.clamp(Look.Y, -1, 1))
                end
                if Camera then Camera.CameraType = Enum.CameraType.Scriptable end
                pcall(function() Services.UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end)
                FPV.Connections[#FPV.Connections + 1] = Services.UserInputService.InputChanged:Connect(function(Input, Processed)
                    if FPV.Current ~= Current then return end
                    if Input.UserInputType == Enum.UserInputType.MouseMovement then
                        Current.Yaw -= Input.Delta.X * 0.0025 * Options.FPVChairLookSpeed.Value
                        Current.Pitch = math.clamp(Current.Pitch - Input.Delta.Y * 0.0025 * Options.FPVChairLookSpeed.Value, -1.45, 1.45)
                    elseif Input.UserInputType == Enum.UserInputType.Touch then
                        local Viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000, 600)
                        if Input.Position.X > Viewport.X * 0.4 and not Current.OverButton then
                            Current.Yaw -= Input.Delta.X * 0.012 * Options.FPVChairLookSpeed.Value
                            Current.Pitch = math.clamp(Current.Pitch - Input.Delta.Y * 0.012 * Options.FPVChairLookSpeed.Value, -1.45, 1.45)
                        end
                    end
                end)
                do
                    local Gui = New("ScreenGui", { Name = "AMRFPVChairButtons", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 60 }, GetHiddenContainer())
                    Current.Gui = Gui
                    local function HoldButton(Text, Y, Key)
                        local Button = New("TextButton", {
                            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, Y), Size = UDim2.fromOffset(64, 64),
                            BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = Text, TextColor3 = Color3.new(1, 1, 1),
                            Font = Enum.Font.GothamBold, TextSize = 26, AutoButtonColor = false,
                        }, Gui)
                        Round(Button, 32)
                        Button.InputBegan:Connect(function(Input)
                            if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
                                Current[Key], Current.OverButton = true, true
                            end
                        end)
                        Button.InputEnded:Connect(function(Input)
                            if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
                                Current[Key], Current.OverButton = false, false
                            end
                        end)
                    end
                    HoldButton("^", -40, "UpHeld")
                    HoldButton("v", 40, "DownHeld")
                end
                Functions.Notify({ Title = "FPV Chair", Body = "Look anywhere and push the stick: the chair flies where you look. ^ / v buttons (or Space / Shift) go up and down." })
                local Token = FPV.Token
                FPV.Connections[#FPV.Connections + 1] = RunService.Heartbeat:Connect(function(Dt)
                    if Token ~= FPV.Token or FPV.Current ~= Current or not Toggles.FPVChair.Value then return end
                    if LocalPlayer.Character ~= SourceCharacter or not Chair.Parent or not DrivePart.Parent then Toggles.FPVChair:SetValue(false) return end
                    local LiveTargetRoot = Current.Target and Current.Target.Character and Current.Target.Character:FindFirstChild("HumanoidRootPart")
                    if not LiveTargetRoot then Toggles.FPVChair:SetValue(false) return end
                    local Distance = (DrivePart.Position - LiveTargetRoot.Position).Magnitude
                    if (DrivePart.Position - Current.StartPosition).Magnitude >= 10 then Current.Departed = true end
                    local CanScare = false
                    if not Current.ScareAt and CanScare and Distance <= 3.5 then Current.ScareAt = tick() end
                    if Current.ScareAt then
                        local Elapsed = tick() - Current.ScareAt
                        Chair:PivotTo(CFrame.new(LiveTargetRoot.Position) * CFrame.Angles(0, Elapsed * 80, 0))
                        DrivePart.AssemblyAngularVelocity = Vector3.new(0, 420, 0)
                        DrivePart.AssemblyLinearVelocity = Vector3.zero
                        if Elapsed >= Options.FPVChairScareTime.Value then Toggles.FPVChair:SetValue(false) end
                        return
                    end
                    local Collide = Toggles.FPVChairCollide.Value
                    for Part in Current.ChairCollision do
                        if Part.Parent and Part.CanCollide ~= Collide then Part.CanCollide = Collide end
                    end
                    if DrivePart.Position.Y < Current.StartPosition.Y - 25 then
                        Chair:PivotTo(CFrame.new(DrivePart.Position.X, Current.StartPosition.Y + 2, DrivePart.Position.Z))
                    end
                    local Move = Current.Controls and Current.Controls:GetMoveVector() or Vector3.zero
                    local CurrentCamera = workspace.CurrentCamera
                    local Look3 = CurrentCamera and CurrentCamera.CFrame.LookVector or Vector3.new(0, 0, -1)
                    local Right = Vector3.new(Look3.Z, 0, -Look3.X)
                    Right = Right.Magnitude > 0.01 and -Right.Unit or Vector3.xAxis
                    local UIS = Services.UserInputService
                    local Vertical = ((UIS:IsKeyDown(Enum.KeyCode.Space) or Current.UpHeld) and 1 or 0) - ((UIS:IsKeyDown(Enum.KeyCode.LeftShift) or Current.DownHeld) and 1 or 0)
                    local WorldMove = Right * Move.X + Look3 * -Move.Z + Vector3.yAxis * Vertical
                    if WorldMove.Magnitude > 0.01 then WorldMove = WorldMove.Unit * Options.FPVChairSpeed.Value end
                    DrivePart.AssemblyLinearVelocity = WorldMove
                    DrivePart.AssemblyAngularVelocity = Vector3.zero
                end)
                FPV.Connections[#FPV.Connections + 1] = RunService.RenderStepped:Connect(function()
                    if FPV.Current ~= Current or not DrivePart.Parent or not CameraAnchor.Parent then return end
                    CameraAnchor.CFrame = CFrame.new(DrivePart.Position)
                    local CurrentCamera = workspace.CurrentCamera
                    if CurrentCamera then
                        if CurrentCamera.CameraType ~= Enum.CameraType.Scriptable then CurrentCamera.CameraType = Enum.CameraType.Scriptable end
                        CurrentCamera.CFrame = CFrame.new(DrivePart.Position + Vector3.new(0, Options.FPVChairEyeHeight.Value, 0)) * CFrame.fromOrientation(Current.Pitch, Current.Yaw, 0)
                    end
                    for Part in Current.ChairCollision do
                        if Part.Parent then Part.LocalTransparencyModifier = 1 end
                    end
                end)
            end
            local function ArmFPVChair(Value)
                StopFPVChair()
                if not Value then return end
                if Toggles.ChairFly.Value then Toggles.ChairFly:SetValue(false) end
                Globals.FPVChairActive = true
                FPV.Token += 1
                local Token = FPV.Token
                local PromptService = Services.ProximityPromptService
                FPV.Connections[#FPV.Connections + 1] = PromptService.PromptButtonHoldBegan:Connect(function(Prompt)
                    if Token ~= FPV.Token then return end
                    local Chair = ChairFromPrompt(Prompt)
                    if not Chair then return end
                    FPV.Pending = { Prompt = Prompt, Chair = Chair, Held = true, Triggered = false, Released = false }
                    Functions.Notify({ Title = "FPV Chair", Body = "Holding: " .. Prompt.Name .. " / " .. tostring(Prompt:GetAttribute("GateSector")), Time = 3 })
                end)
                FPV.Connections[#FPV.Connections + 1] = PromptService.PromptTriggered:Connect(function(Prompt)
                    local Pending = FPV.Pending
                    if not Pending and Token == FPV.Token then
                        local Chair = ChairFromPrompt(Prompt)
                        if Chair then Pending = { Prompt = Prompt, Chair = Chair, Held = false, Triggered = false, Released = true } FPV.Pending = Pending end
                    end
                    if Pending and Pending.Prompt == Prompt then
                        Pending.Triggered = true
                        Functions.Notify({ Title = "FPV Chair", Body = "Grabbed. Let go of the prompt.", Time = 3 })
                        if Pending.Released then StartFPVControl(Pending) end
                        task.delay(1.5, function()
                            if Token == FPV.Token and FPV.Pending == Pending and not FPV.Current then StartFPVControl(Pending) end
                        end)
                    end
                end)
                FPV.Connections[#FPV.Connections + 1] = PromptService.PromptButtonHoldEnded:Connect(function(Prompt)
                    local Pending = FPV.Pending
                    if Pending and Pending.Prompt == Prompt then
                        Pending.Held, Pending.Released = false, true
                        if Pending.Triggered then StartFPVControl(Pending) end
                    end
                end)
                Functions.Notify({ Title = "FPV Chair", Body = "Stand behind an office chair, hold Push, then release it." })
            end
            FPVBox:AddButton({ Text = "Drive nearest chair now", Tooltip = "Skips the prompt dance: grab the chair first (hold + release), then press this next to it.", Func = function()
                if not Toggles.FPVChair.Value then Toggles.FPVChair:SetValue(true) end
                if FPV.Current then return end
                local Chair = NearestChair()
                if not Chair then Functions.Notify({ Title = "FPV Chair", Body = "No office chair found." }) return end
                StartFPVControl({ Chair = Chair })
            end })
            Toggles.FPVChair:OnChanged(ArmFPVChair)
            Toggles.ChairFly:OnChanged(function(Value) if Value and Toggles.FPVChair.Value then Toggles.FPVChair:SetValue(false) end end)
            pcall(function() Library:OnUnload(StopFPVChair) end)
        end

        Groupboxes.Exploits_BypassRight:AddToggle("MinecartAnticheatBypass", {
            Text = "Minecart Anticheat Bypass", Default = false,
            Tooltip = "In Mines room 43 removes the MinecartResult remote so the minecart check cannot fire."
        })
        Toggles.MinecartAnticheatBypass:OnChanged(function(Value)
            if Connections.MinecartAnticheatBypass then Connections.MinecartAnticheatBypass:Disconnect() Connections.MinecartAnticheatBypass = nil end
            if not Value then return end
            Connections.MinecartAnticheatBypass = RunService.Heartbeat:Connect(function()
                if not Toggles.MinecartAnticheatBypass.Value then
                    Connections.MinecartAnticheatBypass:Disconnect() Connections.MinecartAnticheatBypass = nil return
                end
                if tostring(LocalPlayer:GetAttribute("CurrentRoom")) ~= "43" then return end
                local Result = RemotesFolder and RemotesFolder:FindFirstChild("MinecartResult")
                if not Result then return end
                pcall(function() Result:Destroy() end)
                if not Result.Parent then
                    Functions.Notify({ Title = "Minecart bypass", Body = "MinecartResult removed.", Time = 4 })
                    Toggles.MinecartAnticheatBypass:SetValue(false)
                end
            end)
        end)
    end

    ---------------------------------------------------------------------
    -- AUTO TELLER (Archives): asks every Teller for a ticket (there can be two), reads the door count off each ticket,
    -- hands each ticket back to the Teller standing at its door
    ---------------------------------------------------------------------
    do
        Groupboxes.Archives_Experimental:AddToggle("AutoTeller", {
            Text = "Auto Teller", Default = false,
            Tooltip = "Activates every Teller's prompt to get Archives Tickets (works with two Tellers / two tickets), reads the door number on each ticket and gives it back to the Teller as soon as you reach that door."
        })
        Groupboxes.Archives_Experimental:AddDropdown("AutoTellerMode", {
            Text = "Ticket Number Means", Values = { "Doors From Now", "Door Number" }, Default = 1,
            Tooltip = "Doors From Now: the ticket says in how many doors to return it. Door Number: the ticket shows the exact door."
        })
        Groupboxes.Archives_Experimental:AddSlider("AutoTellerOffset", {
            Text = "Give Offset (doors)", Default = 0, Min = -3, Max = 3, Rounding = 0, Compact = true,
            Tooltip = "Shifts the door where tickets are handed in. Use it if the Teller is one door early/late."
        })

        Groupboxes.Archives_Experimental:AddToggle("TellerHUD", {
            Text = "Teller HUD", Default = true,
            Tooltip = "With Auto Teller on: a counter of the doors left for each ticket and an arrow to the Teller."
        })
        local HudGui, HudLabel
        local function SetHud(Lines)
            if not Toggles.TellerHUD.Value or #Lines == 0 then
                if HudGui then HudGui.Enabled = false end
                return
            end
            if not HudGui then
                HudGui = New("ScreenGui", { Name = "AMRTellerHUD", IgnoreGuiInset = true, DisplayOrder = 50, ResetOnSpawn = false }, GetHiddenContainer())
                HudLabel = New("TextLabel", {
                    AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
                    Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.fromRGB(255, 200, 120), TextWrapped = true,
                }, HudGui)
                Round(HudLabel, 8)
                pcall(function() Library:OnUnload(function() if HudGui then HudGui:Destroy() end end) end)
            end
            HudGui.Enabled = true
            HudLabel.Size = UDim2.fromOffset(300, 10 + 18 * #Lines)
            HudLabel.Text = table.concat(Lines, "\n")
        end
        local Tellers = {}
        local Asked = setmetatable({}, { __mode = "k" })
        local Info = setmetatable({}, { __mode = "k" }) -- per ticket: Target, Missed, Said
        local Pending
        local LastGive, WatchConnection = 0, nil
        local Said = {}
        local function Say(Key, Title, Body)
            if Said[Key] and tick() - Said[Key] < 6 then return end
            Said[Key] = tick()
            Functions.Notify({ Title = Title, Body = Body })
        end
        local function IsTeller(Object)
            return Object:IsA("Model") and (Object.Name == "TellerRig" or Object.Name == "Teller")
        end
        local function Watch(Value)
            if WatchConnection then WatchConnection:Disconnect() WatchConnection = nil end
            table.clear(Tellers)
            if not Value then return end
            for _, Object in workspace:GetDescendants() do
                if IsTeller(Object) then Tellers[Object] = true end
            end
            WatchConnection = workspace.DescendantAdded:Connect(function(Object)
                if IsTeller(Object) then Tellers[Object] = true end
            end)
            table.insert(Connections, WatchConnection)
        end
        Toggles.AutoTeller:OnChanged(function(Value)
            Pending = nil
            Watch(Value)
        end)
        local function LiveTellers()
            local List = {}
            for Teller in Tellers do
                if Teller.Parent then List[#List + 1] = Teller else Tellers[Teller] = nil end
            end
            return List
        end
        local function FireTeller(Teller)
            for _, Descendant in Teller:GetDescendants() do
                if Descendant:IsA("ProximityPrompt") then Functions.FirePrompt(Descendant) end
            end
        end
        local function Tickets()
            local List = {}
            local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            for _, Container in { Backpack, LocalPlayer.Character } do
                if Container then
                    for _, Child in Container:GetChildren() do
                        if Child.Name == "ArchivesTicket" then List[#List + 1] = Child end
                    end
                end
            end
            return List
        end
        local function ReadTicket(Ticket)
            local Handle = Ticket:FindFirstChild("Handle")
            local Gui = Handle and Handle:FindFirstChild("SurfaceGui")
            local Label = Gui and Gui:FindFirstChild("TextLabel")
            local Text = Label and Label.Text
            return Text and tonumber(string.match(Text, "%d+")), Text
        end
        -- the Teller that stands in the room we are in (else the closest one)
        local function TellerFor(List, Room)
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            local RoomModel = Rooms and Rooms:FindFirstChild(tostring(Room))
            local Root = RootPart
            local Best, BestDistance
            for _, Teller in List do
                local InRoom = RoomModel and Teller:IsDescendantOf(RoomModel)
                local Distance = Root and (Teller:GetPivot().Position - Root.Position).Magnitude or 0
                if InRoom then Distance -= 10000 end
                if not BestDistance or Distance < BestDistance then Best, BestDistance = Teller, Distance end
            end
            return Best
        end

        task.spawn(function()
            while Alive do
                task.wait(0.25)
                if not Toggles.AutoTeller.Value then
                    Globals.TellerTarget = nil
                    SetHud({})
                    continue
                end
                local Now = tick()
                local Room = CurrentRoomNumber()
                local Character = LocalPlayer.Character
                local TellerList = LiveTellers()
                local TicketList = Tickets()

                -- 1) collect: one Teller at a time, every Teller once
                if Pending then
                    if Now - Pending.At > 0.7 and #TicketList > Pending.Count then
                        Asked[Pending.Teller] = true
                        Pending = nil
                    elseif Now - Pending.At > 3 then
                        Pending = nil
                    end
                end
                if not Pending then
                    for _, Teller in TellerList do
                        if not Asked[Teller] then
                            Pending = { Teller = Teller, At = Now, Count = #TicketList }
                            FireTeller(Teller)
                            break
                        end
                    end
                end

                -- 2) read every ticket, 3) give the one whose door has come
                local Due
                for _, Ticket in TicketList do
                    local Data = Info[Ticket]
                    if not Data then Data = {} Info[Ticket] = Data end
                    if not Data.Target then
                        local Number, Text = ReadTicket(Ticket)
                        if Number then
                            Data.Target = (Options.AutoTellerMode.Value == "Door Number" and Number or Room + Number) + math.floor(Options.AutoTellerOffset.Value)
                            Functions.Notify({ Title = "Teller Ticket", Body = string.format("Ticket says \"%s\". Handing it in at door %d (now door %d).", tostring(Text), Data.Target, Room) })
                        end
                    elseif Room >= Data.Target and not Data.Missed then
                        if Room > Data.Target + 1 then
                            Data.Missed = true
                            Functions.Notify({ Title = "Teller Ticket", Body = "Missed door " .. Data.Target .. ". Ticket kept." })
                        elseif not Due or Data.Target < Info[Due].Target then
                            Due = Ticket
                        end
                    end
                end
                -- HUD + arrow: doors left per ticket, arrow to the Teller we will need next
                do
                    local Lines, Next = {}, nil
                    for _, Ticket in TicketList do
                        local Data = Info[Ticket]
                        if not Data or not Data.Target then
                            Lines[#Lines + 1] = "Ticket: reading the door..."
                        elseif Data.Missed then
                            Lines[#Lines + 1] = "Ticket: missed door " .. Data.Target
                        else
                            local Left = Data.Target - Room
                            Lines[#Lines + 1] = Left > 0 and string.format("Ticket: door %d, %d to go", Data.Target, Left) or string.format("Ticket: door %d, give it now", Data.Target)
                            if not Next or Data.Target < Next then Next = Data.Target end
                        end
                    end
                    SetHud(Lines)
                    local Aim, Label
                    if Next then
                        Aim = TellerFor(TellerList, Next)
                        Label = "TELLER " .. math.max(Next - Room, 0)
                    elseif #TicketList == 0 then
                        for _, Teller in TellerList do
                            if not Asked[Teller] then Aim, Label = Teller, "TELLER (ticket)" break end
                        end
                    end
                    Globals.TellerTarget = Aim and Aim:GetPivot().Position or nil
                    Globals.TellerLabel = Label
                end
                if Due and Now - LastGive > 0.5 then
                    local Teller = TellerFor(TellerList, Room)
                    if Teller then
                        LastGive = Now
                        local Hum = Character and Character:FindFirstChildOfClass("Humanoid")
                        if Due.Parent ~= Character and Hum then Hum:EquipTool(Due) end
                        FireTeller(Teller)
                        Say("give", "Teller Ticket", "Giving the ticket to the Teller.")
                    else
                        Say("wait", "Teller Ticket", "At door " .. Info[Due].Target .. ", waiting for the Teller.")
                    end
                end
            end
        end)
    end

    ---------------------------------------------------------------------
    -- Tamagochi / Пиздёныш: persistent pet driven by real play
    ---------------------------------------------------------------------
    ---------------------------------------------------------------------
    -- Challenge: Random Events (local effects every minute, paused while Seek is chasing)
    ---------------------------------------------------------------------
    do
        local Box = Groupboxes.Floors_Experimental
        Box:AddDivider()
        Box:AddLabel("Random Events")
        Box:AddToggle("ChallengeRandomEvents", {
            Text = "Challenge: Random Events", Default = false,
            Tooltip = "A random local event every interval (not while Seek is chasing). 10% chance for the nasty one: inverted controls and the camera locks onto the nearest entity (not Eyes)."
        })
        Box:AddSlider("RandomEventInterval", { Text = "Event every (s)", Default = 60, Min = 20, Max = 240, Rounding = 0, Compact = true })
        Box:AddSlider("RandomEventLength", { Text = "Event length (s)", Default = 20, Min = 8, Max = 60, Rounding = 0, Compact = true })
        local StatusLabel = Box:AddLabel("Next event: -", true)

        local Lighting = game:GetService("Lighting")
        local Color = New("ColorCorrectionEffect", { Name = "AMREventColor", Enabled = false }, Lighting)
        local Cover = New("ScreenGui", { Name = "AMREventCover", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 30 }, GetHiddenContainer())
        local Black = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0 }, Cover)

        local SeekCount = 0
        local function IsSeek(Object) return Object:IsA("Model") and string.find(Object.Name, "^SeekMoving") ~= nil end
        for _, Object in workspace:GetDescendants() do if IsSeek(Object) then SeekCount += 1 end end
        Connections.EventSeekAdded = workspace.DescendantAdded:Connect(function(Object) if IsSeek(Object) then SeekCount += 1 end end)
        Connections.EventSeekRemoved = workspace.DescendantRemoving:Connect(function(Object) if IsSeek(Object) then SeekCount = math.max(0, SeekCount - 1) end end)

        local function NearestEntity()
            local Camera = workspace.CurrentCamera
            if not Camera then return nil end
            local Best, BestDistance = nil, 220
            for _, Object in workspace:GetChildren() do
                if Object:IsA("Model") and Object.Name ~= "Eyes" and not string.find(Object.Name, "Eyes", 1, true)
                    and (string.find(Object.Name, "Moving$") or Object.Name == "A60" or Object.Name == "A120"
                        or Object.Name == "Lookman" or Object.Name == "BackdoorLookman") then
                    local Ok, Pivot = pcall(function() return Object:GetPivot() end)
                    if Ok then
                        local Distance = (Pivot.Position - Camera.CFrame.Position).Magnitude
                        if Distance < BestDistance then Best, BestDistance = Pivot.Position, Distance end
                    end
                end
            end
            return Best
        end

        local Saved = {}
        local Events = {
            { "Earthquake", function(State) State.Shake = 0.35 end },
            { "Fisheye breathing", function(State) State.Fov = true end },
            { "Upside down", function(State) State.Roll = math.pi end },
            { "Seasick", function(State) State.Sway = true end },
            { "Low gravity", function(State) Saved.Gravity = workspace.Gravity workspace.Gravity = 60 end, function() if Saved.Gravity then workspace.Gravity = Saved.Gravity Saved.Gravity = nil end end },
            { "Disco", function(State) State.Disco = true end },
            { "Old film", function() Color.Saturation, Color.Contrast, Color.TintColor, Color.Enabled = -1, 0.25, Color3.fromRGB(255, 235, 200), true end, function() Color.Enabled = false Color.Saturation, Color.Contrast, Color.TintColor = 0, 0, Color3.new(1, 1, 1) end },
            { "Lights flicker", function(State) State.Flicker = true end },
            { "Tunnel vision", function(State) State.Tunnel = true end },
        }
        local Chaos = { "CHAOS: controls inverted, camera drawn to the nearest entity", function(State) Globals.AMREventInvert = true State.Lock = true end, function() Globals.AMREventInvert = nil end }

        local Current
        local NextAt = tick() + Options.RandomEventInterval.Value
        local function StopEvent()
            if not Current then return end
            local Event = Current
            Current = nil
            if Event.Def[3] then pcall(Event.Def[3]) end
            Globals.AMREventInvert = nil
            Black.BackgroundTransparency = 1
            Color.Enabled = false
            Color.Saturation, Color.Contrast, Color.TintColor = 0, 0, Color3.new(1, 1, 1)
            if Saved.Gravity then workspace.Gravity = Saved.Gravity Saved.Gravity = nil end
            if Saved.Ambient then Lighting.Ambient = Saved.Ambient Saved.Ambient = nil end
            if Saved.Fov and workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = Saved.Fov Saved.Fov = nil end
        end
        local function StartEvent()
            local Def = math.random(1, 100) <= 10 and Chaos or Events[math.random(1, #Events)]
            local State = { Start = tick(), Seed = math.random() * 100 }
            Current = { Def = Def, State = State, Ends = tick() + Options.RandomEventLength.Value }
            Def[2](State)
            Functions.Notify({ Title = "Random Event", Body = Def[1], Time = 4 })
        end

        pcall(function() RunService:UnbindFromRenderStep("AMREventStep") end)
        RunService:BindToRenderStep("AMREventStep", Enum.RenderPriority.Last.Value + 200, function()
            local Camera = workspace.CurrentCamera
            local Time = tick()
            if not Toggles.ChallengeRandomEvents.Value then
                if Current then StopEvent() end
                StatusLabel:SetText("Next event: off")
                return
            end
            if SeekCount > 0 then
                if Current then StopEvent() end
                NextAt = Time + Options.RandomEventInterval.Value
                StatusLabel:SetText("Paused: Seek is chasing")
                return
            end
            if not Current then
                StatusLabel:SetText(string.format("Next event in %ds", math.max(0, math.ceil(NextAt - Time))))
                if Time >= NextAt and Character and Humanoid and Humanoid.Health > 0 and LocalPlayer:GetAttribute("Alive") ~= false then
                    StartEvent()
                end
                return
            end
            local State = Current.State
            StatusLabel:SetText(string.format("%s (%ds)", Current.Def[1], math.max(0, math.ceil(Current.Ends - Time))))
            if Time >= Current.Ends then
                StopEvent()
                NextAt = Time + Options.RandomEventInterval.Value
                return
            end
            if not Camera then return end
            local T = Time - State.Start
            if State.Shake then
                Camera.CFrame = Camera.CFrame * CFrame.new((math.noise(T * 14, State.Seed) * 2) * State.Shake, (math.noise(T * 16, State.Seed + 9) * 2) * State.Shake, 0) * CFrame.Angles(0, 0, math.noise(T * 9, State.Seed + 3) * 0.05)
            end
            if State.Fov then
                if not Saved.Fov then Saved.Fov = Camera.FieldOfView end
                Camera.FieldOfView = math.clamp(Saved.Fov + math.sin(T * 1.6) * 38, 30, 120)
            end
            if State.Roll then Camera.CFrame = Camera.CFrame * CFrame.Angles(0, 0, State.Roll) end
            if State.Sway then Camera.CFrame = Camera.CFrame * CFrame.Angles(math.sin(T * 1.1) * 0.05, 0, math.sin(T * 0.9) * 0.42) end
            if State.Disco then
                if not Saved.Ambient then Saved.Ambient = Lighting.Ambient end
                Lighting.Ambient = Color3.fromHSV((T * 0.5) % 1, 0.8, 0.9)
                Color.Enabled, Color.TintColor, Color.Saturation = true, Color3.fromHSV((T * 0.5 + 0.5) % 1, 0.35, 1), 0.4
            end
            if State.Flicker then
                Black.BackgroundTransparency = math.noise(T * 7, State.Seed) > 0.25 and 1 or 0.15
            end
            if State.Tunnel then
                Black.BackgroundTransparency = 0.45 + math.sin(T * 2) * 0.1
            end
            if State.Lock then
                local Target = NearestEntity()
                if Target then Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, Target) end
            end
        end)
        Toggles.ChallengeRandomEvents:OnChanged(function(Value)
            if Value then NextAt = tick() + Options.RandomEventInterval.Value else StopEvent() end
        end)
        pcall(function() Library:OnUnload(function() pcall(function() RunService:UnbindFromRenderStep("AMREventStep") end) StopEvent() Cover:Destroy() Color:Destroy() Globals.AMREventInvert = nil end) end)
    end

    do
        local Russian = Abysall.Localization and Abysall.Localization.Code == "ru"
        local function L(English, RussianText) return Russian and RussianText or English end
        local Kinds = {
            { id = "classic", en = "Tamagochi", ru = "Пиздёныш", coins = 0, body = Color3.fromRGB(246, 177, 93), head = Color3.fromRGB(255, 195, 110) },
            { id = "nerd", en = "Nerd Loser", ru = "Лох-ботаник", coins = 2000, body = Color3.fromRGB(150, 200, 150), head = Color3.fromRGB(190, 225, 185) },
            { id = "bully", en = "Bully Bob", ru = "Боб-булли", coins = 2000, body = Color3.fromRGB(200, 90, 80), head = Color3.fromRGB(235, 140, 120) },
            { id = "cool", en = "Cool Kid", ru = "Крутой", coins = 2000, body = Color3.fromRGB(70, 110, 200), head = Color3.fromRGB(110, 150, 230) },
            { id = "punk", en = "Punk", ru = "Панк", coins = 2000, body = Color3.fromRGB(150, 80, 190), head = Color3.fromRGB(190, 120, 225) },
            { id = "chad", en = "Gigachad", ru = "Гигачад", brainrots = 15, body = Color3.fromRGB(235, 190, 60), head = Color3.fromRGB(250, 215, 100) },
        }
        local KindById = {}
        for _, Kind in Kinds do KindById[Kind.id] = Kind end
        local function KindName(Kind) return Russian and Kind.ru or Kind.en end
        local StageNames = { { "baby", "малыш" }, { "kid", "ребёнок" }, { "teen", "подросток" }, { "adult", "взрослый" } }
        local StageScale = { 0.62, 0.8, 0.93, 1.06 }
        local function StageOf(P)
            local Age = P.age or 0
            return Age < 1200 and 1 or Age < 7200 and 2 or Age < 21600 and 3 or 4
        end
        local function StageName(Index) return L(StageNames[Index][1], StageNames[Index][2]) end
        local function Fmt(Seconds)
            Seconds = math.max(0, math.floor(Seconds))
            return string.format("%d:%02d:%02d", Seconds // 3600, Seconds % 3600 // 60, Seconds % 60)
        end
        local PetName = Russian and "Пиздёныш" or "Tamagochi"
        Groupboxes.Tamagochi_Pet = Tabs.Tamagochi:AddLeftGroupbox(PetName)
        Groupboxes.Tamagochi_Status = Tabs.Tamagochi:AddRightGroupbox(L("Status", "Состояние"))
        Groupboxes.Tamagochi_Shop = Tabs.Tamagochi:AddLeftGroupbox(L("Shop", "Магазин"))
        Groupboxes.Tamagochi_Brainrot = Tabs.Tamagochi:AddRightGroupbox(L("Steal a Brainrot", "Укради брейнрот"))
        local PetBox, StatusBox, ShopBox, BrainBox = Groupboxes.Tamagochi_Pet, Groupboxes.Tamagochi_Status, Groupboxes.Tamagochi_Shop, Groupboxes.Tamagochi_Brainrot

        local Now = os.time()
        local Root = Boot.LoadJSON("Pet.json")
        local function NewPet(KindId)
            return { id = tostring(os.time()) .. tostring(math.random(1000, 9999)), kind = KindId, birth = os.time(), hunger = 100, mood = 100, alive = true, age = 0 }
        end
        if type(Root) ~= "table" then Root = {} end
        Root.version = 2
        Root.lastSeen = tonumber(Root.lastSeen) or Now
        Root.sessions = type(Root.sessions) == "table" and Root.sessions or {}
        Root.rooms = math.max(0, tonumber(Root.rooms) or 0)
        Root.gold = math.max(0, tonumber(Root.gold) or 0)
        Root.deaths = math.max(0, tonumber(Root.deaths) or 0)
        Root.totalPlaytime = math.max(0, tonumber(Root.totalPlaytime) or 0)
        Root.coins = math.max(0, math.floor(tonumber(Root.coins) or 0))
        Root.brainrots = math.max(0, math.floor(tonumber(Root.brainrots) or 0))
        if type(Root.pets) ~= "table" or #Root.pets == 0 then
            local Legacy = NewPet("classic")
            if Root.hunger ~= nil then
                Legacy.hunger, Legacy.mood = tonumber(Root.hunger) or 100, tonumber(Root.mood) or 100
                Legacy.alive, Legacy.deathAt, Legacy.deathCause = Root.alive ~= false, Root.deathAt, Root.deathCause
                Legacy.birth, Legacy.age = tonumber(Root.birth) or Now, Root.totalPlaytime
            end
            Root.pets = { Legacy }
        end
        Root.hunger, Root.mood, Root.alive, Root.deathAt, Root.deathCause = nil, nil, nil, nil, nil
        for _, P in Root.pets do
            if not KindById[P.kind] then P.kind = "classic" end
            P.id = tostring(P.id or math.random(100000, 999999))
            P.birth = tonumber(P.birth) or Now
            P.age = math.max(0, tonumber(P.age) or 0)
            P.alive = P.alive ~= false
            P.hunger = math.clamp(tonumber(P.hunger) or 100, 0, 100)
            P.mood = math.clamp(tonumber(P.mood) or 100, 0, 100)
            P.stage = StageOf(P)
        end
        Root.sel = math.clamp(math.floor(tonumber(Root.sel) or 1), 1, #Root.pets)
        local Pet = Root.pets[Root.sel]
        if math.max(0, Now - Root.lastSeen) >= 172800 then
            for _, P in Root.pets do
                if P.alive then P.alive, P.deathAt, P.deathCause, P.hunger, P.mood = false, Now, "away", 0, 0 end
            end
        end
        while #Root.sessions >= 200 do table.remove(Root.sessions, 1) end
        local Session = { start = Now, stop = Now }
        Root.sessions[#Root.sessions + 1] = Session
        local LastAccounted, HungerCarry = Now, 0
        local function ForAlive(Callback)
            for _, P in Root.pets do if P.alive then Callback(P) end end
        end
        local RefreshLists
        local function AccountTime()
            local Current = os.time()
            local Delta = math.clamp(Current - LastAccounted, 0, 300)
            LastAccounted = Current
            Root.totalPlaytime += Delta
            Session.stop = Current
            Root.lastSeen = Current
            local Grew = false
            ForAlive(function(P)
                P.age += Delta
                local Stage = StageOf(P)
                if Stage > (P.stage or 1) then
                    P.stage, Grew = Stage, true
                    Functions.Notify({ Title = KindName(KindById[P.kind]), Body = L("Grew up: ", "Вырос: ") .. StageName(Stage) })
                end
            end)
            HungerCarry += Delta
            if HungerCarry >= 300 then
                local Drain = math.floor(HungerCarry / 300)
                HungerCarry -= Drain * 300
                ForAlive(function(P)
                    P.hunger = math.max(0, P.hunger - Drain)
                    if P.hunger < 25 then P.mood = math.max(0, P.mood - Drain * 0.4) end
                end)
            end
            if Grew and RefreshLists then RefreshLists() end
        end
        local function SavePet()
            AccountTime()
            Boot.SaveJSON("Pet.json", Root)
        end

        local UI = {}
        UI.Canvas = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(22, 27, 40), BorderSizePixel = 0, ClipsDescendants = true })
        Round(UI.Canvas, 10)
        New("UIStroke", { Color = Color3.fromRGB(95, 120, 170), Thickness = 1.5, Transparency = 0.25 }, UI.Canvas)
        UI.Name = New("TextLabel", { Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 24), BackgroundTransparency = 1, Text = PetName, TextColor3 = Color3.fromRGB(245, 230, 170), Font = Enum.Font.GothamBold, TextSize = 18 }, UI.Canvas)
        UI.Sky = New("Frame", { Position = UDim2.fromOffset(8, 34), Size = UDim2.new(1, -16, 1, -42), BackgroundColor3 = Color3.fromRGB(70, 112, 150), BorderSizePixel = 0, ClipsDescendants = true }, UI.Canvas)
        local Sky = UI.Sky
        Round(Sky, 8)
        New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Color3.fromRGB(75, 105, 68), BorderSizePixel = 0 }, Sky)
        UI.Holder = New("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(94, 116), BackgroundTransparency = 1 }, Sky)
        UI.Scale = New("UIScale", { Scale = 1 }, UI.Holder)
        UI.Body = New("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(70, 76), BackgroundColor3 = Kinds[1].body, BorderSizePixel = 0 }, UI.Holder)
        Round(UI.Body, 24)
        New("UIStroke", { Color = Color3.fromRGB(88, 55, 43), Thickness = 3 }, UI.Body)
        UI.Head = New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(82, 70), BackgroundColor3 = Kinds[1].head, BorderSizePixel = 0 }, UI.Holder)
        Round(UI.Head, 28)
        New("UIStroke", { Color = Color3.fromRGB(88, 55, 43), Thickness = 3 }, UI.Head)
        UI.EyeLeft = New("Frame", { Position = UDim2.new(0.28, -5, 0.36, 0), Size = UDim2.fromOffset(10, 14), BackgroundColor3 = Color3.fromRGB(25, 25, 30), BorderSizePixel = 0 }, UI.Head)
        UI.EyeRight = New("Frame", { Position = UDim2.new(0.72, -5, 0.36, 0), Size = UDim2.fromOffset(10, 14), BackgroundColor3 = Color3.fromRGB(25, 25, 30), BorderSizePixel = 0 }, UI.Head)
        Round(UI.EyeLeft, 8) Round(UI.EyeRight, 8)
        UI.Mouth = New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.68, 0), Size = UDim2.fromOffset(24, 5), BackgroundColor3 = Color3.fromRGB(110, 48, 48), BorderSizePixel = 0 }, UI.Head)
        Round(UI.Mouth, 4)
        UI.ArmLeft = New("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.2, 0, 0.51, 0), Size = UDim2.fromOffset(30, 12), Rotation = -18, BackgroundColor3 = UI.Body.BackgroundColor3, BorderSizePixel = 0 }, UI.Holder)
        UI.ArmRight = New("Frame", { Position = UDim2.new(0.8, 0, 0.51, 0), Size = UDim2.fromOffset(30, 12), Rotation = 18, BackgroundColor3 = UI.Body.BackgroundColor3, BorderSizePixel = 0 }, UI.Holder)
        Round(UI.ArmLeft, 8) Round(UI.ArmRight, 8)

        -- accessories, shown per kind
        local Acc = {}
        Acc.GlassL = New("Frame", { Position = UDim2.new(0.28, -13, 0.36, -4), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, UI.Head)
        Acc.GlassR = New("Frame", { Position = UDim2.new(0.72, -13, 0.36, -4), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, UI.Head)
        for _, G in { Acc.GlassL, Acc.GlassR } do Round(G, 13) New("UIStroke", { Color = Color3.fromRGB(30, 30, 35), Thickness = 3 }, G) end
        Acc.Shades = New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.3, 0), Size = UDim2.fromOffset(68, 18), BackgroundColor3 = Color3.fromRGB(12, 12, 16), BorderSizePixel = 0, Visible = false, ZIndex = 3 }, UI.Head)
        Round(Acc.Shades, 7)
        Acc.Cap = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(78, 22), BackgroundColor3 = Color3.fromRGB(200, 40, 40), BorderSizePixel = 0, Visible = false, ZIndex = 3 }, UI.Head)
        Round(Acc.Cap, 10)
        Acc.Brim = New("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.55, 0, 0, 12), Size = UDim2.fromOffset(46, 8), BackgroundColor3 = Color3.fromRGB(150, 25, 25), BorderSizePixel = 0, Visible = false, ZIndex = 3 }, UI.Head)
        Round(Acc.Brim, 4)
        Acc.BrowL = New("Frame", { Position = UDim2.new(0.28, -9, 0.28, 0), Size = UDim2.fromOffset(18, 4), Rotation = 20, BackgroundColor3 = Color3.fromRGB(40, 25, 20), BorderSizePixel = 0, Visible = false, ZIndex = 3 }, UI.Head)
        Acc.BrowR = New("Frame", { Position = UDim2.new(0.72, -9, 0.28, 0), Size = UDim2.fromOffset(18, 4), Rotation = -20, BackgroundColor3 = Color3.fromRGB(40, 25, 20), BorderSizePixel = 0, Visible = false, ZIndex = 3 }, UI.Head)
        Acc.Spikes = {}
        for Index = 1, 3 do
            Acc.Spikes[Index] = New("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, (Index - 2) * 14, 0, 6), Size = UDim2.fromOffset(10, 26), Rotation = (Index - 2) * 14, BackgroundColor3 = Color3.fromRGB(255, 80, 170), BorderSizePixel = 0, Visible = false, ZIndex = 2 }, UI.Head)
            Round(Acc.Spikes[Index], 4)
        end
        Acc.Crown = New("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(46, 16), BackgroundColor3 = Color3.fromRGB(255, 215, 60), BorderSizePixel = 0, Visible = false, ZIndex = 3 }, UI.Head)
        Round(Acc.Crown, 3)
        local Looks = {
            classic = {}, nerd = { "GlassL", "GlassR" }, bully = { "Cap", "Brim", "BrowL", "BrowR" },
            cool = { "Shades" }, punk = { "Spikes" }, chad = { "Shades", "Crown" },
        }
        local function ApplyLook()
            local Kind = KindById[Pet.kind] or Kinds[1]
            UI.Body.BackgroundColor3, UI.Head.BackgroundColor3 = Kind.body, Kind.head
            UI.ArmLeft.BackgroundColor3, UI.ArmRight.BackgroundColor3 = Kind.body, Kind.body
            for Key, Value in Acc do
                if typeof(Value) == "table" then for _, Spike in Value do Spike.Visible = false end else Value.Visible = false end
            end
            for _, Key in Looks[Kind.id] or {} do
                local Value = Acc[Key]
                if typeof(Value) == "table" then for _, Spike in Value do Spike.Visible = true end elseif Value then Value.Visible = true end
            end
            UI.Head.Size = Kind.id == "chad" and UDim2.fromOffset(94, 70) or UDim2.fromOffset(82, 70)
            UI.Scale.Scale = StageScale[StageOf(Pet)]
            UI.Name.Text = KindName(Kind) .. " - " .. StageName(StageOf(Pet))
        end

        UI.Grave = New("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(92, 112), BackgroundTransparency = 1, Visible = false }, Sky)
        local Stone = New("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(80, 92), BackgroundColor3 = Color3.fromRGB(105, 110, 122), BorderSizePixel = 0 }, UI.Grave)
        Round(Stone, 20)
        New("UIStroke", { Color = Color3.fromRGB(45, 48, 57), Thickness = 3 }, Stone)
        UI.StoneText = New("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "RIP", TextColor3 = Color3.fromRGB(40, 42, 50), Font = Enum.Font.GothamBold, TextSize = 14, TextWrapped = true }, Stone)

        UI.Reticle = New("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(90, 90), BackgroundTransparency = 1, Text = "+", TextColor3 = Color3.fromRGB(255, 80, 70), Font = Enum.Font.GothamBlack, TextSize = 70, Visible = false }, Sky)
        UI.Drone = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1.15, 0.25), Size = UDim2.fromOffset(54, 24), BackgroundColor3 = Color3.fromRGB(45, 48, 55), BorderSizePixel = 0, Visible = false }, Sky)
        Round(UI.Drone, 6)
        New("UIStroke", { Color = Color3.fromRGB(15, 15, 18), Thickness = 2 }, UI.Drone)
        for _, X in { -20, 20 } do
            local Rotor = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, X, 0.5, 0), Size = UDim2.fromOffset(34, 4), BackgroundColor3 = Color3.fromRGB(25, 25, 30), BorderSizePixel = 0 }, UI.Drone)
            Round(Rotor, 3)
        end
        UI.Flash = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, BackgroundTransparency = 1, Visible = false }, Sky)
        UI.Food = New("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150), Size = UDim2.fromOffset(80, 24), BackgroundTransparency = 1, Text = "+30", TextColor3 = Color3.fromRGB(150, 255, 150), Font = Enum.Font.GothamBold, TextSize = 20, Visible = false }, Sky)
        PetBox:AddUIPassthrough("TamagochiCanvas", { Instance = UI.Canvas, Height = 235, Visible = true })

        local StatusLabel = StatusBox:AddLabel("", true)
        local AwayLabel = StatusBox:AddLabel("", true)
        local UpdateUI
        local Animation, AnimationToken = nil, 0
        local FeedUntil, LastFeed = 0, 0
        local FeedButton = StatusBox:AddButton({ Text = L("Feed", "Покормить"), Tooltip = L("+30 hunger, 3 s cooldown.", "+30 к сытости, перезарядка 3 с."), Func = function()
            if not Pet.alive then Functions.Notify({ Title = PetName, Body = L("Too late, he is dead.", "Поздно, он мертв.") }) return end
            if Animation then return end
            local Stamp = tick()
            if Stamp - LastFeed < 3 then return end
            if Pet.hunger >= 99.5 then Functions.Notify({ Title = PetName, Body = L("He is full.", "Он сыт.") }) return end
            LastFeed, FeedUntil = Stamp, Stamp + 1.3
            Pet.hunger = math.min(100, Pet.hunger + 30)
            Pet.mood = math.min(100, Pet.mood + 6)
            SavePet()
            if UpdateUI then UpdateUI() end
        end })
        local BuryButton = StatusBox:AddButton({ Text = L("Bury him", "Похоронить"), Tooltip = L("Removes the dead pet from your list (a free one appears if you have none left).", "Убирает мёртвого питомца из списка (если никого не осталось, появится бесплатный)."), Func = function()
            if Pet.alive or Animation then return end
            table.remove(Root.pets, Root.sel)
            if #Root.pets == 0 then Root.pets[1] = NewPet("classic") end
            Root.sel = math.clamp(Root.sel, 1, #Root.pets)
            Pet = Root.pets[Root.sel]
            SavePet()
            ApplyLook()
            if RefreshLists then RefreshLists() end
            if UpdateUI then UpdateUI() end
        end })
        local SVOButton = StatusBox:AddButton({ Text = L("sent him to SVO", "отправить его на СВО"), Tooltip = L("Cartoon fictional scene: no real flags, units or people.", "Мультяшная вымышленная сцена без реальных флагов, частей и людей."), Func = function()
            if not Pet.alive or Animation then return end
            AnimationToken += 1
            Animation = { Start = tick(), Token = AnimationToken }
            Pet.alive, Pet.deathAt, Pet.deathCause = false, os.time(), "cartoon_svo"
            SavePet()
            if UpdateUI then UpdateUI() end
        end })
        StatusBox:AddDivider()
        StatusBox:AddLabel(L("Hunger falls only while you play. Pets grow up with play time. Gold you pick up becomes pet coins.", "Голод падает только во время игры. Питомцы взрослеют от времени игры. Золото, которое ты подбираешь, становится монетами питомцев."), true)

        UpdateUI = function()
            local Age = math.max(0, os.time() - Pet.birth)
            pcall(function() StatusLabel:SetText(string.format(
                "%s: %s\n%s: %d/100\n%s: %d/100\n%s: %d | %s: %d\n%s: %d | %s: %s\n%s: %d | %s: %d | %s: %d",
                L("State", "Состояние"), Pet.alive and L("alive", "жив") or L("dead", "мертв"),
                L("Hunger", "Голод"), math.floor(Pet.hunger + 0.5), L("Mood", "Настроение"), math.floor(Pet.mood + 0.5),
                L("Rooms", "Комнаты"), Root.rooms, L("Gold", "Золото"), Root.gold,
                L("Deaths", "Смерти"), Root.deaths, L("Played", "Сыграно"), Fmt(Root.totalPlaytime),
                L("Coins", "Монеты"), Root.coins, L("Brainrots", "Брейнроты"), Root.brainrots, L("Pets", "Питомцы"), #Root.pets
            )) end)
            local Cause
            if not Pet.alive then
                Cause = Pet.deathCause == "away" and L("Died after 48 hours without play.", "Умер после 48 часов без игры.")
                    or Pet.deathCause == "cartoon_svo" and L("Lost in the cartoon FPV scene.", "Погиб в мультяшной FPV-сцене.") or L("The pet is dead.", "Питомец мертв.")
            else
                Cause = string.format("%s: %dh | %s: %s", L("Age", "Возраст"), math.floor(Age / 3600), L("Stage", "Стадия"), StageName(StageOf(Pet)))
            end
            pcall(function() AwayLabel:SetText(Cause) end)
            pcall(function() BuryButton:SetVisible(not Pet.alive and not Animation) end)
            pcall(function() SVOButton:SetVisible(Pet.alive and not Animation) end)
            pcall(function() FeedButton:SetVisible(Pet.alive and not Animation) end)
            UI.Grave.Visible = not Pet.alive and not Animation
            UI.StoneText.Text = "RIP\n" .. KindName(KindById[Pet.kind] or Kinds[1])
            UI.Holder.Visible = Pet.alive or Animation ~= nil
            UI.Scale.Scale = StageScale[StageOf(Pet)]
            UI.Name.Text = KindName(KindById[Pet.kind] or Kinds[1]) .. " - " .. StageName(StageOf(Pet))
        end

        -- shop + pet switcher
        local ShopMap, ActiveMap, Refreshing = {}, {}, false
        local function ShopLabel(Kind)
            return KindName(Kind) .. (Kind.brainrots and string.format(" (%d %s)", Kind.brainrots, L("brainrots", "брейнротов")) or string.format(" (%d)", Kind.coins))
        end
        local ShopValues = {}
        for _, Kind in Kinds do
            if Kind.id ~= "classic" then ShopValues[#ShopValues + 1] = ShopLabel(Kind) ShopMap[ShopLabel(Kind)] = Kind end
        end
        ShopBox:AddDropdown("PetShopKind", { Text = L("Pet", "Питомец"), Values = ShopValues, Default = 1 })
        ShopBox:AddButton({ Text = L("Buy pet", "Купить питомца"), Tooltip = L("2000 pet coins each. Gigachad costs 15 stolen brainrots instead.", "2000 монет каждый. Гигачад стоит 15 украденных брейнротов."), Func = function()
            local Kind = ShopMap[Options.PetShopKind.Value]
            if not Kind then return end
            if #Root.pets >= 8 then Functions.Notify({ Title = L("Shop", "Магазин"), Body = L("8 pets is the limit.", "Максимум 8 питомцев.") }) return end
            if Kind.brainrots then
                if Root.brainrots < Kind.brainrots then Functions.Notify({ Title = L("Shop", "Магазин"), Body = L("Not enough brainrots: ", "Не хватает брейнротов: ") .. Root.brainrots .. "/" .. Kind.brainrots }) return end
                Root.brainrots -= Kind.brainrots
            else
                if Root.coins < Kind.coins then Functions.Notify({ Title = L("Shop", "Магазин"), Body = L("Not enough coins: ", "Не хватает монет: ") .. Root.coins .. "/" .. Kind.coins }) return end
                Root.coins -= Kind.coins
            end
            Root.pets[#Root.pets + 1] = NewPet(Kind.id)
            Root.sel = #Root.pets
            Pet = Root.pets[Root.sel]
            SavePet()
            ApplyLook()
            RefreshLists()
            UpdateUI()
            Functions.Notify({ Title = L("Shop", "Магазин"), Body = L("Bought: ", "Куплен: ") .. KindName(Kind) })
        end })
        ShopBox:AddDivider()
        ShopBox:AddDropdown("PetActive", { Text = L("Active pet", "Активный питомец"), Values = { "1" }, Default = 1 })
        RefreshLists = function()
            Refreshing = true
            table.clear(ActiveMap)
            local Values = {}
            for Index, P in Root.pets do
                local Label = string.format("%d. %s (%s)%s", Index, KindName(KindById[P.kind] or Kinds[1]), StageName(StageOf(P)), P.alive and "" or " x")
                Values[#Values + 1] = Label
                ActiveMap[Label] = Index
            end
            pcall(function() Options.PetActive:SetValues(Values) end)
            pcall(function() Options.PetActive:SetValue(Values[Root.sel]) end)
            Refreshing = false
        end
        Options.PetActive:OnChanged(function(Value)
            if Refreshing then return end
            local Index = ActiveMap[Value]
            if not Index or Index == Root.sel or not Root.pets[Index] then return end
            Root.sel = Index
            Pet = Root.pets[Index]
            Animation = nil
            ApplyLook()
            UpdateUI()
        end)
        RefreshLists()
        ApplyLook()
        UpdateUI()

        local PreviousRoom = LatestRoom and LatestRoom.Value or 0
        if LatestRoom then
            Connections.TamagochiRoom = LatestRoom.Changed:Connect(function(NewRoom)
                NewRoom = tonumber(NewRoom) or PreviousRoom
                if NewRoom > PreviousRoom then
                    local Passed = NewRoom - PreviousRoom
                    Root.rooms += Passed
                    Root.coins += Passed * 3
                    ForAlive(function(P)
                        P.hunger = math.max(0, P.hunger - Passed)
                        P.mood = math.min(100, P.mood + Passed * 1.5)
                    end)
                    UpdateUI()
                end
                PreviousRoom = NewRoom
            end)
        end
        local function HookCurrency(CurrencyRemote)
            if Connections.TamagochiGold then Connections.TamagochiGold:Disconnect() Connections.TamagochiGold = nil end
            if not CurrencyRemote or CurrencyRemote.Name ~= "GetCurrency" or not CurrencyRemote:IsA("RemoteEvent") then return end
            Connections.TamagochiGold = CurrencyRemote.OnClientEvent:Connect(function(_, Amount, Currency)
                if type(Amount) == "number" and Amount > 0 and (Currency == nil or Currency == "Gold") then
                    Root.gold += Amount
                    Root.coins += math.floor(Amount)
                    ForAlive(function(P)
                        P.hunger = math.min(100, P.hunger + math.max(1, Amount / 25))
                        P.mood = math.min(100, P.mood + math.max(0.5, Amount / 100))
                    end)
                    UpdateUI()
                end
            end)
        end
        HookCurrency(RemotesFolder and RemotesFolder:FindFirstChild("GetCurrency"))
        if RemotesFolder then
            Connections.TamagochiCurrencyAdded = RemotesFolder.ChildAdded:Connect(function(Object)
                if Object.Name == "GetCurrency" then HookCurrency(Object) end
            end)
        end
        local WasAlive = LocalPlayer:GetAttribute("Alive")
        Connections.TamagochiDeath = LocalPlayer:GetAttributeChangedSignal("Alive"):Connect(function()
            local IsAlive = LocalPlayer:GetAttribute("Alive")
            if WasAlive == true and IsAlive == false then
                Root.deaths += 1
                ForAlive(function(P) P.mood = math.max(0, P.mood - 18) end)
                UpdateUI()
            end
            WasAlive = IsAlive
        end)

        local LastVisualUpdate = 0
        Connections.TamagochiRender = RunService.RenderStepped:Connect(function()
            if not Alive then return end
            local Time = tick()
            if Time - LastVisualUpdate > 1 then LastVisualUpdate = Time UpdateUI() end
            local Bob = math.sin(Time * 2.2) * 3
            UI.Holder.Position = UDim2.new(0.5, 0, 1, -28 + Bob)
            local Blink = Time % 4.2 > 3.92
            UI.EyeLeft.Size, UI.EyeRight.Size = UDim2.fromOffset(10, Blink and 2 or 14), UDim2.fromOffset(10, Blink and 2 or 14)
            UI.Mouth.Size = UDim2.fromOffset(Pet.mood < 30 and 18 or 24, Pet.mood < 30 and 3 or 5)
            if Time < FeedUntil then
                UI.Mouth.Size = UDim2.fromOffset(22, 4 + math.floor(math.abs(math.sin(Time * 14)) * 14))
                UI.Food.Visible = true
                UI.Food.Position = UDim2.new(0.5, 0, 1, -150 - (1.3 - (FeedUntil - Time)) * 25)
                UI.Food.TextTransparency = math.clamp(1 - (FeedUntil - Time) / 0.5, 0, 1)
            elseif UI.Food.Visible then
                UI.Food.Visible = false
            end
            UI.ArmLeft.Rotation = -18 + math.sin(Time * 3) * 8
            UI.ArmRight.Rotation = 18 - math.sin(Time * 3) * 8

            if Animation then
                local Elapsed = Time - Animation.Start
                UI.Grave.Visible = false
                UI.Holder.Visible = Elapsed < 3.4
                UI.Reticle.Visible = Elapsed >= 0.8 and Elapsed < 3.4
                UI.Drone.Visible = Elapsed >= 1.1 and Elapsed < 3.4
                if UI.Drone.Visible then
                    local P = math.clamp((Elapsed - 1.1) / 2.1, 0, 1)
                    P = P * P * (3 - 2 * P)
                    UI.Drone.Position = UDim2.fromScale(1.12 + (0.5 - 1.12) * P, 0.22 + (0.64 - 0.22) * P)
                    UI.Drone.Rotation = math.sin(Time * 30) * 7
                end
                UI.Flash.Visible = Elapsed >= 3.2 and Elapsed < 3.75
                UI.Flash.BackgroundTransparency = UI.Flash.Visible and math.clamp((Elapsed - 3.2) / 0.55, 0, 1) or 1
                if Elapsed >= 4.1 then
                    Animation = nil
                    UI.Reticle.Visible, UI.Drone.Visible, UI.Flash.Visible = false, false, false
                    UpdateUI()
                end
            end
        end)

        task.spawn(function()
            while Alive do
                task.wait(30)
                if not Alive then break end
                SavePet()
            end
        end)
        pcall(function() Library:OnUnload(function()
            AnimationToken += 1
            Animation = nil
            SavePet()
        end) end)

        ---------------------------------------------------------------------
        -- Steal a Brainrot: local collectibles that pop up somewhere in the room you are in
        ---------------------------------------------------------------------
        do
            BrainBox:AddToggle("StealBrainrot", {
                Text = L("Steal a Brainrot", "Укради брейнрот"), Default = false,
                Tooltip = L("Brainrots pop up at random spots in your room (only you see them). Hold the prompt to steal one. 15 of them buy the Gigachad.", "Брейнроты появляются в случайных местах твоей комнаты (видишь только ты). Зажми промпт, чтобы украсть. За 15 штук покупается Гигачад.")
            })
            BrainBox:AddSlider("BrainrotInterval", { Text = L("Spawn every (s)", "Появление раз в (с)"), Default = 25, Min = 8, Max = 90, Rounding = 0, Compact = true })
            local CountLabel = BrainBox:AddLabel("", true)
            local Names = {
                { "Tralala Bananini", 1 }, { "Bombini Gusini", 1 }, { "Capucha Frogo", 1 }, { "Sigma Spaghetto", 2 },
                { "Ohio Cactusini", 2 }, { "Skibidi Pickle", 2 }, { "Gyatt Gnocchi", 3 }, { "Rizz Raviolo", 4 },
            }
            local Rarity = {
                { "Common", "Обычный", Color3.fromRGB(190, 190, 200) }, { "Rare", "Редкий", Color3.fromRGB(90, 160, 255) },
                { "Epic", "Эпический", Color3.fromRGB(190, 90, 255) }, { "Legendary", "Легендарный", Color3.fromRGB(255, 190, 40) },
            }
            local Folder = New("Folder", { Name = "AMRBrainrots" }, workspace)
            local FleeParams = RaycastParams.new()
            FleeParams.FilterType = Enum.RaycastFilterType.Exclude
            Root.owned = type(Root.owned) == "table" and Root.owned or {}
            Root.stash = tonumber(Root.stash) or 0
            local Rates = { 1, 3, 8, 20 }
            local OwnedBox = Tabs.Tamagochi:AddRightGroupbox(L("My Brainrots", "Мои брейнроты"))
            local OwnedLabel = OwnedBox:AddLabel("", true)
            local Active = {}
            local Elapsed, IncomeTimer = 0, 0
            local function Clear()
                for Entry in Active do if Entry.Part then Entry.Part:Destroy() end Active[Entry] = nil end
            end
            local TierOf = {}
            for _, Entry in Names do TierOf[Entry[1]] = Entry[2] end
            local function Income()
                local Total = 0
                for Name, Amount in Root.owned do Total += (Rates[TierOf[Name] or 1] or 1) * Amount end
                return Total
            end
            local function Count()
                CountLabel:SetText(string.format("%s: %d / 15", L("Stolen", "Украдено"), Root.brainrots))
                local Lines = {}
                for Name, Amount in Root.owned do Lines[#Lines + 1] = Name .. " x" .. Amount end
                table.sort(Lines)
                OwnedLabel:SetText((#Lines > 0 and table.concat(Lines, "\n") or L("No brainrots yet.", "Пока пусто.")) .. string.format("\n\n%s: %d / min\n%s: %d", L("Income", "Доход"), Income(), L("Waiting", "Ждёт"), math.floor(Root.stash)))
            end
            OwnedBox:AddButton({ Text = L("Collect gold", "Забрать золото"), Tooltip = L("Moves the gold your brainrots made into pet coins (fake gold, only used for the pet shop).", "Переводит золото, которое принесли брейнроты, в монеты питомцев (фейковое, только для магазина)."), Func = function()
                local Amount = math.floor(Root.stash)
                if Amount <= 0 then return end
                Root.stash -= Amount
                Root.coins += Amount
                Count()
                UpdateUI()
                pcall(function() Boot.SaveJSON("Pet.json", Root) end)
            end })
            Count()
            local function RandomSpot()
                local Rooms = workspace:FindFirstChild("CurrentRooms")
                local Room = Rooms and Rooms:FindFirstChild(tostring(LocalPlayer:GetAttribute("CurrentRoom")))
                if not Room or not Room:IsA("Model") then return nil end
                local Ok, Center, Size = pcall(function() return Room:GetBoundingBox() end)
                if not Ok then return nil end
                local Params = RaycastParams.new()
                Params.FilterType = Enum.RaycastFilterType.Exclude
                Params.FilterDescendantsInstances = { LocalPlayer.Character, Folder }
                for _ = 1, 10 do
                    local X = Center.Position.X + (math.random() - 0.5) * Size.X * 0.7
                    local Z = Center.Position.Z + (math.random() - 0.5) * Size.Z * 0.7
                    local Hit = workspace:Raycast(Vector3.new(X, Center.Position.Y + Size.Y * 0.3, Z), Vector3.new(0, -Size.Y * 1.2, 0), Params)
                    if Hit and Hit.Normal.Y > 0.7 then return Hit.Position + Vector3.new(0, 2, 0) end
                end
                return nil
            end
            local function Spawn()
                local Position = RandomSpot()
                if not Position then return end
                local Roll = math.random(1, 100)
                local Tier = Roll <= 55 and 1 or Roll <= 82 and 2 or Roll <= 95 and 3 or 4
                local Pool = {}
                for _, Entry in Names do if Entry[2] == Tier or Entry[2] == Tier - 1 then Pool[#Pool + 1] = Entry end end
                local Chosen = Pool[math.random(1, #Pool)] or Names[1]
                local Rare = Rarity[Tier]
                local Part = New("Part", {
                    Name = "AMRBrainrot", Size = Vector3.new(2, 3, 1.4), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
                    Material = Enum.Material.Neon, Color = Rare[3], CFrame = CFrame.new(Position),
                }, Folder)
                local Gui = New("BillboardGui", { Size = UDim2.fromOffset(160, 40), StudsOffset = Vector3.new(0, 3, 0), AlwaysOnTop = true }, Part)
                New("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = Chosen[1] .. "\n" .. L(Rare[1], Rare[2]), TextColor3 = Rare[3], Font = Enum.Font.GothamBold, TextSize = 14, TextStrokeTransparency = 0.4 }, Gui)
                local Prompt = New("ProximityPrompt", {
                    ActionText = L("Steal", "Украсть"), ObjectText = Chosen[1], HoldDuration = 0.8 + Tier * 0.2,
                    MaxActivationDistance = 9, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.E,
                }, Part)
                local Entry = { Part = Part, Base = Position, Seed = math.random() * 6, Expires = tick() + 60, Tier = Tier, Name = Chosen[1] }
                Active[Entry] = true
                Prompt.Triggered:Connect(function()
                    if not Active[Entry] then return end
                    Active[Entry] = nil
                    Part:Destroy()
                    Root.brainrots += 1
                    Root.owned[Entry.Name] = (Root.owned[Entry.Name] or 0) + 1
                    ForAlive(function(P) P.mood = math.min(100, P.mood + 8) end)
                    Count()
                    UpdateUI()
                    Functions.Notify({ Title = L("Stolen!", "Украдено!"), Body = Chosen[1] .. " (" .. Root.brainrots .. ")" })
                    pcall(function() Boot.SaveJSON("Pet.json", Root) end)
                end)
            end
            Connections.BrainrotLoop = RunService.Heartbeat:Connect(function(Dt)
                local Time = tick()
                for Entry in Active do
                    if not Entry.Part.Parent or Time > Entry.Expires then
                        Entry.Part:Destroy() Active[Entry] = nil
                    else
                        local Character = LocalPlayer.Character
                        local Body = Character and Character:FindFirstChild("HumanoidRootPart")
                        if Body then
                            local Away = Vector3.new(Entry.Base.X - Body.Position.X, 0, Entry.Base.Z - Body.Position.Z)
                            if Away.Magnitude < 20 and Away.Magnitude > 0.05 then
                                FleeParams.FilterDescendantsInstances = { Character, Folder }
                                local Step = (9 + Entry.Tier * 2) * Dt
                                local Direction = Away.Unit
                                local Hit = workspace:Raycast(Entry.Base, Direction * (Step + 1.3), FleeParams)
                                if not Hit then
                                    Entry.Base += Direction * Step
                                else
                                    local Slide = Direction - Hit.Normal * Direction:Dot(Hit.Normal)
                                    if Slide.Magnitude > 0.1 and not workspace:Raycast(Entry.Base, Slide.Unit * (Step + 1.3), FleeParams) then
                                        Entry.Base += Slide.Unit * Step
                                    end
                                end
                                local Ground = workspace:Raycast(Entry.Base + Vector3.new(0, 1.5, 0), Vector3.new(0, -6, 0), FleeParams)
                                if Ground then Entry.Base = Vector3.new(Entry.Base.X, Ground.Position.Y + 2, Entry.Base.Z) end
                            end
                        end
                        Entry.Part.CFrame = CFrame.new(Entry.Base + Vector3.new(0, math.sin(Time * 2 + Entry.Seed) * 0.4, 0)) * CFrame.Angles(0, Time * 1.5 + Entry.Seed, 0)
                    end
                end
                IncomeTimer += Dt
                if IncomeTimer >= 60 then
                    IncomeTimer -= 60
                    Root.stash += Income()
                    Count()
                end
                if not Toggles.StealBrainrot.Value then Elapsed = 0 return end
                Elapsed += Dt
                if Elapsed >= Options.BrainrotInterval.Value then
                    Elapsed = 0
                    local Live = 0
                    for _ in Active do Live += 1 end
                    if Live < 4 then Spawn() end
                end
            end)
            Toggles.StealBrainrot:OnChanged(function(Value)
                if not Value then Clear() else Elapsed = Options.BrainrotInterval.Value - 3 end
            end)
            local LastRoom = LocalPlayer:GetAttribute("CurrentRoom")
            Connections.BrainrotRoom = LocalPlayer:GetAttributeChangedSignal("CurrentRoom"):Connect(function()
                local Now = LocalPlayer:GetAttribute("CurrentRoom")
                if Now ~= LastRoom then LastRoom = Now Clear() end
            end)
            pcall(function() Library:OnUnload(function() Clear() Folder:Destroy() end) end)
        end
    end

    ---------------------------------------------------------------------
    -- FPV SHOPPING CART (Stairwell): grab a cart from behind (hold + release the push prompt), then fly it first-person
    ---------------------------------------------------------------------
    do
        Globals.Freeze = Globals.Freeze or {}
        Groupboxes.Imported_FPVCart = Tabs.Stairwell:AddRightGroupbox("FPV Cart")
        local CartBox = Groupboxes.Imported_FPVCart
        CartBox:AddToggle("FPVCart", {
            Text = "FPV Cart", Default = false,
            Tooltip = "Hold and release a Stairwell shopping cart push prompt from behind. Your character freezes; WASD/mobile stick moves only the cart."
        })
        CartBox:AddSlider("FPVCartSpeed", { Text = "Cart Flight Speed", Default = 55, Min = 15, Max = 120, Rounding = 0, Compact = true })
        CartBox:AddToggle("FPVCartCollide", { Text = "Cart Collision", Default = true, Tooltip = "On: the cart collides with floors and walls. Off: it passes through everything." })
        CartBox:AddSlider("FPVCartLookSpeed", { Text = "Look Speed", Default = 1.5, Min = 0.3, Max = 4, Rounding = 1, Compact = true })
        CartBox:AddSlider("FPVCartEyeHeight", { Text = "Camera Height", Default = 2.5, Min = 0, Max = 6, Rounding = 1, Compact = true })

        local PushPrompts = { CartPrompt = true, PushPrompt = true, LongPushPrompt = true, BigPropPrompt = true }
        local FPVCart = { Token = 0, Connections = {} }

        local function CartCollider(Model)
            local Found = Model:FindFirstChild("Collider") or Model.PrimaryPart
            if Found and Found:IsA("BasePart") then return Found end
            local Best, BestVolume = nil, 0
            for _, Part in Model:GetDescendants() do
                if Part:IsA("BasePart") then
                    local Volume = Part.Size.X * Part.Size.Y * Part.Size.Z
                    if Volume > BestVolume then Best, BestVolume = Part, Volume end
                end
            end
            return Best
        end
        local function CartFromPrompt(Prompt)
            if not PushPrompts[Prompt.Name] then return nil end
            local Node = Prompt
            while Node and Node ~= workspace do
                if Node:IsA("Model") and Node.Name == "ShoppingCart" then return Node end
                Node = Node.Parent
            end
            return nil
        end
        local function NearestCart()
            local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not Root then return nil end
            local Best, BestDistance = nil, math.huge
            local function Check(Object)
                if Object:IsA("Model") and Object.Name == "ShoppingCart" then
                    local Collider = CartCollider(Object)
                    if Collider then
                        local Distance = (Root.Position - Collider.Position).Magnitude
                        if Distance < BestDistance then Best, BestDistance = Object, Distance end
                    end
                end
            end
            local Misc = workspace:FindFirstChild("Misc")
            if Misc then for _, Object in Misc:GetDescendants() do Check(Object) end end
            local Rooms = workspace:FindFirstChild("CurrentRooms")
            if Rooms then
                for _, Room in Rooms:GetChildren() do
                    local Assets = Room:FindFirstChild("Assets")
                    if Assets then for _, Object in Assets:GetDescendants() do Check(Object) end end
                end
            end
            return Best
        end

        local function StopFPVCart()
            FPVCart.Token += 1
            for _, Connection in FPVCart.Connections do pcall(function() Connection:Disconnect() end) end
            table.clear(FPVCart.Connections)
            if Globals.FPVChairActive == "cart" then Globals.FPVChairActive = nil end
            Globals.Freeze.FPVCart = nil
            local Current = FPVCart.Current
            FPVCart.Current, FPVCart.Pending = nil, nil
            if not Current then return end
            if Current.Humanoid and Current.Humanoid.Parent then Current.Humanoid.AutoRotate = Current.OldAutoRotate end
            local Camera = workspace.CurrentCamera
            if Camera and Current.OldCameraSubject then
                Camera.CameraSubject = Current.OldCameraSubject
                Camera.CameraType = Current.OldCameraType or Enum.CameraType.Custom
            end
            if Current.Gui then Current.Gui:Destroy() end
            pcall(function() Services.UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
            for Part, Value in Current.CartCollision do
                if Part.Parent then Part.CanCollide = Value Part.LocalTransparencyModifier = 0 end
            end
            if Current.DrivePart and Current.DrivePart.Parent then
                Current.DrivePart.AssemblyLinearVelocity = Vector3.zero
                Current.DrivePart.AssemblyAngularVelocity = Vector3.zero
            end
        end

        local function StartFPVCart(Pending)
            if FPVCart.Current or not Toggles.FPVCart.Value then return end
            local Model = Pending.Cart
            local DrivePart = Model and CartCollider(Model)
            local SourceCharacter = LocalPlayer.Character
            local SourceHumanoid = SourceCharacter and SourceCharacter:FindFirstChildOfClass("Humanoid")
            if not Model or not Model.Parent or not DrivePart or not SourceHumanoid then
                Functions.Notify({ Title = "FPV Cart", Body = "Cart or your character is unavailable." })
                Toggles.FPVCart:SetValue(false)
                return
            end
            local Controls
            pcall(function() Controls = require(LocalPlayer.PlayerScripts.PlayerModule):GetControls() end)
            local Camera = workspace.CurrentCamera
            local CartCollision = {}
            for _, Part in Model:GetDescendants() do
                if Part:IsA("BasePart") then CartCollision[Part] = Part.CanCollide Part.CanCollide = Toggles.FPVCartCollide.Value end
            end
            local Current = {
                CartCollision = CartCollision, Cart = Model, DrivePart = DrivePart, SourceCharacter = SourceCharacter,
                Humanoid = SourceHumanoid, OldAutoRotate = SourceHumanoid.AutoRotate, Controls = Controls,
                OldCameraSubject = Camera and Camera.CameraSubject, OldCameraType = Camera and Camera.CameraType,
                StartPosition = DrivePart.Position,
            }
            FPVCart.Current = Current
            Globals.Freeze.FPVCart = true
            SourceHumanoid.AutoRotate = false
            do
                local Look = Camera and Camera.CFrame.LookVector or Vector3.new(0, 0, -1)
                Current.Yaw, Current.Pitch = math.atan2(-Look.X, -Look.Z), math.asin(math.clamp(Look.Y, -1, 1))
            end
            if Camera then Camera.CameraType = Enum.CameraType.Scriptable end
            pcall(function() Services.UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end)
            FPVCart.Connections[#FPVCart.Connections + 1] = Services.UserInputService.InputChanged:Connect(function(Input)
                if FPVCart.Current ~= Current then return end
                if Input.UserInputType == Enum.UserInputType.MouseMovement then
                    Current.Yaw -= Input.Delta.X * 0.0025 * Options.FPVCartLookSpeed.Value
                    Current.Pitch = math.clamp(Current.Pitch - Input.Delta.Y * 0.0025 * Options.FPVCartLookSpeed.Value, -1.45, 1.45)
                elseif Input.UserInputType == Enum.UserInputType.Touch then
                    local Viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000, 600)
                    if Input.Position.X > Viewport.X * 0.4 and not Current.OverButton then
                        Current.Yaw -= Input.Delta.X * 0.012 * Options.FPVCartLookSpeed.Value
                        Current.Pitch = math.clamp(Current.Pitch - Input.Delta.Y * 0.012 * Options.FPVCartLookSpeed.Value, -1.45, 1.45)
                    end
                end
            end)
            do
                local Gui = New("ScreenGui", { Name = "AMRFPVCartButtons", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 60 }, GetHiddenContainer())
                Current.Gui = Gui
                local function HoldButton(Text, Y, Key)
                    local Button = New("TextButton", {
                        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, Y), Size = UDim2.fromOffset(64, 64),
                        BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = Text, TextColor3 = Color3.new(1, 1, 1),
                        Font = Enum.Font.GothamBold, TextSize = 26, AutoButtonColor = false,
                    }, Gui)
                    Round(Button, 32)
                    Button.InputBegan:Connect(function(Input)
                        if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
                            Current[Key], Current.OverButton = true, true
                        end
                    end)
                    Button.InputEnded:Connect(function(Input)
                        if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
                            Current[Key], Current.OverButton = false, false
                        end
                    end)
                end
                HoldButton("^", -40, "UpHeld")
                HoldButton("v", 40, "DownHeld")
            end
            Functions.Notify({ Title = "FPV Cart", Body = "Look anywhere and push the stick: the cart flies where you look. ^ / v buttons (or Space / Shift) go up and down." })
            local Token = FPVCart.Token
            FPVCart.Connections[#FPVCart.Connections + 1] = RunService.Heartbeat:Connect(function()
                if Token ~= FPVCart.Token or FPVCart.Current ~= Current or not Toggles.FPVCart.Value then return end
                if LocalPlayer.Character ~= SourceCharacter or not Model.Parent or not DrivePart.Parent or SourceHumanoid.Health <= 0 then
                    Toggles.FPVCart:SetValue(false)
                    return
                end
                local Collide = Toggles.FPVCartCollide.Value
                for Part in Current.CartCollision do
                    if Part.Parent and Part.CanCollide ~= Collide then Part.CanCollide = Collide end
                end
                if DrivePart.Position.Y < Current.StartPosition.Y - 25 then
                    Model:PivotTo(CFrame.new(DrivePart.Position.X, Current.StartPosition.Y + 2, DrivePart.Position.Z))
                end
                local Move = Current.Controls and Current.Controls:GetMoveVector() or Vector3.zero
                local CurrentCamera = workspace.CurrentCamera
                local Look3 = CurrentCamera and CurrentCamera.CFrame.LookVector or Vector3.new(0, 0, -1)
                local Right = Vector3.new(Look3.Z, 0, -Look3.X)
                Right = Right.Magnitude > 0.01 and -Right.Unit or Vector3.xAxis
                local UIS = Services.UserInputService
                local Vertical = ((UIS:IsKeyDown(Enum.KeyCode.Space) or Current.UpHeld) and 1 or 0) - ((UIS:IsKeyDown(Enum.KeyCode.LeftShift) or Current.DownHeld) and 1 or 0)
                local WorldMove = Right * Move.X + Look3 * -Move.Z + Vector3.yAxis * Vertical
                if WorldMove.Magnitude > 0.01 then WorldMove = WorldMove.Unit * Options.FPVCartSpeed.Value end
                DrivePart.AssemblyLinearVelocity = WorldMove
                DrivePart.AssemblyAngularVelocity = Vector3.zero
            end)
            FPVCart.Connections[#FPVCart.Connections + 1] = RunService.RenderStepped:Connect(function()
                if FPVCart.Current ~= Current or not DrivePart.Parent then return end
                local CurrentCamera = workspace.CurrentCamera
                if CurrentCamera then
                    if CurrentCamera.CameraType ~= Enum.CameraType.Scriptable then CurrentCamera.CameraType = Enum.CameraType.Scriptable end
                    CurrentCamera.CFrame = CFrame.new(DrivePart.Position + Vector3.new(0, Options.FPVCartEyeHeight.Value, 0)) * CFrame.fromOrientation(Current.Pitch, Current.Yaw, 0)
                end
                for Part in Current.CartCollision do
                    if Part.Parent then Part.LocalTransparencyModifier = 1 end
                end
            end)
        end

        local function ArmFPVCart(Value)
            StopFPVCart()
            if not Value then return end
            if Toggles.FPVChair and Toggles.FPVChair.Value then Toggles.FPVChair:SetValue(false) end
            if Toggles.ChairFly and Toggles.ChairFly.Value then Toggles.ChairFly:SetValue(false) end
            Globals.FPVChairActive = "cart"
            FPVCart.Token += 1
            local Token = FPVCart.Token
            local PromptService = Services.ProximityPromptService
            FPVCart.Connections[#FPVCart.Connections + 1] = PromptService.PromptButtonHoldBegan:Connect(function(Prompt)
                if Token ~= FPVCart.Token then return end
                local Model = CartFromPrompt(Prompt)
                if not Model then return end
                FPVCart.Pending = { Prompt = Prompt, Cart = Model, Held = true, Triggered = false, Released = false }
            end)
            FPVCart.Connections[#FPVCart.Connections + 1] = PromptService.PromptTriggered:Connect(function(Prompt)
                if Token ~= FPVCart.Token then return end
                local Pending = FPVCart.Pending
                if not Pending then
                    local Model = CartFromPrompt(Prompt)
                    if Model then Pending = { Prompt = Prompt, Cart = Model, Held = false, Triggered = false, Released = true } FPVCart.Pending = Pending end
                end
                if Pending and Pending.Prompt == Prompt then
                    Pending.Triggered = true
                    Functions.Notify({ Title = "FPV Cart", Body = "Grabbed. Let go of the prompt.", Time = 3 })
                    if Pending.Released then StartFPVCart(Pending) end
                    task.delay(1.5, function()
                        if Token == FPVCart.Token and FPVCart.Pending == Pending and not FPVCart.Current then StartFPVCart(Pending) end
                    end)
                end
            end)
            FPVCart.Connections[#FPVCart.Connections + 1] = PromptService.PromptButtonHoldEnded:Connect(function(Prompt)
                if Token ~= FPVCart.Token then return end
                local Pending = FPVCart.Pending
                if Pending and Pending.Prompt == Prompt then
                    Pending.Held, Pending.Released = false, true
                    if Pending.Triggered then StartFPVCart(Pending) end
                end
            end)
            Functions.Notify({ Title = "FPV Cart", Body = "Stand behind a shopping cart, hold Push, then release it." })
        end

        CartBox:AddButton({ Text = "Drive nearest cart now", Tooltip = "Skips the prompt dance: grab the cart first (hold + release), then press this next to it.", Func = function()
            if not Toggles.FPVCart.Value then Toggles.FPVCart:SetValue(true) end
            if FPVCart.Current then return end
            local Model = NearestCart()
            if not Model then Functions.Notify({ Title = "FPV Cart", Body = "No shopping cart found." }) return end
            StartFPVCart({ Cart = Model })
        end })
        Toggles.FPVCart:OnChanged(ArmFPVCart)
        if Toggles.FPVChair then Toggles.FPVChair:OnChanged(function(Value) if Value and Toggles.FPVCart.Value then Toggles.FPVCart:SetValue(false) end end) end
        if Toggles.ChairFly then Toggles.ChairFly:OnChanged(function(Value) if Value and Toggles.FPVCart.Value then Toggles.FPVCart:SetValue(false) end end) end
        pcall(function() Library:OnUnload(StopFPVCart) end)
    end
end
local Ok, Error = pcall(BuildAMR)
if not Ok then Boot.Print("AMR features failed: " .. tostring(Error)) warn("[AMR] " .. tostring(Error)) end
end

-- groupboxes can't be dragged around (best effort: switches off any drag detector in the menu)
do
    local function Lock(Object)
        if Object:IsA("UIDragDetector") then Object.Enabled = false end
    end
    local MenuGui = Library.ScreenGui
    if MenuGui then
        for _, Object in MenuGui:GetDescendants() do Lock(Object) end
        MenuGui.DescendantAdded:Connect(Lock)
    end
end

Boot.Print("waiting for game UI...")
while not Globals.MainUI do task.wait() end
Boot.Print("game UI found")


Abysall.Interface.ApplySettingsTab(Window)

-- Language is intentionally outside configs; changing it rebuilds the menu so translated tab names stay consistent.
do
    local SettingsTab = Library.Tabs and Library.Tabs.Settings
    if SettingsTab then
        Groupboxes.Settings_Language = SettingsTab:AddLeftGroupbox("Language")
        local Box = Groupboxes.Settings_Language
        Box:AddLabel(string.format("%s: %s (%s)", Boot.T("current", "Current language"), string.upper(Abysall.Localization.Code), tostring(Abysall.Localization.Country)), true)
        Box:AddButton({ Text = "Change language", Tooltip = "Opens the country picker, saves the choice and reloads the hub.", Func = function()
            task.spawn(function()
                local Choice = Boot.OpenLanguagePicker(true)
                if type(Choice) ~= "table" then return end
                if Boot.LanguagePersisted == false then
                    Functions.Notify({ Title = "Language not saved", Body = "This executor did not allow writing AMR/Language.json.", Time = 5 })
                    return
                end
                local Downloaded, Source = false, nil
                for _, Url in Boot.MainUrls do
                    Downloaded, Source = pcall(Boot.Get, Url)
                    if Downloaded and type(Source) == "string" and #Source > 1000 then break end
                    Downloaded = false
                end
                if not Downloaded or type(Source) ~= "string" or Source == "" then
                    Functions.Notify({ Title = "Reload download failed", Body = "The current hub was left open.", Time = 5 })
                    return
                end
                local Compiled, Chunk = pcall(loadstring, Source)
                if not Compiled or type(Chunk) ~= "function" then
                    Functions.Notify({ Title = "Reload compile failed", Body = "The current hub was left open.", Time = 5 })
                    return
                end
                Functions.Notify({ Title = "Language saved", Body = "Reloading the hub...", Time = 2 })
                task.wait(0.35)
                Library:Unload()
                task.wait(0.65)
                local Ran, ReloadError = pcall(Chunk)
                if not Ran then warn("[AMR] language reload failed: " .. tostring(ReloadError)) end
            end)
        end })
    end
end

-- ===== Settings > Configuration: own config system (replaces the SaveManager box) =====
do
local ConfigOk, ConfigError = pcall(function()
    local HttpService = game:GetService("HttpService")
    local function Fn(Name)
        local Value = getgenv()[Name]
        if Value == nil and Abysall.Environment then Value = Abysall.Environment[Name] end
        return Value
    end
    local OwnFolder = "abyssalrecode"
    local Dir = OwnFolder .. "/configs"
    local AutoFile = OwnFolder .. "/autoload.txt"
    pcall(function()
        if Fn("makefolder") and Fn("isfolder") then
            if not Fn("isfolder")(OwnFolder) then Fn("makefolder")(OwnFolder) end
            if not Fn("isfolder")(Dir) then Fn("makefolder")(Dir) end
        end
    end)

    local function Norm(Path) return (string.gsub(Path, "\\", "/")) end
    local function Skipped(Idx)
        return Idx == "MenuKeybind" or string.sub(Idx, 1, 12) == "SaveManager_" or string.sub(Idx, 1, 13) == "ThemeManager_"
            or string.sub(Idx, 1, 9) == "AMRConfig" or Idx == "AutoloadSkip" or Idx == "GardenProbe" or Idx == "HonchoProbe" or Idx == "SingHotkey"
            or Idx == "BackgroundColor" or Idx == "MainColor" or Idx == "AccentColor" or Idx == "OutlineColor" or Idx == "FontColor"
            or Idx == "FontFace" or Idx == "ConfigCodeInput"
    end
    local function Read(Path)
        local Tries = { Path }
        local Tail = string.match(Path, "/workspace/(.+)$")
        if Tail then Tries[#Tries + 1] = Tail end
        Tries[#Tries + 1] = Dir .. "/" .. Path
        Tries[#Tries + 1] = Dir .. "/" .. Path .. ".json"
        Tries[#Tries + 1] = Path .. ".json"
        for _, Try in Tries do
            local Ok, Text = pcall(Fn("readfile"), Try)
            if Ok and type(Text) == "string" and #Text > 0 then return Text, Try end
        end
        return nil
    end

    -- config files found: own folder (by name) + foreign ones anywhere in the workspace
    local Entries = {}   -- label -> path
    local Labels = {}
    local function Walk(Folder, Depth, Found)
        if Depth > 5 or not Fn("listfiles") then return end
        local Ok, List = pcall(Fn("listfiles"), Folder)
        if not Ok or type(List) ~= "table" then return end
        for _, Path in List do
            Path = Norm(Path)
            local Name = string.match(Path, "([^/]+)$") or Path
            if string.lower(string.sub(Name, -5)) == ".json" then
                if not string.find(Name, "UserData", 1, true) and not string.find(Path, "AMR/", 1, true) then
                    local Text = Read(Path)
                    if Text and #Text < 600000 and string.find(Text, '"objects"', 1, true) then Found[#Found + 1] = Path end
                end
            elseif not string.find(Name, ".", 1, true) then
                Walk(Path, Depth + 1, Found)
            end
        end
    end
    local function Scan()
        Entries, Labels = {}, {}
        local Own = {}
        Walk(Dir, 0, Own)
        for _, Path in Own do
            local Name = string.gsub(string.match(Path, "([^/]+)$"), "%.json$", "")
            Entries[Name] = Path
            Labels[#Labels + 1] = Name
        end
        table.sort(Labels)
        local Foreign = {}
        for _, Root in { "Abysall", "abysall", "Obsidian", "Linoria", "." } do Walk(Root, Root == "." and 4 or 0, Foreign) end
        local Seen, Extra = {}, {}
        for _, Path in Foreign do
            if not Seen[Path] and not string.find(Path, Dir, 1, true) then
                Seen[Path] = true
                local Label = "[old] " .. Path
                Entries[Label] = Path
                Extra[#Extra + 1] = Label
            end
        end
        table.sort(Extra)
        for _, Label in Extra do Labels[#Labels + 1] = Label end
        if #Labels == 0 then Labels[1] = "(no configs yet)" end
        Boot.Print("config scan: " .. #Labels .. " entr(ies) | listfiles=" .. tostring(Fn("listfiles") ~= nil))
    end

    local function Collect()
        local List = {}
        for Idx, Toggle in Toggles do
            if not Skipped(Idx) then List[#List + 1] = { type = "Toggle", idx = Idx, value = Toggle.Value == true } end
        end
        for Idx, Option in Options do
            if not Skipped(Idx) then
                pcall(function()
                    local Kind = Option.Type
                    if Kind == "Slider" then
                        List[#List + 1] = { type = "Slider", idx = Idx, value = tostring(Option.Value) }
                    elseif Kind == "Dropdown" then
                        if Option.Value ~= nil then List[#List + 1] = { type = "Dropdown", idx = Idx, value = Option.Value, multi = Option.Multi == true } end
                    elseif Kind == "Input" then
                        List[#List + 1] = { type = "Input", idx = Idx, text = tostring(Option.Value or "") }
                    elseif Kind == "ColorPicker" then
                        List[#List + 1] = { type = "ColorPicker", idx = Idx, value = Option.Value:ToHex(), transparency = Option.Transparency or 0 }
                    elseif Kind == "KeyPicker" then
                        List[#List + 1] = { type = "KeyPicker", idx = Idx, key = Option.Value, mode = Option.Mode, modifiers = Option.Modifiers or {}, toggled = Option.Toggled == true }
                    end
                end)
            end
        end
        return List
    end

    -- readable form of one config entry, used for the diff
    local function Describe(Object)
        local Kind = Object.type
        if Kind == "Toggle" then
            return tostring(Object.value == true)
        elseif Kind == "Slider" then
            return tostring(tonumber(Object.value) or Object.value)
        elseif Kind == "Dropdown" then
            local Value = Object.value
            if type(Value) == "table" then
                local Names = {}
                for Key, Flag in Value do
                    if type(Key) == "number" then
                        Names[#Names + 1] = tostring(Flag)
                    elseif Flag then
                        Names[#Names + 1] = tostring(Key)
                    end
                end
                table.sort(Names)
                return "{" .. table.concat(Names, ",") .. "}"
            end
            return tostring(Value)
        elseif Kind == "Input" then
            return tostring(Object.text or Object.value or "")
        elseif Kind == "ColorPicker" then
            return tostring(Object.value)
        elseif Kind == "KeyPicker" then
            return tostring(Object.key) .. "/" .. tostring(Object.mode)
        end
        return "?"
    end

    -- writes config objects into the live Toggles / Options (Skip = set of idx to leave alone); returns applied, failed
    local function ApplyObjects(Objects, Skip)
        local Applied, Failed = 0, 0
        for Pass = 1, 2 do   -- options first, then toggles
            for _, Object in Objects do
                local Idx, Kind = Object.idx, Object.type
                if type(Idx) == "string" and not Skipped(Idx) and not Skip[Idx] then
                    local Done, Tried = false, false
                    if Pass == 1 and Kind ~= "Toggle" and Options[Idx] then
                        local Option = Options[Idx]
                        Tried = true
                        if Kind == "Slider" then
                            local Number = tonumber(Object.value)
                            Done = Number ~= nil and pcall(function() Option:SetValue(Number) end)
                        elseif Kind == "Dropdown" then
                            Done = Object.value ~= nil and pcall(function() Option:SetValue(Object.value) end)
                        elseif Kind == "Input" then
                            Done = pcall(function() Option:SetValue(Object.text or Object.value or "") end)
                        elseif Kind == "ColorPicker" then
                            Done = pcall(function() Option:SetValueRGB(Color3.fromHex(Object.value), tonumber(Object.transparency) or 0) end)
                        elseif Kind == "KeyPicker" then
                            Done = pcall(function() Option:SetValue({ Object.key, Object.mode }) end)
                        else
                            Tried = false
                        end
                    elseif Pass == 2 and Kind == "Toggle" and Toggles[Idx] then
                        Tried = true
                        Done = pcall(function() Toggles[Idx]:SetValue(Object.value == true) end)
                    end
                    if Tried then if Done then Applied += 1 else Failed += 1 end end
                end
            end
        end
        return Applied, Failed
    end

    -- Settings = { Skip = {idx = true}, Quiet = bool }. Keeps the state from before the load (Globals.PrevConfig) and the diff.
    local function Apply(Text, Source, Settings)
        Settings = Settings or {}
        local Skip = Settings.Skip or {}
        local Ok, Data = pcall(function() return HttpService:JSONDecode(Text) end)
        if not Ok or type(Data) ~= "table" or type(Data.objects) ~= "table" then
            Functions.Notify({ Title = "File is not a config" })
            return false
        end
        local Before = Collect()
        local Old = {}
        for _, Object in Before do Old[Object.idx] = Describe(Object) end
        local Changes = {}
        for _, Object in Data.objects do
            local Idx = Object.idx
            if type(Idx) == "string" and not Skipped(Idx) and not Skip[Idx] and Old[Idx] ~= nil then
                local New = Describe(Object)
                if New ~= Old[Idx] then Changes[#Changes + 1] = Idx .. ": " .. Old[Idx] .. " -> " .. New end
            end
        end
        Globals.PrevConfig = Before
        Globals.LastDiff = "config diff (" .. #Changes .. " change(s)) from " .. tostring(Source) .. "\n" .. table.concat(Changes, "\n")
        local Applied, Failed = ApplyObjects(Data.objects, Skip)
        Boot.Print("config loaded from " .. tostring(Source) .. ": " .. Applied .. " applied, " .. Failed .. " skipped, " .. #Changes .. " changed")
        if not Settings.Quiet then
            local Shown = {}
            for Index = 1, math.min(8, #Changes) do Shown[Index] = Changes[Index] end
            if #Changes > 8 then Shown[#Shown + 1] = "... +" .. (#Changes - 8) .. " more (Copy last diff)" end
            Functions.Notify({
                Title = "Config loaded: " .. #Changes .. " change(s)",
                Body = #Shown > 0 and table.concat(Shown, "\n") or (Applied .. " applied, " .. Failed .. " skipped"),
                Time = 6,
            })
        end
        return true
    end

    -- the old SaveManager box goes away, ours takes its place
    local SettingsTab = Library.Tabs and Library.Tabs.Settings
    if SettingsTab and SettingsTab.Groupboxes and SettingsTab.Groupboxes.Configuration then
        local Old = SettingsTab.Groupboxes.Configuration
        pcall(function()
            if Old.BoxHolder then Old.BoxHolder:Destroy() elseif Old.Holder then Old.Holder:Destroy() end
        end)
    end
    local Box
    if SettingsTab then Box = SettingsTab:AddRightGroupbox("Configuration") end
    if not Box then Box = Groupboxes.General_Experimental end

    Scan()
    Box:AddLabel("Folder: " .. Dir .. "\nDrop .json configs there.", true)
    Box:AddInput("AMRConfigName", { Text = "Config name", Default = "", Placeholder = "my config", Finished = false })
    Box:AddDropdown("AMRConfigList", { Text = "Configs", Values = Labels, Default = 1, Tooltip = "[old] = found elsewhere in the workspace (e.g. an old config). Loading it also works." })
    local AutoLabel = Box:AddLabel("Autoload: none", true)
    local function AutoName()
        local Ok, Text = pcall(Fn("readfile"), AutoFile)
        if Ok and type(Text) == "string" then
            Text = string.gsub(Text, "^%s*(.-)%s*$", "%1")
            if Text ~= "" then return Text end
        end
        return nil
    end
    local function ShowAuto()
        pcall(function() AutoLabel:SetText("Autoload: " .. (AutoName() or "none")) end)
    end
    local function Refresh(Pick)
        Scan()
        Options.AMRConfigList:SetValues(Labels)
        if Pick and Entries[Pick] then Options.AMRConfigList:SetValue(Pick) end
    end
    local function Selected()
        local Label = Options.AMRConfigList.Value
        return Entries[Label], Label
    end

    Box:AddButton({ Text = "Save Config", Tooltip = "Saves under the typed name, or overwrites the selected one.", Func = function()
        local Name = string.gsub(tostring(Options.AMRConfigName.Value or ""), "[^%w _%-]", "")
        Name = string.gsub(Name, "^%s*(.-)%s*$", "%1")
        if Name == "" then
            local Path, Label = Selected()
            if Path and Label and string.sub(Label, 1, 6) ~= "[old] " then Name = Label end
        end
        if Name == "" then Functions.Notify({ Title = "Type a config name first" }) return end
        local Ok, Text = pcall(function()
            return HttpService:JSONEncode({ name = Name, timestamp = os.date("%d.%m.%Y %H:%M:%S"), objects = Collect() })
        end)
        if not Ok then Functions.Notify({ Title = "Could not encode config" }) return end
        local Wrote = pcall(function() Fn("writefile")(Dir .. "/" .. Name .. ".json", Text) end)
        if Wrote then
            Refresh(Name)
            Functions.Notify({ Title = "Config saved", Body = Name, Time = 3 })
        else
            Functions.Notify({ Title = "Could not write the file" })
        end
    end })
    Box:AddButton({ Text = "Load Config", Func = function()
        local Path = Selected()
        if not Path then Functions.Notify({ Title = "Pick a config first" }) return end
        local Text, Used = Read(Path)
        if not Text then Functions.Notify({ Title = "Can't read the file", Body = Path }) return end
        if Apply(Text, Used) and not string.find(Used, Dir, 1, true) then
            -- keep a copy of an old config in our own folder
            pcall(function()
                local Name = string.match(Used, "([^/]+)$") or "imported.json"
                Fn("writefile")(Dir .. "/" .. Name, Text)
            end)
            Refresh()
        end
    end })
    Box:AddButton({ Text = "Delete Config", DoubleClick = true, Func = function()
        local Path, Label = Selected()
        if not Path or string.sub(Label, 1, 6) == "[old] " or not Fn("delfile") then
            Functions.Notify({ Title = "Only configs in " .. OwnFolder .. " can be deleted" })
            return
        end
        pcall(Fn("delfile"), Path)
        Refresh()
        Functions.Notify({ Title = "Config deleted", Body = Label, Time = 3 })
    end })
    Box:AddButton({ Text = "Refresh List", Func = function()
        Refresh()
        Functions.Notify({ Title = "Found " .. #Labels .. " entr(ies)", Time = 2 })
    end })
    Box:AddButton({ Text = "Set Autoload", Tooltip = "Loads the selected config every time the script starts.", Func = function()
        local Path, Label = Selected()
        if not Path then Functions.Notify({ Title = "Pick a config first" }) return end
        pcall(function() Fn("writefile")(AutoFile, Path) end)
        ShowAuto()
        Functions.Notify({ Title = "Autoload set", Body = Label, Time = 3 })
    end })
    Box:AddButton({ Text = "Clear Autoload", Func = function()
        pcall(function() Fn("writefile")(AutoFile, "") end)
        ShowAuto()
    end })
    ShowAuto()

    Box:AddButton({ Text = "Copy last diff", Tooltip = "Copies what the last loaded config changed.", Func = function()
        if not Globals.LastDiff then Functions.Notify({ Title = "No config loaded yet" }) return end
        local Copy = Fn("setclipboard") or Fn("toclipboard")
        local Done = Copy and pcall(Copy, Globals.LastDiff)
        Functions.Notify({ Title = Done and "Diff copied" or "Clipboard unavailable", Time = 3 })
    end })
    Box:AddButton({ Text = "Rollback last load", DoubleClick = true, Tooltip = "Puts every setting back to what it was before the last config load.", Func = function()
        local Previous = Globals.PrevConfig
        if not Previous then Functions.Notify({ Title = "Nothing to roll back" }) return end
        local Applied, Failed = ApplyObjects(Previous, {})
        Globals.PrevConfig = nil
        Functions.Notify({ Title = "Rolled back", Body = Applied .. " restored, " .. Failed .. " skipped", Time = 4 })
    end })

    -- settings that the autoload leaves alone (kept in their own file, not in configs)
    local SkipMap = {
        ["Fly"] = { "FlyToggle" },
        ["Noclip"] = { "NoclipToggle" },
        ["Third Person"] = { "ThirdPersonToggle" },
        ["Anti Lag"] = { "AntiLag" },
    }
    local SkipLabels = { "Fly", "Noclip", "Third Person", "Anti Lag" }
    local SkipFile = OwnFolder .. "/autoskip.json"
    local SkipDefault = { "Fly", "Noclip", "Third Person", "Anti Lag" }
    pcall(function()
        local Read2, Text = pcall(Fn("readfile"), SkipFile)
        if Read2 and type(Text) == "string" and #Text > 0 then
            local Decoded = HttpService:JSONDecode(Text)
            if type(Decoded) == "table" then
                local Kept = {}
                for _, Label in Decoded do
                    if SkipMap[Label] then Kept[#Kept + 1] = Label end
                end
                SkipDefault = Kept
            end
        end
    end)
    Box:AddDropdown("AutoloadSkip", {
        Text = "Autoload leaves alone", Values = SkipLabels, Default = SkipDefault, Multi = true, AllowNull = true,
        Tooltip = "The autoload config does not touch these toggles."
    })
    Options.AutoloadSkip:OnChanged(function(Value)
        local Chosen = {}
        for Label, Flag in Value do
            if Flag then Chosen[#Chosen + 1] = Label end
        end
        table.sort(Chosen)
        pcall(function() Fn("writefile")(SkipFile, HttpService:JSONEncode(Chosen)) end)
    end)

    Boot.AutoloadConfig = function()
        local Name = AutoName()
        if not Name then return end
        local Text, Used = Read(Name)
        if not Text then Boot.Print("autoload config not found: " .. Name) return end
        local Skip = {}
        local Chosen = Options.AutoloadSkip and Options.AutoloadSkip.Value or {}
        for Label, Flag in Chosen do
            if Flag and SkipMap[Label] then
                for _, Idx in SkipMap[Label] do Skip[Idx] = true end
            end
        end
        Apply(Text, Used, { Skip = Skip, Quiet = true })
    end
end)
if not ConfigOk then Boot.Print("config system failed: " .. tostring(ConfigError)) warn("[AMR] " .. tostring(ConfigError)) end
end

Functions.Notify({ Title = "Successfully loaded in " .. math.floor((tick() - LoadStart) * 1000) / 1000 .. " seconds." , Body = "Press '" .. tostring(Options.MenuKeybind.Value) .. "' to toggle the UI."})

-- auto godmode: Position Spoof (+ Figure Godmode where applicable) on load
task.wait(1)
Toggles.PositionSpoof:SetValue(true)
Toggles.FigureGodmode:SetValue(true)
for _, Name in {"NoScreechDamage", "NoHaltDamage", "NoA90Damage", "NoSurgeDamage", "RemoveCameraFog"} do
    if Toggles[Name] then Toggles[Name]:SetValue(true) end
end
Boot.Print("auto godmode enabled (Position Spoof, Figure Godmode, No Screech/Halt/A-90/Surge Damage, Remove Fog)")
-- the autoload config wins over the defaults above
if Boot.AutoloadConfig then pcall(Boot.AutoloadConfig) end

Boot.Rewrite = false
Boot.Print(string.format("ALL LOADED in %.2fs", tick() - LoadStart))
local CopyFn = setclipboard or toclipboard or (Abysall.Environment and Abysall.Environment.setclipboard)
if CopyFn and pcall(CopyFn, table.concat(Boot.Log, "\n")) then
    print("[AMR] load log copied to clipboard")
else
    print("[AMR] clipboard unavailable, log is in the console above")
end
