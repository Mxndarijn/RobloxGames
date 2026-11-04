from recipes import icon
from helpers import C, group, put, run_model, slime
from props import coin

# Exclusive Shop icons, each rebuilt from the item's own shipping model script so the colours match the uploaded mesh:
#   Hat_<id>        models/slime_hat_<id>.py worn on a small green slime (helpers.slime), the hat the subject
#   LockStyle_<id>  models/lock_stopper_<id>.py, front-on 3/4
#   BatSkin_<id>    models/bat_skin_<id>.py, tilted diagonally to fill the square
#   PetSeat_<id>    models/pet_mount_<id>.py (Halloween / winter seats; the rest live in recipes_seat.py)
#   PlotSkin_<id>   the jar tower top in the skin's theme (recipes_skin.tower_top)
#   PlotBase_<id>   the whole base from its design scene (models/_base_<id>_design.py), 2 floors, no plot foot
#   Bundle_<id>     the bundle's seats / decor in a small group
__all__ = []  # registers via @icon; exports nothing

HAT_VIEW = (26, 22)
HATS = ["party", "bow", "chef", "flower_crown", "top_hat", "witch"]
HAT_SLIME = 0.78  # slime scale under the hat: the hat (~2 studs) covers most of the 2.3-stud-wide head
HAT_SINK = {"bow": 0.25, "flower_crown": 0.18}  # hats that sit lower on the crown than the default


def _hat(hid):
    def build():
        body = slime((110, 225, 130), "happy", (0, 0, 0), (0, 0, 0), HAT_SLIME)
        hat = run_model("slime_hat_" + hid)
        put(hat, (0, 0, 3.0 * HAT_SLIME - 0.12 - HAT_SINK.get(hid, 0.0)))
        return [body, hat]
    build.__name__ = "hat_" + hid
    return build


for _h in HATS:
    icon("Hat_" + _h, view=HAT_VIEW, fill=0.86)(_hat(_h))


LOCK_VIEW = (24, 14)


def _lock(lid):
    def build():
        return [run_model("lock_stopper_" + lid)]
    build.__name__ = "lock_" + lid
    return build


for _l in ["candy", "carousel", "sleepy"]:
    icon("LockStyle_" + _l, view=LOCK_VIEW, fill=0.84)(_lock(_l))


BAT_VIEW = (14, 14)


def _bat(bid):
    def build():
        o = run_model("bat_skin_" + bid)
        return [group([o], rot=(0, 42, 0), name="bat")]  # lean right: grip bottom-left, barrel top-right
    build.__name__ = "bat_" + bid
    return build


for _b in ["lollipop", "fish", "foam_finger", "golden"]:
    icon("BatSkin_" + _b, view=BAT_VIEW, fill=0.9)(_bat(_b))


SEAT_VIEW = (30, 30)  # recipes_seat.SEAT_VIEW


def _seat(sid):
    def build():
        return [run_model("pet_mount_" + sid)]
    build.__name__ = "seat_" + sid
    return build


for _s in ["pumpkin", "snowglobe"]:
    icon("PetSeat_" + _s, view=SEAT_VIEW)(_seat(_s))


def _skin(theme):
    def build():
        from recipes_skin import tower_top
        return tower_top(theme)
    build.__name__ = "skin_" + theme
    return build


for _t in ["fairground", "beach", "space", "winter", "haunted"]:
    icon("PlotSkin_" + _t, view=(28, 30))(_skin(_t))


# ---------------------------------------------------------------- whole bases from their design scenes
BASE_VIEW = (32, 26)
BASE_FLOORS = 2
FLOORS = {"lighthouse": 4}  # the lighthouse only reads as one with its tall tower
GLASS = {"snowglobe": "Glass_"}  # the globe dome is the look: the stronger tinted glass


def _base(kit):
    def build():
        import os, sys
        import bpy
        from helpers import KIT
        os.environ["FLOORS"] = str(FLOORS.get(kit, BASE_FLOORS))
        os.environ["LAYOUT_FLOORS"] = os.environ["FLOORS"]
        for k in ("THEME", "CUT", "COLLIDERS", "LOCKED", "DROP"):
            os.environ.pop(k, None)
        for m in [m for m in sys.modules if m.startswith("models._")]:
            del sys.modules[m]  # the design modules read FLOORS and keep their part lists at import
        import models._base_concept_common as BC
        BC.avatar = lambda *a, **k: None  # no players for scale
        BC.plot_foot = lambda *a, **k: None  # no grass disc / moat round the building
        got = []
        real_ship = BC.ship

        def ship(name, turn=-20):
            out = real_ship(name, turn)
            got.extend(out)
            return out
        BC.ship = ship
        path = os.path.join(KIT, "models", f"_base_{kit}_design.py")
        g = {"__name__": "__model__", "__file__": path}
        exec(compile(open(path, encoding="utf-8").read(), path, "exec"), g)
        # the factory adds every part to the common lists (ship joins them); the other kits keep their pieces in
        # their own `objs` / `glass_objs` beside the joined pads, vat and mascot
        glass = set()
        for o in g.get("glass_objs", []):
            try:
                glass.add(o.name)
            except ReferenceError:
                pass
        out = []
        for o in got + list(g.get("objs", [])):
            try:
                o.name
            except ReferenceError:  # joined away
                continue
            if o in out or o.type != "MESH":
                continue
            o.rotation_euler = (0, 0, 0)
            if o.name.endswith("_glass") or o.name in glass:
                o.name = GLASS.get(kit, "GlassClear_") + o.name  # the icon rig's see-through materials
            out.append(o)
        bpy.context.view_layer.update()
        return out
    build.__name__ = "base_" + kit
    return build


for _k in ["factory", "pagoda", "carousel", "rocket", "treehouse", "lighthouse", "snowglobe"]:
    icon("PlotBase_" + _k, view=BASE_VIEW, fill=0.86)(_base(_k))


# ---------------------------------------------------------------- bundles
@icon("Bundle_starter", view=(30, 36))
def bundle_starter():
    leaf = run_model("pet_mount_leaf", (-0.5, 0.3, 0))
    return [leaf, coin("X2", 1.05, 0.3, (1.15, -0.9, 1.05), (90, 0, -20), mark="x2")]


@icon("Bundle_boutique", view=(30, 24))
def bundle_boutique():
    pole = run_model("plot_skin_fairground", (2.9, 1.6, 0), scale=0.85)
    carpet = run_model("pet_mount_magic_carpet")
    xs = [v.co.x for v in carpet.data.vertices]
    put(carpet, (-0.6, -0.6, 0), (0, 0, -12), scale=5.6 / max(0.1, max(xs) - min(xs)))
    return [pole, carpet]


@icon("Bundle_sky", view=(30, 26))
def bundle_sky():
    spots = [("storm_cloud", (-1.7, 1.4, 1.1)), ("sunset_cloud", (1.9, 1.6, 1.3)),
             ("ice_cloud", (-1.9, -1.5, 0)), ("flame_cloud", (1.7, -1.4, 0.2))]
    out = []
    for sid, pos in spots:
        o = run_model("pet_mount_" + sid)
        xs = [v.co.x for v in o.data.vertices]
        s = 3.6 / max(0.1, max(xs) - min(xs))  # each cloud about 3.6 studs across
        out.append(put(o, pos, scale=s))
    return out
