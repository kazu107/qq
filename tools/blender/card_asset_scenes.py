"""Editable, effect-specific card action scenes for production families C01-C13.

The first six approved illustrations are deliberately not included here. Geometry
helpers are imported read-only; these scenes never reuse a rendered card texture.
"""

from __future__ import annotations

import hashlib
import math
import random

import bpy
from mathutils import Vector

import build_art_vertical_slice as base
import card_action_scenes as actions


PROTECTED = {"quick_slash", "guard", "delay_step", "repair_burst", "auto_turret", "event_horizon"}
FAMILIES = {
    "C01": "strike heavy_swing bleed_cut execution rupture_strike self_tuning_edge axiom_sever spark_jab hammer_feint recycler_claw execution_matrix".split(),
    "C02": "weak_shot assault interrupt_shot tripwire meteor_crash bulwark_cannon marking_dart".split(),
    "C03": "quick_guard barrier_deploy fortify bastion_drive mirror_aegis entropy_armor prism_guard".split(),
    "C04": "haste_focus time_buy time_flow_control stasis_field chronostasis entropy_reversal zero_hour timer_hook chrono_blackout epoch_breaker absolute_zero".split(),
    "C05": "reload recirculate over_reload overclock_routine grit_reload".split(),
    "C06": "purge_pulse brace_patch field_medic phoenix_circuit deus_ex_machina".split(),
    "C07": "blood_chain blood_siphon rust_cloud rupture_mark blood_moon_protocol".split(),
    "C08": "sequence_loader crisis_drone_swarm drone_foundry tactical_mirror recursive_protocol".split(),
    "C09": "adrenaline_link aegis_ram barrier_overdrive capacitor_step reactor_leech recursive_battery quantum_exchange".split(),
    "C10": "paradox_loop grave_protocol final_archive golden_ratio".split(),
    "C11": "phase_lance null_cascade rift_volley phase_zip gravity_snare singularity_guard worldline_collapse".split(),
    "C12": "omega_ray solar_verdict citadel_prime seraph_array omega_sanctuary crown_of_thorns".split(),
    "C13": "atlas_protocol ragnarok_engine infinity_arsenal tempest_choir last_bastion dominion_pulse chronicle_sovereign".split(),
    "SPECIAL": ["environment_fatigue"],
}

# Explicit art direction, not interchangeable seeded prop arrangements.
# Each tuple defines background, subject/action, framing and primary effect color.
RECIPES = {
    "strike": ("ruins", "armored fist drives a straight blade through a broken breastplate", "diagonal_right", "amber"),
    "heavy_swing": ("quarry", "two-handed hammer crushes stone into airborne fragments", "low_left", "amber"),
    "bleed_cut": ("rain", "serrated saber opens a red fissure in steel armor", "diagonal_left", "red"),
    "execution": ("citadel", "descending guillotine cleaves an already damaged red-lit target", "portrait", "red"),
    "rupture_strike": ("forge", "hydraulic cleaver bursts a cracked armor plate", "low_right", "red"),
    "self_tuning_edge": ("workshop", "blade polishes itself against a moving grinding arm", "close_left", "cyan"),
    "axiom_sever": ("white_ruins", "segmented greatsword cuts a geometric lattice in two", "diagonal_right", "amber"),
    "spark_jab": ("rain", "short electrode rapier discharges into a metal opponent", "close_right", "cyan"),
    "hammer_feint": ("desert", "hammer feint leaves a ghost swing beside the real impact", "diagonal_left", "amber"),
    "recycler_claw": ("scrapyard", "recycling claw tears armor into a return chute", "low_left", "green"),
    "execution_matrix": ("archive", "three converging blades sever hostile casting conduits", "portrait", "red"),
    "weak_shot": ("desert", "small pistol strikes an enemy actuator with a weakening bolt", "close_left", "amber"),
    "assault": ("ruins", "heavy blaster thrusts forward through a barricade", "low_right", "red"),
    "interrupt_shot": ("observatory", "precision bolt ruptures an enemy spell mechanism", "diagonal_right", "cyan"),
    "tripwire": ("forest", "taut ground wire catches a moving mechanical leg", "ground", "amber"),
    "meteor_crash": ("cosmic", "burning meteor descends onto a shattered exposed target", "high_left", "red"),
    "bulwark_cannon": ("citadel", "collapsed shield charge feeds a fortress cannon blast", "low_left", "cyan"),
    "marking_dart": ("garden", "dart pins an open targeting reticle onto armor", "close_right", "red"),
    "quick_guard": ("rain", "wrist buckler snaps open against an incoming bolt", "close_left", "cyan"),
    "barrier_deploy": ("desert", "three anchors unfold a broad battlefield energy wall", "wide", "cyan"),
    "fortify": ("citadel", "reinforced gate closes behind overlapping shield layers", "portrait", "cyan"),
    "bastion_drive": ("ruins", "tracked shield plough braces forward through rubble", "low_right", "amber"),
    "mirror_aegis": ("observatory", "reflective shield produces a sword-shaped counter echo", "diagonal_left", "cyan"),
    "entropy_armor": ("forge", "adaptive armor sphere grows new plates around its core", "portrait", "amber"),
    "prism_guard": ("white_ruins", "faceted shield expels dark weakening and slowing particles", "close_right", "green"),
    "haste_focus": ("observatory", "focusing lens draws an allied blade forward along a rail", "diagonal_left", "cyan"),
    "time_buy": ("market", "brass clock lever adds track lengths ahead of enemy weapons", "low_right", "amber"),
    "time_flow_control": ("reservoir", "split switch pulls blue actions forward and red actions backward", "wide", "cyan"),
    "stasis_field": ("garden", "clock dome arrests a blade amid suspended falling leaves", "portrait", "cyan"),
    "chronostasis": ("cathedral", "closed chrono gate locks gears and hostile weapons in place", "portrait", "amber"),
    "entropy_reversal": ("scrapyard", "reversing turbine forces enemy blades back up a conveyor", "diagonal_right", "red"),
    "zero_hour": ("observatory", "midnight clock strikes as reversed rails recoil from its core", "portrait", "amber"),
    "timer_hook": ("ship", "chain hook drags an enemy blade back as an allied pulley advances", "diagonal_left", "cyan"),
    "chrono_blackout": ("night", "eclipsed clock inverts both red and blue timeline streams", "wide", "purple"),
    "epoch_breaker": ("quarry", "hammer shatters a giant schedule wheel and casting needles", "diagonal_right", "amber"),
    "absolute_zero": ("snow", "frost binds a stopped clock and enemy rail inside icy gates", "portrait", "cyan"),
    "reload": ("workshop", "gauntlet seats a fresh cartridge in an open revolver cylinder", "close_left", "amber"),
    "recirculate": ("reservoir", "spent cartridge returns through a circular copper recirculation tube", "portrait", "cyan"),
    "over_reload": ("factory", "multiple magazines feed a high-speed loading rotor", "low_right", "amber"),
    "overclock_routine": ("forge", "dual timing governors accelerate beneath a shielding canopy", "wide", "red"),
    "grit_reload": ("scrapyard", "worn gauntlet hand-cranks a loader behind a small shield", "close_right", "amber"),
    "purge_pulse": ("reservoir", "medical cleansing gate washes away two harmful residues", "portrait", "green"),
    "brace_patch": ("forest", "two armored hands press a ceramic patch onto damaged armor", "close_left", "green"),
    "field_medic": ("ruins", "medical drone repairs a wounded arm with twin treatment tools", "low_right", "green"),
    "phoenix_circuit": ("garden", "winged repair circuit reignites a cracked heart with new green growth", "portrait", "amber"),
    "deus_ex_machina": ("cathedral", "large emergency automaton cleanses repairs and dispatches a shield", "wide", "green"),
    "blood_chain": ("night", "red chain links tear into an already bleeding breastplate", "diagonal_right", "red"),
    "blood_siphon": ("reservoir", "twin-chamber pump draws red energy into a green repair reservoir", "close_left", "red"),
    "rust_cloud": ("scrapyard", "corrosion canister sprays rust over gears and an enemy limb", "ground", "amber"),
    "rupture_mark": ("rain", "red wound and targeting mark overlap on shattered armor", "close_right", "red"),
    "blood_moon_protocol": ("night", "blood moon directs three wound rays onto an exposed target", "portrait", "red"),
    "sequence_loader": ("factory", "assembly arm dispatches a freshly tuned blade along a loading track", "low_left", "cyan"),
    "crisis_drone_swarm": ("ruins", "four rescue shield drones surround a cracked low-power core", "wide", "cyan"),
    "drone_foundry": ("forge", "two blade drones emerge while a shield is upgraded by welding arms", "low_right", "amber"),
    "tactical_mirror": ("observatory", "mirror copies a tactical mechanism into a faster second echo", "diagonal_left", "cyan"),
    "recursive_protocol": ("factory", "self-returning attack mechanism travels around a feedback rail", "portrait", "amber"),
    "adrenaline_link": ("garden", "paired active cells drive a clock turbine and rapid reload rotor", "diagonal_right", "green"),
    "aegis_ram": ("citadel", "shield capacitor discharges into a piston battering ram", "close_left", "cyan"),
    "barrier_overdrive": ("forge", "draining shield tanks power a twin acceleration turbine", "low_right", "cyan"),
    "capacitor_step": ("ship", "charged armored boot launches forward from a shield cell", "ground", "cyan"),
    "reactor_leech": ("scrapyard", "heat leech splits consumed shielding into a strike and repair stream", "diagonal_left", "red"),
    "recursive_battery": ("factory", "nested batteries replenish shielding in a self-feeding circuit", "portrait", "cyan"),
    "quantum_exchange": ("cosmic", "central prism converts blue shield energy into red damage and green repairs", "wide", "purple"),
    "paradox_loop": ("observatory", "three blade echoes orbit an amplifying infinity rail", "portrait", "purple"),
    "grave_protocol": ("cathedral", "sealed preservation casket restores a frame and releases a shield", "low_left", "green"),
    "final_archive": ("archive", "combat records feed weapon refinement and a dispatched shield", "diagonal_right", "amber"),
    "golden_ratio": ("white_ruins", "precision compass guides a growing blade through a golden spiral", "portrait", "amber"),
    "phase_lance": ("white_ruins", "long spear penetrates three phase gates and exposes armor", "diagonal_right", "purple"),
    "null_cascade": ("night", "descending null pulses hit armor and drag the schedule behind it", "portrait", "purple"),
    "rift_volley": ("cosmic", "three cannon bolts pass through a torn spatial seam", "diagonal_left", "purple"),
    "phase_zip": ("ship", "armored courier slips through a short portal toward a reload exit", "low_right", "cyan"),
    "gravity_snare": ("quarry", "gravitational chains pin an enemy clock and pull it backward", "ground", "purple"),
    "singularity_guard": ("cosmic", "dense black core supports a shielding shell and two stopped clocks", "portrait", "cyan"),
    "worldline_collapse": ("cosmic", "red and blue rails fold into a cracked gravitational rift", "wide", "purple"),
    "omega_ray": ("cathedral", "solar cannon concentrates a white-gold beam into exposed armor", "diagonal_left", "amber"),
    "solar_verdict": ("desert", "sun wheel projects a descending judgment blade onto a weak target", "high_left", "amber"),
    "citadel_prime": ("white_ruins", "ceramic citadel unfolds a shield around a green recovery chamber", "low_right", "cyan"),
    "seraph_array": ("cosmic", "three winged shield drones advance in a protective formation", "wide", "cyan"),
    "omega_sanctuary": ("garden", "sanctuary opens its recovery capsule behind a shield and stopped clock", "portrait", "green"),
    "crown_of_thorns": ("night", "barbed crown surrounds a shield and launches red wound thorns", "portrait", "red"),
    "atlas_protocol": ("citadel", "titan frame raises a shield globe with deck-wide upgrade conduits", "low_left", "cyan"),
    "ragnarok_engine": ("forge", "siege furnace fires while a feedback wheel feeds its growing cannon", "low_right", "red"),
    "infinity_arsenal": ("archive", "endless armory dispatches twin swords and shields from a refinement furnace", "wide", "amber"),
    "tempest_choir": ("rain", "four lightning probes follow a conductor toward a weakened target", "diagonal_right", "cyan"),
    "last_bastion": ("ruins", "fortress wall consumes a shield tank and retaliates with its cannon", "low_left", "amber"),
    "dominion_pulse": ("citadel", "command scepter strengthens a blue knight and suppresses a red opponent", "wide", "amber"),
    "chronicle_sovereign": ("archive", "archive throne rewrites weapon records and dispatches a phase courier", "portrait", "amber"),
    "environment_fatigue": ("desert", "third-party hourglass breaks open as ascending clock weights strike both sides", "portrait", "amber"),
}

ENV_COLORS = {
    "ruins": ((0.018, 0.033, 0.05), (0.16, 0.19, 0.24)),
    "quarry": ((0.032, 0.042, 0.052), (0.27, 0.24, 0.19)),
    "rain": ((0.014, 0.035, 0.07), (0.13, 0.23, 0.30)),
    "citadel": ((0.03, 0.043, 0.060), (0.18, 0.23, 0.29)),
    "forge": ((0.035, 0.016, 0.008), (0.29, 0.10, 0.035)),
    "workshop": ((0.032, 0.043, 0.047), (0.16, 0.21, 0.23)),
    "factory": ((0.022, 0.037, 0.043), (0.13, 0.19, 0.22)),
    "white_ruins": ((0.13, 0.16, 0.18), (0.48, 0.51, 0.45)),
    "desert": ((0.14, 0.06, 0.027), (0.45, 0.29, 0.14)),
    "scrapyard": ((0.025, 0.027, 0.018), (0.19, 0.16, 0.073)),
    "archive": ((0.014, 0.029, 0.052), (0.083, 0.15, 0.22)),
    "observatory": ((0.009, 0.018, 0.045), (0.06, 0.12, 0.24)),
    "forest": ((0.009, 0.038, 0.025), (0.11, 0.21, 0.073)),
    "cosmic": ((0.004, 0.006, 0.020), (0.065, 0.054, 0.14)),
    "garden": ((0.036, 0.089, 0.049), (0.23, 0.32, 0.11)),
    "market": ((0.053, 0.038, 0.026), (0.24, 0.17, 0.09)),
    "reservoir": ((0.010, 0.057, 0.067), (0.11, 0.25, 0.25)),
    "cathedral": ((0.018, 0.020, 0.044), (0.14, 0.12, 0.23)),
    "ship": ((0.020, 0.04, 0.076), (0.15, 0.25, 0.31)),
    "night": ((0.006, 0.012, 0.027), (0.073, 0.09, 0.16)),
    "snow": ((0.047, 0.093, 0.15), (0.34, 0.47, 0.54)),
}
FRAMES = {
    "diagonal_right": ((1.6, -8.7, 3.4), (0.0, 0, 1.50), 4.65, -5),
    "diagonal_left": ((-1.5, -8.5, 3.1), (0.0, 0, 1.45), 4.65, 6),
    "low_left": ((-2.0, -9.0, 2.7), (0.0, 0, 1.50), 4.75, 0),
    "low_right": ((1.8, -8.8, 2.9), (0.0, 0, 1.40), 4.70, -3),
    "portrait": ((0.5, -9.5, 3.05), (0.0, 0, 1.55), 4.30, 0),
    "close_left": ((-0.8, -8.4, 3.5), (0.0, 0, 1.42), 4.10, 3),
    "close_right": ((1.0, -8.4, 3.5), (0.0, 0, 1.42), 4.10, -4),
    "wide": ((0.2, -10, 3.8), (0.0, 0, 1.43), 5.20, 0),
    "ground": ((1.6, -8.5, 4.9), (0.0, 0, 1.10), 4.65, -3),
    "high_left": ((-1.4, -9.4, 4.8), (0.0, 0, 1.55), 5.0, 5),
}


class Kit:
    """Named, editable parts; reuse is recorded with each scene's semantic recipe."""

    def __init__(self, card):
        self.card = card
        self.id = card["id"]
        self.family = next(key for key, ids in FAMILIES.items() if self.id in ids)
        self.recipe = RECIPES[self.id]
        self.rng = random.Random(int(hashlib.sha256(self.id.encode()).hexdigest()[:8], 16))
        self.c = base.make_collection("CARD_" + self.id)
        self.m = base.MATERIALS
        self.accent = self.recipe[3]
        self.reused = set()
        self.n = 0

    def name(self, label):
        self.n += 1
        return f"{self.id}__{label}__{self.n:03d}"

    def mat(self, key):
        return self.m[key] if isinstance(key, str) else key

    def box(self, label, p, dim, material="gunmetal", rot=(0, 0, 0), bevel=0.045):
        return base.add_box(self.c, self.name(label), p, dim, self.mat(material), rotation_degrees=rot, bevel=bevel)

    def rod(self, label, start, end, radius=0.05, material="steel"):
        return base.add_rod_between(self.c, self.name(label), start, end, radius, self.mat(material), vertices=24)

    def tube(self, label, pts, radius=0.035, material="brass", cyclic=False):
        return base.add_curve(self.c, self.name(label), pts, radius, self.mat(material), cyclic=cyclic)

    def sphere(self, label, p, scale, material="steel"):
        return base.add_sphere(self.c, self.name(label), p, scale, self.mat(material))

    def cylinder(self, label, p, radius, depth, material="steel", rot=(90, 0, 0), vertices=48):
        return base.add_cylinder(self.c, self.name(label), p, radius, depth, self.mat(material), rotation_degrees=rot, vertices=vertices)

    def ring(self, label, p, r, thickness=0.055, material="brass", rot=(90, 0, 0)):
        return base.add_torus(self.c, self.name(label), p, r, thickness, self.mat(material), rotation_degrees=rot)

    def profile(self, label, pts, p, material="steel", thick=0.1, rot=(0, 0, 0)):
        return base.add_profile(self.c, self.name(label), pts, thick, self.mat(material), location=p, rotation_degrees=rot)

    def bolt_ring(self, p, r, count=12):
        base.add_radial_bolts(self.c, self.name("Precision_fasteners"), p, r, count, self.m["brass_edge"], bolt_radius=0.035)

    def debris(self, center, material="steel", count=14, radius=0.75):
        self.reused.add("fractured_armor_shards")
        for i in range(count):
            p = Vector(center) + Vector((self.rng.uniform(-radius, radius), self.rng.uniform(-0.4, 0.3), self.rng.uniform(-radius, radius)))
            actions.shard(base, self.c, self.name("Flying_fragment"), p, self.rng.uniform(0.035, 0.12), self.mat(material), self.rng)

    def sparks(self, p, material=None, r=0.5, count=9):
        actions.burst(base, self.c, p, self.mat(material or self.accent), radius=r, count=count, seed=self.rng.randrange(100000))

    def hand(self, wrist, elbow, pale=True):
        self.reused.add("segmented_armored_gauntlet")
        actions.gauntlet(base, self.c, self.name("Armored_hand"), wrist, elbow, pale=pale)

    def sword(self, p, angle=35, size=1.5, kind="blade", accent=None):
        self.reused.add("weapon_" + kind)
        name = self.name(kind)
        root = base.add_sword(self.c, name, p, (0, angle, 0), accent=self.mat(accent or self.accent))
        root.scale = (size, size, size)
        if kind in {"greatsword", "cleaver"}:
            root.scale.x *= 2.2
        if kind == "serrated":
            for i in range(9):
                tooth = base.add_profile(self.c, self.name("Serration"), [(0, 0), (0.16, 0.08), (0, 0.17)], 0.07, self.m["steel_edge"], location=(0.10, 0, -0.18 + i * 0.13), parent=root, bevel=0.008)
        if kind == "electrode":
            for z in (0.2, 0.55, 0.85):
                base.add_torus(self.c, self.name("Insulator_band"), (0, 0, z), 0.125, 0.035, self.m["ceramic_light"], parent=root)
        if kind == "segmented":
            for z in (0.08, 0.35, 0.62, 0.9):
                base.add_box(self.c, self.name("Blade_segment"), (0, -0.07, z), (0.35, 0.12, 0.12), self.m["ceramic_light"], parent=root)
        return root

    def hammer(self, p, angle=40, size=1):
        self.reused.add("weapon_piston_hammer")
        before = set(self.c.objects)
        self.rod("Hammer_shaft", (0, 0, -1.1), (0, 0, 0.8), 0.095, "steel")
        self.box("Hammer_head", (0, 0, 0.86), (1.25, 0.60, 0.70), "gunmetal", bevel=0.09)
        for x in (-0.63, 0.63):
            self.box("Hammer_striking_face", (x, 0, 0.86), (0.1, 0.65, 0.75), "brass", bevel=0.05)
        for x in (-0.4, 0, 0.4):
            self.box("Hammer_energy_vent", (x, -0.32, 0.86), (0.10, 0.05, 0.35), self.accent, bevel=0.015)
        self.assembly(before, p, (0, angle, 0), size)

    def assembly(self, before, p, rot=(0, 0, 0), size=1):
        root = base.add_empty(self.c, self.name("Assembly"), p, rot)
        root.scale = (size,) * 3
        for obj in set(self.c.objects) - before - {root}:
            if obj.parent is None:
                obj.parent = root
        return root

    def shield(self, p, size=1, material="cyan_soft", shape="kite"):
        self.reused.add("shield_" + shape)
        if shape == "round":
            self.cylinder("Buckler_outer_rim", p, size, 0.17, "steel")
            self.cylinder("Buckler_energy_face", (p[0], p[1] - 0.11, p[2]), size * 0.83, 0.05, material)
            self.bolt_ring((p[0], p[1] - 0.16, p[2]), size * 0.91, 10)
            self.sphere("Buckler_center_boss", (p[0], p[1] - 0.20, p[2]), (size * 0.4, 0.2, size * 0.4), "brass")
        else:
            pts = [(-0.9, 0.8), (0.9, 0.8), (0.75, -0.4), (0, -1.0), (-0.75, -0.4)]
            if shape == "tower":
                pts = [(-0.6, 1), (0.6, 1), (0.8, 0.7), (0.7, -0.9), (-0.7, -0.9), (-0.8, 0.7)]
            self.profile("Shield_outer", [(x * size, z * size) for x, z in pts], p, "steel", 0.19)
            self.profile("Shield_layer", [(x * size * 0.83, z * size * 0.83) for x, z in pts], (p[0], p[1] - 0.14, p[2]), material, 0.12)
            for i in range(3):
                self.box("Shield_panel_rib", (p[0] + (i - 1) * size * 0.37, p[1] - 0.23, p[2]), (0.05, 0.05, size * 1.1), "brass_edge", bevel=0.015)

    def target(self, p, damaged=False):
        self.reused.add("target_breastplate")
        base.add_target_plate(self.c, self.name("Opponent_armor"), p)
        if damaged:
            self.tube("Damage_fissure", [(p[0] - 0.3, p[1] - 0.24, p[2] + 0.65), (p[0] + 0.1, p[1] - 0.26, p[2] + 0.2), (p[0] - 0.06, p[1] - 0.26, p[2] - 0.3), (p[0] + 0.4, p[1] - 0.24, p[2] - 0.7)], 0.025, "red")

    def clock(self, p, r=0.75, stopped=False):
        self.reused.add("chrono_clock")
        base.add_clock_face(self.c, self.name("Clock"), p, r, self.mat(self.accent))
        self.bolt_ring((p[0], p[1] - 0.05, p[2]), r * 1.08, 12)
        if stopped:
            for x in (-0.18, 0.18):
                self.box("Clock_brake", (p[0] + x, p[1] - 0.3, p[2]), (0.10, 0.08, r * 0.9), "ceramic_light")

    def cell(self, p, size=1, color="cyan", empty=False):
        self.reused.add("energy_cell")
        self.cylinder("Cell_casing", p, 0.28 * size, 1.1 * size, "gunmetal", rot=(0, 0, 0))
        for z in (-0.48, 0.48):
            self.ring("Cell_collar", (p[0], p[1], p[2] + z * size), 0.28 * size, 0.05 * size, "brass", rot=(0, 0, 0))
        for i in range(4):
            self.box("Cell_charge_window", (p[0], p[1] - 0.28 * size, p[2] + (-0.30 + i * 0.2) * size), (0.28 * size, 0.06, 0.1 * size), "black" if empty and i > 0 else color, bevel=0.015)
        for x in (-0.22, 0.22):
            self.rod("Cell_reinforcing_rod", (p[0] + x * size, p[1] - 0.12, p[2] - 0.50 * size), (p[0] + x * size, p[1] - 0.12, p[2] + 0.50 * size), 0.022, "steel")

    def core(self, p, r=0.6, color=None):
        self.reused.add("reactor_core")
        self.cylinder("Core_backplate", p, r, 0.26, "gunmetal")
        self.ring("Core_housing", (p[0], p[1] - 0.15, p[2]), r * 0.94, 0.09, "brass")
        self.sphere("Core_energy", (p[0], p[1] - 0.21, p[2]), (r * 1.1, 0.32, r * 1.1), color or self.accent)
        self.bolt_ring((p[0], p[1] - 0.22, p[2]), r * 0.92, 10)

    def gun(self, p, size=1, cannon=False, fired=True):
        self.reused.add("weapon_cannon" if cannon else "weapon_blaster")
        before = set(self.c.objects)
        self.box("Receiver", (0, 0, 0), (1.3, 0.62, 0.58), "gunmetal", bevel=0.085)
        self.box("Receiver_ceramic_panel", (-0.2, -0.34, 0.05), (0.75, 0.08, 0.36), "ceramic_light")
        for x in (-0.45, -0.15, 0.15):
            self.box("Receiver_cooling_slot", (x, -0.39, 0.06), (0.08, 0.02, 0.20), "black", bevel=0.01)
        self.rod("Barrel", (0.55, 0, 0.12), (1.4 if cannon else 1.0, 0, 0.12), 0.22 if cannon else 0.12, "steel")
        for x in (0.65, 0.90, 1.14 if cannon else 0.92):
            self.ring("Barrel_band", (x, 0, 0.12), 0.24 if cannon else 0.14, 0.035, "brass", rot=(0, 90, 0))
        self.box("Weapon_grip", (-0.45, 0, -0.42), (0.23, 0.28, 0.65), "leather", rot=(0, 15, 0))
        self.box("Sight_rail", (0, 0, 0.4), (0.8, 0.10, 0.08), "brass")
        self.cylinder("Scope", (0, 0, 0.58), 0.095, 0.6, "steel", rot=(0, 90, 0))
        if fired:
            self.profile("Muzzle_burst", [(1.1, 0.12), (1.45, 0.30), (1.34, 0.14), (1.8, 0.14), (1.38, 0.0), (1.1, 0.12)], (0, -0.05, 0), self.accent, 0.035)
        return self.assembly(before, p, (0, -8, 0), size)

    def drone(self, p, size=0.7, role="shield", wing=False):
        self.reused.add("drone_" + role)
        before = set(self.c.objects)
        self.sphere("Drone_body", (0, 0, 0), (0.85, 0.55, 0.65), "ceramic_light")
        self.ring("Drone_equator", (0, 0, 0), 0.4, 0.055, "gunmetal", rot=(0, 0, 0))
        self.sphere("Drone_sensor", (0, -0.31, 0.02), (0.23, 0.08, 0.23), "green" if role == "medic" else self.accent)
        for side in (-1, 1):
            self.rod("Drone_arm", (side * 0.25, 0, 0), (side * 0.66, 0, -0.22), 0.065, "steel")
            if wing:
                for j in range(4):
                    self.profile("Mechanical_wing_feather", [(0, 0), (side * (0.5 + j * 0.08), 0.25 + j * 0.15), (side * 0.72, -0.08), (0, -0.1)], (side * 0.34, 0.1 + j * 0.035, 0.10), "ceramic_light", 0.045)
            else:
                self.ring("Drone_fan", (side * 0.62, 0.08, 0.22), 0.22, 0.045, "brass", rot=(0, 0, 0))
        if role == "shield":
            self.shield((0, -0.35, -0.40), 0.43)
        elif role == "blade":
            self.sword((0, -0.3, -0.43), -70, 0.60)
        elif role == "medic":
            self.cross((0, -0.36, -0.4), 0.30)
        else:
            self.rod("Probe_electrode", (0, -0.2, -0.20), (0, -0.2, -0.7), 0.045, "steel")
        return self.assembly(before, p, (0, -12, 0), size)

    def cross(self, p, size=0.4):
        self.box("Medical_vertical", p, (size * 0.28, 0.08, size), "green", bevel=0.012)
        self.box("Medical_horizontal", (p[0], p[1] - 0.015, p[2]), (size, 0.08, size * 0.28), "green", bevel=0.012)

    def flow(self, start, end, color=None, bend=0.45):
        start, end = Vector(start), Vector(end)
        mid = (start + end) * 0.5 + Vector((0, -bend, bend))
        obj = self.tube("Directed_energy_flow", [start, mid, end], 0.03, color or self.accent)
        obj.data.splines[0].bezier_points[0].radius = 0.3
        obj.data.splines[0].bezier_points[-1].radius = 0.6
        return obj

    def rail(self, start, end, color=None, backward=False):
        self.reused.add("timeline_track")
        a, b = Vector(start), Vector(end)
        direction = (b - a).normalized()
        cross = Vector((-direction.z, 0, direction.x))
        for side in (-1, 1):
            self.rod("Timeline_rail", a + cross * 0.09 * side, b + cross * 0.09 * side, 0.032, "steel")
        for i in range(10):
            p = a.lerp(b, i / 9)
            self.rod("Rail_crossbar", p - cross * 0.15, p + cross * 0.15, 0.018, "brass")
        p = a.lerp(b, 0.6)
        d = direction * (-1 if backward else 1)
        self.tube("Direction_chevron", [p - d * 0.2 + cross * 0.13, p, p - d * 0.2 - cross * 0.13], 0.035, color or self.accent)

    def hexfield(self, p, r=1, color="cyan_soft", filled=True):
        pts = [(p[0] + math.sin(i * math.tau / 6) * r, p[1], p[2] + math.cos(i * math.tau / 6) * r) for i in range(6)]
        self.tube("Hexagonal_barrier_rim", pts, 0.035, "cyan", cyclic=True)
        if filled:
            self.profile("Hexagonal_barrier_surface", [(x - p[0], z - p[2]) for x, y, z in pts], p, color, 0.018)

    def gear(self, p, r=0.55, color="brass", broken=False):
        self.reused.add("chrono_gear")
        self.ring("Gear_web", p, r * 0.72, r * 0.15, color)
        self.cylinder("Gear_hub", p, r * 0.22, 0.20, "steel")
        for i in range(14):
            if broken and 3 <= i <= 6:
                continue
            angle = i * math.tau / 14
            self.box("Gear_tooth", (p[0] + math.sin(angle) * r, p[1], p[2] + math.cos(angle) * r), (r * 0.20, 0.16, r * 0.24), color, rot=(0, math.degrees(angle), 0), bevel=0.016)
        for i in range(5):
            a = i * math.tau / 5
            self.rod("Gear_spoke", p, (p[0] + math.sin(a) * r * 0.65, p[1], p[2] + math.cos(a) * r * 0.65), r * 0.055, color)

    def backdrop(self):
        env = self.recipe[0]
        dark, light = ENV_COLORS[env]
        light = tuple(min(0.65, c * self.rng.uniform(0.82, 1.17)) for c in light)
        actions.backdrop(base, self.c, self.name("Atmosphere_" + env), dark, light, scale=self.rng.uniform(1.2, 3.8))
        stone = base.make_material(self.name("Weathered_environment"), (*light, 1), roughness=0.88, bump_strength=0.18)
        if env not in {"cosmic", "night"}:
            self.box("World_ground_not_pedestal", (0, 1, -0.28), (30, 30, 0.18), stone, bevel=0)
        if env in {"ruins", "white_ruins", "citadel", "cathedral", "rain"}:
            for i, x in enumerate((-3.0, -1.7, 1.9, 3.2)):
                z = 1.7 + self.rng.uniform(-0.5, 0.5)
                self.box("Distant_masonry", (x, 2.6 + i * 0.2, z), (0.4 + i % 2 * 0.25, 0.6, 4.5), stone, bevel=0.06)
                for j in range(4):
                    self.box("Masonry_joint", (x, 2.22 + i * 0.2, j * 0.9), (0.65, 0.04, 0.04), "gunmetal", bevel=0.003)
            if env in {"cathedral", "citadel"}:
                self.tube("Distant_arch", [(-2.4, 3.2, 1.2), (-2.0, 3.2, 3.5), (0, 3.2, 4.5), (2.0, 3.2, 3.5), (2.4, 3.2, 1.2)], 0.19, stone)
        if env in {"forest", "garden"}:
            bark = base.make_material(self.name("Bark"), (0.03, 0.07, 0.028, 1), roughness=1)
            leaf = base.make_material(self.name("Leaves"), (0.08, 0.20, 0.035, 1), roughness=0.95)
            for i in range(7):
                x = i * 0.9 - 2.9
                self.cylinder("Tree_trunk", (x, 3, 1.8), self.rng.uniform(0.07, 0.16), 6, bark, rot=(0, self.rng.uniform(-7, 7), 0), vertices=12)
                actions.shard(base, self.c, self.name("Canopy"), (x, 2.8, 3.6), 1.0, leaf, self.rng)
            for i in range(13):
                p = (self.rng.uniform(-3, 3), self.rng.uniform(1, 3), self.rng.uniform(0, 0.2))
                self.rod("Grass_stem", p, (p[0] + 0.08, p[1], p[2] + self.rng.uniform(0.15, 0.42)), 0.01, leaf)
        if env in {"forge", "factory", "workshop", "scrapyard", "reservoir", "ship"}:
            for i in range(4):
                x = i * 1.4 - 2.2
                self.box("Rear_structure", (x, 2.8, 1), (0.75, 0.65, 2.4 + i % 2), "gunmetal", bevel=0.06)
                self.rod("Rear_conduit", (x, 2.2, 0), (x, 2.2, 3.3), 0.055, "brass")
                self.box("Rear_window", (x, 2.38, 1.6), (0.36, 0.02, 0.65), "amber" if env == "forge" else "cyan_soft")
            if env == "ship":
                for i in range(7):
                    self.box("Deck_plank", (i * 0.7 - 2.1, 0.8, -0.14), (0.64, 5, 0.06), "leather", bevel=0.01)
        if env in {"quarry", "desert", "snow", "scrapyard"}:
            for i in range(14):
                p = (self.rng.uniform(-4, 4), self.rng.uniform(2, 4), self.rng.uniform(-0.2, 0.5))
                actions.shard(base, self.c, self.name("World_rock"), p, self.rng.uniform(0.2, 0.8), stone, self.rng)
        if env in {"archive", "market"}:
            for x in (-2.4, 2.4):
                self.box("Shelving_upright", (x, 2.7, 1.7), (0.16, 0.5, 4), "brass")
                for z in (0.4, 1.3, 2.2, 3.1):
                    self.box("Shelving_level", (x, 2.7, z), (1.4, 0.6, 0.09), "gunmetal")
                    for j in range(4):
                        self.box("Archive_cartridge", (x - 0.5 + j * 0.32, 2.6, z + 0.3), (0.18, 0.35, 0.5), "ceramic" if j % 2 else "leather")
        if env in {"observatory", "cosmic", "night"}:
            for i in range(35):
                self.sphere("Distant_star", (self.rng.uniform(-5, 5), 3.0, self.rng.uniform(-1, 5)), (0.014,) * 3, "cyan_soft")
            if env == "observatory":
                self.ring("Distant_astrolabe", (0.9, 2.5, 2.9), 1.8, 0.045, "brass")
                self.ring("Distant_astrolabe_oblique", (0.9, 2.5, 2.9), 1.75, 0.035, "steel", rot=(75, 15, 20))
        if env == "rain":
            for i in range(20):
                x, z = self.rng.uniform(-3, 3), self.rng.uniform(0, 4)
                self.tube("Rain_streak", [(x, 1.8, z), (x - 0.08, 1.8, z - 0.35)], 0.006, "cyan_soft")
        if env == "snow":
            for i in range(24):
                self.sphere("Snowflake", (self.rng.uniform(-2.5, 2.5), self.rng.uniform(0.3, 2), self.rng.uniform(0, 3.7)), (0.025,) * 3, "ceramic_light")


def melee(k):
    cid = k.id
    if cid == "heavy_swing":
        k.hammer((-0.2, -0.1, 1.9), 54, 1.15)
        k.hand((-0.95, -0.1, 1.0), (-1.8, 0.2, 0.2), False)
        k.debris((0.85, -0.1, 0.4), "ceramic", 24, 1.2)
        k.sparks((0.7, -0.4, 0.5), r=0.8)
    elif cid in {"execution", "execution_matrix"}:
        k.target((0.10, 0, 1.1), True)
        count = 3 if cid == "execution_matrix" else 1
        for i in range(count):
            x = (i - (count - 1) / 2) * 1.0
            k.profile("Descending_execution_blade", [(-0.48, 0.5), (0.48, 0.5), (0.48, -0.1), (-0.48, -0.7)], (x, -0.40, 2.4), "steel_edge", 0.15)
            k.rod("Execution_guide", (x, 0.15, 1.8), (x, 0.15, 3.4), 0.05, "brass")
            k.flow((x, -0.35, 3.1), (x + 0.1, -0.35, 1.5), "red", 0.1)
        if count == 3:
            for x in (-1.1, 1.1):
                k.clock((x, 0.4, 1.0), 0.38, True)
        k.debris((0.2, -0.2, 1.2), count=16)
    elif cid == "self_tuning_edge":
        k.sword((0.0, -0.25, 1.5), -35, 1.65)
        k.gear((0.45, -0.18, 1.8), 0.55, "steel")
        base.add_robot_arm(k.c, k.name("Polishing_arm"), (-1.4, 0.1, 0.2), (-0.6, 0.1, 1.4), (0.2, -0.1, 1.7), k.mat("cyan"))
        k.sparks((0.2, -0.45, 1.7), "amber", 0.65)
        k.cell((1.3, 0.0, 0.8), 0.6)
    elif cid == "recycler_claw":
        k.core((-0.85, 0.0, 1.5), 0.6, "green")
        for i in range(3):
            x = -0.75 + i * 0.40
            k.tube("Articulated_claw", [(x, 0, 1.7), (x + 0.7, -0.2, 2.5), (x + 1.2, -0.30, 1.55)], 0.10, "steel_edge")
        k.target((0.65, -0.05, 1.0), True)
        k.gear((0.9, -0.4, 0.45), 0.45)
        k.rail((1.7, 0, 0.2), (-1.0, 0, 0.2), "green")
        k.debris((0.4, -0.1, 1.7), count=15)
    elif cid == "hammer_feint":
        k.hammer((-0.35, -0.2, 1.5), 55, 1.0)
        k.tube("Feint_ghost_swing", [(-1.5, 0.1, 2.0), (0, 0, 3.0), (1.5, 0, 1.7)], 0.035, "amber")
        k.clock((1.1, 0.25, 0.9), 0.55)
        k.rail((1.4, -0.3, 0.4), (-0.7, -0.3, 0.5), "red", True)
        k.hand((-1.0, -0.2, 0.9), (-1.8, 0.0, 0.1), False)
    else:
        kind = {"bleed_cut": "serrated", "rupture_strike": "cleaver", "axiom_sever": "segmented", "spark_jab": "electrode"}.get(cid, "blade")
        angle = -46 if cid in {"bleed_cut", "spark_jab"} else 45
        k.sword((-0.25, -0.2, 1.6), angle, 1.65, kind)
        k.hand((-0.85 if angle > 0 else 0.6, -0.10, 0.7), (-1.7 if angle > 0 else 1.65, 0.2, 0.1))
        k.target((0.9 if angle > 0 else -0.95, 0.2, 1.8), cid != "strike")
        k.sparks((0.65 if angle > 0 else -0.55, -0.3, 2.0))
        k.debris((0.8 if angle > 0 else -0.8, -0.05, 1.8), count=14)
        if cid == "axiom_sever":
            for i in range(5):
                k.rod("Severed_axiom_grid", (-1.5, 0.5, 0.5 + i * 0.45), (0.05, 0.5, 0.5 + i * 0.45), 0.019, "amber")
                k.rod("Detached_axiom_grid", (0.35, 0.5, 0.2 + i * 0.45), (1.9, 0.5, 0.2 + i * 0.45), 0.019, "amber")
        if cid == "spark_jab":
            k.clock((1.05, 0.1, 0.50), 0.35)
            k.flow((0.2, -0.4, 2.2), (1.1, -0.2, 0.5), "cyan")
        if cid == "rupture_strike":
            k.cell((-1.1, 0.1, 1.6), 0.7, "red")
            k.rod("Hydraulic_piston", (-0.9, 0, 0.8), (0.0, 0, 2.5), 0.10, "steel")


def ranged(k):
    cid = k.id
    if cid == "tripwire":
        k.box("Caught_boot", (0.25, -0.2, 0.55), (0.66, 0.65, 0.40), "ceramic_light", rot=(0, 18, -10), bevel=0.09)
        k.rod("Enemy_leg", (0.35, 0, 0.7), (0.8, 0.1, 2.1), 0.24, "gunmetal")
        k.box("Enemy_knee", (0.7, -0.2, 1.8), (0.64, 0.18, 0.55), "ceramic")
        for x in (-1.5, 1.5):
            k.box("Tripwire_anchor", (x, 0, 0.35), (0.3, 0.3, 0.5), "brass")
        k.tube("Taut_tripwire", [(-1.5, -0.25, 0.5), (0.3, -0.3, 0.65), (1.5, -0.25, 0.5)], 0.025, "steel_edge")
        k.clock((-0.95, 0.2, 1.35), 0.45)
        k.sparks((0.3, -0.3, 0.65), "amber", 0.3)
    elif cid == "meteor_crash":
        rock = base.make_material(k.name("Meteor_rock"), (0.08, 0.025, 0.012, 1), roughness=0.8, bump_strength=0.45)
        actions.shard(base, k.c, k.name("Falling_meteor"), (-0.25, -0.2, 2.0), 0.85, rock, k.rng)
        for i in range(6):
            k.flow((-1.0 - i * 0.08, 0, 3.7), (0.1 + i * 0.12, -0.1, 1.1), "red", 0.15)
        k.target((0.3, 0.0, 0.8), True)
        k.ring("Meteor_impact_ring", (0.2, 0, 0.15), 1.25, 0.035, "red", rot=(0, 0, 0))
        k.debris((0.3, 0, 0.9), "ceramic", 24, 1.3)
    elif cid == "marking_dart":
        k.target((0.45, 0.05, 1.6), True)
        k.rod("Dart_shaft", (-1.4, -0.55, 2.3), (0.4, -0.35, 1.8), 0.035, "steel_edge")
        k.profile("Dart_fletching", [(-0.2, 0.14), (0.2, 0), (-0.2, -0.14)], (-1.2, -0.4, 2.25), "brass")
        k.ring("Exposed_target_reticle", (0.45, -0.25, 1.6), 0.65, 0.025, "red")
        for i in range(4):
            a = i * math.pi / 2
            k.rod("Reticle_tick", (0.45 + math.cos(a) * 0.55, -0.3, 1.6 + math.sin(a) * 0.55), (0.45 + math.cos(a) * 0.80, -0.3, 1.6 + math.sin(a) * 0.80), 0.025, "red")
    else:
        k.gun((-0.7, -0.2, 1.55), 1.1 if cid in {"assault", "bulwark_cannon"} else 0.85, cid in {"interrupt_shot", "bulwark_cannon"})
        k.hand((-1.1, -0.1, 1.1), (-1.8, 0.2, 0.4), False)
        if cid == "interrupt_shot":
            k.clock((1.35, 0.0, 1.8), 0.6, True)
            k.debris((1.3, 0, 1.8), "brass", 15)
        else:
            k.target((1.4, 0.2, 1.5), True)
        if cid == "bulwark_cannon":
            k.cell((-1.2, 0.1, 0.75), 0.9, "cyan", True)
            k.shield((-1.1, 0.6, 2.3), 0.7)
            k.flow((-1.2, -0.1, 0.8), (-0.3, -0.3, 1.6), "cyan")
        k.sparks((1.2, -0.1, 1.7), r=0.65)
        if cid == "weak_shot":
            k.rod("Failing_target_actuator", (1.3, 0.1, 0.5), (1.4, 0.1, 1.4), 0.10, "steel")
            k.tube("Broken_actuator_cable", [(1.3, -0.1, 1.1), (1.0, -0.2, 0.85), (1.2, -0.15, 0.5)], 0.035, "leather")


def defense(k):
    cid = k.id
    if cid == "quick_guard":
        k.hand((0.2, 0.1, 1.35), (1.6, 0.6, 0.4))
        k.shield((-0.25, -0.25, 1.7), 1.0, shape="round")
        k.flow((-2, -0.1, 2.7), (-0.7, -0.5, 2.0), "amber", 0.1)
        k.sparks((-0.7, -0.5, 2.0), "amber", 0.6)
    elif cid in {"barrier_deploy", "fortify"}:
        count = 3 if cid == "barrier_deploy" else 2
        for i in range(count):
            x = (i - (count - 1) / 2) * 1.15
            k.core((x, 0, 0.5), 0.25, "cyan")
            for side in (-1, 1):
                k.rod("Barrier_anchor", (x, 0, 0.5), (x + side * 0.4, 0, 0.0), 0.06, "steel")
            k.hexfield((x, -0.1, 1.5), 1.0 if count == 3 else 1.25)
        if cid == "fortify":
            for x in (-1.5, 1.5):
                k.box("Reinforced_gate_post", (x, 0.3, 1.55), (0.28, 0.4, 2.9), "steel")
            k.box("Reinforced_gate_lintel", (0, 0.35, 2.95), (3.3, 0.42, 0.3), "brass")
            for i in range(6):
                k.box("Closed_gate_bar", (-1.1 + i * 0.44, 0.35, 1.65), (0.1, 0.14, 2.5), "gunmetal")
    elif cid == "bastion_drive":
        k.shield((0.0, -0.3, 1.75), 1.25, shape="tower")
        for x in (-0.85, 0.85):
            for z in (0.25, 0.55):
                k.cylinder("Tracked_drive_wheel", (x, 0.1, z), 0.25, 0.36, "gunmetal")
            k.rail((x, -1, 0.0), (x, 1, 0.0))
        k.debris((0, -0.4, 0.25), "ceramic", 18, 1.1)
    elif cid == "mirror_aegis":
        k.shield((-0.30, 0, 1.65), 1.15, "steel_edge")
        k.sword((1.1, -0.1, 1.7), -30, 1.15, accent="cyan")
        k.flow((-0.4, -0.4, 1.8), (1.15, -0.4, 1.65), "cyan")
        k.ring("Mirror_reflection_wave", (-0.3, -0.24, 1.65), 0.70, 0.025, "cyan")
    elif cid == "entropy_armor":
        k.core((0, 0.1, 1.5), 0.85, "amber")
        for i in range(9):
            a = i * math.tau / 9
            p = (math.cos(a) * 1.1, -0.1, 1.5 + math.sin(a) * 1.1)
            k.profile("Growing_armor_plate", [(-0.22, 0.28), (0.22, 0.28), (0.28, -0.15), (0, -0.3), (-0.28, -0.15)], p, "ceramic", 0.15, (0, math.degrees(a), 0))
            k.flow(p, (p[0] * 0.75, -0.15, 1.5 + (p[2] - 1.5) * 0.75), "amber", 0.1)
        k.gear((0.0, 0.3, 1.5), 1.4)
    elif cid == "prism_guard":
        k.shield((0, 0.05, 1.6), 1.20, "ceramic_light")
        for i, color in enumerate(("cyan", "green", "amber")):
            k.profile("Prism_barrier_facet", [(-0.35, -0.45), (0, 0.85), (0.40, -0.45)], (-0.45 + i * 0.45, -0.20, 1.5), color, 0.07)
        for side in (-1, 1):
            k.flow((side * 0.3, -0.1, 1.2), (side * 1.5, -0.1, 0.65), "green")
            k.debris((side * 1.5, 0, 0.65), "black", 9, 0.25)


def chrono(k):
    cid = k.id
    if cid == "timer_hook":
        k.clock((-0.9, 0.1, 2.1), 0.7)
        k.sword((1.05, -0.1, 1.25), -35, 1.2, accent="red")
        for i in range(13):
            t = i / 12
            k.ring("Hook_chain_link", (-0.6 + t * 1.9, -0.1, 1.6 - t * 0.4), 0.08, 0.025, "steel", rot=(90 if i % 2 else 0, 0, 0))
        k.tube("Timeline_hook", [(1.0, -0.35, 1.1), (1.4, -0.35, 0.85), (1.55, -0.35, 1.2), (1.35, -0.35, 1.3)], 0.07, "steel")
        k.rail((-1.8, 0.0, 0.35), (0.2, 0.0, 0.35), "cyan")
    elif cid == "epoch_breaker":
        k.gear((0.2, 0.05, 1.6), 1.2, broken=True)
        k.clock((0.2, 0.2, 1.6), 0.7, True)
        k.hammer((-0.7, -0.35, 2.05), 47, 1.1)
        k.debris((0.5, -0.2, 1.9), "brass", 22, 1.1)
        k.sparks((0.5, -0.4, 2.0), "amber", 0.7)
        k.rail((-1.7, 0, 0.2), (1.7, 0, 0.2), "red", True)
    elif cid == "haste_focus":
        k.ring("Focus_lens_housing", (-0.8, 0.1, 1.8), 0.8, 0.12, "brass")
        k.sphere("Focus_convex_lens", (-0.8, 0.08, 1.8), (1.3, 0.16, 1.3), "cyan_soft")
        k.sword((0.8, -0.3, 1.65), 45, 1.45, accent="cyan")
        k.rail((-1.7, 0, 0.4), (1.6, 0, 0.4), "cyan")
        k.flow((-1.3, 0, 1.0), (1.4, -0.3, 2.3), "cyan")
    elif cid == "time_buy":
        k.clock((-0.25, 0.1, 1.8), 1.1)
        k.rod("Time_purchase_lever", (-0.9, -0.4, 0.6), (-1.55, -0.4, 1.6), 0.075, "brass")
        k.sphere("Time_purchase_handle", (-1.55, -0.4, 1.6), (0.23,) * 3, "leather")
        for i in range(3):
            k.cell((0.85 + i * 0.4, 0.1, 0.45), 0.40, "amber")
            k.rail((0.6, 0.2, 0.4 + i * 0.5), (1.7, 0.2, 0.4 + i * 0.5), "red", True)
    else:
        stopped = cid in {"chronostasis", "stasis_field", "absolute_zero"}
        k.clock((0, 0.15, 1.7), 1.12, stopped)
        if cid in {"entropy_reversal", "time_flow_control", "chrono_blackout", "zero_hour"}:
            reverse = cid != "time_flow_control"
            for i, color in enumerate(("red", "cyan")):
                z = 0.28 + i * 0.35
                k.rail((-1.8, -0.3, z), (1.8, -0.3, z + 0.35), color, reverse or color == "red")
                k.sword((-1.3 if color == "red" else 1.3, -0.1, 1.0), -40 if color == "red" else 40, 0.68, accent=color)
            if cid == "entropy_reversal":
                k.gear((1.0, -0.2, 1.6), 0.6, "steel")
            if cid == "chrono_blackout":
                k.cylinder("Clock_eclipse", (0.35, -0.20, 1.85), 0.92, 0.09, "black")
                k.ring("Eclipse_corona", (0.35, -0.25, 1.85), 0.94, 0.025, "purple")
            if cid == "zero_hour":
                k.box("Midnight_striker", (0, -0.3, 3.0), (0.2, 0.2, 0.45), "brass")
                k.sparks((0, -0.4, 2.8), "amber", 0.65)
        elif stopped:
            if cid == "stasis_field":
                for radius in (1.42, 1.5):
                    k.ring("Stasis_dome", (0, -0.08, 1.7), radius, 0.025, "cyan")
                k.sword((-0.7, -0.25, 1.5), 42, 1.05)
                k.debris((0.7, 0, 2.2), "brass", 15)
            else:
                for x in (-1.55, 1.55):
                    k.box("Stopping_gate", (x, 0.25, 1.4), (0.23, 0.3, 2.7), "ceramic_light" if cid == "absolute_zero" else "steel")
                k.box("Gate_crosspiece", (0, 0.25, 2.7), (3.25, 0.30, 0.20), "brass")
                k.rail((-1.7, -0.2, 0.3), (1.7, -0.2, 0.3), "red")
                if cid == "absolute_zero":
                    for i in range(14):
                        x = k.rng.uniform(-1.5, 1.5)
                        k.profile("Ice_shard", [(-0.08, 0), (0, k.rng.uniform(0.3, 0.75)), (0.10, 0)], (x, -0.3, 0.2 + i % 3 * 0.15), "cyan_soft", 0.08)


def reloads(k):
    cid = k.id
    if cid == "overclock_routine":
        for x, color in ((-0.8, "red"), (0.8, "cyan")):
            k.clock((x, 0.0, 1.8), 0.75)
            k.gear((x, 0.15, 0.65), 0.45, "steel")
            k.cell((x, 0.2, 0.9), 0.55, color)
        k.flow((-1.3, -0.2, 0.5), (1.3, -0.2, 0.5), "red", 0.2)
        k.hexfield((0, 0.35, 2.0), 1.25, filled=False)
    elif cid == "recirculate":
        k.ring("Recirculation_loop", (0, 0.1, 1.6), 1.25, 0.13, "brass")
        for i in range(6):
            a = i * math.tau / 6
            k.cell((math.cos(a), 0, 1.6 + math.sin(a)), 0.36, "cyan")
        k.gear((0, 0.0, 1.6), 0.65)
        k.flow((-1.1, -0.2, 0.9), (0.3, -0.2, 2.7), "cyan", 0.2)
    else:
        radius = 0.90 if cid == "over_reload" else 0.80
        k.cylinder("Loading_cylinder", (0, 0.05, 1.7), radius, 0.45, "gunmetal")
        k.ring("Loading_cylinder_rim", (0, -0.19, 1.7), radius, 0.055, "steel_edge")
        for i in range(6):
            a = i * math.tau / 6
            x, z = math.cos(a) * radius * 0.67, 1.7 + math.sin(a) * radius * 0.67
            k.cylinder("Open_cartridge_chamber", (x, -0.21, z), 0.13, 0.06, "black")
            if i < (5 if cid == "over_reload" else 3):
                k.cylinder("Loaded_brass_cartridge", (x, -0.36, z), 0.11, 0.37, "brass_edge")
        k.gear((0, 0.3, 1.7), radius * 1.18)
        k.hand((-0.75, -0.55, 1.7), (-1.7, 0.0, 0.5), False)
        k.cell((-0.7, -0.55, 1.8), 0.55, "amber")
        if cid == "over_reload":
            for x in (-1.5, 1.5):
                for i in range(3):
                    k.box("Incoming_magazine", (x, 0.3, 0.7 + i * 0.6), (0.42, 0.25, 0.5), "ceramic")
                    k.flow((x, 0.1, 0.7 + i * 0.6), (0, 0, 1.5), "amber", 0.1)
        if cid == "grit_reload":
            k.rod("Hand_crank", (0.2, -0.3, 1.8), (0.6, -0.5, 1.0), 0.08, "steel")
            k.rod("Crank_handle", (0.6, -0.5, 1.0), (0.6, -0.8, 1.0), 0.10, "leather")
            k.shield((1.15, 0.05, 1.0), 0.55)


def medicine(k):
    cid = k.id
    if cid == "brace_patch":
        k.target((0, 0.2, 1.5), True)
        k.hand((-0.5, -0.2, 1.55), (-1.9, 0.1, 0.5))
        k.hand((0.5, -0.2, 1.55), (1.8, 0.2, 0.7))
        k.box("Repair_patch", (0, -0.32, 1.6), (0.85, 0.11, 0.75), "ceramic_light", bevel=0.08)
        k.cross((0, -0.4, 1.6), 0.35)
        k.hexfield((0, 0.5, 1.6), 1.1, filled=False)
    elif cid == "purge_pulse":
        k.ring("Purge_gate", (0, 0, 1.6), 1.3, 0.16, "ceramic_light")
        k.target((0, 0.2, 1.6), True)
        k.cross((0, -0.3, 1.75), 0.60)
        for side in (-1, 1):
            k.flow((0, -0.1, 1.6), (side * 1.5, 0, 0.7), "green")
            k.debris((side * 1.5, 0, 0.7), "black", 8, 0.24)
            k.cell((side * 1.3, 0.1, 0.4), 0.50, "green")
    elif cid == "phoenix_circuit":
        k.core((0, 0.0, 1.5), 0.75, "green")
        for side in (-1, 1):
            for i in range(5):
                k.profile("Phoenix_repair_feather", [(0, 0), (side * (0.55 + i * 0.1), 0.9), (side * 0.5, 0.15)], (side * (0.35 + i * 0.12), 0.1 + i * 0.04, 1.5 - i * 0.12), "brass_edge", 0.075)
            k.flow((0, -0.2, 1.5), (side * 1.4, -0.2, 2.4), "green")
        k.debris((0.0, -0.1, 0.6), "ceramic", 12)
        k.cross((0, -0.35, 1.5), 0.40)
    elif cid == "field_medic":
        k.drone((-0.65, -0.1, 2.1), 1.25, "medic")
        k.hand((0.5, 0.0, 0.9), (1.8, 0.2, 0.5))
        k.box("Wounded_arm_patch", (0.95, -0.25, 0.8), (0.80, 0.12, 0.35), "ceramic_light", rot=(0, -15, 0))
        for x in (-0.35, 0.10):
            base.add_robot_arm(k.c, k.name("Medical_treatment_tool"), (-0.65, 0, 1.8), (x, 0, 1.2), (0.9, -0.1, 0.9), k.mat("green"))
        k.flow((-0.2, -0.1, 1.8), (0.9, -0.3, 0.9), "green")
        k.debris((1.4, 0, 1.1), "black", 7, 0.25)
    else:
        k.core((0, 0.2, 1.5), 0.85, "green")
        k.box("Emergency_automaton_torso", (0, 0.4, 1.6), (1.6, 0.65, 1.5), "ceramic_light", bevel=0.15)
        k.cross((0, -0.06, 1.75), 0.65)
        for side in (-1, 1):
            for z in (1.1, 2.0):
                base.add_robot_arm(k.c, k.name("Repair_automaton_arm"), (side * 0.6, 0.3, z), (side * 1.35, 0.0, z + 0.2), (side * 1.6, -0.1, 0.5), k.mat("green"))
                k.cell((side * 1.45, 0.1, 0.5), 0.45, "green")
        k.clock((-1.1, 0, 2.6), 0.45)
        k.shield((1.25, -0.25, 2.45), 0.62)
        k.rail((0.5, 0.0, 0.25), (1.8, 0, 0.75), "cyan")


def blood(k):
    cid = k.id
    if cid == "blood_siphon":
        k.cell((-1.0, 0, 1.3), 1.5, "red")
        k.cell((1.0, 0, 1.3), 1.5, "green")
        k.core((0, 0.05, 1.4), 0.48, "red")
        k.tube("Siphon_intake", [(-1, -0.1, 1.9), (-0.8, -0.35, 2.6), (0, -0.2, 1.6)], 0.10, "brass")
        k.tube("Siphon_repair_outlet", [(0, -0.1, 1.4), (0.8, -0.3, 0.6), (1.0, -0.1, 0.8)], 0.10, "brass")
        k.flow((-1.0, -0.4, 1.7), (1, -0.4, 1.3), "green")
        k.cross((1.0, -0.4, 2.1), 0.34)
    elif cid == "rust_cloud":
        k.cell((-0.8, -0.1, 1.0), 1.35, "amber")
        k.rod("Corrosion_nozzle", (-0.75, 0, 1.7), (0.2, -0.1, 2.0), 0.13, "brass")
        rust = base.make_material(k.name("Rust_particles"), (0.22, 0.065, 0.015, 1), roughness=1)
        for i in range(30):
            p = (k.rng.uniform(0.1, 1.45), k.rng.uniform(-0.25, 0.05), k.rng.uniform(0.9, 2.2))
            actions.shard(base, k.c, k.name("Corrosion_cloud"), p, k.rng.uniform(0.06, 0.16), rust, k.rng)
        k.target((1.2, 0.2, 1.2), True)
        k.gear((1.0, 0.1, 0.4), 0.40, "brass")
    else:
        k.target((0.4 if cid != "blood_moon_protocol" else 0, 0.1, 1.2), True)
        if cid == "blood_chain":
            for i in range(16):
                t = i / 15
                k.ring("Blood_chain_link", (-1.7 + t * 3.0, -0.2, 2.7 - math.sin(t * math.pi) * 1.6), 0.12, 0.037, "red", rot=(90 if i % 2 else 30, 0, 0))
            k.cell((-1.2, 0.1, 0.8), 0.85, "red")
        elif cid == "rupture_mark":
            k.ring("Double_wound_mark", (0.4, -0.21, 1.2), 0.73, 0.030, "red")
            k.sword((-0.6, -0.3, 1.7), 42, 1.3, "serrated", "red")
            k.flow((0.45, -0.3, 1.65), (0.3, -0.3, 0.6), "red", 0.1)
        else:
            k.cylinder("Blood_moon_disc", (0, 0.35, 2.65), 0.95, 0.15, "red")
            k.cylinder("Blood_moon_shadow", (0.25, 0.20, 2.75), 0.8, 0.12, "black")
            for x in (-0.8, 0, 0.8):
                k.flow((x * 0.6, -0.1, 2.4), (x, -0.1, 0.9), "red", 0.1)
            k.ring("Exposed_wound_ring", (0, -0.3, 1.2), 0.60, 0.035, "red")
        k.debris((0.3, 0, 1.0), "red", 12)


def automation(k):
    cid = k.id
    if cid == "crisis_drone_swarm":
        k.core((0, 0, 1.15), 0.65, "red")
        k.tube("Critical_core_crack", [(-0.3, -0.3, 1.5), (0.1, -0.3, 1.1), (-0.05, -0.3, 0.8)], 0.035, "red")
        for i, p in enumerate(((-1.2, 0, 2.4), (1.2, 0, 2.4), (-1.4, -0.1, 0.9), (1.4, -0.1, 0.9))):
            k.drone(p, 0.85, "shield")
            k.flow(p, (0, -0.2, 1.2), "cyan", 0.1)
    elif cid == "tactical_mirror":
        k.profile("Tactical_mirror", [(-0.6, -1), (0.6, -1), (0.85, 1), (-0.85, 1)], (0, 0.4, 1.65), "steel_edge", 0.10)
        for x in (-1.15, 1.15):
            k.core((x, -0.05, 1.45), 0.50, "cyan")
            k.clock((x, -0.1, 0.6), 0.35)
        k.flow((-0.8, -0.2, 1.5), (0.8, -0.2, 1.5), "cyan", 0.25)
        k.gear((0, 0.4, 2.85), 0.40)
    elif cid == "recursive_protocol":
        k.ring("Recursive_return_track", (0, 0.1, 1.6), 1.3, 0.10, "steel")
        k.gun((0, -0.15, 1.2), 0.8)
        for i in range(3):
            a = i * math.tau / 3
            k.gear((math.sin(a) * 1.05, 0.15, 1.6 + math.cos(a) * 1.05), 0.26)
        k.flow((1.3, -0.1, 1.5), (-0.2, -0.1, 2.75), "amber", 0.15)
    else:
        k.rail((-1.8, 0, 0.30), (1.8, 0, 0.75), "cyan")
        base.add_robot_arm(k.c, k.name("Factory_assembly_arm"), (-1.5, 0.5, 0.3), (-0.85, 0.3, 2.5), (0.15, 0, 1.85), k.mat("amber"))
        if cid == "sequence_loader":
            k.sword((0.3, -0.2, 1.8), 45, 1.55)
            k.gear((-0.7, -0.1, 1.25), 0.40)
            k.sparks((0.2, -0.25, 1.8), "amber", 0.4)
        else:
            for p in ((-0.1, -0.1, 2.2), (1.1, -0.15, 1.65)):
                k.drone(p, 1.0, "blade")
            k.shield((-0.95, -0.05, 1.0), 0.6)
            k.sparks((-0.6, -0.1, 1.4), "amber", 0.5)
            k.cell((1.4, 0.25, 0.50), 0.55, "amber")


def conversion(k):
    cid = k.id
    if cid == "capacitor_step":
        k.box("Armored_boot_sole", (0.3, -0.15, 0.65), (1.35, 0.7, 0.20), "gunmetal", rot=(0, -12, 0))
        k.box("Armored_boot_upper", (0.0, -0.1, 1.0), (0.80, 0.64, 0.65), "ceramic_light", rot=(0, -12, 0), bevel=0.10)
        k.rod("Charged_leg", (-0.1, 0, 1.3), (-0.4, 0, 2.5), 0.25, "steel")
        k.cell((-1.0, 0.1, 0.75), 0.75)
        k.rail((-1.7, 0, 0.3), (1.7, 0, 0.3), "cyan")
        k.flow((-1, -0.2, 0.8), (0.8, -0.2, 0.65), "cyan", 0.3)
    elif cid == "aegis_ram":
        k.cell((-1.15, 0.1, 1.25), 1.2, "cyan", True)
        k.rod("Ram_piston", (-0.65, 0.0, 1.25), (1.0, 0, 1.25), 0.23, "steel")
        k.box("Ram_striking_head", (1.0, 0, 1.25), (0.40, 0.80, 0.9), "brass", bevel=0.07)
        for x in (-0.4, -0.1, 0.2):
            k.ring("Ram_pressure_band", (x, 0, 1.25), 0.28, 0.035, "brass", rot=(0, 90, 0))
        k.target((1.5, 0.2, 1.3), True)
        k.sparks((1.3, -0.1, 1.3), "cyan", 0.75)
    elif cid == "recursive_battery":
        for i in range(3):
            k.cell((-0.95 + i * 0.85, 0.1 + i * 0.14, 1.5 + i * 0.3), 1.25 - i * 0.15, "cyan")
        k.ring("Battery_feedback_bus", (0, 0.4, 1.65), 1.4, 0.07, "brass")
        k.shield((0, -0.3, 0.55), 0.65)
        k.flow((1.2, -0.1, 1.3), (-1.0, -0.1, 1.3), "cyan", 0.2)
    elif cid == "quantum_exchange":
        k.profile("Conversion_prism", [(-0.6, -0.7), (0.7, -0.7), (0.2, 0.95)], (0, -0.1, 1.6), "ceramic_light", 0.50)
        k.cell((-1.3, 0, 1.7), 1.1, "cyan", True)
        k.sword((1.25, 0, 2.1), 25, 1.15, accent="red")
        k.cell((0.7, 0.0, 0.55), 0.75, "green")
        k.clock((-0.7, 0, 0.5), 0.40)
        for start, end, color in (((-1.3, -0.2, 1.7), (0, -0.3, 1.5), "cyan"), ((0, -0.3, 1.5), (1.2, -0.2, 2.0), "red"), ((0, -0.3, 1.4), (0.7, -0.2, 0.7), "green")):
            k.flow(start, end, color, 0.1)
    else:
        k.core((0, 0.15, 1.6), 0.72, "red" if cid == "reactor_leech" else "cyan")
        for side in (-1, 1):
            k.cell((side * 1.15, 0, 1.4), 1.1, "green" if cid == "adrenaline_link" else "cyan", cid in {"reactor_leech", "barrier_overdrive"})
            k.tube("Power_feed_pipe", [(side * 1.1, -0.2, 1.0), (side * 0.8, -0.1, 0.5), (0, -0.1, 1.3)], 0.09, "brass")
        if cid == "reactor_leech":
            k.sword((-0.65, -0.2, 2.3), 30, 0.9, accent="red")
            k.cross((1.05, -0.25, 2.3), 0.48)
            k.flow((0, -0.3, 1.7), (1.05, -0.25, 2.3), "green")
        else:
            for x in (-0.75, 0.75):
                k.gear((x, 0.0, 0.6), 0.45, "steel")
            k.clock((0, -0.05, 2.75), 0.50)
            k.rail((-1.5, -0.2, 0.2), (1.5, -0.2, 0.2), "cyan")


def archives(k):
    cid = k.id
    if cid == "paradox_loop":
        pts = []
        for i in range(81):
            t = i * math.tau / 80
            pts.append((1.6 * math.cos(t) / (1 + math.sin(t) ** 2), 0.15, 1.7 + 1.1 * math.sin(t) * math.cos(t) / (1 + math.sin(t) ** 2)))
        k.tube("Infinity_recursion_rail", pts, 0.07, "brass", True)
        for x, angle in ((-1, -35), (0, 0), (1, 35)):
            k.sword((x, -0.25, 1.7), angle, 0.9, accent="purple")
        k.gear((0, 0.35, 0.6), 0.45)
    elif cid == "golden_ratio":
        k.sword((0, -0.2, 1.5), 25, 1.8, "segmented", "amber")
        spiral = []
        for i in range(80):
            t = i / 79
            a = t * math.tau * 1.7
            r = 0.15 + t * 1.55
            spiral.append((math.cos(a) * r, 0.25, 1.5 + math.sin(a) * r))
        k.tube("Golden_growth_spiral", spiral, 0.024, "brass_edge")
        k.rod("Precision_compass_leg", (-1.3, 0, 0.4), (0, 0, 2.8), 0.065, "brass")
        k.rod("Precision_compass_leg", (1.1, 0, 0.7), (0, 0, 2.8), 0.065, "brass")
        k.gear((0, 0, 2.8), 0.25)
    elif cid == "grave_protocol":
        k.profile("Preservation_casket", [(-0.55, -1), (0.55, -1), (0.78, 0.4), (0.5, 1.1), (-0.5, 1.1), (-0.78, 0.4)], (0, 0.1, 1.6), "gunmetal", 0.55)
        k.cross((0, -0.3, 2.0), 0.55)
        k.cell((-1.2, 0, 1.3), 1.1, "green")
        k.shield((1.2, -0.05, 1.8), 0.75)
        k.flow((-1.2, -0.1, 1.3), (0, -0.3, 1.5), "green")
        k.rail((0.4, -0.1, 0.4), (1.8, -0.1, 0.8))
    else:
        for i in range(5):
            x = -1.3 + i * 0.65
            k.box("Combat_record_cartridge", (x, 0.3, 1.5), (0.38, 0.5, 1.5), "ceramic_light", rot=(0, (i - 2) * 8, 0))
            k.box("Record_data_channel", (x, 0.0, 1.5), (0.12, 0.06, 1.1), "amber")
        k.sword((-0.9, -0.5, 1.15), -45, 1.15)
        k.shield((1.0, -0.4, 1.0), 0.55)
        k.gear((0, -0.25, 0.5), 0.40)
        k.flow((0, 0, 1.8), (-0.9, -0.35, 1.2), "amber")
        k.flow((0, 0, 1.8), (1.0, -0.3, 1.0), "cyan")


def phase(k):
    cid = k.id
    if cid == "phase_lance":
        for i in range(3):
            k.ring("Phase_gate", (-0.9 + i * 0.9, 0.3 + i * 0.10, 1.6 + i * 0.1), 0.8 - i * 0.12, 0.05, "purple", rot=(80, 0, 15))
        k.rod("Piercing_lance_shaft", (-1.8, -0.2, 0.6), (1.5, -0.2, 2.2), 0.055, "steel")
        k.profile("Lance_spearhead", [(-0.15, 0), (0, 0.8), (0.15, 0), (0, -0.15)], (1.3, -0.2, 2.0), "steel_edge", 0.10, (0, 60, 0))
        k.target((1.45, 0.30, 2.0), True)
        k.sparks((1.4, -0.2, 2.1), "purple", 0.45)
    elif cid == "rift_volley":
        k.tube("Torn_space_outline", [(-0.4, 0, 0.3), (0.35, 0, 1.2), (-0.2, 0, 1.8), (0.5, 0, 2.7), (0.05, 0, 3.1)], 0.065, "purple")
        for i in range(3):
            z = 0.8 + i * 0.7
            k.flow((-1.7, -0.1, z + 0.4), (1.6, -0.1, z), "amber", 0.08)
            k.sphere("Phase_bolt", (0.6 + i * 0.3, -0.1, z + 0.15), (0.24, 0.12, 0.13), "amber")
        k.clock((1.4, 0.25, 2.65), 0.35)
    elif cid == "phase_zip":
        for x in (-1.1, 1.1):
            k.ring("Short_phase_exit", (x, 0.15, 1.7), 0.9, 0.075, "cyan")
        k.box("Courier_armored_boot", (0.3, -0.2, 0.8), (0.9, 0.55, 0.35), "ceramic_light", rot=(0, -30, 0))
        k.rod("Courier_leg", (0.1, -0.1, 0.85), (-0.65, 0.15, 2.4), 0.22, "steel")
        for i in range(4):
            k.flow((-1.6, 0, 0.6 + i * 0.55), (1.6, 0, 0.6 + i * 0.55), "cyan", 0.05)
        k.gear((1.1, 0.0, 0.55), 0.34)
    elif cid == "gravity_snare":
        k.sphere("Gravity_anchor", (-0.6, 0, 1.1), (1.3, 1.1, 1.3), "black")
        for i in range(3):
            k.ring("Gravity_well", (-0.6, 0, 1.1), 0.65 + i * 0.18, 0.025, "purple", rot=(70 + i * 10, 15, 0))
        k.clock((1.1, -0.05, 1.6), 0.65, True)
        for z in (1.0, 1.6, 2.2):
            k.flow((1.2, -0.1, z), (-0.6, -0.3, 1.1), "purple", 0.3)
        k.rail((-1.6, 0, 0.25), (1.6, 0, 0.25), "red", True)
    elif cid == "singularity_guard":
        k.sphere("Shield_singularity", (0, 0, 1.6), (1.2, 0.8, 1.2), "black")
        k.hexfield((0, -0.15, 1.6), 1.2, filled=False)
        for x in (-1.4, 1.4):
            k.clock((x, 0.1, 1.7), 0.45, True)
            k.flow((x, 0, 1.6), (0, -0.2, 1.6), "cyan", 0.1)
        k.shield((0, -0.3, 0.6), 0.55)
    elif cid == "worldline_collapse":
        k.profile("Worldline_rift", [(-0.3, -1.3), (0.4, -0.3), (-0.15, 0.4), (0.4, 1.4), (-0.5, 0.4), (-0.2, -0.5)], (0, 0.0, 1.6), "black", 0.35)
        for i in range(6):
            start = (-2.0 if i % 2 else 2.0, 0.1, 0.3 + i * 0.52)
            k.flow(start, (0.0, -0.2, 1.6), "red" if i % 2 else "cyan", 0.25)
            k.rail(start, (start[0] * 0.3, 0.1, 1.3), "red" if i % 2 else "cyan", True)
        k.debris((0, -0.1, 1.6), "brass", 20, 1.3)
    else:
        for i in range(4):
            k.ring("Cascading_null_gate", (0, 0.2 + i * 0.25, 1.2 + i * 0.35), 1.25 - i * 0.18, 0.065, "purple", rot=(80, 0, 0))
        k.target((0, -0.1, 0.7), True)
        k.flow((0.0, 0, 2.7), (0, -0.35, 0.8), "purple", 0.1)
        k.clock((1.3, 0, 1.6), 0.4)


def celestial(k):
    cid = k.id
    if cid in {"omega_ray", "solar_verdict"}:
        k.gear((-0.7 if cid == "omega_ray" else 0, 0.3, 2.4), 0.9, "brass_edge")
        k.core((-0.7 if cid == "omega_ray" else 0, 0.2, 2.4), 0.65, "amber")
        k.target((1.1 if cid == "omega_ray" else 0.3, -0.1, 0.9), True)
        if cid == "omega_ray":
            for i in range(3):
                k.flow((-0.7, -0.1, 2.4 + i * 0.05), (1.15, -0.3, 0.9 + i * 0.05), "amber", 0.02)
        else:
            k.profile("Solar_judgment_blade", [(-0.35, 0.75), (0.35, 0.75), (0.25, -0.4), (0, -1), (-0.25, -0.4)], (0.2, -0.25, 1.9), "brass_edge", 0.15)
            k.flow((0, -0.1, 3.0), (0.3, -0.3, 0.8), "amber", 0.05)
        k.sparks((0.8 if cid == "omega_ray" else 0.3, -0.2, 0.9), "amber", 0.6)
    elif cid == "seraph_array":
        for i, p in enumerate(((-1.5, 0.2, 1.6), (0, -0.1, 2.2), (1.5, 0.2, 1.6))):
            k.drone(p, 1.1 if i == 1 else 0.8, "shield", True)
        k.rail((-1.8, -0.1, 0.5), (1.8, -0.1, 0.5), "cyan")
    elif cid == "crown_of_thorns":
        k.shield((0, 0.1, 1.5), 1.15)
        k.ring("Barbed_crown", (0, -0.1, 1.7), 1.20, 0.11, "brass", rot=(75, 0, 0))
        for i in range(13):
            a = i * math.tau / 13
            p = (math.cos(a) * 1.15, -0.3, 1.7 + math.sin(a) * 1.15)
            k.profile("Wounding_thorn", [(-0.08, 0), (0, 0.55), (0.08, 0)], p, "red", 0.07, (0, -math.degrees(a) + 90, 0))
        k.debris((1.5, 0, 1.1), "red", 8, 0.3)
    else:
        if cid == "citadel_prime":
            for x in (-1.15, 1.15):
                k.box("Citadel_tower", (x, 0.3, 1.6), (0.7, 0.7, 2.7), "ceramic_light", bevel=0.09)
                for i in range(3):
                    k.box("Citadel_merlon", (x - 0.24 + i * 0.24, 0.3, 3.0), (0.14, 0.65, 0.35), "brass")
            k.box("Citadel_bridge", (0, 0.4, 1.9), (2.0, 0.4, 0.30), "brass")
        else:
            k.profile("Sanctuary_capsule", [(-0.55, -1), (0.55, -1), (0.75, 0.75), (0, 1.1), (-0.75, 0.75)], (0, 0.2, 1.6), "ceramic_light", 0.4)
            for side in (-1, 1):
                k.profile("Open_sanctuary_petals", [(0, -1), (0.35, -0.6), (0.35, 0.8), (0, 1)], (side * 0.95, 0.2, 1.6), "brass_edge", 0.13, (0, side * 15, 0))
            k.clock((1.35, 0.0, 0.7), 0.38, True)
        k.core((0, 0, 1.5), 0.65, "green")
        k.cross((0, -0.25, 1.5), 0.45)
        k.hexfield((0, -0.35, 1.6), 1.38, filled=False)
        k.cell((-1.2, 0.1, 0.55), 0.65, "green")


def commanders(k):
    cid = k.id
    if cid == "ragnarok_engine":
        k.gear((0, 0.35, 1.6), 1.25, "gunmetal")
        k.gun((-0.4, -0.25, 1.55), 1.30, True)
        k.core((-1.1, 0.05, 1.0), 0.65, "red")
        k.flow((1.2, -0.1, 0.6), (-1.0, -0.1, 2.45), "red", 0.30)
        k.debris((1.8, 0, 1.4), "ceramic", 14, 0.45)
    elif cid == "infinity_arsenal":
        k.core((0, 0.3, 1.5), 0.65, "amber")
        for side in (-1, 1):
            k.sword((side * 1.3, -0.1, 2.0), side * 30, 1.1)
            k.shield((side * 1.3, -0.15, 0.9), 0.52)
            k.rail((side * 0.3, 0.1, 0.3), (side * 2, 0.1, 0.3), "cyan")
        for i in range(4):
            k.sword((-1.8 + i * 1.2, 1.0, 2.7), (i - 1.5) * 10, 0.7, "segmented")
    elif cid == "tempest_choir":
        for i in range(4):
            k.drone((-1.4 + i * 0.9, 0.05, 1.8 + math.sin(i * 1.2) * 0.6), 0.80, "probe")
            k.flow((-1.4 + i * 0.9, -0.1, 1.7), (1.5, -0.1, 0.5), "cyan", 0.10)
        k.target((1.4, 0.2, 0.8), True)
        k.rail((-1.7, 0, 0.3), (1.7, 0, 0.3), "cyan")
    elif cid == "last_bastion":
        for x in (-1.2, 0, 1.2):
            k.shield((x, 0.3, 1.5), 0.75, shape="tower")
        k.gun((-0.7, -0.5, 1.3), 1.1, True)
        k.cell((-1.3, -0.1, 0.5), 0.75, "cyan", True)
        k.flow((-1.3, -0.4, 0.7), (0.0, -0.5, 1.2), "cyan")
        k.core((0, 0.2, 2.6), 0.55, "amber")
    elif cid == "dominion_pulse":
        for side, color in ((-1, "cyan"), (1, "red")):
            k.box("Commanded_knight_torso", (side * 1.15, 0.1, 1.4), (0.75, 0.4, 1.1), "ceramic_light" if side == -1 else "gunmetal", bevel=0.10)
            k.sphere("Commanded_knight_head", (side * 1.15, 0.1, 2.3), (0.55, 0.45, 0.55), "steel")
            k.box("Knight_visor", (side * 1.15, -0.15, 2.3), (0.35, 0.055, 0.08), color)
            for leg in (-0.22, 0.22):
                k.rod("Knight_leg", (side * 1.15 + leg, 0.1, 0.2), (side * 1.15 + leg, 0.1, 0.9), 0.12, "steel")
            k.flow((0, -0.1, 1.8), (side * 1.15, -0.2, 1.5), color, 0.05)
        k.rod("Command_scepter", (0, 0, 0.3), (0, 0, 2.8), 0.10, "brass")
        k.core((0, -0.05, 2.7), 0.40, "amber")
        k.shield((0, -0.15, 1.0), 0.55)
    elif cid == "chronicle_sovereign":
        k.box("Archive_throne_back", (0, 0.45, 1.8), (1.6, 0.4, 2.6), "gunmetal", bevel=0.08)
        k.box("Archive_throne_seat", (0, 0.1, 0.9), (1.65, 0.8, 0.25), "brass")
        for side in (-1, 1):
            k.box("Archive_throne_arm", (side * 0.9, 0.1, 1.15), (0.2, 1.0, 0.45), "brass")
        for i in range(5):
            k.cell((-0.8 + i * 0.4, 0.05, 2.1), 0.5, ("red", "cyan", "green", "amber", "purple")[i])
        k.sword((-1.25, -0.3, 1.5), -30, 0.95)
        k.ring("Dispatched_phase_gate", (1.35, 0.0, 1.4), 0.65, 0.045, "cyan")
        k.drone((1.30, -0.05, 1.45), 0.7, "blade")
        k.gear((0, -0.15, 0.5), 0.40)
    else:
        for side in (-1, 1):
            k.rod("Atlas_support_leg", (side * 1.3, 0.0, 0), (side * 0.95, 0.0, 2.7), 0.22, "steel")
            k.box("Atlas_shoulder", (side * 1.1, 0, 2.5), (0.70, 0.65, 0.50), "ceramic_light")
            for j in range(3):
                k.flow((side * 0.85, 0.0, 1.9), (side * 1.85, 0.0, 0.5 + j * 0.8), "cyan", 0.10)
        k.hexfield((0, -0.1, 1.8), 1.0)
        k.core((0, -0.25, 1.8), 0.45, "cyan")
        k.gear((0, 0.2, 2.8), 0.45)
        k.sword((-1.5, -0.05, 0.9), -35, 0.75)
        k.shield((1.5, -0.1, 1.0), 0.48)


def fatigue(k):
    k.reused.add("neutral_hourglass_and_clock_weights")
    for z in (0.45, 2.65):
        k.cylinder("Hourglass_cap", (0, 0.1, z), 0.65, 0.18, "brass", rot=(0, 0, 0))
        k.ring("Hourglass_cap_rim", (0, 0.1, z), 0.65, 0.035, "steel_edge", rot=(0, 0, 0))
    for x in (-0.56, 0.56):
        k.rod("Hourglass_support", (x, 0.1, 0.45), (x, 0.1, 2.65), 0.06, "steel")
    for side in (-1, 1):
        z = 1.55 + side * 0.48
        base.add_cone(k.c, k.name("Hourglass_sand_chamber"), (0, 0.1, z), 0.5 if side < 0 else 0.06, 0.06 if side < 0 else 0.5, 0.9, k.m["amber"], vertices=48)
        k.ring("Hourglass_chamber_outline", (0, 0.1, 1.55 + side * 0.9), 0.51, 0.023, "ceramic_light", rot=(0, 0, 0))
    k.flow((0, -0.13, 1.8), (0, -0.13, 1.2), "amber", 0.02)
    for side in (-1, 1):
        k.clock((side * 1.25, 0.1, 1.9), 0.55)
        for i in range(3):
            k.cylinder("Escalating_fatigue_weight", (side * (1.00 + i * 0.22), -0.05, 0.45 + i * 0.25), 0.14 + i * 0.045, 0.18, "steel", rot=(0, 0, 0))
        k.flow((0, -0.2, 1.5), (side * 1.5, -0.2, 0.5), "amber", 0.3)
    k.debris((0, -0.2, 1.5), "ceramic_light", 15, 1.05)


BUILDERS = {
    "C01": melee, "C02": ranged, "C03": defense, "C04": chrono,
    "C05": reloads, "C06": medicine, "C07": blood, "C08": automation,
    "C09": conversion, "C10": archives, "C11": phase, "C12": celestial,
    "C13": commanders, "SPECIAL": fatigue,
}


def build(card):
    if card["id"] in PROTECTED or card["id"] not in RECIPES:
        raise ValueError("Unowned or missing card art recipe: " + card["id"])
    base.clear_file()
    base.MATERIALS.clear()
    bpy.context.scene.world = None
    bpy.data.orphans_purge(do_recursive=True)
    base.build_materials()
    # Keep highlights readable at 74px without a uniformly overexposed glow.
    for key in ("cyan", "amber", "red", "green", "purple"):
        shader = base.MATERIALS[key].node_tree.nodes.get("Principled BSDF")
        shader.inputs["Emission Strength"].default_value = 1.4
    k = Kit(card)
    k.backdrop()
    BUILDERS[k.family](k)
    k.c["card_id"] = k.id
    k.c["family"] = k.family
    k.c["subject_action"] = k.recipe[1]
    k.c["card_effects"] = str(card.get("effects", []))
    return k


def setup_rig(k, size=2048, samples=32):
    scene = bpy.context.scene
    scene.name = "QueueQuest_Card_" + k.id
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = False
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    scene.eevee.taa_render_samples = samples
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.use_compositing = False
    scene.render.use_sequencer = False
    world = bpy.data.worlds.new("Card_environment_world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.055, 0.065, 0.08, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.40
    scene.world = world
    rig = base.make_collection("RENDER_RIG")
    cam_pos, target, width, roll = FRAMES[k.recipe[2]]
    cam_data = bpy.data.cameras.new("Card_camera")
    cam = bpy.data.objects.new("Card_camera", cam_data)
    rig.objects.link(cam)
    cam.location = cam_pos
    base.look_at(cam, Vector(target))
    cam.rotation_euler.rotate_axis("Z", math.radians(roll))
    cam_data.type = "PERSP"
    cam_data.lens = 36 * (Vector(target) - cam.location).length / width
    cam_data.clip_end = 100
    cam_data.dof.use_dof = True
    cam_data.dof.focus_distance = (Vector(target) - cam.location).length
    cam_data.dof.aperture_fstop = 6.0
    scene.camera = cam
    warm = k.recipe[0] in {"forge", "desert", "scrapyard", "market"}
    key = (1, 0.85, 0.62) if warm else (0.78, 0.91, 1)
    rim = (0.4, 0.77, 1) if warm else (1, 0.68, 0.33)
    base.add_area_light(rig, "Key_softbox", (-3.0, -4.5, 6.0), 1050, key, 4.0, target)
    base.add_area_light(rig, "Fill_softbox", (3.5, -3.2, 3.6), 680, (0.70, 0.84, 1), 3.0, target)
    base.add_area_light(rig, "Rim_environment", (1.3, 2.0, 4.7), 980, rim, 3.0, target)
    return {"position": list(cam_pos), "target": list(target), "frame_width": width, "roll_degrees": roll, "lens_mm": cam_data.lens, "fstop": 6.0}
