#!/usr/bin/python3
## TODO: serial and rfc settings
import os
import sys
import subprocess

import bortrc
import bortd

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk

from glade import Glade
from i18n import _

from serialsel import SerialSelector

(COLUMN_DEVICE, COLUMN_PRIV) = range(2)

def message_dialog(parent, message_type, buttons, text=None):
    return Gtk.MessageDialog(transient_for=parent, modal=True,
                             message_type=message_type, buttons=buttons,
                             text=text)

def file_chooser(title, action):
    chooser = Gtk.FileChooserDialog(title=title, action=action)
    chooser.add_buttons(_('_Cancel'), Gtk.ResponseType.CANCEL,
                        _('_Open'), Gtk.ResponseType.OK)
    return chooser

## TODO
def help():
    import config
    help_file = '%s/navdat-help.xml' % config.HELPDIR
    if not os.access(help_file, os.R_OK):
        return

class ValidationError(Exception):
    pass

serial_speeds = [460800, 230400, 115200, 57600, 38400, 19200, 9600, 4800, 2400]
serial_bits = [8,7,6]
serial_parity = ['n','e','o']
serial_stops = [1,2]

class Source:
    """TODO: handle all other sources as well"""
    (BROKEN, TCP, SERIAL, RFC2217) = range(4)

    def __init__(self, src = ''):
        attrs = src.split('://', 1)
        self.type = self.BROKEN

        self.hostname = ''
        self.port = -1
        self.serial_device = '/dev/ttyS0'
        self.serial_baud = 115200
        self.serial_bits = 8
        self.serial_parity = 'n'
        self.serial_stop_bits = 1
        try:
            if len(attrs) != 2:
                raise ValueError
            if attrs[0] == 'tcp':
                options = attrs[1].split(':', 1)
                self.parse_tcp(options)
            elif attrs[0] == 'serial':
                options = attrs[1].split(',')
                self.parse_serial(options)
            elif attrs[0] == 'rfc2217':
                options = attrs[1].split(':', 1)
                if len(options) != 2:
                    raise ValueError
                options_rfc = options[1].split('/', 1)
                if len(options_rfc) != 2:
                    raise ValueError

                options_tcp = (options[0], options_rfc[0])
                options_serial = options_rfc[1].split(',')
                self.parse_rfc2217(options_tcp, options_serial)
        except ValueError:
            self.type = self.BROKEN

    def parse_tcp(self, options):
        if len(options) == 2:
            self.hostname = options[0]
            try:
                self.port = int(options[1])
                self.type = self.TCP
            except ValueError:
                pass

    def parse_serial(self, options):
        if len(options) < 1:
            raise ValueError
        self.serial_device = options[0]
        if len(options) > 1:
            try:
                self.serial_baud = int(options[1])
            except ValueError:
                pass
        if len(options) > 2:
            try:
                bits = int(options[2])
                if not bits in [6,7,8]:
                    raise ValueError
                self.serial_bits = bits
            except ValueError:
                pass
        if len(options) > 3:
            try:
                parity = options[3].lower()
                if not parity in 'neo':
                    raise ValueError
                self.serial_parity = parity
            except ValueError:
                pass
        if len(options) > 4:
            try:
                bits = int(options[4])
                if not bits in [1,2]:
                    raise ValueError
                self.serial_stop_bits = bits
            except ValueError:
                pass
        self.type = self.SERIAL

    def parse_rfc2217(self, options_tcp, options_serial):
        self.parse_tcp(options_tcp)
        self.parse_serial(['/dev/null'] + options_serial)
        self.type = self.RFC2217

    def __str__(self):
        fmt_serial = lambda: '%d,%d,%s,%d' % (self.serial_baud, self.serial_bits,
                            self.serial_parity, self.serial_stop_bits)
        fmt_tcp = lambda: '%s:%s' % (self.hostname, self.port)
        if self.type == self.TCP:
            return 'tcp://' + fmt_tcp()
        if self.type == self.SERIAL:
            return 'serial://%s,' % (self.serial_device) + fmt_serial()
        if self.type == self.RFC2217:
            return 'rfc2217://' + fmt_tcp() + '/' + fmt_serial()
        return _('No source selected')

    def __repr__(self):
        return '<class %s: %s>' % (self.__class__.__name__, str(self))

class BaseDevice(object):
    have_source = True

    def load_from_config(self, dlg, cfg):
        self.fields = {}
        if self.have_source:
            src = Source(cfg.exclusive('src'))
            self.liststore = Gtk.ListStore(str, int)
            dlg.xml.combobox_source_type.set_model(self.liststore)
            dlg.xml.combobox_source_type.connect('changed', lambda w: self.on_type_combo_changed(w,dlg))

            sources = ((Source.TCP, _("TCP/IP")), (Source.SERIAL, _("Serial Port")), (Source.RFC2217, _("Serial port over TCP/IP (RFC2217)")))

            for (t, n) in sources:
                if hasattr(self, 'sources_allowed'):
                    if not t in self.sources_allowed:
                        continue
                iter = self.liststore.append()
                self.liststore.set(iter, 0, n, 1, t)
                if src.type == t:
                    dlg.xml.combobox_source_type.set_active_iter(iter)

            self.serial_selector = SerialSelector(dlg.xml.combobox_serial)

            for baud in serial_speeds:
                dlg.xml.combobox_baudrate.append_text('%d' % baud)
            dlg.xml.combobox_baudrate.set_active(0)
            dlg.xml.combobox_bits.set_active(0)
            dlg.xml.combobox_parity.set_active(0)
            dlg.xml.combobox_stops.set_active(0)

            if dlg.xml.combobox_source_type.get_active() == -1:
                dlg.xml.combobox_source_type.set_active(0)

            def set_tcp_settings():
                dlg.xml.entry_host.set_text(src.hostname)
                dlg.xml.entry_port.set_text(str(src.port))

            def set_serial_settings():
                try:
                    idx = serial_speeds.index(src.serial_baud)
                    dlg.xml.combobox_baudrate.set_active(idx)
                except ValueError:
                    pass
                try:
                    idx = serial_bits.index(src.serial_bits)
                    dlg.xml.combobox_bits.set_active(idx)
                except ValueError:
                    pass
                try:
                    idx = serial_parity.index(src.serial_parity)
                    dlg.xml.combobox_parity.set_active(idx)
                except ValueError:
                    pass
                try:
                    idx = serial_stops.index(src.serial_stop_bits)
                    dlg.xml.combobox_stops.set_active(idx)
                except ValueError:
                    pass

                self.serial_selector.set_devname(src.serial_device)

            if src.type == Source.TCP:
                set_tcp_settings()
            elif src.type == Source.SERIAL:
                set_serial_settings()
            elif src.type == Source.RFC2217:
                set_tcp_settings()
                set_serial_settings()
            self.fields['src'] = src
        else:
            dlg.xml.table_source_type.hide()

    def on_type_combo_changed(self, box, dlg):
        type = self.liststore[box.get_active_iter()][1]

        if type == Source.TCP:
            dlg.xml.table_serial.hide()
            dlg.xml.table_tcp.show()
        elif type == Source.SERIAL:
            dlg.xml.table_serial.show_all()
            dlg.xml.table_tcp.hide()
        elif type == Source.RFC2217:
            dlg.xml.table_tcp.show()
            dlg.xml.table_serial.show()
            dlg.xml.combobox_serial.hide()
            dlg.xml.label_serial_device.hide()
        else:
            dlg.xml.table_serial.hide()
            dlg.xml.table_tcp.hide()

    def save_to_config(self, dlg, cfg):
        if self.have_source:
            iter = dlg.xml.combobox_source_type.get_active_iter()
            if iter is None:
                raise ValidationError(_("Please, select source"))
            type = self.liststore[iter][1]
            src = self.fields['src']

            def get_tcp_settings():
                src.hostname = dlg.xml.entry_host.get_text()
                if len(src.hostname) == 0:
                    raise ValidationError(_("Invalid hostname specified"))
                try:
                    src.port = int(dlg.xml.entry_port.get_text())
                except ValueError:
                    raise ValidationError(_("Invalid port specified"))

            def get_serial_settings():
                if self.serial_selector.devname is None:
                    raise ValidationError(_("Please, specify serial device"))
                src.serial_device = self.serial_selector.devname
                src.serial_baud = serial_speeds[dlg.xml.combobox_baudrate.get_active()]
                src.serial_bits = serial_bits[dlg.xml.combobox_bits.get_active()]
                src.serial_parity = serial_parity[dlg.xml.combobox_parity.get_active()]
                src.serial_stop_bits = serial_stops[dlg.xml.combobox_stops.get_active()]

            if type == Source.TCP:
                get_tcp_settings()
            elif type == Source.SERIAL:
                get_serial_settings()
            elif type == Source.RFC2217:
                get_tcp_settings()
                get_serial_settings()

            src.type = type
            cfg.set('src', str(self.fields['src']))

    @staticmethod
    def save_hook(cfg, dev):
        pass

class BindDevice(object):
    have_source = True

    def load_from_config(self, dlg, cfg):
        self.fields = {}
        if self.have_source:
            key = cfg.get_key('bind')
            src = Source('')
            if 0 != len(key):
                src = Source(cfg.exclusive('bind'))
            self.liststore = Gtk.ListStore(str, int)
            dlg.xml.combobox_source_type.set_model(self.liststore)
            dlg.xml.combobox_source_type.connect('changed', lambda w: self.on_type_combo_changed(w,dlg))

            sources = ((Source.TCP, _("TCP/IP")), (Source.SERIAL, _("Serial Port")), (Source.RFC2217, _("Serial port over TCP/IP (RFC2217)")))

            for (t, n) in sources:
                if hasattr(self, 'sources_allowed'):
                    if not t in self.sources_allowed:
                        continue
                iter = self.liststore.append()
                self.liststore.set(iter, 0, n, 1, t)
                if src.type == t:
                    dlg.xml.combobox_source_type.set_active_iter(iter)

            self.serial_selector = SerialSelector(dlg.xml.combobox_serial)

            for baud in serial_speeds:
                dlg.xml.combobox_baudrate.append_text('%d' % baud)
            dlg.xml.combobox_baudrate.set_active(0)
            dlg.xml.combobox_bits.set_active(0)
            dlg.xml.combobox_parity.set_active(0)
            dlg.xml.combobox_stops.set_active(0)

            if dlg.xml.combobox_source_type.get_active() == -1:
                dlg.xml.combobox_source_type.set_active(0)

            def set_tcp_settings():
                dlg.xml.entry_host.set_text(src.hostname)
                dlg.xml.entry_port.set_text(str(src.port))

            def set_serial_settings():
                try:
                    idx = serial_speeds.index(src.serial_baud)
                    dlg.xml.combobox_baudrate.set_active(idx)
                except ValueError:
                    pass
                try:
                    idx = serial_bits.index(src.serial_bits)
                    dlg.xml.combobox_bits.set_active(idx)
                except ValueError:
                    pass
                try:
                    idx = serial_parity.index(src.serial_parity)
                    dlg.xml.combobox_parity.set_active(idx)
                except ValueError:
                    pass
                try:
                    idx = serial_stops.index(src.serial_stop_bits)
                    dlg.xml.combobox_stops.set_active(idx)
                except ValueError:
                    pass

                self.serial_selector.set_devname(src.serial_device)

            if src.type == Source.TCP:
                set_tcp_settings()
            elif src.type == Source.SERIAL:
                set_serial_settings()
            elif src.type == Source.RFC2217:
                set_tcp_settings()
                set_serial_settings()
            self.fields['src'] = src
        else:
            dlg.xml.table_source_type.hide()

    def on_type_combo_changed(self, box, dlg):
        type = self.liststore[box.get_active_iter()][1]

        if type == Source.TCP:
            dlg.xml.table_serial.hide()
            dlg.xml.table_tcp.show()
        elif type == Source.SERIAL:
            dlg.xml.table_serial.show_all()
            dlg.xml.table_tcp.hide()
        elif type == Source.RFC2217:
            dlg.xml.table_tcp.show()
            dlg.xml.table_serial.show()
            dlg.xml.combobox_serial.hide()
            dlg.xml.label_serial_device.hide()
        else:
            dlg.xml.table_serial.hide()
            dlg.xml.table_tcp.hide()

    def save_to_config(self, dlg, cfg):
        if self.have_source:
            iter = dlg.xml.combobox_source_type.get_active_iter()
            if iter is None:
                raise ValidationError(_("Please, select source"))
            type = self.liststore[iter][1]
            src = self.fields['src']

            def get_tcp_settings():
                src.hostname = dlg.xml.entry_host.get_text()
                if len(src.hostname) == 0:
                    raise ValidationError(_("Invalid hostname specified"))
                try:
                    src.port = int(dlg.xml.entry_port.get_text())
                except ValueError:
                    raise ValidationError(_("Invalid port specified"))

            def get_serial_settings():
                if self.serial_selector.devname is None:
                    raise ValidationError(_("Please, specify serial device"))
                src.serial_device = self.serial_selector.devname
                src.serial_baud = serial_speeds[dlg.xml.combobox_baudrate.get_active()]
                src.serial_bits = serial_bits[dlg.xml.combobox_bits.get_active()]
                src.serial_parity = serial_parity[dlg.xml.combobox_parity.get_active()]
                src.serial_stop_bits = serial_stops[dlg.xml.combobox_stops.get_active()]

            if type == Source.TCP:
                get_tcp_settings()
            elif type == Source.SERIAL:
                get_serial_settings()
            elif type == Source.RFC2217:
                get_tcp_settings()
                get_serial_settings()

            src.type = type
            cfg.set('bind', str(self.fields['src']))

    @staticmethod
    def save_hook(cfg, dev):
        pass



class AmasterDevice(BaseDevice):
    name = 'amaster'
    pretty_name = _('AeroMaster')
    
        
class ADIS16365Device(BaseDevice):
        name='adis16365'
        pretty_name = _('Adis16365')
        
        def load_from_config(self, dlg, cfg):
                super(ADIS16365Device, self).load_from_config(dlg, cfg)
                correction = cfg.exclusive('correction', '0')
                try:
                        correction = int(correction)
                except:
                        correction = 0
                dlg.xml.correction_switch_on_off.set_active(correction != 0)
                dlg.xml.v_box_adis16365.show()
                
        def save_to_config(self, dlg, cfg):
                if dlg.xml.correction_switch_on_off.get_active():
                        cfg.set('correction', 1)
                else:
                        cfg.set('correction', 0)
                super(ADIS16365Device, self).save_to_config(dlg, cfg)


class FEDevice(BindDevice):
    name = 'fe'
    pretty_name = _('On-Board Server')
    sources_allowed = (Source.TCP,)


class JPSDevice(BaseDevice):
    name = 'jps'
    pretty_name = _('Javad/Topcon receiver')

    def load_from_config(self, dlg, cfg):
        super(JPSDevice, self).load_from_config(dlg, cfg)
        initseq = '\n'.join(i.value for i in cfg.get_key('init'))
        dlg.xml.textview_jps.get_buffer().set_text(initseq)
        dlg.xml.table_jps.show()

    def save_to_config(self, dlg, cfg):
        buf = dlg.xml.textview_jps.get_buffer()
        initseq = [i for i in buf.get_text(
            buf.get_start_iter(), buf.get_end_iter(), True).split('\n') if i]
        cfg.remove('init')
        cfg.set_list('init', initseq)
        super(JPSDevice, self).save_to_config(dlg, cfg)


class RS500Device(BaseDevice):
    name = 'rs50x'
    pretty_name = _('Spectrometer RSx')

class ParsekDevice(BaseDevice):
    name = 'parsek-adc'
    pretty_name = _('Spectrometer Parsek')
    def load_from_config(self, dlg, cfg):
        super(ParsekDevice, self).load_from_config(dlg, cfg)
        chans = cfg.exclusive('chans', '4')
        try:
            chans = int(chans)
        except:
            chans = 4
        dlg.xml.entry_parsek_chans.set_text(_('%d') % chans)
        limit1 = cfg.exclusive('limit1', '20')
        try:
            limit1 = int(limit1)
        except:
            limit1 = 20
        dlg.xml.entry_parsek_limit1.set_text(_('%d') % limit1)
        limit2 = cfg.exclusive('limit2', '20')
        try:
            limit2 = int(limit2)
        except:
            limit2 = 20
        dlg.xml.entry_parsek_limit2.set_text(_('%d') % limit2)
        limit3 = cfg.exclusive('limit3', '20')
        try:
            limit3 = int(limit3)
        except:
            limit3 = 20
        dlg.xml.entry_parsek_limit3.set_text(_('%d') % limit3)
        limit4 = cfg.exclusive('limit4', '20')
        try:
            limit4 = int(limit4)
        except:
            limit4 = 20
        dlg.xml.entry_parsek_limit4.set_text(_('%d') % limit4)
        dlg.xml.table_parsek.show()

    def save_to_config(self, dlg, cfg):
        try: 
            chans = int(dlg.xml.entry_parsek_chans.get_text())
        except:
            chans = 1
        if (chans != 1) and (chans != 4):
            chans = 1
        cfg.set('chans',chans)
        try: 
            limit = int(dlg.xml.entry_parsek_limit1.get_text())
        except:
            limit = 25
        if (limit < 0) or (limit > 127):
            limit = 25
        cfg.set('limit1',limit)
        try: 
            limit = int(dlg.xml.entry_parsek_limit2.get_text())
        except:
            limit = 25
        if (limit < 0) or (limit > 127):
            limit = 25
        cfg.set('limit2',limit)
        try: 
            limit = int(dlg.xml.entry_parsek_limit3.get_text())
        except:
            limit = 25
        if (limit < 0) or (limit > 127):
            limit = 25
        cfg.set('limit3',limit)
        try: 
            limit = int(dlg.xml.entry_parsek_limit4.get_text())
        except:
            limit = 25
        if (limit < 0) or (limit > 127):
            limit = 25
        cfg.set('limit4',limit)
        super(ParsekDevice, self).save_to_config(dlg, cfg)


class GRS410Device(BaseDevice):
    name = 'grs410'
    pretty_name = _('Spectrometer GRS410')

    def load_from_config(self, dlg, cfg):
        super(GRS410Device, self).load_from_config(dlg, cfg)
        xtaloff = cfg.exclusive('xtaloff1', '0')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_1.set_active(xtaloff)
        xtaloff = cfg.exclusive('xtaloff2', '0')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_2.set_active(xtaloff)
        xtaloff = cfg.exclusive('xtaloff3', '0')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_3.set_active(xtaloff)
        xtaloff = cfg.exclusive('xtaloff4', '0')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_4.set_active(xtaloff)
        xtaloff = cfg.exclusive('xtaloff5', '1')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_5.set_active(xtaloff)
        xtaloff = cfg.exclusive('xtaloff6', '1')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_6.set_active(xtaloff)
        xtaloff = cfg.exclusive('xtaloff7', '1')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_7.set_active(xtaloff)
        xtaloff = cfg.exclusive('xtaloff8', '1')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_8.set_active(xtaloff)
        xtaloff = cfg.exclusive('xtaloff9', '1')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_9.set_active(xtaloff)
        xtaloff = cfg.exclusive('xtaloff10', '1')
        try:
            xtaloff = int(xtaloff)
        except:
            xtaloff = 0
        dlg.xml.grs_combobox_10.set_active(xtaloff)

        dlg.xml.table_grs.show()

    def save_to_config(self, dlg, cfg):
        cfg.set('xtaloff1', dlg.xml.grs_combobox_1.get_active())
        cfg.set('xtaloff2', dlg.xml.grs_combobox_2.get_active())
        cfg.set('xtaloff3', dlg.xml.grs_combobox_3.get_active())
        cfg.set('xtaloff4', dlg.xml.grs_combobox_4.get_active())
        cfg.set('xtaloff5', dlg.xml.grs_combobox_5.get_active())
        cfg.set('xtaloff6', dlg.xml.grs_combobox_6.get_active())
        cfg.set('xtaloff7', dlg.xml.grs_combobox_7.get_active())
        cfg.set('xtaloff8', dlg.xml.grs_combobox_8.get_active())
        cfg.set('xtaloff9', dlg.xml.grs_combobox_9.get_active())
        cfg.set('xtaloff10', dlg.xml.grs_combobox_10.get_active())
        super(GRS410Device, self).save_to_config(dlg, cfg)

class GSA2000Device(BaseDevice):
    name = 'gsa2000'
    pretty_name = _('Spectrometer GSA2000')

    def load_from_config(self, dlg, cfg):
        super(GSA2000Device, self).load_from_config(dlg, cfg)
        xtal = cfg.exclusive('xtal', '0')
        try:
            xtal = int(xtal)
        except:
            xtal = 0
        dlg.xml.gsa_combobox_xtal.set_active(xtal)
        light = cfg.exclusive('light', '0')
        try:
            light = int(light)
        except:
            light = 0
        dlg.xml.gsa_combobox_light.set_active(light)
        nostab = cfg.exclusive('nostab','0')
        try:
            nostab = int(nostab)
        except:
            nostab = 0
        if nostab:
            dlg.xml.gsa_checkbutton_stab.set_active(0)
        else:
            dlg.xml.gsa_checkbutton_stab.set_active(1)

        dlg.xml.table_gsa.show()

    def save_to_config(self, dlg, cfg):
        cfg.set('xtal', dlg.xml.gsa_combobox_xtal.get_active())
        cfg.set('light', dlg.xml.gsa_combobox_light.get_active())
        if dlg.xml.gsa_checkbutton_stab.get_active():
            cfg.set('nostab', 0)
        else:
            cfg.set('nostab', 1)
        super(GSA2000Device, self).save_to_config(dlg, cfg)


class NovatelDevice(BaseDevice):
    name = 'novatel'
    pretty_name = _('Novatel Receiver')

    def load_from_config(self, dlg, cfg):
        super(NovatelDevice, self).load_from_config(dlg, cfg)
        initseq = '\n'.join(i.value for i in cfg.get_key('init'))
        dlg.xml.textview_novatel.get_buffer().set_text(initseq)
        dlg.xml.table_novatel.show()

    def save_to_config(self, dlg, cfg):
        buf = dlg.xml.textview_novatel.get_buffer()
        initseq = [i for i in buf.get_text(
            buf.get_start_iter(), buf.get_end_iter(), True).split('\n') if i]
        cfg.remove('init')
        cfg.set_list('init', initseq)
        super(NovatelDevice, self).save_to_config(dlg, cfg)


class TvisorDevice(BaseDevice):
    name = 'tvisor'
    pretty_name = _('Teplovisor')
    sources_allowed = (Source.TCP,)

    @staticmethod
    def save_hook(cfg, dev):
        BaseDevice.save_hook(cfg, dev)
##        for i in cfg.children:
##            if i.name == 'device' and \
##                i.value == 'jps':
##                i.exclusive('ralt_variable', 'tvisor::RA')

class TvNewDevice(TvisorDevice):
    name ='tvnew'
    pretty_name = _('Teplovisor 2009')

    def load_from_config(self, dlg, cfg):
        super(TvNewDevice, self).load_from_config(dlg, cfg)
        direction = cfg.exclusive('direction', '-1')
        try:
            direction = int(direction)
        except:
            direction = 1
        dlg.xml.checkbutton_motor_direction.set_active(direction != -1)
        dlg.xml.vbox_tvnew.show()

    def save_to_config(self, dlg, cfg):
        if dlg.xml.checkbutton_motor_direction.get_active():
            cfg.set('direction', 1)
        else:
            cfg.set('direction', -1)
        super(TvNewDevice, self).save_to_config(dlg, cfg)

class ArrowDevice(BaseDevice):
    name = 'arrow'
    pretty_name = _('Arrow')

    def load_from_config(self, dlg, cfg):
        super(ArrowDevice, self).load_from_config(dlg, cfg)
        arrow_mode = cfg.exclusive('type', '0')
        try:
            arrow_mode = int(arrow_mode)
        except:
            arrow_mode = 0

        arrow_mode = min(max(arrow_mode, 0), 2)

        dlg.xml.combobox_arrow_type.append_text(_('Classic'))
        dlg.xml.combobox_arrow_type.append_text(_('Tvisor'))
        dlg.xml.combobox_arrow_type.append_text(_('Modern'))
        dlg.xml.combobox_arrow_type.set_active(arrow_mode)

        dlg.xml.table_arrow.show()

    def save_to_config(self, dlg, cfg):
        cfg.set('type', dlg.xml.combobox_arrow_type.get_active())
        super(ArrowDevice, self).save_to_config(dlg, cfg)


class HDipRawDevice(BaseDevice):
    name = 'hdip-raw'
    pretty_name = _('HDip Raw data stream')


class EM4HDevice(BaseDevice):
    name = 'em4h'
    pretty_name = _('EM4H')

    def load_from_config(self, dlg, cfg):
        super(EM4HDevice, self).load_from_config(dlg, cfg)
        em4h_mode = cfg.exclusive('aircraft', '0')
        use_ra_em4h = cfg.exclusive('use_ra_em4h', '0')
        try:
            em4h_mode = int(em4h_mode)
            use_ra_em4h = int(use_ra_em4h)
        except:
            em4h_mode = 0
            use_ra_em4h = 0

        em4h_mode = min(max(em4h_mode, 0), 3)

        dlg.xml.combobox_aircraft_type.append_text(_('An-2'))
        dlg.xml.combobox_aircraft_type.append_text(_('An-3'))
        dlg.xml.combobox_aircraft_type.append_text(_('Mi-8'))
        dlg.xml.combobox_aircraft_type.append_text(_('As350'))
        dlg.xml.combobox_aircraft_type.set_active(em4h_mode)

        dlg.xml.checkbutton_ra_em4h.set_active(use_ra_em4h != 0)
        dlg.xml.table_em4h.show()

    def save_to_config(self, dlg, cfg):
        if dlg.xml.checkbutton_ra_em4h.get_active():
            cfg.set('use_ra_em4h', '1')
        else:
            cfg.set('use_ra_em4h', '0')
        cfg.set('aircraft', dlg.xml.combobox_aircraft_type.get_active())
        super(EM4HDevice, self).save_to_config(dlg, cfg)


class KolesoDevice(BaseDevice):
    name = 'equator'
    pretty_name = _('Equator')

    def load_from_config(self, dlg, cfg):
        super(KolesoDevice, self).load_from_config(dlg, cfg)

        gps_port = cfg.exclusive('gps_port', '9999')
        use_ra_koleso = cfg.exclusive('use_ra_koleso', '1')
        try:
            gps_port = int(gps_port)
            use_ra_koleso = int(use_ra_koleso)
        except:
            gps_port = 9999
            use_ra_koleso = 1
        dlg.xml.spinbutton_koleso_gps_port.set_value(gps_port)
        dlg.xml.checkbutton_ra_koleso.set_active(use_ra_koleso != 0)
        dlg.xml.table_koleso.show()

    def save_to_config(self, dlg, cfg):
        gps_port = dlg.xml.spinbutton_koleso_gps_port.get_value_as_int()
        cfg.set('gps_port', gps_port)
        if dlg.xml.checkbutton_ra_koleso.get_active():
            cfg.set('use_ra_koleso', '1')
        else:
            cfg.set('use_ra_koleso', '0')
        super(KolesoDevice, self).save_to_config(dlg, cfg)


class GTMagDevice(BaseDevice):
    name = 'gtmag'
    pretty_name = _('GT-MAG')

    available_freqs = (1, 5, 10, 20, 50, 100, 200, 500, 1000, 2000)
    available_cns = (1, 2, 4)

    def on_button_mcdir_clicked(self, w):
        label_mcdir = w.get_label()
        cfilter = Gtk.FileFilter()
        cfilter.add_pattern("*.mgc")
        cfilter.set_name("*.mgc")
        chooser = file_chooser(_('Choose deviation parameters'),
                               Gtk.FileChooserAction.OPEN)
        chooser.set_icon_name('gtk-directory')
        chooser.add_filter(cfilter)
        chooser.set_filename(label_mcdir)
        while True:
            response = chooser.run()
            if response != Gtk.ResponseType.OK:
                break

            label_mcdir = chooser.get_filename()
            if not os.access(label_mcdir, os.R_OK):
                dlg = message_dialog(chooser, Gtk.MessageType.WARNING, Gtk.ButtonsType.CLOSE,
                                        _("Selected file isn't readable, please choose another one"))
                dlg.run()
                dlg.destroy()
            else:
                w.set_label(label_mcdir)
                break
        chooser.destroy()

    def load_from_config(self, dlg, cfg):
        super(GTMagDevice, self).load_from_config(dlg, cfg)
        freq_out = cfg.exclusive('freq_out', '500')
        channels_number = cfg.exclusive('channels_number', '1')
        use_ra = cfg.exclusive('use_ra', '1')
        ra_off = cfg.exclusive('ra_off', '0')
        ra_sca = cfg.exclusive('ra_sca', '1')
        mc_path = cfg.exclusive('mc_path', '~/.bort/magcom.mgc')
        mc_path = os.path.expanduser(mc_path)
        ugnd = cfg.exclusive('ugnd',0)
        scale = cfg.exclusive('scale',100)
        dx = cfg.exclusive('dx',0)
        dy = cfg.exclusive('dy',0)
        dz = cfg.exclusive('dz',0)
        kx = cfg.exclusive('kx',1)
        ky = cfg.exclusive('ky',1)
        kz = cfg.exclusive('kz',1)
        kyx = cfg.exclusive('kyx',0)
        kzx = cfg.exclusive('kzx',0)
        kxy = cfg.exclusive('kxy',0)
        kzy = cfg.exclusive('kzy',0)
        kxz = cfg.exclusive('kxz',0)
        kyz = cfg.exclusive('kyz',0)
        use_ugnd = cfg.exclusive('use_ugnd', '1')
#        mc_path = os.path.join(mc_path, '')
        try:
            freq_out = int(freq_out)
        except:
            freq_out = 500
        try:
            channels_number = int(channels_number)
        except:
            channels_number = 1
        try:
            use_ra = int(use_ra)
        except:
            use_ra = 1
        try:
            ra_off = float(ra_off)
        except:
            ra_off = 0
        try:
            ra_sca = float(ra_sca)
        except:
            ra_sca = 1
        try:
            use_ugnd = int(use_ugnd)
        except:
            use_ugnd = 1
        try:
            ugnd = float(ugnd)
        except:
            ugnd = 0
        try:
            scale = float(scale)
        except:
            scale = 100
        try:
            dx = float(dx)
        except:
            dx = 0
        try:
            dy = float(dy)
        except:
            dy = 0
        try:
            dz = float(dz)
        except:
            dz = 0
        try:
            kx = float(kx)
        except:
            kx = 0
        try:
            ky = float(ky)
        except:
            ky = 0
        try:
            kz = float(kz)
        except:
            kz = 0
        try:
            kyx = float(kyx)
        except:
            kyx = 0
        try:
            kzx = float(kzx)
        except:
            kzx = 0
        try:
            kxy = float(kxy)
        except:
            kxy = 0
        try:
            kzy = float(kzy)
        except:
            kzy = 0
        try:
            kxz = float(kxz)
        except:
            kxz = 0
        try:
            kyz = float(kyz)
        except:
            kyz = 0
        idx = 0
        for freq in self.available_freqs:
            dlg.xml.combobox_gtmag_freq.append_text(_('%d Hz') % freq)
            if freq == freq_out:
                dlg.xml.combobox_gtmag_freq.set_active(idx)
            idx += 1
        idx = 0
        for cn in self.available_cns:
            dlg.xml.combobox_gtmag_channels.append_text(_('%d') % cn)
            if cn == channels_number:
                dlg.xml.combobox_gtmag_channels.set_active(idx)
            idx += 1
        dlg.xml.checkbutton_ra.set_active(use_ra != 0)
        dlg.xml.checkbutton_ugnd.set_active(use_ugnd == 0)
        dlg.xml.entry_gtmag_ra_scale.set_text(_('%f') % ra_sca)
        dlg.xml.entry_gtmag_ra_offset.set_text(_('%f') % ra_off)
        dlg.xml.button_mcdir.set_label(mc_path)
        dlg.xml.entry_ugnd.set_text(_('%.3f') % ugnd)
        dlg.xml.entry_scale.set_text(_('%.3f') % scale)
        dlg.xml.entry_dx.set_text(_('%.3f') % dx)
        dlg.xml.entry_dy.set_text(_('%.3f') % dy)
        dlg.xml.entry_dz.set_text(_('%.3f') % dz)
        dlg.xml.entry_kx.set_text(_('%.3f') % kx)
        dlg.xml.entry_ky.set_text(_('%.3f') % ky)
        dlg.xml.entry_kz.set_text(_('%.3f') % kz)
        dlg.xml.entry_kyx.set_text(_('%.3f') % kyx)
        dlg.xml.entry_kzx.set_text(_('%.3f') % kzx)
        dlg.xml.entry_kxy.set_text(_('%.3f') % kxy)
        dlg.xml.entry_kzy.set_text(_('%.3f') % kzy)
        dlg.xml.entry_kxz.set_text(_('%.3f') % kxz)
        dlg.xml.entry_kyz.set_text(_('%.3f') % kyz)
        dlg.xml.table_fluxgate.show()
        dlg.xml.table_gtmag.show()

    def save_except(self, wstr):
        dlgw = message_dialog(None, Gtk.MessageType.WARNING, Gtk.ButtonsType.CLOSE,
                                    _("Couldn't read %s!\n Default value will be saved!" % wstr))
        dlgw.run()
        dlgw.destroy()

    def save_to_config(self, dlg, cfg):
        idx = dlg.xml.combobox_gtmag_freq.get_active()
        if idx  >= 0:
            freq_out = self.available_freqs[idx]
            cfg.set('freq_out', freq_out)
        idx = dlg.xml.combobox_gtmag_channels.get_active()
        if idx  >= 0:
            channels_number = self.available_cns[idx]
            cfg.set('channels_number', channels_number)
        if dlg.xml.checkbutton_ra.get_active():
            cfg.set('use_ra', '1')
        else:
            cfg.set('use_ra', '0')
        try: 
            ra_sca = float(dlg.xml.entry_gtmag_ra_scale.get_text())
        except:
            ra_sca = 1
            self.save_except(dlg.xml.label_gtmag_ra_scale.get_text())
        cfg.set('ra_sca',ra_sca);       
        try: 
            ra_off = float(dlg.xml.entry_gtmag_ra_offset.get_text())
        except:
            ra_off = 0
            self.save_except(dlg.xml.label_gtmag_ra_offset.get_text())
        cfg.set('ra_off',ra_off);       
        if dlg.xml.checkbutton_ugnd.get_active():
            cfg.set('use_ugnd', '0')
        else:
            cfg.set('use_ugnd', '1')
        mc_path = dlg.xml.button_mcdir.get_label()
        cfg.set('mc_path',mc_path)
        try: 
            ugnd = float(dlg.xml.entry_ugnd.get_text())
        except:
            ugnd = 0
            self.save_except(dlg.xml.label_ugnd.get_text())
        cfg.set('ugnd',ugnd);
        try: 
            scale = float(dlg.xml.entry_scale.get_text())
        except:
            scale = 100
            self.save_except(dlg.xml.label_scale.get_text())
        cfg.set('scale',scale);
        try: 
            dx = float(dlg.xml.entry_dx.get_text())
        except:
            dx = 0
            self.save_except(dlg.xml.label_dx.get_text())
        cfg.set('dx',dx);
        try: 
            dy = float(dlg.xml.entry_dy.get_text())
        except:
            dy = 0
            self.save_except(dlg.xml.label_dy.get_text())
        cfg.set('dy',dy);
        try: 
            dz = float(dlg.xml.entry_dz.get_text())
        except:
            dz = 0
            self.save_except(dlg.xml.label_dz.get_text())
        cfg.set('dz',dz);
        try: 
            kx = float(dlg.xml.entry_kx.get_text())
        except:
            kx = 1
            self.save_except(dlg.xml.label_kx.get_text())
        cfg.set('kx',kx);
        try: 
            ky = float(dlg.xml.entry_ky.get_text())
        except:
            ky = 1
            self.save_except(dlg.xml.label_ky.get_text())
        cfg.set('ky',ky);
        try:
            kz = float(dlg.xml.entry_kz.get_text())
        except:
            kz = 1
            self.save_except(dlg.xml.label_kz.get_text())
        cfg.set('kz',kz);
        try:
            kyx = float(dlg.xml.entry_kyx.get_text())
        except:
            kyx = 0
            self.save_except(dlg.xml.label_kyx.get_text())
        cfg.set('kyx',kyx);
        try:
            kzx = float(dlg.xml.entry_kzx.get_text())
        except:
            kzx = 0
            self.save_except(dlg.xml.label_kzx.get_text())
        cfg.set('kzx',kzx);
        try:
            kxy = float(dlg.xml.entry_kxy.get_text())
        except:
            kxy = 0
            self.save_except(dlg.xml.label_kxy.get_text())
        cfg.set('kxy',kxy);
        try:
            kzy = float(dlg.xml.entry_kzy.get_text())
        except:
            kzy = 0
            self.save_except(dlg.xml.label_kzy.get_text())
        cfg.set('kzy',kzy);
        try:
            kxz = float(dlg.xml.entry_kxz.get_text())
        except:
            kxz = 0
            self.save_except(dlg.xml.label_kxz.get_text())
        cfg.set('kxz',kxz);
        try:
            kyz = float(dlg.xml.entry_kyz.get_text())
        except:
            kyz = 0
            self.save_except(dlg.xml.label_kyz.get_text())
        cfg.set('kyz',kyz);
        super(GTMagDevice, self).save_to_config(dlg, cfg)


class GtADCDevice(BaseDevice):
    name = 'gtadc'
    pretty_name = _('GeoTechnologies serial ADC device')

    def load_from_config(self, dlg, cfg):
        super(GtADCDevice, self).load_from_config(dlg, cfg)
        initseq = '\n'.join(i.value for i in cfg.get_key('assign'))
        dlg.xml.textview_adc.get_buffer().set_text(initseq)
        dlg.xml.table_adc.show()

    def save_to_config(self, dlg, cfg):
        buf = dlg.xml.textview_adc.get_buffer()
        initseq = [i for i in buf.get_text(
            buf.get_start_iter(), buf.get_end_iter(), True).split('\n') if i]
        cfg.remove('assign')
        cfg.set_list('assign', initseq)
        super(GtADCDevice, self).save_to_config(dlg, cfg)


class D5000ADCDevice(BaseDevice):
    name = 'd5000adc'
    pretty_name = _('DGH serial ADC device')

    def load_from_config(self, dlg, cfg):
        super(D5000ADCDevice, self).load_from_config(dlg, cfg)
        initseq = '\n'.join(i.value for i in cfg.get_key('assign'))
        dlg.xml.textview_adc.get_buffer().set_text(initseq)
        dlg.xml.table_adc.show()

    def save_to_config(self, dlg, cfg):
        buf = dlg.xml.textview_adc.get_buffer()
        initseq = [i for i in buf.get_text(
            buf.get_start_iter(), buf.get_end_iter(), True).split('\n') if i]
        cfg.remove('assign')
        cfg.set_list('assign', initseq)
        super(D5000ADCDevice, self).save_to_config(dlg, cfg)


class E502Device(BaseDevice):
    name = 'e502'
    pretty_name = _('L-Card E502 ADC device')

    def load_from_config(self, dlg, cfg):
        super(E502Device, self).load_from_config(dlg, cfg)
        initseq = '\n'.join(i.value for i in cfg.get_key('assign'))
        dlg.xml.textview_adc.get_buffer().set_text(initseq)
        dlg.xml.table_adc.show()

    def save_to_config(self, dlg, cfg):
        buf = dlg.xml.textview_adc.get_buffer()
        initseq = [i for i in buf.get_text(
            buf.get_start_iter(), buf.get_end_iter(), True).split('\n') if i]
        cfg.remove('assign')
        cfg.set_list('assign', initseq)
        super(E502Device, self).save_to_config(dlg, cfg)

class SP4Device(BaseDevice):
    name = 'sp4'
    pretty_name = _('SP-4 IMU device')

class GeoscanDevice(BaseDevice):
    name = 'geoscan'
    pretty_name = _('Geoscan Magnetometer')

class FFRADevice(BaseDevice):
    name = 'ffra'
    pretty_name = _('Free Flight Radar Altimeter')

    def load_from_config(self, dlg, cfg):
        super(FFRADevice, self).load_from_config(dlg, cfg)
        use_ra_ffra = cfg.exclusive('use_ra_ffra', '1')
        try:
            use_ra_ffra = int(use_ra_ffra)
        except:
            use_ra_ffra = 1
        dlg.xml.checkbutton_ra_ffra.set_active(use_ra_ffra != 0)
        dlg.xml.table_ffra.show()

    def save_to_config(self, dlg, cfg):
        if dlg.xml.checkbutton_ra_ffra.get_active():
            cfg.set('use_ra_ffra', '1')
        else:
            cfg.set('use_ra_ffra', '0')
        super(FFRADevice, self).save_to_config(dlg, cfg)

class SMRADevice(BaseDevice):
    name = 'smra'
    pretty_name = _('Smartmicro Radar Altimeter')

    def load_from_config(self, dlg, cfg):
        super(SMRADevice, self).load_from_config(dlg, cfg)
        use_ra_smra = cfg.exclusive('use_ra_smra', '1')
        try:
            use_ra_smra = int(use_ra_smra)
        except:
            use_ra_smra = 1
        dlg.xml.checkbutton_ra_smra.set_active(use_ra_smra != 0)
        dlg.xml.table_smra.show()

    def save_to_config(self, dlg, cfg):
        if dlg.xml.checkbutton_ra_smra.get_active():
            cfg.set('use_ra_smra', '1')
        else:
            cfg.set('use_ra_smra', '0')
        super(SMRADevice, self).save_to_config(dlg, cfg)


class MP719Device(BaseDevice):
    name = 'mp719'
    pretty_name = _('Multichannel Thermometr MP719')
    
    def load_from_config(self, dlg, cfg):
        super(MP719Device, self).load_from_config(dlg, cfg)
        num_of_sens = cfg.exclusive ('num_of_sens', '1')
        try:
            num_of_sens = int(num_of_sens)
        except:
            num_of_sens = 1
        dlg.xml.entry_mp719_nums.set_text(_('%d') % num_of_sens)
        dlg.xml.table_mp719.show()
        
    def save_to_config(self, dlg, cfg):
        try:
            num_of_sens = int(dlg.xml.entry_mp719_nums.get_text())
        except:
            num_of_sens = 1
        if (num_of_sens < 1) or (num_of_sens > 20):
            num_of_sens = 1
        cfg.set('num_of_sens', num_of_sens)
        super(MP719Device, self).save_to_config(dlg, cfg)
 

devices = {
    'amaster':  AmasterDevice,
    'fe':       FEDevice,
    'jps':      JPSDevice,
    'novatel':  NovatelDevice,
    'arrow':    ArrowDevice,
#    'hdip-raw': HDipRawDevice,
    'em4h':     EM4HDevice,
    'gtmag':    GTMagDevice,
    'geoscan':  GeoscanDevice,
    'rs50x':    RS500Device,
    'grs410':   GRS410Device,
    'gsa2000':  GSA2000Device,
    'parsek-adc': ParsekDevice,
    'gtadc':    GtADCDevice,
    'd5000adc': D5000ADCDevice,
    'e502':     E502Device,
    'ffra':     FFRADevice,
    'smra':     SMRADevice,
    'equator':  KolesoDevice,
    'sp4':      SP4Device,
    'tvisor':   TvisorDevice,
    'tvnew':    TvNewDevice,
    'mp719':    MP719Device,
    'adis16365': ADIS16365Device,
}

class ConfigureDialog:
    def __init__(self, device):
        self.device = device
        self.model = devices[device.value]()
        self.xml = Glade('bortcfg.ui', 'configure_dialog')
        self.xml.signal_autoconnect(self.model)
        self.model.load_from_config(self, device)

    def run(self):
        while self.xml.configure_dialog.run() == Gtk.ResponseType.OK:
            try:
                self.model.save_to_config(self, self.device)
            except ValidationError as e:
                dlg = message_dialog(self.xml.configure_dialog, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE,
                                        str(e))
                dlg.run()
                dlg.destroy()
                continue
            self.xml.configure_dialog.destroy()
            return True
        self.xml.configure_dialog.destroy()
        return False

class BortConfigWindow:
    def __init__(self, proxy = None):
        self.xml = Glade('bortcfg.ui', 'bortcfg_window')
        self.window = self.xml.bortcfg_window
        self.button_datadir = self.xml.button_datadir
        self.label_datadir = self.xml.label_datadir
        self.treeview = self.xml.treeview
        self.xml.signal_autoconnect(self)
        self.liststore = Gtk.ListStore(str, object)
        self.treeview.set_model(self.liststore)
        self.treeview.connect('row-activated', self.on_treeview_row_activated)

        # column for holiday names
        renderer = Gtk.CellRendererText()
        renderer.set_property("xalign", 0.0)

        column = Gtk.TreeViewColumn(_("Device"), renderer, markup = COLUMN_DEVICE)
        #column = gtk_tree_view_get_column(GTK_TREE_VIEW(treeview), col_offset - 1);
        #column.set_clickable(True)
        self.treeview.append_column(column)

        self.selection = self.treeview.get_selection()
        self.selection.set_mode(Gtk.SelectionMode.SINGLE)
        self.read_config()

        self.client = None
        if proxy == None:
            proxy = bortd.BortProxy()

        proxy.connect('event-list', self.on_event_list)
        proxy.connect('event-set', self.on_event_set)
        proxy.connect('connected', self.on_connected)
        proxy.connect('disconnected', self.on_disconnected)
        proxy.start()

        if proxy.client:
            self.on_connected(proxy, proxy.client)
        else:
            self.on_disconnected(proxy)

        self.window.resize(400, 400)

    def on_event_list(self, proxy, client):
        self.demo_mode = client['sys::demo_mode']
        client.notify(self.demo_mode)

    def on_event_set(self, proxy, client, ids):
        if self.demo_mode.id in ids:
            demo_mode = self.demo_mode.get()
            if demo_mode:
                state = _('Bord daemon is running in demo mode')
            else:
                state = proxy.state
            self.xml.label_state.set_markup('<i>%s</i>' % state)

    def on_connected(self, proxy, client):
        self.xml.button_stop.set_sensitive(True)
        self.xml.label_state.set_markup('<i>%s</i>' % proxy.state)
        self.xml.button_restart.show()
        self.xml.button_start.hide()
        self.client = client

    def on_disconnected(self, proxy):
        self.xml.button_stop.set_sensitive(False)
        self.xml.button_restart.hide()
        self.xml.button_start.show()
        self.xml.label_state.set_markup('<i>%s</i>' % proxy.state)
        self.client = None

##
##      control stuff here
##
##

    def save_question(self):
        if self.xml.button_save.get_sensitive():
            dlg = message_dialog(None, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO)
            dlg.set_markup(_("Would you like to save config?"))
            try:
                resp = dlg.run()
            finally:
                dlg.destroy()
            if resp == Gtk.ResponseType.YES:
                self.on_button_save_clicked(self.xml.button_save)
            elif resp != Gtk.ResponseType.NO:
                return False
        return True

    def on_button_start_clicked(self, button):
        if self.save_question():
            StartDaemon()

    def on_button_stop_clicked(self, button):
        dlg = message_dialog(None, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO)
        dlg.set_markup(_("Do you really want to <b>stop</b> deamon?"))

        try:
            resp = dlg.run()
        finally:
            dlg.destroy()
        if resp == Gtk.ResponseType.YES:
            self.client.stop()

    def on_button_restart_clicked(self, button):
        dlg = message_dialog(None, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO)
        dlg.set_markup(_("Do you really want to <b>restart</b> deamon?"))
##
##      if self.xml.button_save.get_sensitive():
##          dlg.format_secondary_markup('<i>Warning! config was not saved</i>')

        try:
            resp = dlg.run()
        finally:
            dlg.destroy()
        if resp == Gtk.ResponseType.YES and self.save_question():
            self.client.restart()

##
##      settings here
##
##
    def show(self):
        self.window.show()

    def setup_device(self, dev):
        configure_dlg = ConfigureDialog(dev)
        if configure_dlg.run():
            self.xml.button_save.set_sensitive(True)

    def on_treeview_row_activated(self, treeview, path, column):
        iter = self.liststore[path].iter
        dev = self.liststore[iter][COLUMN_PRIV]
        self.setup_device(dev)
        self.update_iter(dev, iter)

    def on_button_add_clicked(self, button):
        try:
            xml = Glade('bortcfg.ui', 'add_device_dlg')
            devs = sorted(devices.items(), key=lambda kv: kv[1].pretty_name)

            store = Gtk.ListStore(str, object)
            cell = Gtk.CellRendererText()

            xml.combo_dev.set_model(store)
            xml.combo_dev.pack_start(cell, True)
            xml.combo_dev.add_attribute(cell, 'text', 0)

            for (key, dev) in devs:
                iter = store.append()
                store.set(iter, 0, dev.pretty_name, 1, dev)

            def on_combo_dev_changed(w):
                xml.okbutton.set_sensitive(xml.combo_dev.get_active() != -1)

            xml.okbutton.set_sensitive(False)
            xml.signal_autoconnect(locals())
            resp = xml.add_device_dlg.run()

            if resp == Gtk.ResponseType.OK:
                dev = devs[xml.combo_dev.get_active()][1]
                cfg = bortrc.Config(name = 'device', value = dev.name)
                self.cfg.children.append(cfg)
                self.update_iter(cfg)
                self.xml.button_save.set_sensitive(True)
        finally:
            xml.add_device_dlg.destroy()

    def on_button_remove_clicked(self, button):
        self.remove()

    def on_button_props_clicked(self, button):
        store, iter = self.selection.get_selected()
        if not iter:
            return
        dev = store[iter][COLUMN_PRIV]
        self.setup_device(dev)
        self.update_iter(dev, iter)

    def remove(self):
        ## remove current
        store, iter = self.selection.get_selected()
        if not iter:
            return
        self.cfg.children.remove(self.liststore[iter][COLUMN_PRIV])
        self.liststore.remove(iter)
        self.xml.button_save.set_sensitive(True)

    def on_button_datadir_clicked(self, button):
        chooser = file_chooser(_('Choose directory'),
                               Gtk.FileChooserAction.SELECT_FOLDER)
        chooser.set_icon_name('gtk-directory')
        chooser.set_filename(self.label_datadir.get_text())
        while True:
            response = chooser.run()
            if response != Gtk.ResponseType.OK:
                break

            datadir = chooser.get_filename()
            datadir = os.path.join(datadir, '')

            if not os.access(datadir, os.W_OK | os.R_OK):
                dlg = message_dialog(chooser, Gtk.MessageType.WARNING, Gtk.ButtonsType.CLOSE,
                                        _("Selected directory isn't writeable, please choose another one"))
                dlg.run()
                dlg.destroy()
            else:
                self.label_datadir.set_text(datadir)
                self.xml.button_save.set_sensitive(True)
                break
        chooser.destroy()

    def on_button_save_clicked(self, button):
        self.cfg.set('sys::datadir', self.label_datadir.get_text())

        by_name = {}
        for i in self.cfg.get_key('device'):
            if i.value in by_name:
                by_name[i.value].append(i)
            else:
                by_name[i.value] = [i]
            if i.value in devices:
                devices[i.value].save_hook(self.cfg, i)
        if 'fe' not in by_name:
            dev = bortrc.Config('device', 'fe')
            self.cfg.children.append(dev)
        if 'fplan' not in by_name:
            dev = bortrc.Config('device', 'fplan')
            self.cfg.children.append(dev)

        bortrc.write_config(self.cfg)
        self.xml.button_save.set_sensitive(False)


    def update_iter(self, cfg, iter = None):
        try:
            dev = devices[cfg.value]
        except KeyError:
            return False

        if not iter:
            iter = self.liststore.append()

        def pretty_src(cfg):
            src = cfg.get_key('src')
            if 0!= len(src):    
                source = Source(src[0].value)
                return '%s' % str(source)
            else:
                src = cfg.get_key('bind')
                if 0!= len(src):    
                    source = Source(src[0].value)
                    return '%s' % str(source)
                else:
                    return _('No source selected')

        self.liststore.set(iter, COLUMN_DEVICE,
                        '<b>%s</b>\n<small><i>%s</i></small>' % (dev.pretty_name, pretty_src(cfg)),
                                        COLUMN_PRIV, cfg)
        return True

    def read_config(self):
        self.liststore.clear()

        try:
            self.cfg = bortrc.load_config()
        except:
            self.cfg = bortrc.Config()

        datadir = self.cfg.exclusive('sys::datadir', '~/data')
        datadir = os.path.expanduser(datadir)
        datadir = os.path.join(datadir, '')

        try:
            os.makedirs(datadir)
        except OSError:
            pass
        self.label_datadir.set_label(datadir)

        for i in self.cfg.get_key('device'):
            self.update_iter(i)


def which(what, fallback = None):
    for i in os.getenv('PATH').split(':'):
        path = os.path.join(i, what)
        if os.access(path, os.X_OK):
            return path
    return fallback


def StartDaemon(demo_mode = False):
    path = which('bortd')

    if not path:
        dlg = message_dialog(None, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK)
        dlg.set_markup("Error while trying to start daemon:")
        dlg.format_secondary_markup(_("Could not find <b>bortd</b> executable"))
        dlg.run()
        dlg.destroy()
        return

    args = ['bortd','-d']

    if demo_mode:
        args.append('-D')

    (p_r, p_w) = os.pipe()

    # bortd -d forks into background, so wait only for the parent process
    # and read whatever it reported, without waiting for EOF.
    try:
        proc = subprocess.Popen(args, executable=path,
                                stdin=subprocess.DEVNULL, stdout=p_w,
                                stderr=p_w, close_fds=True)
        status = proc.wait()
    except OSError as e:
        os.write(p_w, str(e).encode())
        status = 1
    finally:
        os.close(p_w)

    data = os.read(p_r, 4096).decode('utf-8', 'replace')
    os.close(p_r)

    if status:
        dlg = message_dialog(None, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK)
        dlg.set_markup(_("On-board daemon exited with error:"))
        dlg.format_secondary_text(data)
        dlg.run()
        dlg.destroy()
    else:
        return True


def SessionSave(client = None):
    if not client:
        try:
            client = bortd.BortClient()
        except OSError:
            dlg = message_dialog(None, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK)
            dlg.set_markup(_("On-board daemon not running, nothing to save"))
            try:
                resp = dlg.run()
            finally:
                dlg.destroy()
            return


    dlg = message_dialog(None, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO)
    dlg.set_markup(_("Would you like to save session"))

    try:
        resp = dlg.run()
    finally:
        dlg.destroy()

    if resp != Gtk.ResponseType.YES:
        return

    client.session_save()
    client.sync()
    session = client._session

    path = os.path.expanduser('~/.bort/client-session')
    with open(path, 'w', encoding='utf-8') as fp:
        fp.write('\n'.join(session) + '\n')

def start(path, argv):
    proc = subprocess.Popen(argv, executable=path,
                            stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            close_fds=True, start_new_session=True)
    return proc.pid

def SessionRestore(client = None):
    should_wait = False

    if not client:
        try:
            client = bortd.BortClient()
        except OSError:
            pass

    if not client and not StartDaemon():
        return

    tries = iter(range(10,0,-1))
    while not client and next(tries, 0):
        import time

        print('Waiting for bortd up...')
        time.sleep(2)

        try:
            client = bortd.BortClient()
            ## wait while clients will connect
            time.sleep(2)
        except OSError:
            continue

    if not client:
        print('On-board server is down')
        return

    client.session_save(False)
    client.sync()
    session = client._session

    path = os.path.expanduser('~/.bort/client-session')
    try:
        with open(path, 'r', encoding='utf-8') as fp:
            saved = fp.read().split('\n')
    except OSError:
        print('No saved session in %s' % path)
        return
    for i in saved:
        if not i or i in session:
            continue
        ## xxx
        session.append(i)
        sess = i.rsplit('-', 1)
        args = [sess[0], '--session', i]

        path = which(sess[0])

        if not path:
            print('Warning no path found for %s' % i)
            continue
        start(path, args)

if __name__ == "__main__":
    if 'save' in sys.argv[1:]:
        SessionSave()
    elif 'restore' in sys.argv[1:]:
        SessionRestore()
    else:
        window = BortConfigWindow()
        window.show()
        window.window.connect('destroy', Gtk.main_quit)
        Gtk.main()
