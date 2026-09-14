local Users = {}

-- Simple password hash (NOT cryptographically secure, just for game)
local function hashPass(pass)
    local h = 5381
    for i = 1, #pass do
        h = (h * 33 + pass:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

Users.hashPass = hashPass

-- Reads a file from real fs (no permission checks - internal use)
local function realRead(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local d = f.readAll()
    f.close()
    return d
end

local function realWrite(path, data)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(data)
    f.close()
    return true
end

local function splitLines(text)
    local t = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            table.insert(t, line)
        end
    end
    return t
end

-- ---- USERS ----
function Users.loadUsers()
    local users = {}
    local data = realRead("/srunix/etc/passwd")
    if not data then return users end
    for _, line in ipairs(splitLines(data)) do
        local name, uid, gid, home = line:match("^([^:]+):(%d+):(%d+):([^:]+)$")
        if name then
            users[name] = {
                name = name,
                uid = tonumber(uid),
                gid = tonumber(gid),
                home = home,
            }
        end
    end
    return users
end

function Users.loadShadow()
    local shadow = {}
    local data = realRead("/srunix/etc/shadow")
    if not data then return shadow end
    for _, line in ipairs(splitLines(data)) do
        local name, hash = line:match("^([^:]+):(.*)$")
        if name then
            shadow[name] = hash
        end
    end
    return shadow
end

function Users.loadGroups()
    local groups = {}
    local data = realRead("/srunix/etc/group")
    if not data then return groups end
    for _, line in ipairs(splitLines(data)) do
        local name, gid, members = line:match("^([^:]+):(%d+):(.*)$")
        if name then
            local m = {}
            for member in (members or ""):gmatch("[^,]+") do
                table.insert(m, member)
            end
            groups[name] = {
                name = name,
                gid = tonumber(gid),
                members = m,
            }
        end
    end
    return groups
end

-- ---- PERMISSIONS ----
function Users.loadPerms()
    local perms = {}
    local data = realRead("/srunix/etc/perms")
    if not data then return perms end
    for _, line in ipairs(splitLines(data)) do
        local path, owner, group, mode = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
        if path then
            perms[path] = {
                owner = owner,
                group = group,
                mode = tonumber(mode, 8) or 0,
            }
        end
    end
    return perms
end

function Users.savePerms(perms)
    local lines = {}
    for path, p in pairs(perms) do
        table.insert(lines, string.format("%s %s %s %o", path, p.owner, p.group, p.mode))
    end
    table.sort(lines)
    realWrite("/srunix/etc/perms", table.concat(lines, "\n") .. "\n")
end

-- ---- AUTH ----
function Users.authenticate(username, password)
    local shadow = Users.loadShadow()
    local users = Users.loadUsers()
    if not users[username] then return false end
    local stored = shadow[username]
    if stored == nil then return false end
    if stored == "" then return true end -- empty hash = no password
    return stored == hashPass(password)
end

-- ---- CURRENT USER ----
function Users.setCurrent(username)
    local users = Users.loadUsers()
    local u = users[username]
    if not u then return false end
    local Srunix = _G.Srunix
    Srunix.user = u.name
    Srunix.uid = u.uid
    Srunix.gid = u.gid
    Srunix.home = u.home
    Srunix.cwd = "C:\\" .. u.home:sub(2):gsub("/", "\\")
    if Srunix.cwd:sub(-1) ~= "\\" then Srunix.cwd = Srunix.cwd .. "\\" end
    return true
end

function Users.inGroup(username, groupname)
    local groups = Users.loadGroups()
    local g = groups[groupname]
    if not g then return false end
    for _, m in ipairs(g.members) do
        if m == username then return true end
    end
    return false
end

-- ---- PERMISSION CHECK ----
-- action: "r" | "w" | "x"
function Users.canAccess(username, uid, realpath, action)
    if uid == 0 then return true end -- root bypasses

    local perms = Users.loadPerms()
    local entry = perms[realpath]

    -- If no entry, default: 755 for dirs, 644 for files
    if not entry then
        if fs.isDir(realpath) then
            entry = {owner = "root", group = "root", mode = tonumber("755", 8)}
        else
            entry = {owner = "root", group = "root", mode = tonumber("644", 8)}
        end
    end

    local perm
    if username == entry.owner then
        perm = math.floor(entry.mode / 64) % 8
    elseif Users.inGroup(username, entry.group) then
        perm = math.floor(entry.mode / 8) % 8
    else
        perm = entry.mode % 8
    end

    if action == "r" then return perm >= 4
    elseif action == "w" then return perm == 2 or perm == 3 or perm == 6 or perm == 7
    elseif action == "x" then return perm % 2 == 1
    end
    return false
end

function Users.getPerms(realpath)
    local perms = Users.loadPerms()
    return perms[realpath]
end

function Users.setPerms(realpath, owner, group, mode)
    local perms = Users.loadPerms()
    perms[realpath] = {owner = owner, group = group, mode = mode}
    Users.savePerms(perms)
end

function Users.deletePerms(realpath)
    local perms = Users.loadPerms()
    perms[realpath] = nil
    Users.savePerms(perms)
end

-- ---- USER MANAGEMENT ----
function Users.addUser(name, uid, gid, home)
    local users = Users.loadUsers()
    if users[name] then return false, "user exists" end

    -- Append to passwd
    local data = realRead("/srunix/etc/passwd") or ""
    if data ~= "" and data:sub(-1) ~= "\n" then data = data .. "\n" end
    data = data .. string.format("%s:%d:%d:%s\n", name, uid, gid, home)
    realWrite("/srunix/etc/passwd", data)

    -- Append to shadow with empty password
    local sh = realRead("/srunix/etc/shadow") or ""
    if sh ~= "" and sh:sub(-1) ~= "\n" then sh = sh .. "\n" end
    sh = sh .. name .. ":\n"
    realWrite("/srunix/etc/shadow", sh)

    -- Append to group "users"
    local gr = realRead("/srunix/etc/group") or ""
    local newgr = {}
    local found = false
    for line in (gr .. "\n"):gmatch("([^\n]*)\n") do
        local gname, ggid, members = line:match("^([^:]+):(%d+):(.*)$")
        if gname == "users" then
            if members == "" then members = name else members = members .. "," .. name end
            table.insert(newgr, string.format("%s:%s:%s", gname, ggid, members))
            found = true
        elseif line ~= "" then
            table.insert(newgr, line)
        end
    end
    if not found then
        table.insert(newgr, string.format("users:%d:%s", gid, name))
    end
    realWrite("/srunix/etc/group", table.concat(newgr, "\n") .. "\n")

    -- Create home dir
    if not fs.exists(home) then fs.makeDir(home) end
    Users.setPerms(home, name, "users", tonumber("700", 8))

    return true
end

function Users.deleteUser(name)
    if name == "root" then return false, "cannot delete root" end
    local users = Users.loadUsers()
    if not users[name] then return false, "no such user" end

    local lines = {}
    for line in (realRead("/srunix/etc/passwd") .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" and not line:match("^" .. name .. ":") then
            table.insert(lines, line)
        end
    end
    realWrite("/srunix/etc/passwd", table.concat(lines, "\n") .. "\n")

    local shlines = {}
    for line in (realRead("/srunix/etc/shadow") .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" and not line:match("^" .. name .. ":") then
            table.insert(shlines, line)
        end
    end
    realWrite("/srunix/etc/shadow", table.concat(shlines, "\n") .. "\n")

    -- Remove from groups
    local newgr = {}
    for line in (realRead("/srunix/etc/group") .. "\n"):gmatch("([^\n]*)\n") do
        local gname, ggid, members = line:match("^([^:]+):(%d+):(.*)$")
        if gname then
            local newm = {}
            for m in members:gmatch("[^,]+") do
                if m ~= name then table.insert(newm, m) end
            end
            table.insert(newgr, string.format("%s:%s:%s", gname, ggid, table.concat(newm, ",")))
        elseif line ~= "" then
            table.insert(newgr, line)
        end
    end
    realWrite("/srunix/etc/group", table.concat(newgr, "\n") .. "\n")

    return true
end

function Users.setPassword(name, password)
    local lines = {}
    local found = false
    for line in (realRead("/srunix/etc/shadow") .. "\n"):gmatch("([^\n]*)\n") do
        local uname = line:match("^([^:]+):")
        if uname == name then
            table.insert(lines, name .. ":" .. hashPass(password))
            found = true
        elseif line ~= "" then
            table.insert(lines, line)
        end
    end
    if not found then
        table.insert(lines, name .. ":" .. hashPass(password))
    end
    realWrite("/srunix/etc/shadow", table.concat(lines, "\n") .. "\n")
    return true
end

function Users.listUsers()
    local users = Users.loadUsers()
    local names = {}
    for n, _ in pairs(users) do table.insert(names, n) end
    table.sort(names)
    return names, users
end

return Users
