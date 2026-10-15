"""Thin GtkBuilder wrapper keeping the old libglade-style API."""
import os
import xml.etree.ElementTree as ET

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import GObject, Gtk

try:
    from config import PACKAGE
except ImportError:
    PACKAGE = None

UI_DIR = os.path.dirname(os.path.abspath(__file__))

# Non-widget toplevel objects (adjustments, models) are not children of any
# widget, so GtkBuilder has to be asked for them explicitly.
_helpers = {}

def _helper_objects(path):
    if path not in _helpers:
        root = ET.parse(path).getroot()
        _helpers[path] = [o.get('id') for o in root.findall('object')
                          if o.get('class') in ('GtkAdjustment', 'GtkListStore',
                                                'GtkTreeStore', 'GtkTextBuffer')]
    return _helpers[path]


class Glade:
    def __init__(self, filename, root):
        path = os.path.join(UI_DIR, filename)
        self.builder = Gtk.Builder()
        if PACKAGE:
            self.builder.set_translation_domain(PACKAGE)
        self.builder.add_objects_from_file(path, [root] + _helper_objects(path))

    def __getattr__(self, what):
        widget = self.builder.get_object(what)
        if widget is None:
            raise AttributeError('no such widget %s' % what)
        setattr(self, what, widget)
        return widget

    def signal_autoconnect(self, handlers):
        """Connect signals to a dict or an object; like libglade, missing
        handlers are silently ignored."""
        def lookup(name):
            if isinstance(handlers, dict):
                return handlers.get(name)
            return getattr(handlers, name, None)

        def connect(builder, obj, signal, handler_name, connect_obj, flags, *args):
            handler = lookup(handler_name)
            if handler is None:
                return
            if flags & GObject.ConnectFlags.AFTER:
                obj.connect_after(signal, handler)
            else:
                obj.connect(signal, handler)

        self.builder.connect_signals_full(connect, None)
