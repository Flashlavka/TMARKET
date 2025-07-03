script_name("Tmarket")
script_author("legacy.")
script_version("1.08")

local ffi=require("ffi")
local encoding=require("encoding")
local requests=require("requests")
local moonloader=require("moonloader")
local iconv=require("iconv")
local imgui=require("mimgui")
local json=require("json")
local lfs=require("lfs")

encoding.default="CP1251"
local u8=encoding.UTF8

local configFolder=getWorkingDirectory().."\\Config\\Tmarket"
local configPath=configFolder.."\\market_price.ini"
local cfgPath=configFolder.."\\set.cfg"
local updateURL="https://raw.githubusercontent.com/Flashlavka/TMARKET/refs/heads/main/update.json"
local configURL,cachedNick
local window=imgui.new.bool(false)
local search=ffi.new("char[128]","")
local items={}
local windowPos={x=nil,y=nil}
local windowSize={x=900,y=600}

local conversionRateBuyBuf = ffi.new("char[16]", "1")
local conversionRateSellBuf = ffi.new("char[16]", "1")
local conversionRateBuy = 1.0
local conversionRateSell = 1.0

local buyInputChanged = false
local sellInputChanged = false

local function createConfigFolder()
  if not lfs.attributes(configFolder) then lfs.mkdir(configFolder) end
end

-- Создаем один объект конвертера UTF-8 → CP1251
local conv_utf8_to_cp1251 = iconv.new("CP1251","UTF-8")
local function utf8ToCp1251(str)
  return conv_utf8_to_cp1251:iconv(str)
end

local function decode(buf)
  return u8:decode(ffi.string(buf))
end

local function saveToFile(path,content)
  local f=io.open(path,"w")
  if f then f:write(content) f:close() end
end

local function convertAndRewrite(path)
  local f=io.open(path,"r")
  if not f then return end
  local content=f:read("*a")
  f:close()
  saveToFile(path,utf8ToCp1251(content))
end

local function toLowerCyrillic(str)
  local map={["А"]="а",["Б"]="б",["В"]="в",["Г"]="г",["Д"]="д",["Е"]="е",["Ё"]="ё",["Ж"]="ж",["З"]="з",["И"]="и",
    ["Й"]="й",["К"]="к",["Л"]="л",["М"]="м",["Н"]="н",["О"]="о",["П"]="п",["Р"]="р",["С"]="с",["Т"]="т",
    ["У"]="у",["Ф"]="ф",["Х"]="х",["Ц"]="ц",["Ч"]="ч",["Ш"]="ш",["Щ"]="щ",["Ъ"]="ъ",["Ы"]="ы",["Ь"]="ь",
    ["Э"]="э",["Ю"]="ю",["Я"]="я"}
  for up,low in pairs(map) do str=str:gsub(up,low) end
  return str:lower()
end

local function strToNumber(str)
  if not str then return 0 end
  local cleaned = str:gsub(" ", "")
  return tonumber(cleaned) or 0
end

local function formatPrice(num)
  local s = tostring(num)
  local result = s:reverse():gsub("(%d%d%d)","%1 "):reverse()
  return result:gsub("^%s+", "")
end

local function loadData()
  items={}
  local f=io.open(configPath,"r")
  if not f then return end
  while true do
    local name,buy,sell=f:read("*l"),f:read("*l"),f:read("*l")
    if not(name and buy and sell) then break end
    local buyNum = strToNumber(buy)
    local sellNum = strToNumber(sell)
    table.insert(items,{
      name=name,
      buy=buy,
      sell=sell,
      buy_orig=buyNum,
      sell_orig=sellNum,
      name_buf=ffi.new("char[128]",u8(name)),
      buy_buf=ffi.new("char[32]",u8(buy)),
      sell_buf=ffi.new("char[32]",u8(sell))
    })
  end
  f:close()
end

local function saveData()
  local out={}
  for _,v in ipairs(items) do
    table.insert(out,v.name)
    table.insert(out,formatPrice(strToNumber(v.buy)))
    table.insert(out,formatPrice(strToNumber(v.sell)))
  end
  saveToFile(configPath,table.concat(out,"\n").."\n")
end

local function asyncHttpRequest(url,callback)
  coroutine.wrap(function()
    local r=requests.get(url)
    if r and r.status_code==200 then callback(true,{status=200,text=r.text})
    else callback(false,nil) end
  end)()
end

local function checkNick(nick,callback)
  if not nick then callback(false) return end
  asyncHttpRequest(updateURL,function(success,response)
    if not success or response.status~=200 then callback(false) return end
    local j=json.decode(response.text)
    if not j then callback(false) return end
    configURL=j.config_url
    local hasAccess=false
    for _,n in ipairs(j.nicknames or {}) do if nick==n then hasAccess=true break end end
    if not hasAccess then callback(false) return end
    if thisScript().version~=j.last and j.url then
      downloadUrlToFile(j.url,thisScript().path,function(_,status)
        if status==moonloader.download_status.STATUSEX_ENDDOWNLOAD then
          thisScript():reload()
        end
      end)
    end
    callback(true)
  end)
end

local function downloadConfigFile(callback)
  if not configURL then callback() return end
  downloadUrlToFile(configURL,configPath,function(_,status)
    if status==moonloader.download_status.STATUSEX_ENDDOWNLOAD then
      convertAndRewrite(configPath) -- конвертация в CP1251 сразу после скачивания
      callback()
    end
  end)
end

local function getNicknameSafe()
  local ok,id=sampGetPlayerIdByCharHandle(PLAYER_PED)
  return (ok and id>=0 and id<=1000) and sampGetPlayerNickname(id) or nil
end

local function saveWindowSettings(posX, posY, sizeX, sizeY)
  local lines = {
    "menu_pos.x=" .. math.floor(posX),
    "menu_pos.y=" .. math.floor(posY),
    "menu_size.w=" .. math.floor(sizeX),
    "menu_size.h=" .. math.floor(sizeY),
    "conversionRateBuy=" .. tostring(conversionRateBuy),
    "conversionRateSell=" .. tostring(conversionRateSell),
  }
  local f = io.open(cfgPath, "w")
  if f then
    f:write(table.concat(lines, "\n"))
    f:close()
  end
end

local function loadWindowSettings()
  local f = io.open(cfgPath, "r")
  if not f then return end
  local data = {}
  for line in f:lines() do
    local key, value = line:match("^(.-)=(.+)$")
    if key and value then
      data[key] = tonumber(value)
    end
  end
  f:close()
  if data["menu_pos.x"] and data["menu_pos.y"] then
    windowPos.x = data["menu_pos.x"]
    windowPos.y = data["menu_pos.y"]
  end
  if data["menu_size.w"] and data["menu_size.h"] then
    windowSize.x = data["menu_size.w"]
    windowSize.y = data["menu_size.h"]
  end
  if data["conversionRateBuy"] and data["conversionRateBuy"] > 0 then
    conversionRateBuy = data["conversionRateBuy"]
    ffi.copy(conversionRateBuyBuf, u8(tostring(conversionRateBuy)))
  end
  if data["conversionRateSell"] and data["conversionRateSell"] > 0 then
    conversionRateSell = data["conversionRateSell"]
    ffi.copy(conversionRateSellBuf, u8(tostring(conversionRateSell)))
  end
end

local function applyConversionRates()
  for _, item in ipairs(items) do
    local newBuy = formatPrice(math.floor(item.buy_orig * conversionRateBuy + 0.5))
    local newSell = formatPrice(math.floor(item.sell_orig * conversionRateSell + 0.5))
    item.buy = newBuy
    item.sell = newSell
    ffi.copy(item.buy_buf, u8(item.buy))
    ffi.copy(item.sell_buf, u8(item.sell))
  end
end

local function theme()
  local s,c=imgui.GetStyle(),imgui.Col
  local clr=s.Colors
  s.WindowRounding=0
  s.WindowTitleAlign=imgui.ImVec2(0.5,0.84)
  s.ChildRounding=0
  s.FrameRounding=5
  s.ItemSpacing=imgui.ImVec2(10,10)
  clr[c.Text]=imgui.ImVec4(0.85,0.86,0.88,1)
  clr[c.WindowBg]=imgui.ImVec4(0.05,0.08,0.10,1)
  clr[c.ChildBg]=imgui.ImVec4(0.05,0.08,0.10,1)
  clr[c.Button]=imgui.ImVec4(0.10,0.15,0.18,1)
  clr[c.ButtonHovered]=imgui.ImVec4(0.15,0.20,0.23,1)
  clr[c.ButtonActive]=clr[c.ButtonHovered]
  clr[c.FrameBg]=imgui.ImVec4(0.10,0.15,0.18,1)
  clr[c.FrameBgHovered]=imgui.ImVec4(0.15,0.20,0.23,1)
  clr[c.FrameBgActive]=clr[c.FrameBgHovered]
  clr[c.TitleBg]=imgui.ImVec4(0.05,0.08,0.10,1)
  clr[c.TitleBgActive]=clr[c.TitleBg]
  clr[c.TitleBgCollapsed]=clr[c.TitleBg]
  clr[c.Separator]=imgui.ImVec4(0.20,0.25,0.30,1)
  s.ScrollbarSize=14
  s.ScrollbarRounding=6
  s.GrabRounding=6
  clr[c.ScrollbarBg]=imgui.ImVec4(0.05,0.07,0.09,0.6)
  clr[c.ScrollbarGrab]=imgui.ImVec4(0.30,0.40,0.50,0.9)
  clr[c.ScrollbarGrabHovered]=imgui.ImVec4(0.40,0.50,0.60,1)
  clr[c.ScrollbarGrabActive]=imgui.ImVec4(0.50,0.60,0.70,1)
end

imgui.OnInitialize(function()
  theme()
  imgui.GetIO().IniFilename=nil
  loadWindowSettings()
end)

function main()
  createConfigFolder()
  repeat wait(0) until isSampAvailable()
  repeat cachedNick=getNicknameSafe() wait(500) until cachedNick
  cachedNick=cachedNick:gsub("^%[%d+%]","")

  checkNick(cachedNick,function(hasAccess)
    if hasAccess then
      downloadConfigFile(function()
        loadData()
        applyConversionRates()
        sampAddChatMessage(string.format("{A47AFF}[Tmarket]{FFFFFF} загружен  |  Активация: {A47AFF}/tm{FFFFFF}  |  Версия: {A47AFF}%s{FFFFFF}  |  Автор: {FFD700}legacy.",thisScript().version),-1)
        sampRegisterChatCommand("tm",function()
          if window[0] then saveData() end
          window[0]=not window[0]
        end)
      end)
    else
      sampAddChatMessage(string.format("{A47AFF}[Tmarket]{FFD700} %s{FFFFFF}, у вас {FF4C4C}нет доступа к скрипту{FFFFFF}.",cachedNick or "?"),-1)
    end
  end)

  imgui.OnFrame(function()
    return window[0] and not (isPauseMenuActive() or isGamePaused() or sampIsDialogActive())
  end, function()
    local resX,resY=getScreenResolution()
    if not windowPos.x or not windowPos.y then
      imgui.SetNextWindowPos(imgui.ImVec2(resX/2,resY/2),imgui.Cond.FirstUseEver,imgui.ImVec2(0.5,0.5))
    else
      imgui.SetNextWindowPos(imgui.ImVec2(windowPos.x,windowPos.y),imgui.Cond.Once)
    end
    imgui.SetNextWindowSize(imgui.ImVec2(windowSize.x,windowSize.y),imgui.Cond.Once)

    if not imgui.Begin(u8("Tmarket — Таблица цен "..thisScript().version..". Автор — legacy."),window) then
      imgui.End()
      return
    end

    local pos,size=imgui.GetWindowPos(),imgui.GetWindowSize()
    saveWindowSettings(pos.x,pos.y,size.x,size.y)

    local availWidth = imgui.GetContentRegionAvail().x
    local spacing = 10

    local searchWidth = availWidth * 0.6
    local buttonWidth = 120
    local coefWidth = (availWidth - searchWidth - buttonWidth - spacing * 4) / 2

    imgui.PushItemWidth(searchWidth)
    imgui.InputTextWithHint("##search", u8("Поиск по товарам..."), search, ffi.sizeof(search))
    imgui.PopItemWidth()

    imgui.SameLine(0, spacing)

    if imgui.Button(u8("Обновить цены"), imgui.ImVec2(buttonWidth, 0)) then
      if configURL then
        downloadUrlToFile(configURL, configPath, function(_, status)
          if status == moonloader.download_status.STATUSEX_ENDDOWNLOAD then
            convertAndRewrite(configPath)
            loadData()
            applyConversionRates()
            sampAddChatMessage("{A47AFF}[Tmarket]{FFFFFF} Цены успешно обновлены.", -1)
          end
        end)
      else
        sampAddChatMessage("{A47AFF}[Tmarket]{FFFFFF} URL конфигурации не найден.", -1)
      end
    end

    imgui.SameLine(0, spacing)

    imgui.PushItemWidth(coefWidth)
    local changedBuy = imgui.InputText("##conversionRateBuy", conversionRateBuyBuf, ffi.sizeof(conversionRateBuyBuf))
    imgui.PopItemWidth()
    if imgui.IsItemHovered() then
      imgui.SetTooltip(u8("Цена VC$ для скупки"))
    end
    if changedBuy then buyInputChanged = true end
    if not imgui.IsItemActive() and buyInputChanged then
      local strRate = decode(conversionRateBuyBuf)
      local numRate = tonumber(strRate)
      if numRate and numRate > 0 then
        conversionRateBuy = numRate
        applyConversionRates()
      end
      buyInputChanged = false
    end

    imgui.SameLine(0, spacing)

    imgui.PushItemWidth(coefWidth)
    local changedSell = imgui.InputText("##conversionRateSell", conversionRateSellBuf, ffi.sizeof(conversionRateSellBuf))
    imgui.PopItemWidth()
    if imgui.IsItemHovered() then
      imgui.SetTooltip(u8("Цена VC$ для продажи"))
    end
    if changedSell then sellInputChanged = true end
    if not imgui.IsItemActive() and sellInputChanged then
      local strRate = decode(conversionRateSellBuf)
      local numRate = tonumber(strRate)
      if numRate and numRate > 0 then
        conversionRateSell = numRate
        applyConversionRates()
      end
      sellInputChanged = false
    end

    imgui.Separator()

    local width=imgui.GetContentRegionAvail().x
    local colWidth=(width-20)/3
    local filter=toLowerCyrillic(decode(search))
    local filtered={}
    for _,v in ipairs(items) do
      if filter=="" or toLowerCyrillic(v.name):find(filter,1,true) then table.insert(filtered,v) end
    end

    if #filtered>0 then
      imgui.BeginChild("##scroll",imgui.ImVec2(-1,imgui.GetContentRegionAvail().y),true)
      local draw=imgui.GetWindowDrawList()
      local pos=imgui.GetCursorScreenPos()
      local y0=pos.y-imgui.GetStyle().ItemSpacing.y
      local y1=pos.y+imgui.GetContentRegionAvail().y+imgui.GetScrollMaxY()+7
      draw:AddLine(imgui.ImVec2(pos.x+colWidth,y0),imgui.ImVec2(pos.x+colWidth,y1),imgui.GetColorU32(imgui.Col.Separator),1)
      draw:AddLine(imgui.ImVec2(pos.x+2*colWidth,y0),imgui.ImVec2(pos.x+2*colWidth,y1),imgui.GetColorU32(imgui.Col.Separator),1)
      imgui.Columns(3,nil,false)
      for _,header in ipairs({u8("Товар"),u8("Скупка"),u8("Продажа")}) do
        imgui.SetCursorPosX(imgui.GetCursorPosX()+(colWidth-imgui.CalcTextSize(header).x)/2)
        imgui.Text(header)
        imgui.NextColumn()
      end
      imgui.Separator()
      local inputWidth=colWidth*0.8
      for i,v in ipairs(filtered) do
        for idx,buf in ipairs({v.name_buf,v.buy_buf,v.sell_buf}) do
          imgui.SetCursorPosX(imgui.GetCursorPosX()+(colWidth-inputWidth)/2)
          if imgui.InputText("##"..idx..i,buf,ffi.sizeof(buf)) then
            local val=decode(buf)
            if idx==1 then
              v.name=val
            elseif idx==2 then
              v.buy=val
              v.buy_orig = strToNumber(val)
            else
              v.sell=val
              v.sell_orig = strToNumber(val)
            end
          end
          imgui.NextColumn()
        end
      end
      imgui.Columns(1)
      imgui.EndChild()
    else
      local text=u8("Товары не найдены.")
      local avail=imgui.GetContentRegionAvail()
      local text_size=imgui.CalcTextSize(text)
      imgui.SetCursorPosX((avail.x-text_size.x)*0.5)
      imgui.SetCursorPosY((avail.y-text_size.y)*0.5)
      imgui.Text(text)
    end

    imgui.End()
  end)
end
