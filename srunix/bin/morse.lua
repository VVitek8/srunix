local Srunix = _G.Srunix
local SB = Srunix.SB
local args = Srunix.args or {}
local function col(c) return Srunix.colorOverride or c end
local function spr(...) local t={} for i=1,select("#",...) do t[i]=tostring(select(i,...)) end SB.addLine(table.concat(t,"\t"), col(colors.white)) end
local function sprc(c,...) local t={} for i=1,select("#",...) do t[i]=tostring(select(i,...)) end SB.addLine(table.concat(t,"\t"), col(c)) end

local M = {
A=".-",B="-...",C="-.-.",D="-..",E=".",F="..-.",G="--.",H="....",
I="..",J=".---",K="-.-",L=".-..",M="--",N="-.",O="---",P=".--.",
Q="--.-",R=".-.",S="...",T="-",U="..-",V="...-",W=".--",X="-..-",
Y="-.--",Z="--..",
["0"]="-----",["1"]=".----",["2"]="..---",["3"]="...--",["4"]="....-",
["5"]=".....",["6"]="-....",["7"]="--...",["8"]="---..",["9"]="----.",
}
local RM = {}
for k, v in pairs(M) do RM[v] = k end

local function encode(text)
    local out = {}
    for i = 1, #text do
        local c = text:sub(i, i):upper()
        if c == " " then out[#out+1] = "/"
        else
            local m = M[c]
            if m then out[#out+1] = m end
        end
    end
    return table.concat(out, " ")
end

local function decode(text)
    local words = {}
    local cur = {}
    for tok in (text .. " "):gmatch("(%S+)") do
        if tok == "/" then
            words[#words+1] = table.concat(cur)
            cur = {}
        else
            local ch = RM[tok]
            if ch then cur[#cur+1] = ch end
        end
    end
    if #cur > 0 then words[#words+1] = table.concat(cur) end
    return table.concat(words, " ")
end

if #args == 0 then
    spr("Usage:")
    spr("  morse <text>            encode text to morse")
    spr("  morse <morse>           decode morse to text")
    spr("  morse -e <text>         force encode")
    spr("  morse -d <morse>        force decode")
    return
end

local mode, text
local first = args[1]
if first == "-d" or first == "--decode" then
    mode = "decode"
    text = table.concat(args, " ", 2)
elseif first == "-e" or first == "--encode" then
    mode = "encode"
    text = table.concat(args, " ", 2)
else
    local all = table.concat(args, " ")
    if all:match("^[%.%-/ ]+$") and (all:find("%.") or all:find("%-")) then
        mode = "decode"
        text = all
    else
        mode = "encode"
        text = all
    end
end

if mode == "encode" then
    sprc(colors.cyan, "Encoding: " .. text)
    sprc(colors.lime, encode(text))
else
    sprc(colors.cyan, "Decoding: " .. text)
    sprc(colors.lime, decode(text))
end
