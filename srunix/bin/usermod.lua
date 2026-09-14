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
    spr("usermod: permission denied (root only)")
    return
end

local groups = {}
local username = nil
local i = 1
while i <= #args do
    local a = args[i]
    if a == "-aG" or a == "-aG" then
        i = i + 1
        if args[i] then table.insert(groups, args[i]) end
    elseif a:match("^%-aG") then
        table.insert(groups, a:sub(4))
    elseif a:sub(1,1) ~= "-" then
        username = a
    end
    i = i + 1
end

if not username or #groups == 0 then
    spr("usage: usermod -aG <group> <user>")
    return
end

local users = Users.loadUsers()
if not users[username] then
    spr("usermod: no such user: " .. username)
    return
end

local f = fs.open("/srunix/etc/group", "r")
local data = f.readAll()
f.close()

local lines = {}
local changed = false
for line in (data .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
        local gname, gid, members = line:match("^([^:]+):(%d+):(.*)$")
        if gname then
            for _, target in ipairs(groups) do
                if gname == target then
                    local already = false
                    for m in members:gmatch("[^,]+") do
                        if m == username then already = true end
                    end
                    if not already then
                        if members == "" then members = username
                        else members = members .. "," .. username end
                        changed = true
                    end
                end
            end
            table.insert(lines, string.format("%s:%s:%s", gname, gid, members))
        else
            table.insert(lines, line)
        end
    end
end

if changed then
    local out = fs.open("/srunix/etc/group", "w")
    out.write(table.concat(lines, "\n") .. "\n")
    out.close()
    spr("Added " .. username .. " to group(s): " .. table.concat(groups, ", "))
else
    spr("No changes made (user may already be in these groups)")
end
