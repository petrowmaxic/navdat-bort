"""Python implementation of Bortd FE protocol."""
import os
import socket
import struct


from i18n import _

DEFAULT_ADDR = '@/bortd/%s' % os.getenv('USER', 'nobody')

(CMD_OK,
 CMD_ERR,
 CMD_LIST,
 CMD_LIST_REPLY,
 CMD_GET,
 CMD_SET,
 CMD_NOTIFY,
 CMD_RMNOTIFY,
 CMD_CHANGE,
 CMD_SYS_INFO,
 CMD_SYS_INFO_REPLY,
 CMD_SET_SESSION_ID,
 CMD_SESSION_SAVE,
 CMD_SESSION_SAVE_REPLY,
 CMD_RESTART,
 CMD_STOP,
 CMD_EXIT_NOTIFY) = range(17)


"""Data types"""
T_UNSIGNED    	= 0x100
T_BAD 		= 0
T_CHAR  	= 1
T_UCHAR		= T_UNSIGNED | T_CHAR
T_SHORT		= 2
T_USHORT	= T_UNSIGNED | T_SHORT
T_LONG		= 4
T_ULONG		= T_UNSIGNED | T_LONG
T_LLONG		= 8
T_ULLONG	= T_UNSIGNED | T_LLONG
T_FLOAT		= 0x200 | 4
T_DOUBLE	= 0x200 | 8
T_DYNDATA	= 0x400 | 1


bortd_types = {
    T_ULONG: (4, 'L'),
    T_LONG: (4, 'l')
}


HEAD_LEN = 16
DATA_INFO_LEN = 32 + 32 + 4 * 5

class CmdSplitter:
    def __init__(self, data, itemlen):
	self.data = data[HEAD_LEN:]
	self.itemlen = itemlen
	a,b = divmod(len(self.data), itemlen)

	if b:
	    raise Error
	    
	self.items = a

    def __iter__(self):
	start = 0
	for i in xrange(self.items):
	    yield self.data[start:start+self.itemlen]
	    start += self.itemlen

class FEIDSplitter:
    def __init__(self, data):
	self.data = data[HEAD_LEN:]

    def __iter__(self):
	start = 0
	end = len(self.data)
	
	while start < end:
	    id, dlen = struct.unpack('<LL', self.data[start:start + 8])
	    data = self.data[start + 8: start + dlen + 8]
	    start += dlen + 8
	    yield (id, data)


def asciz(str):
    try:
	zero = str.index('\0')
	return str[:zero]
    except ValueError:
	return str


class DataInfo:
    def __init__(self, data, id, client):
	self.id = id
	self.client = client
	self.name = asciz(data[:32])
	self.fmt = asciz(data[32:64])
	self._cached = None

	(self.type, self.perm, self.x, self.y, self.len) =	\
	    struct.unpack('<LLLLL', data[64:])

    def _set_value(self, data):
	if not bortd_types.has_key(self.type):
	    raise Error, 'Unsupported type %d' % self.type
	
	blen, fmt = bortd_types[self.type]
	(self._cached,) = struct.unpack('<' + fmt, data[:blen])

    def __str__(self):
	return self.name

    def __int__(self):
	return self.id

    def validate(self):
	""" Is info valid or not """
	if len(self.client._vars) <= self.id or \
		self.client._vars[self.id] != self:
	    raise Error, 'Id is not valid for variable %s' % self.name

    def get(self, force = False):
	if force or self._cached == None:
	    self.validate()
	    self.client.get(self.id)
	    self.client.sync()
	return self._cached


    def set(self, value):
	self.validate()
	blen, fmt = bortd_types[self.type]
	data = struct.pack('<' + fmt, value)
	self.client.set((self.id, data))
	self.client.sync()

class Error(Exception):
    pass

def connect_unix(addr):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    if addr[0] == '@':
	addr = '\0' + addr[1:]
    print addr
    s.connect(addr)
    return s

def connect_tcp(addr):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    addrs = addr[6:]
    addrl = addrs.split(":")
    addrt = (addrl[0],int(addrl[1]))
    s.connect(addrt)
    return s


class IDRange:
    def __init__(self, id, limit = -1):
	self.id = id
	self.limit = limit
    def __str__(self):
	return struct.pack('<LL', self.id, self.limit)

class BortCommand:
    def __init__(self, id, arg0=0):
	self.id = id
	self.arg0 = arg0
	self.payload = []
	
    def append(self, data):
	if type(data) != str:
	    data = str(data)
	self.payload.append(data)
    def __str__(self):
        payload = ''.join(self.payload)
	return ''.join([struct.pack('<LLLL', self.id, len(payload), 1, self.arg0), payload])

from itertools import count, izip
class BortClient:
    def __init__(self):
	addr = os.getenv("BORT_SERVER")
	if addr:
	    self.socket = connect_tcp(addr)
	else:
	    self.socket = connect_unix(DEFAULT_ADDR)
	self.input = ''
	self.handlers = {
	    CMD_OK: lambda x: None,
	    CMD_LIST_REPLY: self._list_reply,
	    CMD_SET: self._set,
	    CMD_SESSION_SAVE_REPLY: self._session_save_reply,
	}
	self._vars = []
	self._vars_dict = {}
	self._sync = 0
	self.notify((0,1))

    def fileno(self):
	return self.socket.fileno()

    def handle_input(self):
	data = self.socket.recv(4096)
	if data == '':
	    raise Error
	self.input += data

	while self.parse():
	    pass

    def _send_cmd(self, cmd):
	self.socket.send(str(cmd))
	self._sync += 1

    def _idrange_payload(self, cmd, *what):
	for i in what:
	    if type(i) == type(0):
		cmd.append(IDRange(i, 1))
	    elif hasattr(i, '__int__'):
		cmd.append(IDRange(int(i), 1))
	    else:
		cmd.append(IDRange(*i))

    def notify(self, *what):
	cmd = BortCommand(CMD_NOTIFY)
	self._idrange_payload(cmd, *what)
	self._send_cmd(cmd)

    def get(self, *what):
	cmd = BortCommand(CMD_GET)
	self._idrange_payload(cmd, *what)
	self._send_cmd(cmd)

    def set(self, *what):
	cmd = BortCommand(CMD_SET)
	for id, data in what:
	    cmd.append(struct.pack('<LL', id, len(data)) + data)
	self._send_cmd(cmd)

    def session_save(self, force_save = True):
        """Request list of running applications, if force_save is true
            ask all other applications to save their state too"""
        if force_save:
            arg0 = 1
        else:
            arg0 = 0
	cmd = BortCommand(CMD_SESSION_SAVE, arg0)
	self._send_cmd(cmd)

    def restart(self):
	cmd = BortCommand(CMD_RESTART)
	self._send_cmd(cmd)

    def stop(self):
	cmd = BortCommand(CMD_STOP)
	self._send_cmd(cmd)

    def list(self):
	self._send_cmd(BortCommand(CMD_LIST))

    def parse(self):
	cnt = len(self.input)
	if cnt < HEAD_LEN:
	    return
	cmd_id, cmd_len, cmd_sync, cmd_r1 = struct.unpack('<LLLL', self.input[:HEAD_LEN])
	if cnt < HEAD_LEN + cmd_len:
	    return
	data = self.input[:HEAD_LEN + cmd_len]
	self.input = self.input[HEAD_LEN + cmd_len:]
	if cmd_sync:
	    self._sync -= 1
	if not self.handlers.has_key(cmd_id):
	    print 'Unhandled reply cmd_id = %d' % cmd_id
	    return True
	self.handlers[cmd_id](data)
	return True

    def _list_reply(self, data):
	self._vars = []
	for id, info in izip(count(), CmdSplitter(data, DATA_INFO_LEN)):
	    info = DataInfo(info, id, self)
	    self._vars.append(info)
	    self._vars_dict[info.name] = info
	self.on_event_list()

    def _set(self, data):
	ids = set()
	for (id,data) in FEIDSplitter(data):
	    self._vars[id]._set_value(data)
	    ids.add(id)
	self.on_event_set(ids)

    def _session_save_reply(self, data):
	class ii:
	    def __init__(self):
		self.data = data[HEAD_LEN:]
	    def __iter__(self):
		start = 0
		end = len(self.data)

		while start < end:
		    (nlen,) = struct.unpack('<L', self.data[start:start+4])
		    name = self.data[start+4:start+nlen+4]
		    start += nlen + 4
		    yield name
	self._session = list(ii())
	self.on_session_saved(self._session)

    def sync(self):
	while self._sync > 0:
	    self.handle_input()

    def __getitem__(self, what):
	if type(what) == type(0):
	    return self._vars[what]
	else:
	    return self._vars_dict[what]

    """ Override this """
    def on_event_list(self):
	pass
    def on_event_set(self, ids):
	pass
    def on_session_saved(self, ids):
	pass

import gobject
class BortProxy(gobject.GObject):
    __gsignals__ = {
        'connected': (gobject.SIGNAL_RUN_FIRST, gobject.TYPE_NONE, (gobject.TYPE_PYOBJECT,)),
        'disconnected': (gobject.SIGNAL_RUN_FIRST, gobject.TYPE_NONE, ()),
        'event-list': (gobject.SIGNAL_RUN_FIRST, gobject.TYPE_NONE, (gobject.TYPE_PYOBJECT,)),
        'event-set': (gobject.SIGNAL_RUN_FIRST, gobject.TYPE_NONE, (gobject.TYPE_PYOBJECT,gobject.TYPE_PYOBJECT)),
        'event-session-saved': (gobject.SIGNAL_RUN_FIRST, gobject.TYPE_NONE, (gobject.TYPE_PYOBJECT,gobject.TYPE_PYOBJECT)),
    }

    def __init__(self, timeout = 1000):
	gobject.GObject.__init__(self)
	self.client = None
	self._io_src = None
	self._started = False
	self._timeout = timeout
	self.state = _('Bort daemon is not running')
#	addr = os.getenv("BORT_SERVER")
#	if addr:
#	    self.state = _('{0}'.format(addr))
#	else:
#	    self.state = _('{0}'.format(DEFAULT_ADDR))

    def start(self):
	if not self._started:
##	    self.state = _('Connecting...')
	    self._connect()
	    self._started = True

    def _connect(self):
	try:
	    if self._io_src != None:
		gobject.source_remove(self._io_src)
	    self.client = BortClient()
	    self._io_src = gobject.io_add_watch(self.client.fileno(), gobject.IO_IN|gobject.IO_ERR|
							    gobject.IO_HUP,
							    self._handle_input)
	    self.client.on_event_list = lambda: self.emit('event-list', self.client)
	    self.client.on_event_set =  lambda a: self.emit('event-set', self.client, a)
	    self.client.on_session_saved = lambda a: self.emit('event-session-saved', self.client, a)
	    self.state = _('Bort daemon is running')
#	    addr = os.getenv("BORT_SERVER")
#	    if addr:
#		self.state = _('{0}'.format(addr))
#	    else:
#		self.state = _('{0}'.format(DEFAULT_ADDR))
	    self.emit('connected', self.client)

	except socket.error:
	    self.client = None
	    gobject.timeout_add(self._timeout, self._connect)

    def _disconnected(self):
	self.state = _('Bort daemon is not running')
#	addr = os.getenv("BORT_SERVER")
#	if addr:
#	    self.state = _('{0}'.format(addr))
#	else:
#	    self.state = _('{0}'.format(DEFAULT_ADDR))
	self.emit('disconnected')
	self._connect()

    def _handle_input(self, fd, cond):

	if cond != gobject.IO_IN:
	    self._disconnected()
	    return False
	try:
	    self.client.handle_input()
	except:
	    self._disconnected()
	    return False
	return True

	
if __name__ == "__main__":
    b = BortClient()
