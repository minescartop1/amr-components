-- Settings tab (rebuilt from dump). No title/anti-reupload check, no kick.
local fenv = getfenv()
local GistMain = "https://gist.githubusercontent.com/minescartop1/8ce36218105a35db0bf47c064009f470/raw/Main.luau"

return function(Tab)
    local Library = fenv.Abysall.Interface.Library
    local Env = fenv.Abysall.Environment
    local Players = game:GetService("Players")

    local Settings = Tab:AddTab("Settings", "settings")
    local Menu = Settings:AddLeftGroupbox("Menu")

    Menu:AddToggle("KeybindMenuOpen", {
        Text = "Open Keybind Menu",
        Default = Library.KeybindFrame.Visible,
        Callback = function(Value)
            Library.KeybindFrame.Visible = Value
        end,
    })

    Menu:AddToggle("ShowCustomCursor", {
        Text = "Custom Cursor",
        Default = false,
        Callback = function(Value)
            Library.ShowCustomCursor = Value
        end,
    })

    Menu:AddToggle("QueueOnTeleport", {
        Text = "Queue On Teleport",
        Default = false,
        Tooltip = "Automatically loads the script when you teleport to another server.",
        Callback = function()
            local Queue = queue_on_teleport or (syn and syn.queue_on_teleport)
            if Queue then
                Queue('loadstring(game:HttpGet("' .. GistMain .. '"))()')
            end
        end,
    })

    Menu:AddDropdown("UILibrary", {
        Text = "UI Style",
        Values = { "Obsidian", "Linoria" },
        Default = 1,
        Callback = function(Value)
            pcall(function()
                local HttpService = Env.cloneref(game:GetService("HttpService"))
                if not Env.isfile("Abysall/UserData.json") then return end
                local Data = HttpService:JSONDecode(Env.readfile("Abysall/UserData.json"))
                Data.UILibrary = Value
                fenv.Abysall.TotalExecutions = Data.TotalExecutions
                fenv.Abysall.UILibrary = Value
                Env.writefile("Abysall/UserData.json", HttpService:JSONEncode(Data))
            end)
        end,
    })

    Menu:AddDropdown("DPIDropdown", {
        Text = "DPI Scale",
        Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
        Default = "100%",
        Callback = function(Value)
            Library:SetDPIScale(tonumber((Value:gsub("%%", ""))))
        end,
    })

    Menu:AddDivider()
    Menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
        NoUI = true,
        Default = "RightShift",
        Text = "Menu keybind",
    })

    Menu:AddButton("Copy Discord Invite", function()
        fenv.toclipboard("https://discord.gg/an2h2MXED")
        Library:Notify("Discord invite copied.")
    end)

    Menu:AddButton("Unload", function()
        Library:Unload()
    end)

    -- reloads OUR gist, not the authors' script
    Menu:AddButton("Reload", function()
        Library:Unload()
        task.wait(0.5)
        loadstring(game:HttpGet(GistMain))()
    end)
end
