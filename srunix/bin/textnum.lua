local Srunix = Srunix
local SB = Srunix.SB
local args = Srunix.args or {}
local word = args[1]

local function spr(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring(select(i, ...))
    end
    SB.addLine(table.concat(parts, "\t"))
end

if not word then
    spr("usage: textnum <word>")
    return
end

local sum = 0
local parts = {}
local ok = false
for i = 1, #word do
    local c = word:sub(i, i):upper()
    local code = c:byte()
    if code >= 65 and code <= 90 then
        sum = sum + (code - 64)
        table.insert(parts, tostring(code - 64))
        ok = true
    end
end

if not ok then
    spr("textnum: '" .. word .. "' has no A-Z letters")
else
    spr(word:upper() .. " = " .. table.concat(parts, "+") .. " = " .. sum)
end
