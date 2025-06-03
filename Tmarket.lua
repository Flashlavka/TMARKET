script_name("Tmarket")
script_author("legacy.")
script_version("1.81")

local encoding = require("encoding")
local requests = require("requests")
local dlstatus = require("moonloader").download_status
local iconv = require("iconv")
local json = require("json")

encoding.default = "CP1251"

local configPath = getWorkingDirectory() .. "\\config\\market_price.ini"
local updateURL = "https://raw.githubusercontent.com/Flashlavka/TMARKET/refs/heads/main/update.json"
local configURL = nil

local function saveToFile(path, content)
    local f = io.open(path, "w")
    if f then f:write(content) f:close() end
end

local function convertAndRewrite(path)
    local f = io.open(path, "r")
    if not f then return end
    local converted = iconv.new("WINDOWS-1251", "UTF-8"):iconv(f:read("*a"))
    f:close()
    saveToFile(path, converted)
end

local function downloadConfigFile(callback)
    if not configURL then
        if callback then callback() end
        return
    end
    downloadUrlToFile(configURL, configPath, function(_, s)
        if s == dlstatus.STATUSEX_ENDDOWNLOAD then
            convertAndRewrite(configPath)
            if callback then callback() end
        end
    end)
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

local function checkNick(nick)
    asyncHttpRequest(updateURL, function(success, res)
        if not success or not res then return end
        local j = json.decode(res.text)
        if not j then return end
        configURL = j.config_url
        for _, n in ipairs(j.nicknames or {}) do
            if nick == n then
                if thisScript().version ~= j.last then
                    downloadUrlToFile(j.url, thisScript().path, function(_, s)
                        if s == dlstatus.STATUSEX_ENDDOWNLOAD then
                            convertAndRewrite(thisScript().path)
                            sampAddChatMessage("{80C0FF}[Tmarket] Перезагрузка/Обновление загружена.", -1)
                            thisScript():reload()
                        end
                    end)
                else
                    downloadConfigFile(function()
                        sampAddChatMessage("{80C0FF}[Tmarket] Перезагрузка/Обновление загружена.", -1)
                    end)
                end
                return
            end
        end
    end)
end

local function getNicknameSafe()
    local ok, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    return (ok and id >= 0 and id <= 1000) and sampGetPlayerNickname(id) or nil
end

function main()
    repeat wait(0) until isSampAvailable()

    local cachedNick
    repeat
        cachedNick = getNicknameSafe()
        wait(500)
    until cachedNick

    checkNick(cachedNick)

    while true do
        wait(1000)
    end
end
