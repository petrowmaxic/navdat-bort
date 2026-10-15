# NavDat — бортовой комплекс

Открытые части бортовой программы сбора аэрогеофизических данных **NavDat**
и их порт с Ubuntu 16.04 на **Ubuntu 24.04 LTS**.

| Каталог | Содержимое |
|---|---|
| `bort/bortcfg/` | `navdat-bortcfg`: конфигуратор демона `bortd`, апплет в трее, сохранение и восстановление сессии. Python 3, GTK 3 (PyGObject), GtkBuilder |
| `bort/applications`, `bort/menus`, `bort/desktop-directories` | Ярлыки и XDG-меню клиентов NavDat |
| `bort/glade/` | Интерфейсы закрытых клиентов `rapanel`, `tvpanel`, `rhost-koleso` (libglade, используются бинарниками) |
| `navdat/` | Справка (DocBook XML и HTML, ru/en) и `navdat-help` |
| `navdat-awesome-config/` | Конфигурация awesome WM рабочего места оператора и X-сеанс `navdat-awesome` |
| `packaging/` | Сборка deb-пакетов для 24.04 и перепаковка закрытых пакетов |
| `tools/glade2builder.py` | Конвертер libglade → GtkBuilder |
| `tests/` | Тесты bortcfg с фейковым `bortd` |

Исходная версия для 16.04 лежит в ветке `main`.

## Что изменилось при переносе на 24.04

- **bortcfg**: Python 2 + PyGTK 2 + libglade → Python 3 + GTK 3 + GtkBuilder.
  Протокол `bortd` работает с `bytes`. Поиск последовательных портов через HAL
  удалён, остался поиск по `/dev`.
- **awesome 4.3**: вместо Unity и gnome-session используется собственный X-сеанс
  `navdat-awesome-session`. Замены: compton → picom, gnome-screensaver →
  `dm-tool lock`, unity-control-center → gnome-control-center или pavucontrol,
  `pacmd` → `pactl` (работает с PipeWire). Автозапуск (`navdat-applet`,
  nm-applet) выполняет `dex`.
- **navdat-user** создаёт пользователя `navdat` **без пароля**. Пароль задаётся
  вручную после установки.
- **bortd** (закрытый бинарник) зависит только от glibc и libstdc++ и работает
  на 24.04 нативно. В пакете исправлена зависимость `libgcc1` → `libgcc-s1`.
- **Клиенты** (`navdat-arrow`, `navdat-specview`, `navdat-tvpanel` и др.)
  работают нативно, без контейнера. 15 из 21 клиента используют GTK2 и
  libglade, а они есть в 24.04. Для остальных пакет `navdat-compat` кладёт в
  `/opt/navdat/lib` библиотеки из Ubuntu 16.04: Qt4, Qwt, libpng12, libaudio
  и libFOX. Сами бинарники лежат в `/usr/lib/navdat/bin`, а
  `/usr/bin/navdat-*` — обёртки, которые подключают эти библиотеки.

## Установка на новый ноутбук

Нужен ноутбук x86-64 с Ubuntu 24.04 или новее и интернетом. Закрытые
программы NavDat существуют только под x86-64, на ARM (Raspberry Pi)
не работают.

### Оператору

Скачать мастер и запустить его под своей учётной записью (с правами
администратора):

```bash
wget https://raw.githubusercontent.com/petrowmaxic/navdat-bort/port/ubuntu-24.04/install/navdat-install.sh
```

```bash
bash navdat-install.sh
```

Мастер по очереди спросит:

1. логин GitHub и ключ доступа к закрытым пакетам NavDat (выдаёт администратор);
2. новый пароль для оператора `navdat`, дважды;
3. входить ли автоматически при включении;
4. пароль администратора этого ноутбука.

Дальше всё ставится само: закрытые пакеты, открытые пакеты из этого
репозитория, библиотеки совместимости, пользователь `navdat`, сеанс
«Navdat Awesome» и менеджер входа LightDM. Журнал пишется в
`~/navdat-install.log`; ключ доступа и пароли в него не попадают. В конце
мастер предложит перезагрузку.

### Администратору (один раз)

Закрытые пакеты NavDat 0.2.12 хранятся в приватном репозитории
`petrowmaxic/navdat-bort-private`, в релизе `navdat-0.2.12`. Создать его из
каталога с оригинальными deb (`bortNFVSEGEI/bortNFVSEGEI`):

```bash
gh repo create petrowmaxic/navdat-bort-private --private --add-readme
```

```bash
cd bortNFVSEGEI/bortNFVSEGEI && shasum -a 256 *.deb > SHA256SUMS
```

```bash
gh release create navdat-0.2.12 --repo petrowmaxic/navdat-bort-private --title "NavDat 0.2.12" --notes "Оригинальные пакеты для navdat-install.sh" *.deb SHA256SUMS
```

Ключ доступа для ноутбуков: GitHub → Settings → Developer settings →
Personal access tokens → Fine-grained tokens → Generate new token.

- Repository access: только `petrowmaxic/navdat-bort-private`.
- Permissions → Contents: Read-only.
- Срок действия — по вашей политике.

Оператору сообщаются логин учётной записи, создавшей ключ, и сам ключ.

### Вручную, без мастера

```bash
packaging/build-debs.sh dist
```

```bash
packaging/repack-proprietary.sh ~/navdat-debs dist
```

```bash
sudo apt install ./dist/*.deb
```

```bash
sudo passwd navdat
```

`repack-proprietary.sh` скачивает из архива Ubuntu 16.04 библиотеки для
`navdat-compat`. Их версии и SHA256 зафиксированы в
`packaging/build-compat.sh`.

## Проверка

Локально, в виртуальной машине Ubuntu 24.04 на QEMU (на macOS работает без Docker):

```bash
tests/vm/run.sh
```

Скрипт поднимает ВМ из облачного образа и прогоняет юнит-тесты bortcfg. Затем
собирает и ставит пакеты, запускает настоящий сеанс `navdat-awesome` от
пользователя `navdat`, открывает меню и bortcfg, проверяет индикаторы и
сохраняет скриншоты в `~/.cache/navdat-vm-<arch>/shots`. Без закрытых пакетов
`navdat-bortd` заменяется пустой заглушкой.

С настоящими закрытыми пакетами (нужна x86-64 ВМ; на ARM-Mac она работает
через эмуляцию, прогон занимает около получаса):

```bash
VM_ARCH=amd64 NAVDAT_DEBS=~/navdat-debs tests/vm/run.sh
```

В этом режиме проверяются перепаковка, `navdat-compat`, запуск настоящего
`bortd` в демо-режиме со всеми типами приборов и его остановка по протоколу.
Затем каждый клиент из меню NavDat запускается в сеансе и должен открыть окно.

Результат на Ubuntu 24.04.5 x86-64 (15.10.2026):

- `bortd` 0.2.12 работает нативно: 525 переменных, демо-режим, штатная
  остановка по команде;
- все 17 графических клиентов открывают окна без контейнера, включая
  Qt4-клиенты (`arrow`, `specview`, `status`, `qem-control`) и `fplan` на FOX;
- реальные приборы, запись данных и сравнение файлов со старой системой
  этим не проверяются.

Тот же набор проверок, кроме живого сеанса, выполняет CI (`.github/workflows/ubuntu-24.04.yml`) на Ubuntu 24.04:

- гоняет тесты bortcfg под Xvfb: протокол, все 23 диалога устройств, сохранение
  конфига, апплет;
- собирает и ставит пакеты;
- запускает awesome с конфигом и проверяет, что нет ошибок.

Работа с реальным `bortd` и клиентами в CI не проверяется, потому что для
этого нужны закрытые пакеты. Локально её проверяет `tests/vm/run.sh` с
`NAVDAT_DEBS=<каталог с оригинальными deb>` на x86-64 ВМ.
