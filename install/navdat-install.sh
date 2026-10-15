#!/bin/bash
# Мастер установки бортовой программы NavDat на Ubuntu 24.04+ (x86-64).
#
# Скачайте этот файл на свежий ноутбук и запустите под обычным пользователем
# с правами администратора:
#
#   bash navdat-install.sh
#
# Мастер спросит логин GitHub и ключ доступа к закрытым пакетам NavDat
# (их выдаёт администратор), пароль оператора navdat и нужен ли автовход.
# Дальше всё ставится само: закрытые пакеты из приватного релиза, открытые
# пакеты из этого репозитория, библиотеки совместимости, пользователь navdat,
# сеанс «Navdat Awesome» и менеджер входа LightDM.
#
# Работает в два этапа: сначала от пользователя задаются все вопросы и
# проверяется доступ, затем мастер один раз перезапускает себя от root
# (sudo) и устанавливает всё без вопросов. Окна zenity используются, если
# есть экран, иначе вопросы задаются в терминале. Для автоматических проверок
# ответы можно передать переменными NAVDAT_* (см. ниже).
set -euo pipefail

PUBLIC_REPO=${NAVDAT_PUBLIC_REPO:-petrowmaxic/navdat-bort}
NAVDAT_REF=${NAVDAT_REF:-port/ubuntu-24.04}
PRIVATE_REPO=${NAVDAT_PRIVATE_REPO:-petrowmaxic/navdat-bort-private}
RELEASE_TAG=${NAVDAT_RELEASE_TAG:-navdat-0.2.12}
GITHUB_API=${NAVDAT_GITHUB_API:-https://api.github.com}
SOURCE_URL=${NAVDAT_SOURCE_URL:-https://codeload.github.com/$PUBLIC_REPO/tar.gz/$NAVDAT_REF}
TITLE="Установка NavDat"
ROLE=${1:-user}            # user | root (второй этап, запускается самим мастером)

if [ "$ROLE" = user ]; then
    export NAVDAT_LOG=${NAVDAT_LOG:-$HOME/navdat-install.log}
    : > "$NAVDAT_LOG"
fi
LOG=$NAVDAT_LOG

# ---------------------------------------------------------------- интерфейс
if [ -n "${NAVDAT_UI:-}" ]; then
    UI=$NAVDAT_UI
elif { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; } && command -v zenity >/dev/null; then
    UI=zenity
else
    UI=text
fi
export NAVDAT_UI=$UI

say() { echo "$*"; echo "[$(date '+%F %T')] $*" >> "$LOG"; }

ui_info() {
    if [ "$UI" = zenity ]; then zenity --info --title "$TITLE" --width 440 --text "$1" 2>/dev/null || true
    else echo; echo "$1"; echo; fi
}
ui_error() {
    echo "[$(date '+%F %T')] ERROR: $1" >> "$LOG"
    if [ "$UI" = zenity ] && [ "$ROLE" = user ]; then
        zenity --error --title "$TITLE" --width 440 --text "$1" 2>/dev/null || true
    else echo; echo "ОШИБКА: $1" >&2; fi
}
die() { ui_error "$1"$'\n\n'"Подробности: $LOG"; exit 1; }

ui_entry() {
    local answer
    if [ "$UI" = zenity ]; then
        answer=$(zenity --entry --title "$TITLE" --width 440 --text "$1" 2>/dev/null) || exit 1
    else
        read -r -p "$1 " answer || exit 1
    fi
    printf '%s' "$answer"
}
ui_secret() {
    local answer
    if [ "$UI" = zenity ]; then
        answer=$(zenity --password --title "$1" 2>/dev/null) || exit 1
    else
        read -r -s -p "$1 " answer || exit 1; echo >&2
    fi
    printf '%s' "$answer"
}
ui_yesno() {
    if [ "$UI" = zenity ]; then
        zenity --question --title "$TITLE" --width 440 --text "$1" 2>/dev/null
    else
        local a; read -r -p "$1 [д/н] " a || return 1
        case "$a" in [дДyY]*) return 0 ;; *) return 1 ;; esac
    fi
}

# Шаги второго этапа пишутся в файл прогресса; первый этап показывает их
# в окне zenity (графика от root не нужна) или в терминале.
step() {
    say "== $1"
    [ -n "${NAVDAT_PROGRESS:-}" ] && echo "# $1" >> "$NAVDAT_PROGRESS" || true
}

# ================================================================ этап root
if [ "$ROLE" = root ]; then
    [ "$(id -u)" = 0 ] || die "Второй этап должен запускаться от root."
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT
    export DEBIAN_FRONTEND=noninteractive
    GH_TOKEN=$NAVDAT_GH_TOKEN

    gh_api() {
        local path=$1; shift
        curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
             -H "X-GitHub-Api-Version: 2022-11-28" "$@" "$GITHUB_API$path"
    }

    step "Подготовка системы"
    apt-get update -qq >>"$LOG" 2>&1 || die "apt-get update не удался. Проверьте интернет."
    apt-get install -y -qq curl ca-certificates dpkg-dev python3 >>"$LOG" 2>&1 \
        || die "Не удалось установить служебные пакеты."
    # LightDM станет менеджером входа без вопроса debconf
    echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections

    step "Скачивание закрытых пакетов NavDat"
    mkdir -p "$WORK/debs"
    gh_api "/repos/$PRIVATE_REPO/releases/tags/$RELEASE_TAG" > "$WORK/release.json" 2>>"$LOG" \
        || die "Нет доступа к релизу $RELEASE_TAG в $PRIVATE_REPO."
    python3 - "$WORK/release.json" > "$WORK/assets.txt" <<'EOF'
import json, sys
for a in json.load(open(sys.argv[1]))["assets"]:
    print(a["url"], a["name"])
EOF
    [ -s "$WORK/assets.txt" ] || die "В релизе $RELEASE_TAG нет файлов."
    while read -r url name; do
        say "  $name"
        # curl не пересылает Authorization на другой хост при редиректе (S3)
        gh_api "${url#"$GITHUB_API"}" -H "Accept: application/octet-stream" \
            -o "$WORK/debs/$name" 2>>"$LOG" || die "Не удалось скачать $name."
    done < "$WORK/assets.txt"
    unset GH_TOKEN NAVDAT_GH_TOKEN
    [ -f "$WORK/debs/SHA256SUMS" ] || die "В релизе нет SHA256SUMS."
    (cd "$WORK/debs" && sha256sum -c --quiet SHA256SUMS) >>"$LOG" 2>&1 \
        || die "Контрольные суммы закрытых пакетов не совпали."

    step "Скачивание исходников NavDat"
    mkdir -p "$WORK/src"
    curl -fsSL "$SOURCE_URL" 2>>"$LOG" | tar xz -C "$WORK/src" --strip-components=1 2>>"$LOG" \
        || die "Не удалось скачать исходники $PUBLIC_REPO ($NAVDAT_REF)."

    step "Сборка пакетов"
    "$WORK/src/packaging/build-debs.sh" "$WORK/dist" >>"$LOG" 2>&1 \
        || die "Сборка открытых пакетов не удалась."
    NAVDAT_COMPAT_CACHE="$WORK/compat-cache" \
        "$WORK/src/packaging/repack-proprietary.sh" "$WORK/debs" "$WORK/dist" >>"$LOG" 2>&1 \
        || die "Перепаковка закрытых пакетов не удалась."

    step "Установка пакетов (несколько минут)"
    apt-get install -y -q "$WORK"/dist/*.deb >>"$LOG" 2>&1 || die "Установка пакетов не удалась."

    step "Настройка оператора и входа в систему"
    printf 'navdat:%s\n' "$NAVDAT_PASSWORD" | chpasswd || die "Не удалось задать пароль оператора."
    unset NAVDAT_PASSWORD
    mkdir -p /etc/lightdm/lightdm.conf.d
    {
        echo "[Seat:*]"
        echo "user-session=navdat-awesome"
        if [ "$NAVDAT_AUTOLOGIN" = yes ]; then
            echo "autologin-user=navdat"
            echo "autologin-session=navdat-awesome"
        fi
    } > /etc/lightdm/lightdm.conf.d/50-navdat.conf
    echo /usr/sbin/lightdm > /etc/X11/default-display-manager
    ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
    systemctl disable gdm3 >>"$LOG" 2>&1 || true

    say "Установка завершена."
    exit 0
fi

# ================================================================ этап user
say "NavDat installer: $PUBLIC_REPO@$NAVDAT_REF, packages $PRIVATE_REPO@$RELEASE_TAG"

. /etc/os-release
if [ "${ID:-}" != ubuntu ] || ! printf '%s\n%s\n' 24.04 "${VERSION_ID:-0}" | sort -V -C; then
    die "Нужна Ubuntu 24.04 или новее, а здесь: ${PRETTY_NAME:-неизвестная система}."
fi
if [ "$(dpkg --print-architecture)" != amd64 ]; then
    die "Нужен компьютер x86-64 (amd64): закрытые программы NavDat существуют только для этой архитектуры."
fi
command -v curl >/dev/null && command -v python3 >/dev/null \
    || die "Нужны curl и python3 (sudo apt install curl python3)."

ui_info "Мастер установит бортовую программу NavDat.

Понадобятся:
 • логин GitHub и ключ доступа к закрытым пакетам NavDat (выдаёт администратор);
 • пароль для оператора navdat;
 • пароль администратора этого компьютера;
 • подключение к интернету.

После установки компьютер нужно перезагрузить."

check_credentials() {   # $1 логин, $2 ключ
    local login
    login=$(curl -fsSL -H "Authorization: Bearer $2" -H "Accept: application/vnd.github+json" \
                 "$GITHUB_API/user" 2>>"$LOG" \
            | python3 -c 'import json,sys; print(json.load(sys.stdin).get("login",""))' 2>>"$LOG") \
        || return 1
    if [ "${login,,}" != "${1,,}" ]; then
        say "key belongs to '$login', not '$1'"
        return 1
    fi
    curl -fsSL -o /dev/null -H "Authorization: Bearer $2" -H "Accept: application/vnd.github+json" \
         "$GITHUB_API/repos/$PRIVATE_REPO/releases/tags/$RELEASE_TAG" 2>>"$LOG"
}

GH_LOGIN=${NAVDAT_GH_LOGIN:-}
GH_TOKEN=${NAVDAT_GH_TOKEN:-}
for attempt in 1 2 3; do
    [ -n "$GH_LOGIN" ] || GH_LOGIN=$(ui_entry "Логин GitHub:")
    [ -n "$GH_TOKEN" ] || GH_TOKEN=$(ui_secret "Ключ доступа GitHub для $GH_LOGIN:")
    if check_credentials "$GH_LOGIN" "$GH_TOKEN"; then break; fi
    ui_error "Логин или ключ доступа не подходят, либо у этой учётной записи нет доступа к закрытым пакетам NavDat."
    [ -n "${NAVDAT_GH_TOKEN:-}" ] && die "Неверные учётные данные GitHub."
    [ "$attempt" = 3 ] && die "Не удалось войти в GitHub."
    GH_LOGIN=; GH_TOKEN=
done
say "GitHub access ok for $GH_LOGIN"

OP_PASSWORD=${NAVDAT_PASSWORD:-}
while [ -z "$OP_PASSWORD" ]; do
    p1=$(ui_secret "Новый пароль оператора navdat:")
    p2=$(ui_secret "Повторите пароль оператора:")
    if [ -z "$p1" ]; then ui_error "Пароль не может быть пустым."
    elif [ "$p1" != "$p2" ]; then ui_error "Пароли не совпадают."
    else OP_PASSWORD=$p1; fi
done
unset p1 p2

case "${NAVDAT_AUTOLOGIN:-ask}" in
    yes|no) AUTOLOGIN=$NAVDAT_AUTOLOGIN ;;
    *) if ui_yesno "Входить в систему как оператор navdat автоматически при включении?"; then
           AUTOLOGIN=yes; else AUTOLOGIN=no; fi ;;
esac

# ответы передаются второму этапу через окружение sudo -E
export NAVDAT_GH_TOKEN=$GH_TOKEN NAVDAT_PASSWORD=$OP_PASSWORD NAVDAT_AUTOLOGIN=$AUTOLOGIN
export NAVDAT_PUBLIC_REPO=$PUBLIC_REPO NAVDAT_REF NAVDAT_PRIVATE_REPO=$PRIVATE_REPO \
       NAVDAT_RELEASE_TAG=$RELEASE_TAG NAVDAT_GITHUB_API=$GITHUB_API NAVDAT_SOURCE_URL=$SOURCE_URL
# не в /tmp: fs.protected_regular запрещает root дописывать чужие файлы
# в каталогах со sticky-битом
export NAVDAT_PROGRESS=$(mktemp -p "${XDG_RUNTIME_DIR:-$HOME}" .navdat-progress.XXXXXX)
SELF=$(readlink -f "$0")

run_root() {  # запускает второй этап; пароль sudo спрашивается до трёх раз
    if [ "$(id -u)" = 0 ]; then bash "$SELF" root; return; fi
    if sudo -n true 2>/dev/null; then sudo -E bash "$SELF" root; return; fi
    local pw
    for _ in 1 2 3; do
        pw=$(ui_secret "Пароль администратора (sudo) пользователя $(id -un):")
        if printf '%s\n' "$pw" | sudo -S -p '' -v 2>/dev/null; then
            printf '%s\n' "$pw" | sudo -S -p '' -E bash "$SELF" root
            return
        fi
        ui_error "Неверный пароль администратора."
    done
    die "Не удалось получить права администратора."
}

say "== Установка"
if [ "$UI" = zenity ]; then
    tail -f "$NAVDAT_PROGRESS" | zenity --progress --title "$TITLE" --width 460 \
        --pulsate --auto-close --no-cancel 2>/dev/null &
    PROGRESS_PID=$!
    trap 'pkill -P $PROGRESS_PID 2>/dev/null; kill $PROGRESS_PID 2>/dev/null; rm -f "$NAVDAT_PROGRESS"' EXIT
else
    trap 'rm -f "$NAVDAT_PROGRESS"' EXIT
fi

if run_root; then
    RESULT=0
else
    RESULT=$?
fi
[ "$UI" = zenity ] && echo 100 >> "$NAVDAT_PROGRESS"
unset NAVDAT_GH_TOKEN NAVDAT_PASSWORD GH_TOKEN OP_PASSWORD
[ "$RESULT" = 0 ] || die "Установка прервалась."

case "${NAVDAT_REBOOT:-ask}" in
    yes) systemctl reboot ;;
    no)  ui_info "NavDat установлен. После перезагрузки войдите как navdat (сеанс «Navdat Awesome»)." ;;
    *)   if ui_yesno "NavDat установлен. Для входа выберите пользователя navdat, сеанс «Navdat Awesome».

Перезагрузить компьютер сейчас?"; then
             systemctl reboot
         fi ;;
esac
