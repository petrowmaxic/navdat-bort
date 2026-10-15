import gettext
import locale

try:
    from config import PACKAGE, PACKAGE_LOCALE_DIR

    gettext.bindtextdomain(PACKAGE, PACKAGE_LOCALE_DIR)
    gettext.textdomain(PACKAGE)
    try:
        # GtkBuilder translates through the C library
        locale.bindtextdomain(PACKAGE, PACKAGE_LOCALE_DIR)
        locale.textdomain(PACKAGE)
    except AttributeError:
        pass

    _ = gettext.gettext
except Exception:
    _ = lambda x: x
