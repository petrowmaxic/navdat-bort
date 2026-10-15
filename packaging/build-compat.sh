#!/bin/bash
# Пакет navdat-compat: старые библиотеки, которых нет в современной Ubuntu,
# для закрытых клиентов NavDat (Qt4, Qwt, libpng12, libaudio, libFOX).
#
#   packaging/build-compat.sh <каталог с оригинальными deb NavDat> [выходной каталог]
#
# Qt4, Qwt, libpng12 и libaudio скачиваются из архива Ubuntu 16.04 по
# зафиксированным версиям и SHA256. libFOX берётся из оригинального пакета
# libfox-gt. Всё кладётся в /opt/navdat/lib; клиенты запускаются через
# обёртки с LD_LIBRARY_PATH (см. repack-proprietary.sh).
set -euo pipefail

SRC=$(cd "${1:?usage: $0 <dir-with-original-debs> [outdir]}" && pwd)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mkdir -p "${2:-$ROOT/dist}" && cd "${2:-$ROOT/dist}" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ARCHIVE=${UBUNTU_ARCHIVE:-http://archive.ubuntu.com/ubuntu}
CACHE=${NAVDAT_COMPAT_CACHE:-$HOME/.cache/navdat-compat}
mkdir -p "$CACHE"

# sha256  путь в архиве Ubuntu 16.04
DEBS="
b5f25c03f05f994577e4b8dc8c125b7835a43aa12269be36676007db327d7e71 pool/main/q/qt4-x11/libqtcore4_4.8.7+dfsg-5ubuntu2_amd64.deb
90bf975ae02072cf89f12d1036d26d924894351bcf6e32190828d5b1f31e23bd pool/main/q/qt4-x11/libqtgui4_4.8.7+dfsg-5ubuntu2_amd64.deb
bd1def9898b48cba1e2820a81c149d9050027f4bc8a3e8205ee6991d8e36511d pool/main/q/qt4-x11/libqt4-network_4.8.7+dfsg-5ubuntu2_amd64.deb
64c2b5d75620dd5210c9710427e6917754f443283950eb38079415025a0fb64e pool/main/q/qt4-x11/libqt4-opengl_4.8.7+dfsg-5ubuntu2_amd64.deb
6e566c219ab973fd25764a14e1d8e69d7a4c58c8dee5acc0ec73e817c38addce pool/main/q/qt4-x11/libqt4-svg_4.8.7+dfsg-5ubuntu2_amd64.deb
b54981a75c5c00689adf0ee8ccfbf5eff713a35875a1aebe357f822f94afa8f2 pool/universe/q/qwt/libqwt6abi1_6.1.2-5_amd64.deb
9d938a376dafd1668827ceeb742f18b164c390e53774b06eaaf644713b6ffb25 pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1_amd64.deb
96cab20c82d3a8ab0c2248cd85c1b004be94e9966502782a8f844c43f213159e pool/main/n/nas/libaudio2_1.9.4-4_amd64.deb
"

P=navdat-compat
LIB=$WORK/$P/opt/navdat/lib
mkdir -p "$LIB" "$WORK/$P/DEBIAN" "$WORK/x"

echo "$DEBS" | while read -r sha path; do
    [ -n "$sha" ] || continue
    f=$CACHE/$(basename "$path")
    if [ ! -f "$f" ]; then
        curl -fsSL -o "$f.part" "$ARCHIVE/$path"
        mv "$f.part" "$f"
    fi
    echo "$sha  $f" | sha256sum -c --quiet - || { rm -f "$f"; exit 1; }
    dpkg-deb -x "$f" "$WORK/x"
done

fox=$(ls "$SRC"/libfox-gt_*_amd64.deb | head -n1)
dpkg-deb -x "$fox" "$WORK/x"

# только сами библиотеки, без плагинов Qt и документации
find "$WORK/x" \( -name 'libQtCore.so.4*' -o -name 'libQtGui.so.4*' \
    -o -name 'libQtNetwork.so.4*' -o -name 'libQtOpenGL.so.4*' -o -name 'libQtSvg.so.4*' \
    -o -name 'libqwt.so.6*' -o -name 'libpng12.so.0*' -o -name 'libaudio.so.2*' \
    -o -name 'libFOX-gt-1.6.so.0*' \) \( -type f -o -type l \) -exec cp -P {} "$LIB/" \;

cat > "$WORK/$P/DEBIAN/control" <<EOF
Package: $P
Version: 1.0
Architecture: amd64
Maintainer: NavDat port <navdat@localhost>
Depends: libc6, libstdc++6, libgcc-s1, zlib1g, libglib2.0-0t64 | libglib2.0-0, libfontconfig1, libfreetype6, libsm6, libice6, libxi6, libxrender1, libxext6, libx11-6, libxt6t64 | libxt6, libxau6, libgl1
Section: libs
Priority: optional
Description: Legacy libraries for NavDat clients (Qt4, Qwt, libpng12, libFOX)
 Libraries from Ubuntu 16.04 installed to /opt/navdat/lib for the
 proprietary NavDat clients built against them.
EOF
chmod -R u=rwX,go=rX "$WORK/$P"
dpkg-deb --root-owner-group --build "$WORK/$P" "$OUT" >/dev/null
echo "built $P"; ls "$LIB"
