import gettext

try:
    from config import PACKAGE, PACKAGE_LOCALE_DIR

    gettext.bindtextdomain(PACKAGE, PACKAGE_LOCALE_DIR)
    gettext.bind_textdomain_codeset(PACKAGE, "UTF-8")
    gettext.textdomain(PACKAGE)

    _ = lambda x: gettext.gettext(x)
except:
    _ = lambda x: x
