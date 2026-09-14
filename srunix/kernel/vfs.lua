local VFS = {}

VFS.mounts = {
    ["C:"] = "/",
    ["SYS:"] = "/srunix",
}

function VFS.parse(vpath)
    local Srunix = _G.Srunix
    if not vpath or vpath == "" then vpath = Srunix.cwd end
    vpath = vpath:gsub("/", "\\")
    local drive
    if vpath:match("^%a:") then
        drive = vpath:sub(1, 2)
        vpath = vpath:sub(3)
    else
        drive = Srunix.cwd:sub(1, 2)
        if vpath:sub(1, 1) ~= "\\" then
            local cwd_rest = Srunix.cwd:sub(3)
            if cwd_rest:sub(-1) ~= "\\" then cwd_rest = cwd_rest .. "\\" end
            vpath = cwd_rest .. vpath
        end
    end
    local parts = {}
    for part in vpath:gmatch("[^\\]+") do
        if part == ".." then
            table.remove(parts)
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end
    return drive, parts
end

function VFS.realpath(vpath)
    local drive, parts = VFS.parse(vpath)
    local mount = VFS.mounts[drive] or "/"
    local real = mount
    for _, p in ipairs(parts) do
        if real:sub(-1) == "/" then
            real = real .. p
        else
            real = real .. "/" .. p
        end
    end
    return real
end

local function check(path, action)
    local Srunix = _G.Srunix
    local Users = Srunix.Users
    if not Users then return true end -- perms not loaded yet
    return Users.canAccess(Srunix.user, Srunix.uid, path, action)
end

function VFS.exists(vpath) return fs.exists(VFS.realpath(vpath)) end
function VFS.isDir(vpath) return fs.isDir(VFS.realpath(vpath)) end

function VFS.list(vpath)
    local real = VFS.realpath(vpath)
    if not fs.isDir(real) then return {} end
    if not check(real, "r") then return {} end
    return fs.list(real)
end

function VFS.read(vpath)
    local real = VFS.realpath(vpath)
    if not fs.exists(real) or fs.isDir(real) then return nil end
    if not check(real, "r") then return nil end
    local f = fs.open(real, "r")
    if not f then return nil end
    local d = f.readAll()
    f.close()
    return d
end

function VFS.write(vpath, data)
    local real = VFS.realpath(vpath)
    local parent = real:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
    if fs.exists(real) then
        if not check(real, "w") then return false end
    else
        if parent and parent ~= "" and not check(parent, "w") then return false end
    end
    local f = fs.open(real, "w")
    if not f then return false end
    f.write(data)
    f.close()
    return true
end

function VFS.delete(vpath)
    local real = VFS.realpath(vpath)
    if not fs.exists(real) then return false end
    local parent = real:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and not check(parent, "w") then return false end
    fs.delete(real)
    return true
end

function VFS.mkdir(vpath)
    local real = VFS.realpath(vpath)
    if fs.exists(real) then return true end
    local parent = real:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and not check(parent, "w") then return false end
    fs.makeDir(real)
    return true
end

return VFS
