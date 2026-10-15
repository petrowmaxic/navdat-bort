# NavDat — бортовой комплекс

Открытые части бортовой программы сбора аэрогеофизических данных **NavDat**
(Ubuntu 16.04 «xenial»):

| Каталог | Содержимое |
|---|---|
| `bort/bortcfg/` | `navdat-bortcfg`: GUI-конфигуратор демона `bortd`, апплет в трее, сохранение и восстановление сессии (Python 2, PyGTK2, libglade) |
| `bort/applications`, `bort/menus`, `bort/desktop-directories` | Ярлыки и XDG-меню клиентов NavDat |
| `bort/glade/` | Интерфейсы клиентов `rapanel`, `tvpanel`, `rhost-koleso` |
| `navdat/help/` | Справка (DocBook XML и HTML, ru/en) |
| `awesome/`, `navdat-awesome-config/`, `awesome (status)/` | Варианты конфигурации awesome WM рабочего места оператора |
| `bortNFVSEGEI/README.txt` | Инструкция по ручной установке deb-пакетов |

Демон `bortd` и клиенты (`navdat-arrow`, `navdat-specview` и др.) — закрытые
бинарники. Их deb-пакеты в репозиторий не входят (см. `.gitignore`).

Порт на современную Ubuntu ведётся в ветке `port/ubuntu-24.04`.
