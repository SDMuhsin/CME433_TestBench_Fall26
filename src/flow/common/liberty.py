"""Minimal Liberty reader: group tree with simple/complex attributes (enough for cell/pin/timing).

parse(path) -> Group('library', ...).  Group: .kind, .args (list of str), .attrs (dict name ->
str for simple attributes, last wins), .cattrs (list of (name, [args]) complex attributes),
.groups (list of Group).  Comments, line continuations and quoted strings are handled; values
are returned without quotes.  Tables are kept as complex attributes (values(...)) but not decoded.
"""
import re

_TOK = re.compile(r'"(?:[^"\\]|\\.)*"|[{}();:,]|[^\s{}();:,"]+')


class Group:
    __slots__ = ("kind", "args", "attrs", "cattrs", "groups")

    def __init__(self, kind, args):
        self.kind, self.args = kind, args
        self.attrs, self.cattrs, self.groups = {}, [], []

    def sub(self, kind):
        return [g for g in self.groups if g.kind == kind]

    def name(self):
        return self.args[0] if self.args else ""


def _tokens(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = text.replace("\\\n", " ")
    for m in _TOK.finditer(text):
        t = m.group(0)
        yield t[1:-1] if t.startswith('"') else t


def parse(path):
    with open(path) as f:
        toks = list(_tokens(f.read()))
    pos = 0
    root = Group("root", [])
    stack = [root]
    n = len(toks)
    while pos < n:
        t = toks[pos]
        if t == "}":
            stack.pop()
            pos += 1
            continue
        if t == ";":
            pos += 1
            continue
        name = t
        nxt = toks[pos + 1] if pos + 1 < n else ""
        if nxt == ":":                                   # simple attribute  name : value ;
            j = pos + 2
            val = []
            while toks[j] != ";" and toks[j] != "}":
                val.append(toks[j])
                j += 1
            stack[-1].attrs[name] = " ".join(val)
            pos = j + 1 if toks[j] == ";" else j
        elif nxt == "(":                                 # group or complex attribute
            j = pos + 2
            args = []
            while toks[j] != ")":
                if toks[j] != ",":
                    args.append(toks[j])
                j += 1
            j += 1
            if j < n and toks[j] == "{":
                g = Group(name, args)
                stack[-1].groups.append(g)
                stack.append(g)
                pos = j + 1
            else:
                stack[-1].cattrs.append((name, args))
                pos = j + 1 if j < n and toks[j] == ";" else j
        else:
            pos += 1
    libs = root.sub("library")
    return libs[0] if libs else root
