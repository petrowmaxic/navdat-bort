local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

local connection_status = {}

-- Конфигурация устройств - теперь легко добавлять новые
local devices = {
    { name = "MG", host = "10.100.4.50", port = 1917 },
    { name = "NV", host = "10.100.4.50", port = 4444 },
    { name = "RS61", host = "192.168.1.162", port = 4001 },
    { name = "RS83", host = "192.168.1.161", port = 4001 },
    { name = "RS501", host = "192.168.1.2", port = 4001 }
    -- Просто добавьте новую строку для нового устройства:
    -- { name = "NEW", host = "192.168.1.100", port = 1234 }
}

-- Функция проверки доступности порта
local function check_port(host, port, callback)
    local cmd = string.format("timeout 1 nc -z -w 1 %s %d >/dev/null 2>&1 && echo true || echo false", host, port)
    
    awful.spawn.easy_async_with_shell(cmd, function(stdout)
        local result = stdout:gsub("%s+", "") -- Убираем пробелы и переводы строк
        local is_available = (result == "true")
        callback(is_available)
    end)
end

-- Создание виджета индикатора для одного устройства
local function create_device_widget(device)
    local text_widget = wibox.widget {
        text = device.name,
        align = 'center',
        widget = wibox.widget.textbox,
    }
    
    local widget = wibox.widget {
        {
            text_widget,
            left = 8,
            right = 8,
            top = 4,
            bottom = 4,
            widget = wibox.container.margin,
        },
        bg = "#aa0000", -- Красный по умолчанию (нет соединения)
        shape = gears.shape.rounded_rect,
        forced_width = 60, -- Фиксированная ширина для одинакового размера
        widget = wibox.container.background,
    }

    return {
        widget = widget,
        host = device.host,
        port = device.port,
        name = device.name
    }
end

-- Создание виджета со всеми индикаторами
function connection_status.create_widget()
    local widget_container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }

    local device_widgets = {}

    -- Создаем виджеты для каждого устройства
    for i, device in ipairs(devices) do
        local device_widget = create_device_widget(device)
        device_widgets[i] = device_widget
        widget_container:add(device_widget.widget)
    end

    -- Функция обновления статуса
    local function update_status()
        for _, device in ipairs(device_widgets) do
            check_port(device.host, device.port, function(is_available)
                -- Обновляем цвет в основном потоке Awesome
                gears.timer.delayed_call(function()
                    if is_available then
                        device.widget.bg = "#006600" -- Темно-зеленый при доступности
                    else
                        device.widget.bg = "#aa0000" -- Красный при недоступности
                    end
                    -- Принудительно обновляем отображение
                    device.widget:emit_signal("widget::redraw_needed")
                end)
            end)
        end
    end

    -- Обновляем статус каждую секунду
    local update_timer = gears.timer {
        timeout = 1,
        autostart = true,
        call_now = true,
        callback = update_status
    }

    return widget_container
end

return connection_status
