-- install.lua - Srunix installer
-- Downloads all system files from GitHub.
-- Usage: wget run https://raw.githubusercontent.com/VVitek8/srunix/main/install.lua

local BASE = "https://raw.githubusercontent.com/VVitek8/srunix/main/"

-- All files: source path on GitHub -> destination on the computer
local FILES = {
    -- Boot
    {"boot/boot.lua", "/boot/boot.lua"},
    {"startup.lua", "/startup.lua"},

    -- Kernel
    {"srunix/kernel/init.lua", "/srunix/kernel/init.lua"},
    {"srunix/kernel/vfs.lua", "/srunix/kernel/vfs.lua"},
    {"srunix/kernel/screen.lua", "/srunix/kernel/screen.lua"},
    {"srunix/kernel/shell.lua", "/srunix/kernel/shell.lua"},
    {"srunix/kernel/users.lua", "/srunix/kernel/users.lua"},
    {"srunix/kernel/utils.lua", "/srunix/kernel/utils.lua"},

    -- Userland commands
    {"srunix/bin/srun.lua", "/srunix/bin/srun.lua"},
    {"srunix/bin/cube.lua", "/srunix/bin/cube.lua"},
    {"srunix/bin/textnum.lua", "/srunix/bin/textnum.lua"},
    {"srunix/bin/morse.lua", "/srunix/bin/morse.lua"},
    {"srunix/bin/about.lua", "/srunix/bin/about.lua"},
    {"srunix/bin/neofetch.lua", "/srunix/bin/neofetch.lua"},
    {"srunix/bin/pic.lua", "/srunix/bin/pic.lua"},

    -- Config
    {"srunix/etc/passwd", "/srunix/etc/passwd"},
    {"srunix/etc/shadow", "/srunix/etc/shadow"},
    {"srunix/etc/group", "/srunix/etc/group"},
    {"srunix/etc/perms", "/srunix/etc/perms"},
    {"srunix/etc/motd", "/srunix/etc/motd"},
}

-- Directories to create
local DIRS = {
    "/boot",
    "/srunix",
    "/srunix/kernel",
    "/srunix/bin",
    "/srunix/etc",
    "/srunix/var",
    "/srunix/var/log",
    "/srunix/home",
    "/srunix/home/root",
    "/srunix/home/guest",
    "/programs",
}

-- Default file contents for configs (in case GitHub files are missing)
local DEFAULTS = {
    ["/srunix/etc/passwd"] = "root:0:0:/srunix/home/root\nguest:1000:1000:/srunix/home/guest\n",
    ["/srunix/etc/shadow"] = "root:\nguest:\n",
    ["/srunix/etc/group"] = "root:0:root\nusers:1000:guest\n",
    ["/srunix/etc/perms"] = "",
    ["/srunix/etc/motd"] = "Welcome to Srunix!\nLinux-like OS for CC:Tweaked.\n",
    ["/startup.lua"] = 'shell.run("/boot/boot")\n',
}

-- Simple HTTP fetch with fallback
local function fetch(url)
    if not http then return nil, "HTTP disabled" end
    local ok, res = pcall(http.get, url)
    if not ok or not res then return nil, "request failed" end
    local data = res.readAll()
    res.close()
    return data
end

local function ensureDir(path)
    if not fs.exists(path) then fs.makeDir(path) end
end

local function writeFile(path, data)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(data)
    f.close()
    return true
end

-- Banner
term.clear()
term.setCursorPos(1, 1)
print("====================================")
print("  Srunix Installer")
print("====================================")
print("")
print("Downloading system files...")
print("")

-- Create directories first
for _, d in ipairs(DIRS) do
    ensureDir(d)
end
print("[OK] directories")

-- Download files
local okCount, failCount = 0, 0
for _, pair in ipairs(FILES) do
    local remote, localPath = pair[1], pair[2]
    local url = BASE .. remote
    write("  " .. remote .. " ... ")
    local data, err = fetch(url)
    if data then
        writeFile(localPath, data)
        print("ok")
        okCount = okCount + 1
    else
        -- Fallback: use default content if available
        local def = DEFAULTS[localPath]
        if def then
            writeFile(localPath, def)
            print("default")
            okCount = okCount + 1
        else
            print("FAIL (" .. tostring(err) .. ")")
            failCount = failCount + 1
        end
    end
end

print("")
print("Downloaded: " .. okCount .. " ok, " .. failCount .. " failed")
print("")

-- Extra: seed log file
if not fs.exists("/srunix/var/log") then fs.makeDir("/srunix/var/log") end
local lf = fs.open("/srunix/var/log/srunix.log", "w")
if lf then
    lf.writeLine("=== Srunix installed ===")
    lf.close()
end

print("====================================")
print("Installation complete!")
print("====================================")
print("")
print("Type 'reboot' to start Srunix.")
