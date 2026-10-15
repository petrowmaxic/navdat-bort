#!/bin/bash
# Перепаковка оригинальных (закрытых) пакетов NavDat 0.2.12 для Ubuntu 24.04+.
#
#   packaging/repack-proprietary.sh <каталог с оригинальными deb> [выходной каталог]
#
# navdat-bortd     - бинарнику нужны только glibc/libstdc++, работает нативно;
#                    меняется лишь зависимость libgcc1 -> libgcc-s1.
# navdat-clients-* - работают нативно. Бинарники переносятся в
#                    /usr/lib/navdat/bin, а /usr/bin/<клиент> становится обёрткой,
#                    добавляющей /opt/navdat/lib (Qt4, Qwt, libpng12, libFOX из
#                    пакета navdat-compat). Зависимости от библиотек, которых нет
#                    в новой Ubuntu, заменяются на navdat-compat.
# navdat-full      - метапакет, копируется без изменений.
# navdat-compat    - собирается packaging/build-compat.sh.
set -euo pipefail

SRC=$(cd "${1:?usage: $0 <dir-with-original-debs> [outdir]}" && pwd)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mkdir -p "${2:-$ROOT/dist}" && cd "${2:-$ROOT/dist}" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

repack() {   # repack <deb> <hook>
    local deb=$1 dir
    dir=$WORK/$(basename "$deb" .deb)
    dpkg-deb -R "$deb" "$dir"
    sed -i -E 's/^(Version: .*)$/\1+noble1/' "$dir/DEBIAN/control"
    "$2" "$dir"
    rm -f "$dir/DEBIAN/md5sums"
    dpkg-deb --root-owner-group --build "$dir" "$OUT" >/dev/null
    echo "repacked $(basename "$deb")"
}

# Depends: убрать то, что даёт navdat-compat, и переименованные в новой Ubuntu
fix_depends() {
    python3 - "$1/DEBIAN/control" <<'EOF'
import re, sys
path = sys.argv[1]
text = open(path).read()
m = re.search(r'^Depends: (.*)$', text, re.M)
if m:
    out = []
    for dep in [d.strip() for d in m.group(1).split(',')]:
        name = dep.split()[0]
        if re.match(r'(libqt|libqwt|libfox-gt|libpng12)', name):
            continue
        if name == 'libgcc1':
            dep = 'libgcc-s1'
        elif name in ('libglib2.0-0', 'libgtk2.0-0'):
            dep = '%st64 | %s' % (name, name)     # 64-bit time_t rename (24.04)
        out.append(dep)
    out.append('navdat-compat')   # обёртки клиентов берут библиотеки из /opt/navdat/lib
    text = text[:m.start(1)] + ', '.join(dict.fromkeys(out)) + text[m.end(1):]
    open(path, 'w').write(text)
EOF
}

fix_bortd() {
    sed -i 's/libgcc1 ([^)]*)/libgcc-s1/' "$1/DEBIAN/control"
}

wrap_clients() {
    local f name
    mkdir -p "$1/usr/lib/navdat/bin"
    for f in "$1"/usr/bin/*; do
        name=$(basename "$f")
        mv "$f" "$1/usr/lib/navdat/bin/$name"
        cat > "$f" <<EOF
#!/bin/sh
# NavDat client built for Ubuntu 16.04: legacy libraries live in /opt/navdat/lib
export LD_LIBRARY_PATH=/opt/navdat/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
exec /usr/lib/navdat/bin/$name "\$@"
EOF
        chmod 755 "$f"
    done
    fix_depends "$1"
}

keep() { :; }

for deb in "$SRC"/navdat-bortd_*.deb; do repack "$deb" fix_bortd; done
for deb in "$SRC"/navdat-clients-*_*.deb; do repack "$deb" wrap_clients; done
for deb in "$SRC"/navdat-full_*.deb; do repack "$deb" keep; done
"$ROOT/packaging/build-compat.sh" "$SRC" "$OUT"
