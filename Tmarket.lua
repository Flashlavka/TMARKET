script_name("Tmarket")
script_author("legacy")
script_version("1.3")

local ffi = require("ffi")
local encoding = require("encoding")
local imgui = require("mimgui")
local requests = require("requests")
local dlstatus = require("moonloader").download_status
local iconv = require("iconv")
local u8 = encoding.UTF8
encoding.default = "CP1251"

local search = ffi.new("char[128]", "")
local window = imgui.new.bool(false)
local configPath = getWorkingDirectory() .. "\\config\\market_price.ini"
local updateURL = "https://raw.githubusercontent.com/legacy-Chay/legacy/refs/heads/main/update.json"

local configURL, items, cachedNick = nil, {}, nil

local function utf8ToCp1251(str)
    return iconv.new("WINDOWS-1251", "UTF-8"):iconv(str)
end

local function downloadConfigFile(callback)
    if configURL then
        downloadUrlToFile(configURL, configPath, function(_, status)
            if status == dlstatus.STATUSEX_ENDDOWNLOAD and callback then
                local f = io.open(configPath, "r")
                if f then
                    local content = f:read("*a")
                    f:close()

                    local convertedContent = utf8ToCp1251(content)
                    f = io.open(configPath, "w")
                    f:write(convertedContent)
                    f:close()
                end
                callback()
            end
        end)
    end
end

local function loadData()
    items = {}
    local f = io.open(configPath, "r")
    if not f then downloadConfigFile(loadData) return end

    for line in f:lines() do
        local name = line
        local buy, sell = f:read("*l"), f:read("*l")
        if name and buy and sell then
            table.insert(items, { name = name, buy = buy, sell = sell })
        end
    end
    f:close()
end

local function saveData()
    local f = io.open(configPath, "w")
    if f then
        for _, v in ipairs(items) do
            f:write(("%s\n%s\n%s\n"):format(v.name, v.buy, v.sell))
        end
        f:close()
    end
end

local function checkNick(nick)
    local response = requests.get(updateURL)
    if response.status_code == 200 then
        local j = decodeJson(response.text)
        configURL = j.config_url or nil

        if configURL and j.nicknames and type(j.nicknames) == "table" then
            for _, n in ipairs(j.nicknames) do
                if nick == n then
                    if thisScript().version ~= j.last then
                        downloadUrlToFile(j.url, thisScript().path, function(_, status)
                            if status == dlstatus.STATUSEX_ENDDOWNLOAD then
                                local f = io.open(thisScript().path, "r")
                                local content = f:read("*a")
                                f:close()
                                local conv = utf8ToCp1251(content)
                                f = io.open(thisScript().path, "w")
                                f:write(conv)
                                f:close()
                                thisScript():reload()
                            end
                        end)
                    end
                    return true
                end
            end
        end
    end
    return false
end

local function getNicknameSafe()
    local result, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if result and id >= 0 and id <= 1000 then
        return sampGetPlayerNickname(id)
    end
    return nil
end

function main()
    repeat wait(0) until isSampAvailable()

    repeat
        cachedNick = getNicknameSafe()
        wait(500)
    until cachedNick ~= nil

    if checkNick(cachedNick) then
        downloadConfigFile(loadData)
        sampAddChatMessage("{4169E1}[Tmarket çàãğóæåí v1]{FFFFFF}. {00BFFF}Àêòèâàöèÿ:{FFFFFF} {DA70D6}/lm {FFFFFF}. Àâòîğ: {1E90FF}legacy{FFFFFF}", 0x00FF00FF)
    else
        sampAddChatMessage("{FF8C00}[Tmarket] {FFFFFF}Ó âàñ {FF0000}íåò äîñòóïà{FFFFFF}. Ïğèîáğåòèòå {32CD32}Tmarket{FFFFFF} äëÿ èñïîëüçîâàíèÿ.", 0xFFFFFF)
        sampAddChatMessage("{FF8C00}[Tmarket] {FFFFFF}Âû ìîæåòå ïğèîáğåñòè ñêğèïò - {1E90FF}https://t.me/legacy_chay{FFFFFF}", 0xFFFFFF)
        return
    end

    sampRegisterChatCommand("lm", function()
        if cachedNick and checkNick(cachedNick) then
            window[0] = not window[0]
        end
    end)

    while true do wait(0) end
end

imgui.OnFrame(
    function() return window[0] and not isPauseMenuActive() and not sampIsDialogActive() end,
    function()
        imgui.SetNextWindowSize(imgui.ImVec2(1000, 600), imgui.Cond.FirstUseEver)
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.08, 0.08, 0.15, 1.0))
        imgui.Begin(u8("Tmarket - Îíëàéí Òàáëèöà Öåí â Ñêğèïòå"), window)

        imgui.InputTextWithHint("##search", u8("Ïîèñê ïî òîâàğàì..."), search, ffi.sizeof(search))
        imgui.SameLine()
        if imgui.Button(u8("Â ğàçğàáîòêå")) then saveData() end

        imgui.Separator()
        imgui.Columns(3)
        imgui.Text(u8("Òîâàğ")); imgui.NextColumn()
        imgui.Text(u8("Ñêóïêà")); imgui.NextColumn()
        imgui.Text(u8("Ïğîäàæà")); imgui.NextColumn()
        imgui.Separator()

        local filter = u8:decode(ffi.string(search)):lower()
        for i, v in ipairs(items) do
            if filter == "" or v.name:lower():find(filter, 1, true) then
                local name_buf = ffi.new("char[128]", u8(v.name))
                local buy_buf = ffi.new("char[32]", u8(v.buy))
                local sell_buf = ffi.new("char[32]", u8(v.sell))

                if imgui.InputText("##name" .. i, name_buf, 128) then
                    v.name = u8:decode(ffi.string(name_buf))
                end
                imgui.NextColumn()
                if imgui.InputText("##buy" .. i, buy_buf, 32) then
                    v.buy = u8:decode(ffi.string(buy_buf))
                end
                imgui.NextColumn()
                if imgui.InputText("##sell" .. i, sell_buf, 32) then
                    v.sell = u8:decode(ffi.string(sell_buf))
                end
                imgui.NextColumn()
            end
        end

        imgui.Columns(1)
        imgui.End()
    end
)
