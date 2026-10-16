#!/usr/bin/env python3
"""Writes the slime KeyframeSequences (animations/*.rbxmx) for the Motor6D slime rig.

    python3 tools/gen_slime_animations.py

Rig (src/visuals/shared/SlimeRig.luau): Body (root, anchored) -> FaceRoot, Body -> SkinRoot
(Motor6Ds named like their Part1); the skin MeshPart "Mesh" has a "Squash" bone. Poses are the
Motor6D Transform (offset from rest): face and skin get the same move so they stay together.
SlimeBlink is not authored: the eyes are separate parts without a lid.
Durations match v28-ALIVE-NEEDS.md: idle 2.5 s loop, hop 0.75 s, looks 0.4 s.
"""
import math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "animations")
EASE_CUBIC, EASE_INOUT = 3, 2


def cframe(y=0.0, yaw=0.0, roll=0.0, pitch=0.0):
    """CoordinateFrame xml for translation (0, y, 0) and rotation Ry(yaw) * Rx(pitch) * Rz(roll)."""
    cy, sy_, cp, sp, cr, sr = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch), math.cos(roll), math.sin(roll)
    ry = [[cy, 0, sy_], [0, 1, 0], [-sy_, 0, cy]]
    rx = [[1, 0, 0], [0, cp, -sp], [0, sp, cp]]
    rz = [[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]]
    mul = lambda a, b: [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    r = mul(mul(ry, rx), rz)
    tags = "".join(f"<R{i}{j}>{r[i][j]:.6f}</R{i}{j}>" for i in range(3) for j in range(3))
    return f'<CoordinateFrame name="CFrame"><X>0</X><Y>{y:.6f}</Y><Z>0</Z>{tags}</CoordinateFrame>'


class Ids:
    n = 0

    @classmethod
    def next(cls):
        cls.n += 1
        return f"RBX{cls.n}"


def pose(name, cf, children=""):
    return (f'<Item class="Pose" referent="{Ids.next()}"><Properties>{cf}'
            f'<token name="EasingDirection">{EASE_INOUT}</token><token name="EasingStyle">{EASE_CUBIC}</token>'
            f'<string name="Name">{name}</string><float name="Weight">1</float></Properties>{children}</Item>')


def keyframe(t, move):
    """move = dict(y, yaw, roll, pitch, squash) -> Body > FaceRoot, SkinRoot > Mesh > Squash."""
    m = {k: move.get(k, 0.0) for k in ("y", "yaw", "roll", "pitch")}
    same = cframe(**m)
    squash = pose("Squash", cframe(y=-0.1 * move.get("squash", 0.0)))  # bone: squash > 0 = flatter
    mesh = pose("Mesh", cframe(), squash)
    root = pose("Body", cframe(), pose("FaceRoot", same) + pose("SkinRoot", same, mesh))
    return (f'<Item class="Keyframe" referent="{Ids.next()}"><Properties><float name="Time">{t:.4f}</float>'
            f'<string name="Name">Keyframe</string></Properties>{root}</Item>')


def sequence(name, loop, priority, frames):
    body = "".join(keyframe(t, m) for t, m in frames)
    return ('<roblox version="4"><Item class="KeyframeSequence" referent="RBX0"><Properties>'
            f'<float name="AuthoredHipHeight">2</float><bool name="Loop">{str(loop).lower()}</bool>'
            f'<string name="Name">{name}</string><token name="Priority">{priority}</token></Properties>'
            f'{body}</Item></roblox>\n')


# Enum.AnimationPriority: Core 1000, Idle 0, Movement 1, Action 2, Action2 3, Action3 4 (tokens are the enum values)
IDLE, MOVEMENT, ACTION = 0, 1, 2

def idle():
    n = 5
    frames = []
    for i in range(n):  # last frame == first so the 2.5 s loop is seamless
        a = 2 * math.pi * i / (n - 1)
        frames.append((2.5 * i / (n - 1), dict(y=-0.04 * (1 - math.cos(a)) / 2, roll=0.03 * math.sin(a),
                                               pitch=0.015 * math.sin(a + 1), squash=0.6 * (1 - math.cos(a)) / 2)))
    return sequence("SlimeIdleSquish", True, IDLE, frames)


def hop():
    return sequence("SlimeHop", False, ACTION, [
        (0.00, dict()),
        (0.14, dict(y=-0.06, squash=1.0)),            # wind-up squat
        (0.28, dict(y=0.45, squash=-0.6)),            # take-off, stretched
        (0.45, dict(y=0.9, squash=-0.2)),             # apex
        (0.60, dict(y=0.0, squash=1.2)),              # land, squashed
        (0.75, dict()),
    ])


def look(name, sign):
    return sequence(name, False, ACTION, [
        (0.0, dict()),
        (0.2, dict(yaw=sign * 0.5, roll=sign * -0.04)),
        (0.4, dict()),
    ])


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, xml in (("SlimeIdleSquish", idle()), ("SlimeHop", hop()),
                      ("SlimeLookLeft", look("SlimeLookLeft", 1)), ("SlimeLookRight", look("SlimeLookRight", -1))):
        with open(os.path.join(OUT, name + ".rbxmx"), "w") as f:
            f.write(xml)
        print("wrote", name)


if __name__ == "__main__":
    main()
