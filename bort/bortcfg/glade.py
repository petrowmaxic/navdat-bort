import gtk
import gtk.glade

class Glade(gtk.glade.XML):
    def __init__(self, *args, **kwargs):
	gtk.glade.XML.__init__(self, *args, **kwargs)

    def __getattr__(self, what):
	widget = self.get_widget(what)
	if not widget:
	    raise AttributeError, 'no such widget %s' % what
	setattr(self, what, widget)
	return widget

try:
    from i18n import PACKAGE, PACKAGE_LOCALE_DIR
    gtk.glade.bindtextdomain(PACKAGE, PACKAGE_LOCALE_DIR)
    gtk.glade.textdomain(PACKAGE)
except:
    pass
