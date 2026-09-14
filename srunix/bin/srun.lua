local Srunix = _G.Srunix
local SB = Srunix.SB
local Utils = Srunix.Utils
local args = Srunix.args or {}
local raw = args[1]

local function sprc(color, ...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring(select(i, ...)) end
    SB.addLine(table.concat(parts, "\t"), color)
end

if not raw then
    SB.addSegments({{text = "SRUN", color = Utils.randomColor()}})
    return
end

local n = tonumber(raw)
if not n then
    n = Utils.textToNumber(raw)
    if n > 0 then
        sprc(colors.cyan, "srun: '" .. raw .. "' -> " .. n)
    else
        sprc(colors.red, "srun: '" .. raw .. "' ne chislo i ne bukvy")
        return
    end
end

if n < 1 then
    sprc(colors.red, "srun: number must be at least 1")
elseif n > 1000 then
    sprc(colors.red, "srun: number too large (max 1000)")
else
    local width = SB.textWidth()
    local itemLen = 5
    local perLine = math.floor(width / itemLen)
    if perLine < 1 then perLine = 1 end

    local lineSegs = {}
    local count = 0
    for i = 1, n do
        local col = Utils.randomColor()
        local txt = (i < n) and "SRUN " or "SRUN"
        table.insert(lineSegs, {text = txt, color = col})
        count = count + 1
        if count >= perLine or i == n then
            SB.addSegments(lineSegs)
            lineSegs = {}
            count = 0
        end
    end
end
