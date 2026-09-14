local M = {}

function M.textToNumber(str)
    local sum = 0
    for i = 1, #str do
        local c = str:sub(i, i):upper()
        local code = c:byte()
        if code >= 65 and code <= 90 then
            sum = sum + (code - 64)
        end
    end
    return sum
end

function M.argToNumber(str)
    if not str then return nil end
    local n = tonumber(str)
    if n then return n end
    local sum = M.textToNumber(str)
    if sum > 0 then return sum end
    return nil
end

M.colorNames = {
    white = colors.white, orange = colors.orange, magenta = colors.magenta,
    lightblue = colors.lightBlue, yellow = colors.yellow, lime = colors.lime,
    pink = colors.pink, gray = colors.gray, lightgray = colors.lightGray,
    cyan = colors.cyan, purple = colors.purple, blue = colors.blue,
    brown = colors.brown, green = colors.green, red = colors.red,
    black = colors.black,
}

M.colorOrder = {
    "white", "orange", "magenta", "lightblue", "yellow", "lime",
    "pink", "gray", "lightgray", "cyan", "purple", "blue",
    "brown", "green", "red", "black",
}

M.randomPalette = {
    colors.white, colors.orange, colors.magenta, colors.lightBlue,
    colors.yellow, colors.lime, colors.pink, colors.gray,
    colors.lightGray, colors.cyan, colors.purple, colors.blue,
    colors.brown, colors.green, colors.red,
}

function M.randomColor()
    return M.randomPalette[math.random(1, #M.randomPalette)]
end

M.logLevels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 }
M.logLevelNames = { [1] = "ERROR", [2] = "WARN", [3] = "INFO", [4] = "DEBUG" }
M.currentLogLevel = 3

-- Copy text to clipboard: native if available, else file.
function M.copyToClipboard(text)
    if type(setClipboard) == "function" then
        local ok = pcall(setClipboard, text)
        if ok then return "clipboard" end
    end
    if not fs.exists("/srunix") then fs.makeDir("/srunix") end
    local f = fs.open("/srunix/clipboard.txt", "w")
    if f then
        f.write(text)
        f.close()
        return "file"
    end
    return nil
end

return M