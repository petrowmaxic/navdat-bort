import sys

if len(sys.argv) != 2 or sys.argv[1] not in ('save', 'restore'):
    print("Usage: %s <save|restore>" % sys.argv[0], file=sys.stderr)
    sys.exit(1)

import bortcfg

if sys.argv[1] == 'save':
    bortcfg.SessionSave()
elif sys.argv[1] == 'restore':
    bortcfg.SessionRestore()
