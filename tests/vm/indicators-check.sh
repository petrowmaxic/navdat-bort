#!/bin/sh
# Запускается в ВМ от пользователя navdat. Проверяет, что индикаторы связи
# в верхней панели не подключаются к приборам и верно показывают состояние.
#
# Имитация: LIVE (127.0.0.1:4101) шлёт данные, IDLE (:4102) молчит, DOWN (:4103)
# не слушается. "bortd" подключается к LIVE и IDLE по одному разу. Приборы
# считают входящие соединения и принятые байты: должно быть ровно одно
# соединение и ноль байт.
set -e
export XDG_RUNTIME_DIR=/tmp/xdg-navdat
rm -rf "$XDG_RUNTIME_DIR"; mkdir -m 700 -p "$XDG_RUNTIME_DIR"
cd "$HOME"

mkdir -p .config/navdat
cat > .config/navdat/devices.lua <<'EOF'
return {
    { name = "LIVE", host = "127.0.0.1", port = 4101 },
    { name = "IDLE", host = "127.0.0.1", port = 4102 },
    { name = "DOWN", host = "127.0.0.1", port = 4103 },
}
EOF

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
time.sleep(0.5)
# "bortd": one connection per device, reads forever
for p in (4101, 4102):
    def client(p=p):
        c = socket.create_connection(("127.0.0.1", p))
        while c.recv(4096): pass
    threading.Thread(target=client, daemon=True).start()
while True:
    json.dump(stats, open("/tmp/fake_devices.json", "w")); time.sleep(0.5)
EOF
python3 /tmp/fake_devices.py & FAKE=$!

xvfb-run -a -s "-screen 0 1280x800x24" sh -c '
  dbus-launch --exit-with-session navdat-awesome-session > /tmp/awesome-ind.log 2>&1 &
  sleep 14
  import -window root /tmp/shot-4-indicators.png
  awesome-client "local t={} for _,d in ipairs(require(\"connection_status\").devices) do t[#t+1]=d.peer..\"=\"..tostring(d.state) end return table.concat(t, \" \")" > /tmp/indicators.result
  awesome-client "awesome.quit()"; sleep 1'
kill $FAKE

echo "--- indicators"; cat /tmp/indicators.result
echo "--- device side [connections, bytes received]"; cat /tmp/fake_devices.json; echo
grep -q '127.0.0.1:4101=ok 127.0.0.1:4102=stale 127.0.0.1:4103=down' /tmp/indicators.result || {
    echo "FAIL: wrong indicator states"; exit 1; }
python3 -c 'import json,sys; s=json.load(open("/tmp/fake_devices.json")); sys.exit(0 if all(v==[1,0] for v in s.values()) else 1)' || {
    echo "FAIL: indicators touched the devices"; exit 1; }
echo "OK: indicators are passive and correct"
