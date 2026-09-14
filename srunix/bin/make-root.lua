local Srunix = _G.Srunix
local SB = Srunix.SB
local Users = Srunix.Users
local args = Srunix.args or {}

local function spr(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring(select(i, ...)) end
    SB.addLine(table.concat(parts, "\t"))
end

if Srunix.uid ~= 0 then
    spr("make-root: permission denied (root only)")
    return
end

local name = args[1]
if not name then
    spr("usage: make-root <username>")
    return
end

local users = Users.loadUsers()
if not users[name] then
    spr("make-root: no such user: " .. name)
    return
end

-- Rewrite passwd, setting uid=0 gid=0 for that user
local f = fs.open("/srunix/etc/passwd", "r")
local data = f.readAll()
f.close()

local lines = {}
local found = false
for line in (data .. "\n"):gmatch("([^\n]*)\n") do
    local uname, uid, gid, home = line:match("^([^:]+):(%d+):(%d+):([^:]+)$")
    if uname == name then
        table.insert(lines, name .. ":0:0:" .. home)
        found = true
    elseif line ~= "" then
        table.insert(lines, line)
    end
end

if not found then
    spr("make-root: user not found in passwd")
    return
end

f = fs.open("/srunix/etc/passwd", "w")
f.write(table.concat(lines, "\n") .. "\n")
f.close()

-- Add to root group
f = fs.open("/srunix/etc/group", "r")
data = f.readAll()
f.close()

lines = {}
local added = false
for line in (data .. "\n"):gmatch("([^\n]*)\n") do
    local gname, gid, members = line:match("^([^:]+):(%d+):(.*)$")
    if gname == "root" then
        local already = false
        for m in members:gmatch("[^,]+") do
            if m == name then already = true end
        end
        if not already then
            if members == "" then members = name
            else members = members .. "," .. name end
            added = true
        end
        table.insert(lines, "root:0:" .. members)
    elseif gname then
        table.insert(lines, gname .. ":" .. gid .. ":" .. members)
    elseif line ~= "" then
        table.insert(lines, line)
    end
end

f = fs.open("/srunix/etc/group", "w")
f.write(table.concat(lines, "\n") .. "\n")
f.close()

-- Fix home dir perms
local home = users[name].home
if home and fs.exists(home) then
    Users.setPerms(home, name, "root", tonumber("700", 8))
end

spr("User " .. name .. " is now root (uid=0, gid=0).")
spr("Added to group 'root'.")
spr("")
spr("To apply: logout then login " .. name)
