import os.path

class SerialDevice:
    def __init__(self, devname, info=None, by_path=None, by_id=None):
        self.devname = devname
        self.info = info
        self.by_path = by_path
        self.by_id = by_id

    def pretty_name(self):
        if self.info:
            return '%s: %s' % (self.devname, self.info)
        return self.devname

    def __repr__(self):
        return 'SerialDevice("%s")' % self.pretty_name()

    def __eq__(self, a):
        if not isinstance(a, SerialDevice):
            return False
        return self.devname == a.devname and \
                self.by_path == a.by_path and \
                self.by_id == a.by_id
