#!/bin/sh
# Запускается в ВМ от пользователя navdat. Проверяет индикаторы связи:
#  - список строится из ~/.bort/bortdrc и обновляется при его изменении;
#  - состояние берётся пассивно у процесса bortd, к приборам никто, кроме
#    bortd, не подключается и не пишет.
#
# Имитация приборов: 127.0.0.1:4101 шлёт данные, :4102 молчит (в bortdrc задан
# именем localhost - проверка разрешения имён), :4103 не слушает.
# Имитация bortd: процесс с именем bortd подключается к 4101 и 4102 и держит
# открытым псевдотерминал /tmp/ttyFAKE.
set -e
export XDG_RUNTIME_DIR=/tmp/xdg-navdat
rm -rf "$XDG_RUNTIME_DIR"; mkdir -m 700 -p "$XDG_RUNTIME_DIR"
cd "$HOME"
pkill -x bortd 2>/dev/null || true

cp .bort/bortdrc /tmp/bortdrc.orig
cat > .bort/bortdrc <<'EOF'
sys::datadir /home/navdat/data/
device fe
{
    bind tcp://127.0.0.1:5000
}
device rs50x
{
    src tcp://127.0.0.1:4101
}
device rs50x
{
    src tcp://localhost:4102
}
device novatel
{
    src rfc2217://127.0.0.1:4103/115200,8,n,1
}
device gtmag
{
    src serial:///tmp/ttyFAKE,115200,8,n,1
}
device jps
{
    src serial:///tmp/ttyNONE,115200,8,n,1
}
device fplan
EOF
mkdir -p .config/navdat
echo 'return { ["127.0.0.1:4101"] = "RS61" }' > .config/navdat/devices.lua

cat > /tmp/fake_devices.py <<'EOF'
import socket, threading, time, json
stats = {4101: [0, 0], 4102: [0, 0]}   # port -> [connections, bytes received]
def serve(port, talk):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", port)); s.listen(5)
    while True:
        c, _ = s.accept(); stats[port][0] += 1
        def handle(c=c):
            c.settimeout(0.2)
            while True:
                if talk:
                    try: c.sendall(b"$GPGGA,data\r\n")
                    except OSError: return
                try:
                    d = c.recv(100)
                    if d == b"": return
                    stats[port][1] += len(d)
                except socket.timeout: pass
                except OSError: return
        threading.Thread(target=handle, daemon=True).start()
for p, t in ((4101, True), (4102, False)):
    threading.Thread(target=serve, args=(p, t), daemon=True).start()
while True:
    json.dump(stats, open("/tmp/fake_devices.json", "w")); time.sleep(0.5)
EOF

cat > /tmp/fake_bortd.py <<'EOF'
import os, socket, threading, time
master, slave = os.openpty()
name = os.ttyname(slave)
if os.path.lexists("/tmp/ttyFAKE"): os.unlink("/tmp/ttyFAKE")
os.symlink(name, "/tmp/ttyFAKE")
fd = os.open("/tmp/ttyFAKE", os.O_RDWR | os.O_NOCTTY)   # bortd держит порт открытым
os.close(slave)
for p in (4101, 4102):
    def client(p=p):
        c = socket.create_connection(("127.0.0.1", p))
        while c.recv(4096): pass
    threading.Thread(target=client, daemon=True).start()
while True: time.sleep(1)
EOF
mkdir -p /tmp/fakebin && cp "$(readlink -f /usr/bin/python3)" /tmp/fakebin/bortd

python3 /tmp/fake_devices.py & DEVICES=$!

QUERY='local t={} for _,i in ipairs(require(\"connection_status\").indicators) do t[#t+1]=i.label..\"=\"..i.state end return table.concat(t, \" \")'
xvfb-run -a -s "-screen 0 1280x800x24" sh -c "
  dbus-launch --exit-with-session navdat-awesome-session > /tmp/awesome-ind.log 2>&1 &
  sleep 6
  awesome-client \"$QUERY\" > /tmp/ind-1.txt
  /tmp/fakebin/bortd /tmp/fake_bortd.py & echo \$! > /tmp/fake_bortd.pid
  sleep 12
  awesome-client \"$QUERY\" > /tmp/ind-2.txt
  import -window root /tmp/shot-4-indicators.png
  sed -i '/^device jps/,/^}/d' \$HOME/.bort/bortdrc
  sleep 4
  awesome-client \"$QUERY\" > /tmp/ind-3.txt
  awesome-client 'awesome.quit()'; sleep 1"
kill "$(cat /tmp/fake_bortd.pid)" $DEVICES 2>/dev/null || true
cp /tmp/bortdrc.orig .bort/bortdrc; rm -f .config/navdat/devices.lua

echo "--- 1. bortd не запущен:"; cat /tmp/ind-1.txt
echo "--- 2. bortd работает:";   cat /tmp/ind-2.txt
echo "--- 3. jps убран из bortdrc:"; cat /tmp/ind-3.txt
echo "--- со стороны приборов [подключений, принято байт]:"; cat /tmp/fake_devices.json; echo

fail() { echo "FAIL: $1"; exit 1; }
grep -q '"RS61=off RS4102=off NV=off MG=off JPS=off"' /tmp/ind-1.txt || fail "bortd stopped: expected all off"
grep -q '"RS61=ok RS4102=stale NV=down MG=ok JPS=down"' /tmp/ind-2.txt || fail "bortd running: wrong states"
grep -q '"RS61=ok RS4102=stale NV=down MG=ok"' /tmp/ind-3.txt || fail "list did not follow bortdrc"
python3 -c 'import json,sys; s=json.load(open("/tmp/fake_devices.json")); sys.exit(0 if all(v==[1,0] for v in s.values()) else 1)' \
    || fail "indicators touched the devices"
if grep -qiE 'stack traceback|attempt to' /tmp/awesome-ind.log; then fail "Lua errors"; fi
echo "OK: indicators follow bortdrc and are passive"
