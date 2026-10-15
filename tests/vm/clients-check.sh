#!/bin/sh
# Запускается в x86-64 ВМ от пользователя navdat после установки настоящих
# (перепакованных) пакетов NavDat. Проверяет без контейнера:
#  1. каждому клиенту хватает библиотек (ldd с /opt/navdat/lib);
#  2. настоящий bortd стартует в демо-режиме и отвечает по протоколу;
#  3. каждый графический клиент из меню NavDat запускается в сеансе
#     navdat-awesome и открывает окно.
export XDG_RUNTIME_DIR=/tmp/xdg-navdat
rm -rf "$XDG_RUNTIME_DIR"; mkdir -m 700 -p "$XDG_RUNTIME_DIR"
cd "$HOME"
pkill -x bortd 2>/dev/null || true
rm -f /tmp/shot-5-*.png /tmp/clients.result /tmp/client-*.log
FAIL=0

echo "--- 1. библиотеки"
for b in /usr/lib/navdat/bin/*; do
    missing=$(LD_LIBRARY_PATH=/opt/navdat/lib ldd "$b" 2>&1 | grep -E 'not found|not a dynamic' || true)
    if [ -n "$missing" ]; then
        echo "FAIL $(basename "$b"): $missing"; FAIL=1
    else
        echo "ok   $(basename "$b")"
    fi
done

# клиенты из ярлыков меню (кроме bortcfg/апплета/сессий)
CLIENTS=$(grep -h '^Exec=' /usr/share/bort/applications/navdat-*.desktop \
    | sed 's/^Exec=//' | grep -vE '^navdat-(bortcfg|applet)\b' | sort -u)

cat > /tmp/bortd_query.py <<'EOF'
import sys, time
sys.path.insert(0, "/usr/share/bort/bortcfg")
import bortd
# bortd со многими приборами (и под эмуляцией) открывает сокет не сразу
for _ in range(60):
    try:
        c = bortd.BortClient()
        break
    except OSError:
        time.sleep(1)
else:
    sys.exit("bortd socket did not appear in 60 s")
c.sync()
while not c._vars:
    c.handle_input()
print("vars=%d demo_mode=%s" % (len(c._vars), c["sys::demo_mode"].get(force=True)))
if len(sys.argv) > 1 and sys.argv[1] == "stop":
    c.stop(); c.sync()
EOF

# все типы приборов, чтобы bortd создал их переменные и клиенты нашли
# свои устройства; источники - закрытые порты, к приборам никто не ходит
cp .bort/bortdrc /tmp/bortdrc.orig
{
    echo "sys::datadir $HOME/data/"
    echo "device fe"; echo "{"; echo "    bind tcp://127.0.0.1:5000"; echo "}"
    port=5901
    for t in jps novatel arrow em4h gtmag geoscan rs50x grs410 gsa2000 parsek-adc \
             gtadc d5000adc ffra smra equator sp4 tvisor tvnew mp719 adis16365 amaster; do
        echo "device $t"; echo "{"; echo "    src tcp://127.0.0.1:$port"; echo "}"
        port=$((port+1))
    done
    echo "device fplan"
} > .bort/bortdrc
trap 'cp /tmp/bortdrc.orig "$HOME/.bort/bortdrc"' EXIT

echo "--- 2. bortd (демо-режим, все типы приборов)"
if ! bortd -d -D > /tmp/bortd.log 2>&1; then
    echo "FAIL: bortd -d -D exited with error"; cat /tmp/bortd.log; exit 1
fi
sleep 1
pgrep -u "$(id -u)" -x bortd >/dev/null || { echo "FAIL: bortd is not running"; cat /tmp/bortd.log; exit 1; }
python3 /tmp/bortd_query.py || { echo "FAIL: bortd does not answer"; FAIL=1; }

echo "--- 3. клиенты в сеансе navdat-awesome"
echo "$CLIENTS" > /tmp/clients.list
xvfb-run -a -s "-screen 0 1600x1000x24" sh -c '
  dbus-launch --exit-with-session navdat-awesome-session > /tmp/awesome-clients.log 2>&1 &
  sleep 10
  n=0
  while read -r cmd; do
    [ -n "$cmd" ] || continue
    n=$((n+1)); name=${cmd%% *}
    before=$(awesome-client "return #client.get()" | awk "{print \$2}")
    $cmd > /tmp/client-$name.log 2>&1 &
    pid=$!
    sleep 6
    after=$(awesome-client "return #client.get()" | awk "{print \$2}")
    title=$(awesome-client "local c=client.focus return c and (tostring(c.class)..\" / \"..tostring(c.name)) or \"-\"" | sed "s/^ *string //")
    if kill -0 $pid 2>/dev/null; then alive=yes; else alive=no; fi
    import -window root /tmp/shot-5-$n-$name.png
    echo "$name alive=$alive windows:$before->$after focus=$title" >> /tmp/clients.result
    kill $pid 2>/dev/null; sleep 1; kill -9 $pid 2>/dev/null
  done < /tmp/clients.list
  awesome-client "awesome.quit()"; sleep 1'

cat /tmp/clients.result
while read -r line; do
    name=${line%% *}
    case "$line" in
        *alive=yes*) ;;
        *) echo "FAIL: $name exited"; sed -n '1,15p' /tmp/client-$name.log; FAIL=1 ;;
    esac
    after=$(echo "$line" | sed -n 's/.*windows:\([0-9]*\)->\([0-9]*\).*/\2/p')
    before=$(echo "$line" | sed -n 's/.*windows:\([0-9]*\)->.*/\1/p')
    [ "${after:-0}" -gt "${before:-0}" ] || { echo "FAIL: $name opened no window"; FAIL=1; }
done < /tmp/clients.result

echo "--- bortd остановка"
python3 /tmp/bortd_query.py stop >/dev/null 2>&1 || true
for _ in $(seq 1 30); do pgrep -x bortd >/dev/null || break; sleep 1; done
if pgrep -x bortd >/dev/null; then
    echo "FAIL: bortd did not stop on CMD_STOP"; pkill -x bortd; FAIL=1
else
    echo "bortd stopped by CMD_STOP"
fi
echo "--- bortd.log"; tail -20 /tmp/bortd.log

[ $FAIL = 0 ] && echo "OK: all clients start without the container" || { echo "FAIL: see above"; exit 1; }
