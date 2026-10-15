#!/bin/sh
# Пассивное состояние связи bortd с приборами для индикаторов панели.
# Ничего не отправляет приборам: читает только таблицу соединений ядра и
# открытые файлы процесса bortd.
#
# Аргументы - приборы из bortdrc:
#   net:<хост>:<порт>    TCP/RFC2217; хост может быть именем или IPv4/IPv6
#   tty:<путь>           COM-порт (ссылки /dev/serial/by-id/... и т.п.)
# Имена и ссылки разрешаются при каждом вызове (DNS, переподключение USB).
#
# Вывод (по строке на объект):
#   bortd <pid>|none
#   net <хост:порт> <принято байт>|down     соединение bortd с прибором
#   tty <путь> open|closed                  открыт ли bortd этот порт

pid=$(pgrep -u "$(id -u)" -x bortd | head -n1)
if [ -z "$pid" ]; then
    echo "bortd none"
    exit 0
fi
echo "bortd $pid"

# установленные соединения самого bortd: «<адрес:порт> <принято байт>»;
# ss -n печатает IPv6 как [адрес]:порт
conns=$(ss -tinpH state established 2>/dev/null | awk -v pid="pid=$pid," '
    /^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]/ { peer = $4; mine = index($0, pid) > 0; next }
    mine && peer != "" {
        n = 0
        if (match($0, /bytes_received:[0-9]+/)) n = substr($0, RSTART + 15, RLENGTH - 15)
        print peer, n
        peer = ""
    }')
open_fds=$(for f in /proc/"$pid"/fd/*; do readlink "$f" 2>/dev/null; done)

for dev in "$@"; do
    case "$dev" in
    net:*)
        key=${dev#net:}
        host=${key%:*}; port=${key##*:}
        host=${host#[}; host=${host%]}
        # все адреса хоста (имя, IPv4, IPv6) в том виде, как их печатает ss
        addrs=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u)
        [ -n "$addrs" ] || addrs=$host
        total=
        for a in $addrs; do
            case "$a" in
                *:*) cands="[$a]:$port" ;;
                *)   cands="$a:$port [::ffff:$a]:$port" ;;
            esac
            for c in $cands; do
                n=$(printf '%s\n' "$conns" | awk -v c="$c" '$1 == c {s += $2; f = 1} END {if (f) print s}')
                [ -n "$n" ] && total=$(( ${total:-0} + n ))
            done
        done
        echo "net $key ${total:-down}"
        ;;
    tty:*)
        path=${dev#tty:}
        real=$(readlink -f "$path" 2>/dev/null || echo "$path")
        if [ -e "$real" ] && printf '%s\n' "$open_fds" | grep -qxF "$real"; then
            echo "tty $path open"
        else
            echo "tty $path closed"
        fi
        ;;
    esac
done
