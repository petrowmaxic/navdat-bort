#!/bin/bash
# Проверка мастера установки на чистой ВМ (запускается в ВМ от ubuntu).
#
#   install-check.sh install   имитация GitHub + мастер от «обычного» пользователя
#                              laptop (sudo с паролем), ответы через терминал
#   install-check.sh verify    после перезагрузки: LightDM, автовход navdat,
#                              сеанс Navdat Awesome, скриншот экрана
set -u
LAPTOP_PW='Laptop-pass-1'
NAVDAT_PW='Navdat-2026!'
TOKEN='test-token-123'

case "${1:-}" in
install)
    set -e
    # пользователь ноутбука: sudo только с паролем, как на настоящем ноутбуке
    if ! id laptop >/dev/null 2>&1; then
        sudo useradd -m -s /bin/bash -G sudo laptop
        echo "laptop:$LAPTOP_PW" | sudo chpasswd
    fi
    sudo -u laptop sudo -n true 2>/dev/null && { echo "FAIL: laptop must need a sudo password"; exit 1; }

    # приватный релиз: закрытые пакеты + SHA256SUMS
    mkdir -p ~/release && cp ~/navdat-debs/*.deb ~/release/
    (cd ~/release && sha256sum *.deb > SHA256SUMS)
    pkill -f fake_github.py 2>/dev/null || true
    python3 /tmp/fake_github.py ~/release 8088 2>/tmp/fake_github.log &
    sleep 1

    sudo install -o laptop -m 644 /tmp/navdat-install.sh /home/laptop/navdat-install.sh
    set +e
    # первая попытка с неверным ключом, затем верные ответы
    sudo -iu laptop env NAVDAT_UI=text NAVDAT_GITHUB_API=http://127.0.0.1:8088 \
        NAVDAT_REBOOT=no bash navdat-install.sh <<EOF
navdat-admin
wrong-token
navdat-admin
$TOKEN
$NAVDAT_PW
$NAVDAT_PW
д
$LAPTOP_PW
EOF
    rc=$?
    set -e
    pkill -f fake_github.py || true
    LOG=/home/laptop/navdat-install.log
    echo "--- installer exit code: $rc"
    echo "--- log (tail)"; sudo tail -25 "$LOG"
    [ $rc = 0 ] || { echo "FAIL: installer failed"; exit 1; }
    sudo grep -q "Установка завершена" "$LOG" || { echo "FAIL: no completion in log"; exit 1; }
    sudo grep -q "ERROR: Логин или ключ доступа не подходят" "$LOG" \
        || { echo "FAIL: wrong key was not rejected"; exit 1; }
    if sudo grep -qF -e "$TOKEN" -e "$NAVDAT_PW" -e "$LAPTOP_PW" "$LOG"; then
        echo "FAIL: secrets leaked into the log"; exit 1
    fi
    grep -c "GET /download/" /tmp/fake_github.log | sed 's/^/files downloaded: /'
    echo "--- installed"; dpkg -l 'navdat-*' | awk '/^ii/ {print $2, $3}'
    getent passwd navdat
    sudo passwd -S navdat
    cat /etc/lightdm/lightdm.conf.d/50-navdat.conf
    echo "OK: installer finished"
    ;;
offline)
    set -e
    TAR=${2:?usage: install-check.sh offline <bundle.tar>}
    if ! id laptop >/dev/null 2>&1; then
        sudo useradd -m -s /bin/bash -G sudo laptop
        echo "laptop:$LAPTOP_PW" | sudo chpasswd
    fi
    # комплект «с флешки» в Загрузки пользователя ноутбука
    sudo -u laptop mkdir -p /home/laptop/Downloads
    sudo tar -xf "$TAR" -C /home/laptop/Downloads
    sudo chown -R laptop:laptop /home/laptop/Downloads
    # домашний каталог laptop закрыт для ubuntu (750), поэтому через sudo
    DIR=$(sudo sh -c 'ls -d /home/laptop/Downloads/navdat-offline-*')
    echo "bundle: $DIR ($(sudo du -sh "$DIR" | cut -f1), $(sudo sh -c "ls $DIR/repo/*.deb" | wc -l) packages)"
    set +e
    printf '%s\n%s\n%s\n%s\n' "$NAVDAT_PW" "$NAVDAT_PW" "д" "$LAPTOP_PW" | \
        sudo -iu laptop env NAVDAT_UI=text NAVDAT_REBOOT=no bash "$DIR/navdat-install.sh"
    rc=$?
    set -e
    LOG=/home/laptop/navdat-install.log
    echo "--- installer exit code: $rc"
    echo "--- log (tail)"; sudo tail -15 "$LOG"
    [ $rc = 0 ] || { echo "FAIL: offline installer failed"; exit 1; }
    sudo grep -q "offline bundle" "$LOG" || { echo "FAIL: installer did not use the bundle"; exit 1; }
    if sudo grep -qF -e "$NAVDAT_PW" -e "$LAPTOP_PW" "$LOG"; then
        echo "FAIL: secrets leaked into the log"; exit 1
    fi
    echo "--- installed"; dpkg -l 'navdat-*' | awk '/^ii/ {print $2, $3}'
    sudo passwd -S navdat
    echo "OK: offline installer finished"
    ;;
verify)
    for _ in $(seq 1 60); do pgrep -u navdat -x awesome >/dev/null && break; sleep 5; done
    echo "--- display manager: $(cat /etc/X11/default-display-manager), lightdm $(systemctl is-active lightdm)"
    loginctl list-sessions --no-legend
    echo "--- navdat processes"; ps -u navdat -o comm= | sort -u | tr '\n' ' '; echo
    pgrep -u navdat -x awesome >/dev/null || { echo "FAIL: navdat session did not start"; exit 1; }
    # скриншот только если есть интернет для imagemagick
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq imagemagick >/dev/null 2>&1; then
        sudo DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 import -window root /tmp/shot-install.png \
            && echo "screenshot ok"
    fi
    echo "OK: autologin into Navdat Awesome after reboot"
    ;;
*)
    sed -n '2,8p' "$0"; exit 1 ;;
esac
