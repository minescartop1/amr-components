-- Info tab (rebuilt from dump). Credits kept as in the original.
local fenv = getfenv()

return function(Tab)
    local Library = fenv.Abysall.Interface.Library
    local Env = fenv.Abysall.Environment
    local Players = game:GetService("Players")
    local LocalPlayer = Env.cloneref(Players).LocalPlayer

    local Info = Tab:AddTab("Info", "user")

    local User = Info:AddLeftGroupbox("User Info")
    pcall(function()
        User:AddImage("UserIcon", {
            Image = Env.cloneref(Players):GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420),
        })
    end)
    User:AddLabel("ID: " .. LocalPlayer.Name, true)
    User:AddLabel("Total Executions: " .. tostring(fenv.Abysall.TotalExecutions or 0), true)

    local Credits = Info:AddRightGroupbox("Credits")
    Credits:AddLabel("<font color='rgb(0, 255, 255)'>CookieMonster — Owner of the Continued Script</font>", true)
    Credits:AddLabel("<font color='rgb(255, 165, 0)'>FireBacon — Owner of the Discontinued Script</font>", true)
    Credits:AddLabel("<font color='rgb(197, 63, 132)'>Rhyan57 — Provided the Infinite Crucifix</font>", true)
    Credits:AddLabel("<font color='rgb(241, 106, 212)'>Abbas - Basicly a developer</font>", true)
    Credits:AddLabel("<font color='rgb(120, 200, 255)'>den4ik_top_off - Theme creator</font>", true)
    Credits:AddLabel("<font color='rgb(120, 200, 255)'>sasanixx - Theme creator</font>", true)
    Credits:AddLabel("<font color='rgb(50, 205, 50)'>" .. LocalPlayer.Name .. " — For Using This Script</font>", true)

    local Changelog = Info:AddRightGroupbox("Changelog")
    Changelog:AddLabel("<font color='rgb(255, 255, 0)'>~ Updated Sally notification message</font>", true)
    Changelog:AddLabel("<font color='rgb(255, 255, 0)'>~ Expanded ItemNames & Entities lists</font>", true)
    Changelog:AddLabel("<font color='rgb(255, 255, 0)'>~ Forgot to add supporter list so i could add it later</font>", true)
    Changelog:AddLabel("<font color='rgb(255, 0, 0)'>- Removed FireBacon</font>", true)

    local Exec = Info:AddRightGroupbox("Executor Info")
    Exec:AddLabel("Name: " .. Env.identifyexecutor(), true)
    Exec:AddLabel("Version: N/A", true)
    Exec:AddDivider()
    Exec:AddLabel("Test Result: ", true)
    for _, Result in pairs(Env.Results) do
        Exec:AddLabel((Result:gsub("<", "("):gsub(">", ")")), true)
    end

    local Scripts = Info:AddLeftGroupbox("Scripts")
    Scripts:AddButton("InfiniteYield", {
        Text = "Infinite Yield",
        Tooltip = "Runs infinite yield.",
        Func = function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
        end,
    })
    Scripts:AddButton("Dex", {
        Text = "Dex",
        Tooltip = "Runs Dex.",
        Func = function()
            Library:Notify("Please wait.")
            loadstring(game:HttpGet("https://github.com/AZYsGithub/DexPlusPlus/releases/latest/download/out.lua"))()
        end,
    })

    Info:AddLeftGroupbox("Community"):AddButton("Copy Discord Invite", function()
        fenv.toclipboard("https://discord.gg/an2h2MXED")
        Library:Notify("Discord invite copied.")
    end)
end
