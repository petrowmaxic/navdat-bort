import gtk
import gobject
from glade import Glade
import bortcfg
import bortd
from i18n import _

class BortApplet:
    def __init__(self, proxy = None):
	self.icon = gtk.StatusIcon()
	self.settings_dlg = None
	self.about_dlg = None
	self.icon.connect('popup-menu', self.popup_menu)
	self.icon.connect('activate', lambda x: self.settings_show())

	self.on_disconnected()

	if not proxy:
	    proxy = bortd.BortProxy()

	proxy.connect('connected', self.on_connected)
	proxy.connect('disconnected', self.on_disconnected)

	self.proxy = proxy
	self.proxy.start()

    def on_connected(self, proxy, client):
	self.icon.set_from_icon_name('gtk-yes')
	self.icon.set_tooltip(_('Bort daemon running'))
	self.client = client

    def on_disconnected(self, proxy = None):
	self.icon.set_from_icon_name('gtk-dialog-error')
	self.icon.set_tooltip(_('Bort daemon not running!'))
	self.client = None

    def settings_show(self):
	if self.settings_dlg == None:
	    self.settings_dlg = bortcfg.BortConfigWindow(proxy = self.proxy)
	    self.settings_dlg.window.connect('delete-event', lambda x,ev: x.hide() or True)
	else:
	    self.settings_dlg.read_config()
	    self.settings_dlg.window.present()

    def about_show(self):
	def on_applet_about_response(dlg, applet):
	    dlg.destroy()
	    self.about_dlg =  None

	if self.about_dlg == None:
	    about = Glade('bortcfg.glade', 'applet_about')
	    about.signal_autoconnect(locals())
	    self.about_dlg = about.applet_about
	    self.about_dlg.set_logo_icon_name('navdat-logo')
	else:
	    self.about_dlg.present()

    def popup_menu(self, icon, button, activate_time):
	def on_bortd_settings_activate(item):
	    self.settings_show()
	def on_about_activate(item):
	    self.about_show()
	def on_save_activate(item):
	    bortcfg.SessionSave(self.client)
	def on_restore_activate(item):
	    bortcfg.SessionRestore(self.client)

	menu = Glade('bortcfg.glade', 'applet_menu')
	menu.applet_menu.popup(None,None,gtk.status_icon_position_menu, button, activate_time, self.icon)
	menu.signal_autoconnect(locals())

if __name__ == "__main__":
    applet = BortApplet()
    gtk.main()
