-- Индикаторы связи bortd с приборами.
--
-- Список приборов берётся из конфигурации bortd (~/.bort/bortdrc): все
-- устройства с источником tcp://, rfc2217:// или serial://. Файл
-- перечитывается при изменении, поэтому индикаторы всегда соответствуют
-- тому, что настроено в bortcfg.
--
-- ВАЖНО: индикаторы НИКОГДА не подключаются к приборам сами. Пробные
-- подключения (nc -z, echo >/dev/tcp) отбирали единственное соединение
-- преобразователя Ethernet->COM у bortd или писали байты в прибор и портили
-- данные. Состояние берётся пассивно (link-status.sh): соединения и открытые
-- порты самого процесса bortd.
--   зелёный - bortd подключён к прибору и данные идут;
--   жёлтый  - соединение есть, но данных нет дольше stale_after секунд;
--             для COM-портов зелёный означает лишь, что порт открыт bortd;
--   красный - bortd к прибору не подключён;
--   серый   - bortd не запущен.
--
-- Подписи можно задать в ~/.config/navdat/devices.lua:
--   return { ["192.168.1.162:4001"] = "RS61", ["/dev/ttyUSB0"] = "MAG" }

local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

local connection_status = {}

local interval = 2       -- период опроса, с
local stale_after = 5    -- сколько секунд без новых байт считать "данных нет"
local bortdrc = os.getenv("HOME") .. "/.bort/bortdrc"
local helper = gears.filesystem.get_configuration_dir() .. "link-status.sh"

local state_text = {
    net = {
        ok    = "bortd подключён, данные идут",
        stale = "bortd подключён, данных нет",
        down  = "bortd не подключён",
        off   = "bortd не запущен",
    },
    tty = {
        ok    = "порт открыт bortd (поток данных не контролируется)",
        down  = "порт не открыт bortd",
        off   = "bortd не запущен",
    },
}

local colors = {
    ok    = "#006600",
    stale = "#aa8800",
    down  = "#aa0000",
    off   = "#555555",
}

-- короткие подписи по типу устройства bortd
local short_names = {
    amaster = "AM", jps = "JPS", novatel = "NV", arrow = "ARR", em4h = "EM4H",
    gtmag = "MG", geoscan = "GEO", rs50x = "RS", grs410 = "GRS", gsa2000 = "GSA",
    ["parsek-adc"] = "PRS", gtadc = "ADC", d5000adc = "ADC", e502 = "E502",
    ffra = "FFRA", smra = "SMRA", equator = "EQ", sp4 = "SP4", tvisor = "TV",
    tvnew = "TV", mp719 = "MP", adis16365 = "IMU",
}

local function load_labels()
    local path = gears.filesystem.get_xdg_config_home() .. "navdat/devices.lua"
    if gears.filesystem.file_readable(path) then
        local ok, map = pcall(dofile, path)
        if ok and type(map) == "table" then return map end
        print("connection_status: bad " .. path .. ": " .. tostring(map))
    end
    return {}
end

-- "tcp://h:p", "rfc2217://h:p/9600,8,n,1", "serial:///dev/ttyS0,115200,..."
-- -> kind ("net"/"tty"), key (host:port или путь к устройству)
local function parse_source(src)
    local hostport = src:match("^tcp://([^/%s]+)") or src:match("^rfc2217://([^/%s]+)")
    if hostport then return "net", hostport end
    local dev = src:match("^serial://([^,%s]+)")
    if dev then return "tty", dev end
    return nil
end

local function read_file(path)
    local fp = io.open(path, "r")
    if not fp then return "" end
    local data = fp:read("*a") or ""
    fp:close()
    return data
end

-- Приборы из текста bortdrc: { {type=..., kind=..., key=...}, ... }
function connection_status.parse_bortdrc(text)
    local devices, current = {}, nil
    for raw in text:gmatch("[^\n]+") do
        local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
        local dtype = line:match("^device%s+(%S+)")
        if dtype then
            current = { type = dtype }
        elseif line == "}" then
            current = nil
        elseif current then
            local src = line:match("^src%s+(%S+)")
            if src then
                local kind, key = parse_source(src)
                if kind then
                    current.kind, current.key = kind, key
                    table.insert(devices, current)
                end
            end
        end
    end
    return devices
end

-- Вывод link-status.sh -> { running=bool, tcp={peer=bytes}, tty={path=bool} }
function connection_status.parse_status(out)
    local st = { running = false, tcp = {}, tty = {} }
    for line in out:gmatch("[^\n]+") do
        local pid = line:match("^bortd (%S+)")
        if pid then st.running = pid ~= "none" end
        local peer, bytes = line:match("^tcp (%S+) (%d+)")
        if peer then st.tcp[peer] = (st.tcp[peer] or 0) + tonumber(bytes) end
        local dev, open = line:match("^tty (%S+) (%a+)")
        if dev then st.tty[dev] = open == "open" end
    end
    return st
end

function connection_status.create_widget()
    local container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }
    local indicators = {}
    local rc_text = nil
    -- история счётчиков по адресу прибора, переживает перечитывание bortdrc
    local history = {}

    local function rebuild()
        local labels = load_labels()
        local devices = connection_status.parse_bortdrc(rc_text)
        local count = {}
        for _, d in ipairs(devices) do count[d.type] = (count[d.type] or 0) + 1 end

        container:reset()
        indicators = {}
        for _, d in ipairs(devices) do
            local label = labels[d.key]
            if not label then
                label = short_names[d.type] or d.type:upper()
                if count[d.type] > 1 then
                    -- несколько приборов одного типа: добавляем хвост адреса
                    label = label .. (d.key:match("%.(%d+):%d+$") or d.key:match("(%d+)$") or "")
                end
            end
            local ind = {
                type = d.type, kind = d.kind, key = d.key, label = label,
                state = "off",
            }
            ind.widget = wibox.widget {
                {
                    { text = label, align = "center", widget = wibox.widget.textbox },
                    left = 8, right = 8, top = 4, bottom = 4,
                    widget = wibox.container.margin,
                },
                bg = colors.off,
                shape = gears.shape.rounded_rect,
                forced_width = 60,
                widget = wibox.container.background,
            }
            awful.tooltip {
                objects = { ind.widget },
                timer_function = function()
                    return string.format("%s  %s\n%s", d.type, d.key, state_text[ind.kind][ind.state])
                end,
            }
            container:add(ind.widget)
            table.insert(indicators, ind)
        end
        connection_status.indicators = indicators
    end

    local function update(st)
        local now = os.time()
        for _, ind in ipairs(indicators) do
            local state
            if not st.running then
                state = "off"
                history[ind.key] = nil
            elseif ind.kind == "net" then
                local bytes = st.tcp[ind.key]
                local h = history[ind.key]
                if bytes == nil then
                    state = "down"
                    history[ind.key] = nil
                else
                    if h == nil or bytes < h.bytes then
                        -- новое соединение: зелёный только после того, как
                        -- увидим рост счётчика принятых байт
                        h = { bytes = bytes, change = nil }
                        history[ind.key] = h
                    elseif bytes > h.bytes then
                        h.bytes, h.change = bytes, now
                    end
                    state = (h.change and now - h.change <= stale_after) and "ok" or "stale"
                end
            else
                state = st.tty[ind.key] and "ok" or "down"
            end
            ind.state = state
            ind.widget.bg = colors[state]
        end
    end

    gears.timer {
        timeout = interval,
        autostart = true,
        call_now = true,
        callback = function()
            -- bortdrc маленький: перечитываем и пересобираем при изменении
            local text = read_file(bortdrc)
            if text ~= rc_text then
                rc_text = text
                rebuild()
            end
            local cmd = { "sh", helper }
            for _, ind in ipairs(indicators) do
                if ind.kind == "tty" then table.insert(cmd, ind.key) end
            end
            awful.spawn.easy_async(cmd, function(stdout)
                update(connection_status.parse_status(stdout))
            end)
        end
    }

    return container
end

return connection_status
