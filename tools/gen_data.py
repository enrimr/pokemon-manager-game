#!/usr/bin/env python3
"""Generates shared/data/{pokemon,moves,typechart,world,items}.json for Trainer Manager.
Deterministic (seeded). Run from repo root: python3 tools/gen_data.py
"""
import json, os, random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "shared", "data")
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- moves
# name: (type, power, accuracy, pp, category, [effects])
# power 0 => status / fixed. accuracy 0 => never misses.
# effect tags: burn:p para:p sleep:p poison:p freeze:p confuse:p flinch:p
#   stat:<atk|def|spa|spd|spe|acc|eva>:<+/-stages>[:chance][:self]
#   priority:n recoil:f drain:f heal:f crit:1 fixed:level fixed:n never_miss confuse_self
MOVES = {
    # Normal
    "Tackle": ("normal", 40, 100, 35, "phys", []),
    "Scratch": ("normal", 40, 100, 35, "phys", []),
    "Pound": ("normal", 40, 100, 35, "phys", []),
    "Quick Attack": ("normal", 40, 100, 30, "phys", ["priority:1"]),
    "Body Slam": ("normal", 85, 100, 15, "phys", ["para:0.3"]),
    "Hyper Beam": ("normal", 150, 90, 5, "spec", []),
    "Double-Edge": ("normal", 120, 100, 15, "phys", ["recoil:0.25"]),
    "Take Down": ("normal", 90, 85, 20, "phys", ["recoil:0.25"]),
    "Slash": ("normal", 70, 100, 20, "phys", ["crit:1"]),
    "Swift": ("normal", 60, 0, 20, "spec", ["never_miss"]),
    "Hyper Fang": ("normal", 80, 90, 15, "phys", ["flinch:0.1"]),
    "Stomp": ("normal", 65, 100, 20, "phys", ["flinch:0.3"]),
    "Mega Punch": ("normal", 80, 85, 20, "phys", []),
    "Mega Kick": ("normal", 120, 75, 5, "phys", []),
    "Horn Attack": ("normal", 65, 100, 25, "phys", []),
    "Fury Swipes": ("normal", 54, 80, 15, "phys", []),
    "Pay Day": ("normal", 40, 100, 20, "phys", []),
    "Tri Attack": ("normal", 80, 100, 10, "spec", ["para:0.07", "burn:0.07", "freeze:0.07"]),
    "Bite": ("normal", 60, 100, 25, "phys", ["flinch:0.1"]),
    "Bind": ("normal", 15, 85, 20, "phys", []),
    "Wrap": ("normal", 15, 90, 20, "phys", []),
    "Growl": ("normal", 0, 100, 40, "status", ["stat:atk:-1"]),
    "Tail Whip": ("normal", 0, 100, 30, "status", ["stat:def:-1"]),
    "Leer": ("normal", 0, 100, 30, "status", ["stat:def:-1"]),
    "Screech": ("normal", 0, 85, 40, "status", ["stat:def:-2"]),
    "Swords Dance": ("normal", 0, 0, 20, "status", ["stat:atk:+2:1:self"]),
    "Sharpen": ("normal", 0, 0, 30, "status", ["stat:atk:+1:1:self"]),
    "Harden": ("normal", 0, 0, 30, "status", ["stat:def:+1:1:self"]),
    "Defense Curl": ("normal", 0, 0, 40, "status", ["stat:def:+1:1:self"]),
    "Growth": ("normal", 0, 0, 20, "status", ["stat:spa:+1:1:self"]),
    "Recover": ("normal", 0, 0, 10, "status", ["heal:0.5"]),
    "Soft-Boiled": ("normal", 0, 0, 10, "status", ["heal:0.5"]),
    "Rest": ("psychic", 0, 0, 10, "status", ["heal:1.0"]),
    "Sing": ("normal", 0, 55, 15, "status", ["sleep:1.0"]),
    "Supersonic": ("normal", 0, 55, 20, "status", ["confuse:1.0"]),
    "Glare": ("normal", 0, 75, 30, "status", ["para:1.0"]),
    "Lovely Kiss": ("normal", 0, 75, 10, "status", ["sleep:1.0"]),
    "Double Team": ("normal", 0, 0, 15, "status", ["stat:eva:+1:1:self"]),
    "Minimize": ("normal", 0, 0, 10, "status", ["stat:eva:+1:1:self"]),
    "Smokescreen": ("normal", 0, 100, 20, "status", ["stat:acc:-1"]),
    "Flash": ("normal", 0, 100, 20, "status", ["stat:acc:-1"]),
    "Splash": ("normal", 0, 0, 40, "status", []),
    # Fire
    "Ember": ("fire", 40, 100, 25, "spec", ["burn:0.1"]),
    "Flamethrower": ("fire", 90, 100, 15, "spec", ["burn:0.1"]),
    "Fire Blast": ("fire", 110, 85, 5, "spec", ["burn:0.1"]),
    "Fire Punch": ("fire", 75, 100, 15, "phys", ["burn:0.1"]),
    "Fire Spin": ("fire", 35, 85, 15, "spec", []),
    "Flame Wheel": ("fire", 60, 100, 25, "phys", ["burn:0.1"]),
    # Water
    "Water Gun": ("water", 40, 100, 25, "spec", []),
    "Bubble Beam": ("water", 65, 100, 20, "spec", ["stat:spe:-1:0.1"]),
    "Bubble": ("water", 40, 100, 30, "spec", ["stat:spe:-1:0.1"]),
    "Surf": ("water", 90, 100, 15, "spec", []),
    "Hydro Pump": ("water", 110, 80, 5, "spec", []),
    "Waterfall": ("water", 80, 100, 15, "phys", ["flinch:0.2"]),
    "Crabhammer": ("water", 100, 90, 10, "phys", ["crit:1"]),
    "Clamp": ("water", 35, 85, 15, "phys", []),
    "Withdraw": ("water", 0, 0, 40, "status", ["stat:def:+1:1:self"]),
    # Grass
    "Vine Whip": ("grass", 45, 100, 25, "phys", []),
    "Razor Leaf": ("grass", 55, 95, 25, "phys", ["crit:1"]),
    "Solar Beam": ("grass", 120, 100, 10, "spec", []),
    "Mega Drain": ("grass", 40, 100, 15, "spec", ["drain:0.5"]),
    "Absorb": ("grass", 20, 100, 25, "spec", ["drain:0.5"]),
    "Petal Dance": ("grass", 120, 100, 10, "spec", ["confuse_self"]),
    "Leech Seed": ("grass", 0, 90, 10, "status", ["poison:1.0"]),
    "Sleep Powder": ("grass", 0, 75, 15, "status", ["sleep:1.0"]),
    "Stun Spore": ("grass", 0, 75, 30, "status", ["para:1.0"]),
    "Poison Powder": ("poison", 0, 75, 35, "status", ["poison:1.0"]),
    "Spore": ("grass", 0, 100, 15, "status", ["sleep:1.0"]),
    # Electric
    "Thunder Shock": ("electric", 40, 100, 30, "spec", ["para:0.1"]),
    "Thunderbolt": ("electric", 90, 100, 15, "spec", ["para:0.1"]),
    "Thunder": ("electric", 110, 70, 10, "spec", ["para:0.3"]),
    "Thunder Punch": ("electric", 75, 100, 15, "phys", ["para:0.1"]),
    "Thunder Wave": ("electric", 0, 90, 20, "status", ["para:1.0"]),
    # Ice
    "Ice Beam": ("ice", 90, 100, 10, "spec", ["freeze:0.1"]),
    "Blizzard": ("ice", 110, 70, 5, "spec", ["freeze:0.1"]),
    "Ice Punch": ("ice", 75, 100, 15, "phys", ["freeze:0.1"]),
    "Aurora Beam": ("ice", 65, 100, 20, "spec", ["stat:atk:-1:0.1"]),
    "Icy Wind": ("ice", 55, 95, 15, "spec", ["stat:spe:-1:1.0"]),
    "Mist": ("ice", 0, 0, 30, "status", ["stat:spd:+1:1:self"]),
    # Fighting
    "Karate Chop": ("fighting", 50, 100, 25, "phys", ["crit:1"]),
    "Low Kick": ("fighting", 65, 100, 20, "phys", ["flinch:0.3"]),
    "Double Kick": ("fighting", 60, 100, 30, "phys", []),
    "Seismic Toss": ("fighting", 0, 100, 20, "phys", ["fixed:level"]),
    "Submission": ("fighting", 80, 80, 20, "phys", ["recoil:0.25"]),
    "High Jump Kick": ("fighting", 130, 90, 10, "phys", ["recoil:0.15"]),
    "Rolling Kick": ("fighting", 60, 85, 15, "phys", ["flinch:0.3"]),
    "Jump Kick": ("fighting", 100, 95, 10, "phys", ["recoil:0.15"]),
    "Meditate": ("psychic", 0, 0, 40, "status", ["stat:atk:+1:1:self"]),
    # Poison
    "Poison Sting": ("poison", 15, 100, 35, "phys", ["poison:0.3"]),
    "Sludge": ("poison", 65, 100, 20, "spec", ["poison:0.3"]),
    "Acid": ("poison", 40, 100, 30, "spec", ["stat:def:-1:0.1"]),
    "Smog": ("poison", 30, 70, 20, "spec", ["poison:0.4"]),
    "Toxic": ("poison", 0, 90, 10, "status", ["poison:1.0"]),
    "Poison Gas": ("poison", 0, 55, 40, "status", ["poison:1.0"]),
    "Acid Armor": ("poison", 0, 0, 20, "status", ["stat:def:+2:1:self"]),
    # Ground
    "Earthquake": ("ground", 100, 100, 10, "phys", []),
    "Dig": ("ground", 80, 100, 10, "phys", []),
    "Bone Club": ("ground", 65, 85, 20, "phys", ["flinch:0.1"]),
    "Bonemerang": ("ground", 90, 90, 10, "phys", []),
    "Sand Attack": ("ground", 0, 100, 15, "status", ["stat:acc:-1"]),
    # Rock
    "Rock Slide": ("rock", 75, 90, 10, "phys", ["flinch:0.3"]),
    "Rock Throw": ("rock", 50, 90, 15, "phys", []),
    # Flying
    "Gust": ("flying", 40, 100, 35, "spec", []),
    "Wing Attack": ("flying", 60, 100, 35, "phys", []),
    "Drill Peck": ("flying", 80, 100, 20, "phys", []),
    "Peck": ("flying", 35, 100, 35, "phys", []),
    "Fly": ("flying", 90, 95, 15, "phys", []),
    "Sky Attack": ("flying", 140, 90, 5, "phys", ["crit:1"]),
    # Psychic
    "Confusion": ("psychic", 50, 100, 25, "spec", ["confuse:0.1"]),
    "Psychic": ("psychic", 90, 100, 10, "spec", ["stat:spd:-1:0.1"]),
    "Psybeam": ("psychic", 65, 100, 20, "spec", ["confuse:0.1"]),
    "Hypnosis": ("psychic", 0, 60, 20, "status", ["sleep:1.0"]),
    "Dream Eater": ("psychic", 100, 100, 15, "spec", ["drain:0.5"]),
    "Amnesia": ("psychic", 0, 0, 20, "status", ["stat:spd:+2:1:self"]),
    "Barrier": ("psychic", 0, 0, 20, "status", ["stat:def:+2:1:self"]),
    "Agility": ("psychic", 0, 0, 30, "status", ["stat:spe:+2:1:self"]),
    "Light Screen": ("psychic", 0, 0, 30, "status", ["stat:spd:+1:1:self"]),
    "Reflect": ("psychic", 0, 0, 20, "status", ["stat:def:+1:1:self"]),
    "Kinesis": ("psychic", 0, 80, 15, "status", ["stat:acc:-1"]),
    "Psywave": ("psychic", 0, 80, 15, "spec", ["fixed:level"]),
    # Bug
    "Twineedle": ("bug", 50, 100, 20, "phys", ["poison:0.2"]),
    "Pin Missile": ("bug", 50, 95, 20, "phys", []),
    "Leech Life": ("bug", 30, 100, 15, "phys", ["drain:0.5"]),
    "String Shot": ("bug", 0, 95, 40, "status", ["stat:spe:-1"]),
    # Ghost
    "Lick": ("ghost", 30, 100, 30, "phys", ["para:0.3"]),
    "Night Shade": ("ghost", 0, 100, 15, "spec", ["fixed:level"]),
    "Confuse Ray": ("ghost", 0, 100, 10, "status", ["confuse:1.0"]),
    # Dragon
    "Dragon Rage": ("dragon", 0, 100, 10, "spec", ["fixed:40"]),
    "Outrage": ("dragon", 120, 100, 10, "phys", ["confuse_self"]),
    "Dragon Breath": ("dragon", 60, 100, 20, "spec", ["para:0.3"]),
    # Extra normals to pad staples
    "Headbutt": ("normal", 70, 100, 15, "phys", ["flinch:0.3"]),
    "Strength": ("normal", 80, 100, 15, "phys", []),
    "Cut": ("normal", 50, 95, 30, "phys", []),
    "Focus Energy": ("normal", 0, 0, 30, "status", ["crit:1"]),
    "Explosion": ("normal", 250, 100, 5, "phys", ["recoil:1.0"]),
    "Self-Destruct": ("normal", 200, 100, 5, "phys", ["recoil:1.0"]),
}

TYPES = ["normal", "fire", "water", "grass", "electric", "ice", "fighting", "poison",
         "ground", "flying", "psychic", "bug", "rock", "ghost", "dragon"]

# ---------------------------------------------------------------- items
# Two classes:
#   "held"   — passive while held in battle (assigned to a Pokémon's held_item slot)
#   "usable" — consumed as a trainer action during battle ({"type":"use_item",...})
# Effect tag grammar (colon-separated, consumed by BattleEngine — see ARCHITECTURE.md):
#   held:  end_turn_heal:f  choice:<atk|spa|spe>:mult  sash  life_orb  quick_claw:p
#          rocky_helmet:f  assault_vest  eviolite  shell_bell:f  kings_rock:p
#          bright_powder:f  scope_lens  type_boost:<type>:mult
#          cure_berry:<status|confuse|all>  sitrus:f (heal f*max_hp when <=50%, once)
#   usable: heal:<n|full>  cure:<status|confuse|all>  full_restore  revive:f
#           xstat:<stat>:stages  dire_hit  guard_spec
# name: (class, price, rarity, [effects], description)
ITEMS = {
    # --- held: battle staples
    "leftovers":     ("Leftovers", "held", 4000, "rare", ["end_turn_heal:0.0625"],
                      "The holder restores 1/16 of its max HP at the end of every turn."),
    "choice_band":   ("Choice Band", "held", 5000, "rare", ["choice:atk:1.5"],
                      "Boosts Attack by 50%, but locks the holder into the first move it uses."),
    "choice_specs":  ("Choice Specs", "held", 5000, "rare", ["choice:spa:1.5"],
                      "Boosts Sp. Atk by 50%, but locks the holder into the first move it uses."),
    "choice_scarf":  ("Choice Scarf", "held", 5000, "rare", ["choice:spe:1.5"],
                      "Boosts Speed by 50%, but locks the holder into the first move it uses."),
    "focus_sash":    ("Focus Sash", "held", 3000, "rare", ["sash"],
                      "If the holder is at full HP, it survives a knockout blow with 1 HP. Single use."),
    "life_orb":      ("Life Orb", "held", 5000, "rare", ["life_orb"],
                      "Boosts move damage by 30%, but the holder loses 10% max HP after each attack."),
    "quick_claw":    ("Quick Claw", "held", 2500, "uncommon", ["quick_claw:0.2"],
                      "20% chance each turn for the holder to move first within its priority bracket."),
    "rocky_helmet":  ("Rocky Helmet", "held", 3000, "uncommon", ["rocky_helmet:0.166"],
                      "Attackers striking the holder with physical moves lose 1/6 of their max HP."),
    "assault_vest":  ("Assault Vest", "held", 4500, "rare", ["assault_vest"],
                      "Raises Sp. Def by 50%, but the holder cannot select status moves."),
    "eviolite":      ("Eviolite", "held", 4500, "rare", ["eviolite"],
                      "Raises Defense and Sp. Def by 50% if the holder can still evolve."),
    "shell_bell":    ("Shell Bell", "held", 2500, "uncommon", ["shell_bell:0.125"],
                      "The holder restores HP equal to 1/8 of the damage it deals."),
    "kings_rock":    ("King's Rock", "held", 2500, "uncommon", ["kings_rock:0.1"],
                      "The holder's damaging moves gain a 10% chance to make the target flinch."),
    "bright_powder": ("Bright Powder", "held", 2500, "uncommon", ["bright_powder:0.9"],
                      "Moves aimed at the holder are 10% less accurate."),
    "scope_lens":    ("Scope Lens", "held", 2000, "uncommon", ["scope_lens"],
                      "Doubles the holder's critical-hit chance."),
    # --- held: type boosters (1.2x damage of matching-type moves)
    "silk_scarf":    ("Silk Scarf", "held", 1500, "common", ["type_boost:normal:1.2"],
                      "Boosts the power of the holder's Normal-type moves by 20%."),
    "charcoal":      ("Charcoal", "held", 1500, "common", ["type_boost:fire:1.2"],
                      "Boosts the power of the holder's Fire-type moves by 20%."),
    "mystic_water":  ("Mystic Water", "held", 1500, "common", ["type_boost:water:1.2"],
                      "Boosts the power of the holder's Water-type moves by 20%."),
    "miracle_seed":  ("Miracle Seed", "held", 1500, "common", ["type_boost:grass:1.2"],
                      "Boosts the power of the holder's Grass-type moves by 20%."),
    "magnet":        ("Magnet", "held", 1500, "common", ["type_boost:electric:1.2"],
                      "Boosts the power of the holder's Electric-type moves by 20%."),
    "never_melt_ice":("Never-Melt Ice", "held", 1500, "common", ["type_boost:ice:1.2"],
                      "Boosts the power of the holder's Ice-type moves by 20%."),
    "black_belt":    ("Black Belt", "held", 1500, "common", ["type_boost:fighting:1.2"],
                      "Boosts the power of the holder's Fighting-type moves by 20%."),
    "poison_barb":   ("Poison Barb", "held", 1500, "common", ["type_boost:poison:1.2"],
                      "Boosts the power of the holder's Poison-type moves by 20%."),
    "soft_sand":     ("Soft Sand", "held", 1500, "common", ["type_boost:ground:1.2"],
                      "Boosts the power of the holder's Ground-type moves by 20%."),
    "sharp_beak":    ("Sharp Beak", "held", 1500, "common", ["type_boost:flying:1.2"],
                      "Boosts the power of the holder's Flying-type moves by 20%."),
    "twisted_spoon": ("Twisted Spoon", "held", 1500, "common", ["type_boost:psychic:1.2"],
                      "Boosts the power of the holder's Psychic-type moves by 20%."),
    "silver_powder": ("Silver Powder", "held", 1500, "common", ["type_boost:bug:1.2"],
                      "Boosts the power of the holder's Bug-type moves by 20%."),
    "hard_stone":    ("Hard Stone", "held", 1500, "common", ["type_boost:rock:1.2"],
                      "Boosts the power of the holder's Rock-type moves by 20%."),
    "spell_tag":     ("Spell Tag", "held", 1500, "common", ["type_boost:ghost:1.2"],
                      "Boosts the power of the holder's Ghost-type moves by 20%."),
    "dragon_fang":   ("Dragon Fang", "held", 1500, "common", ["type_boost:dragon:1.2"],
                      "Boosts the power of the holder's Dragon-type moves by 20%."),
    # --- held: berries (consumed when they trigger)
    "lum_berry":     ("Lum Berry", "held", 1200, "uncommon", ["cure_berry:all"],
                      "Cures the holder of any status condition or confusion the moment it strikes. Single use."),
    "sitrus_berry":  ("Sitrus Berry", "held", 800, "uncommon", ["sitrus:0.25"],
                      "Restores 25% max HP when the holder drops to half health or below. Single use."),
    "chesto_berry":  ("Chesto Berry", "held", 500, "common", ["cure_berry:sleep"],
                      "Wakes the holder the moment it falls asleep. Single use."),
    "cheri_berry":   ("Cheri Berry", "held", 500, "common", ["cure_berry:para"],
                      "Cures the holder of paralysis the moment it is inflicted. Single use."),
    "rawst_berry":   ("Rawst Berry", "held", 500, "common", ["cure_berry:burn"],
                      "Heals the holder's burn the moment it is inflicted. Single use."),
    "pecha_berry":   ("Pecha Berry", "held", 500, "common", ["cure_berry:poison"],
                      "Cures the holder of poison the moment it is inflicted. Single use."),
    "aspear_berry":  ("Aspear Berry", "held", 500, "common", ["cure_berry:freeze"],
                      "Thaws the holder the moment it is frozen. Single use."),
    "persim_berry":  ("Persim Berry", "held", 500, "common", ["cure_berry:confuse"],
                      "Snaps the holder out of confusion the moment it sets in. Single use."),
    # --- usable: healing (a trainer action; costs the Pokémon's turn)
    "potion":        ("Potion", "usable", 200, "common", ["heal:20"],
                      "Restores 20 HP to one of your Pokémon."),
    "super_potion":  ("Super Potion", "usable", 700, "common", ["heal:60"],
                      "Restores 60 HP to one of your Pokémon."),
    "hyper_potion":  ("Hyper Potion", "usable", 1500, "uncommon", ["heal:120"],
                      "Restores 120 HP to one of your Pokémon."),
    "max_potion":    ("Max Potion", "usable", 2500, "rare", ["heal:full"],
                      "Fully restores one of your Pokémon's HP."),
    "full_restore":  ("Full Restore", "usable", 3000, "rare", ["full_restore"],
                      "Fully restores HP and cures all status conditions and confusion."),
    "antidote":      ("Antidote", "usable", 100, "common", ["cure:poison"],
                      "Cures a poisoned Pokémon."),
    "awakening":     ("Awakening", "usable", 150, "common", ["cure:sleep"],
                      "Wakes a sleeping Pokémon."),
    "burn_heal":     ("Burn Heal", "usable", 150, "common", ["cure:burn"],
                      "Heals a burned Pokémon."),
    "ice_heal":      ("Ice Heal", "usable", 150, "common", ["cure:freeze"],
                      "Thaws a frozen Pokémon."),
    "paralyze_heal": ("Paralyze Heal", "usable", 150, "common", ["cure:para"],
                      "Cures a paralyzed Pokémon."),
    "full_heal":     ("Full Heal", "usable", 400, "uncommon", ["cure:all"],
                      "Cures all status conditions and confusion on one Pokémon."),
    "revive":        ("Revive", "usable", 2000, "rare", ["revive:0.5"],
                      "Revives a fainted Pokémon with half its max HP."),
    "max_revive":    ("Max Revive", "usable", 4000, "rare", ["revive:1.0"],
                      "Revives a fainted Pokémon with full HP."),
    "x_attack":      ("X Attack", "usable", 500, "common", ["xstat:atk:1"],
                      "Sharply focuses your active Pokémon: raises Attack by one stage."),
    "x_defense":     ("X Defense", "usable", 500, "common", ["xstat:def:1"],
                      "Raises your active Pokémon's Defense by one stage."),
    "x_sp_atk":      ("X Sp. Atk", "usable", 500, "common", ["xstat:spa:1"],
                      "Raises your active Pokémon's Sp. Atk by one stage."),
    "x_sp_def":      ("X Sp. Def", "usable", 500, "common", ["xstat:spd:1"],
                      "Raises your active Pokémon's Sp. Def by one stage."),
    "x_speed":       ("X Speed", "usable", 500, "common", ["xstat:spe:1"],
                      "Raises your active Pokémon's Speed by one stage."),
    "dire_hit":      ("Dire Hit", "usable", 600, "uncommon", ["dire_hit"],
                      "Doubles your active Pokémon's critical-hit chance for the rest of the battle."),
    "guard_spec":    ("Guard Spec.", "usable", 700, "uncommon", ["guard_spec"],
                      "Prevents the opponent from lowering your active Pokémon's stats for 5 turns."),
}

TYPE_BOOST_BY_TYPE = {}
for _iid, _it in ITEMS.items():
    for _fx in _it[4]:
        if _fx.startswith("type_boost:"):
            TYPE_BOOST_BY_TYPE[_fx.split(":")[1]] = _iid

# Gen-1 style effectiveness chart. chart[attacker][defender] = multiplier (missing = 1.0)
CHART = {
    "normal":   {"rock": 0.5, "ghost": 0.0},
    "fire":     {"fire": 0.5, "water": 0.5, "grass": 2, "ice": 2, "bug": 2, "rock": 0.5, "dragon": 0.5},
    "water":    {"fire": 2, "water": 0.5, "grass": 0.5, "ground": 2, "rock": 2, "dragon": 0.5},
    "grass":    {"fire": 0.5, "water": 2, "grass": 0.5, "poison": 0.5, "ground": 2, "flying": 0.5, "bug": 0.5, "rock": 2, "dragon": 0.5},
    "electric": {"water": 2, "grass": 0.5, "electric": 0.5, "ground": 0.0, "flying": 2, "dragon": 0.5},
    "ice":      {"fire": 0.5, "water": 0.5, "grass": 2, "ice": 0.5, "ground": 2, "flying": 2, "dragon": 2},
    "fighting": {"normal": 2, "ice": 2, "poison": 0.5, "flying": 0.5, "psychic": 0.5, "bug": 0.5, "rock": 2, "ghost": 0.0},
    "poison":   {"grass": 2, "poison": 0.5, "ground": 0.5, "bug": 2, "rock": 0.5, "ghost": 0.5},
    "ground":   {"fire": 2, "grass": 0.5, "electric": 2, "poison": 2, "flying": 0.0, "bug": 0.5, "rock": 2},
    "flying":   {"grass": 2, "electric": 0.5, "fighting": 2, "bug": 2, "rock": 0.5},
    "psychic":  {"fighting": 2, "poison": 2, "psychic": 0.5},
    "bug":      {"fire": 0.5, "grass": 2, "fighting": 0.5, "poison": 2, "flying": 0.5, "psychic": 2, "ghost": 0.5},
    "rock":     {"fire": 2, "ice": 2, "fighting": 0.5, "ground": 0.5, "flying": 2, "bug": 2},
    "ghost":    {"normal": 0.0, "psychic": 0.0, "ghost": 2},
    "dragon":   {"dragon": 2},
}

# ---------------------------------------------------------------- pokemon
# (id, name, type1, type2|None, hp, atk, def, spa, spd, spe, growth)
P = [
    (1,"Bulbasaur","grass","poison",45,49,49,65,65,45,"medium_slow"),
    (2,"Ivysaur","grass","poison",60,62,63,80,80,60,"medium_slow"),
    (3,"Venusaur","grass","poison",80,82,83,100,100,80,"medium_slow"),
    (4,"Charmander","fire",None,39,52,43,60,50,65,"medium_slow"),
    (5,"Charmeleon","fire",None,58,64,58,80,65,80,"medium_slow"),
    (6,"Charizard","fire","flying",78,84,78,109,85,100,"medium_slow"),
    (7,"Squirtle","water",None,44,48,65,50,64,43,"medium_slow"),
    (8,"Wartortle","water",None,59,63,80,65,80,58,"medium_slow"),
    (9,"Blastoise","water",None,79,83,100,85,105,78,"medium_slow"),
    (10,"Caterpie","bug",None,45,30,35,20,20,45,"medium_fast"),
    (11,"Metapod","bug",None,50,20,55,25,25,30,"medium_fast"),
    (12,"Butterfree","bug","flying",60,45,50,90,80,70,"medium_fast"),
    (13,"Weedle","bug","poison",40,35,30,20,20,50,"medium_fast"),
    (14,"Kakuna","bug","poison",45,25,50,25,25,35,"medium_fast"),
    (15,"Beedrill","bug","poison",65,90,40,45,80,75,"medium_fast"),
    (16,"Pidgey","normal","flying",40,45,40,35,35,56,"medium_slow"),
    (17,"Pidgeotto","normal","flying",63,60,55,50,50,71,"medium_slow"),
    (18,"Pidgeot","normal","flying",83,80,75,70,70,101,"medium_slow"),
    (19,"Rattata","normal",None,30,56,35,25,35,72,"medium_fast"),
    (20,"Raticate","normal",None,55,81,60,50,70,97,"medium_fast"),
    (21,"Spearow","normal","flying",40,60,30,31,31,70,"medium_fast"),
    (22,"Fearow","normal","flying",65,90,65,61,61,100,"medium_fast"),
    (23,"Ekans","poison",None,35,60,44,40,54,55,"medium_fast"),
    (24,"Arbok","poison",None,60,95,69,65,79,80,"medium_fast"),
    (25,"Pikachu","electric",None,35,55,40,50,50,90,"medium_fast"),
    (26,"Raichu","electric",None,60,90,55,90,80,110,"medium_fast"),
    (27,"Sandshrew","ground",None,50,75,85,20,30,40,"medium_fast"),
    (28,"Sandslash","ground",None,75,100,110,45,55,65,"medium_fast"),
    (29,"Nidoran F","poison",None,55,47,52,40,40,41,"medium_slow"),
    (30,"Nidorina","poison",None,70,62,67,55,55,56,"medium_slow"),
    (31,"Nidoqueen","poison","ground",90,92,87,75,85,76,"medium_slow"),
    (32,"Nidoran M","poison",None,46,57,40,40,40,50,"medium_slow"),
    (33,"Nidorino","poison",None,61,72,57,55,55,65,"medium_slow"),
    (34,"Nidoking","poison","ground",81,102,77,85,75,85,"medium_slow"),
    (35,"Clefairy","normal",None,70,45,48,60,65,35,"fast"),
    (36,"Clefable","normal",None,95,70,73,95,90,60,"fast"),
    (37,"Vulpix","fire",None,38,41,40,50,65,65,"medium_fast"),
    (38,"Ninetales","fire",None,73,76,75,81,100,100,"medium_fast"),
    (39,"Jigglypuff","normal",None,115,45,20,45,25,20,"fast"),
    (40,"Wigglytuff","normal",None,140,70,45,85,50,45,"fast"),
    (41,"Zubat","poison","flying",40,45,35,30,40,55,"medium_fast"),
    (42,"Golbat","poison","flying",75,80,70,65,75,90,"medium_fast"),
    (43,"Oddish","grass","poison",45,50,55,75,65,30,"medium_slow"),
    (44,"Gloom","grass","poison",60,65,70,85,75,40,"medium_slow"),
    (45,"Vileplume","grass","poison",75,80,85,110,90,50,"medium_slow"),
    (46,"Paras","bug","grass",35,70,55,45,55,25,"medium_fast"),
    (47,"Parasect","bug","grass",60,95,80,60,80,30,"medium_fast"),
    (48,"Venonat","bug","poison",60,55,50,40,55,45,"medium_fast"),
    (49,"Venomoth","bug","poison",70,65,60,90,75,90,"medium_fast"),
    (50,"Diglett","ground",None,10,55,25,35,45,95,"medium_fast"),
    (51,"Dugtrio","ground",None,35,100,50,50,70,120,"medium_fast"),
    (52,"Meowth","normal",None,40,45,35,40,40,90,"medium_fast"),
    (53,"Persian","normal",None,65,70,60,65,65,115,"medium_fast"),
    (54,"Psyduck","water",None,50,52,48,65,50,55,"medium_fast"),
    (55,"Golduck","water",None,80,82,78,95,80,85,"medium_fast"),
    (56,"Mankey","fighting",None,40,80,35,35,45,70,"medium_fast"),
    (57,"Primeape","fighting",None,65,105,60,60,70,95,"medium_fast"),
    (58,"Growlithe","fire",None,55,70,45,70,50,60,"slow"),
    (59,"Arcanine","fire",None,90,110,80,100,80,95,"slow"),
    (60,"Poliwag","water",None,40,50,40,40,40,90,"medium_slow"),
    (61,"Poliwhirl","water",None,65,65,65,50,50,90,"medium_slow"),
    (62,"Poliwrath","water","fighting",90,95,95,70,90,70,"medium_slow"),
    (63,"Abra","psychic",None,25,20,15,105,55,90,"medium_slow"),
    (64,"Kadabra","psychic",None,40,35,30,120,70,105,"medium_slow"),
    (65,"Alakazam","psychic",None,55,50,45,135,95,120,"medium_slow"),
    (66,"Machop","fighting",None,70,80,50,35,35,35,"medium_slow"),
    (67,"Machoke","fighting",None,80,100,70,50,60,45,"medium_slow"),
    (68,"Machamp","fighting",None,90,130,80,65,85,55,"medium_slow"),
    (69,"Bellsprout","grass","poison",50,75,35,70,30,40,"medium_slow"),
    (70,"Weepinbell","grass","poison",65,90,50,85,45,55,"medium_slow"),
    (71,"Victreebel","grass","poison",80,105,65,100,70,70,"medium_slow"),
    (72,"Tentacool","water","poison",40,40,35,50,100,70,"slow"),
    (73,"Tentacruel","water","poison",80,70,65,80,120,100,"slow"),
    (74,"Geodude","rock","ground",40,80,100,30,30,20,"medium_slow"),
    (75,"Graveler","rock","ground",55,95,115,45,45,35,"medium_slow"),
    (76,"Golem","rock","ground",80,120,130,55,65,45,"medium_slow"),
    (77,"Ponyta","fire",None,50,85,55,65,65,90,"medium_fast"),
    (78,"Rapidash","fire",None,65,100,70,80,80,105,"medium_fast"),
    (79,"Slowpoke","water","psychic",90,65,65,40,40,15,"medium_fast"),
    (80,"Slowbro","water","psychic",95,75,110,100,80,30,"medium_fast"),
    (81,"Magnemite","electric",None,25,35,70,95,55,45,"medium_fast"),
    (82,"Magneton","electric",None,50,60,95,120,70,70,"medium_fast"),
    (83,"Farfetch'd","normal","flying",52,90,55,58,62,60,"medium_fast"),
    (84,"Doduo","normal","flying",35,85,45,35,35,75,"medium_fast"),
    (85,"Dodrio","normal","flying",60,110,70,60,60,110,"medium_fast"),
    (86,"Seel","water",None,65,45,55,45,70,45,"medium_fast"),
    (87,"Dewgong","water","ice",90,70,80,70,95,70,"medium_fast"),
    (88,"Grimer","poison",None,80,80,50,40,50,25,"medium_fast"),
    (89,"Muk","poison",None,105,105,75,65,100,50,"medium_fast"),
    (90,"Shellder","water",None,30,65,100,45,25,40,"slow"),
    (91,"Cloyster","water","ice",50,95,180,85,45,70,"slow"),
    (92,"Gastly","ghost","poison",30,35,30,100,35,80,"medium_slow"),
    (93,"Haunter","ghost","poison",45,50,45,115,55,95,"medium_slow"),
    (94,"Gengar","ghost","poison",60,65,60,130,75,110,"medium_slow"),
    (95,"Onix","rock","ground",35,45,160,30,45,70,"medium_fast"),
    (96,"Drowzee","psychic",None,60,48,45,43,90,42,"medium_fast"),
    (97,"Hypno","psychic",None,85,73,70,73,115,67,"medium_fast"),
    (98,"Krabby","water",None,30,105,90,25,25,50,"medium_fast"),
    (99,"Kingler","water",None,55,130,115,50,50,75,"medium_fast"),
    (100,"Voltorb","electric",None,40,30,50,55,55,100,"medium_fast"),
    (101,"Electrode","electric",None,60,50,70,80,80,150,"medium_fast"),
    (102,"Exeggcute","grass","psychic",60,40,80,60,45,40,"slow"),
    (103,"Exeggutor","grass","psychic",95,95,85,125,75,55,"slow"),
    (104,"Cubone","ground",None,50,50,95,40,50,35,"medium_fast"),
    (105,"Marowak","ground",None,60,80,110,50,80,45,"medium_fast"),
    (106,"Hitmonlee","fighting",None,50,120,53,35,110,87,"medium_fast"),
    (107,"Hitmonchan","fighting",None,50,105,79,35,110,76,"medium_fast"),
    (108,"Lickitung","normal",None,90,55,75,60,75,30,"medium_fast"),
    (109,"Koffing","poison",None,40,65,95,60,45,35,"medium_fast"),
    (110,"Weezing","poison",None,65,90,120,85,70,60,"medium_fast"),
    (111,"Rhyhorn","ground","rock",80,85,95,30,30,25,"slow"),
    (112,"Rhydon","ground","rock",105,130,120,45,45,40,"slow"),
    (113,"Chansey","normal",None,250,5,5,35,105,50,"fast"),
    (114,"Tangela","grass",None,65,55,115,100,40,60,"medium_fast"),
    (115,"Kangaskhan","normal",None,105,95,80,40,80,90,"medium_fast"),
    (116,"Horsea","water",None,30,40,70,70,25,60,"medium_fast"),
    (117,"Seadra","water",None,55,65,95,95,45,85,"medium_fast"),
    (118,"Goldeen","water",None,45,67,60,35,50,63,"medium_fast"),
    (119,"Seaking","water",None,80,92,65,65,80,68,"medium_fast"),
    (120,"Staryu","water",None,30,45,55,70,55,85,"slow"),
    (121,"Starmie","water","psychic",60,75,85,100,85,115,"slow"),
    (122,"Mr. Mime","psychic",None,40,45,65,100,120,90,"medium_fast"),
    (123,"Scyther","bug","flying",70,110,80,55,80,105,"medium_fast"),
    (124,"Jynx","ice","psychic",65,50,35,115,95,95,"medium_fast"),
    (125,"Electabuzz","electric",None,65,83,57,95,85,105,"medium_fast"),
    (126,"Magmar","fire",None,65,95,57,100,85,93,"medium_fast"),
    (127,"Pinsir","bug",None,65,125,100,55,70,85,"slow"),
    (128,"Tauros","normal",None,75,100,95,40,70,110,"slow"),
    (129,"Magikarp","water",None,20,10,55,15,20,80,"slow"),
    (130,"Gyarados","water","flying",95,125,79,60,100,81,"slow"),
    (131,"Lapras","water","ice",130,85,80,85,95,60,"slow"),
    (132,"Ditto","normal",None,48,48,48,48,48,48,"medium_fast"),
    (133,"Eevee","normal",None,55,55,50,45,65,55,"medium_fast"),
    (134,"Vaporeon","water",None,130,65,60,110,95,65,"medium_fast"),
    (135,"Jolteon","electric",None,65,65,60,110,95,130,"medium_fast"),
    (136,"Flareon","fire",None,65,130,60,95,110,65,"medium_fast"),
    (137,"Porygon","normal",None,65,60,70,85,75,40,"medium_fast"),
    (138,"Omanyte","rock","water",35,40,100,90,55,35,"medium_fast"),
    (139,"Omastar","rock","water",70,60,125,115,70,55,"medium_fast"),
    (140,"Kabuto","rock","water",30,80,90,55,45,55,"medium_fast"),
    (141,"Kabutops","rock","water",60,115,105,65,70,80,"medium_fast"),
    (142,"Aerodactyl","rock","flying",80,105,65,60,75,130,"slow"),
    (143,"Snorlax","normal",None,160,110,65,65,110,30,"slow"),
    (144,"Articuno","ice","flying",90,85,100,95,125,85,"slow"),
    (145,"Zapdos","electric","flying",90,90,85,125,90,100,"slow"),
    (146,"Moltres","fire","flying",90,100,90,125,85,90,"slow"),
    (147,"Dratini","dragon",None,41,64,45,50,50,50,"slow"),
    (148,"Dragonair","dragon",None,61,84,65,70,70,70,"slow"),
    (149,"Dragonite","dragon","flying",91,134,95,100,100,80,"slow"),
    (150,"Mewtwo","psychic",None,106,110,90,154,90,130,"slow"),
    (151,"Mew","psychic",None,100,100,100,100,100,100,"medium_slow"),
]

# Type -> candidate attacking/status moves (used to build plausible learnsets)
TYPE_POOL = {
    "normal": ["Tackle", "Quick Attack", "Body Slam", "Slash", "Double-Edge", "Hyper Beam", "Headbutt", "Swift"],
    "fire": ["Ember", "Flame Wheel", "Flamethrower", "Fire Blast", "Fire Punch", "Fire Spin"],
    "water": ["Water Gun", "Bubble Beam", "Surf", "Hydro Pump", "Waterfall"],
    "grass": ["Vine Whip", "Razor Leaf", "Mega Drain", "Solar Beam", "Petal Dance", "Sleep Powder", "Stun Spore"],
    "electric": ["Thunder Shock", "Thunderbolt", "Thunder", "Thunder Wave", "Thunder Punch"],
    "ice": ["Aurora Beam", "Ice Beam", "Blizzard", "Icy Wind", "Ice Punch"],
    "fighting": ["Karate Chop", "Low Kick", "Double Kick", "Seismic Toss", "Submission", "High Jump Kick"],
    "poison": ["Poison Sting", "Acid", "Sludge", "Toxic", "Smog"],
    "ground": ["Dig", "Earthquake", "Bone Club", "Sand Attack"],
    "flying": ["Peck", "Gust", "Wing Attack", "Drill Peck", "Fly"],
    "psychic": ["Confusion", "Psybeam", "Psychic", "Hypnosis", "Agility", "Recover"],
    "bug": ["Leech Life", "Twineedle", "Pin Missile", "String Shot"],
    "rock": ["Rock Throw", "Rock Slide"],
    "ghost": ["Lick", "Night Shade", "Confuse Ray"],
    "dragon": ["Dragon Rage", "Dragon Breath", "Outrage"],
}
STATUS_POOL = ["Growl", "Tail Whip", "Leer", "Screech", "Swords Dance", "Agility",
               "Double Team", "Harden", "Focus Energy", "Reflect", "Light Screen"]
NORMAL_STAPLES_PHYS = ["Tackle", "Quick Attack", "Body Slam", "Headbutt", "Slash"]
NORMAL_STAPLES_SPEC = ["Swift", "Tackle", "Quick Attack"]

# Signature/flavour overrides (a few iconic ones)
SIGNATURE = {
    25: ["Thunderbolt", "Quick Attack", "Thunder Wave", "Agility", "Thunder"],
    129: ["Splash", "Tackle"],
    113: ["Soft-Boiled", "Body Slam", "Sing", "Light Screen", "Seismic Toss"],
    143: ["Body Slam", "Rest", "Hyper Beam", "Earthquake", "Amnesia"],
    94: ["Night Shade", "Confuse Ray", "Hypnosis", "Dream Eater", "Sludge", "Psychic"],
    65: ["Psychic", "Recover", "Psybeam", "Reflect", "Confusion"],
    68: ["Karate Chop", "Submission", "Seismic Toss", "Body Slam", "Leer"],
    149: ["Outrage", "Wing Attack", "Hyper Beam", "Agility", "Surf", "Thunder Wave"],
    150: ["Psychic", "Recover", "Barrier", "Ice Beam", "Thunderbolt", "Amnesia"],
    151: ["Psychic", "Surf", "Thunderbolt", "Soft-Boiled", "Swords Dance", "Body Slam"],
}

# Species ids that can still evolve (gen-1 lines) — drives Eviolite ("nfe").
EVOLVES = {
    1, 2, 4, 5, 7, 8, 10, 11, 13, 14, 16, 17, 19, 21, 23, 25, 27, 29, 30, 32, 33,
    35, 37, 39, 41, 43, 44, 46, 48, 50, 52, 54, 56, 58, 60, 61, 63, 64, 66, 67,
    69, 70, 72, 74, 75, 77, 79, 81, 84, 86, 88, 90, 92, 93, 96, 98, 100, 102,
    104, 109, 111, 116, 118, 120, 129, 133, 138, 140, 147, 148,
}

rng = random.Random(20260801)

def build_learnset(pid, name, t1, t2, atk, spa):
    if pid in SIGNATURE:
        base = list(SIGNATURE[pid])
    else:
        base = []
        for t in filter(None, [t1, t2]):
            pool = list(TYPE_POOL[t])
            k = min(len(pool), 3 if t2 else 4)
            base += rng.sample(pool, k)
        # a normal staple
        if t1 != "normal":
            base.append(rng.choice(NORMAL_STAPLES_PHYS if atk >= spa else NORMAL_STAPLES_SPEC))
        base.append(rng.choice(STATUS_POOL))
    # dedupe preserving order, clamp 4..8
    seen, out = set(), []
    for m in base:
        if m not in seen:
            seen.add(m)
            out.append(m)
    while len(out) < 4:
        m = rng.choice(NORMAL_STAPLES_PHYS + STATUS_POOL)
        if m not in seen:
            seen.add(m)
            out.append(m)
    return out[:8]

pokemon = []
for (pid, name, t1, t2, hp, atk, dfn, spa, spd, spe, growth) in P:
    pokemon.append({
        "id": pid, "name": name,
        "types": [t for t in [t1, t2] if t],
        "base": {"hp": hp, "atk": atk, "def": dfn, "spa": spa, "spd": spd, "spe": spe},
        "growth": growth,
        "evolves": pid in EVOLVES,
        "learnset": build_learnset(pid, name, t1, t2, atk, spa),
    })

moves_out = {}
for name, (mtype, power, acc, pp, cat, fx) in MOVES.items():
    moves_out[name] = {"type": mtype, "power": power, "accuracy": acc, "pp": pp,
                       "category": cat, "effects": fx}

# ---------------------------------------------------------------- world
CLUBS = [
    ("Viridian Vipers", "VIR"), ("Pewter Boulders", "PEW"), ("Cerulean Tides", "CER"),
    ("Vermilion Volts", "VER"), ("Lavender Phantoms", "LAV"), ("Celadon Blossoms", "CEL"),
    ("Fuchsia Fangs", "FUC"), ("Saffron Sages", "SAF"), ("Cinnabar Blaze", "CIN"),
    ("Indigo Royals", "IND"), ("Pallet Pioneers", "PAL"), ("Rock Tunnel Miners", "RTM"),
    ("Seafoam Islanders", "SEA"), ("Mt. Moon Comets", "MTM"), ("Safari Rangers", "SFR"),
    ("Victory Road Wanderers", "VRW"),
]
FIRST = ["Akira","Brendan","Carla","Daisuke","Elena","Franco","Gwen","Hiro","Ines","Jonah",
         "Kaede","Lucas","Mira","Noel","Olga","Pau","Quinn","Rosa","Silas","Tomoko",
         "Uma","Viktor","Wanda","Ximena","Yuki","Zane","Marta","Ander","Leire","Iker"]
LAST = ["Okada","Serrano","Voss","Ibarra","Kline","Duarte","Hoshino","Marchetti","Novak","Petit",
        "Reyes","Sato","Tanaka","Ulloa","Vidal","Watanabe","Yamamoto","Zubiri","Fowler","Grant",
        "Hale","Iwata","Joyce","Kimura","Lorca","Mendez","Nishida","Oteiza"]
ROLES = ["coach", "coach", "scout", "physio"]

def person_name():
    return f"{rng.choice(FIRST)} {rng.choice(LAST)}"

def month_add(y, m, delta):
    m2 = m - 1 + delta
    return y + m2 // 12, m2 % 12 + 1

uid_counter = [0]
def make_instance(species, lvl_lo, lvl_hi, salary_scale=1.0):
    uid_counter[0] += 1
    level = rng.randint(lvl_lo, lvl_hi)
    ivs = {k: rng.randint(0, 15) for k in ["hp", "atk", "def", "spa", "spd", "spe"]}
    learn = species["learnset"]
    moves = rng.sample(learn, min(4, len(learn)))
    bst = sum(species["base"].values())
    salary = int((bst * 2 + level * 40) * salary_scale * rng.uniform(0.8, 1.25))
    exp_y, exp_m = month_add(2026, 8, rng.randint(10, 46))
    return {
        "uid": f"pkm{uid_counter[0]:04d}",
        "species_id": species["id"],
        "species": species["name"],
        "nickname": None,
        "level": level,
        "ivs": ivs,
        "moves": moves,
        "held_item": None,
        "condition": rng.randint(70, 100),
        "fitness": rng.randint(75, 100),
        "morale": rng.randint(50, 95),
        "age_months": rng.randint(12, 120),
        "contract": {"salary": salary, "expiry": f"{exp_y:04d}-{exp_m:02d}-30"},
    }

def make_staff(role):
    return {
        "name": person_name(),
        "role": role,
        "ratings": {
            "attacking": rng.randint(4, 20),
            "defending": rng.randint(4, 20),
            "fitness": rng.randint(4, 20),
            "judging_ability": rng.randint(4, 20),
            "judging_potential": rng.randint(4, 20),
            "youth": rng.randint(4, 20),
        },
    }

# tiered species pools by BST so top clubs get better squads
by_bst = sorted(pokemon, key=lambda p: sum(p["base"].values()))
usable = [p for p in by_bst if p["id"] not in (150, 151, 132)]  # no Mewtwo/Mew/Ditto in squads
low, mid, high = usable[:60], usable[40:110], usable[80:]

clubs = []
for i, (name, short) in enumerate(CLUBS):
    rep = rng.randint(8, 18)
    tier_pool = high if rep >= 15 else (mid if rep >= 11 else low + mid[:30])
    squad_n = rng.randint(8, 14)
    squad = [make_instance(rng.choice(tier_pool), 20 + rep, min(60, 30 + rep * 2)) for _ in range(squad_n)]
    wage_bill = sum(m["contract"]["salary"] for m in squad)
    clubs.append({
        "id": f"club{i:02d}",
        "name": name,
        "short": short,
        "manager": person_name(),
        "reputation": rep,
        "finances": {
            "balance": rng.randint(200, 900) * 1000 + rep * 50000,
            "wage_budget": int(wage_bill * rng.uniform(1.1, 1.4)),
        },
        "squad": squad,
        "staff": [make_staff(r) for r in rng.sample(ROLES, rng.randint(2, 4))],
    })

# make player club (Pallet Pioneers) deliberately mid-table
player_club = next(c for c in clubs if c["name"] == "Pallet Pioneers")
player_club["reputation"] = 12

free_agents = [make_instance(rng.choice(usable), 18, 55, 0.7) for _ in range(80)]
prospects = []
for _ in range(30):
    inst = make_instance(rng.choice(usable), 5, 22, 0.3)
    inst["potential"] = rng.randint(8, 20)
    inst["scouted_pct"] = 0
    prospects.append(inst)

# ---- item economy: starting held items on key mons + club item inventories.
# Separate RNG so everything generated above stays byte-identical across runs.
irng = random.Random(20260829)
poke_by_id = {p["id"]: p for p in pokemon}

def pick_held(inst):
    sp = poke_by_id[inst["species_id"]]
    b = sp["base"]
    cands = [TYPE_BOOST_BY_TYPE[sp["types"][0]]]
    if len(sp["types"]) > 1:
        cands.append(TYPE_BOOST_BY_TYPE[sp["types"][1]])
    if b["hp"] >= 85:
        cands += ["leftovers", "leftovers"]
    if b["atk"] >= b["spa"] + 15 and b["atk"] >= 90:
        cands.append("choice_band")
    if b["spa"] >= b["atk"] + 15 and b["spa"] >= 90:
        cands.append("choice_specs")
    if b["spe"] >= 100:
        cands.append("choice_scarf")
    if b["hp"] <= 50 and b["def"] <= 60:
        cands += ["focus_sash", "focus_sash"]
    if b["spd"] >= 90 and b["atk"] >= b["spa"]:
        cands.append("assault_vest")
    if sp.get("evolves") and (b["def"] >= 70 or b["spd"] >= 70):
        cands.append("eviolite")
    if b["spe"] <= 45:
        cands.append("quick_claw")
    cands += ["sitrus_berry", "lum_berry"]
    return irng.choice(cands)

USABLE_STOCK = ["potion", "super_potion", "hyper_potion", "full_heal", "revive",
                "x_attack", "x_speed", "antidote", "paralyze_heal", "awakening"]

for c in clubs:
    rep = c["reputation"]
    # equip the top (by level) key battlers, more at bigger clubs
    key = sorted(c["squad"], key=lambda m: -m["level"])[: 2 + rep // 6]
    for m in key:
        if irng.random() < 0.85:
            m["held_item"] = pick_held(m)
    inv = {}
    inv["potion"] = irng.randint(2, 4)
    inv["super_potion"] = irng.randint(1, 3)
    inv["full_heal"] = irng.randint(0, 2)
    inv["revive"] = irng.randint(0, 1)
    for extra in irng.sample(USABLE_STOCK, 2 + rep // 8):
        inv[extra] = inv.get(extra, 0) + irng.randint(1, 2)
    if rep >= 13:
        inv["hyper_potion"] = inv.get("hyper_potion", 0) + irng.randint(1, 2)
    # a spare held item or two in the storeroom
    for _ in range(irng.randint(1, 2)):
        spare = irng.choice(list(TYPE_BOOST_BY_TYPE.values()) + ["leftovers", "quick_claw", "sitrus_berry"])
        inv[spare] = inv.get(spare, 0) + 1
    c["items"] = {k: v for k, v in inv.items() if v > 0}

world = {
    "meta": {
        "league_name": "Indigo League",
        "season_start": "2026-08-01",
        "player_club_id": player_club["id"],
        "currency": "P$",
    },
    "clubs": clubs,
    "free_agents": free_agents,
    "prospects": prospects,
}

def dump(name, obj):
    path = os.path.join(OUT, name)
    with open(path, "w") as f:
        json.dump(obj, f, indent=1)
    print(f"wrote {path} ({os.path.getsize(path)} bytes)")

items_out = {}
for iid, (iname, icls, price, rarity, fx, desc) in ITEMS.items():
    items_out[iid] = {"id": iid, "name": iname, "class": icls, "price": price,
                      "rarity": rarity, "effects": fx, "desc": desc}

dump("pokemon.json", pokemon)
dump("moves.json", moves_out)
dump("typechart.json", {"types": TYPES, "chart": CHART})
dump("world.json", world)
dump("items.json", items_out)

# sanity: every learnset/instance move exists in moves.json
missing = set()
for p in pokemon:
    for m in p["learnset"]:
        if m not in moves_out:
            missing.add(m)
assert not missing, f"missing moves: {missing}"
# sanity: every assigned/stocked item exists in items.json
for c in clubs:
    for m in c["squad"]:
        assert m["held_item"] is None or m["held_item"] in items_out, m["held_item"]
    for iid in c["items"]:
        assert iid in items_out, iid
held_n = sum(1 for i in items_out.values() if i["class"] == "held")
usable_n = len(items_out) - held_n
equipped = sum(1 for c in clubs for m in c["squad"] if m["held_item"])
print(f"OK: {len(pokemon)} pokemon, {len(moves_out)} moves, {len(clubs)} clubs, "
      f"{len(free_agents)} free agents, {len(prospects)} prospects, "
      f"{len(items_out)} items ({held_n} held / {usable_n} usable), {equipped} mons equipped")
