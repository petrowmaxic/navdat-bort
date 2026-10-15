-- Индикаторы связи bortd с приборами.
--
-- ВАЖНО: индикаторы НИКОГДА не подключаются к приборам сами. Преобразователи
-- Ethernet->COM (NPort и т.п.) обычно принимают одно TCP-соединение, а любые
-- байты в нём уходят в последовательный порт прибора. Пробные подключения
-- (nc -z, echo >/dev/tcp) отбирали соединение у bortd или писали мусор в прибор
-- и портили данные.
--
-- Вместо этого раз в 2 с читается состояние уже открытых соединений в ядре
-- (ss -tin) и счётчик принятых байт:
--   зелёный - bortd подключён и данные идут;
--   жёлтый  - соединение есть, но данных не было дольше stale_after секунд;
--   красный - соединения нет.
--
-- Список приборов можно переопределить в ~/.config/navdat/devices.lua:
--   return { { name = "RS61", host = "192.168.1.162", port = 4001 }, ... }

local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

local connection_status = {}

local default_devices = {
    { name = "MG", host = "10.100.4.50", port = 1917 },
    { name = "NV", host = "10.100.4.50", port = 4444 },
    { name = "RS61", host = "192.168.1.162", port = 4001 },
    { name = "RS83", host = "192.168.1.161", port = 4001 },
    { name = "RS501", host = "192.168.1.2", port = 4001 },
}

local interval = 2       -- период опроса ss, с
local stale_after = 5    -- сколько секунд без новых байт считать "данных нет"

local colors = {
    ok    = "#006600",
    stale = "#aa8800",
    down  = "#aa0000",
}

local function load_devices()
    local path = gears.filesystem.get_xdg_config_home() .. "navdat/devices.lua"
    if gears.filesystem.file_readable(path) then
        local ok, list = pcall(dofile, path)
        if ok and type(list) == "table" then
            return list
        end
        print("connection_status: bad " .. path .. ": " .. tostring(list))
    end
    return default_devices
end

-- Разбор вывода "ss -tinH state established":
-- строка соединения "<recvq> <sendq> <local> <peer>", под ней строка
-- с параметрами, где есть bytes_received:N. Возвращает peer -> байты.
local function parse_ss(out)
    local peers = {}
    local peer
    for line in out:gmatch("[^\n]+") do
        local p = line:match("^%s*%d+%s+%d+%s+%S+%s+(%S+)")
        if p then
            peer = p
            peers[peer] = peers[peer] or 0
        elseif peer then
            local n = tonumber(line:match("bytes_received:(%d+)") or "0")
            peers[peer] = peers[peer] + n
            peer = nil
        end
    end
    return peers
end

local function create_device_widget(device)
    local widget = wibox.widget {
        {
            {
                text = device.name,
                align = 'center',
                widget = wibox.widget.textbox,
            },
            left = 8,
            right = 8,
            top = 4,
            bottom = 4,
            widget = wibox.container.margin,
        },
        bg = colors.down,
        shape = gears.shape.rounded_rect,
        forced_width = 60,
        widget = wibox.container.background,
    }
    return {
        widget = widget,
        peer = string.format("%s:%d", device.host, device.port),
        last_bytes = nil,
        last_change = 0,
    }
end

function connection_status.create_widget()
    local widget_container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }

    local device_widgets = {}
    for i, device in ipairs(load_devices()) do
        device_widgets[i] = create_device_widget(device)
        widget_container:add(device_widgets[i].widget)
    end

    local function update(peers)
        local now = os.time()
        for _, d in ipairs(device_widgets) do
            local bytes = peers[d.peer]
            local state
            if bytes == nil then
                state = "down"
                d.last_bytes = nil
            else
                if d.last_bytes == nil or bytes ~= d.last_bytes then
                    d.last_change = now
                end
                d.last_bytes = bytes
                state = (now - d.last_change <= stale_after) and "ok" or "stale"
            end
            d.widget.bg = colors[state]
            d.state = state
        end
    end

    connection_status.devices = device_widgets
    gears.timer {
        timeout = interval,
        autostart = true,
        call_now = true,
        callback = function()
            awful.spawn.easy_async({"ss", "-tinH", "state", "established"},
                function(stdout) update(parse_ss(stdout)) end)
        end
    }

    return widget_container
end

connection_status.parse_ss = parse_ss

return connection_status
