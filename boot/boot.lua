term.clear()
term.setCursorPos(1, 1)
print("====================================")
print("  Srunix Bootloader v2.0")
print("====================================")
print("")
print("[boot] Initializing hardware...")
sleep(0.2)
print("[boot] Mounting C: at /")
sleep(0.1)
print("[boot] Mounting SYS: at /srunix")
sleep(0.1)
print("[boot] Loading kernel...")
sleep(0.2)
print("")

local ok, err = pcall(dofile, "/srunix/kernel/init.lua")

if not ok then
    print("")
    print("[boot] KERNEL PANIC")
    print("[boot] " .. tostring(err))
    print("[boot] System halted.")
end

-- SRUNIX_CHECKSUM: защита startup.lua
local ok, startup = pcall(fs.open, "/startup.lua", "r")
if ok and startup then
    local content = startup.readAll()
    startup.close()
    local expected = 'shell.run("/boot/boot")'
    if not content:find(expected, 1, true) then
        term.setTextColor(colors.red)
        print("")
        print("!!! WARNING: startup.lua MODIFIED !!!")
        print("Expected: " .. expected)
        print("Found: " .. content:sub(1, 60))
        print("")
        print("Press R to restore or any other key to continue.")
        local ev = os.pullEvent("key")
        if ev == "key" and select(2, os.pullEvent()) == keys.r then
            local f = fs.open("/startup.lua", "w")
            f.write(expected)
            f.close()
            print("startup.lua restored.")
        end
    end
end
