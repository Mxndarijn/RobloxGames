"""Steal a Slime: time-to-collect simulation for the reworked slime pool.

Design aid for docs/SLIME-ECONOMY.md, not game code. It models one server second by second:
the fountain (spawn interval, wild cap, lifetimes, rarity weights, pity, Slime Rain), N players
who walk to the plaza, grab the best slime they may catch and carry it home, the 3-slime merge
vat with recipes (MergeRecipes.resolve as designed), stealing, rebirth unlocks and the boss event.
It tracks one player ("you") and reports when each species, tier and Dex milestone is reached.

Run:  python slime_economy_sim.py [--runs 24] [--hours 60] [--scenario all|proposed|...] [--out results.md]
Only the standard library is used. Species come from shared/modeling-kit/models/pool/*.json.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import statistics
from dataclasses import dataclass, field, replace
from pathlib import Path

HERE = Path(__file__).resolve().parent
POOL = HERE.parents[3] / "shared" / "modeling-kit" / "models" / "pool"

# ---------------------------------------------------------------- design data (mirrors SLIME-ECONOMY.md)

TIER_NAMES = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]

# Family per spawning species; the family opens at FAMILY_RANK rebirths (Config.REBIRTH_TIERS[i].family).
FAMILY = {
    # meadow: open from the start. "sprout" is the roster.json id; the doc renames it to "sprig" (old-id clash).
    "gummy": "meadow", "mochi": "meadow", "bubbles": "meadow", "pebble": "meadow",
    "bumble": "meadow", "mushie": "meadow", "froggo": "meadow",
    "whiskers": "meadow", "lop": "meadow", "moo": "meadow",
    "blaze": "meadow", "octo": "meadow", "king": "meadow", "cosmo": "meadow", "midas": "meadow",
    # orchard ("Garden" in the new look), rank 3
    "sprout": "orchard", "cheddar": "orchard", "prickles": "orchard", "flan": "orchard",
    # frost ("Frost & Sea"), rank 6
    "chomp": "frost", "pengoo": "frost", "frostbite": "frost", "zap": "frost", "ninja": "frost",
    # starlight, rank 10
    "imp": "starlight", "drako": "starlight", "robo": "starlight", "seraph": "starlight",
    "amethyst": "starlight", "prism": "starlight", "eclipse": "starlight", "boo": "starlight",
}
FAMILY_RANK = {"meadow": 0, "orchard": 3, "frost": 6, "starlight": 10}

# Hybrid -> its three input species (a multiset, all one tier T); the hybrid is tier T + 1.
RECIPES = {
    "soda": ("bubbles", "gummy", "mochi"),
    "rocky_road": ("cheddar", "mochi", "pebble"),
    "bloom": ("bumble", "mushie", "prickles"),
    "honey_toad": ("bumble", "flan", "froggo"),
    "truffle": ("flan", "flan", "mushie"),
    "moo_shroom": ("lop", "moo", "moo"),
    "snow_bunny": ("lop", "lop", "pengoo"),
    "catfish": ("chomp", "pengoo", "whiskers"),
    "sushi": ("chomp", "chomp", "pengoo"),
    "steam": ("blaze", "frostbite", "zap"),
    "kraken": ("octo", "octo", "zap"),
    "thunderbee": ("imp", "zap", "zap"),
    "dragon_king": ("king", "king", "king"),
    "cyber_ninja": ("ninja", "ninja", "robo"),
    "nightwing": ("cosmo", "seraph", "seraph"),
}
HYBRID_TIER = {  # result tier; checked against the input tier below
    "soda": 2, "rocky_road": 2, "bloom": 3, "honey_toad": 3, "truffle": 3, "moo_shroom": 4,
    "snow_bunny": 4, "catfish": 4, "sushi": 4, "steam": 5, "kraken": 5, "thunderbee": 5,
    "dragon_king": 6, "cyber_ninja": 6, "nightwing": 7,
}
BOSSES = {"goozilla": 6, "queen_jelly": 6, "klawdius": 6, "pumpking": 6, "mecha_goo": 7, "goomancer": 7}
BOSS_ROTATION = ["goozilla", "queen_jelly", "klawdius", "pumpking", "mecha_goo",
                 "goozilla", "queen_jelly", "klawdius", "pumpking", "goomancer"]


def load_species() -> dict[str, int]:
    roster = json.loads((POOL / "roster.json").read_text(encoding="utf-8"))
    tiers = {s["id"]: int(s["tier"]) for s in roster}
    missing = set(tiers) ^ set(FAMILY)
    assert not missing, f"FAMILY and roster.json disagree: {sorted(missing)}"
    hybrids = json.loads((POOL / "hybrids.json").read_text(encoding="utf-8"))
    hybrid_ids = {h["id"] for h in hybrids if h.get("kind") == "hybrid"}
    assert hybrid_ids == set(RECIPES), f"RECIPES and hybrids.json disagree: {sorted(hybrid_ids ^ set(RECIPES))}"
    for hid, parents in RECIPES.items():
        t = {tiers[p] for p in parents}
        assert len(t) == 1, f"{hid}: parents span tiers {t}"
        assert t.pop() + 1 == HYBRID_TIER[hid], f"{hid}: tier mismatch"
    keys = [tuple(sorted(p)) for p in RECIPES.values()]
    assert len(keys) == len(set(keys)), "two recipes share one input set"
    return tiers


SPECIES_TIER = load_species()
SPAWNING = sorted(SPECIES_TIER)
RECIPE_BY_KEY = {tuple(sorted(p)): h for h, p in RECIPES.items()}
ALL_DEX = SPAWNING + sorted(RECIPES) + sorted(BOSSES)

# ---------------------------------------------------------------- scenario


@dataclass
class Scenario:
    name: str
    text: str
    weights: tuple = (52, 28, 13, 5.2, 1.45, 0.35, 0.1)  # Config.RARITIES weights today
    spawn_interval: float = 4.0
    wild_cap: int = 18
    wild_lifetime: float = 115.0
    players: int = 6  # average occupancy of an 8-slot server
    other_ranks: tuple = (0, 1, 3, 5, 8)  # rebirths of the other players (a mixed server)
    # Played hours at which "you" reach rebirth 1, 2, 3, ... (assumption, see the doc).
    rebirth_hours: tuple = (0.5, 1.2, 2.2, 3.5, 5, 7, 9, 11.5, 14, 17, 20.5, 24, 28, 32, 36)  # REBIRTH_HOURS
    walk_out: float = 10.0  # plot -> plaza
    carry_base: float = 14.0  # plaza -> plot while carrying, before the tier slow-down
    carry_per_tier: float = 1.5
    activity: float = 0.6  # share of the time spent on the grab loop (the rest: locking, defending, shop, AFK)
    steals_per_hour: float = 2.0  # successful steals per player per hour
    pity_epic: int = 30
    pity_legendary: int = 300
    rain_interval: float = 3600
    rain_first: float = 300
    rain_duration: float = 180
    rain_spawn_interval: float = 4.0
    rain_wild_cap_mult: float = 2.0
    rain_luck: float = 5.0
    boss_first: float = 480
    boss_interval: float = 1200
    boss_shower: int = 6  # wild slimes the boss sheds in the fight (3 sheds x 2, luck x3)
    merge_jump: float = 0.2
    jump_max_tier: int = 6  # a +2 jump may land at most here (today: anything below Secret)
    merge_max_tier: int = 7  # a random (non-recipe) merge result is at most this tier (today: Mythic x3 -> Secret)
    merge_assist: float = 0.0  # chance a random merge result is a species you don't have yet
    pads: int = 8
    veteran: bool = False  # someone with 10+ rebirths keeps the fountain at tier 4 all session


REBIRTH_HOURS = (0.5, 1.2, 2.2, 3.5, 5, 7, 9, 11.5, 14, 17, 20.5, 24, 28, 32, 36)
PROPOSED = Scenario(
    "proposed",
    "Recommended rules: weights 52/28/13/5.2/1.2/0.2/0.05, merge jumps stop at Legendary, random merges stop at "
    "Mythic (Secret is never a random merge), 35 % merge assist, boss every 20 min, 6 players, mixed ranks.",
    weights=(52, 28, 13, 5.2, 1.2, 0.2, 0.05),
    merge_assist=0.35,
    jump_max_tier=5,
    merge_max_tier=6,
)
SCENARIOS = {
    "proposed": PROPOSED,
    "today_rules": Scenario(
        "today_rules",
        "Today's odds and vat (52/28/13/5.2/1.45/0.35/0.1, +2 jumps up to Mythic, Mythic x3 -> Secret, no assist), "
        "on the new pool with the proposed families, recipes and boss so only the odds differ.",
    ),
    "no_assist": replace(PROPOSED, name="no_assist", text="Proposed, without the merge assist (random merges are uniform).", merge_assist=0.0),
    "casual": replace(
        PROPOSED,
        name="casual",
        text="Proposed rules, casual player: 35 % activity, 0.5 steals/h, rebirths take twice as long.",
        activity=0.35,
        steals_per_hour=0.5,
        rebirth_hours=tuple(h * 2 for h in REBIRTH_HOURS),
    ),
    "full_server": replace(
        PROPOSED,
        name="full_server",
        text="Proposed rules on a full 8-player server (more players chasing the same spawns).",
        players=8,
        other_ranks=(0, 1, 2, 3, 5, 8, 12),
    ),
    "veteran_server": replace(
        PROPOSED,
        name="veteran_server",
        text="Proposed rules; a 10+ rebirth player keeps the fountain at Starlight, so species you can't catch yet "
        "take part of your drops (you can still steal them).",
        other_ranks=(0, 2, 5, 8, 12),
        veteran=True,
    ),
    "quiet_server": replace(
        PROPOSED,
        name="quiet_server",
        text="Proposed rules with only 2 players on the server: little competition, so the 18-slime wild cap binds.",
        players=2,
        other_ranks=(3,),
    ),
    "no_rank_gate": replace(
        PROPOSED,
        name="no_rank_gate",
        text="Proposed odds, but every family is open from the first minute (what the rebirth gate is worth).",
        rebirth_hours=(0.0,) * 10 + REBIRTH_HOURS[10:],
    ),
}

# ---------------------------------------------------------------- model


@dataclass
class Slime:
    tier: int
    species: str
    keep: bool = False  # hybrids: never fed to a random merge, sold last


@dataclass
class Player:
    pid: int
    rank: int
    tracked: bool = False
    dex: dict = field(default_factory=dict)  # species -> first time (s)
    source: dict = field(default_factory=dict)  # species -> how it was first found
    inv: list = field(default_factory=list)  # slimes on pads
    trophies: set = field(default_factory=set)  # boss species on the trophy stand (no pad, can't be stolen)
    ready_at: float = 0.0
    carrying: Slime | None = None
    deposit_at: float = 0.0
    catches: int = 0
    merges: int = 0
    steals: int = 0

    def unlocked(self, species: str) -> bool:
        fam = FAMILY.get(species)
        return fam is None or self.rank >= FAMILY_RANK[fam]


class Sim:
    def __init__(self, sc: Scenario, seed: int):
        self.sc = sc
        self.rng = random.Random(seed)
        self.t = 0.0
        self.wild: dict[int, tuple] = {}  # id -> (Slime, expires)
        self.next_id = 0
        self.pity_epic = 0
        self.pity_leg = 0
        self.spawns = 0
        self.boss_count = 0
        you = Player(0, 0, tracked=True)
        self.players = [you] + [Player(i + 1, r) for i, r in enumerate(sc.other_ranks[: sc.players - 1])]
        self.you = you

    # -- fountain
    def fountain_ranks(self) -> int:
        if self.sc.veteran:
            return 10
        return max(p.rank for p in self.players)

    def raining(self) -> bool:
        if self.t < self.sc.rain_first:
            return False
        return (self.t - self.sc.rain_first) % self.sc.rain_interval < self.sc.rain_duration

    def roll_tier(self, luck: float) -> int:
        min_tier = 1
        if self.pity_leg + 1 >= self.sc.pity_legendary:
            min_tier = 5
        elif self.pity_epic + 1 >= self.sc.pity_epic:
            min_tier = 4
        weights = []
        for i, w in enumerate(self.sc.weights):
            tier = i + 1
            w = w * luck if tier >= 3 else w
            weights.append(0 if tier < min_tier else w)
        r = self.rng.random() * sum(weights)
        for i, w in enumerate(weights):
            r -= w
            if r < 0:
                return i + 1
        return len(weights)

    def spawn(self, luck: float):
        tier = self.roll_tier(luck)
        self.pity_epic = 0 if tier >= 4 else self.pity_epic + 1
        self.pity_leg = 0 if tier >= 5 else self.pity_leg + 1
        best = self.fountain_ranks()
        pool = [s for s in SPAWNING if SPECIES_TIER[s] == tier and best >= FAMILY_RANK[FAMILY[s]]]
        species = self.rng.choice(pool)
        slime = Slime(tier, species)
        self.wild[self.next_id] = (slime, self.t + self.sc.wild_lifetime)
        self.next_id += 1
        self.spawns += 1

    # -- player actions
    def record(self, p: Player, s: Slime, how: str):
        if s.species not in p.dex:
            p.dex[s.species] = self.t
            p.source[s.species] = how

    def pick(self, p: Player) -> int | None:
        best_id, best_score = None, -1
        for wid, (s, _) in self.wild.items():
            if not p.unlocked(s.species):
                continue  # FountainTiers.catchBlock
            # A species you lack is worth about two tiers (a new Common beats a known Rare, not a known Epic).
            score = s.tier * 10 + (25 if s.species not in p.dex else 0)
            if p.tracked and s.species in self.wanted(p):
                score += 25  # chasing an input of a recipe you know
            if score > best_score:
                best_id, best_score = wid, score
        return best_id

    def known_recipes(self, p: Player) -> list[str]:
        # A recipe is "known" (shown in full in the Dex) once every input species is in your Dex.
        return [h for h, parts in RECIPES.items() if h not in p.dex and all(x in p.dex for x in parts)]

    def target_recipe(self, p: Player) -> list[str]:
        # The player works on one known recipe at a time: the lowest-tier one (ties by id).
        known = self.known_recipes(p)
        return sorted(known, key=lambda h: (HYBRID_TIER[h], h))[:1]

    def wanted(self, p: Player) -> set:
        # Input species of known recipes that you don't hold enough of yet.
        out = set()
        for h in self.target_recipe(p):
            for sp in set(RECIPES[h]):
                held = sum(1 for s in p.inv if s.species == sp)
                if held < RECIPES[h].count(sp):
                    out.add(sp)
        return out

    def take(self, p: Player, parts: tuple) -> list[Slime] | None:
        picked, pool = [], [s for s in p.inv if not s.keep]
        for sp in parts:
            match = next((s for s in pool if s.species == sp and s not in picked), None)
            if match is None:
                return None
            picked.append(match)
        return picked

    def merge_result(self, p: Player, inputs: list[Slime]) -> Slime:
        tier = inputs[0].tier
        hybrid = RECIPE_BY_KEY.get(tuple(sorted(s.species for s in inputs)))
        if hybrid:
            return Slime(HYBRID_TIER[hybrid], hybrid, keep=True)
        out = min(tier + 1, self.sc.merge_max_tier)
        if tier + 2 <= self.sc.jump_max_tier and self.rng.random() < self.sc.merge_jump:
            out = tier + 2
        pool = [s for s in SPAWNING if SPECIES_TIER[s] == out and p.unlocked(s)]
        missing = [s for s in pool if s not in p.dex]
        if missing and self.rng.random() < self.sc.merge_assist:
            pool = missing
        return Slime(out, self.rng.choice(pool))

    def do_merges(self, p: Player):
        while True:
            done = False
            if p.tracked:
                for h in self.known_recipes(p):
                    parts = self.take(p, RECIPES[h])
                    if parts:
                        self.apply_merge(p, parts, "recipe")
                        done = True
                        break
            if done:
                continue
            reserved = []
            if p.tracked:
                for h in self.target_recipe(p):
                    reserved.extend(RECIPES[h])
            for tier in range(1, 7):
                spares = [s for s in p.inv if s.tier == tier and not s.keep]
                keep_back = list(reserved)
                free = []
                for s in spares:
                    if s.species in keep_back:
                        keep_back.remove(s.species)
                    else:
                        free.append(s)
                if len(free) >= 3:
                    self.apply_merge(p, free[:3], "merge")
                    done = True
                    break
            if not done:
                return

    def apply_merge(self, p: Player, inputs: list[Slime], how: str):
        for s in inputs:
            p.inv.remove(s)
        child = self.merge_result(p, inputs)
        p.merges += 1
        p.inv.append(child)
        self.record(p, child, "recipe" if child.species in RECIPES else how)

    def trim(self, p: Player):
        reserved = set()
        if p.tracked:
            for h in self.target_recipe(p):
                reserved.update(RECIPES[h])
        while len(p.inv) > self.sc.pads:
            loose = [s for s in p.inv if not s.keep and s.species not in reserved]
            loose = loose or [s for s in p.inv if not s.keep] or p.inv
            loose.sort(key=lambda s: s.tier)
            p.inv.remove(loose[0])  # sold

    def deposit(self, p: Player, s: Slime, how: str):
        p.inv.append(s)
        self.record(p, s, how)
        self.do_merges(p)
        self.trim(p)

    def steal(self, thief: Player):
        victims = [v for v in self.players if v is not thief and v.inv]
        if not victims:
            return
        v = self.rng.choice(victims)
        loot = v.inv  # hybrids can be stolen like any slime; boss trophies are not on pads
        s = max(loot, key=lambda x: x.tier) if self.rng.random() < 0.5 else self.rng.choice(loot)
        v.inv.remove(s)
        thief.steals += 1
        self.deposit(thief, s, "steal")

    def rebirth(self, p: Player):
        p.rank += 1
        if p.inv:
            best = max(p.inv, key=lambda s: s.tier)
            p.inv = [best]

    def boss(self):
        kind = BOSS_ROTATION[self.boss_count % len(BOSS_ROTATION)]
        self.boss_count += 1
        if BOSSES[kind] == 7 and self.fountain_ranks() < 10:
            kind = "goozilla"
        # Team fight, then a carry race: modelled as an even chance for every player on the server.
        winner = self.rng.choice(self.players)
        winner.trophies.add(kind)
        self.record(winner, Slime(BOSSES[kind], kind), "boss")
        for _ in range(self.sc.boss_shower):
            self.spawn(self.sc.rain_luck)

    # -- main loop
    def run(self, hours: float) -> dict:
        sc, rng = self.sc, self.rng
        end = hours * 3600
        next_spawn, next_boss = 0.0, sc.boss_first
        steal_rate = sc.steals_per_hour / 3600
        reb = list(sc.rebirth_hours)
        dt = 1.0
        while self.t < end:
            t = self.t
            while reb and t >= reb[0] * 3600:
                reb.pop(0)
                self.rebirth(self.you)
            for wid in [w for w, (_, exp) in self.wild.items() if exp <= t]:
                del self.wild[wid]
            rain = self.raining()
            if t >= next_spawn:
                next_spawn = t + (sc.rain_spawn_interval if rain else sc.spawn_interval)
                if len(self.wild) < (int(sc.wild_cap * sc.rain_wild_cap_mult) if rain else sc.wild_cap):
                    self.spawn(sc.rain_luck if rain else 1.0)
            if t >= next_boss:
                next_boss = t + sc.boss_interval
                self.boss()
            order = self.players[:]
            rng.shuffle(order)
            for p in order:
                if p.carrying is not None and t >= p.deposit_at:
                    s, p.carrying = p.carrying, None
                    p.catches += 1
                    self.deposit(p, s, "wild")
                    p.ready_at = t + sc.walk_out / sc.activity
                if p.carrying is None and t >= p.ready_at:
                    wid = self.pick(p)
                    if wid is None:
                        p.ready_at = t + 3
                    else:
                        s, _ = self.wild.pop(wid)
                        p.carrying = s
                        p.deposit_at = t + (sc.carry_base + sc.carry_per_tier * s.tier) / sc.activity
                if rng.random() < steal_rate * dt:
                    self.steal(p)
            self.t += dt
        return self.report(hours)

    def report(self, hours: float) -> dict:
        you = self.you
        return {
            "dex": dict(you.dex),
            "source": dict(you.source),
            "catches_per_h": you.catches / hours,
            "merges_per_h": you.merges / hours,
            "steals_per_h": you.steals / hours,
            "spawns_per_h": self.spawns / hours,
        }


# ---------------------------------------------------------------- reporting


def hours(x):
    return x / 3600


def fmt(v, cap):
    return f"{v:.1f}" if v is not None and v <= cap else f">{cap:.0f}"


def quantile(values, q, cap):
    vals = sorted(v if v is not None else math.inf for v in values)
    i = min(len(vals) - 1, max(0, int(round(q * (len(vals) - 1)))))
    v = vals[i]
    return None if v == math.inf else v


def summarize(sc: Scenario, results: list[dict], hours_cap: float) -> str:
    lines = [f"### `{sc.name}`", "", sc.text, ""]
    n = len(results)
    sp = statistics.mean(r["spawns_per_h"] for r in results)
    lines.append(
        f"Runs: {n} x {hours_cap:.0f} h. Spawns/h on the server: {sp:.0f}. You: "
        f"{statistics.mean(r['catches_per_h'] for r in results):.0f} catches/h "
        f"({100 * statistics.mean(r['catches_per_h'] for r in results) / sp:.0f} % of spawns), "
        f"{statistics.mean(r['merges_per_h'] for r in results):.1f} merges/h, "
        f"{statistics.mean(r['steals_per_h'] for r in results):.1f} steals/h."
    )
    lines += ["", "| Goal | median h | p90 h |", "|---|---:|---:|"]

    def goal(label, fn):
        vals = [fn(r) for r in results]
        med, p90 = quantile(vals, 0.5, hours_cap), quantile(vals, 0.9, hours_cap)
        lines.append(f"| {label} | {fmt(med, hours_cap)} | {fmt(p90, hours_cap)} |")

    def first_of(r, ids):
        ts = [r["dex"][s] for s in ids if s in r["dex"]]
        return hours(min(ts)) if ts else None

    def all_of(r, ids):
        if any(s not in r["dex"] for s in ids):
            return None
        return hours(max(r["dex"][s] for s in ids))

    for tier in range(1, 8):
        ids = [s for s in SPAWNING if SPECIES_TIER[s] == tier]
        goal(f"first {TIER_NAMES[tier - 1]}", lambda r, ids=ids: first_of(r, ids))
    for tier in range(1, 8):
        ids = [s for s in SPAWNING if SPECIES_TIER[s] == tier]
        goal(f"all {len(ids)} {TIER_NAMES[tier - 1]}", lambda r, ids=ids: all_of(r, ids))
    for count in (10, 20, 32):
        goal(
            f"{count} spawning species",
            lambda r, c=count: hours(sorted(r["dex"][s] for s in SPAWNING if s in r["dex"])[c - 1])
            if sum(s in r["dex"] for s in SPAWNING) >= c
            else None,
        )
    goal("first hybrid", lambda r: first_of(r, list(RECIPES)))
    goal("all 15 hybrids", lambda r: all_of(r, list(RECIPES)))
    goal(f"all {len(BOSSES)} bosses", lambda r: all_of(r, list(BOSSES)))
    goal(f"full Dex ({len(ALL_DEX)})", lambda r: all_of(r, ALL_DEX))

    lines += ["", "<details><summary>Per species: median hours to first catch, and how it was first found</summary>", ""]
    lines += ["| Species | Tier | Family | median h | p90 h | wild / merge / steal / recipe / boss |", "|---|---|---|---:|---:|---|"]
    for s in ALL_DEX:
        vals = [hours(r["dex"][s]) if s in r["dex"] else None for r in results]
        srcs = [r["source"].get(s) for r in results]
        mix = " / ".join(str(sum(x == k for x in srcs)) for k in ("wild", "merge", "steal", "recipe", "boss"))
        tier = SPECIES_TIER.get(s) or HYBRID_TIER.get(s) or BOSSES.get(s)
        fam = FAMILY.get(s, "hybrid" if s in RECIPES else "boss")
        lines.append(
            f"| {s} | {TIER_NAMES[tier - 1]} | {fam} | {fmt(quantile(vals, 0.5, hours_cap), hours_cap)} | "
            f"{fmt(quantile(vals, 0.9, hours_cap), hours_cap)} | {mix} |"
        )
    lines += ["", "</details>", ""]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=24)
    ap.add_argument("--hours", type=float, default=60)
    ap.add_argument("--scenario", default="all")
    ap.add_argument("--out", default=str(HERE / "results.md"))
    args = ap.parse_args()
    names = list(SCENARIOS) if args.scenario == "all" else args.scenario.split(",")
    parts = [
        "# Slime economy sim: results",
        "",
        f"Generated by `slime_economy_sim.py --runs {args.runs} --hours {args.hours:.0f}` (seeds 1..{args.runs}). "
        "Hours are played hours of the tracked player. `>N` = not reached within the run in that share of runs.",
        "",
    ]
    for name in names:
        sc = SCENARIOS[name]
        results = [Sim(sc, seed).run(args.hours) for seed in range(1, args.runs + 1)]
        text = summarize(sc, results, args.hours)
        print(text.split("<details>")[0])
        parts.append(text)
    Path(args.out).write_text("\n".join(parts), encoding="utf-8")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
