local Srunix = _G.Srunix
local SB = Srunix.SB
local function col(c) return Srunix.colorOverride or c end
local function spr(...) local t={} for i=1,select("#",...) do t[i]=tostring(select(i,...)) end SB.addLine(table.concat(t,"\t"), col(colors.white)) end
local function sprc(c,...) local t={} for i=1,select("#",...) do t[i]=tostring(select(i,...)) end SB.addLine(table.concat(t,"\t"), col(c)) end

-- ASCII-арт SRUNIX
local art = {
"███████╗██████╗ ██╗   ██╗███╗   ██╗██╗██╗  ██╗",
"██╔════╝██╔══██╗██║   ██║████╗  ██║██║╚██╗██╔╝",
"███████╗██████╔╝██║   ██║██╔██╗ ██║██║ ╚███╔╝ ",
"╚════██║██╔══██╗██║   ██║██║╚██╗██║██║ ██╔██╗ ",
"███████║██║  ██║╚██████╔╝██║ ╚████║██║██╔╝ ██╗",
"╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝",
}

for _, line in ipairs(art) do
    sprc(colors.red, line)
end
spr("")

local host = os.getComputerLabel() or ("computer #" .. os.getComputerID())
local free = fs.getFreeSpace("/") or 0
local used = 0
local function walk(p, d)
    if d > 5 then return end
    local ok, list = pcall(fs.list, p)
    if not ok then return end
    for _, n in ipairs(list) do
        local full = p.."/"..n
        if fs.isDir(full) then walk(full, d+1)
        else
            local ok2, s = pcall(fs.getSize, full)
            if ok2 then used = used + s end
        end
    end
end
walk("/srunix", 1)

sprc(colors.cyan, "  OS:        Srunix 0.5.0")
sprc(colors.cyan, "  Kernel:      Srunixkernel0.5.0")
sprc(colors.cyan, "  Host:      " .. host)
sprc(colors.cyan, "  User: " .. (Srunix.user or "root"))
sprc(colors.cyan, "  Disk:      " .. math.floor(used/1024) .. " KB used / " .. math.floor(free/1024) .. " KB free.")
sprc(colors.cyan, "  Display:     " .. term.getSize() .. " (text)")
sprc(colors.cyan, "  Graphics:   " .. (term.setGraphicsMode and "CC:Graphics (256 colors)" or "missing"))
sprc(colors.cyan, "  GPU:       " .. (peripheral.find("tm_gpu") and "Tom's Peripherals" or "missing"))
sprc(colors.cyan, "  Rednet:    " .. (rednet.isOpen() and "открыт" or "закрыт"))
