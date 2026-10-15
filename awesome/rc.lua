-- @DOC_REQUIRE_SECTION@
-- Standard awesome library
local gears = require("gears")
local timer = require("gears.timer")
local awful = require("awful")
require("awful.autofocus")
local vsegeibar = require("vsegeibar")
-- Theme handling library
local beautiful = require("beautiful")
-- Notification library
local naughty = require("naughty")
--local menubar = require("menubar")
local hotkeys_popup = require("awful.hotkeys_popup").widget

local keyboard_layout = require("keyboard_layout")
local utils = require("utils")
local mywibar = require("mywibar")
local redflat = require("redflat")

local pulseaudio = require("apw.pulseaudio")
local brightness = require("brightness")
local quake = require("quake")
local xrandr = require("xrandr")

-- {{{ Error handling
-- @DOC_ERROR_HANDLING@
-- Check if awesome encountered an error during startup and fell back to
-- another config (This code will only ever execute for the fallback config)
if awesome.startup_errors then
    naughty.notify({ preset = naughty.config.presets.critical,
                     title = "Oops, there were errors during startup!",
                     text = awesome.startup_errors })
end

-- Handle runtime errors after startup
do
    local in_error = false
    awesome.connect_signal("debug::error", function (err)
        -- Make sure we don't go into an endless error loop
        if in_error then return end
        in_error = true

        naughty.notify({ preset = naughty.config.presets.critical,
                         title = "Oops, an error happened!",
                         text = tostring(err) })
        in_error = false
    end)
end
-- }}}

-- {{{ Variable definitions
-- @LOCAL_SETTINGS@
local function load_settings(module_name, default_settings)
   local status, value = pcall(require, module_name)
   if not status then
      print('using default settings: ' .. value)
      return default_settings
   end
   setmetatable(value, {__index = default_settings})
   return value
end

local settings = load_settings(
   "local_settings", {
      enable_wibar = true,
      terminal = "gnome-terminal",
      editor = os.getenv("EDITOR") or "vim"
})

-- @DOC_LOAD_THEME@
-- Themes define colours, icons, font and wallpapers.
beautiful.init(awful.util.get_themes_dir() .. "default/theme.lua")

beautiful.tooltip_border_color = "#ff0000"
beautiful.tooltip_bg = "#aaaaaa"
beautiful.tooltip_fg = "#111111"
beautiful.tooltip_bg = "#000000"
beautiful.tooltip_fg = "#ffffff"
beautiful.tooltip_border_width = 0
beautiful.tooltip_align = "right"

beautiful.border_focus = "#aaaaaa"

-- @DOC_DEFAULT_APPLICATIONS@
-- This is used later as the default terminal and editor to run.
terminal = settings.terminal
editor = settings.editor
editor_cmd = terminal .. " -e " .. editor

-- Default modkey.
-- Usually, Mod4 is the key with a logo between Control and Alt.
-- If you do not like this or do not have such a key,
-- I suggest you to remap Mod4 to another key using xmodmap or other tools.
-- However, you can use another modifier like Mod1, but it may interact with others.
modkey = "Mod4"
Alt = "Mod1"
Control = "Control"
Shift = "Shift"

function command(cmd)
    return function () awful.spawn(cmd) end
end

-- @DOC_LAYOUT@
-- Table of layouts to cover with awful.layout.inc, order matters.
awful.layout.layouts = {
    -- awful.layout.suit.tile,
    -- awful.layout.suit.tile.left,
    -- awful.layout.suit.tile.bottom,
    -- awful.layout.suit.tile.top,
    awful.layout.suit.floating,

    -- awful.layout.suit.fair,
    -- awful.layout.suit.fair.horizontal,
    -- awful.layout.suit.spiral,
    -- awful.layout.suit.spiral.dwindle,
    -- awful.layout.suit.max,
    -- awful.layout.suit.max.fullscreen,
    -- awful.layout.suit.magnifier,
    -- awful.layout.suit.corner.nw,
    -- awful.layout.suit.corner.ne,
    -- awful.layout.suit.corner.sw,
    -- awful.layout.suit.corner.se,
}
-- }}}

-- {{{ Menu
-- @DOC_MENU@
-- Create a launcher widget and a main menu
local function create_menu()
    local separator = { widget = redflat.gauge.separator.horizontal() }
    local navdat_appmenu = redflat.service.dfparser.menu{
        icons = icon_style, wm_name = "awesome",
        desktop_file_dirs = {
            "/usr/share/bort/applications"
        }
    }
    return redflat.menu({
        items = {
            { "Navdat", navdat_appmenu },
            separator,
            { "Файловый менеджер", "nautilus" },
            { "Терминал", terminal },
            separator,
            { "Настройки", function ()
                    awful.spawn.with_shell(
                        "XDG_CURRENT_DESKTOP=Unity unity-control-center")
                end
            },
            separator,
            { "Документация", "navdat-help" },
            { "Клавиши", hotkeys_popup.show_help },
            { "Выход", "navdat-session-quit" }
        },
        theme = {
            border_width = 1,
            color = {
                border = "#373737",
                text = "#aaaaaa",
                highlight = "#eeeeee",
                main = "#b1222b",
                wibox = "#202020",
                submenu_icon = nil, right_icon = nil, left_icon = nil
            }
        }
    })
end

mymainmenu = create_menu()

mylauncher = awful.widget.launcher({
      image = "/usr/share/icons/ubuntu-mono-dark/status/22/system-devices-panel.svg",
      menu = mymainmenu
})

quakeconsole = quake{
    height = 0.3,
    keys = awful.util.table.join(
        awful.key({ modkey }, "Down", function (c)
            quakeconsole:incHeight(c, 0.1)
        end),
        awful.key({ modkey }, "Up", function (c)
            quakeconsole:incHeight(c, -0.1)
        end))
}

-- Menubar configuration
--menubar.utils.terminal = terminal -- Set the terminal for applications that require it
-- }}}

-- {{{ Wibar

-- @DOC_WALLPAPER@
local function set_wallpaper(s)
    -- -- Wallpaper
    -- if beautiful.wallpaper then
    --     local wallpaper = beautiful.wallpaper
    --     -- If wallpaper is a function, call it with the screen
    --     if type(wallpaper) == "function" then
    --         wallpaper = wallpaper(s)
    --     end
    --     gears.wallpaper.maximized(wallpaper, s, true)
    -- end
    gears.wallpaper.set("#444444")
end

-- Re-set wallpaper when a screen's geometry changes (e.g. different resolution)
screen.connect_signal("property::geometry", set_wallpaper)

local function mypromptbox_run ()
   local mypromptbox =
      awful.screen.focused().mypromptbox or screen[1].mypromptbox
   if mypromptbox then
      mypromptbox:run()
   else
      awful.spawn("gnome-panel-control --run-dialog")
   end
end

-- @DOC_FOR_EACH_SCREEN@
awful.screen.connect_for_each_screen(function(s)
    -- Wallpaper
    set_wallpaper(s)

    -- Each screen has its own tag table.
    awful.tag({ "1", "2", "3", "4" }, s,
        awful.layout.layouts[1])

    if settings.enable_wibar then
        -- only enable wibar on the main screen
        if s.index == 1 then
            mywibar.create_wibar(s)
            vsegeibar.create_vsegeibar(s)
        end
    end
end)
-- }}}

-- {{{ Mouse bindings
-- @DOC_ROOT_BUTTONS@
root.buttons(awful.util.table.join(
    awful.button({ }, 1, function () mymainmenu:toggle() end),
    awful.button({ }, 4, awful.tag.viewnext),
    awful.button({ }, 5, awful.tag.viewprev)
))
-- }}}

-- {{{ Key bindings
-- @DOC_GLOBAL_KEYBINDINGS@
globalkeys = awful.util.table.join(
    -- Awesome keys
    awful.key(
        { modkey }, "s",
        hotkeys_popup.show_help,
        {
            description = "Показать подсказку",
            group = "awesome"
        }
    ),
    awful.key(
        { Alt }, "F1",
        function () mymainmenu:show() end,
        {
            description = "Главное меню",
            group = "awesome"
        }
    ),
    -- awful.key(
    --     {"Mod1"}, "Escape",
    --     xrandr.menu,
    --     {
    --         description = "Настройка экранов",
    --         group = "awesome"
    --     }
    -- ),
    awful.key({ "Mod1" }, "space",
       function ()
          keyboard_layout.next(client.focus or {})
       end,
       {
            description = "Переключение раскладки клавиатуры",
            group = "awesome"
       }
    ),

    -- navdat
    awful.key({ Control, Alt }, "s",
        command("navdat-bortcfg save"),
        {
            description = "Сохранить настройки программ (Положение на экране)",
            group = "navdat"
        }
    ),
    awful.key({ Control, Alt }, "r",
        command("navdat-bortcfg restore"),
        {
            description = "Восстановить сохраненное состояние программ и запустить бортовой сервер, если он не был запущен ранее",
            group = "navdat"
        }
    ),
    awful.key({ Control, Alt }, "q",
        command("navdat-tool -z 1.1"),
        {
            description = "Увеличить масштаб панорамы, для всех приложений 'панорама' на текущем рабочем месте",
            group = "navdat"
        }
    ),
    awful.key({ Control, Alt }, "a",
        command("navdat-tool -z 0.9"),
        {
            description = "Уменьшить масштаб панорамы, для всех приложений 'панорама' на текущем рабочем месте",
            group = "navdat"
        }
    ),
    awful.key({ Control }, "k",
        command("navdat-tool --stop"),
        {
            description = "Прекратить проводку по маршруту, если таковая осуществлялась",
            group = "navdat"
        }
    ),
    awful.key({ Control }, "f",
        command("navdat-tool --fix"),
        {
            description = "Запись координат текущей точки",
            group = "navdat"
        }
    ),

    -- Tags manipulation
    awful.key(
        { Alt, Control }, "Left",
        awful.tag.viewprev,
        {
            description = "Переключиться на рабочее влево",
            group = "tag"
        }
    ),
    awful.key(
        { Alt, Control }, "Right",
        awful.tag.viewnext,
        {
            description = "Переключиться на рабочее вправо вправо",
            group = "tag"
        }
    ),
    awful.key(
        { Alt }, "Tab",
        function ()
            awful.client.focus.byidx(1)
        end,
        {
            description = "Переключить фокус на следующее окно",
            group = "client"
        }
    ),
    awful.key(
        { Alt, Shift }, "Tab",
        function ()
            awful.client.focus.byidx(-1)
        end,
        {
            description = "Переключить фокус на предыдущее окно",
            group = "client"
        }
    ),

    -- Standard program
    awful.key(
        { modkey }, "Return",
        command(terminal),
        {
            description = "Открыть терминал",
            group = "launcher"
        }
    ),

    -- My custom keys
    awful.key(
        { Alt }, "F2",
        mypromptbox_run,
        {
            description = "Запустить команду",
            group = "launcher"
        }
    ),
    awful.key(
        { Control, Alt }, "l",
        utils.lock_screen,
        {
            description = "Заблокировать экран",
            group = "launcher"
        }
    ),

    -- Volume control
    awful.key({ }, "XF86AudioRaiseVolume",  pulseaudio.VolumeUp),
    awful.key({ }, "XF86AudioLowerVolume",  pulseaudio.VolumeDown),
    awful.key({ }, "XF86AudioMute",         pulseaudio.VolumeToggleMute),

    -- Brightness control
    awful.key({ }, "XF86MonBrightnessDown", brightness.dec),
    awful.key({ }, "XF86MonBrightnessUp", brightness.inc),

    awful.key(
        { modkey }, "`",
        function () quakeconsole:toggle() end,
        {
            description = "Показать/Скрыть выпадающую консоль",
            group = "launcher"
        }
    )
)

local movements = require "movements"

local function shift_with_client(c, step)
    local s = c.screen
    local idx = 1 + (#s.tags + s.selected_tag.index + step - 1) % #s.tags
    local tag = s.tags[idx]
    if tag then
        tag:view_only()
        c:move_to_tag(tag)
    end
end

-- @DOC_CLIENT_KEYBINDINGS@
clientkeys = awful.util.table.join(
    awful.key(
        { modkey }, "f",
        function (c)
            c.fullscreen = not c.fullscreen
            c:raise()
        end,
        {
            description = "toggle fullscreen",
            group = "client"
        }
    ),
    awful.key(
        { Alt }, "F4",
        function (c) c:kill() end,
        {
            description = "close",
            group = "client"
        }
    ),
    awful.key(
        { Alt }, "F10",
        function (c)
            c.maximized = not c.maximized
            c:raise()
        end ,
        {
            description = "Максимизировать окно",
            group = "client"
        }
    ),
    awful.key(
        { Alt }, "F7",
        movements.start_move,
        {
            description = "Переместить окно",
            group = "client"
        }
    ),
    awful.key(
        { Alt }, "F8",
        movements.start_resize,
        {
            description = "Изменить размер окна",
            group = "client"
        }
    ),
    awful.key(
        { Alt, Control, Shift }, "Left",
        function (c) shift_with_client(c, -1)  end,
        {
            description = "Переключиться на рабочее место влево вместе с окном",
            group = "tag"
        }
    ),
    awful.key(
        { Alt, Control, Shift }, "Right",
        function (c) shift_with_client(c, 1)  end,
        {
            description = "Переключиться на рабочее место влево вместе с окном",
            group = "tag"
        }
    )
)

-- @DOC_NUMBER_KEYBINDINGS@
-- Bind all key numbers to tags.
-- Be careful: we use keycodes to make it works on any keyboard layout.
-- This should map on the top row of your keyboard, usually 1 to 9.
for i = 1, 9 do
    globalkeys = awful.util.table.join(globalkeys,
        -- View tag only.
        awful.key(
            { modkey }, "#" .. i + 9,
            function ()
                local screen = awful.screen.focused()
                 local tag = screen.tags[i]
                 if tag then
                    tag:view_only()
                end
            end,
            {
                description = "Перейти на рабочее место #".. i,
                group = "tag"
            }
        ),
        awful.key(
            { Control, Shift }, "#" .. i + 9,
            function ()
                if client.focus then
                    local tag = client.focus.screen.tags[i]
                    if tag then
                        client.focus:move_to_tag(tag)
                    end
                end
            end,
            {
                description = "Перенести окно на рабочее место #".. i,
                group = "tag"
            }
        )
        -- -- Toggle tag on focused client.
        -- awful.key({ modkey, "Control", "Shift" }, "#" .. i + 9,
        --           function ()
        --               if client.focus then
        --                   local tag = client.focus.screen.tags[i]
        --                   if tag then
        --                       client.focus:toggle_tag(tag)
        --                   end
        --               end
        --           end,
        --           {description = "toggle focused client on tag #" .. i, group = "tag"})
    )
end

-- @DOC_CLIENT_BUTTONS@
local function _raise_and(func)
    return function (c)
        c:raise()
        func(c)
    end
end


clientbuttons = awful.util.table.join(
    awful.button({ }, 1, function (c) client.focus = c; c:raise() end),
    awful.button({ modkey }, 1, _raise_and(awful.mouse.client.move)),
    awful.button({ modkey }, 3, _raise_and(awful.mouse.client.resize)),
    awful.button({ Alt }, 1, _raise_and(awful.mouse.client.move)),
    awful.button({ Alt }, 3, _raise_and(awful.mouse.client.resize)))

-- Set keys
root.keys(globalkeys)
-- }}}

-- {{{ Rules
-- Rules to apply to new clients (through the "manage" signal).
-- @DOC_RULES@
awful.rules.rules = {
    -- @DOC_GLOBAL_RULE@
    -- All clients will match this rule.
    { rule = { },
      properties = { border_width = beautiful.border_width,
                     border_color = beautiful.border_normal,
                     focus = awful.client.focus.filter,
                     raise = true,
                     keys = clientkeys,
                     buttons = clientbuttons,
                     screen = awful.screen.preferred,
                     placement = awful.placement.no_overlap+awful.placement.no_offscreen,
                     size_hints_honor = false
     }
    },

    -- @DOC_FLOATING_RULE@
    -- Floating clients.
    { rule_any = {
        instance = {
          "DTA",  -- Firefox addon DownThemAll.
          "copyq",  -- Includes session name in class.
        },
        class = {
          "Arandr",
          "Gpick",
          "Kruler",
          "MessageWin",  -- kalarm.
          "Sxiv",
          "Wpa_gui",
          "pinentry",
          "veromix",
          "xtightvncviewer"},

        name = {
          "Event Tester",  -- xev.
        },
        role = {
          "AlarmWindow",  -- Thunderbird's calendar.
          "pop-up",       -- e.g. Google Chrome's (detached) Developer Tools.
        }
      }, properties = { floating = true }},

    -- @DOC_DIALOG_RULE@
    -- Add titlebars to normal clients and dialogs
    { rule_any = {type = { "normal", "dialog" }
      }, properties = { titlebars_enabled = false }
    },

    -- Emacs has its own keyboard switcher
    { rule_any = { class =  { "Emacs" } },
      properties = { disable_kbd_switch = true } },

    { rule_any = { class =  { "chrome-browser",
                              "chromium-browser",
                              "yandex-browser-beta" } },
      properties = { floating = false, maximized = false } }

    -- Set Firefox to always map on the tag named "2" on screen 1.
    -- { rule = { class = "Firefox" },
    --   properties = { screen = 1, tag = "2" } },
}
-- }}}

-- {{{ Signals
-- Signal function to execute when a new client appears.
-- @DOC_MANAGE_HOOK@
client.connect_signal("manage", function (c)
    -- Set the windows at the slave,
    -- i.e. put it at the end of others instead of setting it master.
    -- if not awesome.startup then awful.client.setslave(c) end

    if awesome.startup and
      not c.size_hints.user_position
      and not c.size_hints.program_position then
        -- Prevent clients from being unreachable after screen count changes.
        awful.placement.no_offscreen(c)
    end
end)

-- @DOC_BORDER@
client.connect_signal("focus", function(c)
    c.border_color = beautiful.border_focus
end)
client.connect_signal("unfocus", function(c)
    c.border_color = beautiful.border_normal
end)
-- }}}

-- On screen disconnect move client to the same tag number other screen
client.connect_signal("request::tag", function (c, t, hints)
    if hints and hints.reason == "screen-removed" then
        local fallback = nil
        for other_screen in screen do
            if #other_screen.tags > 0 then
                fallback = other_screen.tags[c.first_tag.index] or
                    other_screen.tags[1]
                break
            end
        end
        if fallback then
            c.screen_evicted = true
            c:move_to_tag(fallback)
        end
    end
end)

local screen_state = {
    selected_tag
}
-- Move client back to the screen and tag
-- TODO: restore full state
screen.connect_signal("added", function (s)
    for _, c in ipairs(client.get()) do
        if c.screen_evicted then
            local tag = s.tags[c.first_tag.index]
            if tag then
                c:move_to_tag(tag)
            end
            c.screen_evicted = nil
        end
    end

    local tag = s.tags[screen_state.selected_tag]
    if tag then
        tag:view_only()
    end
    screen_state.selected_tag = nil
end)

tag.connect_signal("removal-pending", function (t)
    if t.selected then
        screen_state.selected_tag = t.index
    end
end)

-- minimize hidden clients
local function _check_tag(t)
    for _,c in ipairs(t:clients()) do
        c.minimized = not t.selected;
    end
end

tag.connect_signal("property::selected", function (t)
    timer.delayed_call(_check_tag, t)
end)

gears.timer {
    timeout = 2.0,
    autostart = true,
    callback = function ()
        for _, t in ipairs(root.tags()) do
            _check_tag(t)
        end
    end
}
