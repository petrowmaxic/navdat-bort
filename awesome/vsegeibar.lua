local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

local vsegeibar = {}

function vsegeibar.create_vsegeibar(s)
    -- Создаем панель с определенной шириной и позицией
    s.vsegeibox = awful.wibar({
        position = "top",
        screen = s,
        height = 30, -- Высота панели
        width = 600, -- Ширина панели (меньше ширины экрана)
        bg = "#000000AA", -- Черный с прозрачностью
        ontop = true, -- Очень важно - поверх всех окон
        stretch = false, -- Не растягивать на всю ширину
    })
    
    -- Устанавливаем панель по центру сверху
    s.vsegeibox:geometry({
        x = (s.geometry.width - 600) / 2, -- Центрируем по горизонтали
        y = 10, -- Отступ сверху
        width = 600,
        height = 30
    })
    
    -- Настройка содержимого панели
    s.vsegeibox:setup {
        layout = wibox.layout.align.horizontal,
        expand = "none",
        { -- Левая часть
            layout = wibox.layout.fixed.horizontal,
            wibox.widget.textbox(" Левая часть "),
        },
        { -- Центральная часть
            layout = wibox.layout.fixed.horizontal,
            wibox.widget.textbox(" ЦЕНТРАЛЬНАЯ ПАНЕЛЬ "),
        },
        { -- Правая часть
            layout = wibox.layout.fixed.horizontal,
            wibox.widget.textbox(" Правая часть "),
        },
    }
end

return vsegeibar
