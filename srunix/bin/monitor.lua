local Srunix = _G.Srunix
local SB = Srunix.SB
local args = Srunix.args or {}

local function mk(color)
    return function(...)
        local n = select("#", ...)
        local t = {}
        for i = 1, n do t[i] = tostring(select(i, ...)) end
        SB.addLine(table.concat(t, "\t"), color)
    end
end
local spr     = mk(colors.white)
local sprOk   = mk(colors.lime)
local sprErr  = mk(colors.red)
local sprWarn = mk(colors.yellow)

local sub = (args[1] or "status"):lower()

local function findMonitor()
    local ok, m, side = pcall(peripheral.find, "monitor")
    if ok and m then return m, side end
    return nil, nil
end

if sub == "help" or sub == "?" then
    spr("monitor - manage advanced monitor")
    spr("")
    spr("  monitor status       - show state")
    spr("  monitor attach       - use advanced monitor")
    spr("  monitor detach       - back to computer screen")
    spr("  monitor scale <n>    - text scale (0.5 - 5)")

elseif sub == "status" then
    if Srunix.monitorAttached then
        spr("Monitor: ATTACHED")
    else
        spr("Monitor: not attached (using computer screen)")
    end
    local m, side = findMonitor()
    if m then
        local ok, w, h = pcall(function() return m.getSize() end)
        if ok and w and h then
            spr("Found monitor on side: " .. tostring(side))
            spr("  size: " .. tostring(w) .. "x" .. tostring(h))
        else
            sprWarn("Monitor found but getSize failed.")
        end
    else
        spr("No monitor found on any side.")
        spr("Place an Advanced Monitor next to the computer.")
    end

elseif sub == "attach" then
    if Srunix.monitorAttached then
        spr("Already attached.")
        return
    end
    local m, side = findMonitor()
    if not m then
        sprErr("No monitor connected.")
        return
    end

    -- Save BOTH current terminal and the raw native one.
    local original
    local okOrig = pcall(function() original = term.current() end)
    if not okOrig then
        sprErr("Failed to read current terminal.")
        return
    end
    _G.srunixOriginalTerminal = original
    _G.srunixNativeTerminal = term.native()

    pcall(function() m.setTextScale(0.5) end)

    local rok, rerr = pcall(term.redirect, m)
    if not rok then
        sprErr("Failed to redirect: " .. tostring(rerr))
        return
    end

    Srunix.monitorAttached = true
    Srunix.monitorRef = m

    SB.lines = {}
    SB.scrollOffset = 0
    SB.redraw()

    sprOk("Monitor attached on side: " .. tostring(side))
    spr("All output is now on the monitor.")
    spr("Type 'monitor detach' to go back.")

elseif sub == "detach" then
    if not Srunix.monitorAttached then
        spr("Not attached to any monitor.")
        return
    end

    -- Try original, then native, then nothing.
    local restored = false
    if _G.srunixOriginalTerminal then
        local ok = pcall(term.redirect, _G.srunixOriginalTerminal)
        if ok then restored = true end
    end
    if not restored and _G.srunixNativeTerminal then
        local ok = pcall(term.redirect, _G.srunixNativeTerminal)
        if ok then restored = true end
    end
    if not restored then
        local ok = pcall(term.redirect, term.native())
        restored = ok
    end

    Srunix.monitorAttached = false
    Srunix.monitorRef = nil

    if not restored then
        sprErr("Could not restore terminal. Try 'reboot'.")
        return
    end

    SB.lines = {}
    SB.scrollOffset = 0
    SB.redraw()

    sprOk("Monitor detached. Back on computer screen.")

elseif sub == "scale" then
    local s = tonumber(args[2])
    if not s then
        spr("usage: monitor scale <0.5|1|2|3|4|5>")
        return
    end
    if s < 0.5 then s = 0.5 end
    if s > 5 then s = 5 end
    local m = Srunix.monitorRef
    if not m then m = findMonitor() end
    if not m then
        sprErr("No monitor connected.")
        return
    end
    local ok = pcall(function() m.setTextScale(s) end)
    if not ok then
        sprErr("Failed to set scale.")
        return
    end
    SB.redraw()
    sprOk("Scale set to " .. s)

else
    spr("usage:")
    spr("  monitor status  - show state")
    spr("  monitor attach  - use advanced monitor")
    spr("  monitor detach  - back to computer screen")
    spr("  monitor scale <n> - text scale (0.5 - 5)")
    spr("")
    spr("Type 'monitor help' for more info.")
end
