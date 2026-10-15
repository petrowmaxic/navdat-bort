local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

local connection_status = {}

-- Конфигурация устройств
local devices = {
    { name = "MG", host = "10.100.4.50", port = 1917 },
    { name = "NV", host = "10.100.4.50", port = 4444 },
    { name = "RS61", host = "192.168.1.162", port = 4001 },
    { name = "RS83", host = "192.168.1.161", port = 4001 }
--    { name = "RS83", host = "192.168.1.2", port = 4001 }
}

-- Функция проверки доступности порта
local function check_port(host, port, callback)
    -- Используем netcat для проверки порта
    local cmd = string.format("timeout 1 nc -z -w 1 %s %d >/dev/null 2>&1 && echo true || echo false", host, port)
    
    awful.spawn.easy_async_with_shell(cmd, function(stdout)
        local result = stdout:gsub("%s+", "") -- Убираем пробелы и переводы строк
        local is_available = (result == "true")
        callback(is_available)
    end)
end

-- Создание виджета индикатора
function connection_status.create_widget()
    local widget_container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }

    local device_widgets = {}

    -- Создаем виджеты для каждого устройства
    for i, device in ipairs(devices) do
        local text_widget = wibox.widget {
            text = device.name,
            align = 'center',
            widget = wibox.widget.textbox,
        }
        
        local widget = wibox.widget {
            {
                text_widget,
                left = 6,
                right = 6,
                top = 2,
                bottom = 2,
                widget = wibox.container.margin,
            },
            bg = "#aa0000", -- Красный по умолчанию
            shape = gears.shape.rounded_rect,
            forced_width = 60, -- Фиксированная ширина для одинакового размера
            widget = wibox.container.background,
        }

        device_widgets[i] = {
            widget = widget,
            host = device.host,
            port = device.port
        }

        widget_container:add(widget)
    end

    -- Функция обновления статуса
    local function update_status()
        for _, device in ipairs(device_widgets) do
            check_port(device.host, device.port, function(is_available)
                -- Обновляем цвет в основном потоке Awesome
                gears.timer.delayed_call(function()
                    device.widget.bg = is_available and "#006600" or "#aa0000"
                end)
            end)
        end
    end

    -- Обновляем статус каждые 1 секунд
    local update_timer = gears.timer {
        timeout = 1,
        autostart = true,
        call_now = true,
        callback = update_status
    }

    return widget_container
end

return connection_status
