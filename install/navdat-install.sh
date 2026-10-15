#!/bin/bash
# Мастер установки бортовой программы NavDat на Ubuntu 24.04+ (x86-64).
#
# Запуск на свежем ноутбуке (под обычным пользователем с правами sudo):
#
#   bash navdat-install.sh
#
# Мастер спросит логин GitHub и ключ доступа к закрытым пакетам NavDat,
# пароль оператора и нужен ли автоматический вход. Дальше всё ставится само:
# пакеты из приватного релиза, открытые пакеты из этого репозитория,
# библиотеки совместимости, пользователь navdat, сеанс Navdat Awesome и LightDM.
#
# Графические окна (zenity) используются, если есть экран; иначе вопросы
# задаются в терминале. Для автоматических проверок все ответы можно передать
# переменными окружения (см. ниже NAVDAT_*).
set -euo pipefail

PUBLIC_REPO=${NAVDAT_PUBLIC_REPO:-petrowmaxic/navdat-bort}
NAVDAT_REF=${NAVDAT_REF:-port/ubuntu-24.04}
PRIVATE_REPO=${NAVDAT_PRIVATE_REPO:-petrowmaxic/navdat-bort-private}
RELEASE_TAG=${NAVDAT_RELEASE_TAG:-navdat-0.2.12}
GITHUB_API=${NAVDAT_GITHUB_API:-https://api.github.com}
SOURCE_URL=${NAVDAT_SOURCE_URL:-https://codeload.github.com/$PUBLIC_REPO/tar.gz/$NAVDAT_REF}
LOG=${NAVDAT_LOG:-$HOME/navdat-install.log}
TITLE="Установка NavDat"

# ---------------------------------------------------------------- интерфейс
if [ -n "${NAVDAT_UI:-}" ]; then
    UI=$NAVDAT_UI
elif { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; } && command -v zenity >/dev/null; then
    UI=zenity
else
    UI=text
fi

say() { echo "$*"; echo "[$(date '+%F %T')] $*" >> "$LOG"; }

ui_info() {
    if [ "$UI" = zenity ]; then zenity --info --title "$TITLE" --width 420 --text "$1" 2>/dev/null || true
    else echo; echo "$1"; fi
}
ui_error() {
    echo "[$(date '+%F %T')] ERROR: $1" >> "$LOG"
    if [ "$UI" = zenity ]; then zenity --error --title "$TITLE" --width 420 --text "$1" 2>/dev/null || true
    else echo; echo "ОШИБКА: $1" >&2; fi
}
die() { ui_error "$1"$'\n\n'"Подробности: $LOG"; exit 1; }

ui_entry() {   # ui_entry <вопрос> [значение по умолчанию]
    local answer
    if [ "$UI" = zenity ]; then
        answer=$(zenity --entry --title "$TITLE" --width 420 --text "$1" --entry-text "${2:-}" 2>/dev/null) || exit 1
    else
        read -r -p "$1 " answer || exit 1
        [ -n "$answer" ] || answer=${2:-}
    fi
    printf '%s' "$answer"
}
ui_secret() {  # ui_secret <вопрос>
    local answer
    if [ "$UI" = zenity ]; then
        answer=$(zenity --password --title "$1" 2>/dev/null) || exit 1
    else
        read -r -s -p "$1 " answer || exit 1; echo >&2
    fi
    printf '%s' "$answer"
}
ui_yesno() {   # ui_yesno <вопрос> -> 0 да / 1 нет
    if [ "$UI" = zenity ]; then
        zenity --question --title "$TITLE" --width 420 --text "$1" 2>/dev/null
    else
        local a; read -r -p "$1 [д/н] " a || return 1
        case "$a" in [дДyY]*) return 0 ;; *) return 1 ;; esac
    fi
}

# Шаги показываются в окне прогресса (zenity) или строками в терминале.
PROGRESS_FD=
progress_start() {
    if [ "$UI" = zenity ]; then
        exec {PROGRESS_FD}> >(zenity --progress --title "$TITLE" --width 460 \
                                --pulsate --auto-close --no-cancel 2>/dev/null)
    fi
}
step() {
    say "== $1"
    [ -n "$PROGRESS_FD" ] && echo "# $1" >&"$PROGRESS_FD" || true
}
progress_end() {
    if [ -n "$PROGRESS_FD" ]; then echo "100" >&"$PROGRESS_FD"; exec {PROGRESS_FD}>&-; PROGRESS_FD=; fi
}

# ---------------------------------------------------------------- sudo
SUDO=sudo
sudo_init() {
    if [ "$(id -u)" = 0 ]; then SUDO=; return; fi
    if sudo -n true 2>/dev/null; then return; fi
    local pw
    for _ in 1 2 3; do
        pw=$(ui_secret "Пароль администратора (sudo) для пользователя $(id -un):")
        if printf '%s\n' "$pw" | sudo -S -v -p '' 2>/dev/null; then
            # держим sudo активным до конца установки
            ( while true; do sudo -n -v 2>/dev/null; sleep 50; done ) &
            SUDO_KEEPALIVE=$!
            return
        fi
        ui_error "Неверный пароль администратора."
    done
    die "Не удалось получить права администратора."
}
SUDO_KEEPALIVE=
cleanup() {
    [ -n "$SUDO_KEEPALIVE" ] && kill "$SUDO_KEEPALIVE" 2>/dev/null || true
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
    progress_end 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------- GitHub
gh_api() {     # gh_api <путь> [доп. аргументы curl]
    local path=$1; shift
    curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
         -H "X-GitHub-Api-Version: 2022-11-28" "$@" "$GITHUB_API$path"
}

check_credentials() {
    local login
    login=$(gh_api /user 2>>"$LOG" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("login",""))' 2>>"$LOG") \
        || return 1
    if [ "${login,,}" != "${GH_LOGIN,,}" ]; then
        say "token belongs to '$login', not '$GH_LOGIN'"
        return 1
    fi
    gh_api "/repos/$PRIVATE_REPO/releases/tags/$RELEASE_TAG" > "$WORK/release.json" 2>>"$LOG"
}

download_release() {   # -> $WORK/debs
    mkdir -p "$WORK/debs"
    python3 - "$WORK/release.json" > "$WORK/assets.txt" <<'EOF'
import json, sys
for a in json.load(open(sys.argv[1]))["assets"]:
    print(a["url"], a["name"])
EOF
    [ -s "$WORK/assets.txt" ] || die "В релизе $RELEASE_TAG нет файлов."
    while read -r url name; do
        say "  $name"
        gh_api "${url#"$GITHUB_API"}" -H "Accept: application/octet-stream" \
            -o "$WORK/debs/$name" 2>>"$LOG" || die "Не удалось скачать $name."
    done < "$WORK/assets.txt"
    [ -f "$WORK/debs/SHA256SUMS" ] || die "В релизе нет SHA256SUMS."
    (cd "$WORK/debs" && sha256sum -c --quiet SHA256SUMS) >>"$LOG" 2>&1 \
        || die "Контрольные суммы закрытых пакетов не совпали."
}

# ---------------------------------------------------------------- проверки
: > "$LOG"
say "NavDat installer, source $PUBLIC_REPO@$NAVDAT_REF, packages $PRIVATE_REPO@$RELEASE_TAG"

. /etc/os-release
if [ "${ID:-}" != ubuntu ] || ! printf '%s\n%s\n' 24.04 "${VERSION_ID:-0}" | sort -V -C; then
    die "Нужна Ubuntu 24.04 или новее, а здесь: ${PRETTY_NAME:-неизвестная система}."
fi
if [ "$(dpkg --print-architecture)" != amd64 ]; then
    die "Нужен компьютер x86-64 (amd64): закрытые программы NavDat существуют только для этой архитектуры."
fi

ui_info "Мастер установит бортовую программу NavDat.

Понадобятся:
 • логин GitHub и ключ доступа к закрытым пакетам NavDat (выдаёт администратор);
 • пароль для оператора navdat;
 • подключение к интернету.

После установки компьютер нужно перезагрузить."

WORK=$(mktemp -d)

# ---------------------------------------------------------------- вопросы
GH_LOGIN=${NAVDAT_GH_LOGIN:-}
GH_TOKEN=${NAVDAT_GH_TOKEN:-}
for attempt in 1 2 3; do
    [ -n "$GH_LOGIN" ] || GH_LOGIN=$(ui_entry "Логин GitHub:")
    [ -n "$GH_TOKEN" ] || GH_TOKEN=$(ui_secret "Ключ доступа GitHub для $GH_LOGIN:")
    if check_credentials; then break; fi
    ui_error "Логин или ключ доступа не подходят, либо у этой учётной записи нет доступа к $PRIVATE_REPO."
    [ -n "${NAVDAT_GH_TOKEN:-}" ] && die "Неверные учётные данные GitHub."
    GH_LOGIN=; GH_TOKEN=
    [ "$attempt" = 3 ] && die "Не удалось войти в GitHub."
done

OP_PASSWORD=${NAVDAT_PASSWORD:-}
while [ -z "$OP_PASSWORD" ]; do
    p1=$(ui_secret "Новый пароль оператора navdat:")
    p2=$(ui_secret "Повторите пароль оператора:")
    if [ -z "$p1" ]; then ui_error "Пароль не может быть пустым."
    elif [ "$p1" != "$p2" ]; then ui_error "Пароли не совпадают."
    else OP_PASSWORD=$p1; fi
done

case "${NAVDAT_AUTOLOGIN:-ask}" in
    yes) AUTOLOGIN=yes ;;
    no)  AUTOLOGIN=no ;;
    *)   if ui_yesno "Входить в систему как оператор navdat автоматически при включении?"; then
             AUTOLOGIN=yes; else AUTOLOGIN=no; fi ;;
esac

sudo_init

# ---------------------------------------------------------------- установка
progress_start

step "Подготовка системы"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq >>"$LOG" 2>&1 || die "apt-get update не удался."
$SUDO apt-get install -y -qq curl ca-certificates dpkg-dev python3 >>"$LOG" 2>&1 \
    || die "Не удалось установить служебные пакеты."
# LightDM станет менеджером входа без вопроса debconf
echo "lightdm shared/default-x-display-manager select lightdm" | $SUDO debconf-set-selections

step "Скачивание закрытых пакетов NavDat"
download_release
unset GH_TOKEN NAVDAT_GH_TOKEN

step "Скачивание исходников NavDat"
mkdir -p "$WORK/src"
curl -fsSL "$SOURCE_URL" | tar xz -C "$WORK/src" --strip-components=1 2>>"$LOG" \
    || die "Не удалось скачать исходники $PUBLIC_REPO."

step "Сборка пакетов"
"$WORK/src/packaging/build-debs.sh" "$WORK/dist" >>"$LOG" 2>&1 || die "Сборка открытых пакетов не удалась."
NAVDAT_COMPAT_CACHE="$WORK/compat-cache" \
    "$WORK/src/packaging/repack-proprietary.sh" "$WORK/debs" "$WORK/dist" >>"$LOG" 2>&1 \
    || die "Перепаковка закрытых пакетов не удалась."

step "Установка пакетов (это может занять несколько минут)"
$SUDO apt-get install -y -q "$WORK"/dist/*.deb >>"$LOG" 2>&1 || die "Установка пакетов не удалась."

step "Настройка оператора и входа в систему"
printf 'navdat:%s\n' "$OP_PASSWORD" | $SUDO chpasswd || die "Не удалось задать пароль оператора."
unset OP_PASSWORD NAVDAT_PASSWORD p1 p2
$SUDO mkdir -p /etc/lightdm/lightdm.conf.d
{
    echo "[Seat:*]"
    echo "user-session=navdat-awesome"
    if [ "$AUTOLOGIN" = yes ]; then
        echo "autologin-user=navdat"
        echo "autologin-session=navdat-awesome"
    fi
} | $SUDO tee /etc/lightdm/lightdm.conf.d/50-navdat.conf >/dev/null
echo /usr/sbin/lightdm | $SUDO tee /etc/X11/default-display-manager >/dev/null
$SUDO ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
$SUDO systemctl disable gdm3 >>"$LOG" 2>&1 || true

progress_end
say "Установка завершена."

case "${NAVDAT_REBOOT:-ask}" in
    yes) $SUDO systemctl reboot ;;
    no)  ui_info "NavDat установлен. После перезагрузки войдите как navdat (сеанс «Navdat Awesome»)." ;;
    *)   if ui_yesno "NavDat установлен. Для входа выберите пользователя navdat, сеанс «Navdat Awesome».

Перезагрузить компьютер сейчас?"; then
             $SUDO systemctl reboot
         fi ;;
esac
