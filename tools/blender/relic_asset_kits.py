"""Editable, pedestal-free mechanical relic assemblies, grouped by R01-R11.

Each recipe has its own geometry/arrangement. Shared fittings are reusable
mechanisms, not a single recoloured model. Coordinates use X/Z as the face.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Vector

import build_art_vertical_slice as h


PRESERVED = {"iron_plating", "auxiliary_core", "chrono_shard", "salvage_magnet"}
KIT_IDS = {
    "R01": "tempered_edge kinetic_boots war_banner omega_crown titanium_rib",
    "R02": "reactive_barrier aegis_matrix phase_capacitor echo_coil entropy_battery eternity_engine barrier_seed overclock_key prism_furnace echo_rectifier waste_heat_printer resin_memory_block",
    "R03": "paradox_prism stasis_clock chrono_metronome triplet_relay borrowed_second_hand terminal_echo_ring four_name_quartet dead_heat_needle silent_three_second_timer delay_return_gear zero_hour_clapper terminal_bell paradox_mortgage reversal_turbine",
    "R04": "surge_gimbal rift_compass signal_lens archive_compass overtake_signal",
    "R05": "war_cache scavenger_contract bounty_drone memorial_fund_coil carryover_price_tag",
    "R06": "repair_nanites pulse_injector blood_pump emergency_foam armor_garden twilight_pacemaker bleed_pulsator",
    "R07": "loadout_harness full_slot_bell vacancy_interest_meter fourth_reserve_rack single_seat_duel_sheath reserved_seat_tag isolation_chamber grade_staircase unpolished_motherboard overload_seal empty_rack_bus full_load_latch weight_ticket_punch grade_differential_wheel",
    "R08": "full_absorption_gauge evaporation_recovery_valve residual_pressure_detonator rupture_insurance_film compression_caliper",
    "R09": "slow_charge_accumulator four_symptom_seal quarantine_buffer symptom_transfer_paper critical_pathology_meter",
    "R10": "solar_pinion overcharge_confection_furnace polarization_converter balanced_three_phase_unit",
    "R11": "seven_step_validator depth_pressure_gauge emergency_recovery_line defeat_wiring overtime_key loop_wear_wheel",
}
KIT_NAMES = {
    "R01": "armor_and_weapons", "R02": "cores_batteries_and_heat",
    "R03": "clocks_and_timeline", "R04": "navigation_and_signals",
    "R05": "economy_and_rewards", "R06": "medical_and_biomechanical",
    "R07": "slots_loadout_and_grade", "R08": "shield_pressure_and_spend",
    "R09": "status_and_pathology", "R10": "card_imprint_and_conversion",
    "R11": "progression_hazard_and_arena",
}
KIT_BY_ID = {asset_id: kit for kit, ids in KIT_IDS.items() for asset_id in ids.split()}


def setup_materials():
    h.MATERIALS.clear()
    colors = {
        "steel": ((0.32, 0.43, 0.52, 1), .78, .30),
        "edge": ((0.70, 0.80, 0.84, 1), .82, .22),
        "dark": ((0.034, 0.052, 0.070, 1), .70, .38),
        "brass": ((0.47, 0.28, 0.09, 1), .75, .30),
        "gold": ((0.82, 0.58, 0.22, 1), .76, .24),
        "copper": ((0.50, 0.19, 0.09, 1), .78, .28),
        "white": ((0.80, 0.82, 0.75, 1), .12, .34),
        "leather": ((0.16, 0.075, 0.031, 1), .0, .76),
        "cloth": ((0.39, 0.038, 0.035, 1), .0, .75),
        "paper": ((0.76, 0.60, 0.35, 1), .0, .70),
        "blue": ((0.055, 0.40, 0.65, 1), .23, .27),
        "red": ((0.59, 0.045, 0.045, 1), .15, .29),
        "green": ((0.09, 0.51, 0.28, 1), .16, .27),
        "amber": ((0.85, 0.37, 0.05, 1), .23, .28),
        "purple": ((0.32, 0.09, 0.49, 1), .18, .30),
        "glass": ((0.23, 0.51, 0.58, 1), .08, .19),
    }
    for name, (color, metallic, roughness) in colors.items():
        glow = name in {"blue", "red", "green", "amber", "purple"}
        h.MATERIALS[name] = h.make_material(
            "Relic_" + name, color, metallic=metallic, roughness=roughness,
            emission=color if glow else None, emission_strength=.35 if glow else 0,
            bump_strength=.055 if metallic > .5 else 0, bump_scale=30,
        )
    shader = h.MATERIALS["glass"].node_tree.nodes.get("Principled BSDF")
    h.set_material_input(shader, "Transmission Weight", .25)


class Assembly:
    def __init__(self, asset_id):
        self.id = asset_id
        self.collection = h.make_collection("RELIC_" + asset_id)
        self.parts = set()
        self.notes = []
        self.index = 0

    def name(self, part):
        self.index += 1
        self.parts.add(part)
        return f"{self.id}__{part}_{self.index:03d}"

    def box(self, part, p, size, mat="steel", rot=(0, 0, 0), bevel=.035):
        return h.add_box(self.collection, self.name(part), p, size, h.MATERIALS[mat],
                         rotation_degrees=rot, bevel=min(bevel, min(size) * .22))

    def cyl(self, part, p, r, depth, mat="brass", rot=(90, 0, 0), n=48):
        return h.add_cylinder(self.collection, self.name(part), p, r, depth, h.MATERIALS[mat],
                              rotation_degrees=rot, vertices=n, bevel=min(.024, depth*.18))

    def sphere(self, part, p, scale, mat="glass"):
        return h.add_sphere(self.collection, self.name(part), p, scale, h.MATERIALS[mat])

    def ring(self, part, p, r, tube=.06, mat="gold", rot=(90, 0, 0)):
        return h.add_torus(self.collection, self.name(part), p, r, tube, h.MATERIALS[mat],
                           rotation_degrees=rot)

    def profile(self, part, pts, depth=.15, mat="steel", p=(0, 0, 0), rot=(0, 0, 0)):
        return h.add_profile(self.collection, self.name(part), pts, depth, h.MATERIALS[mat],
                             location=p, rotation_degrees=rot, bevel=.025)

    def rod(self, part, a, b, r=.04, mat="steel"):
        return h.add_rod_between(self.collection, self.name(part), a, b, r, h.MATERIALS[mat])

    def tube(self, part, pts, r=.045, mat="copper", cyclic=False):
        return h.add_curve(self.collection, self.name(part), pts, r, h.MATERIALS[mat], cyclic=cyclic)

    def bolts(self, center, radius, count=8):
        for i in range(count):
            t = math.tau*i/count
            self.cyl("hex_bolt", (center[0]+radius*math.cos(t), center[1], center[2]+radius*math.sin(t)),
                     .035, .045, "edge", n=6)

    def gear(self, p, r=.5, teeth=16, mat="brass"):
        self.ring("gear_rim", p, r*.68, r*.19, mat)
        self.cyl("gear_hub", p, r*.18, .18, "steel")
        for i in range(teeth):
            t = math.tau*i/teeth
            self.box("gear_tooth", (p[0]+r*.94*math.sin(t), p[1], p[2]+r*.94*math.cos(t)),
                     (r*.22, .20, r*.22), mat, (0, math.degrees(t), 0), .015)
        for i in range(4):
            t = math.tau*i/4
            self.rod("gear_spoke", p, (p[0]+r*.65*math.sin(t), p[1], p[2]+r*.65*math.cos(t)), r*.055, mat)

    def dial(self, p, r=.5, hand=35, mat="white", ticks=12):
        self.cyl("dial_case", p, r, .19, "dark")
        self.cyl("dial_face", (p[0],p[1]-.11,p[2]), r*.86, .025, mat)
        self.ring("dial_bezel", (p[0],p[1]-.12,p[2]), r*.93, .04, "gold")
        for i in range(ticks):
            t=math.tau*i/ticks
            self.box("dial_tick", (p[0]+r*.72*math.sin(t),p[1]-.145,p[2]+r*.72*math.cos(t)),
                     (.018,.025,r*.10), "dark", (0,math.degrees(t),0), .003)
        t=math.radians(hand)
        self.rod("dial_hand", (p[0],p[1]-.18,p[2]),
                 (p[0]+r*.64*math.sin(t),p[1]-.18,p[2]+r*.64*math.cos(t)),.025,"red")
        self.cyl("dial_axle", (p[0],p[1]-.20,p[2]), .055, .03,"brass")

    def capsule(self, p, r=.22, length=.95, color="blue", axis="z"):
        rot=(0,0,0) if axis=="z" else (90,0,0)
        self.cyl("sealed_cell",p,r,length,"glass",rot)
        for side in (-1,1):
            end=(p[0],p[1],p[2]+side*length*.5) if axis=="z" else (p[0],p[1]+side*length*.5,p[2])
            self.cyl("cell_endcap",end,r*1.16,.10,"brass",rot)
        self.cyl("cell_liquid",p,r*.83,length*.80,color,rot)
        self.box("cell_inspection_strip",(p[0],p[1]-r-.008,p[2]),(r*.38,.03,length*.65),color)

    def coil(self, p, r=.23, height=.9, turns=8, mat="copper"):
        pts=[]
        for i in range(turns*20+1):
            f=i/(turns*20)
            t=math.tau*turns*f
            pts.append((p[0]+r*math.cos(t),p[1]+r*math.sin(t),p[2]+(f-.5)*height))
        self.tube("wound_copper_coil",pts,.026,mat)
        self.cyl("coil_core",p,r*.63,height,"dark",(0,0,0))
        for side in (-1,1):
            self.cyl("coil_insulator",(p[0],p[1],p[2]+height*.52*side),r*1.22,.08,"white",(0,0,0))

    def card(self,p,size=.55,mat="blue",angle=0):
        self.box("card_socket",p,(size,.13,size*1.28),"brass",(0,angle,0))
        self.box("card_insert",(p[0],p[1]-.08,p[2]),(size*.82,.04,size*1.10),mat,(0,angle,0))
        for i in range(3):
            self.box("card_contacts",(p[0]+(i-1)*size*.18,p[1]-.12,p[2]-size*.43),
                     (size*.10,.025,size*.15),"gold",(0,angle,0),.008)

    def bell(self,p,r=.42):
        h.add_cone(self.collection,self.name("cast_bell"),p,r,r*.38,r*1.1,h.MATERIALS["brass"],vertices=64)
        self.ring("bell_lip",(p[0],p[1],p[2]-r*.55),r,.04,"gold",(0,0,0))
        self.sphere("bell_clapper",(p[0],p[1]-.15,p[2]-r*.47),(.16,.16,.22),"steel")
        self.ring("bell_hanger",(p[0],p[1],p[2]+r*.72),.105,.025)

    def arrow(self,p,size=.5,mat="blue",angle=0):
        pts=[(-.13,-.5),(.13,-.5),(.13,.08),(.38,.08),(0,.5),(-.38,.08),(-.13,.08)]
        return self.profile("direction_arrow",[(x*size,z*size) for x,z in pts],.08,mat,p,(0,angle,0))

    def shield(self,p,size=.65,mat="blue"):
        pts=[(-.52,.50),(.52,.50),(.58,.08),(.40,-.43),(0,-.70),(-.40,-.43),(-.58,.08)]
        self.profile("shield_shell",[(x*size,z*size) for x,z in pts],.15,"brass",p)
        self.profile("shield_inset",[(x*size*.80,z*size*.80) for x,z in pts],.08,mat,(p[0],p[1]-.10,p[2]))
        self.rod("shield_ridge",(p[0],p[1]-.16,p[2]-size*.40),(p[0],p[1]-.16,p[2]+size*.32),.035,"edge")

    def scroll(self,p,width=.85,height=1.05):
        self.box("parchment",p,(width,.055,height),"paper",bevel=.02)
        for z in (-height/2,height/2):
            self.cyl("scroll_roller",(p[0],p[1],p[2]+z),.10,width*1.12,"brass",(0,90,0))
        for i in range(5):
            self.box("inscribed_line",(p[0]-.03,p[1]-.045,p[2]+height*(.27-i*.11)),
                     (width*(.64 if i%2 else .78),.016,.018),"leather",bevel=.004)

    def frame(self,p,w=1.2,hgt=1.3,mat="brass"):
        for x in (-w/2,w/2):
            self.box("mechanism_side_rail",(p[0]+x,p[1],p[2]),(.10,.18,hgt),mat)
        for z in (-hgt/2,hgt/2):
            self.box("mechanism_cross_rail",(p[0],p[1],p[2]+z),(w+.08,.18,.10),mat)


def build(asset_id):
    if asset_id not in KIT_BY_ID or asset_id in PRESERVED:
        raise ValueError("No new relic recipe: " + asset_id)
    a=Assembly(asset_id)
    fn=BUILDERS[KIT_BY_ID[asset_id]]
    fn(a)
    a.collection["asset_id"]=asset_id
    a.collection["semantic_kit"]=KIT_BY_ID[asset_id]
    a.collection["presentation"]="transparent_object_no_pedestal"
    a.collection["reuse_components"]="|".join(sorted(a.parts))
    for obj in a.collection.objects:
        obj["relic_id"]=asset_id
    return a


def armor(a):
    if a.id=="tempered_edge":
        a.profile("tempered_blade",[(-.14,-.48),(.14,-.48),(.14,.78),(0,1.15),(-.14,.78)],.11,"edge",rot=(0,-23,0))
        a.box("heat_treated_center",(0,-.08,.25),(.055,.04,1.15),"blue",(0,-23,0))
        a.box("cross_guard",(-.23,0,-.5),(.72,.20,.13),"brass",(0,-23,0))
        a.cyl("wrapped_handle",(-.39,0,-.87),.13,.52,"leather",(0,-23,0))
        for z in range(6):
            a.ring("handle_binding",(-.34-z*.033,0,-.73-z*.078),.13,.015,"gold",(0,-23,0))
        a.sphere("pommel",(-.51,0,-1.14),(.30,.22,.24),"brass")
    elif a.id=="kinetic_boots":
        for i,x in enumerate((-.43,.43)):
            z=.13*i
            a.box("boot_armored_shaft",(x,0,z+.35),(.52,.48,.82),"steel",(0,(-1 if i else 1)*7,0))
            a.box("boot_toe",(x,-.30,z-.20),(.54,.90,.30),"edge")
            a.box("boot_sole",(x,-.26,z-.37),(.57,.98,.10),"dark")
            for j in range(3):
                a.box("ankle_strap",(x,-.27,z+.18+j*.19),(.52,.07,.065),"leather")
            a.cyl("kinetic_thruster",(x,.35,z+.15),.18,.55,"brass",(0,0,0))
            a.cyl("thruster_nozzle",(x,.35,z-.16),.15,.06,"blue",(0,0,0))
    elif a.id=="war_banner":
        a.rod("banner_staff",(-.56,0,-.98),(-.56,0,1.13),.055,"brass")
        a.rod("banner_crossbar",(-.70,0,.95),(.72,0,.95),.048,"gold")
        a.profile("torn_fabric",[(-.49,.89),(.62,.86),(.77,.27),(.46,.05),(.54,-.16),(.10,-.06),(-.15,-.32),(-.47,-.21)],.045,"cloth")
        a.shield((.02,-.07,.43),.38,"gold")
        a.profile("spear_finial",[(-.12,0),(0,.34),(.12,0)],.10,"edge",(-.56,0,1.15))
        for x in (-.32,.0,.32): a.ring("fabric_fastener",(x,0,.91),.05,.016)
    elif a.id=="omega_crown":
        a.ring("crown_band",(0,0,-.22),.69,.10,"gold",(0,0,0))
        for i in range(9):
            t=math.tau*i/9
            x,y=.66*math.sin(t),.66*math.cos(t)
            a.profile("crown_spire",[(-.10,0),(0,.62+(.23 if i%3==0 else 0)),(.10,0)],.13,"dark",(x,y,-.16),(0,0,-math.degrees(t)))
            a.sphere("crown_ruby",(x,y-.08,.13),(.14,.09,.20),"red")
        a.shield((0,-.72,-.16),.32,"gold")
    elif a.id=="titanium_rib":
        a.rod("vertebral_spine",(0,.08,-.75),(0,.08,.91),.13,"edge")
        for i in range(6):
            z=.68-i*.24; width=.56-.04*abs(i-2)
            for side in (-1,1):
                a.tube("titanium_rib",[(0,0,z),(side*width*.72,-.10,z+.08),(side*width,-.28,z-.01),(side*width*.86,-.43,z-.15)],.072,"edge")
                a.box("blue_reinforcement",(side*width*.77,-.25,z),(.10,.13,.12),"blue")


def energy(a):
    if a.id=="reactive_barrier":
        a.cyl("shield_emitter",(0,0,0),.29,.44,"dark")
        a.cyl("core_aperture",(0,-.26,0),.18,.045,"blue")
        for i in range(5):
            t=math.tau*i/5
            a.profile("opening_shield_petal",[(-.18,.28),(-.28,.76),(0,1.0),(.28,.76),(.18,.28)],.16,"edge",rot=(0,math.degrees(t),0))
            a.rod("petal_hinge",(0,-.1,0),(.55*math.sin(t),-.1,.55*math.cos(t)),.043,"brass")
    elif a.id=="aegis_matrix":
        for i in range(6):
            t=math.tau*i/6
            a.cyl("hex_shield_layer",(.56*math.sin(t),0,.56*math.cos(t)),.36,.14,"blue",n=6)
            a.ring("layer_frame",(.56*math.sin(t),-.075,.56*math.cos(t)),.28,.035,"brass")
        a.gear((0,-.13,0),.34,12,"gold")
        a.shield((0,-.30,0),.35,"white")
    elif a.id=="phase_capacitor":
        a.capsule((0,0,0),.38,1.60,"blue")
        for z in (-.52,0,.52): a.ring("insulation_band",(0,0,z),.40,.05,"white",(0,0,0))
        for side in (-1,1):
            a.rod("capacitor_terminal",(side*.25,0,.82),(side*.25,0,1.1),.055,"gold")
        a.box("phase_splitter",(.42,-.20,.2),(.30,.27,.70),"dark")
        a.bolts((0,-.41,0),.24,6)
    elif a.id=="echo_coil":
        a.coil((-.35,0,0),.26,1.25,12)
        a.bell((.42,0,.14),.43)
        a.tube("magnetic_yoke",[(-.35,.25,-.67),(.10,.35,-.64),(.62,.18,-.45),(.68,0,.38)],.095,"steel")
        a.rod("resonance_link",(-.35,-.03,.65),(.39,-.03,.70),.045,"gold")
    elif a.id=="entropy_battery":
        a.capsule((0,0,0),.44,1.32,"amber")
        for x in (-.57,.57):
            a.tube("recovery_coolant",[(x*.6,0,.60),(x,0,.63),(x,0,-.62),(x*.6,0,-.60)],.055,"copper")
        for z in (-.46,-.17,.12,.41): a.box("heat_fin",(0,.36,z),(1.05,.30,.065),"steel")
        a.box("recovery_cross",(0,-.45,0),(.38,.08,.12),"green")
        a.box("recovery_cross",(0,-.45,0),(.12,.08,.38),"green")
    elif a.id=="eternity_engine":
        a.capsule((0,0,0),.36,1.08,"blue")
        for z,r in ((-.60,.57),(0,.71),(.60,.57)):
            a.ring("chrono_reactor_hoop",(0,0,z),r,.075,"gold",(0,0,0))
        for x in (-.57,.57): a.rod("reactor_strut",(x,0,-.69),(x,0,.69),.060,"steel")
        a.dial((0,-.48,.06),.36,65)
        a.shield((0,-.58,-.59),.27)
    elif a.id=="barrier_seed":
        a.sphere("shield_seed",(0,0,0),(.58,.58,.83),"blue")
        for i in range(4):
            t=math.tau*i/4
            a.profile("seed_shell",[(-.18,-.46),(-.34,0),(-.15,.49),(0,.66),(.13,.38),(.28,-.08),(.12,-.44)],.16,"brass",(.12*math.sin(t),.20*math.cos(t),0),(0,0,math.degrees(t)))
        a.tube("germinating_feed",[(0,0,-.39),(.15,0,-.69),(.33,0,-.73)],.06,"green")
    elif a.id=="overclock_key":
        a.gear((0,0,.55),.41,14,"gold")
        a.capsule((0,-.07,.55),.16,.60,"amber",axis="y")
        a.box("key_shank",(0,0,-.23),(.18,.20,1.12),"edge")
        for i in range(3): a.box("key_teeth",(.18,0,-.55+i*.22),(.33,.20,.11),"brass")
        a.arrow((-.34,-.15,.53),.32,"red")
    elif a.id=="prism_furnace":
        a.box("furnace_housing",(0,.08,0),(1.0,.62,1.23),"dark")
        a.cyl("prism_window",(0,-.32,.13),.36,.10,"purple",n=6)
        a.ring("window_lock",(0,-.39,.13),.36,.045)
        for x,mat in ((-.61,"red"),(0,"blue"),(.61,"amber")):
            a.tube("three_effect_conduit",[(x,0,-.55),(x,0,-.78),(x*.60,-.10,-.78),(x*.60,-.20,-.46)],.055,mat)
        a.box("furnace_flue",(.30,.06,.86),(.21,.24,.51),"brass")
        a.bolts((0,-.41,.13),.44,8)
    elif a.id=="echo_rectifier":
        a.box("rectifier_chassis",(0,.08,-.51),(1.36,.58,.35),"steel")
        for x in (-.41,.41):
            a.capsule((x,0,.12),.22,1.05,"blue")
            a.coil((x,0,.12),.28,.56,6)
        a.dial((0,-.35,-.48),.23,85)
        a.tube("manual_source_feedback",[(-.43,.0,.68),(0,-.05,.89),(.43,0,.68)],.035,"blue")
    elif a.id=="waste_heat_printer":
        a.box("heat_printer",(0,0,.08),(1.32,.64,.80),"dark")
        for x in (-.42,0,.42): a.capsule((x,.05,.67),.14,.34,"amber")
        for x in (-.51,.51): a.cyl("print_roller",(x,-.34,-.10),.13,.60,"brass",(0,0,0))
        a.profile("cancelled_auto_ticket",[(-.44,.1),(.44,.1),(.45,-.75),(.30,-.85),(.16,-.76),(.03,-.89),(-.11,-.77),(-.28,-.86),(-.44,-.77)],.045,"paper",(0,-.47,-.10))
        a.box("ticket_cancel_bar",(0,-.51,-.43),(.71,.035,.07),"red",(0,30,0))
        a.gear((.64,0,-.05),.21,10)
    elif a.id=="resin_memory_block":
        a.box("resin_block",(0,.11,0),(1.17,.53,1.12),"glass",bevel=.08)
        for i in range(3):
            a.card((-.31+i*.31,-.21,.04+i*.10),.34,"green",(i-1)*10)
        for x in (-.57,.57):
            for z in (-.52,.52): a.box("resin_corner_clamp",(x,-.11,z),(.16,.24,.16),"gold")
        for z in (-.26,0,.26): a.rod("memory_growth_trace",(-.46,-.25,z),(.45,-.25,z),.014,"gold")


def clocks(a):
    if a.id=="paradox_prism":
        a.cyl("chronal_prism",(0,0,0),.50,.99,"purple",(0,0,0),n=3)
        a.ring("crossing_time_ring",(0,0,0),.75,.065,"gold",(35,10,0))
        a.ring("crossing_time_ring",(0,0,0),.75,.065,"steel",(125,-10,0))
        a.arrow((0,-.57,-.14),.44,"blue",90)
    elif a.id=="stasis_clock":
        a.sphere("spherical_clock_shell",(0,.13,0),(1.40,.73,1.40),"steel")
        a.dial((0,-.27,0),.61,0)
        for x in (-.63,.63): a.box("stasis_clamp",(x,-.30,0),(.22,.31,.74),"brass")
        a.box("fixed_hand_bar",(0,-.46,.35),(.20,.12,.45),"blue")
        a.cyl("winding_stem",(0,0,.87),.12,.28,"gold",(0,0,0))
    elif a.id=="chrono_metronome":
        a.profile("metronome_case",[(-.65,-.70),(.65,-.70),(.30,.85),(-.30,.85)],.48,"leather")
        a.profile("metronome_inset",[(-.49,-.57),(.49,-.57),(.20,.72),(-.20,.72)],.065,"brass",(0,-.27,0))
        a.rod("pendulum_arm",(0,-.36,-.46),(.38,-.36,.65),.04,"edge")
        a.box("adjustable_pendulum_weight",(.23,-.38,.21),(.25,.15,.22),"blue")
        for z in range(7): a.box("metronome_tick",(-.15,-.32,-.35+z*.15),(.13,.03,.018),"edge",bevel=.003)
        a.cyl("pendulum_pivot",(0,-.42,-.46),.10,.06,"gold")
    elif a.id=="triplet_relay":
        for x in (-.51,0,.51):
            a.box("third_card_relay",(x,0,0),(.37,.44,1.14),"white")
            a.coil((x,-.10,.13),.12,.48,7)
            a.box("relay_switch",(x,-.28,.48),(.25,.10,.13),"blue")
        a.rod("shared_relay_axle",(-.72,0,-.48),(.72,0,-.48),.06,"gold")
        a.gear((0,-.33,-.61),.23,12)
    elif a.id=="borrowed_second_hand":
        a.gear((-.37,0,-.16),.49,18)
        a.gear((.37,0,.34),.36,14,"steel")
        a.profile("borrowed_long_hand",[(-.055,-.17),(.055,-.17),(.055,.82),(0,1.02),(-.055,.82)],.065,"blue",(-.36,-.15,-.14),(0,24,0))
        a.profile("lent_short_hand",[(-.07,-.10),(.07,-.10),(.07,.5),(0,.68),(-.07,.5)],.065,"red",(.38,-.15,.34),(0,133,0))
        a.tube("borrowing_link",[(-.60,.06,.31),(-.15,.18,.88),(.49,.10,.79)],.04,"gold")
    elif a.id=="terminal_echo_ring":
        a.ring("primary_echo_ring",(0,0,0),.72,.10,"brass")
        a.ring("delayed_echo_ring",(.17,.12,-.12),.55,.06,"steel")
        a.rod("primary_hand",(0,-.12,0),(-.40,-.12,.54),.045,"blue")
        a.rod("trailing_hand",(.17,-.03,-.12),(.48,-.03,.23),.030,"amber")
        a.cyl("echo_pivot",(0,-.18,0),.12,.17,"gold")
        a.card((-.57,-.03,-.58),.33,"blue",-30)
    elif a.id=="four_name_quartet":
        a.gear((0,0,0),.35,12)
        for i,mat in enumerate(("blue","red","green","amber")):
            t=math.tau*i/4
            p=(.63*math.sin(t),0,.63*math.cos(t))
            a.card(p,.39,mat,i*90)
            a.rod("quartet_terminal",(0,0,0),p,.055,"steel")
    elif a.id=="dead_heat_needle":
        a.profile("race_gauge_shell",[(-.91,-.25),(.91,-.25),(.86,.44),(.5,.68),(-.5,.68),(-.86,.44)],.35,"dark")
        for x,mat,hand in ((-.38,"blue",30),(.38,"red",-30)):
            a.dial((x,-.21,.17),.38,hand,mat,8)
        a.profile("alignment_index",[(-.06,-.32),(.06,-.32),(0,.31)],.07,"gold",(0,-.49,.56))
        a.rod("same_time_lock",(-.53,-.27,-.20),(.53,-.27,-.20),.045,"edge")
    elif a.id=="silent_three_second_timer":
        a.frame((0,0,0),1.22,1.51)
        for x in (-.41,0,.41):
            for side in (-1,1):
                h.add_cone(a.collection,a.name("sandglass_chamber"),(x,0,side*.28),.15 if side<0 else .045,.045 if side<0 else .15,.49,h.MATERIALS["glass"],vertices=48)
            a.cyl("three_second_sand",(x,0,-.48),.12,.19,"amber",(0,0,0))
        a.box("silencing_shutter",(0,.22,0),(1.08,.10,1.16),"leather")
        a.cyl("timing_button",(0,0,.90),.11,.21,"blue",(0,0,0))
    elif a.id=="delay_return_gear":
        a.gear((-.30,0,.16),.53,18)
        a.gear((.43,0,-.24),.36,12,"steel")
        pts=[]
        for i in range(101):
            t=math.tau*2.4*i/100; r=.06+.35*i/100
            pts.append((-.30+r*math.sin(t),-.15,.16+r*math.cos(t)))
        a.tube("stored_delay_return_spring",pts,.022,"blue")
        a.arrow((.43,-.17,-.22),.35,"amber",180)
    elif a.id=="zero_hour_clapper":
        a.box("threshold_rail",(0,.06,-.30),(1.72,.24,.19),"steel")
        for x in (-.62,0,.62):
            a.bell((x,0,.21),.25)
            a.cyl("threshold_station",(x,-.16,-.31),.10,.06,"blue")
        a.rod("sliding_clapper_arm",(-.65,-.22,-.29),(.20,-.22,.33),.045,"brass")
        a.sphere("shared_clapper_head",(.20,-.22,.33),(.20,.18,.18),"edge")
    elif a.id=="terminal_bell":
        a.bell((-.16,0,.24),.61)
        a.box("third_delay_counter",(.66,0,-.20),(.38,.28,.89),"dark")
        for z in (-.46,-.17,.12): a.cyl("delay_counter_lamp",(.66,-.18,z),.09,.04,"red")
        a.rod("interrupt_hammer",(.46,-.19,-.47),(.24,-.19,.26),.045,"steel")
        a.box("interrupt_hammer_head",(.24,-.18,.26),(.32,.27,.16),"gold")
    elif a.id=="paradox_mortgage":
        a.dial((-.28,0,.30),.49,125)
        a.scroll((.31,-.22,-.26),.77,.95)
        a.ring("mortgage_seal",(.33,-.30,-.31),.20,.045,"red")
        a.gear((-.40,.05,-.50),.30,14)
        a.tube("time_debt_link",[(-.67,0,.18),(-.90,0,-.43),(-.30,0,-.73),(.22,0,-.71)],.055,"brass")
    elif a.id=="reversal_turbine":
        a.ring("turbine_duct",(0,0,0),.71,.13,"steel")
        for i in range(7):
            t=math.tau*i/7
            a.profile("reverse_pitch_blade",[(.10,0),(.40,.10),(.70,-.06),(.65,-.24),(.35,-.29)],.085,"brass",rot=(0,math.degrees(t),0))
        a.cyl("turbine_hub",(0,-.10,0),.18,.30,"dark")
        a.tube("reverse_red_channel",[(-.74,0,-.4),(-.96,0,.05),(-.76,0,.57)],.055,"red")
        a.tube("reverse_blue_channel",[(.74,0,.4),(.96,0,-.05),(.76,0,-.57)],.055,"blue")
        a.arrow((0,-.30,.74),.36,"blue",-90)


def navigation(a):
    if a.id=="surge_gimbal":
        for r,rot,mat in ((.73,(90,0,0),"brass"),(.61,(0,25,0),"steel"),(.49,(40,90,0),"gold")):
            a.ring("gimbal_axis",(0,0,0),r,.06,mat,rot)
        a.arrow((0,-.12,0),.95,"blue",33)
        a.rod("gimbal_mount",(0,0,-.88),(0,0,.88),.045,"edge")
    elif a.id=="rift_compass":
        a.dial((0,0,0),.76,40,"dark",16)
        a.tube("rift_in_face",[(-.60,-.13,.34),(-.26,-.14,.20),(-.04,-.15,-.03),(.18,-.14,-.22),(.47,-.14,-.50)],.030,"purple")
        a.arrow((0,-.22,.03),1.05,"edge",40)
        a.ring("compass_hanging_loop",(0,0,.94),.17,.05)
        a.sphere("floating_compass_axle",(0,-.30,0),(.18,.18,.18),"blue")
    elif a.id=="signal_lens":
        a.cyl("telescope_barrel",(0,0,0),.27,1.54,"brass",(0,65,0))
        for x,z,r in ((-.61,-.29,.32),(.55,.26,.38)):
            a.ring("lens_rim",(x,0,z),r,.065,"gold",(0,65,0))
            a.cyl("signal_lens",(x,0,z),r*.81,.045,"blue",(0,65,0))
        a.cyl("focus_knob",(0,-.33,.05),.14,.17,"dark")
        a.dial((-.24,-.25,-.21),.20,55)
        a.rod("sighting_reticle",(.37,-.11,.48),(.57,-.11,.48),.018,"red")
    elif a.id=="archive_compass":
        a.scroll((.08,.03,0),1.50,1.20)
        a.dial((-.42,-.13,.12),.37,-50,"white",8)
        a.box("folded_map",(.45,-.14,.11),(.53,.06,.90),"paper",(0,-12,0))
        for z in (-.1,.1,.3): a.tube("map_route",[(.23,-.2,z),(.43,-.2,z+.09),(.62,-.2,z-.03)],.012,"dark")
        a.cyl("archive_inkpot",(.63,-.10,-.56),.17,.35,"dark",(0,0,0))
        a.profile("index_quill",[(-.07,0),(.09,.18),(.03,.69),(-.13,.29)],.05,"white",(.77,0,.30),(0,-20,0))
    elif a.id=="overtake_signal":
        a.box("signal_switchboard",(0,0,.02),(.80,.43,1.37),"dark")
        for z,mat in ((.38,"red"),(-.33,"blue")):
            a.cyl("overtake_lamp",(0,-.25,z),.25,.09,mat)
            a.ring("lamp_bezel",(0,-.30,z),.26,.05)
        a.arrow((.60,-.05,.05),1.14,"gold")
        a.rod("switch_lever",(-.39,0,-.20),(-.66,-.05,.31),.050,"steel")
        a.sphere("switch_handle",(-.66,-.05,.31),(.19,.17,.19),"white")


def economy(a):
    if a.id=="war_cache":
        a.box("supply_chest",(0,.05,-.18),(1.44,.83,.77),"leather")
        a.box("open_chest_lid",(0,.23,.55),(1.47,.20,.70),"steel",(-30,0,0))
        for x in (-.47,.47): a.box("sealed_gold_band",(x,-.38,-.18),(.10,.08,.73),"gold")
        for i in range(7): a.cyl("gold_supply_coin",(-.48+i*.16,-.29,.22+(i%2)*.10),.16,.10,"gold",(70,0,i*17))
        a.box("chest_lock",(0,-.43,-.15),(.28,.10,.31),"brass")
    elif a.id=="scavenger_contract":
        a.scroll((-.15,0,.13),.92,1.39)
        a.cyl("contract_wax_seal",(.14,-.10,-.30),.20,.075,"red")
        a.tube("salvage_hook",[(.66,0,.77),(.63,0,-.45),(.44,0,-.67),(.28,0,-.51)],.08,"steel")
        a.ring("hook_attachment",(.65,0,.85),.14,.05)
        a.box("bounty_ribbon",(.08,-.11,-.58),(.12,.07,.52),"cloth",(0,-15,0))
    elif a.id=="bounty_drone":
        a.sphere("drone_head",(0,0,0),(.94,.67,.65),"steel")
        a.cyl("tracking_lens",(0,-.35,.04),.23,.15,"blue")
        a.ring("lens_focus",(0,-.45,.04),.24,.045)
        for side in (-1,1):
            a.rod("drone_arm",(side*.4,0,.07),(side*.88,0,.24),.06,"brass")
            a.ring("drone_rotor",(side*.91,0,.28),.32,.065,"dark",(0,0,0))
            a.box("rotor_blade",(side*.91,0,.29),(.47,.12,.06),"edge")
        a.box("coin_hopper",(0,0,.55),(.62,.32,.31),"gold")
        a.box("coin_slot",(0,-.17,.60),(.43,.025,.055),"dark")
        a.cyl("bounty_coin",(0,0,.81),.20,.07,"gold")
    elif a.id=="memorial_fund_coil":
        a.coil((.30,0,-.03),.34,1.11,12)
        a.profile("coin_funnel",[(-.75,.55),(.08,.55),(-.13,.02),(-.55,.02)],.25,"brass")
        for i in range(3): a.cyl("shield_spend_coin",(-.42,-.13,.61+i*.15),.20,.10,"gold")
        a.shield((-.46,-.21,-.29),.48,"blue")
        a.tube("fund_feed",[(-.31,0,.02),(-.13,0,-.61),(.30,0,-.65)],.085,"copper")
    elif a.id=="carryover_price_tag":
        a.profile("held_price_tag",[(-.57,-.65),(.57,-.65),(.57,.51),(.31,.75),(-.31,.75),(-.57,.51)],.18,"brass")
        a.box("price_window",(0,-.11,.08),(.87,.06,.77),"white")
        for i in range(4): a.box("carried_round_discount",(-.30+i*.20,-.16,-.17+i*.11),(.12,.05,.22+i*.06),"blue")
        for i in range(5): a.ring("tag_chain",(-.36+i*.18,.0,.86+(i%2)*.10),.10,.025,"steel",(90 if i%2 else 0,0,0))
        a.arrow((0,-.17,.40),.42,"green",180)


def medical(a):
    if a.id=="repair_nanites":
        a.capsule((0,.05,0),.34,1.30,"green")
        for side in (-1,1):
            for z in (-.46,.38):
                a.tube("nanite_repair_arm",[(side*.24,.05,z),(side*.61,.02,z+.18),(side*.74,-.10,z-.11)],.055,"steel")
                for d in (-1,1): a.rod("nanite_pincer",(side*.74,-.10,z-.11),(side*.74+d*.09,-.10,z-.24),.024,"edge")
        for z in (-.35,0,.35): a.cyl("nanite_marker",(0,-.31,z),.058,.025,"gold")
    elif a.id=="pulse_injector":
        a.capsule((-.05,0,.03),.24,1.08,"green")
        a.rod("injection_needle",(-.05,0,-.55),(-.05,0,-1.02),.022,"edge")
        a.box("finger_grip",(-.05,0,.55),(.80,.22,.12),"edge")
        a.rod("plunger",(-.05,0,.62),(-.05,0,.98),.066,"steel")
        a.box("plunger_pad",(-.05,0,1.0),(.46,.26,.10),"brass")
        a.dial((.43,-.05,.13),.27,75)
        a.tube("pulse_line",[(.18,0,-.17),(.44,0,-.33),(.45,0,-.03)],.04,"copper")
    elif a.id=="blood_pump":
        for x,z in ((-.24,.21),(.24,.08)):
            a.sphere("artificial_heart_chamber",(x,0,z),(.75,.58,.89),"red")
        a.profile("heart_tip",[(-.52,.12),(.52,.12),(0,-.75)],.40,"red",(0,0,-.05))
        a.cyl("brass_pump",(.52,-.04,.08),.23,.63,"brass",(0,0,0))
        for x in (-.34,.20): a.tube("blood_feed",[(x,0,.44),(x,0,.81),(x+.23,0,.83)],.086,"copper")
        a.dial((-.05,-.33,.15),.25,65,"white",8)
    elif a.id=="emergency_foam":
        a.capsule((-.20,0,-.03),.32,1.20,"white")
        a.box("pressure_valve",(-.20,0,.67),(.39,.25,.22),"brass")
        a.tube("foam_nozzle",[(-.03,0,.65),(.33,-.03,.65),(.53,-.03,.41)],.060,"steel")
        for i in range(7):
            a.sphere("expanding_shield_foam",(.48+(i%3)*.14,-.08,.29-(i//3)*.20),(.31,.31,.29),"white")
        a.shield((-.20,-.34,-.08),.36,"blue")
    elif a.id=="armor_garden":
        a.capsule((0,0,-.11),.20,.61,"green")
        for i in range(7):
            t=math.tau*i/7
            a.profile("armored_flower_petal",[(-.11,.09),(-.24,.50),(0,.91),(.24,.50),(.11,.09)],.11,"edge",rot=(0,math.degrees(t),0))
        a.sphere("repair_growth_cell",(0,-.18,0),(.41,.27,.41),"green")
        for side in (-1,1):
            a.tube("healing_root_pipe",[(0,0,-.30),(side*.30,0,-.52),(side*.43,0,-.83)],.050,"copper")
            a.tube("healing_root_pipe",[(0,0,-.30),(side*.16,.14,-.60),(side*.25,.14,-.94)],.036,"steel")
    elif a.id=="twilight_pacemaker":
        a.box("pacemaker_housing",(0,.04,0),(1.28,.45,1.10),"white")
        for x,color in ((-.31,"red"),(.31,"blue")):
            a.capsule((x,-.11,.08),.19,.75,color)
        a.dial((0,-.44,-.18),.32,10,"dark",10)
        a.tube("hp_boundary_switch",[(-.50,.05,.59),(0,0,.80),(.50,.05,.59)],.063,"brass")
        a.rod("threshold_lever",(.44,-.30,-.37),(.65,-.30,-.05),.038,"gold")
    elif a.id=="bleed_pulsator":
        a.capsule((-.28,0,0),.28,1.36,"red")
        a.coil((-.28,0,.06),.34,.75,9)
        a.dial((.40,-.10,-.10),.35,60)
        a.rod("bleed_time_needle",(.40,-.32,-.10),(.40,-.32,.83),.032,"blue")
        a.tube("pulsation_conduit",[(-.28,0,-.69),(.05,0,-.83),(.42,0,-.52)],.065,"copper")


def loadout(a):
    if a.id=="loadout_harness":
        for side in (-1,1):
            a.tube("shoulder_harness",[(side*.33,0,-.65),(side*.56,0,.14),(side*.43,0,.74),(side*.20,.05,.84)],.105,"leather")
        a.rod("harness_belt",(-.61,0,-.42),(.61,0,-.42),.085,"leather")
        for x in (-.38,0,.38): a.card((x,-.15,-.02),.31,"blue")
        a.dial((0,-.23,-.51),.23,40)
    elif a.id=="full_slot_bell":
        a.bell((0,0,.33),.48)
        for x in (-.48,0,.48):
            a.card((x,0,-.45),.32,"blue")
            a.rod("full_slot_bell_feed",(x,0,-.27),(0,0,.04),.036,"copper")
        a.shield((0,-.23,.27),.25,"white")
    elif a.id=="vacancy_interest_meter":
        a.box("interest_meter_case",(0,.12,0),(1.36,.39,1.02),"dark")
        for x in (-.44,0,.44):
            a.frame((x,-.14,.07),.31,.57,"edge")
        a.dial((0,-.29,-.49),.27,110)
        for i in range(3): a.cyl("interest_charge",(-.28+i*.28,-.25,.68),.09,.08,"amber")
    elif a.id=="fourth_reserve_rack":
        a.box("four_slot_rail",(0,0,-.46),(1.55,.27,.17),"brass")
        for i in range(4):
            x=-.57+i*.38
            a.frame((x,0,.04),.27,1.06,"steel" if i<3 else "gold")
            a.card((x,-.06,.03),.23,"blue" if i<3 else "amber")
        a.dial((.61,-.24,-.52),.24,-40,"white",8)
    elif a.id=="single_seat_duel_sheath":
        a.profile("single_duel_sheath",[(-.39,.83),(.39,.83),(.33,-.73),(0,-.98),(-.33,-.73)],.31,"leather")
        a.card((0,-.19,.19),.64,"red")
        for z in (-.44,.56): a.box("locking_bar",(0,-.28,z),(.86,.14,.11),"brass")
        a.gear((-.49,0,-.12),.21,10)
    elif a.id=="reserved_seat_tag":
        a.profile("reserved_slot_tag",[(-.52,-.58),(.52,-.58),(.52,.57),(-.52,.57)],.16,"white")
        a.card((0,-.15,-.03),.55,"amber")
        a.profile("interrupt_lightning",[(-.20,.39),(.10,.39),(-.03,.05),(.20,.05),(-.14,-.43),(-.04,-.12),(-.24,-.12)],.06,"red",(0,-.24,0))
        a.ring("seat_hanging_hook",(0,0,.78),.22,.06)
    elif a.id=="isolation_chamber":
        a.frame((0,0,0),1.09,1.50,"edge")
        a.box("isolated_glass",(0,.17,0),(.92,.10,1.25),"glass")
        a.card((0,-.12,0),.62,"blue")
        a.cyl("auxiliary_socket",(.74,0,-.33),.20,.28,"brass")
        a.arrow((-.74,0,.16),.67,"green",90)
        a.rod("isolator_tube",(.50,0,-.33),(.74,0,-.33),.070,"steel")
    elif a.id=="grade_staircase":
        for i in range(4):
            x=-.66+i*.44; ht=.28+i*.23
            a.box("grade_step_mechanism",(x,0,-.59+ht/2),(.40,.50,ht),"steel")
            a.card((x,-.03,-.37+ht),.26,("white","green","blue","purple")[i])
        a.shield((-.66,-.34,-.50),.18)
    elif a.id=="unpolished_motherboard":
        a.box("unpolished_circuit_board",(0,0,0),(1.35,.17,1.44),"green")
        for x,z in ((-.36,.37),(.30,.34),(-.19,-.35)):
            a.box("base_card_processor",(x,-.14,z),(.40,.15,.32),"dark")
            for j in range(5):
                a.rod("circuit_trace",(x-.17+j*.085,-.105,z+.18),(x-.17+j*.085,-.105,z+.38),.012,"gold")
        a.card((.43,-.17,-.29),.39,"white",12)
        a.cyl("slow_warning_lamp",(-.50,-.12,-.55),.095,.045,"amber")
        a.bolts((0,-.11,0),.61,4)
    elif a.id=="overload_seal":
        a.box("overloaded_satchel",(0,.05,0),(1.18,.53,1.28),"leather",bevel=.13)
        for i in range(4): a.card((-.34+i*.24,-.06,.56+(i%2)*.11),.31,"blue",(i-2)*9)
        a.box("satchel_clasp",(0,-.30,.07),(.84,.19,.27),"brass")
        a.cyl("overload_wax_seal",(0,-.44,.05),.25,.08,"red")
        for x in (-.45,.45): a.box("overflow_warning",(x,-.29,-.43),(.15,.08,.29),"amber")
        a.ring("satchel_handle",(0,.03,.80),.29,.07,"leather")
    elif a.id=="empty_rack_bus":
        for x in (-.55,0,.55): a.frame((x,0,.08),.38,1.22,"steel")
        for z in (-.66,.69): a.rod("empty_rack_busbar",(-.80,0,z),(.80,0,z),.055,"copper")
        for x in (-.70,.70):
            a.cyl("additional_slot_socket",(x,-.16,-.13),.13,.13,"gold")
            a.cyl("open_socket",(x,-.25,-.13),.065,.02,"dark")
    elif a.id=="full_load_latch":
        a.box("latch_receiver",(.35,0,0),(.52,.40,1.17),"steel")
        a.box("latch_tongue",(-.39,0,0),(.78,.28,.31),"brass")
        a.ring("hinged_latch_loop",(-.36,-.17,.03),.39,.08,"gold")
        a.rod("closed_latch_pin",(.15,-.31,-.40),(.15,-.31,.43),.075,"edge")
        a.card((.38,-.26,.0),.28,"blue")
        a.cyl("full_capacity_indicator",(.38,-.23,.42),.077,.05,"green")
    elif a.id=="weight_ticket_punch":
        a.box("ticket_punch_body",(0,0,-.04),(1.0,.65,.89),"dark")
        a.rod("heavy_card_punch_lever",(-.44,0,.42),(.48,0,.77),.085,"steel")
        a.box("punch_handle",(.52,0,.78),(.39,.34,.17),"leather")
        a.scroll((0,-.38,-.15),.55,.88)
        for i in range(5): a.cyl("five_weight_punch",(-.20+i*.10,-.44,.16),.032,.015,"dark")
        for x in (-.61,.61): a.card((x,-.14,-.41),.28,"blue",-15 if x<0 else 15)
    elif a.id=="grade_differential_wheel":
        for i in range(4):
            a.ring("grade_difference_ring",(0,-i*.045,0),.77-i*.15,.052,("brass","steel","blue","purple")[i])
        a.rod("higher_grade_index",(0,-.20,0),(.62,-.20,.36),.035,"gold")
        a.rod("lower_grade_index",(0,-.23,0),(-.25,-.23,.42),.035,"green")
        a.gear((0,-.28,0),.18,12)
        a.dial((.64,-.12,-.65),.22,80)


def pressure(a):
    if a.id=="full_absorption_gauge":
        a.shield((-.21,.03,.02),1.08,"blue")
        a.dial((.32,-.28,.18),.43,135,"white",10)
        a.box("full_absorption_stop",(.65,-.42,.54),(.12,.12,.20),"green")
        a.tube("shield_pressure_tube",[(-.17,.12,-.52),(.33,.12,-.71),(.62,.06,-.31)],.055,"copper")
    elif a.id=="evaporation_recovery_valve":
        a.cyl("recovery_valve_body",(-.22,0,0),.34,.90,"steel",(0,0,0))
        a.ring("valve_handwheel",(-.22,0,.72),.34,.06,"red",(0,0,0))
        a.rod("valve_stem",(-.22,0,.42),(-.22,0,.71),.065,"brass")
        for i in range(3): a.capsule((.49,0,-.35+i*.35),.13,.27,"blue")
        a.tube("decay_recovery_feed",[(-.22,0,-.47),(-.07,0,-.74),(.50,0,-.61),(.49,0,-.36)],.078,"copper")
        a.tube("steam_escape",[(-.55,0,.12),(-.72,0,.41),(-.68,0,.83)],.045,"white")
    elif a.id=="residual_pressure_detonator":
        a.capsule((0,0,-.07),.39,1.07,"blue")
        a.dial((0,-.43,.08),.34,-135)
        a.box("detonator_trigger",(0,0,.66),(.39,.33,.31),"red")
        a.ring("safety_pin",(.29,0,.71),.16,.035,"edge")
        for side in (-1,1): a.tube("zero_pressure_feed",[(side*.33,0,-.34),(side*.57,0,-.18),(side*.58,0,.33),(side*.26,0,.51)],.055,"copper")
    elif a.id=="rupture_insurance_film":
        a.frame((-.02,0,.0),1.34,1.16,"steel")
        a.profile("ruptured_shield_membrane",[(-.59,-.49),(.55,-.49),(.56,-.05),(.10,-.10),(.30,.18),(.0,.10),(.18,.51),(-.59,.51)],.045,"glass",(0,-.08,0))
        a.dial((.52,-.18,-.49),.30,115,"white",10)
        a.cyl("refund_insurance_seal",(-.37,-.14,.11),.25,.07,"gold")
        a.arrow((-.37,-.22,.11),.38,"green",180)
    elif a.id=="compression_caliper":
        a.box("caliper_spine",(-.30,0,0),(.22,.22,1.64),"edge")
        for z,length in ((.64,.90),(-.29,1.05)):
            a.box("compression_jaw",(.14,0,z),(length,.29,.17),"steel")
            a.box("compression_jaw_tip",(.57,0,z+(-.1 if z>0 else .1)),(.15,.29,.30),"brass")
        a.shield((.34,-.17,.19),.45,"blue")
        a.dial((-.34,-.22,-.36),.25,70)
        for i in range(10): a.box("caliper_graduation",(-.30,-.13,-.67+i*.13),(.09,.02,.012),"dark",bevel=.002)


def pathology(a):
    if a.id=="slow_charge_accumulator":
        a.coil((.32,0,-.10),.32,1.15,10)
        a.dial((-.37,-.06,.22),.47,-80,"blue",8)
        a.capsule((-.40,0,-.55),.15,.35,"amber")
        a.arrow((.34,-.37,.13),.49,"green")
        a.tube("slow_penalty_charge",[(-.36,0,-.24),(-.02,0,-.70),(.32,0,-.66)],.055,"copper")
    elif a.id=="four_symptom_seal":
        a.frame((0,0,0),1.42,1.42,"gold")
        for x,z,mat in ((-.34,.34,"red"),(.34,.34,"purple"),(-.34,-.34,"amber"),(.34,-.34,"blue")):
            a.cyl("symptom_medallion",(x,-.03,z),.27,.15,mat)
            a.ring("symptom_bezel",(x,-.12,z),.25,.035,"brass")
        a.cyl("timeline_stop_seal",(0,-.25,0),.26,.11,"dark")
        for x in (-.08,.08): a.box("stop_engraving",(x,-.32,0),(.07,.04,.29),"gold")
    elif a.id=="quarantine_buffer":
        a.capsule((0,0,0),.41,1.48,"purple")
        a.frame((0,0,0),1.03,1.75,"edge")
        a.dial((0,-.45,.06),.33,-45,"white",6)
        a.box("quarantine_shutoff",(.56,0,-.13),(.29,.38,.61),"brass")
        a.ring("shutoff_handle",(.62,-.21,-.11),.21,.05,"red")
    elif a.id=="symptom_transfer_paper":
        a.box("status_transfer_chassis",(0,.13,0),(1.33,.44,.78),"steel")
        for x in (-.54,.54): a.cyl("transfer_roller",(x,-.20,0),.14,.93,"brass",(0,0,0))
        a.scroll((0,-.30,-.03),.84,1.16)
        for x in (-.26,0,.26): a.cyl("absorbed_status_stamp",(x,-.36,.18),.075,.025,"purple")
        a.arrow((0,-.40,-.31),.59,"red",90)
        a.capsule((-.71,0,.10),.13,.55,"green")
        a.capsule((.71,0,.10),.13,.55,"red")
    elif a.id=="critical_pathology_meter":
        a.box("pathology_meter_housing",(0,.09,-.14),(1.55,.41,.98),"dark")
        for i,color in enumerate(("red","amber","purple","blue")):
            a.capsule((-.54+i*.36,-.13,.27),.12,.74,color)
        a.dial((0,-.29,-.45),.31,135)
        a.cyl("terminal_status_reaction",(.63,-.18,-.38),.12,.06,"red")
        a.profile("bleed_final_tick",[(-.09,.22),(-.18,-.02),(-.1,-.18),(.1,-.18),(.18,-.02)],.05,"red",(-.62,-.25,-.42))


def imprint(a):
    if a.id=="solar_pinion":
        a.gear((-.12,0,.10),.73,24,"gold")
        a.card((.21,-.15,-.14),.72,"amber",15)
        a.dial((-.58,-.15,-.55),.25,30,"white",8)
        a.dial((.57,-.15,.61),.21,-30,"blue",8)
        a.cyl("solar_imprint_stamp",(-.11,-.25,.11),.17,.10,"gold")
    elif a.id=="overcharge_confection_furnace":
        a.box("overcharge_furnace",(0,.10,-.08),(1.16,.65,1.20),"dark")
        a.card((0,-.30,.05),.64,"amber")
        for x in (-.51,.51): a.coil((x,-.02,.04),.12,.87,9)
        a.dial((.0,-.34,-.68),.28,115,"white",12)
        a.cyl("sixty_second_safety_valve",(.41,0,.72),.14,.31,"brass",(0,0,0))
        a.tube("amplification_chamber",[(-.35,0,.60),(0,0,.92),(.33,0,.60)],.085,"amber")
    elif a.id=="polarization_converter":
        a.frame((0,0,0),1.60,.75,"steel")
        a.cyl("rotating_conversion_prism",(0,-.03,0),.39,.62,"purple",(0,0,0),n=3)
        a.profile("attack_polarity_blade",[(-.09,-.42),(.09,-.42),(.09,.29),(0,.47),(-.09,.29)],.10,"red",(-.61,-.10,0))
        a.shield((.61,-.12,.0),.52,"blue")
        a.gear((0,-.33,-.58),.26,12)
        for x,mat in ((-.33,"red"),(.33,"blue")):
            a.tube("conversion_feed",[(x*1.8,0,-.29),(x,0,-.52),(x*.25,0,-.47)],.04,mat)
    elif a.id=="balanced_three_phase_unit":
        a.card((0,-.10,0),.78,"white")
        for i,mat in enumerate(("blue","amber","green")):
            t=math.tau*i/3
            p=(.73*math.sin(t),0,.73*math.cos(t))
            a.dial(p,.28,30+i*75,mat,8)
            a.rod("normalization_phase_terminal",(0,.04,0),p,.070,"brass")
        a.cyl("effect_cap_regulator",(0,-.24,0),.20,.12,"gold")


def progression(a):
    if a.id=="seven_step_validator":
        for i in range(7):
            x=-.72+i*.24; ht=.25+i*.17
            a.box("seven_step_counter",(x,0,-.59+ht*.5),(.20,.30,ht),"brass")
            if i in (0,2,4,6): a.cyl("milestone_light",(x,-.17,-.56+ht),.052,.05,"green")
        a.card((-.50,-.25,-.06),.42,"blue",-12)
        a.gear((.48,-.27,.14),.24,12,"gold")
    elif a.id=="depth_pressure_gauge":
        a.dial((0,-.02,.29),.61,120,"white",16)
        for x in (-.50,0,.50):
            a.capsule((x,.02,-.59),.15,.42,"blue")
            a.rod("wave_slot_pipe",(x,0,-.39),(x*.60,0,-.11),.045,"copper")
        a.ring("cast_load_valve",(.66,0,-.24),.22,.05,"red")
        a.box("wave_counter",(-.59,-.21,.42),(.30,.20,.48),"dark")
    elif a.id=="emergency_recovery_line":
        a.ring("emergency_lifeline_reel",(-.10,0,.11),.64,.12,"white")
        a.tube("recovery_hose",[(-.55,-.10,.31),(-.24,-.18,.62),(.42,-.12,.33),(.41,-.11,-.31),(.70,-.10,-.60)],.074,"red")
        a.box("withdrawal_lever",(.63,0,-.10),(.13,.23,.72),"steel",(0,-18,0))
        a.sphere("withdrawal_lever_handle",(.75,0,.27),(.24,.18,.24),"red")
        a.cyl("one_hp_survival_light",(-.15,-.16,-.28),.20,.10,"green")
        a.box("one_hp_marker",(-.15,-.23,-.28),(.07,.035,.23),"white")
    elif a.id=="defeat_wiring":
        a.box("comeback_wiring_board",(0,.07,0),(1.44,.19,1.44),"dark")
        for i in range(4):
            x=-.53+i*.35
            a.card((x,-.12,.36),.26,"blue")
            a.tube("loss_to_next_slot_wire",[(-.47,-.16,-.45),(x,-.20,-.18),(x,-.16,.14)],.033,"red")
        a.dial((.36,-.17,-.45),.28,90,"white",12)
        a.cyl("comeback_connector",(-.47,-.20,-.45),.16,.08,"gold")
    elif a.id=="overtime_key":
        a.ring("double_key_handle",(0,0,.52),.38,.09,"gold")
        for side,mat in ((-1,"green"),(1,"red")):
            a.box("wins_losses_key_shank",(side*.20,0,-.22),(.15,.18,1.02),"steel")
            for z in (-.42,-.63): a.box("overtime_key_tooth",(side*.32,0,z),(.30,.18,.10),"brass")
            a.cyl("wins_losses_setting",(side*.20,-.12,.51),.09,.05,mat)
        a.gear((0,.09,-.85),.28,12)
    elif a.id=="loop_wear_wheel":
        a.gear((0,0,0),.74,28)
        a.ring("worn_recast_track",(0,-.16,0),.48,.085,"steel")
        for i in range(28):
            t=math.tau*i/28
            a.box("infinite_cycle_tick",(.62*math.sin(t),-.14,.62*math.cos(t)),(.019,.04,.066),"dark",(0,math.degrees(t),0),.002)
        a.gear((.45,-.24,-.37),.25,12,"blue")
        a.rod("wear_shortening_needle",(0,-.26,0),(-.40,-.26,.28),.030,"gold")
        a.card((-.61,-.15,-.66),.30,"green",-20)


BUILDERS={"R01":armor,"R02":energy,"R03":clocks,"R04":navigation,
          "R05":economy,"R06":medical,"R07":loadout,"R08":pressure,
          "R09":pathology,"R10":imprint,"R11":progression}
