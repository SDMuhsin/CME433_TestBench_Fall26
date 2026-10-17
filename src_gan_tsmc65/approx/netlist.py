"""Tiny bit-level netlist: 2-input AND / OR / XOR and NOT over named input bits.

One description serves both the Python reference model (`evaluate`, vectorised over any
integer or boolean arrays: unpacked 0/1 bits or 64 inputs packed per uint64 word) and the
Verilog writer (`emit.py`). Constants are folded while building, so constant partial-product
bits (Baugh-Wooley, Booth sign extension) disappear from the logic.
"""
ZERO, ONE = 0, 1                       # node ids of the two constants


class Net:
    def __init__(self):
        self.ops = [('const', 0), ('const', 1)]   # (op, *operand node ids | value)
        self.names = {}                           # node id -> Verilog wire name
        self.inputs = {}                          # bus name -> width
        self._memo = {}

    def _add(self, *op):
        if op not in self._memo:
            self._memo[op] = len(self.ops)
            self.ops.append(op)
        return self._memo[op]

    def bus(self, name, width):
        self.inputs[name] = width
        return [self._add('in', name, i) for i in range(width)]

    def name(self, node, label):
        if node > ONE and self.ops[node][0] != 'in' and node not in self.names:
            self.names[node] = label
        return node

    def NOT(self, x):
        if x <= ONE:
            return 1 - x
        if self.ops[x][0] == 'not':
            return self.ops[x][1]
        return self._add('not', x)

    def AND(self, x, y):
        if ZERO in (x, y):
            return ZERO
        if x == ONE or x == y:
            return y
        if y == ONE:
            return x
        return self._add('and', *sorted((x, y)))

    def OR(self, x, y):
        if ONE in (x, y):
            return ONE
        if x == ZERO or x == y:
            return y
        if y == ZERO:
            return x
        return self._add('or', *sorted((x, y)))

    def XOR(self, x, y):
        if x == y:
            return ZERO
        if x <= ONE:
            return y if x == ZERO else self.NOT(y)
        if y <= ONE:
            return x if y == ZERO else self.NOT(x)
        return self._add('xor', *sorted((x, y)))

    def any(self, xs):
        """OR of a list (one multi-input OR gate in the drawing)."""
        out = ZERO
        for x in xs:
            out = self.OR(out, x)
        return out

    def evaluate(self, bits, outputs, ones):
        """Values of `outputs` (nested lists of node ids). bits[name][i] is the array of input
        bit i of bus `name`; `ones` is the all-ones value of the array type (1, True, ~0)."""
        need = set()
        stack = [n for n in _flat(outputs)]
        while stack:
            n = stack.pop()
            if n not in need:
                need.add(n)
                op = self.ops[n]
                if op[0] in ('not', 'and', 'or', 'xor'):
                    stack.extend(op[1:])
        last = {}
        for n in sorted(need):
            for m in self.ops[n][1:] if self.ops[n][0] in ('not', 'and', 'or', 'xor') else ():
                last[m] = n
        keep = set(_flat(outputs))
        val = {}
        for n in sorted(need):
            op = self.ops[n]
            kind = op[0]
            if kind == 'const':
                val[n] = ones if op[1] else ones ^ ones
            elif kind == 'in':
                val[n] = bits[op[1]][op[2]]
            elif kind == 'not':
                val[n] = val[op[1]] ^ ones
            elif kind == 'and':
                val[n] = val[op[1]] & val[op[2]]
            elif kind == 'or':
                val[n] = val[op[1]] | val[op[2]]
            else:
                val[n] = val[op[1]] ^ val[op[2]]
            for m in op[1:] if kind in ('not', 'and', 'or', 'xor') else ():
                if last.get(m) == n and m not in keep:
                    del val[m]                      # free intermediate arrays early
        return _map(outputs, val)


def _flat(x):
    if isinstance(x, (list, tuple)):
        for y in x:
            yield from _flat(y)
    else:
        yield x


def _map(x, val):
    if isinstance(x, (list, tuple)):
        return [_map(y, val) for y in x]
    return val[x]
