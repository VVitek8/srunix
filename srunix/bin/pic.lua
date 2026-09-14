local Srunix = _G.Srunix
local SB = Srunix.SB
local args = Srunix.args or {}

local srunixLog = _G.srunixLog or function() end
local function picLog(msg)
    pcall(srunixLog, "PIC", msg)
end
local function nowMs()
    if os.epoch then
        local ok, v = pcall(os.epoch, "utc")
        if ok and type(v) == "number" then return v end
    end
    return (os.time() or 0) * 1000
end
local function keyName(code)
    if type(keys) == "table" then
        for k, v in pairs(keys) do
            if v == code then return k end
        end
    end
    return "k"..tostring(code)
end


local function mk(c) return function(...) local t={} for i=1,select("#",...) do t[i]=tostring(select(i,...)) end SB.addLine(table.concat(t,"\t"),c) end end
local spr,sprOk,sprErr,sprWarn,sprInfo,sprDbg =
    mk(colors.white),mk(colors.lime),mk(colors.red),mk(colors.yellow),mk(colors.cyan),mk(colors.gray)

local __yc=0
local function Y(f) __yc=__yc+1 if f or __yc>=500 then __yc=0 os.queueEvent("_y") os.pullEvent("_y") end end

local DIRS={"/images","/srunix/images","/programs/images"}
local MAX_FILE=1500000
local HAS_GFX=(term.setGraphicsMode~=nil)

-- target decode resolution
local DEC_W=200
local DEC_H=113

-- palette setup
local paletteReady=false
local function setupPalette256()
    if paletteReady then return end
    paletteReady=true
    for i=0,215 do
        local r6=math.floor(i/36) local g6=math.floor((i%36)/6) local b6=i%6
        pcall(term.setPaletteColor,16+i,r6/5,g6/5,b6/5)
    end
    for i=0,23 do
        local v=(8+i*(255-8)/23)/255
        pcall(term.setPaletteColor,232+i,v,v,v)
    end
end

-- plain RGB->256, no saturation
local GRAY_TH=12
local function rgbTo256(r,g,b)
    local mx=math.max(r,g,b) local mn=math.min(r,g,b)
    if mx-mn<GRAY_TH then
        local gray=(r+g+b)/3
        local idx=math.floor((gray-8)/((255-8)/23)+0.5)
        if idx<0 then idx=0 end if idx>23 then idx=23 end
        return 232+idx
    end
    local r6=math.floor(r/51+0.5) local g6=math.floor(g/51+0.5) local b6=math.floor(b/51+0.5)
    if r6>5 then r6=5 end if g6>5 then g6=5 end if b6>5 then b6=5 end
    return 16+36*r6+6*g6+b6
end

-- ===== INFLATE =====
local LB={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local LE={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local DB={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local DE={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local CLO={17,18,19,1,9,8,10,7,11,6,12,5,13,4,14,3,15,2,16}
local FL={} for i=1,288 do local s=i-1 if s<=143 then FL[i]=8 elseif s<=255 then FL[i]=9 elseif s<=279 then FL[i]=7 else FL[i]=8 end end
local FD={} for i=1,30 do FD[i]=5 end
local BC={} for i=0,255 do BC[i]=string.char(i) end

local BR={} BR.__index=BR
function BR.new(d,p) return setmetatable({d=d,p=p or 1,bb=0,bc=0},BR) end
function BR:rb() local b=self.d:byte(self.p) or 0 self.p=self.p+1 return b end
function BR:bit() if self.bc==0 then self.bb=self:rb() self.bc=8 end local b=self.bb%2 self.bb=math.floor(self.bb/2) self.bc=self.bc-1 return b end
function BR:bits(n) local v,p=0,1 for _=1,n do v=v+self:bit()*p p=p*2 end return v end
function BR:align() self.bc=0 end

local function buildHuff(lens)
    local mB=0 local bc={}
    for i=1,#lens do local l=lens[i] if l>0 then bc[l]=(bc[l] or 0)+1 if l>mB then mB=l end end end
    if mB==0 then return {},0 end
    local nc,code={},0
    for b=1,mB do code=(code+(bc[b-1] or 0))*2 nc[b]=code end
    local lut={}
    for i=1,#lens do local l=lens[i] if l>0 then if not lut[l] then lut[l]={} end lut[l][nc[l]]=i-1 nc[l]=nc[l]+1 end end
    return lut,mB
end

local function dhuff(br,lut,mB)
    local c=0
    for l=1,mB do c=c*2+br:bit() local r=lut[l] if r then local s=r[c] if s~=nil then return s end end end
    error("bad huffman")
end

local function inflate(data, startPos, onChunk, onProgress)
    local br=BR.new(data,startPos or 1)
    local cmf,flg=br:rb(),br:rb()
    if (cmf*256+flg)%31~=0 then error("bad zlib") end
    if cmf%16~=8 then error("not deflate") end
    local ring={} local ringLen=0
    local function rput(ch)
        local last=ring[#ring]
        if last and #last<512 then ring[#ring]=last..ch else ring[#ring+1]=ch end
        ringLen=ringLen+1
        while ringLen>32768 and #ring>1 do ringLen=ringLen-#ring[1] table.remove(ring,1) end
    end
    local function rget(off)
        local need=off
        for i=#ring,1,-1 do
            local c=ring[i]
            if need<=#c then return c:byte(-need) end
            need=need-#c
        end
        return 0
    end
    local buf,bufN,total={},0,0
    local function flush()
        if bufN>0 then
            onChunk(table.concat(buf,nil,1,bufN))
            total=total+bufN bufN=0
            if onProgress then onProgress(total) end
        end
    end
    local function wb(b)
        local ch=BC[b] rput(ch) bufN=bufN+1 buf[bufN]=ch
        if bufN>=4096 then flush() Y(true) end
    end
    local flit,flitM=buildHuff(FL)
    local fdst,fdstM=buildHuff(FD)
    local function dblock(ll,lm,dl,dm)
        while true do
            Y()
            local s=dhuff(br,ll,lm)
            if s<256 then wb(s)
            elseif s==256 then return
            else
                local li=s-256
                if li<1 or li>#LB then error("bad len") end
                local len=LB[li] local le=LE[li]
                if le>0 then len=len+br:bits(le) end
                local ds=dhuff(br,dl,dm)
                local di=ds+1
                if di<1 or di>#DB then error("bad dist") end
                local dist=DB[di] local de=DE[di]
                if de>0 then dist=dist+br:bits(de) end
                for _=1,len do wb(rget(dist)) end
            end
        end
    end
    local done=false
    while not done do
        Y()
        local bf=br:bit() local bt=br:bits(2)
        if bt==0 then
            br:align()
            local ln=br:rb()+br:rb()*256
            br:rb() br:rb()
            for _=1,ln do wb(br:rb()) Y() end
        elseif bt==1 then dblock(flit,flitM,fdst,fdstM)
        elseif bt==2 then
            local hlit=br:bits(5)+257
            local hdist=br:bits(5)+1
            local hclen=br:bits(4)+4
            local cl={} for i=1,19 do cl[i]=0 end
            for i=1,hclen do cl[CLO[i]]=br:bits(3) end
            local cll,clm=buildHuff(cl)
            local all,i,tot={},1,hlit+hdist
            while i<=tot do
                Y()
                local s=dhuff(br,cll,clm)
                if s<16 then all[i]=s i=i+1
                elseif s==16 then
                    local pv=all[i-1] or 0 local n=br:bits(2)+3
                    for _=1,n do all[i]=pv i=i+1 end
                elseif s==17 then
                    local n=br:bits(3)+3
                    for _=1,n do all[i]=0 i=i+1 end
                elseif s==18 then
                    local n=br:bits(7)+11
                    for _=1,n do all[i]=0 i=i+1 end
                end
            end
            local ll,dl={},{}
            for j=1,hlit do ll[j]=all[j] or 0 end
            for j=1,hdist do dl[j]=all[hlit+j] or 0 end
            local llut,llm=buildHuff(ll)
            local dlut,dlm=buildHuff(dl)
            dblock(llut,llm,dlut,dlm)
        else error("bad btype") end
        if bf==1 then done=true end
    end
    flush()
end

local function u32(d,p) return (d:byte(p) or 0)*16777216+(d:byte(p+1) or 0)*65536+(d:byte(p+2) or 0)*256+(d:byte(p+3) or 0) end

local function showProg(t)
    local _,h=term.getSize()
    term.setBackgroundColor(colors.black) term.setTextColor(colors.yellow)
    term.setCursorPos(1,h) term.clearLine() term.write(t)
end

-- ===== PNG -> packed RGB string =====
local function decodePng(data, tw, th)
    if data:sub(1,8)~="\137\080\078\071\013\010\026\010" then return nil,"bad sig" end
    local pos=9
    local W,H,bd,ct,il
    local idatParts={}
    local pal=nil
    while pos<=#data do
        if pos+8>#data then break end
        local cl=u32(data,pos)
        local cy=data:sub(pos+4,pos+7)
        local cdp=pos+8
        if cy=="IHDR" then
            W=u32(data,cdp) H=u32(data,cdp+4)
            bd=data:byte(cdp+8) ct=data:byte(cdp+9) il=data:byte(cdp+12)
        elseif cy=="PLTE" then
            pal={}
            for i=0,math.floor(cl/3)-1 do
                pal[i]={data:byte(cdp+i*3),data:byte(cdp+i*3+1),data:byte(cdp+i*3+2)}
            end
        elseif cy=="IDAT" then
            idatParts[#idatParts+1]=data:sub(cdp,cdp+cl-1)
        elseif cy=="IEND" then break end
        pos=pos+8+cl+4
    end
    if not W then return nil,"no IHDR" end
    if il~=0 then return nil,"interlaced" end
    if bd~=8 then return nil,"bd "..bd end
    if ct~=0 and ct~=2 and ct~=3 and ct~=6 then return nil,"ct "..ct end
    local chan=(ct==0 or ct==3) and 1 or (ct==2) and 3 or 4
    local rs=W*chan
    local bpr=1+rs
    local totalRaw=H*bpr

    local idatS=table.concat(idatParts)
    idatParts=nil
    data=nil

    local accR,accG,accB,accN={},{},{},{}
    for i=1,tw do accR[i]=0 accG[i]=0 accB[i]=0 accN[i]=0 end
    local outRows={}
    local curTy=-1

    local prev={} for i=1,rs do prev[i]=0 end
    local rb,rn={},0
    local sy=0
    local lastPct=-1

    local function finalizeRow()
        if curTy<1 or curTy>th then return end
        local parts={}
        for tx=1,tw do
            local n=accN[tx]
            if n>0 then
                parts[tx]=string.char(math.floor(accR[tx]/n),math.floor(accG[tx]/n),math.floor(accB[tx]/n))
            else
                parts[tx]=string.char(0,0,0)
            end
        end
        outRows[curTy]=table.concat(parts)
        for i=1,tw do accR[i]=0 accG[i]=0 accB[i]=0 accN[i]=0 end
    end

    local function processRow()
        local ft=rb[1] or 0
        local row={}
        for i=1,rs do
            local x=rb[i+1] or 0
            local a=(i>chan) and row[i-chan] or 0
            local b=prev[i] or 0
            local c=(i>chan) and (prev[i-chan] or 0) or 0
            local v
            if ft==0 then v=x
            elseif ft==1 then v=x+a
            elseif ft==2 then v=x+b
            elseif ft==3 then v=x+math.floor((a+b)/2)
            elseif ft==4 then
                local p=a+b-c
                local pa,pb,pc=math.abs(p-a),math.abs(p-b),math.abs(p-c)
                local pred
                if pa<=pb and pa<=pc then pred=a
                elseif pb<=pc then pred=b
                else pred=c end
                v=x+pred
            else error("ft "..ft) end
            row[i]=v%256
        end
        local ty=math.floor(sy*th/H)+1
        if ty>th then ty=th end
        if ty~=curTy then finalizeRow() curTy=ty end
        if ty>=1 and ty<=th then
            for x=0,W-1 do
                local base=x*chan+1
                local r,g,b
                if ct==0 then local v=row[base] or 0 r,g,b=v,v,v
                elseif ct==2 then r=row[base] or 0 g=row[base+1] or 0 b=row[base+2] or 0
                elseif ct==3 then
                    local pi=row[base] or 0
                    local p=pal and pal[pi]
                    if p then r,g,b=p[1],p[2],p[3] else r,g,b=0,0,0 end
                elseif ct==6 then r=row[base] or 0 g=row[base+1] or 0 b=row[base+2] or 0 end
                local tx=math.floor(x*tw/W)+1
                if tx>tw then tx=tw end
                if tx>=1 then
                    accR[tx]=accR[tx]+r accG[tx]=accG[tx]+g
                    accB[tx]=accB[tx]+b accN[tx]=accN[tx]+1
                end
            end
        end
        prev=row
        sy=sy+1
    end

    inflate(idatS,1,function(chunk)
        for i=1,#chunk do
            rn=rn+1 rb[rn]=chunk:byte(i)
            if rn==bpr then processRow() rb={} rn=0 Y() end
        end
    end,function(w)
        local pct=math.floor(w*100/totalRaw)
        if pct>100 then pct=100 end
        if pct~=lastPct then lastPct=pct showProg(string.format("Decoding: %d%% (%dx%d)",pct,W,H)) end
    end)

    finalizeRow()
    idatS=nil
    local parts={}
    for ty=1,th do parts[ty]=outRows[ty] or string.rep(string.char(0,0,0),tw) end
    return table.concat(parts),tw,th
end

local function decodeBmp(data, tw, th)
    if data:sub(1,2)~="BM" then return nil,"not BMP" end
    local po=(data:byte(11) or 0)+(data:byte(12) or 0)*256+(data:byte(13) or 0)*65536+(data:byte(14) or 0)*16777216
    local W=(data:byte(19) or 0)+(data:byte(20) or 0)*256+(data:byte(21) or 0)*65536+(data:byte(22) or 0)*16777216
    local h1,h2,h3,h4=data:byte(23) or 0,data:byte(24) or 0,data:byte(25) or 0,data:byte(26) or 0
    local H,flip
    if h4>=128 then local b4=256-h4 H=-(h1+h2*256+h3*65536+b4*16777216) flip=false
    else H=h1+h2*256+h3*65536+h4*16777216 flip=true end
    local bpp=(data:byte(29) or 0)+(data:byte(30) or 0)*256
    local cmp=(data:byte(31) or 0)+(data:byte(32) or 0)*256
    if cmp~=0 then return nil,"compressed BMP" end
    if bpp~=24 then return nil,"bpp "..bpp end
    local rs=math.floor((bpp*W+31)/32)*4
    local accR,accG,accB,accN={},{},{},{}
    for i=1,tw do accR[i]=0 accG[i]=0 accB[i]=0 accN[i]=0 end
    local outRows={}
    local curTy=-1
    local function finalizeRow()
        if curTy<1 or curTy>th then return end
        local parts={}
        for tx=1,tw do
            local n=accN[tx]
            if n>0 then parts[tx]=string.char(math.floor(accR[tx]/n),math.floor(accG[tx]/n),math.floor(accB[tx]/n))
            else parts[tx]=string.char(0,0,0) end
        end
        outRows[curTy]=table.concat(parts)
        for i=1,tw do accR[i]=0 accG[i]=0 accB[i]=0 accN[i]=0 end
    end
    local lastPct=-1
    for y=1,H do
        Y()
        local pct=math.floor((y-1)*100/H)
        if pct~=lastPct then lastPct=pct showProg(string.format("BMP: %d%% (%dx%d)",pct,W,H)) end
        local srow=flip and (H-y) or (y-1)
        local rs2=po+srow*rs+1
        local ty=math.floor((y-1)*th/H)+1
        if ty>th then ty=th end
        if ty~=curTy then finalizeRow() curTy=ty end
        if ty>=1 and ty<=th then
            for x=0,W-1 do
                local px=rs2+x*3
                local b=data:byte(px) or 0
                local g=data:byte(px+1) or 0
                local r=data:byte(px+2) or 0
                local tx=math.floor(x*tw/W)+1
                if tx>tw then tx=tw end
                if tx>=1 then
                    accR[tx]=accR[tx]+r accG[tx]=accG[tx]+g
                    accB[tx]=accB[tx]+b accN[tx]=accN[tx]+1
                end
            end
        end
    end
    finalizeRow()
    local parts={}
    for ty=1,th do parts[ty]=outRows[ty] or string.rep(string.char(0,0,0),tw) end
    return table.concat(parts),tw,th
end

-- ===== save/load =====
local function saveNfp(path, packed, w, h)
    local f=fs.open(path,"w") if not f then return false end
    f.write(textutils.serialize({w=w,h=h,data=packed}))
    f.close()
    return true
end

local function loadNfp(path)
    if not fs.exists(path) then return nil end
    local f=fs.open(path,"r") if not f then return nil end
    local raw=f.readAll() f.close()
    if not raw or #raw==0 then return nil end
    local first=raw:sub(1,1)
    if first~="{" and first~=" " and first~="\n" then return nil end
    local ok,obj=pcall(textutils.unserialize,raw)
    if not ok or type(obj)~="table" then return nil end
    if obj.data and obj.w and obj.h then return obj.data,obj.w,obj.h end
    if #obj>0 and obj[1] then
        local mnx,mny,mxx,mxy=math.huge,math.huge,-math.huge,-math.huge
        for _,p in ipairs(obj) do
            if p.x and p.y then
                if p.x<mnx then mnx=p.x end if p.y<mny then mny=p.y end
                if p.x>mxx then mxx=p.x end if p.y>mxy then mxy=p.y end
            end
        end
        if mnx==math.huge then return nil end
        local w,h=mxx-mnx+1,mxy-mny+1
        local map={}
        for _,p in ipairs(obj) do
            if p.x and p.y then
                local gx,gy=p.x-mnx+1,p.y-mny+1
                local r,g,b=0,0,0
                if p.r then r,g,b=p.r,p.g,p.b
                elseif p.color then
                    local cc=p.color
                    local CCV={{1,240,240,240},{2,242,178,51},{4,229,127,216},{8,153,178,242},{16,222,222,108},{32,127,204,25},{64,242,178,204},{128,76,76,76},{256,153,153,153},{512,76,153,178},{1024,178,102,229},{2048,51,102,204},{4096,127,102,76},{8192,87,166,78},{16384,204,76,76}}
                    for _,c in ipairs(CCV) do if c[1]==cc then r,g,b=c[2],c[3],c[4] break end end
                end
                map[(gy-1)*w+gx]={r,g,b}
            end
        end
        local parts={}
        for gy=1,h do
            local rowchars={}
            for gx=1,w do
                local p=map[(gy-1)*w+gx]
                if p then rowchars[gx]=string.char(p[1],p[2],p[3])
                else rowchars[gx]=string.char(0,0,0) end
            end
            parts[gy]=table.concat(rowchars)
        end
        return table.concat(parts),w,h
    end
    return nil
end

local function tryDecode(path, tw, th)
    local f=fs.open(path,"rb") if not f then return nil,"cannot open" end
    local data=f.readAll() f.close()
    if not data or #data<8 then return nil,"too small" end
    if #data>MAX_FILE then return nil,"file too big" end
    if data:sub(1,8)=="\137\080\078\071\013\010\026\010" then
        local p,w,h=decodePng(data,tw,th) data=nil return p,w,h
    end
    if data:sub(1,2)=="BM" then
        local p,w,h=decodeBmp(data,tw,th) data=nil return p,w,h
    end
    if data:byte(1)==255 and data:byte(2)==216 then return nil,"JPEG not supported" end
    if data:sub(1,3)=="GIF" then return nil,"GIF not supported" end
    return nil,"unknown"
end

-- ===== draw =====
local function drainEvents(dur)
    local timer = os.startTimer(dur or 0.2)
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "timer" and p1 == timer then return end
    end
end

local function waitKey()
    -- Drain any pending events (auto-repeat from Enter, etc.)
    do
        local timer = os.startTimer(0.3)
        while true do
            local ev, p1 = os.pullEvent()
            if ev == "timer" and p1 == timer then break end
        end
    end
    -- Exit ONLY on Q or mouse click. Enter never exits.
    local tView = nowMs()
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "key" and p1 == keys.q then
            picLog(string.format("view exit Q after %dms", nowMs() - tView))
            return
        end
        if ev == "mouse_click" then
            picLog(string.format("view exit click after %dms", nowMs() - tView))
            return
        end
        if ev == "key" then
            picLog(string.format("view key=%s(%d) ignored", keyName(p1), p1))
        end
    end
end


local function findGPU()
    if not peripheral or not peripheral.getNames then return nil end
    for _, name in ipairs(peripheral.getNames()) do
        local t = peripheral.getType(name)
        if type(t) == "string" then
            local lt = t:lower()
            if lt:find("gpu") or lt == "tm_gpu" then
                local ok, g = pcall(peripheral.wrap, name)
                if ok and g then return g end
            end
        end
    end
    return nil
end

local function drawGfx(packed,w,h)
    -- 1. Попытка через GPU Tom's Peripherals
    local gpu = findGPU()
    if gpu then
        gpu.refreshSize()
        local sw, sh = gpu.getSize()
        gpu.fill(0)
        -- Рисуем попиксельно через filledRectangle (если drawImage нет)
        local sx = sw / w
        local sy = sh / h
        for y = 1, h do
            for x = 1, w do
                local b = ((y-1)*w + (x-1))*3
                local r = packed:byte(b+1) or 0
                local g = packed:byte(b+2) or 0
                local bl = packed:byte(b+3) or 0
                local color = r * 65536 + g * 256 + bl
                gpu.filledRectangle(math.floor((x-1)*sx), math.floor((y-1)*sy), 
                                   math.ceil(sx), math.ceil(sy), color)
            end
            if y % 8 == 0 then Y() end
        end
        gpu.sync()
        return true
    end
    -- 2. CC:Graphics fallback
    if term.setGraphicsMode then
        local ok = pcall(term.setGraphicsMode, 2)
        if ok then
            setupPalette256()
            local cw,ch = term.getSize()
            local pw = cw * 6
            local ok2, mw = pcall(function() return term.getSize(1) end)
            if ok2 and type(mw)=="number" and mw > 100 then pw = mw end
            local ph = (ch - 1) * 9
            local lines = {}
            for py = 0, ph-1 do
                local ty = math.floor(py*h/ph)+1
                if ty>h then ty=h end
                local rowOff = (ty-1)*w*3
                local chars = {}
                for px = 0, pw-1 do
                    local tx = math.floor(px*w/pw)+1
                    if tx>w then tx=w end
                    local b = rowOff+(tx-1)*3
                    local r = packed:byte(b+1) or 0
                    local g = packed:byte(b+2) or 0
                    local bl = packed:byte(b+3) or 0
                    chars[px+1] = string.char(rgbTo256(r,g,bl))
                end
                lines[py+1] = table.concat(chars)
                if py%12==0 then Y() end
            end
            if term.drawPixels then
                pcall(term.drawPixels, 0, 0, lines)
            elseif term.setPixel then
                for py=0,ph-1 do
                    local row = lines[py+1]
                    for px=1,pw do pcall(term.setPixel, px-1, py, row:byte(px)) end
                    if py%4==0 then Y() end
                end
            end
            pcall(term.setGraphicsMode, 0)
            return true
        end
    end
    return false
end

local function drawText(packed,w,h)
    local cw,ch=term.getSize()
    local rows=ch-1
    term.setBackgroundColor(colors.black) term.clear()
    local P={{240,240,240},{242,178,51},{229,127,216},{153,178,242},{222,222,108},{127,204,25},{242,178,204},{76,76,76},{153,153,153},{76,153,178},{178,102,229},{51,102,204},{127,102,76},{87,166,78},{204,76,76},{17,17,17}}
    local V={1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768}
    local function nearest(r,g,b)
        local best,bd=1,math.huge
        for i=1,16 do local c=P[i] local dr,dg,db=r-c[1],g-c[2],b-c[3] local d=dr*dr+dg*dg+db*db if d<bd then bd=d best=V[i] end end
        return best
    end
    for cy=1,rows do
        local ty=math.floor((cy-1)*h/rows)+1 if ty>h then ty=h end
        local rowOff=(ty-1)*w*3
        for cx=1,cw do
            local tx=math.floor((cx-1)*w/cw)+1 if tx>w then tx=w end
            local b=rowOff+(tx-1)*3
            term.setCursorPos(cx,cy)
            term.setBackgroundColor(nearest(packed:byte(b+1) or 0,packed:byte(b+2) or 0,packed:byte(b+3) or 0))
            term.write(" ")
        end
        if cy%4==0 then Y() end
    end
end

local function lastPathFile()
    local home = (_G.Srunix and _G.Srunix.home) or "/srunix/home/root"
    return home .. "/.pic_last"
end
local function saveLastShown(p)
    local fp = lastPathFile()
    local dir = fp:match("^(.*)/[^/]+$")
    if dir and not fs.exists(dir) then pcall(fs.makeDir, dir) end
    local f = fs.open(fp, "w")
    if f then f.write(p) f.close() end
end
local function loadLastShown()
    local fp = lastPathFile()
    if not fs.exists(fp) then return nil end
    local f = fs.open(fp, "r")
    if not f then return nil end
    local p = f.readAll() f.close()
    if p and p ~= "" then return p end
    return nil
end

local function showImage(packed,w,h,title)
    picLog(string.format("show start name=%s %dx%d", title or "?", w, h))
    pcall(term.setCursorBlink,false)
    local ok=drawGfx(packed,w,h)
    if ok then
        waitKey()
        pcall(term.setGraphicsMode,0)
    else
        drawText(packed,w,h)
        term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
        local _,sh=term.getSize()
        term.setCursorPos(1,sh) term.write(" "..(title or "").."  [any key] ")
        waitKey()
    end
    pcall(term.setCursorBlink,true)
    pcall(term.setGraphicsMode,0)
    term.setBackgroundColor(colors.black)
    term.clear()
    SB.redraw()
end

-- ===== scan =====
local function stripExt(n) return (n:gsub("%.[^%.]+$","")) end

local function collectOne(dir)
    local files,folders={},{}
    local ok,list=pcall(fs.list,dir)
    if not ok or not list then return files,folders end
    for _,name in ipairs(list) do
        local full=dir.."/"..name
        if fs.isDir(full) then
            local sOk,sL=pcall(fs.list,full)
            if sOk and sL then
                local frames={}
                for _,s in ipairs(sL) do if s:match("%.nfp$") then frames[#frames+1]=full.."/"..s end end
                if #frames>0 then table.sort(frames) folders[#folders+1]={name=name,frames=frames} end
            end
        else
            files[#files+1]=full
        end
    end
    return files,folders
end

local function buildEntries()
    local entries={}
    local allF,allD={},{}
    for _,d in ipairs(DIRS) do
        if fs.exists(d) and fs.isDir(d) then
            local files,folders=collectOne(d)
            for _,f in ipairs(files) do allF[#allF+1]=f end
            for _,f in ipairs(folders) do allD[#allD+1]=f end
        end
    end
    local nfpBases={}
    for _,p in ipairs(allF) do
        local b=p:match("^(.*)%.nfp$")
        if b then
            local ok=(loadNfp(p)~=nil)
            if ok then nfpBases[b]=true end
        end
    end
    for _,path in ipairs(allF) do
        Y()
        local name=path:match("[^/]+$") or path
        local ext=name:match("%.([^%.]+)$")
        ext=ext and ext:lower() or ""
        if ext=="nfp" or ext=="nft" then
            local ok=(loadNfp(path)~=nil)
            if ok then entries[#entries+1]={kind="image",name=name,path=path}
            else entries[#entries+1]={kind="unknown",name=name,path=path,reason="broken"} end
        elseif ext=="png" or ext=="bmp" then
            local base=path:gsub("%.[^%.]+$","")
            if not nfpBases[base] then entries[#entries+1]={kind="raw",name=name,path=path} end
        elseif ext=="jpg" or ext=="jpeg" or ext=="gif" then
            entries[#entries+1]={kind="undecodable",name=name,path=path}
        elseif ext~="" then
            entries[#entries+1]={kind="unknown",name=name,path=path,reason="unknown"}
        end
    end
    for _,f in ipairs(allD) do entries[#entries+1]={kind="anim",name=f.name.."/",frames=f.frames} end
    table.sort(entries,function(a,b) return a.name:lower()<b.name:lower() end)
    return entries
end

-- ===== prompts =====
local function askYes(t)
    term.setBackgroundColor(colors.black) term.setTextColor(colors.red)
    local _,h=term.getSize()
    term.setCursorPos(1,h) term.clearLine() term.write(t or "[Y/N]: ")
    pcall(term.setCursorBlink,true)
    local yes=false
    while true do
        local ev,p1=os.pullEvent()
        if ev=="char" then
            local c=tostring(p1 or ""):lower()
            if c=="y" or c=="н" then yes=true end
            break
        elseif ev=="key" then
            if p1==keys.y then yes=true break end
            if p1==keys.enter or p1==keys.escape then break end
        elseif ev=="mouse_click" then break end
    end
    pcall(term.setCursorBlink,false)
    term.setCursorPos(1,h) term.clearLine()
    return yes
end

local function renderList(entries, cursor)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    -- Header row 1
    term.setTextColor(colors.cyan)
    term.setCursorPos(1, 1)
    term.write("=== Select image (" .. #entries .. ") ===")

    -- Hint row 2
    local _, h = term.getSize()
    term.setTextColor(colors.gray)
    term.setCursorPos(1, 2)
    term.write("Up/Down=nav  Enter=view  Q=quit")

    -- Entries start at row 3
    local topRow = 3
    local mv = h - topRow  -- how many rows fit
    if mv < 1 then mv = 1 end
    local si = 1
    if cursor > mv then si = cursor - mv + 1 end
    local ei = math.min(#entries, si + mv - 1)

    for i = si, ei do
        local e = entries[i]
        local marker = (i == cursor) and "-> " or "   "
        local line = marker .. "[" .. i .. "] " .. e.name
        if e.kind == "raw" then line = line .. " (not converted)"
        elseif e.kind == "undecodable" then line = line .. " (cannot decode)"
        elseif e.kind == "anim" then line = line .. " (animation)"
        elseif e.kind == "unknown" then line = line .. " (broken)" end

        term.setCursorPos(1, topRow + (i - si))
        if i == cursor then term.setTextColor(colors.lime)
        elseif e.kind == "raw" then term.setTextColor(colors.yellow)
        elseif e.kind == "undecodable" or e.kind == "unknown" then term.setTextColor(colors.red)
        else term.setTextColor(colors.white) end
        term.write(line)
    end
end

local function listSelect(entries, init)
    if #entries == 0 then return nil end
    local c = init or 1
    if c < 1 then c = 1 end
    if c > #entries then c = #entries end

    -- Drain pending events
    do
        local timer = os.startTimer(0.05)
        while true do
            local ev, p1 = os.pullEvent()
            if ev == "timer" and p1 == timer then break end
        end
    end

    while true do
        renderList(entries, c)
        local ev, p1 = os.pullEvent()
        if ev == "key" then
            picLog(string.format("list key=%s(%d) cursor=%d", keyName(p1), p1, c))
            if p1 == keys.up then
                c = c - 1
                if c < 1 then c = #entries end
            elseif p1 == keys.down then
                c = c + 1
                if c > #entries then c = 1 end
            elseif p1 == keys.q then
                return nil, c
            elseif p1 == keys.enter or p1 == keys.numPadEnter then
                -- Wait for key_up first so we don't auto-repeat Enter
                local timer = os.startTimer(0.5)
                while true do
                    local e2, p2 = os.pullEvent()
                    if e2 == "key_up" then break end
                    if e2 == "timer" and p2 == timer then break end
                end
                return entries[c], c
            end
        elseif ev == "mouse_scroll" then
            if p1 == -1 then
                c = c - 1
                if c < 1 then c = #entries end
            else
                c = c + 1
                if c > #entries then c = 1 end
            end
        end
    end
end


local function convertOne(e)
    local tw,th=DEC_W,DEC_H
    showProg("Decoding: 0%")
    local t0=os.clock()
    local packed,w,h=tryDecode(e.path,tw,th)
    local dt=os.clock()-t0
    showProg("")
    if not packed then sprErr("Failed: "..tostring(w)) return nil end
    local dir=e.path:match("^(.*)/[^/]+$") or "/images"
    local base=stripExt(e.name)
    local dst=dir.."/"..base..".nfp"
    if not saveNfp(dst,packed,w,h) then sprErr("Save failed") return nil end
    sprOk("Converted to "..base..".nfp  ("..string.format("%.1f",dt).."s)  "..w.."x"..h)
    return packed,w,h
end

local function showEntry(e)
    if e.kind=="image" or e.kind=="anim" then
        local src=e.path
        if e.kind=="anim" then src=e.frames[1] end
        local packed,w,h=loadNfp(src)
        if not packed then sprErr("Failed: "..e.name) return "error" end
        saveLastShown(e.path or src)
        saveLastShown(e.path) showImage(packed,w,h,e.name)
        return "shown"
    elseif e.kind=="raw" then
        sprWarn("'"..e.name.."' is not converted.")
        sprWarn("Convert now? Press Y for yes, any other key = no.")
        if not askYes("[Y/N]: ") then return "back" end
        local packed,w,h=convertOne(e)
        if not packed then return "error" end
        local dir=e.path:match("^(.*)/[^/]+$") or "/images"
        saveLastShown(dir.."/"..stripExt(e.name)..".nfp")
        showImage(packed,w,h,stripExt(e.name)..".nfp")
        return "shown"
    elseif e.kind=="undecodable" then
        sprErr(e.name.." cannot be decoded.") return "error"
    elseif e.kind=="unknown" then
        sprErr(e.name.." is not valid.") return "error"
    end
    return "error"
end

-- ===== argument parser =====
-- Format: pic [subcommand] [name/number]
-- Subcommands: random|r, list|l|choose, info, test, sat N, grayth N
local GRAY_TH=12
local mode="list"
local target=nil

-- First, scan for subcommands
local i=1
while i<=#args do
    local a=args[i]:lower()
    if a=="sat" and args[i+1] then
        local v=tonumber(args[i+1]) or 1.0
        -- sat not used in this version (kept for compat)
        i=i+2
    elseif a=="grayth" and args[i+1] then
        local v=tonumber(args[i+1])
        if v then
            if v<0 then v=0 end
            if v>60 then v=60 end
            GRAY_TH=v
            sprOk("Gray threshold = "..v)
        end
        i=i+2
    elseif a=="last" then
        mode="last" i=i+1
    elseif a=="show" or a=="random" then
        mode="random" i=i+1
    elseif a=="fit" then
        FIT_MODE = "fit"
        sprOk("Режим: fit (сохранять пропорции).")
        i=i+1
    elseif a=="stretch" then
        FIT_MODE = "stretch"
        sprOk("Режим: stretch (растянуть).")
        i=i+1
    elseif a=="1to1" or a=="1:1" then
        FIT_MODE = "1to1"
        sprOk("Режим: 1:1 (без масштаба).")
        i=i+1
    elseif a=="random" or a=="r" or a=="rand" then
        mode="random" i=i+1
    elseif a=="list" or a=="l" or a=="choose" then
        mode="list" i=i+1
    elseif a=="info" or a=="diag" then
        mode="info" i=i+1
    else
        -- treat as target name
        if not target then
            mode="specific"
            target=args[i]
        end
        i=i+1
    end
end

-- ===== main =====
local anyDir=false
for _,d in ipairs(DIRS) do if fs.exists(d) and fs.isDir(d) then anyDir=true break end end
if not anyDir then sprErr("No 'images' folder.") return end

if mode=="info" then
    sprInfo("=== Screen info ===")
    local w1,h1=term.getSize()
    spr("Text size: "..tostring(w1).."x"..tostring(h1))
    if HAS_GFX then
        pcall(term.setGraphicsMode,2)
        local gw,gh
        pcall(function() gw=term.getSize(1) end)
        pcall(function() gh=term.getSize(2) end)
        pcall(term.setGraphicsMode,0)
        spr("Graphics: getSize(1)="..tostring(gw).." getSize(2)="..tostring(gh))
        spr("Using: 306x"..tostring((h1-1)*9).." pixels (height=ch*9)")
    end
    spr("Decode target: "..DEC_W.."x"..DEC_H)
    spr("Gray threshold: "..GRAY_TH)
    return
end

if mode=="last" then
    local lp = loadLastShown()
    if not lp then
        sprErr("No last image recorded. Run 'pic list' first.")
        return
    end
    if not fs.exists(lp) then
        sprErr("Last image no longer exists: "..lp)
        return
    end
    local packed,w,h=loadNfp(lp)
    if not packed then
        sprErr("Could not load "..lp)
        return
    end
    showImage(packed,w,h,lp:match("[^/]+$") or lp)
    SB.redraw()
    return
end

if mode=="list" then
    local cursor=1
    while true do
        local entries=buildEntries()
        if #entries==0 then sprErr("No images.") return end
        local e,nc=listSelect(entries,cursor)
        cursor=nc or cursor
        if not e then SB.redraw() return end
        showEntry(e)
    end
end

if mode=="specific" then
    local entries=buildEntries()
    local chosen=nil
    local num=tonumber(target)
    if num and num>=1 and num<=#entries then chosen=entries[num]
    else
        for _,e in ipairs(entries) do
            if e.name:lower()==target:lower() then chosen=e break end
        end
    end
    if not chosen then sprErr("No such image: "..target) return end
    showEntry(chosen)
    SB.redraw()
    return
end

-- random mode
local entries=buildEntries()
local showable,convertible,undecodable={},{},{}
for _,e in ipairs(entries) do
    if e.kind=="image" or e.kind=="anim" then showable[#showable+1]=e
    elseif e.kind=="raw" then convertible[#convertible+1]=e
    elseif e.kind=="undecodable" then undecodable[#undecodable+1]=e end
end

if #showable==0 then
    if #convertible==0 and #undecodable==0 then sprErr("No pictures.") return end
    if #convertible>0 then
        sprInfo("Found "..#convertible.." file(s) to decode:")
        for _,e in ipairs(convertible) do sprDbg("  "..e.name) end
        spr("")
        sprErr("Convert now?  (may take 1-3 min)")
        if not askYes("[Y/N]: ") then sprWarn("Cancelled.") return end
        local okN,failN=0,0
        for i,e in ipairs(convertible) do
            sprInfo("["..i.."/"..#convertible.."] decoding "..e.name.."...")
            local packed,w,h=convertOne(e)
            if packed then okN=okN+1 else failN=failN+1 end
            Y(true)
        end
        spr("")
        sprOk("Converted: "..okN.." ok, "..failN.." failed.")
        spr("Run 'pic' again.")
    end
    return
end

local e=showable[math.random(1,#showable)]
showEntry(e)
SB.redraw()
