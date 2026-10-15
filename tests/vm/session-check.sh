#!/bin/sh
# Запускается в ВМ от пользователя navdat: поднимает настоящий сеанс
# navdat-awesome под Xvfb, открывает меню и bortcfg, снимает скриншоты.
# Падает, если awesome откатился на системный rc.lua или были ошибки запуска.
export XDG_RUNTIME_DIR=/tmp/xdg-navdat
rm -rf "$XDG_RUNTIME_DIR"; mkdir -m 700 -p "$XDG_RUNTIME_DIR"
cd "$HOME"; rm -f /tmp/shot-*.png /tmp/session.result

xvfb-run -a -s "-screen 0 1280x800x24" sh -c '
  dbus-launch --exit-with-session navdat-awesome-session > /tmp/awesome.log 2>&1 &
  sleep 8
  import -window root /tmp/shot-1-desktop.png
  awesome-client "return awesome.conffile .. \" | errors: \" .. tostring(awesome.startup_errors) .. \" | tags: \" .. #screen[1].tags .. \" | vsegeibar: \" .. tostring(screen[1].vsegeibox ~= nil)" > /tmp/session.result
  awesome-client "mymainmenu:show()"; sleep 1
  import -window root /tmp/shot-2-menu.png
  awesome-client "mymainmenu:hide()"
  navdat-bortcfg > /tmp/bortcfg.log 2>&1 &
  sleep 4
  import -window root /tmp/shot-3-bortcfg.png
  awesome-client "local t={} for _,c in ipairs(client.get()) do t[#t+1]=tostring(c.name) end return table.concat(t, \"; \")" >> /tmp/session.result
  awesome-client "awesome.quit()"; sleep 1'

echo "--- session"; cat /tmp/session.result
echo "--- awesome.log"; grep -vE "no file|AT-SPI|^\s*$|Xlib: ignoring|DeprecationWarning|set_from_icon|set_tooltip" /tmp/awesome.log
echo "--- bortcfg.log"; grep -vE "AT-SPI|^\s*$" /tmp/bortcfg.log

grep -q '/home/navdat/.config/awesome/rc.lua | errors: nil | tags: 4 | vsegeibar: true' /tmp/session.result || {
    echo "FAIL: NavDat rc.lua did not load cleanly"; exit 1; }
grep -q 'Bortd configuration' /tmp/session.result || {
    echo "FAIL: bortcfg window did not open"; exit 1; }
if grep -qiE 'stack traceback|attempt to' /tmp/awesome.log; then
    echo "FAIL: Lua errors in awesome.log"; exit 1
fi
echo "OK: session checks passed"
