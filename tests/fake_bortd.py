"""Minimal fake of the bortd FE protocol for tests.

Listens on the abstract unix socket @/bortd/$USER (as the real daemon) and
answers the commands used by bortcfg: NOTIFY, GET, SET, LIST, SESSION_SAVE,
RESTART, STOP.
"""
import os
import socket
import struct
import threading

(CMD_OK, CMD_ERR, CMD_LIST, CMD_LIST_REPLY, CMD_GET, CMD_SET, CMD_NOTIFY,
 CMD_RMNOTIFY, CMD_CHANGE, CMD_SYS_INFO, CMD_SYS_INFO_REPLY,
 CMD_SET_SESSION_ID, CMD_SESSION_SAVE, CMD_SESSION_SAVE_REPLY,
 CMD_RESTART, CMD_STOP, CMD_EXIT_NOTIFY) = range(17)

T_ULONG = 0x100 | 4
HEAD = struct.Struct('<LLLL')


def pack(cmd, payload=b'', sync=1, arg0=0):
    return HEAD.pack(cmd, len(payload), sync, arg0) + payload


def var_info(name, fmt='%d', type_=T_ULONG):
    return (name.encode().ljust(32, b'\0') + fmt.encode().ljust(32, b'\0') +
            struct.pack('<LLLLL', type_, 3, 0, 0, 4))


class FakeBortd:
    def __init__(self, session=('navdat-arrow-1', 'navdat-fplan-2')):
        self.vars = [('sys::list_changed', 0), ('sys::demo_mode', 1)]
        self.session = list(session)
        self.commands = []
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind('\0/bortd/%s' % os.getenv('USER', 'nobody'))
        self.sock.listen(5)
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def close(self):
        self.sock.close()

    def _serve(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._client, args=(conn,), daemon=True).start()

    def _set_reply(self, ids, sync):
        payload = b''.join(struct.pack('<LL', i, 4) + struct.pack('<L', self.vars[i][1])
                           for i in ids)
        return pack(CMD_SET, payload, sync)

    def _client(self, conn):
        buf = b''
        while True:
            data = conn.recv(4096)
            if not data:
                return
            buf += data
            while len(buf) >= HEAD.size:
                cmd, length, sync, arg0 = HEAD.unpack(buf[:HEAD.size])
                if len(buf) < HEAD.size + length:
                    break
                payload = buf[HEAD.size:HEAD.size + length]
                buf = buf[HEAD.size + length:]
                self.commands.append(cmd)
                conn.sendall(self._handle(cmd, payload, arg0))

    def _handle(self, cmd, payload, arg0):
        if cmd == CMD_NOTIFY:
            ids = [struct.unpack('<LL', payload[i:i + 8])[0]
                   for i in range(0, len(payload), 8)]
            reply = pack(CMD_OK)
            if 0 in ids:
                # subscription to sys::list_changed: send the variable list
                listing = b''.join(var_info(n) for n, _ in self.vars)
                reply += pack(CMD_LIST_REPLY, listing, sync=0)
            ids = [i for i in ids if 0 < i < len(self.vars)]
            if ids:
                reply += self._set_reply(ids, sync=0)
            return reply
        if cmd == CMD_GET:
            ids = [struct.unpack('<LL', payload[i:i + 8])[0]
                   for i in range(0, len(payload), 8)]
            return self._set_reply(ids, sync=1)
        if cmd == CMD_LIST:
            listing = b''.join(var_info(n) for n, _ in self.vars)
            return pack(CMD_LIST_REPLY, listing)
        if cmd == CMD_SESSION_SAVE:
            names = b''.join(struct.pack('<L', len(n)) + n.encode() for n in self.session)
            return pack(CMD_SESSION_SAVE_REPLY, names)
        return pack(CMD_OK)
