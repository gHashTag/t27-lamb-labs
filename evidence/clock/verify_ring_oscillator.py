#!/usr/bin/env python3
"""Static verification that the ring oscillator survives synthesis as a closed loop.

Reads the synthesised JSON netlist and walks the inverter chain from chain[0] to
chain[19], then checks whether the chain closes back through the clock buffer.

This proves STRUCTURAL presence. It does not prove FUNCTIONAL oscillation: a
closed inverter loop can still fail to oscillate in silicon. That needs a board.
"""
import json, sys

def check(path):
    d = json.load(open(path))
    mod = d['modules']['ternary_mac_demo_top']
    cells = mod.get('cells', {})
    bit2net = {}
    for name, n in mod.get('netnames', {}).items():
        for b in n.get('bits', []):
            if isinstance(b, int):
                bit2net[b] = name
    # Inverters AND buffers both forward a signal; the ring closes through the
    # BUFG that the clock-buffer mapper inserts in the clock path.
    inv = []
    for name, c in cells.items():
        if c['type'] in ('LUT1', 'INV', 'BUFG', 'BUF', 'BUFR', 'BUFIO'):
            cn = c.get('connections', {})
            i = cn.get('I0') or cn.get('I')
            o = cn.get('O')
            if i and o:
                inv.append((name, c['type'], i[0], o[0]))
    drivers = {}
    for name, c in cells.items():
        o = c.get('connections', {}).get('O')
        if o: drivers[o[0]] = (name, c['type'])

    # start from the element that drives chain[0]
    start = None
    for n, t, i, o in inv:
        if bit2net.get(o) == 'chain[0]':
            start = (n, t, i, o); break
    if not start:
        return None, "no inverter drives chain[0]"

    # walk forward: the inverter whose input is this one's output
    chain = []
    node = start
    seen = set()
    for _ in range(64):
        n, t, i, o = node
        chain.append((n, t, bit2net.get(i), bit2net.get(o)))
        if n in seen: break
        seen.add(n)
        nxt = None
        for nm, tt, ii, oo in inv:
            if ii == o:
                nxt = (nm, tt, ii, oo); break
        if nxt is None: break
        node = nxt
        if bit2net.get(node[3]) == 'chain[0]':
            return chain, "CLOSED"
    return chain, "OPEN"

if __name__ == "__main__":
    p = sys.argv[1] if len(sys.argv) > 1 else \
        "/Users/playra/t27/fpga/verilog/ternary_mac_demo_top.json"
    chain, verdict = check(p)
    print(f"netlist: {p}")
    if chain:
        print(f"inverter chain length walked: {len(chain)}")
        for n, t, i, o in chain[:3]:
            print(f"  {n:26s} ({t:4s}) in={i} out={o}")
        print("  ...")
        for n, t, i, o in chain[-3:]:
            print(f"  {n:26s} ({t:4s}) in={i} out={o}")
    print(f"VERDICT: ring oscillator loop is {verdict}")
    print("NOTE: structural presence only. Functional oscillation needs a board.")
