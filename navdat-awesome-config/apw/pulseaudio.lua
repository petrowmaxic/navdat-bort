-- Copyright 2013 mokasin
-- This file is part of the Awesome Pulseaudio Widget (APW).
--
-- APW is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- APW is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with APW. If not, see <http://www.gnu.org/licenses/>.


-- Simple pulseaudio command bindings for Lua.
local awful = require("awful")
local timer = require("gears.timer")

local pulseaudio = {
   Volume = 0,
   mute = false
}

-- pactl работает и с PulseAudio, и с PipeWire (pipewire-pulse) в Ubuntu 22.04+
local cmd = "pactl"
local default_sink = "@DEFAULT_SINK@"
local default_increment = 0.10
local timer_timeout = 2.0

local update_callbacks = {}
local timer_obj = nil


function pulseaudio.register_callback(callback)
   table.insert(update_callbacks, callback)
end

local function UpdateStateFromOutput(out)
   -- "Volume: front-left: 65536 / 100% / 0.00 dB, ..." -- берём первый канал
   local value = string.match(out, "Volume:%s*[%w%-]+:%s*(%d+)%s*/")
   if value == nil then
      return false
   end
   pulseaudio.Volume = tonumber(value) / 0x10000

   pulseaudio.Mute = string.match(out, "Mute:%s*(%a+)") == "yes"

   for i, callback in ipairs(update_callbacks) do
      callback()
   end
end

function pulseaudio.UpdateState()
    awful.spawn.easy_async_with_shell(
        cmd .. " get-sink-volume " .. default_sink .. "; " ..
        cmd .. " get-sink-mute " .. default_sink, function (stdout)
        UpdateStateFromOutput(stdout)
    end)
end

-- Run pactl
local function pacmd_run(command)
    awful.spawn.easy_async(command, function ()
        pulseaudio.UpdateState()
    end)
end

-- Sets the volume of the default sink to vol from 0 to 1.
function pulseaudio.SetVolume(vol)
    if vol > 1 then
        vol = 1
    end
    if vol < 0 then
        vol = 0
    end

    vol = vol * 0x10000
    -- set…
    pacmd_run(
        cmd .. " set-sink-volume " .. default_sink ..
        " " .. string.format("%d", math.floor(vol)))
end

function pulseaudio.IncVolumeBy(increment)
   pulseaudio.SetVolume(pulseaudio.Volume + increment)
end

function pulseaudio.get_increment()
   if pulseaudio.Volume <= 0.5 then
      return default_increment / 4
   elseif pulseaudio.Volume < 0.8 then
      return default_increment / 2
   else
      return default_increment
   end
end

function pulseaudio.VolumeUp()
   local increment = pulseaudio.get_increment()
   pulseaudio.IncVolumeBy(increment)
end

function pulseaudio.VolumeDown()
   local increment = pulseaudio.get_increment()
   pulseaudio.IncVolumeBy(-increment)
end

-- Toggles the mute flag of the default default_sink.
function pulseaudio.VolumeToggleMute()
   if pulseaudio.Mute then
      pacmd_run(cmd .. " set-sink-mute " .. default_sink .. " 0")
   else
      pacmd_run(cmd .. " set-sink-mute " .. default_sink .. " 1")
   end
end

function pulseaudio.start_timer()
   if timer_obj == nil then
      timer_obj = timer { timeout = timer_timeout}
      timer_obj:connect_signal("timeout", pulseaudio.UpdateState)
      timer_obj:start()
   end
end

timer.delayed_call(pulseaudio.UpdateState)
return pulseaudio
