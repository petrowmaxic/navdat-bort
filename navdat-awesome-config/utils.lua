local awful = require("awful")

local utils = {}

function utils.switch_tag(s, step)
    local tag = s.tags[s.selected_tag.index + step]
    if tag then
        tag:view_only()
    end
end

function utils.lock_screen()
   -- force english before the greeter shows up
   awesome.xkb_set_layout_group(0)
   awful.spawn("dm-tool lock")
end

function utils.quit_session()
   awful.spawn.easy_async(
      {"zenity", "--question", "--title", "Confirmation",
       "--text", "Do you really want to quit?"},
      function (_, _, _, exit_code)
         if exit_code == 0 then
            awesome.quit()
         end
   end)
end

function utils.suspend()
   awful.spawn("systemctl -i suspend")
end

return utils
