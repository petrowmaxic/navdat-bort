"""Smoke tests for the Python 3 / GTK 3 port of bortcfg.

Run under X (e.g. xvfb-run):  python3 -m unittest discover -s tests -v
"""
import os
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'bort', 'bortcfg'))
sys.path.insert(0, HERE)

# isolated HOME before bortrc expands ~
HOME = tempfile.mkdtemp(prefix='navdat-home-')
os.environ['HOME'] = HOME
os.environ.setdefault('USER', 'navdat-test')
os.environ.pop('BORT_SERVER', None)

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import GLib, Gtk

import bortd
import bortrc
import bortcfg
import applet
from fake_bortd import FakeBortd

# one fake daemon for the whole run: the abstract socket name is fixed
SERVER = FakeBortd()


def iterate(cond, timeout=5.0):
    """Run the GLib main loop until cond() is true."""
    ctx = GLib.MainContext.default()
    end = time.time() + timeout
    while not cond():
        if time.time() > end:
            raise AssertionError('timeout waiting for condition')
        ctx.iteration(False)
        time.sleep(0.01)


BORTDRC = """sys::datadir %s/data/
device fe
{
    bind tcp://127.0.0.1:5000
}
device fplan
""" % HOME + ''.join(
    'device %s\n{\n    src tcp://127.0.0.1:4001\n}\n' % name
    for name in sorted(bortcfg.devices) if name != 'fe')


class ProtocolTest(unittest.TestCase):
    def test_list_get_session(self):
        client = bortd.BortClient()
        client.sync()
        while not client._vars:
            client.handle_input()
        self.assertEqual(client['sys::demo_mode'].get(force=True), 1)
        client.session_save(False)
        client.sync()
        self.assertEqual(client._session, ['navdat-arrow-1', 'navdat-fplan-2'])


class ConfigTest(unittest.TestCase):
    def test_roundtrip(self):
        path = os.path.join(HOME, 'roundtrip')
        cfg = bortrc.Config()
        cfg.set('sys::datadir', '/data/')
        dev = bortrc.Config('device', 'jps')
        dev.set_list('init', ['a', 'b'])
        cfg.children.append(dev)
        bortrc.write_config(cfg, path)
        again = bortrc.load_config(path)
        self.assertEqual(str(again), str(cfg))
        self.assertEqual([i.value for i in again.get_key('device')[0].get_key('init')],
                         ['a', 'b'])

    def test_zero_values_are_written(self):
        path = os.path.join(HOME, 'zeros')
        cfg = bortrc.Config()
        dev = bortrc.Config('device', 'gsa2000')
        dev.set('nostab', 0)
        dev.set('dx', 0.0)
        cfg.children.append(dev)
        bortrc.write_config(cfg, path)
        again = bortrc.load_config(path).get_key('device')[0]
        self.assertEqual(again.exclusive('nostab'), '0')
        self.assertEqual(again.exclusive('dx'), '0.0')

    def test_malformed_config_is_rejected(self):
        for text in ('}\n', '{\n', 'device jps\n{\n', 'device jps\n}\n}\n'):
            with self.subTest(text=text):
                path = os.path.join(HOME, 'broken')
                with open(path, 'w') as fp:
                    fp.write(text)
                with self.assertRaises(bortrc.Error):
                    bortrc.load_config(path)

    def test_source_parse(self):
        self.assertEqual(str(bortcfg.Source('tcp://host:4001')), 'tcp://host:4001')
        self.assertEqual(str(bortcfg.Source('serial:///dev/ttyS0,9600,8,n,1')),
                         'serial:///dev/ttyS0,9600,8,n,1')
        self.assertEqual(str(bortcfg.Source('rfc2217://h:1/115200,8,e,2')),
                         'rfc2217://h:1/115200,8,e,2')


class GuiTest(unittest.TestCase):
    def setUp(self):
        os.makedirs(os.path.join(HOME, '.bort'), exist_ok=True)
        with open(os.path.join(HOME, '.bort', 'bortdrc'), 'w') as fp:
            fp.write(BORTDRC)

    def test_config_window(self):
        proxy = bortd.BortProxy()
        window = bortcfg.BortConfigWindow(proxy=proxy)
        window.show()
        iterate(lambda: window.client is not None)
        iterate(lambda: 'demo' in window.xml.label_state.get_label())
        # every known device (fplan has no dialog) is listed
        self.assertEqual(len(window.liststore), len(bortcfg.devices))

        # open, fill and save the properties dialog of every device type
        for row in window.liststore:
            cfg = row[bortcfg.COLUMN_PRIV]
            with self.subTest(device=cfg.value):
                dlg = bortcfg.ConfigureDialog(cfg)
                dlg.xml.entry_host.set_text('10.0.0.1')
                dlg.xml.entry_port.set_text('4002')
                dlg.model.save_to_config(dlg, cfg)
                dlg.xml.configure_dialog.destroy()
                key = 'bind' if cfg.value == 'fe' else 'src'
                self.assertEqual(cfg.exclusive(key), 'tcp://10.0.0.1:4002')

        window.xml.button_save.set_sensitive(True)
        window.on_button_save_clicked(window.xml.button_save)
        saved = bortrc.load_config()
        self.assertEqual(len(saved.get_key('device')), len(bortcfg.devices) + 1)
        window.window.destroy()

    def test_fe_local_socket(self):
        """FE со штатным «src bind unix»: OK в диалоге не должен добавлять
        «bind tcp», иначе bortd закрывает локальный сокет для клиентов."""
        fe = bortrc.Config('device', 'fe')
        fe.set('src', 'bind unix /tmp/.bort-0')
        dlg = bortcfg.ConfigureDialog(fe)
        dlg.model.save_to_config(dlg, fe)
        dlg.xml.configure_dialog.destroy()
        self.assertEqual(fe.get_key('bind'), [])
        self.assertEqual(fe.exclusive('src'), 'bind unix /tmp/.bort-0')

        # явный выбор TCP заменяет локальный сокет, а не добавляется к нему
        dlg = bortcfg.ConfigureDialog(fe)
        combo = dlg.xml.combobox_source_type
        for row in combo.get_model():
            if row[1] == bortcfg.Source.TCP:
                combo.set_active_iter(row.iter)
        dlg.xml.entry_host.set_text('0.0.0.0')
        dlg.xml.entry_port.set_text('5000')
        dlg.model.save_to_config(dlg, fe)
        dlg.xml.configure_dialog.destroy()
        self.assertEqual(fe.exclusive('bind'), 'tcp://0.0.0.0:5000')
        self.assertEqual(fe.get_key('src'), [])

    def test_window_from_connected_proxy(self):
        """Окно из апплета: proxy уже подключён и получил список переменных."""
        proxy = bortd.BortProxy()
        proxy.start()
        iterate(lambda: proxy.client is not None and proxy.client._vars)
        window = bortcfg.BortConfigWindow(proxy=proxy)
        iterate(lambda: 'demo' in window.xml.label_state.get_label())
        window.window.destroy()

    def test_applet(self):
        proxy = bortd.BortProxy()
        app = applet.BortApplet(proxy=proxy)
        iterate(lambda: app.client is not None)
        app.about_show()
        self.assertIsNotNone(app.about_dlg)
        app.about_dlg.destroy()
        menu = applet.Glade('bortcfg.ui', 'applet_menu')
        self.assertEqual(len(menu.applet_menu.get_children()), 4)


if __name__ == '__main__':
    unittest.main()
