#!/bin/sh
# Пассивное состояние связи bortd с приборами для индикаторов панели.
# Ничего не отправляет приборам: читает только таблицу соединений ядра и
# открытые файлы процесса bortd.
#
# Вывод (по строке на объект):
#   bortd <pid>|none
#   tcp <peer-host:port> <bytes_received>    установленные TCP-соединения bortd
#   tty <путь из bortdrc> open|closed       открыт ли bortd этот порт
#
# Аргументы: пути COM-портов из bortdrc (ссылки /dev/serial/by-id/... и т.п.
# разрешаются при каждом вызове, чтобы ловить переподключение USB).

pid=$(pgrep -u "$(id -u)" -x bortd | head -n1)
if [ -z "$pid" ]; then
    echo "bortd none"
    exit 0
fi
echo "bortd $pid"

# только соединения процесса bortd (-p), с внутренней статистикой (-i)
ss -tinpH state established 2>/dev/null | awk -v pid="pid=$pid," '
    /^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]/ { peer = $4; mine = index($0, pid) > 0; next }
    mine && peer != "" {
        n = 0
        if (match($0, /bytes_received:[0-9]+/)) n = substr($0, RSTART + 15, RLENGTH - 15)
        print "tcp", peer, n
        peer = ""
    }'

[ $# -gt 0 ] || exit 0
open_fds=$(for f in /proc/"$pid"/fd/*; do readlink "$f" 2>/dev/null; done)
for dev in "$@"; do
    real=$(readlink -f "$dev" 2>/dev/null || echo "$dev")
    if [ -e "$real" ] && printf '%s\n' "$open_fds" | grep -qxF "$real"; then
        echo "tty $dev open"
    else
        echo "tty $dev closed"
    fi
done
