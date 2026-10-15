import os

BORTDRC = '~/.bort/bortdrc'

class Error(Exception):
    pass

class Config:
    def __init__(self, name = None, value = None):
        self.name = name
        self.value = value
        self.children = []

    def __str__(self, indent = 0):
        do_indent = lambda x: '%*s%s' % (4 * indent, '', x)
        if self.name:
            if self.value:
                ret = [do_indent('%s %s' % (self.name, self.value))]
            else:
                ret = [do_indent(self.name)]
            if self.children:
                ret += [do_indent('{')] + [i.__str__(indent + 1) for i in self.children] + \
                    [do_indent('}')]
        else: # root item
            ret = [i.__str__(indent) for i in self.children]
        return '\n'.join(ret)

    def exclusive(self, name, default=''):
        keys = self.get_key(name)

        if 0 == len(keys):
            keys = [Config(name, default)]
            self.children += keys
        for i in keys[1:]:
            self.children.remove(i)
        return keys[0].value

    def get_key(self, name):
        return [i for i in self.children if i.name == name]

    def set(self, name, value):
        keys = self.get_key(name)

        if len(keys):
            keys[0].value = value
        else:
            self.children.append(Config(name, value))

    def remove(self, key):
        self.children = [i for i in self.children
                         if i.name != key]

    def set_list(self, key, values):
        for value in values:
            self.children.append(Config(key, value))


def load_config(path = BORTDRC):
    path = os.path.expanduser(path)

    with open(path, 'r', encoding='utf-8') as fp:
        lines = fp.readlines()
    stack = [Config()]

    for line in lines:
        line = line.strip()
        if line.startswith('#') or line == '':
            continue
        elif line == '{':
            stack.append(stack[-1].children[-1])
        elif line == '}':
            if len(stack) == 0:
                raise Error
            stack.pop()
        else:
            args = line.split(None, 1)
            cfg = Config(*args)
            stack[-1].children.append(cfg)

    return stack[0]

def write_config(cfg, path = BORTDRC):
    path = os.path.expanduser(path)
    dirname = os.path.dirname(path)
    try:
        os.makedirs(dirname)
    except os.error:
        pass
    try:
        os.rename(path, path + '~')
    except os.error:
        pass
    with open(path, 'w', encoding='utf-8') as fp:
        fp.write(str(cfg) + '\n')



if __name__ == "__main__":
    cfg = load_config()
    write_config(cfg, 'foo')
