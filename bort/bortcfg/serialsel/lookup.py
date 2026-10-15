import os
import os.path

try:
    from lookup_dbus import SerialLookupDBus as SerialLookupBase
except:
    from lookup_unix import SerialLookupUnix as SerialLookupBase

def readlinks(basedir):
    ret = {}
    abspath = lambda path: os.path.abspath( \
                    os.path.join(basedir, path))
    try:
        items = os.listdir(basedir)
    except OSError:
        return ret
    items.sort()
    items.reverse()
    for i in items:
        path = abspath(i)
        try:
            devname = os.readlink(path)
        except OSError:
            continue
        devname = abspath(devname)
        ret[devname] = path
    return ret


class SerialLookup(SerialLookupBase):
    def __init__(self):
        SerialLookupBase.__init__(self)

    def lookup(self):
        devices = SerialLookupBase.lookup(self)

        by_path = readlinks('/dev/serial/by-path')
        by_id = readlinks('/dev/serial/by-id')

        for dev in devices:
            dev.by_path = by_path.get(dev.devname)
            dev.by_id = by_id.get(dev.devname)

        return devices


if __name__ == "__main__":
    lookup = SerialLookup()
    for i in lookup.lookup():
        print i, i.by_id, i.by_path


