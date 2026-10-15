"""Scale. 1 Blender unit = 1 stud (kit + v17 convention). Helpers for when a reference
is given in metres (Roblox: 1 stud = 0.28 m for physics/character scale)."""
STUD_M = 0.28
AVATAR_HEIGHT = 5.0  # default R15 avatar is ~5 studs tall; the contact sheet shows one


def studs(m):
    """metres -> studs (Blender units)."""
    return m / STUD_M


def meters(s):
    return s * STUD_M
