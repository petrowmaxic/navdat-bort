local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local connection_status = require("connection_status")

local vsegeibar = {}

function vsegeibar.create_vsegeibar(s)
    -- Создаем панель с определенной шириной и позицией
    s.vsegeibox = awful.wibar({
        position = "top",
        screen = s,
        height = 20, -- Высота панели
        width = 600, -- Ширина панели (меньше ширины экрана)
        ontop = true, -- Очень важно - поверх всех окон
        stretch = false, -- Не растягивать на всю ширину
    })

    -- Устанавливаем панель по центру сверху
    s.vsegeibox:geometry({
        x = (s.geometry.width - 600) / 2, -- Центрируем по горизонтали
        y = 0, -- Отступ сверху
        width = 600,
        height = 20
    })

    -- Создаем виджеты индикаторов
    local indicators = connection_status.create_widget()

    -- Настройка содержимого панели
    s.vsegeibox:setup {
        layout = wibox.layout.align.horizontal,
        expand = "none",
        nil, -- Левая часть пустая
        { -- Центральная часть - индикаторы
            layout = wibox.layout.fixed.horizontal,
            spacing = 10,
            indicators,
        },
        nil, -- Правая часть пустая
    }
end

return vsegeibar
