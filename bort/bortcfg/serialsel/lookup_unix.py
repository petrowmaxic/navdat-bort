from dev import SerialDevice

import os
import re

re_tty = re.compile('tty(S|USB|ACM)[0-9]+')

class SerialLookupUnix:
    def __init__(self):
        pass

    def lookup(self):
        try:
            items = os.listdir('/dev/')
        except OSError:
            return []
        items.sort()
        ret = []
        for i in items:
            if not re_tty.match(i):
                continue
            dev = SerialDevice('/dev/%s' % i)
            ret.append(dev)
        return ret
