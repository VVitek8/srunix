local SB = {
    colorOverride = nil,
    lines = {},
    pendingInput = "",
    pendingPrompt = "",
    pendingPromptColor = nil,
    pendingInputColor = nil,
    pendingSuggestion = "",
    scrollOffset = 0,
    selection = {
        active = false,
        startLine = nil, startCol = nil,
        endLine = nil,   endCol = nil,
    },
}

-- Log every line that appears on screen.
-- Only writes if global srunixLog exists (shell defines it).
local __logBuf = {}
local __logTimer = nil
local function logToFile(text)
    if not _G.srunixLog then return end
    text = tostring(text or "")
    if text == "" then return end
    -- Batch: append to buffer, flush every ~20 lines or on timer
    __logBuf[#__logBuf+1] = text
    if #__logBuf >= 20 then
        local joined = table.concat(__logBuf, "\n")
        __logBuf = {}
        pcall(_G.srunixLog, "SCR", joined)
    else
        if not __logTimer then
            __logTimer = os.startTimer(0.3)
        end
    end
end

local function flushLog()
    if #__logBuf > 0 then
        local joined = table.concat(__logBuf, "\n")
        __logBuf = {}
        pcall(_G.srunixLog, "SCR", joined)
    end
    __logTimer = nil
end

function SB.textWidth()
    local w = term.getSize()
    return w - 1
end
function SB.viewHeight()
    local _, h = term.getSize()
    return h - 1
end
function SB.init()
    SB.lines = {}
    SB.pendingInput = ""
    SB.pendingPrompt = ""
    SB.pendingPromptColor = nil
    SB.pendingInputColor = nil
    SB.pendingSuggestion = ""
    SB.scrollOffset = 0
    SB.selection.active = false
end

-- === selection helpers ===
local function normSelection()
    local a1 = SB.selection.startLine
    local b1 = SB.selection.endLine
    local a2 = SB.selection.startCol
    local b2 = SB.selection.endCol
    if not a1 or not b1 then return nil end
    if a1 > b1 or (a1 == b1 and a2 > b2) then
        a1, b1 = b1, a1
        a2, b2 = b2, a2
    end
    return a1, a2, b1, b2
end

-- Is char at (lineIdx, x) selected?
function SB.isSelected(lineIdx, x)
    if not SB.selection.active then return false end
    local a1, a2, b1, b2 = normSelection()
    if not a1 then return false end
    if lineIdx < a1 or lineIdx > b1 then return false end
    if a1 == b1 then
        return x >= a2 and x <= b2
    end
    if lineIdx == a1 then return x >= a2 end
    if lineIdx == b1 then return x <= b2 end
    return true
end

function SB.selectionBegin(screenX, screenY)
    local visibleRows = SB.viewHeight()
    if screenY < 1 or screenY > visibleRows then
        SB.selection.active = false
        return
    end
    local lineIdx = SB.scrollOffset + screenY
    if lineIdx < 1 or lineIdx > #SB.lines then
        SB.selection.active = false
        return
    end
    SB.selection.active = true
    SB.selection.startLine = lineIdx
    SB.selection.startCol = screenX
    SB.selection.endLine = lineIdx
    SB.selection.endCol = screenX
end

function SB.selectionUpdate(screenX, screenY)
    if not SB.selection.active then return end
    local visibleRows = SB.viewHeight()
    if screenY < 1 then screenY = 1 end
    if screenY > visibleRows then screenY = visibleRows end
    local lineIdx = SB.scrollOffset + screenY
    if lineIdx < 1 then lineIdx = 1 end
    if lineIdx > #SB.lines then lineIdx = #SB.lines end
    SB.selection.endLine = lineIdx
    SB.selection.endCol = screenX
end

function SB.selectionClear()
    SB.selection.active = false
    SB.selection.startLine = nil
    SB.selection.startCol = nil
    SB.selection.endLine = nil
    SB.selection.endCol = nil
end

-- Extract plain text of selection
function SB.selectionText()
    if not SB.selection.active then return nil end
    local a1, a2, b1, b2 = normSelection()
    if not a1 then return nil end

    local out = {}
    for lineIdx = a1, b1 do
        local line = SB.lines[lineIdx]
        if line then
            local text = ""
            if line.segments then
                for _, seg in ipairs(line.segments) do
                    text = text .. (seg.text or "")
                end
            else
                text = line.text or ""
            end
            local fromX = (lineIdx == a1) and a2 or 1
            local toX = (lineIdx == b1) and b2 or #text
            if fromX < 1 then fromX = 1 end
            if toX > #text then toX = #text end
            if fromX > toX then
                table.insert(out, "")
            else
                table.insert(out, text:sub(fromX, toX))
            end
        end
    end

    for i = 1, #out do
        out[i] = out[i]:gsub("%s+$", "")
    end
    while #out > 0 and out[1] == "" do table.remove(out, 1) end
    while #out > 0 and out[#out] == "" do table.remove(out) end
    return table.concat(out, "\n")
end

-- === wrapping (word-wrap with char-break for long words) ===
local function flatten(segments)
    local flat = {}
    for _, s in ipairs(segments) do
        local txt = tostring(s.text or "")
        for i = 1, #txt do
            table.insert(flat, {char = txt:sub(i, i), color = s.color or colors.white})
        end
    end
    return flat
end

local function wrapChars(flat, width)
    if width < 1 then width = 1 end
    local tokens = {}
    local i = 1
    while i <= #flat do
        local c = flat[i].char
        if c == " " or c == "\t" then
            local t = {kind = "space", chars = {}}
            while i <= #flat and (flat[i].char == " " or flat[i].char == "\t") do
                table.insert(t.chars, flat[i]); i = i + 1
            end
            table.insert(tokens, t)
        else
            local t = {kind = "word", chars = {}}
            while i <= #flat and flat[i].char ~= " " and flat[i].char ~= "\t" do
                table.insert(t.chars, flat[i]); i = i + 1
            end
            table.insert(tokens, t)
        end
    end
    local lines, current, currentLen = {}, {}, 0
    local function flush()
        while #current > 0 and current[#current].char == " " do
            table.remove(current)
        end
        table.insert(lines, current); current = {}; currentLen = 0
    end
    for _, tok in ipairs(tokens) do
        if tok.kind == "space" then
            if currentLen > 0 then
                for _, c in ipairs(tok.chars) do
                    if currentLen >= width then flush() end
                    table.insert(current, c); currentLen = currentLen + 1
                end
            end
        else
            local wlen = #tok.chars
            if currentLen + wlen <= width then
                for _, c in ipairs(tok.chars) do
                    table.insert(current, c); currentLen = currentLen + 1
                end
            elseif currentLen == 0 then
                for _, c in ipairs(tok.chars) do
                    if currentLen >= width then flush() end
                    table.insert(current, c); currentLen = currentLen + 1
                end
            else
                flush()
                for _, c in ipairs(tok.chars) do
                    if currentLen >= width then flush() end
                    table.insert(current, c); currentLen = currentLen + 1
                end
            end
        end
    end
    if #current > 0 then flush() end
    if #lines == 0 then lines = {{}} end
    return lines
end

local function lineToSegments(line)
    local segs = {}
    for _, c in ipairs(line) do
        if #segs > 0 and segs[#segs].color == c.color then
            segs[#segs].text = segs[#segs].text .. c.char
        else
            table.insert(segs, {text = c.char, color = c.color})
        end
    end
    if #segs == 0 then segs = {{text = "", color = colors.white}} end
    return segs
end

function SB.addSegments(segments)
    do
        local __segAll = {}
        for _, s in ipairs(segments or {}) do
            __segAll[#__segAll+1] = tostring(s.text or "")
        end
        logToFile(table.concat(__segAll))
    end

    if SB.colorOverride then
        local newSegs = {}
        for _, s in ipairs(segments) do
            newSegs[#newSegs+1] = {text = s.text, color = SB.colorOverride}
        end
        segments = newSegs
    end
    local width = SB.textWidth()
    local flat = flatten(segments)
    local lines = wrapChars(flat, width)
    for _, line in ipairs(lines) do
        table.insert(SB.lines, {segments = lineToSegments(line)})
    end
    local vh = SB.viewHeight()
    if #SB.lines > vh then SB.scrollOffset = #SB.lines - vh end
    SB.selectionClear()
    SB.redraw()
end

function SB.addLine(text, color)
    SB.addSegments({{text = tostring(text or ""), color = color or colors.white}})
end

function SB.drawPrompt()
    local _, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, h)
    term.clearLine()
    term.setTextColor(SB.pendingPromptColor or colors.white)
    term.write(SB.pendingPrompt)
    term.setTextColor(SB.pendingInputColor or colors.white)
    term.write(SB.pendingInput)
    if SB.pendingSuggestion and #SB.pendingSuggestion > 0 then
        term.setTextColor(colors.gray)
        term.write(SB.pendingSuggestion)
    end
    term.setTextColor(colors.white)
end

-- Draw one line, with optional selection highlight
local function drawLine(line, screenRow)
    local sel = SB.selection.active
    if not sel then
        -- fast path: no selection
        term.setBackgroundColor(colors.black)
        if line.segments then
            for _, seg in ipairs(line.segments) do
                term.setTextColor(seg.color or colors.white)
                term.write(seg.text)
            end
        else
            term.setTextColor(line.color or colors.white)
            term.write(line.text or "")
        end
        return
    end

    -- slow path: char-by-char, apply background per char
    local offset = 0
    local function putChar(c, color)
        offset = offset + 1
        local bg = colors.black
        if SB.isSelected(line, offset) then bg = colors.blue end
        term.setBackgroundColor(bg)
        term.setTextColor(color)
        term.write(c)
    end

    if line.segments then
        for _, seg in ipairs(line.segments) do
            for i = 1, #seg.text do
                putChar(seg.text:sub(i, i), seg.color or colors.white)
            end
        end
    else
        local t = line.text or ""
        for i = 1, #t do
            putChar(t:sub(i, i), line.color or colors.white)
        end
    end
end

-- Здесь lineIdx нужен в drawLine, поэтому переделываем
local realDrawLine = function(line, lineIdx, screenRow)
    term.setCursorPos(1, screenRow)
    local sel = SB.selection.active
    if not sel then
        term.setBackgroundColor(colors.black)
        if line.segments then
            for _, seg in ipairs(line.segments) do
                term.setTextColor(seg.color or colors.white)
                term.write(seg.text)
            end
        else
            term.setTextColor(line.color or colors.white)
            term.write(line.text or "")
        end
        return
    end
    local offset = 0
    if line.segments then
        for _, seg in ipairs(line.segments) do
            local s = seg.text
            local i = 1
            while i <= #s do
                offset = offset + 1
                local bg = colors.black
                if SB.isSelected(lineIdx, offset) then bg = colors.blue end
                term.setBackgroundColor(bg)
                term.setTextColor(seg.color or colors.white)
                term.write(s:sub(i, i))
                i = i + 1
            end
        end
    else
        local t = line.text or ""
        for i = 1, #t do
            offset = offset + 1
            local bg = colors.black
            if SB.isSelected(lineIdx, offset) then bg = colors.blue end
            term.setBackgroundColor(bg)
            term.setTextColor(line.color or colors.white)
            term.write(t:sub(i, i))
        end
    end
end

function SB.redraw()
    local w, h = term.getSize()
    local visibleRows = h - 1
    local total = #SB.lines
    local startIdx = 1
    if total > visibleRows then startIdx = SB.scrollOffset + 1 end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    for i = 0, visibleRows - 1 do
        local lineIdx = startIdx + i
        if lineIdx <= total then
            local line = SB.lines[lineIdx]
            realDrawLine(line, lineIdx, i + 1)
        end
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    if total > visibleRows and visibleRows > 0 then
        local barX = w
        local maxOffset = total - visibleRows
        local barHeight = math.max(1, math.floor(visibleRows * visibleRows / total))
        local barPos = 1
        if maxOffset > 0 then
            barPos = math.floor((SB.scrollOffset / maxOffset) * (visibleRows - barHeight)) + 1
        end
        for i = 1, visibleRows do
            term.setCursorPos(barX, i); term.write(" ")
        end
        for i = 0, barHeight - 1 do
            local y = barPos + i
            if y >= 1 and y <= visibleRows then
                term.setCursorPos(barX, y); term.write("#")
            end
        end
    end
    SB.drawPrompt()
end

function SB.handleScroll(dir)
    local visibleRows = SB.viewHeight()
    local total = #SB.lines
    if total <= visibleRows then return end
    local maxOffset = total - visibleRows
    if dir == -1 then
        SB.scrollOffset = math.max(0, SB.scrollOffset - 1)
    else
        SB.scrollOffset = math.min(maxOffset, SB.scrollOffset + 1)
    end
    SB.selectionClear()
    SB.redraw()
end

return SB
