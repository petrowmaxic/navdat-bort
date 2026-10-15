import gi
gi.require_version('Gtk', '3.0')
from gi.repository import GLib, Gtk

from .lookup import SerialLookup

class SerialSelector:
    def __init__(self, combobox, devname=None):
        self.combobox = combobox
        self.lookup = SerialLookup()
        self.devname = devname
        self.extra = set()

        if devname:
            self.extra.add(devname)

        renderer = Gtk.CellRendererText()
        self.combobox.pack_start(renderer, True)
        self.combobox.add_attribute(renderer, "text", 0);
        self.old_devices = []
        self.update()

        self.combobox.connect("changed", self.devname_changed)
        self.combobox.connect("destroy", self.on_combo_destroy)
        self.timer_id = GLib.timeout_add_seconds(2, self.on_timeout)

    def set_devname(self, devname):
        self.devname = devname
        if devname is not None:
            self.extra.add(devname)
        self.update(True)

    def on_combo_destroy(self, w):
        if self.timer_id is not None:
            GLib.source_remove(self.timer_id)
            self.timer_id = None

    def on_timeout(self):
        """update serial device list"""
        self.update()
        return True

    def devname_changed(self, combo):
        model = combo.get_model()
        iter = combo.get_active_iter()
        if not iter:
            return
        old = self.devname
        self.devname, = model.get(iter, 1)
        self.extra.add(old)
        self.extra.add(self.devname)

    def update(self, force=False):
        devices = {}

        devs = self.lookup.lookup()

        if not force and devs == self.old_devices:
            return

        model = Gtk.TreeStore(str, str)
        for dev in devs:
            piter = model.append(None)
            model.set(piter, 0, dev.pretty_name(), 1, dev.devname)

            devices[dev.devname] = piter

            if not dev.by_path or not dev.by_id:
                continue

            if dev.by_path:
                iter = model.append(piter)
                model.set(iter, 0, '%s: by-path' % dev.devname, 1, dev.by_path)
                devices[dev.by_path] = iter
            if dev.by_id:
                iter = model.append(piter)
                model.set(iter, 0, '%s: by-id' % dev.devname, 1, dev.by_id)
                devices[dev.by_id] = iter

        for i in self.extra:
            if i is None or i in devices:
                continue
            iter = model.append(None)
            model.set(iter, 0, "%s: (not connected)" % i, 1, i)
            devices[i] = iter

        self.combobox.set_model(model)
        if self.devname in devices:
            self.combobox.set_active_iter(devices[self.devname])
        self.old_devices = devs

if __name__ == "__main__":
    window = Gtk.Window()
    combo = Gtk.ComboBox()
    window.add(combo)
    window.show_all()

    selector = SerialSelector(combo, '/dev/serial/by-path/pci-0000:00:1d.1-usb-0:1:1.0-port0')
    window.connect('destroy', Gtk.main_quit)
    Gtk.main()
