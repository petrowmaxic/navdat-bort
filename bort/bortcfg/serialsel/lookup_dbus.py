import dbus
import dbus.glib

from dev import SerialDevice

system_bus = dbus.SystemBus()
hal_manager = system_bus.get_object('org.freedesktop.Hal',
                                '/org/freedesktop/Hal/Manager')

class SerialLookupDBus:
    def __init__(self):
        pass

    def lookup(self):
        serial_udis = hal_manager.FindDeviceByCapability('serial',
                        dbus_interface='org.freedesktop.Hal.Manager')
        devices = []

        for udi in serial_udis:
            obj = dbus.Interface(system_bus.get_object('org.freedesktop.Hal', udi), 'org.freedesktop.Hal.Device')
            props = obj.GetAllProperties()
            device = props['serial.device']
            type = props['serial.type']
            product = props['info.product']
            devices.append(SerialDevice(device, '%s (%s)' % (product, type)))
        return devices
