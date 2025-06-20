script_name("Tmarket")
script_author("legacy.")
script_version("1.00")

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
local jsonPath = configFolder .. "\\set.json"
local updateURL = "https://raw.githubusercontent.com/Flashlavka/TMARKET/refs/heads/main/update.json"
local configURL, cachedNick = nil, nil
local window = imgui.new.bool(false)
local search = ffi.new("char[128]", "")
local items = {}
local windowPos = {x = nil, y = nil}
local windowSize = {x = 900, y = 600}

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
        table.insert(out, v.buy)
        table.insert(out, v.sell)
    end
    saveToFile(configPath, table.concat(out, "\n") .. "\n")
end

local function asyncHttpRequest(url, callback)
    local co = coroutine.create(function()
        local r = requests.get(url)
        if r and r.status_code == 200 then
            callback(true, {status = 200, text = r.text})
        else
            callback(false, nil)
        end
    end)
    coroutine.resume(co)
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
            downloadUrlToFile(j.url, thisScript().path, function(_, status)
                if status == moonloader.download_status.STATUSEX_ENDDOWNLOAD then
                    convertAndRewrite(thisScript().path)
                    thisScript():reload()
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
    local f = io.open(jsonPath, "r")
    if not f then return end
    local content = f:read("*a")
    f:close()
    local ok, data = pcall(json.decode, content)
    if ok and data then
        if data.posX and data.posY then
            windowPos.x = data.posX
            windowPos.y = data.posY
        end
        if data.sizeX and data.sizeY then
            windowSize.x = data.sizeX
            windowSize.y = data.sizeY
        end
    end
end

local function saveWindowSettings(posX, posY, sizeX, sizeY)
    local data = {
        posX = posX,
        posY = posY,
        sizeX = sizeX,
        sizeY = sizeY,
    }
    local content = json.encode(data)
    local f = io.open(jsonPath, "w+")
    if f then
        f:write(content)
        f:close()
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
    s.ScrollbarSize = 14
    s.ScrollbarRounding = 6
    s.GrabRounding = 6
    clr[c.ScrollbarBg] = imgui.ImVec4(0.05, 0.07, 0.09, 0.6)
    clr[c.ScrollbarGrab] = imgui.ImVec4(0.30, 0.40, 0.50, 0.9)
    clr[c.ScrollbarGrabHovered] = imgui.ImVec4(0.40, 0.50, 0.60, 1)
    clr[c.ScrollbarGrabActive] = imgui.ImVec4(0.50, 0.60, 0.70, 1)
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

        imgui.InputTextWithHint("##search", u8("Поиск по товарам..."), search, ffi.sizeof(search))
        imgui.SameLine()
        if imgui.Button(u8("Обновить цены")) then
            downloadConfigFile(function()
                loadData()
                sampAddChatMessage("{A47AFF}[Tmarket] {90EE90}Цены успешно обновлены.{FFFFFF}.", -1)
            end)
        end

        imgui.Separator()
        local width = imgui.GetContentRegionAvail().x
        local colWidth = (width - 20) / 3
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
            local x0 = pos.x + colWidth
            local x1 = pos.x + 2 * colWidth
            local sepColor = imgui.GetColorU32(imgui.Col.Separator)
            local draw = imgui.GetWindowDrawList()
            draw:AddLine(imgui.ImVec2(x0, y0), imgui.ImVec2(x0, y1), sepColor, 1)
            draw:AddLine(imgui.ImVec2(x1, y0), imgui.ImVec2(x1, y1), sepColor, 1)

            imgui.Columns(3, nil, false)
            for _, header in ipairs({u8("Товар"), u8("Скупка"), u8("Продажа")}) do
                imgui.SetCursorPosX(imgui.GetCursorPosX() + (colWidth - imgui.CalcTextSize(header).x) / 2)
                imgui.Text(header)
                imgui.NextColumn()
            end

            imgui.Separator()
            local inputWidth = colWidth * 0.8
            for i, v in ipairs(filtered) do
                for idx, buf in ipairs({v.name_buf, v.buy_buf, v.sell_buf}) do
                    imgui.SetCursorPosX(imgui.GetCursorPosX() + (colWidth - inputWidth) / 2)
                    if imgui.InputText("##"..idx..i, buf, ffi.sizeof(buf)) then
                        local val = decode(buf)
                        if idx == 1 then v.name = val elseif idx == 2 then v.buy = val else v.sell = val end
                    end
                    imgui.NextColumn()
                end
            end
            imgui.Columns(1)
            imgui.EndChild()
        else
            local text_message = u8("Товары не найдены.")
            local text_size = imgui.CalcTextSize(text_message)
            local window_size = imgui.GetContentRegionAvail()
            imgui.SetCursorPosX((window_size.x - text_size.x) * 0.5)
            imgui.SetCursorPosY((window_size.y - text_size.y) * 1)
            imgui.Text(text_message)
        end

        imgui.End()
    end)
end
