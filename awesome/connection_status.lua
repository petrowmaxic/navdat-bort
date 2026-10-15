local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

local connection_status = {}

local devices = {
    { name = "MG", host = "10.100.4.50", port = 1917 },
    { name = "NV", host = "10.100.4.50", port = 4444 },
    { name = "RS61", host = "192.168.1.162", port = 4001 },
    { name = "RS83", host = "192.168.1.161", port = 4001 }
}

local status_cache = {}
local current_device_index = 1

local function check_port(host, port, callback)
    local cmd = string.format("timeout 0.3 bash -c 'echo >/dev/tcp/%s/%d 2>/dev/null' && echo true || echo false", host, port)
    
    awful.spawn.easy_async_with_shell(cmd, function(stdout)
        local result = stdout:gsub("%s+", "")
        callback(result == "true")
    end)
end

function connection_status.create_widget()
    local widget_container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }

    local device_widgets = {}

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
            bg = "#aa0000",
            shape = gears.shape.rounded_rect,
            forced_width = 60,
            widget = wibox.container.background,
        }

        device_widgets[i] = {
            widget = widget,
            host = device.host,
            port = device.port,
            name = device.name
        }
        
        status_cache[device.name] = false
        widget_container:add(widget)
    end

    local function update_single_device()
        if #device_widgets == 0 then return end
        
        local device = device_widgets[current_device_index]
        check_port(device.host, device.port, function(is_available)
            if status_cache[device.name] ~= is_available then
                status_cache[device.name] = is_available
                gears.timer.delayed_call(function()
                    device.widget.bg = is_available and "#006600" or "#aa0000"
                end)
            end
        end)
        
        -- Переходим к следующему устройству
        current_device_index = (current_device_index % #devices) + 1
    end

    -- Проверяем по одному устройству каждую секунду
    local update_timer = gears.timer {
        timeout = 1,
        autostart = true,
        call_now = true,
        callback = update_single_device
    }

    return widget_container
end

return connection_status