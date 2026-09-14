local Srunix = _G.Srunix
local SB = Srunix.SB
local Users = Srunix.Users

local function spr(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring(select(i, ...)) end
    SB.addLine(table.concat(parts, "\t"))
end

local function readLine(prompt, isPass)
    local buf = ""
    SB.pendingInput = prompt
    SB.redraw()
    pcall(term.setCursorBlink, true)
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "key" then
            if p1 == keys.enter then
                SB.pendingInput = ""
                return buf
            elseif p1 == keys.backspace then
                if #buf > 0 then buf = buf:sub(1, -2) end
            end
        elseif ev == "char" then
            buf = buf .. p1
        elseif ev == "paste" then
            buf = buf .. p1
        elseif ev == "mouse_scroll" then
            SB.handleScroll(p1)
        end
        local shown = isPass and string.rep("*", #buf) or buf
        SB.pendingInput = prompt .. shown
        term.setCursorPos(1, select(2, term.getSize()))
        term.clearLine()
        term.write(SB.pendingInput)
    end
end

spr("=== Add user wizard ===")
spr("")

local name = readLine("Username: ")
if not name or name == "" then spr("Cancelled.") return end
if not name:match("^[%w_%-]+$") then
    spr("Invalid name (use letters, digits, _ or -)")
    return
end

local _, info = Users.listUsers()
if info[name] then
    spr("User '" .. name .. "' already exists.")
    return
end

local ans = readLine("Make root (uid 0)? [y/N]: "):lower()
local uid
local gid
if ans == "y" or ans == "yes" then
    uid = 0
    gid = 0
else
    local maxuid = 999
    for _, u in pairs(info) do
        if u.uid > maxuid then maxuid = u.uid end
    end
    uid = maxuid + 1
    gid = 1000
end

local p1 = readLine("Password (empty = none): ", true)
local p2 = readLine("Repeat: ", true)
if p1 ~= p2 then
    spr("Passwords do not match.")
    return
end

local home = "/srunix/home/" .. name

local ok, err = Users.addUser(name, uid, gid, home)
if not ok then
    spr("Error: " .. tostring(err))
    return
end

if p1 ~= "" then
    Users.setPassword(name, p1)
end

if not fs.exists(home) then
    fs.makeDir(home)
end
Users.setPerms(home, name, uid == 0 and "root" or "users", tonumber("700", 8))

spr("")
spr("User created successfully!")
spr("  name:  " .. name)
spr("  uid:   " .. uid)
spr("  gid:   " .. gid)
spr("  home:  " .. home)
if uid == 0 then
    spr("  *** ROOT PRIVILEGES ***")
end
spr("")
spr("Use 'login " .. name .. "' to switch.")
