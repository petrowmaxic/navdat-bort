#!/bin/bash
# Сборка офлайн-комплекта NavDat для установки без интернета.
#
#   sudo install/build-offline-bundle.sh <каталог с оригинальными deb NavDat> [выходной каталог]
#
# Запускать на Ubuntu той же версии и архитектуры, что и целевые ноутбуки
# (сейчас 24.04 amd64), с доступом в интернет. Результат — каталог
#   navdat-offline-<ubuntu>-amd64/
#       navdat-install.sh       мастер (видит комплект и работает без сети)
#       repo/                   локальный репозиторий apt: пакеты NavDat и
#                               ВСЕ их зависимости из Ubuntu (полное дерево)
#   и архив navdat-offline-<ubuntu>-amd64.tar рядом с ним.
#
# Полное дерево зависимостей скачивается так, будто в системе ничего не
# установлено (пустой dpkg status), поэтому комплект ставится и на
# ноутбук с более старыми пакетами Ubuntu 24.04, чем у сборочной машины.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
SRC=$(cd "${1:?usage: $0 <dir-with-original-debs> [outdir]}" && pwd)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTDIR=$(mkdir -p "${2:-$ROOT/dist}" && cd "${2:-$ROOT/dist}" && pwd)
. /etc/os-release
NAME=navdat-offline-$VERSION_ID-$(dpkg --print-architecture)
BUNDLE=$OUTDIR/$NAME
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq dpkg-dev curl python3 >/dev/null

echo "== NavDat packages"
"$ROOT/packaging/build-debs.sh" "$WORK/navdat"
NAVDAT_COMPAT_CACHE="$WORK/compat-cache" "$ROOT/packaging/repack-proprietary.sh" "$SRC" "$WORK/navdat"

echo "== Ubuntu dependencies (full tree)"
mkdir -p "$WORK/archives/partial" "$WORK/state"
: > "$WORK/state/status"
# apt считает систему пустой и скачивает всё дерево зависимостей.
# Рекомендуемые пакеты тоже: обычная установка их ставит, и без них,
# например, не будет видеодрайверов X (xserver-xorg-video-all) и
# accountsservice — найдено проверкой на ВМ без интернета.
apt-get install -y -q --download-only \
    -o Dir::State::status="$WORK/state/status" \
    -o Dir::Cache::archives="$WORK/archives" \
    -o Debug::NoLocking=1 \
    "$WORK"/navdat/*.deb >"$WORK/apt.log" 2>&1 \
    || { tail -30 "$WORK/apt.log"; echo "dependency download failed" >&2; exit 1; }

echo "== local repository"
rm -rf "$BUNDLE"; mkdir -p "$BUNDLE/repo"
cp "$WORK"/archives/*.deb "$WORK"/navdat/*.deb "$BUNDLE/repo/"
(cd "$BUNDLE/repo" && dpkg-scanpackages --multiversion . /dev/null > Packages 2>/dev/null \
    && gzip -9k Packages && sha256sum *.deb > SHA256SUMS)
install -m 755 "$ROOT/install/navdat-install.sh" "$BUNDLE/"
cat > "$BUNDLE/README.txt" <<EOF
Офлайн-комплект NavDat для Ubuntu $VERSION_ID ($(dpkg --print-architecture)).

Скопируйте каталог $NAME на ноутбук (например, с флешки) и запустите:

    bash $NAME/navdat-install.sh

Интернет не нужен. Мастер спросит пароль оператора navdat, автовход и
пароль администратора ноутбука.
EOF
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$BUNDLE"

tar -C "$OUTDIR" -cf "$OUTDIR/$NAME.tar" "$NAME"
chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUTDIR/$NAME.tar"
echo "packages: $(ls "$BUNDLE/repo"/*.deb | wc -l), size: $(du -sh "$BUNDLE" | cut -f1)"
echo "bundle: $OUTDIR/$NAME.tar"
