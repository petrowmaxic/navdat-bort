#!/bin/bash
# Сборка открытых пакетов NavDat для Ubuntu 24.04 из этого репозитория.
#
#   packaging/build-debs.sh [каталог-для-пакетов]   (по умолчанию dist/)
#
# Собираются: navdat-bortcfg, navdat-help, navdat-awesome-config,
# navdat-user, navdat-legacy. Нужен только dpkg-deb.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mkdir -p "${1:-$ROOT/dist}" && cd "${1:-$ROOT/dist}" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

MAINTAINER="NavDat port <navdat@localhost>"

# control <pkg> <version> <arch> <depends> <description> [recommends]
control() {
    local dir=$WORK/$1
    mkdir -p "$dir/DEBIAN"
    {
        echo "Package: $1"
        echo "Version: $2"
        echo "Architecture: $3"
        echo "Maintainer: $MAINTAINER"
        [ -n "$4" ] && echo "Depends: $4"
        [ -n "${6:-}" ] && echo "Recommends: $6"
        echo "Section: misc"
        echo "Priority: optional"
        echo "Description: $5"
    } > "$dir/DEBIAN/control"
}

build() {
    find "$WORK/$1" -name __pycache__ -prune -exec rm -rf {} +
    find "$WORK/$1" -name .DS_Store -delete
    # права из рабочей копии (например 600 на macOS) не должны попасть в пакет
    chmod -R u=rwX,go=rX "$WORK/$1"
    dpkg-deb --root-owner-group --build "$WORK/$1" "$OUT" >/dev/null
    echo "built $1"
}

# --- navdat-bortcfg ---------------------------------------------------------
P=navdat-bortcfg
control $P 0.3.0 all \
    "python3, python3-gi, gir1.2-gtk-3.0, navdat-bortd" \
    "Navdat - configuration manager (Python 3 / GTK 3)" \
    "navdat-help"
install -d "$WORK/$P/usr/share/bort/bortcfg/serialsel" \
           "$WORK/$P/usr/share/bort/applications" "$WORK/$P/usr/bin"
install -m 644 "$ROOT"/bort/bortcfg/*.py "$ROOT"/bort/bortcfg/bortcfg.ui \
    "$WORK/$P/usr/share/bort/bortcfg/"
install -m 644 "$ROOT"/bort/bortcfg/serialsel/*.py "$WORK/$P/usr/share/bort/bortcfg/serialsel/"
for d in navdat-bortcfg navdat-applet navdat-session-save navdat-session-restore; do
    install -m 644 "$ROOT/bort/applications/$d.desktop" "$WORK/$P/usr/share/bort/applications/"
done
install -m 755 "$ROOT"/bort/bin/navdat-bortcfg "$ROOT"/bort/bin/navdat-applet "$WORK/$P/usr/bin/"
build $P

# --- navdat-help ------------------------------------------------------------
P=navdat-help
control $P 0.3.0 all "xdg-utils" "Navdat documentation in HTML format"
install -d "$WORK/$P/usr/share/navdat" "$WORK/$P/usr/bin"
cp -R "$ROOT/navdat/help" "$WORK/$P/usr/share/navdat/"
install -m 755 "$ROOT/navdat/bin/navdat-help" "$WORK/$P/usr/bin/"
build $P

# --- navdat-awesome-config --------------------------------------------------
P=navdat-awesome-config
control $P 0.1.0 all \
    "awesome (>= 4.3), awesome-extra, ubuntu-mono, librsvg2-common, picom, dex, zenity, rofi, pavucontrol, pulseaudio-utils, network-manager-gnome, lightdm, x11-xserver-utils" \
    "Navdat Awesome WM configuration files" \
    "navdat-bortcfg, navdat-help, gnome-control-center, gnome-terminal, nautilus, gsimplecal, xbacklight, gnome-keyring"
A=$WORK/$P/usr/share/navdat-awesome-config
install -d "$A" "$WORK/$P/usr/share/xsessions" "$WORK/$P/usr/bin"
(cd "$ROOT/navdat-awesome-config" && tar cf - --exclude=session --exclude=.DS_Store .) | tar xf - -C "$A"
chmod 755 "$A/startup.sh"
install -m 644 "$ROOT/navdat-awesome-config/session/navdat-awesome.desktop" "$WORK/$P/usr/share/xsessions/"
install -m 755 "$ROOT/navdat-awesome-config/session/navdat-awesome-session" \
               "$ROOT/navdat-awesome-config/session/navdat-session-quit" "$WORK/$P/usr/bin/"
build $P

# --- navdat-user ------------------------------------------------------------
P=navdat-user
control $P 0.7.0 all "adduser, navdat-awesome-config, lightdm, mc, vim-nox" \
    "Navdat system operator user" "navdat-full"
install -d "$WORK/$P/usr/share/navdat-user"
cp -R "$ROOT/packaging/navdat-user/skel" "$WORK/$P/usr/share/navdat-user/"
install -m 755 "$ROOT/packaging/navdat-user/postinst" "$WORK/$P/DEBIAN/postinst"
build $P

# --- navdat-legacy ----------------------------------------------------------
P=navdat-legacy
control $P 0.1.0 all "podman" \
    "Run proprietary Ubuntu 16.04 NavDat clients in a container"
install -d "$WORK/$P/usr/share/navdat-legacy" "$WORK/$P/usr/bin"
install -m 644 "$ROOT/legacy/Containerfile" "$WORK/$P/usr/share/navdat-legacy/"
install -m 755 "$ROOT/legacy/navdat-legacy" "$WORK/$P/usr/bin/"
build $P

ls -1 "$OUT"
