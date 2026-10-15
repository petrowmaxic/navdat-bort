#!/bin/bash
# Локальная проверка порта в виртуальной машине Ubuntu 24.04 (QEMU, без Docker).
#
#   tests/vm/run.sh            поднять ВМ (если не запущена) и прогнать всё
#   VM_ARCH=amd64 tests/vm/run.sh     x86-64 ВМ (на ARM-хосте — эмуляция TCG, медленно)
#   NAVDAT_DEBS=<каталог> ...         ещё и настоящие закрытые пакеты NavDat:
#                                     перепаковка, bortd в демо-режиме, все клиенты (только amd64)
#   VM_ARCH=amd64 NAVDAT_DEBS=<каталог> tests/vm/run.sh install
#                              мастер установки на ЧИСТОЙ ВМ (отдельный VM_DIR):
#                              имитация GitHub, ответы как у человека, перезагрузка,
#                              проверка автовхода в сеанс Navdat Awesome
#   VM_ARCH=amd64 NAVDAT_DEBS=<каталог> tests/vm/run.sh bundle
#                              собрать офлайн-комплект в ВМ с интернетом,
#                              архив -> $VM_DIR/bundle/
#   VM_ARCH=amd64 NAVDAT_BUNDLE_TAR=<архив> tests/vm/run.sh offline-install
#                              ЧИСТАЯ ВМ без интернета (отдельный VM_DIR): комплект
#                              как с флешки, мастер, перезагрузка, проверка автовхода
#   tests/vm/run.sh gui        запустить ВМ с окном на экране (посмотреть и
#                              понажимать); также доступна по VNC 127.0.0.1:5901
#   tests/vm/run.sh ssh [cmd]  зайти в ВМ
#   tests/vm/run.sh stop       выключить ВМ
#
# Что делает: юнит-тесты bortcfg под Xvfb, сборка и установка deb-пакетов
# (с заглушкой закрытого navdat-bortd), настоящий X-сеанс navdat-awesome от
# пользователя navdat, открытие меню и bortcfg, скриншоты в $VM_DIR/shots.
#
# Нужно: qemu (brew install qemu на macOS или qemu-system-* на Linux), curl, rsync.
# Образ и диск ВМ лежат в $VM_DIR (по умолчанию ~/.cache/navdat-vm-<arch>).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAVDAT_DEBS=${NAVDAT_DEBS:+$(cd "$NAVDAT_DEBS" && pwd)}

case "$(uname -m)" in
    arm64|aarch64) HOST_ARCH=arm64 ;;
    *)             HOST_ARCH=amd64 ;;
esac
ARCH=${VM_ARCH:-$HOST_ARCH}
case "$ARCH" in
    arm64) QEMU=qemu-system-aarch64; MACHINE=virt; FW_NAME=edk2-aarch64-code.fd ;;
    amd64) QEMU=qemu-system-x86_64;  MACHINE=q35;  FW_NAME= ;;   # SeaBIOS
    *)     echo "unsupported VM_ARCH=$ARCH" >&2; exit 1 ;;
esac
if [ "$ARCH" != "$HOST_ARCH" ]; then
    ACCEL="tcg,thread=multi"; CPU=max
else
    case "$(uname -s)" in Darwin) ACCEL=hvf ;; *) ACCEL=kvm ;; esac
    CPU=host
fi
if [ -n "$NAVDAT_DEBS" ] && [ "$ARCH" != amd64 ]; then
    echo "NAVDAT_DEBS needs an amd64 VM (VM_ARCH=amd64)" >&2; exit 1
fi

VM_DIR=${VM_DIR:-$HOME/.cache/navdat-vm-$ARCH}
PORT=${VM_SSH_PORT:-2222}
mkdir -p "$VM_DIR"
cd "$VM_DIR"

SSH_OPTS=(-q -i "$VM_DIR/id_vm" -p "$PORT" -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3)
SCP_OPTS=(-q -i "$VM_DIR/id_vm" -P "$PORT" -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null)
vssh() { ssh "${SSH_OPTS[@]}" ubuntu@127.0.0.1 "$@"; }

prepare() {
    local img=noble-server-cloudimg-$ARCH.img
    local url=https://cloud-images.ubuntu.com/noble/current
    if [ ! -f "$img" ]; then
        curl -fL -o "$img.part" "$url/$img"
        curl -fsSL "$url/SHA256SUMS" | grep " \*$img\$" | sed "s/\*$img\$/*$img.part/" | shasum -a 256 -c -
        mv "$img.part" "$img"
    fi
    [ -f id_vm ] || ssh-keygen -q -t ed25519 -N '' -f id_vm
    if [ ! -f disk.qcow2 ]; then
        qemu-img create -q -f qcow2 -F qcow2 -b "$img" disk.qcow2 20G
        mkdir -p seed
        printf '#cloud-config\nusers:\n  - name: ubuntu\n    sudo: ALL=(ALL) NOPASSWD:ALL\n    shell: /bin/bash\n    ssh_authorized_keys:\n      - %s\nssh_pwauth: false\n' \
            "$(cat id_vm.pub)" > seed/user-data
        printf 'instance-id: navdat-test\nlocal-hostname: navdat-test\n' > seed/meta-data
        rm -f seed.iso
        if command -v hdiutil >/dev/null; then
            hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o seed.iso seed
        else
            genisoimage -quiet -output seed.iso -volid cidata -joliet -rock seed/user-data seed/meta-data
        fi
    fi
    if [ -n "$FW_NAME" ] && [ ! -f efi-code.fd ]; then
        local fw
        fw=$(ls "$(dirname "$(command -v $QEMU)")"/../share/qemu/$FW_NAME /usr/share/qemu/$FW_NAME 2>/dev/null | head -n1)
        cp "$fw" efi-code.fd
        dd if=/dev/zero of=efi-vars.fd bs=1048576 count=64 2>/dev/null
    fi
}

DISPLAY_OPTS=(-display none)
start() {
    vssh true 2>/dev/null && return
    prepare
    local fw=()
    [ -n "$FW_NAME" ] && fw=(-drive if=pflash,format=raw,file=efi-code.fd,readonly=on
                             -drive if=pflash,format=raw,file=efi-vars.fd)
    local qemu_args=(-machine $MACHINE -accel $ACCEL -cpu $CPU -smp 4 -m 4096 ${fw[@]+"${fw[@]}"}
        -drive if=virtio,format=qcow2,file=disk.qcow2
        -drive if=virtio,format=raw,file=seed.iso,readonly=on
        -netdev user,id=n0${VM_OFFLINE:+,restrict=on},hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0
        "${DISPLAY_OPTS[@]}" -serial file:serial.log -monitor none)
    if [ "${DAEMON:-yes}" = yes ]; then
        $QEMU "${qemu_args[@]}" -daemonize -pidfile qemu.pid
    else
        nohup $QEMU "${qemu_args[@]}" > qemu-gui.log 2>&1 &
        echo $! > qemu.pid
        disown
    fi
    echo "waiting for VM..."
    for _ in $(seq 1 360); do vssh 'cloud-init status --wait >/dev/null' 2>/dev/null && return; sleep 5; done
    echo "VM did not come up, see $VM_DIR/serial.log" >&2; exit 1
}

case "${1:-run}" in
    ssh)  shift; start; vssh "$@"; exit ;;
    bundle)
        [ -n "$NAVDAT_DEBS" ] || { echo "bundle needs NAVDAT_DEBS" >&2; exit 1; }
        start
        echo "== sync sources and proprietary packages"
        rsync -a --delete --exclude .git --exclude '*.deb' --exclude dist --exclude .DS_Store \
            -e "ssh ${SSH_OPTS[*]}" "$ROOT/" ubuntu@127.0.0.1:navdat-bort/
        rsync -a --delete --include '*.deb' --exclude '*' -e "ssh ${SSH_OPTS[*]}" \
            "$NAVDAT_DEBS/" ubuntu@127.0.0.1:navdat-debs/
        echo "== build offline bundle"
        vssh 'cd navdat-bort && rm -rf ~/bundle-out && sudo install/build-offline-bundle.sh ~/navdat-debs ~/bundle-out'
        mkdir -p bundle
        scp "${SCP_OPTS[@]}" 'ubuntu@127.0.0.1:bundle-out/*.tar' bundle/
        ls -la bundle
        exit ;;
    offline-install)
        [ -n "${NAVDAT_BUNDLE_TAR:-}" ] || { echo "offline-install needs NAVDAT_BUNDLE_TAR" >&2; exit 1; }
        VM_OFFLINE=1
        start
        echo "== internet must be unreachable"
        if vssh 'curl -sS -m 10 -o /dev/null http://archive.ubuntu.com/' 2>/dev/null; then
            echo "FAIL: VM has internet access" >&2; exit 1
        fi
        echo "ok: no internet"
        echo "== copy bundle (as from a USB stick)"
        scp "${SCP_OPTS[@]}" "$NAVDAT_BUNDLE_TAR" "$ROOT/tests/vm/install-check.sh" ubuntu@127.0.0.1:/tmp/
        echo "== run installer from bundle"
        vssh "bash /tmp/install-check.sh offline /tmp/$(basename "$NAVDAT_BUNDLE_TAR")"
        echo "== reboot"
        vssh 'sudo systemctl reboot' || true
        sleep 20
        for _ in $(seq 1 120); do vssh true 2>/dev/null && break; sleep 5; done
        echo "== verify after reboot"
        vssh 'bash /tmp/install-check.sh verify'
        exit ;;
    gui)
        if vssh true 2>/dev/null; then
            echo "VM is already running headless; stop it first: $0 stop" >&2; exit 1
        fi
        case "$(uname -s)" in
            Darwin) DISPLAY_OPTS=(-display cocoa -vnc 127.0.0.1:1) ;;
            *)      DISPLAY_OPTS=(-display gtk -vnc 127.0.0.1:1) ;;
        esac
        # с окном QEMU не может уйти в фон сам
        DAEMON=no
        start
        echo "VM window is open (also vnc://127.0.0.1:5901)"
        exit ;;
    stop) [ -f qemu.pid ] && kill "$(cat qemu.pid)" && rm -f qemu.pid; exit ;;
    run)  ;;
    install)
        [ -n "$NAVDAT_DEBS" ] || { echo "install needs NAVDAT_DEBS" >&2; exit 1; }
        start
        echo "== copy installer and packages"
        scp "${SCP_OPTS[@]}" "$ROOT/install/navdat-install.sh" "$ROOT/tests/vm/fake_github.py" \
            "$ROOT/tests/vm/install-check.sh" ubuntu@127.0.0.1:/tmp/
        rsync -a --delete --include '*.deb' --exclude '*' -e "ssh ${SSH_OPTS[*]}" \
            "$NAVDAT_DEBS/" ubuntu@127.0.0.1:navdat-debs/
        echo "== run installer"
        vssh 'bash /tmp/install-check.sh install'
        echo "== reboot"
        vssh 'sudo systemctl reboot' || true
        sleep 20
        for _ in $(seq 1 120); do vssh true 2>/dev/null && break; sleep 5; done
        echo "== verify after reboot"
        scp "${SCP_OPTS[@]}" "$ROOT/tests/vm/install-check.sh" ubuntu@127.0.0.1:/tmp/
        vssh 'bash /tmp/install-check.sh verify'
        mkdir -p shots
        scp "${SCP_OPTS[@]}" ubuntu@127.0.0.1:/tmp/shot-install.png shots/ || true
        echo "screenshots: $VM_DIR/shots"
        exit ;;
    *)    sed -n '2,17p' "$0"; exit 1 ;;
esac

start
echo "== dependencies"
vssh 'sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends python3-gi gir1.2-gtk-3.0 xvfb xauth dbus-x11 adwaita-icon-theme awesome dpkg-dev rsync imagemagick >/dev/null'

echo "== sync sources"
rsync -a --delete --exclude .git --exclude '*.deb' --exclude dist --exclude .DS_Store \
    -e "ssh ${SSH_OPTS[*]}" "$ROOT/" ubuntu@127.0.0.1:navdat-bort/

echo "== bortcfg unit tests"
vssh 'cd navdat-bort && xvfb-run -a dbus-launch --exit-with-session python3 -m unittest discover -s tests -v 2>&1 | tee /tmp/test.log | grep -E "\.\.\. |^Ran|^OK|^FAILED"; ! grep -E "Gtk-(WARNING|CRITICAL)|^FAILED" /tmp/test.log'

if [ -n "$NAVDAT_DEBS" ]; then
    echo "== sync proprietary packages"
    rsync -a --delete --include '*.deb' --exclude '*' -e "ssh ${SSH_OPTS[*]}" \
        "$NAVDAT_DEBS/" ubuntu@127.0.0.1:navdat-debs/
fi

echo "== build and install packages"
vssh "REAL=${NAVDAT_DEBS:+1}"'; set -e; cd navdat-bort; rm -rf dist; packaging/build-debs.sh dist >/dev/null
  if [ -n "$REAL" ]; then
    packaging/repack-proprietary.sh ~/navdat-debs dist
    if dpkg -s navdat-bortd 2>/dev/null | grep -q "Version: 0.0.0~stub"; then
      sudo dpkg --purge --force-depends navdat-bortd >/dev/null
    fi
  elif ! dpkg -s navdat-bortd >/dev/null 2>&1; then
    d=$(mktemp -d); mkdir $d/DEBIAN
    printf "Package: navdat-bortd\nVersion: 0.0.0~stub\nArchitecture: all\nMaintainer: test <test@localhost>\nDescription: test stub for the proprietary bortd\n" > $d/DEBIAN/control
    dpkg-deb --root-owner-group -b $d /tmp/navdat-bortd-stub.deb >/dev/null
    sudo dpkg -i /tmp/navdat-bortd-stub.deb >/dev/null
  fi
  sudo dpkg -i dist/*.deb >/dev/null 2>&1 || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y -qq --no-install-recommends >/dev/null
  dpkg -l "navdat-*" | awk "/^ii/ {print \$2, \$3}"
  dpkg -l "navdat-*" | awk "/^i[^i]|^[^i]/ && /navdat/ {print \"NOT INSTALLED:\", \$1, \$2; bad=1} END {exit bad}"
  getent passwd navdat; sudo passwd -S navdat'

echo "== X session as navdat"
scp -q "${SCP_OPTS[@]}" "$ROOT/tests/vm/session-check.sh" ubuntu@127.0.0.1:/tmp/
vssh 'chmod 755 /tmp/session-check.sh; sudo -iu navdat /tmp/session-check.sh'
echo "== status indicators (passive)"
scp "${SCP_OPTS[@]}" "$ROOT/tests/vm/indicators-check.sh" ubuntu@127.0.0.1:/tmp/
vssh 'chmod 755 /tmp/indicators-check.sh; sudo -iu navdat /tmp/indicators-check.sh'

if [ -n "$NAVDAT_DEBS" ]; then
    echo "== proprietary clients and bortd (demo mode)"
    scp "${SCP_OPTS[@]}" "$ROOT/tests/vm/clients-check.sh" ubuntu@127.0.0.1:/tmp/
    vssh 'chmod 755 /tmp/clients-check.sh; sudo -iu navdat /tmp/clients-check.sh'
fi

mkdir -p shots
scp -q "${SCP_OPTS[@]}" 'ubuntu@127.0.0.1:/tmp/shot-*.png' shots/
echo "screenshots: $VM_DIR/shots"
