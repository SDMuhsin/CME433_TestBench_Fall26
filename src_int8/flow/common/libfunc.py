"""Liberty boolean functions: evaluation and unateness conditions (shared by the SDF GLS models
and the SDF fix-ups)."""
import itertools
import re


def lib_expr(func):
    """Liberty boolean function -> python lambda over a dict of 0/1."""
    if "^" in func:
        raise SystemExit("xor operator in Liberty function %r not handled" % func)
    e = re.sub(r"\b([A-Za-z_]\w*)\b", r"v['\1']", func)
    e = e.replace("!", " not ").replace("&", " and ").replace("*", " and ")
    e = e.replace("|", " or ").replace("+", " or ")
    return eval("lambda v: int(bool(" + e + "))")


def unate_conds(func, pins, x):
    """Verilog conditions on the side inputs for which y = f(x) is positive / negative unate."""
    f = lib_expr(func)
    side = [p for p in pins if p != x]
    pos, neg = [], []
    for bits in itertools.product((0, 1), repeat=len(side)):
        v = dict(zip(side, bits))
        v[x] = 0
        y0 = f(v)
        v[x] = 1
        y1 = f(v)
        term = " && ".join("%s == 1'b%d" % (p, b) for p, b in zip(side, bits))
        if y0 == 0 and y1 == 1:
            pos.append(term)
        elif y0 == 1 and y1 == 0:
            neg.append(term)
    j = lambda ts: " || ".join("(%s)" % t for t in ts)
    return j(pos), j(neg)
