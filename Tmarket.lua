script_name("Tmarket")
script_author("legacy.")
script_version("1.77")

local ffi = require("ffi")
local encoding = require("encoding")
local requests = require("requests")
local dlstatus = require("moonloader").download_status
local iconv = require("iconv")
local imgui = require("mimgui")
local json = require("json")

encoding.default = "CP1251"
local u8 = encoding.UTF8

local configPath = getWorkingDirectory() .. "\\config\\market_price.ini"
local updateURL = "https://raw.githubusercontent.com/Flashlavka/TMARKET/refs/heads/main/update.json"
local configURL, cachedNick = nil, nil
local window = imgui.new.bool(false)
local search = ffi.new("char[128]", "")
local items = {}

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

local cyrillicMap = {
    ["А"]="а", ["Б"]="б", ["В"]="в", ["Г"]="г", ["Д"]="д", ["Е"]="е", ["Ё"]="ё", ["Ж"]="ж", ["З"]="з", ["И"]="и",
    ["Й"]="й", ["К"]="к", ["Л"]="л", ["М"]="м", ["Н"]="н", ["О"]="о", ["П"]="п", ["Р"]="р", ["С"]="с", ["Т"]="т",
    ["У"]="у", ["Ф"]="ф", ["Х"]="х", ["Ц"]="ц", ["Ч"]="ч", ["Ш"]="ш", ["Щ"]="щ", ["Ъ"]="ъ", ["Ы"]="ы", ["Ь"]="ь",
    ["Э"]="э", ["Ю"]="ю", ["Я"]="я"
}

local function toLowerCyrillic(str)
    if not str then return "" end
    for upper, lower in pairs(cyrillicMap) do
        str = str:gsub(upper, lower)
    end
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
    local lines = {}
    for _, v in ipairs(items) do
        table.insert(lines, v.name)
        table.insert(lines, v.buy)
        table.insert(lines, v.sell)
    end
    saveToFile(configPath, table.concat(lines, "\n") .. "\n")
end

local function getNicknameSafe()
    local ok, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    return (ok and id >= 0 and id <= 1000) and sampGetPlayerNickname(id) or nil
end

local function theme()
    local style, col = imgui.GetStyle(), imgui.Col
    local clr = style.Colors
    style.WindowRounding = 4.0
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    style.ChildRounding = 2.0
    style.FrameRounding = 4.0
    style.ItemSpacing = imgui.ImVec2(10, 10)

    clr[col.Text] = imgui.ImVec4(0.95, 0.96, 0.98, 1)
    clr[col.WindowBg] = imgui.ImVec4(0.07, 0.11, 0.13, 1)
    clr[col.Button] = imgui.ImVec4(0.15, 0.20, 0.24, 1)
    clr[col.ButtonHovered] = imgui.ImVec4(0.20, 0.25, 0.29, 1)
    clr[col.ButtonActive] = clr[col.ButtonHovered]
end

-- Асинхронное обновление и загрузка
local function asyncInit()
    downloadUrlToFile(updateURL, getWorkingDirectory() .. "\\tmarket_update.json", function(_, status)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            local f = io.open(getWorkingDirectory() .. "\\tmarket_update.json", "r")
            if not f then return end
            local content = f:read("*a")
            f:close()
            os.remove(getWorkingDirectory() .. "\\tmarket_update.json")

            local j = json.decode(content)
            if not j then return end

            configURL = j.config_url

            for _, n in ipairs(j.nicknames or {}) do
                if cachedNick == n then
                    if thisScript().version ~= j.last then
                        downloadUrlToFile(j.url, thisScript().path, function(_, status2)
                            if status2 == dlstatus.STATUSEX_ENDDOWNLOAD then
                                convertAndRewrite(thisScript().path)
                                thisScript():reload()
                            end
                        end)
                    end

                    downloadUrlToFile(configURL, configPath, function(_, status3)
                        if status3 == dlstatus.STATUSEX_ENDDOWNLOAD then
                            convertAndRewrite(configPath)
                            loadData()
                            sampAddChatMessage(string.format("{80C0FF}Tmarket {6A5ACD}v%s {FFFFFF}загружен | {B0C4DE}Команда {FFFFFF}/tmarket {B0C4DE}для запуска", thisScript().version), -1)
                            sampRegisterChatCommand("tmarket", function() window[0] = not window[0] end)
                        end
                    end)

                    return
                end
            end

            sampAddChatMessage("{FF8C00}[Tmarket] {FFFFFF}У вас {FF0000}нет доступа{FFFFFF}.", -1)
        end
    end)
end

function main()
    repeat wait(0) until isSampAvailable()

    repeat
        cachedNick = getNicknameSafe()
        wait(500)
    until cachedNick

    asyncInit()
    imgui.OnInitialize(theme)

    imgui.OnFrame(function()
        return window[0] and not (isPauseMenuActive() or isGamePaused() or sampIsDialogActive())
    end, function()
        local resX, resY = getScreenResolution()
        imgui.SetNextWindowSize(imgui.ImVec2(900, 600), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))

        if not imgui.Begin(u8("legacy.-Tmarket — Таблица цен v1.3"), window) then
            imgui.End()
            return
        end

        imgui.InputTextWithHint("##search", u8("Поиск по товарам..."), search, ffi.sizeof(search))
        imgui.SameLine()
        if imgui.Button(u8("В разработке")) then
            sampAddChatMessage("{A47AFF}[Tmarket] {FFFFFF}Функция в разработке.", -1)
        end

        imgui.Separator()

        local contentWidth = imgui.GetContentRegionAvail().x
        local colWidth = (contentWidth - 20) / 3
        local filter = toLowerCyrillic(decode(search))
        local filtered = {}

        for _, v in ipairs(items) do
            if filter == "" or toLowerCyrillic(v.name):find(filter, 1, true) then
                table.insert(filtered, v)
            end
        end

        if #filtered > 0 then
            imgui.BeginChild("##scroll_vertical", imgui.ImVec2(-1, imgui.GetContentRegionAvail().y), true)

            local draw_list = imgui.GetWindowDrawList()
            local pos = imgui.GetCursorScreenPos()
            local y0, y1 = pos.y - imgui.GetStyle().ItemSpacing.y, pos.y + imgui.GetContentRegionAvail().y + imgui.GetScrollMaxY()
            local x0, x1 = pos.x + colWidth, pos.x + 2 * colWidth
            local sepColor = imgui.GetColorU32(imgui.Col.Separator)

            draw_list:AddLine(imgui.ImVec2(x0, y0), imgui.ImVec2(x0, y1), sepColor, 1)
            draw_list:AddLine(imgui.ImVec2(x1, y0), imgui.ImVec2(x1, y1), sepColor, 1)

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
                        if idx == 1 then v.name = decode(buf)
                        elseif idx == 2 then v.buy = decode(buf)
                        else v.sell = decode(buf) end
                    end
                    imgui.NextColumn()
                end
            end

            imgui.Columns(1)
            imgui.EndChild()
        else
            local avail = imgui.GetContentRegionAvail()
            local text = u8("Товары не найдены")
            local textSize = imgui.CalcTextSize(text)
            imgui.SetCursorPosX((avail.x - textSize.x) / 2)
            imgui.SetCursorPosY(avail.y / 2 - textSize.y / 2)
            imgui.Text(text)
        end

        imgui.End()
    end)

    while true do wait(0) end
end
