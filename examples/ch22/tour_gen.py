# Generates delve's built-in tour demo (src/demos/tour.txt): BFS paths
# through the labyrinth, followed by a pure-pursuit "driver" that presses W
# and the arrow keys, simulated with the same rules as player.zig.
#
# usage: python3 tour_gen.py MAP OUT [LOOKAHEAD]
#   MAP        the labyrinth, src/maps/labyrinth.txt
#   OUT        where to write the demo
#   LOOKAHEAD  how far ahead on the path the driver aims, in cells (0.6)
import math, sys
from collections import deque

rows = [r for r in open(sys.argv[1]).read().split("\n") if r]
LOOK = float(sys.argv[3]) if len(sys.argv) > 3 else 0.6
H, W = len(rows), len(rows[0])
wall = lambda x, y: not (0 <= x < W and 0 <= y < H) or rows[y][x] in "#%"
barrels = [(x + .5, y + .5) for y in range(H) for x in range(W) if rows[y][x] == "o"]
# player.zig's numbers: tick, move speed, turn speed, tilt speed, the
# player's radius and a barrel's.
DT, MOVE, TURN, TILT, R, RB = 1 / 60, 3.0, 2.5, 1.5, 0.25, 0.23

def bfs(a, b):
    """The shortest path of cells from a to b, both included."""
    prev = {a: None}
    q = deque([a])
    while q:
        c = q.popleft()
        if c == b: break
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + d[0], c[1] + d[1])
            if n not in prev and not wall(*n) and rows[n[1]][n[0]] != "o":
                prev[n] = c; q.append(n)
    path = [b]
    while prev[path[-1]] is not None: path.append(prev[path[-1]])
    return path[::-1]

# Collision, as in player.zig: push out of barrels, then out of the 3x3
# wall cells around the player, each push away from the closest point.
def push(p, q, dist):
    dx, dy = p[0] - q[0], p[1] - q[1]
    l = math.hypot(dx, dy)
    if l >= dist or l == 0: return p
    return (q[0] + dx * dist / l, q[1] + dy * dist / l)

def collide(p):
    for b in barrels: p = push(p, b, R + RB)
    cx, cy = math.floor(p[0]), math.floor(p[1])
    for y in range(cy - 1, cy + 2):
        for x in range(cx - 1, cx + 2):
            if wall(x, y):
                p = push(p, (max(x, min(x + 1, p[0])), max(y, min(y + 1, p[1]))), R)
    return p

class Sim:
    """The player, and the runs of input that moved it."""
    def __init__(s, pos, yaw):
        s.pos, s.yaw, s.pitch, s.ticks, s.runs = pos, yaw, 0.0, 0, []
        s.contacts = 0
    def tick(s, fwd=0.0, turn=0.0, tilt=0.0):
        # The file keeps 6 digits; simulate exactly what it will say.
        turn = float(f"{turn:.6g}")
        s.yaw = (s.yaw + turn * TURN * DT) % math.tau
        s.pitch = max(-math.radians(85), min(math.radians(85), s.pitch + tilt * TILT * DT))
        if fwd:
            step = (math.cos(s.yaw) * MOVE * DT, math.sin(s.yaw) * MOVE * DT)
            want = (s.pos[0] + step[0], s.pos[1] + step[1])
            moved = collide(want)
            # A wall or barrel pushed back: the driver touched it.
            if moved != want: s.contacts += 1
            if all(math.hypot(moved[0] - b[0], moved[1] - b[1]) >= R + RB - 1e-4 for b in barrels):
                s.pos = moved
        line = (fwd, turn, tilt)
        if s.runs and s.runs[-1][1] == line: s.runs[-1][0] += 1
        else: s.runs.append([1, line])
        s.ticks += 1
        if s.ticks > 20000: sys.exit("the driver is lost: gave up after 20000 ticks")

def wrap(a): return (a + math.pi) % math.tau - math.pi

def follow(sim, cells, look):
    """Drives along the path through `cells` until at its end."""
    pts = [(x + .5, y + .5) for x, y in cells]
    seg = 0
    stopped = False
    while True:
        p = sim.pos
        # Closest point on the path from the current segment on, then a
        # point `look` cells further along it.
        while seg < len(pts) - 2:
            a, b = pts[seg], pts[seg + 1]
            if (p[0] - b[0]) * (b[0] - a[0]) + (p[1] - b[1]) * (b[1] - a[1]) > 0: seg += 1
            else: break
        a, b = pts[seg], pts[seg + 1]
        seglen = math.hypot(b[0] - a[0], b[1] - a[1])
        t = max(0, min(seglen, ((p[0] - a[0]) * (b[0] - a[0]) + (p[1] - a[1]) * (b[1] - a[1])) / seglen))
        left, i, pos = look, seg, t
        while True:
            a, b = pts[i], pts[i + 1]
            l = math.hypot(b[0] - a[0], b[1] - a[1])
            if pos + left <= l or i == len(pts) - 2:
                u = min(l, pos + left) / l
                target = (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u)
                break
            left -= l - pos; pos = 0; i += 1
        end = pts[-1]
        if math.hypot(end[0] - p[0], end[1] - p[1]) < 0.06: return
        # Turn toward the target as fast as the arrow keys allow, but not
        # past it, and not at all for tiny errors.
        diff = wrap(math.atan2(target[1] - p[1], target[0] - p[0]) - sim.yaw)
        turn = 0.0 if abs(diff) < 0.02 else max(-1, min(1, diff / (TURN * DT)))
        # Stop to turn at corners, and walk on once facing the way out.
        if abs(diff) > 0.8: stopped = True
        if abs(diff) < 0.1: stopped = False
        sim.tick(fwd=0.0 if stopped else 1.0, turn=turn)

def turn_by(sim, angle, fwd=0.0):
    n = abs(angle) / (TURN * DT)
    for _ in range(int(n)): sim.tick(fwd=fwd, turn=math.copysign(1, angle))
    if n % 1 > 1e-6: sim.tick(fwd=fwd, turn=math.copysign(n % 1, angle))

def look_up(sim, angle, hold):
    n = int(round(angle / (TILT * DT)))
    for _ in range(n): sim.tick(tilt=1.0)
    for _ in range(hold): sim.tick()
    for _ in range(n): sim.tick(tilt=-1.0)

# From the start to the west room, look at its ceiling, on to the big
# northern room, turn around once there and look up.
sim = Sim((1.5, 1.5), 0.0)
stops = [(1, 1), (13, 12), (40, 9)]
for a, b in zip(stops, stops[1:]):
    print("leg", a, b, len(bfs(a, b)) - 1, "cells", file=sys.stderr)
    follow(sim, bfs(a, b), LOOK)
    if b == (13, 12):
        look_up(sim, 0.6, 30)
turn_by(sim, math.tau)
look_up(sim, 0.75, 45)

out = ["# delve demo: the built-in tour, generated by a script",
       "map labyrinth", "start 1.5 1.5 0 0"]
fmt = lambda v: ("%d" % v) if v == int(v) else repr(float(f"{v:.6g}"))
for n, (f, t, u) in sim.runs:
    out.append(f"{n} {fmt(f)} 0 {fmt(t)} {fmt(u)} 0 0")
open(sys.argv[2], "w").write("\n".join(out) + "\n")
print("ticks", sim.ticks, "runs", len(sim.runs), "end", sim.pos, "yaw", sim.yaw, "contacts", sim.contacts, file=sys.stderr)
