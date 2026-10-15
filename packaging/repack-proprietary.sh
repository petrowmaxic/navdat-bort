#!/bin/bash
# Перепаковка оригинальных (закрытых) пакетов NavDat 0.2.12 для Ubuntu 24.04.
#
#   packaging/repack-proprietary.sh <каталог с оригинальными deb> [выходной каталог]
#
# navdat-bortd   - бинарник нужен только glibc/libstdc++, работает нативно;
#                  меняется лишь зависимость libgcc1 -> libgcc-s1.
# navdat-clients-* - Qt4/Qwt/libglade2 в 24.04 нет, поэтому /usr/bin/* заменяются
#                  обёртками "navdat-legacy run <клиент>", а ярлыки, меню,
#                  иконки и переводы ставятся на хост как есть.
# navdat-full    - метапакет, копируется без изменений.
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

fix_bortd() {
    sed -i 's/libgcc1 ([^)]*)/libgcc-s1/' "$1/DEBIAN/control"
}

wrap_clients() {
    local f name
    for f in "$1"/usr/bin/*; do
        name=$(basename "$f")
        printf '#!/bin/sh\nexec navdat-legacy run %s "$@"\n' "$name" > "$f"
        chmod 755 "$f"
    done
    sed -i -E 's/^Depends: .*/Depends: navdat-legacy, navdat-help/' "$1/DEBIAN/control"
    sed -i -E 's/^Architecture: .*/Architecture: all/' "$1/DEBIAN/control"
}

keep() { :; }

for deb in "$SRC"/navdat-bortd_*.deb; do repack "$deb" fix_bortd; done
for deb in "$SRC"/navdat-clients-*_*.deb; do repack "$deb" wrap_clients; done
for deb in "$SRC"/navdat-full_*.deb; do repack "$deb" keep; done
