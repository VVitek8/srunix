local Srunix = _G.Srunix
local SB = Srunix.SB
local Utils = Srunix.Utils
local args = Srunix.args or {}

local function sprc(color, ...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring(select(i, ...)) end
    SB.addLine(table.concat(parts, "\t"), color)
end

local colorMap = Utils.colorNames

local sizeArg = nil
local colorName = "lime"
local mode = "wire"

for _, a in ipairs(args) do
    local l = a:lower()
    if l == "fill" or l == "filled" or l == "solid" or l == "f" then
        mode = "fill"
    elseif l == "wire" or l == "wireframe" or l == "line" or l == "outline" or l == "w" then
        mode = "wire"
    elseif l == "random" or l == "rand" or l == "rnd" or l == "r" then
        colorName = "random"
    elseif colorMap[l] then
        colorName = l
    else
        sizeArg = a
    end
end

local isRandom = (colorName == "random")
local cubeColor = isRandom and colors.white or colorMap[colorName]

local w, h = term.getSize()
local centerX = math.floor(w / 2)
local centerY = math.floor(h / 2)
local scale = 16
if sizeArg then
    local n = Utils.argToNumber(sizeArg)
    if n and n >= 1 and n <= 200 then
        scale = n
    else
        sprc(colors.yellow, "cube: cannot use '" .. sizeArg .. "' as size, using 16")
    end
end
local distance = 4

local vertices = {
    {x=-1, y=-1, z=-1},
    {x= 1, y=-1, z=-1},
    {x= 1, y= 1, z=-1},
    {x=-1, y= 1, z=-1},
    {x=-1, y=-1, z= 1},
    {x= 1, y=-1, z= 1},
    {x= 1, y= 1, z= 1},
    {x=-1, y= 1, z= 1},
}

local edges = {
    {1,2},{2,3},{3,4},{4,1},
    {5,6},{6,7},{7,8},{8,5},
    {1,5},{2,6},{3,7},{4,8},
}

local faces = {
    {1,2,3,4},
    {5,6,7,8},
    {1,2,6,5},
    {4,3,7,8},
    {1,4,8,5},
    {2,3,7,6},
}

local faceCenters = {}
for fi, face in ipairs(faces) do
    local cx, cy, cz = 0, 0, 0
    for _, vi in ipairs(face) do
        cx = cx + vertices[vi].x
        cy = cy + vertices[vi].y
        cz = cz + vertices[vi].z
    end
    faceCenters[fi] = {x = cx / #face, y = cy / #face, z = cz / #face}
end

local edgeFaces = {}
for ei, edge in ipairs(edges) do
    edgeFaces[ei] = {}
    for fi, face in ipairs(faces) do
        local hasA, hasB = false, false
        for _, vi in ipairs(face) do
            if vi == edge[1] then hasA = true end
            if vi == edge[2] then hasB = true end
        end
        if hasA and hasB then
            table.insert(edgeFaces[ei], fi)
        end
    end
end

local faceColors = {}
for i = 1, #faces do
    faceColors[i] = Utils.randomColor()
end

local edgeColors = {}
for i = 1, #edges do
    edgeColors[i] = Utils.randomColor()
end

local function rotate(v, ax, ay, az)
    local y1 = v.y * math.cos(ax) - v.z * math.sin(ax)
    local z1 = v.y * math.sin(ax) + v.z * math.cos(ax)
    local x2 = v.x * math.cos(ay) + z1 * math.sin(ay)
    local z2 = -v.x * math.sin(ay) + z1 * math.cos(ay)
    local x3 = x2 * math.cos(az) - y1 * math.sin(az)
    local y3 = x2 * math.sin(az) + y1 * math.cos(az)
    return {x=x3, y=y3, z=z2}
end

local function project(v)
    local z = v.z + distance
    if z < 0.1 then z = 0.1 end
    local px = math.floor(centerX + (v.x * scale) / z)
    local py = math.floor(centerY - (v.y * scale) / z)
    return px, py
end

local function drawLine(x1, y1, x2, y2)
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy
    while true do
        if x1 >= 1 and x1 <= w and y1 >= 1 and y1 <= h then
            term.setCursorPos(x1, y1)
            term.write("#")
        end
        if x1 == x2 and y1 == y2 then break end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x1 = x1 + sx end
        if e2 < dx then err = err + dx; y1 = y1 + sy end
    end
end

local function fillPoly(points)
    local minY, maxY = points[1].y, points[1].y
    for _, p in ipairs(points) do
        if p.y < minY then minY = p.y end
        if p.y > maxY then maxY = p.y end
    end
    if minY < 1 then minY = 1 end
    if maxY > h then maxY = h end

    local n = #points
    for y = minY, maxY do
        local xs = {}
        for i = 1, n do
            local a = points[i]
            local b = points[i % n + 1]
            if (a.y <= y and b.y > y) or (b.y <= y and a.y > y) then
                local t = (y - a.y) / (b.y - a.y)
                table.insert(xs, a.x + t * (b.x - a.x))
            end
        end
        table.sort(xs)
        for i = 1, #xs - 1, 2 do
            local x1 = math.max(1, math.floor(xs[i] + 0.5))
            local x2 = math.min(w, math.floor(xs[i + 1] + 0.5))
            for x = x1, x2 do
                term.setCursorPos(x, y)
                term.write(" ")
            end
        end
    end
end

local ax, ay, az = 0, 0, 0
local running = true

local function animate()
    while running do
        ax = ax + 0.03
        ay = ay + 0.05
        az = az + 0.02

        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()

        local proj = {}
        local rotVerts = {}
        for i, v in ipairs(vertices) do
            local r = rotate(v, ax, ay, az)
            rotVerts[i] = r
            local px, py = project(r)
            proj[i] = {x = px, y = py}
        end

        local faceVisible = {}
        for fi, fc in ipairs(faceCenters) do
            local rfc = rotate(fc, ax, ay, az)
            local lenSq = rfc.x*rfc.x + rfc.y*rfc.y + rfc.z*rfc.z
            local dot = -lenSq - rfc.z * distance
            faceVisible[fi] = dot > 0
        end

        local edgeVisible = {}
        for ei, fis in ipairs(edgeFaces) do
            local vis = false
            for _, fi in ipairs(fis) do
                if faceVisible[fi] then vis = true break end
            end
            edgeVisible[ei] = vis
        end

        if mode == "fill" then
            local faceList = {}
            for fi, face in ipairs(faces) do
                if faceVisible[fi] then
                    local sumz = 0
                    for _, vi in ipairs(face) do
                        sumz = sumz + rotVerts[vi].z
                    end
                    table.insert(faceList, {verts = face, z = sumz / #face, idx = fi})
                end
            end
            table.sort(faceList, function(a, b) return a.z > b.z end)

            for _, f in ipairs(faceList) do
                local col = isRandom and faceColors[f.idx] or cubeColor
                term.setBackgroundColor(col)
                local pts = {}
                for _, vi in ipairs(f.verts) do
                    table.insert(pts, {x = proj[vi].x, y = proj[vi].y})
                end
                fillPoly(pts)
            end

            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            for ei, edge in ipairs(edges) do
                if edgeVisible[ei] then
                    local p1 = proj[edge[1]]
                    local p2 = proj[edge[2]]
                    drawLine(p1.x, p1.y, p2.x, p2.y)
                end
            end
        else
            term.setBackgroundColor(colors.black)
            for ei, edge in ipairs(edges) do
                if edgeVisible[ei] then
                    local col = isRandom and edgeColors[ei] or cubeColor
                    term.setTextColor(col)
                    local p1 = proj[edge[1]]
                    local p2 = proj[edge[2]]
                    drawLine(p1.x, p1.y, p2.x, p2.y)
                end
            end
        end

        os.sleep(0.05)
    end
end

local function waitForKey()
    os.pullEvent("key")
    running = false
end

pcall(term.setCursorBlink, false)
parallel.waitForAll(animate, waitForKey)

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
pcall(term.setCursorBlink, true)
SB.redraw()
