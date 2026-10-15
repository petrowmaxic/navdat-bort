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
| `legacy/` | Контейнер Ubuntu 16.04 для закрытых клиентов на Qt4 |
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
  собраны под Qt4, Qwt и libglade2, которых в 24.04 нет. Поэтому они
  запускаются в контейнере Ubuntu 16.04 через `navdat-legacy`. Ярлыки, меню и
  иконки ставятся на хост, а `/usr/bin/navdat-*` становятся обёртками.

## Установка на Ubuntu 24.04

Закрытые deb-пакеты NavDat 0.2.12 в репозиторий не входят. Положите их в
отдельный каталог, например `~/navdat-debs`.

```bash
sudo apt install dpkg-dev podman
packaging/build-debs.sh dist
packaging/repack-proprietary.sh ~/navdat-debs dist
sudo apt install ./dist/*.deb
sudo passwd navdat
```

Образ контейнера для клиентов собирается один раз, от имени пользователя `navdat`:

```bash
navdat-legacy build ~/navdat-debs
```

После перезагрузки в LightDM выберите сеанс **Navdat Awesome**.

## Проверка

CI (`.github/workflows/ubuntu-24.04.yml`) на Ubuntu 24.04:

- гоняет тесты bortcfg под Xvfb: протокол, все 23 диалога устройств, сохранение
  конфига, апплет;
- собирает и ставит пакеты;
- запускает awesome с конфигом и проверяет, что нет ошибок.

Работа с реальным `bortd`, приборами и контейнером клиентов в CI не
проверяется, потому что для этого нужны закрытые пакеты.
