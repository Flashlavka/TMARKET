script_name("Tmarket")
script_author("legacy.")
script_version("1.02")

local ffi = require("ffi")
local encoding = require("encoding")
local requests = require("requests")
local moonloader = require("moonloader")
local iconv = require("iconv")
local imgui = require("mimgui")
local json = require("json")
local lfs = require("lfs")

encoding.default = "CP1251"
local u8 = encoding.UTF8

local configFolder = getWorkingDirectory() .. "\\Config\\Tmarket"
local configPath = configFolder .. "\\market_price.ini"
local cfgPath = configFolder .. "\\set.cfg"
local updateURL = "https://raw.githubusercontent.com/Flashlavka/TMARKET/refs/heads/main/update.json"
local configURL, cachedNick = nil, nil
local window = imgui.new.bool(false)
local search = ffi.new("char[128]", "")
local items = {}
local windowPos = {x = nil, y = nil}
local windowSize = {x = 900, y = 600}

local conversionRateBuy = 1.0
local conversionRateSell = 1.0

local conversionRateBuyBuf = ffi.new("char[16]", "1")
local conversionRateSellBuf = ffi.new("char[16]", "1")

local buyInputChanged = false
local sellInputChanged = false

local lastWindowSize = {x = windowSize.x, y = windowSize.y}

local function createConfigFolder()
    local attr = lfs.attributes(configFolder)
    if not attr then
        lfs.mkdir(configFolder)
    end
end

local function utf8ToCp1251(str)
    return iconv.new("WINDOWS-1251", "UTF-8"):iconv(str)
end

local function decode(buf)
    return u8:decode(ffi.string(buf))
end

local function saveToFile(path, content)
    local f = io.open(path, "w")
    if f then f:write(content) f:close() end
end

local function convertAndRewrite(path)
    local f = io.open(path, "r")
    if not f then return end
    local converted = utf8ToCp1251(f:read("*a"))
    f:close()
    saveToFile(path, converted)
end

local function toLowerCyrillic(str)
    local map = {
        ["А"]="а",["Б"]="б",["В"]="в",["Г"]="г",["Д"]="д",["Е"]="е",["Ё"]="ё",["Ж"]="ж",["З"]="з",["И"]="и",
        ["Й"]="й",["К"]="к",["Л"]="л",["М"]="м",["Н"]="н",["О"]="о",["П"]="п",["Р"]="р",["С"]="с",["Т"]="т",
        ["У"]="у",["Ф"]="ф",["Х"]="х",["Ц"]="ц",["Ч"]="ч",["Ш"]="ш",["Щ"]="щ",["Ъ"]="ъ",["Ы"]="ы",["Ь"]="ь",
        ["Э"]="э",["Ю"]="ю",["Я"]="я"
    }
    for up, low in pairs(map) do str = str:gsub(up, low) end
    return str:lower()
end

local function loadData()
    items = {}
    local f = io.open(configPath, "r")
    if not f then return end
    while true do
        local name, buy, sell = f:read("*l"), f:read("*l"), f:read("*l")
        if not (name and buy and sell) then break end
        table.insert(items, {
            name = name,
            buy_orig = buy,
            sell_orig = sell,
            buy = buy,
            sell = sell,
            name_buf = ffi.new("char[128]", u8(name)),
            buy_buf = ffi.new("char[32]", u8(buy)),
            sell_buf = ffi.new("char[32]", u8(sell))
        })
    end
    f:close()
end

local function saveData()
    local out = {}
    for _, v in ipairs(items) do
        table.insert(out, v.name)
        table.insert(out, v.buy_orig)
        table.insert(out, v.sell_orig)
    end
    saveToFile(configPath, table.concat(out, "\n") .. "\n")
end

local function asyncHttpRequest(url, callback)
    local thread = require('effil').thread(function(url)
        local requests = require('requests')
        local ok, res = pcall(requests.get, url)
        if ok and res.status_code == 200 then
            return true, res.text
        else
            return false, nil
        end
    end)(url)

    lua_thread.create(function()
        while true do
            local status = thread:status()
            if status == 'completed' then
                local success, text = thread:get()
                callback(success, {status = success and 200 or 0, text = text})
                break
            elseif status == 'canceled' then
                callback(false, nil)
                break
            end
            wait(0)
        end
    end)
end


local function checkNick(nick, callback)
    if not nick then callback(false) return end
    asyncHttpRequest(updateURL, function(success, response)
        if not success or response.status ~= 200 then callback(false) return end
        local j = json.decode(response.text)
        if not j then callback(false) return end
        configURL = j.config_url
        local hasAccess = false
        for _, n in ipairs(j.nicknames or {}) do
            if nick == n then hasAccess = true break end
        end
        if not hasAccess then callback(false) return end
    if thisScript().version ~= j.last and j.url then
    asyncHttpRequest(j.url, function(success, response)
        if success and response.status == 200 then
            local file = io.open(thisScript().path, 'wb')
            if file then
                file:write(response.text)
                file:close()
                convertAndRewrite(thisScript().path)
                sampAddChatMessage("{A47AFF}[Tmarket] {90EE90}Скрипт обновлён. Перезагрузка...", -1)
                thisScript():reload()
            else
                sampAddChatMessage("{A47AFF}[Tmarket] {FF4C4C}Ошибка записи обновления!", -1)
            end
        else
            sampAddChatMessage("{A47AFF}[Tmarket] {FF4C4C}Ошибка загрузки обновления!", -1)
        end
    end)
end
        callback(true)
    end)
end

local function downloadConfigFile(callback)
    if not configURL then callback() return end
    downloadUrlToFile(configURL, configPath, function(_, status)
        if status == moonloader.download_status.STATUSEX_ENDDOWNLOAD then
            convertAndRewrite(configPath)
            callback()
        end
    end)
end

local function getNicknameSafe()
    local ok, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    return (ok and id >= 0 and id <= 1000) and sampGetPlayerNickname(id) or nil
end

local function loadWindowSettings()
    local f = io.open(cfgPath, "r")
    if not f then return end
    for line in f:lines() do
        local key, value = line:match("^(%w+)%s*=%s*(%-?%d+%.?%d*)$")
        if key and value then
            local num = tonumber(value)
            if key == "posX" then windowPos.x = num
            elseif key == "posY" then windowPos.y = num
            elseif key == "sizeX" then windowSize.x = num
            elseif key == "sizeY" then windowSize.y = num
            elseif key == "conversionRateBuy" then
                conversionRateBuy = num
                ffi.copy(conversionRateBuyBuf, u8(tostring(conversionRateBuy)))
            elseif key == "conversionRateSell" then
                conversionRateSell = num
                ffi.copy(conversionRateSellBuf, u8(tostring(conversionRateSell)))
            end
        end
    end
    f:close()
end

local function saveWindowSettings(posX, posY, sizeX, sizeY)
    local f = io.open(cfgPath, "w+")
    if not f then return end
    f:write(string.format("posX=%d\nposY=%d\nsizeX=%d\nsizeY=%d\n", posX, posY, sizeX, sizeY))
    f:write(string.format("conversionRateBuy=%s\n", tostring(conversionRateBuy)))
    f:write(string.format("conversionRateSell=%s\n", tostring(conversionRateSell)))
    f:close()
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

local function applyConversionRates()
    for _, item in ipairs(items) do
        local buyNum = strToNumber(item.buy_orig)
        local sellNum = strToNumber(item.sell_orig)
        local newBuy = formatPrice(math.floor(buyNum * conversionRateBuy + 0.5))
        local newSell = formatPrice(math.floor(sellNum * conversionRateSell + 0.5))
        ffi.copy(item.buy_buf, u8(newBuy))
        ffi.copy(item.sell_buf, u8(newSell))
    end
end

local function theme()
    local s, c = imgui.GetStyle(), imgui.Col
    local clr = s.Colors

    s.WindowRounding = 0
    s.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    s.ChildRounding = 0
    s.FrameRounding = 5.0
    s.ItemSpacing = imgui.ImVec2(10, 10)

    clr[c.Text] = imgui.ImVec4(0.85, 0.86, 0.88, 1)
    clr[c.WindowBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.ChildBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.Button] = imgui.ImVec4(0.10, 0.15, 0.18, 1)
    clr[c.ButtonHovered] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[c.ButtonActive] = clr[c.ButtonHovered]
    clr[c.FrameBg] = imgui.ImVec4(0.10, 0.15, 0.18, 1)
    clr[c.FrameBgHovered] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[c.FrameBgActive] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[c.TitleBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.TitleBgActive] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.TitleBgCollapsed] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[c.Separator] = imgui.ImVec4(0.20, 0.25, 0.30, 1)

    s.ScrollbarSize = 18
    s.ScrollbarRounding = 0
    s.GrabRounding = 0
    s.GrabMinSize = 38

    clr[c.ScrollbarBg] = imgui.ImVec4(0.04, 0.06, 0.07, 0.8)
    clr[c.ScrollbarGrab] = imgui.ImVec4(0.15, 0.15, 0.18, 1.0)
    clr[c.ScrollbarGrabHovered] = imgui.ImVec4(0.25, 0.25, 0.28, 1.0)
    clr[c.ScrollbarGrabActive] = imgui.ImVec4(0.35, 0.35, 0.38, 1.0)
end


function main()
    createConfigFolder()
    repeat wait(0) until isSampAvailable()
    repeat cachedNick = getNicknameSafe() wait(500) until cachedNick
    cachedNick = cachedNick:gsub("^%[%d+%]", "")

    checkNick(cachedNick, function(hasAccess)
        if hasAccess then
            downloadConfigFile(function()
                loadData()
                applyConversionRates()
                sampAddChatMessage(string.format("{A47AFF}[Tmarket]{FFFFFF} загружен  |  Активация: {A47AFF}/tm{FFFFFF}  |  Версия: {A47AFF}v%s{FFFFFF}  |  Автор: {FFD700}legacy.", thisScript().version), -1)
                sampRegisterChatCommand("tm", function()
                    if window[0] then saveData() end
                    window[0] = not window[0]
                end)
            end)
        else
            sampAddChatMessage(string.format("{A47AFF}[Tmarket]{FFD700} %s{FFFFFF}, у вас {FF4C4C}нет доступа к скрипту{FFFFFF}.", cachedNick or "?"), -1)
        end
    end)

    loadWindowSettings()

    imgui.OnInitialize(function()
        theme()
        imgui.GetIO().IniFilename = nil
    end)

    imgui.OnFrame(function()
        return window[0] and not (isPauseMenuActive() or isGamePaused() or sampIsDialogActive())
    end, function()
        local resX, resY = getScreenResolution()
        if not windowPos.x or not windowPos.y then
            imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        else
            imgui.SetNextWindowPos(imgui.ImVec2(windowPos.x, windowPos.y), imgui.Cond.Once)
        end
        imgui.SetNextWindowSize(imgui.ImVec2(windowSize.x, windowSize.y), imgui.Cond.Once)

        if not imgui.Begin(u8("Tmarket — Таблица цен v" .. thisScript().version .. ". Автор — legacy."), window) then
            imgui.End()
            return
        end

        local pos = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()
        saveWindowSettings(pos.x, pos.y, size.x, size.y)

        if lastWindowSize.x ~= size.x or lastWindowSize.y ~= size.y then
            lastWindowSize.x = size.x
            lastWindowSize.y = size.y
        end

        local fullWidth = size.x - 40
        local searchWidth = fullWidth * 0.52
        local buttonWidth = fullWidth * 0.18
        local inputWidth = fullWidth * 0.10
        local columnWidth = fullWidth / 3
        local inputFieldWidth = columnWidth * 0.7

        imgui.PushItemWidth(searchWidth)
        imgui.InputTextWithHint("##search", u8("Поиск по товарам..."), search, ffi.sizeof(search))
        imgui.PopItemWidth()

        imgui.SameLine()
        if imgui.Button(u8("Обновить цены"), imgui.ImVec2(buttonWidth, 0)) then
            downloadConfigFile(function()
                loadData()
                applyConversionRates()
                sampAddChatMessage("{A47AFF}[Tmarket] {90EE90}Цены успешно обновлены.{FFFFFF}.", -1)
            end)
        end

        imgui.SameLine()
        imgui.PushItemWidth(inputWidth)
        local changedBuy = imgui.InputText("##conversionRateBuy", conversionRateBuyBuf, ffi.sizeof(conversionRateBuyBuf))
        imgui.PopItemWidth()
        if imgui.IsItemHovered() then
            imgui.SetTooltip(u8("Курс VC$ для цены скупки"))
        end
        if changedBuy then buyInputChanged = true end
        if not imgui.IsItemActive() and buyInputChanged then
            local val = decode(conversionRateBuyBuf)
            local num = tonumber(val)
            if num and num > 0 then
                conversionRateBuy = num
                applyConversionRates()
            end
            buyInputChanged = false
        end

        imgui.SameLine()
        imgui.PushItemWidth(inputWidth)
        local changedSell = imgui.InputText("##conversionRateSell", conversionRateSellBuf, ffi.sizeof(conversionRateSellBuf))
        imgui.PopItemWidth()
        if imgui.IsItemHovered() then
            imgui.SetTooltip(u8("Курс VC$ для цены продажи"))
        end
        if changedSell then sellInputChanged = true end
        if not imgui.IsItemActive() and sellInputChanged then
            local val = decode(conversionRateSellBuf)
            local num = tonumber(val)
            if num and num > 0 then
                conversionRateSell = num
                applyConversionRates()
            end
            sellInputChanged = false
        end

        imgui.Separator()

        local filter = toLowerCyrillic(decode(search))
        local filtered = {}

        for _, v in ipairs(items) do
            if filter == "" or toLowerCyrillic(v.name):find(filter, 1, true) then
                table.insert(filtered, v)
            end
        end

        if #filtered > 0 then
            imgui.BeginChild("##scroll", imgui.ImVec2(-1, imgui.GetContentRegionAvail().y), true)

            local pos = imgui.GetCursorScreenPos()
            local y0 = pos.y - imgui.GetStyle().ItemSpacing.y
            local y1 = pos.y + imgui.GetContentRegionAvail().y + imgui.GetScrollMaxY() + 7
            local x0 = pos.x + columnWidth
            local x1 = pos.x + 2 * columnWidth
            local sepColor = imgui.GetColorU32(imgui.Col.Separator)
            local draw = imgui.GetWindowDrawList()
            draw:AddLine(imgui.ImVec2(x0, y0), imgui.ImVec2(x0, y1), sepColor, 1)
            draw:AddLine(imgui.ImVec2(x1, y0), imgui.ImVec2(x1, y1), sepColor, 1)

            imgui.Columns(3, nil, false)

            local headers = {u8("Товар"), u8("Скупка"), u8("Продажа")}
            for _, header in ipairs(headers) do
                local textSize = imgui.CalcTextSize(header)
                local cursorX = imgui.GetCursorPosX()
                imgui.SetCursorPosX(cursorX + (columnWidth - textSize.x) / 2)
                imgui.Text(header)
                imgui.NextColumn()
            end

            imgui.Separator()

            for i, v in ipairs(filtered) do
                imgui.PushItemWidth(inputFieldWidth)

                local cursorStart = imgui.GetCursorPosX()
                imgui.SetCursorPosX(cursorStart + (columnWidth - inputFieldWidth) / 2)
                if imgui.InputText("##name" .. i, v.name_buf, ffi.sizeof(v.name_buf)) then
                    v.name = decode(v.name_buf)
                end
                imgui.NextColumn()

                cursorStart = imgui.GetCursorPosX()
                imgui.SetCursorPosX(cursorStart + (columnWidth - inputFieldWidth) / 2)
                if imgui.InputText("##buy" .. i, v.buy_buf, ffi.sizeof(v.buy_buf)) then
                    v.buy = decode(v.buy_buf)
                    v.buy_orig = v.buy
                end
                imgui.NextColumn()

                cursorStart = imgui.GetCursorPosX()
                imgui.SetCursorPosX(cursorStart + (columnWidth - inputFieldWidth) / 2)
                if imgui.InputText("##sell" .. i, v.sell_buf, ffi.sizeof(v.sell_buf)) then
                    v.sell = decode(v.sell_buf)
                    v.sell_orig = v.sell
                end
                imgui.NextColumn()

                imgui.PopItemWidth()
            end

            imgui.EndChild()
        else
            local center = imgui.GetWindowContentRegionWidth() / 2
            imgui.SetCursorPosX(center - 70)
            imgui.Text(u8("Error по вашему запросу ничего не найден :("))
        end

        imgui.End()
    end)
end
