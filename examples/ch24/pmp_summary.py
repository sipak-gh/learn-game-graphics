#!/usr/bin/env python3
"""Counts the stacks that pmp.sh printed: the function each sample was in
(self), the source line, and every function on the stack (inclusive).

    usage: pmp_summary.py stacks.txt
"""
import collections
import re
import sys

# "#0  0x00000000011ba4e1 in texture.Texture.bilinear (...) at src/texture.zig:198"
# Inlined frames have no address: "#1  texture.Texture.filtered (...) at ...".
FRAME = re.compile(r"^#(\d+)\s+(?:0x[0-9a-f]+ in )?(\S+) \(.*?\)(?: at (\S+):(\d+))?")


def short(name):
    # Zig adds "__anon_1234" or "__func_787" to the names of generic
    # instances; one name per function is enough.
    return re.sub(r"__(anon|func)_\d+", "", name)


stacks = []
with open(sys.argv[1]) as f:
    for line in f:
        m = FRAME.match(line)
        if not m:
            continue
        if m.group(1) == "0":
            stacks.append([])
        if stacks:
            # The last two parts of the path tell src/math.zig from std/math.zig.
            where = f"{'/'.join(m.group(3).split('/')[-2:])}:{m.group(4)}" if m.group(3) else "?"
            stacks[-1].append((short(m.group(2)), where))

n = len(stacks)
self_count = collections.Counter(s[0][0] for s in stacks)
line_count = collections.Counter(s[0][1] for s in stacks)
# A function counts once per sample, however often it is on the stack.
incl_count = collections.Counter(name for s in stacks for name in {f for f, _ in s})


def show(title, counter):
    print(title)
    for name, c in counter.most_common(12):
        print(f"  {100 * c / n:5.1f}%  {name}")


print(f"samples {n}")
show("self (the function the program was in)", self_count)
show("lines", line_count)
show("inclusive (on the stack)", incl_count)
