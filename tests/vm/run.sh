#!/bin/bash
# Локальная проверка порта в виртуальной машине Ubuntu 24.04 (QEMU, без Docker).
#
#   tests/vm/run.sh            поднять ВМ (если не запущена) и прогнать всё
#   tests/vm/run.sh ssh [cmd]  зайти в ВМ
#   tests/vm/run.sh stop       выключить ВМ
#
# Что делает: юнит-тесты bortcfg под Xvfb, сборка и установка deb-пакетов
# (с заглушкой закрытого navdat-bortd), настоящий X-сеанс navdat-awesome от
# пользователя navdat, открытие меню и bortcfg, скриншоты в $VM_DIR/shots.
#
# Нужно: qemu (brew install qemu на macOS или qemu-system-* на Linux), curl, rsync.
# Образ и диск ВМ лежат в $VM_DIR (по умолчанию ~/.cache/navdat-vm).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VM_DIR=${VM_DIR:-$HOME/.cache/navdat-vm}
PORT=${VM_SSH_PORT:-2222}
mkdir -p "$VM_DIR"
cd "$VM_DIR"

case "$(uname -m)" in
    arm64|aarch64) ARCH=arm64; QEMU=qemu-system-aarch64
                   MACHINE="-machine virt -cpu host"; FW_NAME=edk2-aarch64-code.fd ;;
    *)             ARCH=amd64; QEMU=qemu-system-x86_64
                   MACHINE="-machine q35 -cpu host"; FW_NAME=edk2-x86_64-code.fd ;;
esac
case "$(uname -s)" in
    Darwin) ACCEL=hvf ;;
    *)      ACCEL=kvm ;;
esac

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
        curl -fsSL "$url/SHA256SUMS" | grep " \*$img\$" | sed "s/\*$img/$img.part/" | shasum -a 256 -c -
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
    if [ ! -f efi-code.fd ]; then
        local fw
        fw=$(ls "$(dirname "$(command -v $QEMU)")"/../share/qemu/$FW_NAME /usr/share/qemu/$FW_NAME 2>/dev/null | head -n1)
        cp "$fw" efi-code.fd
        dd if=/dev/zero of=efi-vars.fd bs=1048576 count=64 2>/dev/null
    fi
}

start() {
    vssh true 2>/dev/null && return
    prepare
    $QEMU $MACHINE,accel=$ACCEL -smp 4 -m 4096 \
        -drive if=pflash,format=raw,file=efi-code.fd,readonly=on \
        -drive if=pflash,format=raw,file=efi-vars.fd \
        -drive if=virtio,format=qcow2,file=disk.qcow2 \
        -drive if=virtio,format=raw,file=seed.iso,readonly=on \
        -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0 \
        -display none -serial file:serial.log -monitor none -daemonize -pidfile qemu.pid
    echo "waiting for VM..."
    for _ in $(seq 1 90); do vssh 'cloud-init status --wait >/dev/null' 2>/dev/null && return; sleep 5; done
    echo "VM did not come up, see $VM_DIR/serial.log" >&2; exit 1
}

case "${1:-run}" in
    ssh)  shift; start; vssh "$@"; exit ;;
    stop) [ -f qemu.pid ] && kill "$(cat qemu.pid)" && rm -f qemu.pid; exit ;;
    run)  ;;
    *)    sed -n '2,13p' "$0"; exit 1 ;;
esac

start
echo "== dependencies"
vssh 'sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends python3-gi gir1.2-gtk-3.0 xvfb xauth dbus-x11 adwaita-icon-theme awesome dpkg-dev rsync imagemagick >/dev/null'

echo "== sync sources"
rsync -a --delete --exclude .git --exclude '*.deb' --exclude dist --exclude .DS_Store \
    -e "ssh ${SSH_OPTS[*]}" "$ROOT/" ubuntu@127.0.0.1:navdat-bort/

echo "== bortcfg unit tests"
vssh 'cd navdat-bort && xvfb-run -a dbus-launch --exit-with-session python3 -m unittest discover -s tests -v 2>&1 | tee /tmp/test.log | grep -E "\.\.\. |^Ran|^OK|^FAILED"; ! grep -E "Gtk-(WARNING|CRITICAL)|^FAILED" /tmp/test.log'

echo "== build and install packages"
vssh 'set -e; cd navdat-bort; rm -rf dist; packaging/build-debs.sh dist >/dev/null
  if ! dpkg -s navdat-bortd >/dev/null 2>&1; then
    d=$(mktemp -d); mkdir $d/DEBIAN
    printf "Package: navdat-bortd\nVersion: 0.0.0~stub\nArchitecture: all\nMaintainer: test <test@localhost>\nDescription: test stub for the proprietary bortd\n" > $d/DEBIAN/control
    dpkg-deb --root-owner-group -b $d /tmp/navdat-bortd-stub.deb >/dev/null
    sudo dpkg -i /tmp/navdat-bortd-stub.deb >/dev/null
  fi
  sudo dpkg -i dist/*.deb >/dev/null 2>&1 || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y -qq --no-install-recommends >/dev/null
  dpkg -l "navdat-*" | awk "/^ii/ {print \$2, \$3}"
  getent passwd navdat; sudo passwd -S navdat'

echo "== X session as navdat"
scp -q "${SCP_OPTS[@]}" "$ROOT/tests/vm/session-check.sh" ubuntu@127.0.0.1:/tmp/
vssh 'chmod 755 /tmp/session-check.sh; sudo -iu navdat /tmp/session-check.sh'
mkdir -p shots
scp -q "${SCP_OPTS[@]}" 'ubuntu@127.0.0.1:/tmp/shot-*.png' shots/
echo "screenshots: $VM_DIR/shots"
