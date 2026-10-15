#!/bin/sh
# Автозапуск сеанса NavDat. Вызывается из rc.lua при каждом (пере)запуске
# awesome, но выполняется один раз за вход в систему.

STAMP="${XDG_RUNTIME_DIR:-/tmp}/navdat-autostart.$(id -u)"
[ -e "$STAMP" ] && exit 0
touch "$STAMP"

# XDG autostart: navdat-applet, nm-applet, picom (замена compton) и т.п.
command -v dex >/dev/null 2>&1 && dex --autostart --environment Navdat &

SCRIPT_PATH=$HOME/.navdatrc

if [ -x "$SCRIPT_PATH" ]; then
    $SCRIPT_PATH
fi
