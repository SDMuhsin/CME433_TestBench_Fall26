"""Flat gate-level netlist reader (LibreLane final/nl, final/pnl): ports and instance pins."""
import re

from names import norm


def parse_netlist(path):
    """-> (top ports, [(instance, pin, net)], {instance: cell}); bus pins `.A({n7, ..., n0})`
    become pins A[7] .. A[0]; names are norm()-alised"""
    text = open(path).read()
    body = text[text.index(");") + 2:]
    ports = re.findall(r"^\s*(?:input|output|inout)\s+(?:\[[^\]]+\]\s*)?(\S+)\s*;", body, re.M)
    pins, cells = [], {}
    for m in re.finditer(r"^\s*(gf180mcu_\w+)\s+(\\\S+\s|\S+)\s*\((.*?)\);", body, re.M | re.S):
        inst = norm(m.group(2))
        cells[inst] = m.group(1)
        for p in re.finditer(r"\.(\w+)\(\s*(\{[^}]*\}|\\\S+\s|[^()\s]+)\s*\)", m.group(3)):
            conn = p.group(2)
            if conn.startswith("{"):
                bits = [norm(b) for b in re.findall(r"\\\S+\s|[^,{}\s]+", conn)]
                for k, net in enumerate(bits):
                    pins.append((inst, "%s[%d]" % (p.group(1), len(bits) - 1 - k), net))
            else:
                pins.append((inst, p.group(1), norm(conn)))
    return [norm(p) for p in ports], pins, cells
