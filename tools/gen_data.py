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
         "ground", "flying", "psychic", "bug", "rock", "ghost", "dragon",
         "dark", "steel", "fairy"]

# ---------------------------------------------------------------- gen-2 moves
# Same tuple format as MOVES. New forward-looking tag: weather:<sun|rain|sand>
# (BattleEngine ignores unknown tags today; the battle-depth piece wires them).
# Gen-2 correction: Bite becomes Dark-type.
MOVES["Bite"] = ("dark", 60, 100, 25, "phys", ["flinch:0.1"])
MOVES.update({
    # Dark
    "Crunch": ("dark", 80, 100, 15, "phys", ["stat:spd:-1:0.2"]),
    "Pursuit": ("dark", 40, 100, 20, "phys", []),
    "Feint Attack": ("dark", 60, 0, 20, "phys", ["never_miss"]),
    "Thief": ("dark", 60, 100, 25, "phys", []),
    "Beat Up": ("dark", 60, 100, 10, "phys", []),
    # Steel
    "Iron Tail": ("steel", 100, 75, 15, "phys", ["stat:def:-1:0.3"]),
    "Steel Wing": ("steel", 70, 90, 25, "phys", ["stat:def:+1:0.1:self"]),
    "Metal Claw": ("steel", 50, 95, 35, "phys", ["stat:atk:+1:0.1:self"]),
})
MOVES.update({
    # Normal
    "Return": ("normal", 102, 100, 20, "phys", []),
    "Extreme Speed": ("normal", 80, 100, 5, "phys", ["priority:1"]),
    "Rapid Spin": ("normal", 50, 100, 40, "phys", []),
    "Slam": ("normal", 80, 75, 20, "phys", []),
    "Snore": ("normal", 50, 100, 15, "spec", ["flinch:0.3"]),
    "False Swipe": ("normal", 40, 100, 40, "phys", []),
    "Triple Kick": ("fighting", 47, 90, 10, "phys", []),
    "Milk Drink": ("normal", 0, 0, 10, "status", ["heal:0.5"]),
    "Morning Sun": ("normal", 0, 0, 5, "status", ["heal:0.5"]),
    "Moonlight": ("normal", 0, 0, 5, "status", ["heal:0.5"]),
    "Scary Face": ("normal", 0, 100, 10, "status", ["stat:spe:-2"]),
    "Charm": ("normal", 0, 100, 20, "status", ["stat:atk:-2"]),
    "Sweet Scent": ("normal", 0, 100, 20, "status", ["stat:eva:-1"]),
    "Sweet Kiss": ("normal", 0, 75, 10, "status", ["confuse:1.0"]),
    "Belly Drum": ("normal", 0, 0, 10, "status", ["stat:atk:+2:1:self"]),
    "Safeguard": ("normal", 0, 0, 25, "status", ["guard_spec"]),
    "Hidden Power": ("normal", 60, 100, 15, "spec", []),
})
MOVES.update({
    # Fire / Water / Grass
    "Sacred Fire": ("fire", 100, 95, 5, "phys", ["burn:0.5"]),
    "Sunny Day": ("fire", 0, 0, 5, "status", ["weather:sun"]),
    "Flame Burst": ("fire", 70, 100, 15, "spec", []),
    "Whirlpool": ("water", 35, 85, 15, "spec", []),
    "Octazooka": ("water", 65, 85, 10, "spec", ["stat:acc:-1:0.5"]),
    "Rain Dance": ("water", 0, 0, 5, "status", ["weather:rain"]),
    "Giga Drain": ("grass", 60, 100, 10, "spec", ["drain:0.5"]),
    "Synthesis": ("grass", 0, 0, 5, "status", ["heal:0.5"]),
    "Cotton Spore": ("grass", 0, 100, 40, "status", ["stat:spe:-2"]),
    # Electric / Ice
    "Spark": ("electric", 65, 100, 20, "phys", ["para:0.3"]),
    "Zap Cannon": ("electric", 120, 50, 5, "spec", ["para:1.0"]),
    "Powder Snow": ("ice", 40, 100, 25, "spec", ["freeze:0.1"]),
})
MOVES.update({
    # Fighting / Poison / Ground
    "Cross Chop": ("fighting", 100, 80, 5, "phys", ["crit:1"]),
    "Dynamic Punch": ("fighting", 100, 50, 5, "phys", ["confuse:1.0"]),
    "Mach Punch": ("fighting", 40, 100, 30, "phys", ["priority:1"]),
    "Vital Throw": ("fighting", 70, 0, 10, "phys", ["never_miss"]),
    "Rock Smash": ("fighting", 40, 100, 15, "phys", ["stat:def:-1:0.5"]),
    "Sludge Bomb": ("poison", 90, 100, 10, "spec", ["poison:0.3"]),
    "Mud-Slap": ("ground", 20, 100, 10, "spec", ["stat:acc:-1:1.0"]),
    "Magnitude": ("ground", 70, 100, 30, "phys", []),
    "Bone Rush": ("ground", 75, 90, 10, "phys", []),
    "Spikes": ("ground", 0, 0, 20, "status", []),
    # Flying / Psychic / Bug
    "Aeroblast": ("flying", 100, 95, 5, "spec", ["crit:1"]),
    "Future Sight": ("psychic", 80, 90, 10, "spec", []),
    "Psych Up": ("psychic", 0, 0, 10, "status", ["stat:spa:+1:1:self"]),
    "Megahorn": ("bug", 120, 85, 10, "phys", []),
    "Fury Cutter": ("bug", 40, 95, 20, "phys", []),
})
MOVES.update({
    # Rock / Ghost / Dragon / misc status
    "Ancient Power": ("rock", 60, 100, 5, "spec", ["stat:atk:+1:0.1:self"]),
    "Rollout": ("rock", 30, 90, 20, "phys", []),
    "Sandstorm": ("rock", 0, 0, 10, "status", ["weather:sand"]),
    "Shadow Ball": ("ghost", 80, 100, 15, "spec", ["stat:spd:-1:0.2"]),
    "Twister": ("dragon", 40, 100, 20, "spec", ["flinch:0.2"]),
    "Curse": ("ghost", 0, 0, 10, "status", ["stat:atk:+1:1:self", "stat:def:+1:1:self"]),
    "Encore": ("normal", 0, 100, 5, "status", []),
    "Attract": ("normal", 0, 100, 15, "status", ["confuse:1.0"]),
    "Swagger": ("normal", 0, 85, 15, "status", ["confuse:1.0"]),
    "Heal Bell": ("normal", 0, 0, 5, "status", ["heal:0.25"]),
    "Pain Split": ("normal", 0, 100, 20, "status", []),
    "Endure": ("normal", 0, 0, 10, "status", []),
    "Protect": ("normal", 0, 0, 10, "status", []),
    "Detect": ("fighting", 0, 0, 5, "status", []),
    "Baton Pass": ("normal", 0, 0, 40, "status", []),
    "Mean Look": ("normal", 0, 0, 5, "status", []),
    "Mirror Coat": ("psychic", 0, 100, 20, "spec", ["fixed:level"]),
    "Present": ("normal", 60, 90, 15, "phys", []),
    "Frustration": ("normal", 70, 100, 20, "phys", []),
})
# __GEN2_MOVES_END__

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

# Gen-2+ effectiveness chart (18 types; fairy is forward-compat — no fairy
# species/moves yet). chart[attacker][defender] = multiplier (missing = 1.0).
# Gen-2 corrections vs the old gen-1 chart: bug/poison 0.5 (was 2), poison/bug
# 1 (was 2), ghost/psychic 2 (was 0), ice/fire 0.5; new dark & steel rows+cols.
CHART = {
    "normal":   {"rock": 0.5, "ghost": 0.0, "steel": 0.5},
    "fire":     {"fire": 0.5, "water": 0.5, "grass": 2, "ice": 2, "bug": 2, "rock": 0.5, "dragon": 0.5, "steel": 2},
    "water":    {"fire": 2, "water": 0.5, "grass": 0.5, "ground": 2, "rock": 2, "dragon": 0.5},
    "grass":    {"fire": 0.5, "water": 2, "grass": 0.5, "poison": 0.5, "ground": 2, "flying": 0.5, "bug": 0.5, "rock": 2, "dragon": 0.5, "steel": 0.5},
    "electric": {"water": 2, "grass": 0.5, "electric": 0.5, "ground": 0.0, "flying": 2, "dragon": 0.5},
    "ice":      {"fire": 0.5, "water": 0.5, "grass": 2, "ice": 0.5, "ground": 2, "flying": 2, "dragon": 2, "steel": 0.5},
    "fighting": {"normal": 2, "ice": 2, "poison": 0.5, "flying": 0.5, "psychic": 0.5, "bug": 0.5, "rock": 2, "ghost": 0.0, "dark": 2, "steel": 2, "fairy": 0.5},
    "poison":   {"grass": 2, "poison": 0.5, "ground": 0.5, "rock": 0.5, "ghost": 0.5, "steel": 0.0, "fairy": 2},
    "ground":   {"fire": 2, "grass": 0.5, "electric": 2, "poison": 2, "flying": 0.0, "bug": 0.5, "rock": 2, "steel": 2},
    "flying":   {"grass": 2, "electric": 0.5, "fighting": 2, "bug": 2, "rock": 0.5, "steel": 0.5},
    "psychic":  {"fighting": 2, "poison": 2, "psychic": 0.5, "dark": 0.0, "steel": 0.5},
    "bug":      {"fire": 0.5, "grass": 2, "fighting": 0.5, "poison": 0.5, "flying": 0.5, "psychic": 2, "ghost": 0.5, "dark": 2, "steel": 0.5, "fairy": 0.5},
    "rock":     {"fire": 2, "ice": 2, "fighting": 0.5, "ground": 0.5, "flying": 2, "bug": 2, "steel": 0.5},
    "ghost":    {"normal": 0.0, "psychic": 2, "ghost": 2, "dark": 0.5},
    "dragon":   {"dragon": 2, "steel": 0.5, "fairy": 0.0},
    "dark":     {"fighting": 0.5, "psychic": 2, "ghost": 2, "dark": 0.5, "fairy": 0.5},
    "steel":    {"fire": 0.5, "water": 0.5, "electric": 0.5, "ice": 2, "rock": 2, "steel": 0.5, "fairy": 2},
    "fairy":    {"fire": 0.5, "fighting": 2, "poison": 0.5, "dragon": 2, "dark": 2, "steel": 0.5},
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

# Gen-2 (Johto) species 152-251. Same tuple format. Gen-2 base stats.
P2 = [
    (152,"Chikorita","grass",None,45,49,65,49,65,45,"medium_slow"),
    (153,"Bayleef","grass",None,60,62,80,63,80,60,"medium_slow"),
    (154,"Meganium","grass",None,80,82,100,83,100,80,"medium_slow"),
    (155,"Cyndaquil","fire",None,39,52,43,60,50,65,"medium_slow"),
    (156,"Quilava","fire",None,58,64,58,80,65,80,"medium_slow"),
    (157,"Typhlosion","fire",None,78,84,78,109,85,100,"medium_slow"),
    (158,"Totodile","water",None,50,65,64,44,48,43,"medium_slow"),
    (159,"Croconaw","water",None,65,80,80,59,63,58,"medium_slow"),
    (160,"Feraligatr","water",None,85,105,100,79,83,78,"medium_slow"),
    (161,"Sentret","normal",None,35,46,34,35,45,20,"medium_fast"),
    (162,"Furret","normal",None,85,76,64,45,55,90,"medium_fast"),
    (163,"Hoothoot","normal","flying",60,30,30,36,56,50,"medium_fast"),
    (164,"Noctowl","normal","flying",100,50,50,76,96,70,"medium_fast"),
    (165,"Ledyba","bug","flying",40,20,30,40,80,55,"fast"),
    (166,"Ledian","bug","flying",55,35,50,55,110,85,"fast"),
    (167,"Spinarak","bug","poison",40,60,40,40,40,30,"fast"),
    (168,"Ariados","bug","poison",70,90,70,60,60,40,"fast"),
    (169,"Crobat","poison","flying",85,90,80,70,80,130,"medium_fast"),
    (170,"Chinchou","water","electric",75,38,38,56,56,67,"slow"),
    (171,"Lanturn","water","electric",125,58,58,76,76,67,"slow"),
    (172,"Pichu","electric",None,20,40,15,35,35,60,"medium_fast"),
    (173,"Cleffa","normal",None,50,25,28,45,55,15,"fast"),
    (174,"Igglybuff","normal",None,90,30,15,40,20,15,"fast"),
    (175,"Togepi","normal",None,35,20,65,40,65,20,"fast"),
    (176,"Togetic","normal","flying",55,40,85,80,105,40,"fast"),
    (177,"Natu","psychic","flying",40,50,45,70,45,70,"medium_fast"),
    (178,"Xatu","psychic","flying",65,75,70,95,70,95,"medium_fast"),
    (179,"Mareep","electric",None,55,40,40,65,45,35,"medium_slow"),
    (180,"Flaaffy","electric",None,70,55,55,80,60,45,"medium_slow"),
    (181,"Ampharos","electric",None,90,75,75,115,90,55,"medium_slow"),
    (182,"Bellossom","grass",None,75,80,85,90,100,50,"medium_slow"),
    (183,"Marill","water",None,70,20,50,20,50,40,"fast"),
    (184,"Azumarill","water",None,100,50,80,50,80,50,"fast"),
    (185,"Sudowoodo","rock",None,70,100,115,30,65,30,"medium_fast"),
    (186,"Politoed","water",None,90,75,75,90,100,70,"medium_slow"),
    (187,"Hoppip","grass","flying",35,35,40,35,55,50,"medium_slow"),
    (188,"Skiploom","grass","flying",55,45,50,45,65,80,"medium_slow"),
    (189,"Jumpluff","grass","flying",75,55,70,55,95,110,"medium_slow"),
    (190,"Aipom","normal",None,55,70,55,40,55,85,"fast"),
    (191,"Sunkern","grass",None,30,30,30,30,30,30,"medium_slow"),
    (192,"Sunflora","grass",None,75,75,55,105,85,30,"medium_slow"),
    (193,"Yanma","bug","flying",65,65,45,75,45,95,"medium_fast"),
    (194,"Wooper","water","ground",55,45,45,25,25,15,"medium_fast"),
    (195,"Quagsire","water","ground",95,85,85,65,65,35,"medium_fast"),
    (196,"Espeon","psychic",None,65,65,60,130,95,110,"medium_fast"),
    (197,"Umbreon","dark",None,95,65,110,60,130,65,"medium_fast"),
    (198,"Murkrow","dark","flying",60,85,42,85,42,91,"medium_slow"),
    (199,"Slowking","water","psychic",95,75,80,100,110,30,"medium_fast"),
    (200,"Misdreavus","ghost",None,60,60,60,85,85,85,"fast"),
    (201,"Unown","psychic",None,48,72,48,72,48,48,"medium_fast"),
    (202,"Wobbuffet","psychic",None,190,33,58,33,58,33,"medium_fast"),
    (203,"Girafarig","normal","psychic",70,80,65,90,65,85,"medium_fast"),
    (204,"Pineco","bug",None,50,65,90,35,35,15,"medium_fast"),
    (205,"Forretress","bug","steel",75,90,140,60,60,40,"medium_fast"),
    (206,"Dunsparce","normal",None,100,70,70,65,65,45,"medium_fast"),
    (207,"Gligar","ground","flying",65,75,105,35,65,85,"medium_slow"),
    (208,"Steelix","steel","ground",75,85,200,55,65,30,"medium_fast"),
    (209,"Snubbull","normal",None,60,80,50,40,40,30,"fast"),
    (210,"Granbull","normal",None,90,120,75,60,60,45,"fast"),
    (211,"Qwilfish","water","poison",65,95,75,55,55,85,"medium_fast"),
    (212,"Scizor","bug","steel",70,130,100,55,80,65,"medium_fast"),
    (213,"Shuckle","bug","rock",20,10,230,10,230,5,"medium_slow"),
    (214,"Heracross","bug","fighting",80,125,75,40,95,85,"slow"),
    (215,"Sneasel","dark","ice",55,95,55,35,75,115,"medium_slow"),
    (216,"Teddiursa","normal",None,60,80,50,50,50,40,"medium_fast"),
    (217,"Ursaring","normal",None,90,130,75,75,75,55,"medium_fast"),
    (218,"Slugma","fire",None,40,40,40,70,40,20,"medium_fast"),
    (219,"Magcargo","fire","rock",50,50,120,80,80,30,"medium_fast"),
    (220,"Swinub","ice","ground",50,50,40,30,30,50,"slow"),
    (221,"Piloswine","ice","ground",100,100,80,60,60,50,"slow"),
    (222,"Corsola","water","rock",55,55,85,65,85,35,"fast"),
    (223,"Remoraid","water",None,35,65,35,65,35,65,"medium_fast"),
    (224,"Octillery","water",None,75,105,75,105,75,45,"medium_fast"),
    (225,"Delibird","ice","flying",45,55,45,65,45,75,"fast"),
    (226,"Mantine","water","flying",65,40,70,80,140,70,"slow"),
    (227,"Skarmory","steel","flying",65,80,140,40,70,70,"slow"),
    (228,"Houndour","dark","fire",45,60,30,80,50,65,"slow"),
    (229,"Houndoom","dark","fire",75,90,50,110,80,95,"slow"),
    (230,"Kingdra","water","dragon",75,95,95,95,95,85,"medium_fast"),
    (231,"Phanpy","ground",None,90,60,60,40,40,40,"medium_fast"),
    (232,"Donphan","ground",None,90,120,120,60,60,50,"medium_fast"),
    (233,"Porygon2","normal",None,85,80,90,105,95,60,"medium_fast"),
    (234,"Stantler","normal",None,73,95,62,85,65,85,"slow"),
    (235,"Smeargle","normal",None,55,20,35,20,45,75,"fast"),
    (236,"Tyrogue","fighting",None,35,35,35,35,35,35,"medium_fast"),
    (237,"Hitmontop","fighting",None,50,95,95,35,110,70,"medium_fast"),
    (238,"Smoochum","ice","psychic",45,30,15,85,65,65,"medium_fast"),
    (239,"Elekid","electric",None,45,63,37,65,55,95,"medium_fast"),
    (240,"Magby","fire",None,45,75,37,70,55,83,"medium_fast"),
    (241,"Miltank","normal",None,95,80,105,40,70,100,"slow"),
    (242,"Blissey","normal",None,255,10,10,75,135,55,"fast"),
    (243,"Raikou","electric",None,90,85,75,115,100,115,"slow"),
    (244,"Entei","fire",None,115,115,85,90,75,100,"slow"),
    (245,"Suicune","water",None,100,75,115,90,115,85,"slow"),
    (246,"Larvitar","rock","ground",50,64,50,45,50,41,"slow"),
    (247,"Pupitar","rock","ground",70,84,70,65,70,51,"slow"),
    (248,"Tyranitar","rock","dark",100,134,110,95,100,61,"slow"),
    (249,"Lugia","psychic","flying",106,90,130,90,154,110,"slow"),
    (250,"Ho-Oh","fire","flying",106,130,90,110,154,90,"slow"),
    (251,"Celebi","psychic","grass",100,100,100,100,100,100,"medium_slow"),
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

def build_learnset(pid, name, t1, t2, atk, spa, r=None, pools=None, sigs=None):
    r = r or rng
    pools = pools or TYPE_POOL
    sigs = sigs if sigs is not None else SIGNATURE
    if pid in sigs:
        base = list(sigs[pid])
    else:
        base = []
        for t in filter(None, [t1, t2]):
            pool = list(pools[t])
            k = min(len(pool), 3 if t2 else 4)
            base += r.sample(pool, k)
        # a normal staple
        if t1 != "normal":
            base.append(r.choice(NORMAL_STAPLES_PHYS if atk >= spa else NORMAL_STAPLES_SPEC))
        base.append(r.choice(STATUS_POOL))
    # dedupe preserving order, clamp 4..8
    seen, out = set(), []
    for m in base:
        if m not in seen:
            seen.add(m)
            out.append(m)
    while len(out) < 4:
        m = r.choice(NORMAL_STAPLES_PHYS + STATUS_POOL)
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

# ---------------------------------------------------------------- gen-2 build
# Separate RNG + extended pools so every gen-1 species (and the world gen
# below, which only draws from gen-1) stays byte-identical across regens.
rng2 = random.Random(20260830)
TYPE_POOL2 = {t: list(v) for t, v in TYPE_POOL.items()}
TYPE_POOL2["dark"] = ["Bite", "Crunch", "Pursuit", "Feint Attack", "Thief"]
TYPE_POOL2["steel"] = ["Metal Claw", "Iron Tail", "Steel Wing"]
TYPE_POOL2["normal"] += ["Return", "Headbutt"]
TYPE_POOL2["fighting"] += ["Cross Chop", "Mach Punch", "Rock Smash"]
TYPE_POOL2["water"] += ["Whirlpool"]
TYPE_POOL2["grass"] += ["Giga Drain", "Synthesis"]
TYPE_POOL2["electric"] += ["Spark"]
TYPE_POOL2["ice"] += ["Powder Snow"]
TYPE_POOL2["poison"] += ["Sludge Bomb"]
TYPE_POOL2["ground"] += ["Mud-Slap", "Magnitude"]
TYPE_POOL2["psychic"] += ["Future Sight"]
TYPE_POOL2["bug"] += ["Megahorn", "Fury Cutter"]
TYPE_POOL2["rock"] += ["Ancient Power", "Rollout"]
TYPE_POOL2["ghost"] += ["Shadow Ball"]
TYPE_POOL2["dragon"] += ["Twister"]

SIGNATURE2 = {
    157: ["Flamethrower", "Fire Blast", "Swift", "Quick Attack", "Smokescreen"],
    160: ["Surf", "Crunch", "Slash", "Ice Punch", "Screech"],
    169: ["Wing Attack", "Bite", "Confuse Ray", "Toxic", "Agility"],
    181: ["Thunderbolt", "Zap Cannon", "Thunder Wave", "Fire Punch", "Light Screen"],
    196: ["Psychic", "Psybeam", "Morning Sun", "Swift", "Reflect"],
    197: ["Feint Attack", "Crunch", "Moonlight", "Toxic", "Confuse Ray", "Screech"],
    208: ["Iron Tail", "Earthquake", "Rock Slide", "Crunch", "Harden", "Screech"],
    212: ["Metal Claw", "Fury Cutter", "Slash", "Wing Attack", "Swords Dance", "Agility"],
    214: ["Megahorn", "Cross Chop", "Earthquake", "Fury Cutter", "Focus Energy"],
    230: ["Surf", "Hydro Pump", "Twister", "Ice Beam", "Agility", "Smokescreen"],
    242: ["Soft-Boiled", "Seismic Toss", "Sing", "Light Screen", "Toxic"],
    243: ["Thunderbolt", "Crunch", "Zap Cannon", "Quick Attack", "Reflect"],
    244: ["Fire Blast", "Sacred Fire", "Bite", "Stomp", "Swagger"],
    245: ["Surf", "Aurora Beam", "Ice Beam", "Mist", "Rain Dance"],
    248: ["Crunch", "Rock Slide", "Earthquake", "Fire Blast", "Scary Face"],
    249: ["Aeroblast", "Psychic", "Recover", "Rain Dance", "Ancient Power"],
    250: ["Sacred Fire", "Fire Blast", "Ancient Power", "Recover", "Sunny Day"],
    251: ["Psychic", "Giga Drain", "Ancient Power", "Recover", "Heal Bell"],
    235: ["Sketch", "Tackle", "Swift", "Double Team"],
    225: ["Present", "Icy Wind", "Fly", "Quick Attack"],
}
MOVES["Sketch"] = ("normal", 0, 0, 1, "status", [])

# Gen-2 species that can still evolve (drives Eviolite "nfe").
EVOLVES2 = {
    152, 153, 155, 156, 158, 159, 161, 163, 165, 167, 170, 172, 173, 174, 175,
    176, 177, 179, 180, 183, 187, 188, 191, 194, 204, 209, 215, 216, 218, 220,
    223, 228, 231, 236, 238, 239, 240, 246, 247,
}

pokemon_gen2 = []
for (pid, name, t1, t2, hp, atk, dfn, spa, spd, spe, growth) in P2:
    pokemon_gen2.append({
        "id": pid, "name": name,
        "types": [t for t in [t1, t2] if t],
        "base": {"hp": hp, "atk": atk, "def": dfn, "spa": spa, "spd": spd, "spe": spe},
        "growth": growth,
        "evolves": pid in EVOLVES2,
        "learnset": build_learnset(pid, name, t1, t2, atk, spa,
                                   r=rng2, pools=TYPE_POOL2, sigs=SIGNATURE2),
    })
pokemon_all = pokemon + pokemon_gen2

moves_out = {}
for name, (mtype, power, acc, pp, cat, fx) in MOVES.items():
    moves_out[name] = {"type": mtype, "power": power, "accuracy": acc, "pp": pp,
                       "category": cat, "effects": fx}

# ---------------------------------------------------------------- natures
# The 25 real natures: +10% to `plus`, -10% to `minus` (null/null = neutral).
# Written to natures.json as {name: {plus, minus}}; every world instance
# carries a "nature" field with one of these names.
NATURES = {
    "Hardy":   (None, None),  "Lonely": ("atk", "def"), "Brave": ("atk", "spe"),
    "Adamant": ("atk", "spa"), "Naughty": ("atk", "spd"),
    "Bold":    ("def", "atk"), "Docile": (None, None),  "Relaxed": ("def", "spe"),
    "Impish":  ("def", "spa"), "Lax":    ("def", "spd"),
    "Timid":   ("spe", "atk"), "Hasty":  ("spe", "def"), "Serious": (None, None),
    "Jolly":   ("spe", "spa"), "Naive":  ("spe", "spd"),
    "Modest":  ("spa", "atk"), "Mild":   ("spa", "def"), "Quiet": ("spa", "spe"),
    "Bashful": (None, None),   "Rash":   ("spa", "spd"),
    "Calm":    ("spd", "atk"), "Gentle": ("spd", "def"), "Sassy": ("spd", "spe"),
    "Careful": ("spd", "spa"), "Quirky": (None, None),
}
NATURE_NAMES = list(NATURES.keys())
natures_out = {n: {"plus": p, "minus": m} for n, (p, m) in NATURES.items()}

# ---------------------------------------------------------------- abilities
# ~45 real abilities with machine-readable effect tags (colon-separated).
# BattleEngine wires these later (battle-depth piece); unknown tags are inert.
# Tag grammar:
#   on_switch_in:stat:<stat>:<±stages>:foe      on_switch_in:weather:<sun|rain|sand>
#   contact_status:<status|confuse|spore>:p     contact_damage:f
#   immune:<move type>   immune_status:<status>  immune_confuse  immune_flinch
#   absorb:<type>[:heal:f]      resist:<type>:mult     pinch_boost:<type>:mult
#   mult:<stat>:mult    status_boost:<stat>:mult    end_turn_stat:<stat>:<±n>
#   weather_speed:<w>:mult   weather_eva:<w>:mult   weather_heal:<w>:f
#   no_stat_drop  no_acc_drop  no_atk_drop  no_secondary_effects  no_recoil
#   effect_chance_mult:f  acc_mult:<all|phys>:f  end_turn_cure:p  sleep_half
#   heal_status_on_switch  reflect_status  sturdy  pp_pressure:n
ABILITIES = {
    "intimidate":   ("Intimidate", ["on_switch_in:stat:atk:-1:foe"], "Lowers the foe's Attack one stage on switch-in."),
    "levitate":     ("Levitate", ["immune:ground"], "Immune to Ground-type moves."),
    "static":       ("Static", ["contact_status:para:0.3"], "30% to paralyze attackers on contact."),
    "flash_fire":   ("Flash Fire", ["absorb:fire"], "Immune to Fire moves; powers up its own Fire moves when hit by one."),
    "sturdy":       ("Sturdy", ["sturdy"], "Survives a one-hit KO from full HP with 1 HP."),
    "speed_boost":  ("Speed Boost", ["end_turn_stat:spe:+1"], "Speed rises one stage at the end of each turn."),
    "drizzle":      ("Drizzle", ["on_switch_in:weather:rain"], "Summons rain on switch-in."),
    "drought":      ("Drought", ["on_switch_in:weather:sun"], "Summons harsh sunlight on switch-in."),
    "sand_stream":  ("Sand Stream", ["on_switch_in:weather:sand"], "Whips up a sandstorm on switch-in."),
    "chlorophyll":  ("Chlorophyll", ["weather_speed:sun:2.0"], "Doubles Speed in harsh sunlight."),
    "swift_swim":   ("Swift Swim", ["weather_speed:rain:2.0"], "Doubles Speed in rain."),
    "guts":         ("Guts", ["status_boost:atk:1.5"], "Attack x1.5 while statused."),
    "thick_fat":    ("Thick Fat", ["resist:fire:0.5", "resist:ice:0.5"], "Halves damage from Fire and Ice moves."),
    "volt_absorb":  ("Volt Absorb", ["absorb:electric:heal:0.25"], "Heals 25% when hit by Electric moves."),
    "water_absorb": ("Water Absorb", ["absorb:water:heal:0.25"], "Heals 25% when hit by Water moves."),
    "poison_point": ("Poison Point", ["contact_status:poison:0.3"], "30% to poison attackers on contact."),
    "flame_body":   ("Flame Body", ["contact_status:burn:0.3"], "30% to burn attackers on contact."),
    "effect_spore": ("Effect Spore", ["contact_status:spore:0.3"], "30% to sleep/poison/paralyze attackers on contact."),
    "rough_skin":   ("Rough Skin", ["contact_damage:0.125"], "Attackers lose 1/8 max HP on contact."),
    "overgrow":     ("Overgrow", ["pinch_boost:grass:1.5"], "Grass moves x1.5 below 1/3 HP."),
    "blaze":        ("Blaze", ["pinch_boost:fire:1.5"], "Fire moves x1.5 below 1/3 HP."),
    "torrent":      ("Torrent", ["pinch_boost:water:1.5"], "Water moves x1.5 below 1/3 HP."),
    "swarm":        ("Swarm", ["pinch_boost:bug:1.5"], "Bug moves x1.5 below 1/3 HP."),
    "hustle":       ("Hustle", ["mult:atk:1.5", "acc_mult:phys:0.8"], "Attack x1.5 but physical accuracy x0.8."),
    "huge_power":   ("Huge Power", ["mult:atk:2.0"], "Doubles Attack."),
    "natural_cure": ("Natural Cure", ["heal_status_on_switch"], "Status conditions heal on switch-out."),
    "serene_grace": ("Serene Grace", ["effect_chance_mult:2.0"], "Doubles move secondary-effect chances."),
    "shed_skin":    ("Shed Skin", ["end_turn_cure:0.33"], "33% each turn to shrug off a status condition."),
    "immunity":     ("Immunity", ["immune_status:poison"], "Cannot be poisoned."),
    "limber":       ("Limber", ["immune_status:para"], "Cannot be paralyzed."),
    "insomnia":     ("Insomnia", ["immune_status:sleep"], "Cannot fall asleep."),
    "vital_spirit": ("Vital Spirit", ["immune_status:sleep"], "Cannot fall asleep."),
    "water_veil":   ("Water Veil", ["immune_status:burn"], "Cannot be burned."),
    "magma_armor":  ("Magma Armor", ["immune_status:freeze"], "Cannot be frozen."),
    "own_tempo":    ("Own Tempo", ["immune_confuse"], "Cannot be confused."),
    "inner_focus":  ("Inner Focus", ["immune_flinch"], "Cannot flinch."),
    "keen_eye":     ("Keen Eye", ["no_acc_drop"], "Accuracy cannot be lowered."),
    "hyper_cutter": ("Hyper Cutter", ["no_atk_drop"], "Attack cannot be lowered."),
    "clear_body":   ("Clear Body", ["no_stat_drop"], "Stats cannot be lowered by opponents."),
    "shield_dust":  ("Shield Dust", ["no_secondary_effects"], "Blocks incoming moves' secondary effects."),
    "rock_head":    ("Rock Head", ["no_recoil"], "Takes no recoil damage."),
    "synchronize":  ("Synchronize", ["reflect_status"], "Passes burns/poison/paralysis back to the inflicter."),
    "pressure":     ("Pressure", ["pp_pressure:2"], "Foes spend 2 PP per move."),
    "early_bird":   ("Early Bird", ["sleep_half"], "Wakes from sleep twice as fast."),
    "sand_veil":    ("Sand Veil", ["weather_eva:sand:0.8"], "Evasion up in a sandstorm."),
    "rain_dish":    ("Rain Dish", ["weather_heal:rain:0.0625"], "Heals 1/16 max HP each turn in rain."),
    "cute_charm":   ("Cute Charm", ["contact_status:confuse:0.3"], "30% to infatuate/confuse attackers on contact."),
    "compound_eyes":("Compound Eyes", ["acc_mult:all:1.3"], "Accuracy x1.3."),
}
abilities_out = {aid: {"id": aid, "name": nm, "effects": fx, "desc": d}
                 for aid, (nm, fx, d) in ABILITIES.items()}

# One plausible ability per species (canonical where the ability exists above).
ABILITY_MAP = {}
def _amap(ab, *ids):
    for i in ids:
        ABILITY_MAP[i] = ab
_amap("overgrow", 1, 2, 3, 152, 153, 154)
_amap("blaze", 4, 5, 6, 155, 156, 157)
_amap("torrent", 7, 8, 9, 158, 159, 160)
_amap("shield_dust", 10, 11, 13, 14, 48, 49)
_amap("compound_eyes", 12)
_amap("swarm", 15, 123, 167, 168, 193, 204)
_amap("keen_eye", 16, 17, 18, 21, 22, 83, 107, 161, 162, 198, 215)
_amap("guts", 19, 20, 56, 57, 66, 67, 68, 214, 216, 217, 236, 246)
_amap("shed_skin", 23, 147, 148, 247)
_amap("intimidate", 24, 58, 59, 128, 130, 209, 210, 234, 237)
_amap("static", 25, 26, 100, 101, 125, 172, 179, 180, 181, 239)
_amap("sand_veil", 27, 28, 50, 51)
_amap("poison_point", 29, 30, 31, 32, 33, 34, 88, 89, 211)
_amap("cute_charm", 35, 36, 39, 40, 173, 174)
_amap("flash_fire", 37, 38, 77, 78, 136, 228, 229)
_amap("inner_focus", 41, 42, 122, 149, 169, 203)
_amap("chlorophyll", 43, 44, 45, 69, 70, 71, 102, 103, 114, 182, 187, 188, 189, 191, 192)
_amap("effect_spore", 46, 47)
_amap("limber", 52, 53, 106, 132)
_amap("swift_swim", 54, 55, 116, 117, 129, 138, 139, 140, 141, 223, 224, 230)
_amap("water_absorb", 60, 61, 62, 131, 134, 186, 194, 195, 226)
_amap("synchronize", 63, 64, 65, 151, 177, 178, 196, 197)
_amap("clear_body", 72, 73)
_amap("sturdy", 74, 75, 76, 81, 82, 90, 91, 95, 205, 208, 213, 227)
_amap("own_tempo", 79, 80, 108, 124, 199, 238)
_amap("early_bird", 84, 85, 165, 166)
_amap("thick_fat", 86, 87, 143, 220, 221, 241)
_amap("levitate", 92, 93, 94, 109, 110, 200, 201)
_amap("insomnia", 96, 97, 163, 164, 202)
_amap("hyper_cutter", 98, 99, 127, 207)
_amap("rock_head", 104, 105, 111, 112, 142, 185, 219, 231, 232)
_amap("natural_cure", 113, 120, 121, 222, 242, 251)
_amap("early_bird", 115)
_amap("water_veil", 118, 119)
_amap("pressure", 144, 145, 146, 150, 243, 244, 245, 248, 249, 250)
_amap("flame_body", 126, 218, 240)
_amap("vital_spirit", 225)
_amap("volt_absorb", 135, 170, 171)
_amap("huge_power", 183, 184)
_amap("serene_grace", 175, 176, 206, 233)
_amap("speed_boost", 193)
_amap("sand_stream", 248)
# fallback by primary type for anything unmapped (deterministic RNG)
ABILITY_FALLBACK = {
    "normal": ["keen_eye", "guts", "limber"], "fire": ["flash_fire", "flame_body"],
    "water": ["swift_swim", "water_absorb"], "grass": ["chlorophyll"],
    "electric": ["static"], "ice": ["thick_fat"], "fighting": ["guts"],
    "poison": ["poison_point"], "ground": ["sand_veil"], "flying": ["keen_eye"],
    "psychic": ["synchronize", "own_tempo"], "bug": ["swarm", "shield_dust"],
    "rock": ["sturdy", "rock_head"], "ghost": ["levitate"], "dragon": ["shed_skin"],
    "dark": ["inner_focus"], "steel": ["sturdy"], "fairy": ["cute_charm"],
}
arng = random.Random(20260831)
for sp in pokemon_all:
    ab = ABILITY_MAP.get(sp["id"]) or arng.choice(ABILITY_FALLBACK[sp["types"][0]])
    assert ab in ABILITIES, ab
    sp["ability"] = ab

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
poke_by_id = {p["id"]: p for p in pokemon_all}

def pick_held(inst):
    sp = poke_by_id[inst["species_id"]]
    b = sp["base"]
    # dark/steel have no type-boost item in the catalog — skip, don't crash
    cands = [TYPE_BOOST_BY_TYPE[t] for t in sp["types"] if t in TYPE_BOOST_BY_TYPE]
    if not cands:
        cands = ["leftovers"]
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

# ---- natures + abilities on every instance (separate RNG: everything above
# stays byte-identical). Ability is the species ability; nature is rolled.
nrng = random.Random(20260901)
_all_by_id = {p["id"]: p for p in pokemon_all}
for _inst in [m for c in clubs for m in c["squad"]] + free_agents + prospects:
    _inst["nature"] = nrng.choice(NATURE_NAMES)
    _inst["ability"] = _all_by_id[_inst["species_id"]]["ability"]

# ---------------------------------------------------------------- Johto league
# Generated strictly AFTER everything above so the Kanto half of the world is
# byte-identical to the single-league output (same rng consumption order).
JOHTO_CLUBS = [
    ("New Bark Gales", "NBK"), ("Cherrygrove Mariners", "CHY"),
    ("Violet Skylarks", "VIO"), ("Azalea Silkwings", "AZA"),
    ("Goldenrod Magnates", "GLD"), ("Ecruteak Bellkeepers", "ECR"),
    ("Olivine Beacons", "OLV"), ("Cianwood Stormfists", "CIA"),
    ("Mahogany Icebreakers", "MAH"), ("Blackthorn Dragonguard", "BLK"),
    ("Lake Rage Tempest", "LKR"), ("Alph Runekeepers", "ALP"),
    ("Whirl Islands Corsairs", "WHI"), ("Mt. Silver Summits", "MTS"),
    ("Ilex Timekeepers", "ILX"), ("Union Cave Drifters", "UNC"),
]

for c in clubs:
    c["league"] = "kanto"

# Johto squads are flavoured with gen-2 species: no legendaries, no Unown.
_johto_banned = {201, 243, 244, 245, 249, 250, 251}
johto_species = [p for p in pokemon_all if 152 <= p["id"] <= 251 and p["id"] not in _johto_banned]
j_by_bst = sorted(johto_species, key=lambda p: sum(p["base"].values()))
j_low, j_mid, j_high = j_by_bst[:35], j_by_bst[20:65], j_by_bst[45:]

def johto_pick(tier_pool):
    # ~1 in 5 squad slots is a Kanto import; the rest are Johto natives
    if rng.random() < 0.20:
        return rng.choice(usable)
    return rng.choice(tier_pool)

johto_clubs = []
for i, (name, short) in enumerate(JOHTO_CLUBS):
    rep = rng.randint(8, 18)
    tier_pool = j_high if rep >= 15 else (j_mid if rep >= 11 else j_low + j_mid[:20])
    squad_n = rng.randint(8, 14)
    squad = [make_instance(johto_pick(tier_pool), 20 + rep, min(60, 30 + rep * 2))
             for _ in range(squad_n)]
    wage_bill = sum(m["contract"]["salary"] for m in squad)
    johto_clubs.append({
        "id": f"club{16 + i:02d}",
        "name": name,
        "short": short,
        "league": "johto",
        "manager": person_name(),
        "reputation": rep,
        "finances": {
            "balance": rng.randint(200, 900) * 1000 + rep * 50000,
            "wage_budget": int(wage_bill * rng.uniform(1.1, 1.4)),
        },
        "squad": squad,
        "staff": [make_staff(r) for r in rng.sample(ROLES, rng.randint(2, 4))],
    })

# Johto market: extra free agents + prospects. native_region is INERT data —
# the transfers piece's regional scouting maps these by type today (so cross-
# region watches already pay travel days) and can adopt a first-class Johto
# region later without a data regen. (A live "region" key would crash the
# current region_coverage board, so we deliberately do not set it.)
johto_free_agents = []
for _ in range(40):
    inst = make_instance(rng.choice(johto_species), 18, 55, 0.7)
    inst["native_region"] = "Johto"
    johto_free_agents.append(inst)
johto_prospects = []
for _ in range(20):
    inst = make_instance(rng.choice(johto_species), 5, 22, 0.3)
    inst["potential"] = rng.randint(8, 20)
    inst["scouted_pct"] = 0
    inst["native_region"] = "Johto"
    johto_prospects.append(inst)
for c in johto_clubs:
    for m in c["squad"]:
        m["native_region"] = "Johto"

# Held items + club inventories for Johto (fresh rng; pick_held reads module irng)
irng = random.Random(20270115)
for c in johto_clubs:
    rep = c["reputation"]
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
    for _ in range(irng.randint(1, 2)):
        spare = irng.choice(list(TYPE_BOOST_BY_TYPE.values()) + ["leftovers", "quick_claw", "sitrus_berry"])
        inv[spare] = inv.get(spare, 0) + 1
    c["items"] = {k: v for k, v in inv.items() if v > 0}

# natures + abilities for the new Johto instances
jnrng = random.Random(20270120)
for _inst in [m for c in johto_clubs for m in c["squad"]] + johto_free_agents + johto_prospects:
    _inst["nature"] = jnrng.choice(NATURE_NAMES)
    _inst["ability"] = _all_by_id[_inst["species_id"]]["ability"]

clubs += johto_clubs
free_agents += johto_free_agents
prospects += johto_prospects

world = {
    "meta": {
        "league_name": "Kanto League",
        "season_start": "2026-08-01",
        "player_club_id": player_club["id"],
        "currency": "P$",
        "cup_name": "Indigo Cup",
        "leagues": [
            {"id": "kanto", "name": "Kanto League"},
            {"id": "johto", "name": "Johto League"},
        ],
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

dump("pokemon.json", pokemon_all)
dump("moves.json", moves_out)
dump("typechart.json", {"types": TYPES, "chart": CHART})
dump("world.json", world)
dump("items.json", items_out)
dump("natures.json", natures_out)
dump("abilities.json", abilities_out)

# sanity: every learnset/instance move exists in moves.json
missing = set()
for p in pokemon_all:
    for m in p["learnset"]:
        if m not in moves_out:
            missing.add(m)
assert not missing, f"missing moves: {missing}"
# sanity: species ids contiguous 1..251, chart consistent over all 18 types
assert [p["id"] for p in pokemon_all] == list(range(1, 252))
assert len(TYPES) == 18 and len(CHART) == 18
for atk_t, row in CHART.items():
    assert atk_t in TYPES
    for def_t, mult in row.items():
        assert def_t in TYPES and mult in (0.0, 0, 0.5, 2), (atk_t, def_t, mult)
for p in pokemon_all:
    assert all(t in TYPES for t in p["types"]), p["name"]
    assert p["ability"] in ABILITIES, p["name"]
assert len(NATURES) == 25
assert sum(1 for v in NATURES.values() if v[0] is None) == 5
# sanity: every instance carries a valid nature + ability
for _inst in [m for c in clubs for m in c["squad"]] + free_agents + prospects:
    assert _inst["nature"] in NATURES and _inst["ability"] in ABILITIES
# sanity: two 16-club leagues, unique ids, every club assigned to a league
assert len(clubs) == 32 and len(set(c["id"] for c in clubs)) == 32
assert sum(1 for c in clubs if c["league"] == "kanto") == 16
assert sum(1 for c in clubs if c["league"] == "johto") == 16
_uids = [m["uid"] for c in clubs for m in c["squad"]] + \
        [m["uid"] for m in free_agents] + [m["uid"] for m in prospects]
assert len(_uids) == len(set(_uids)), "duplicate instance uids"
# sanity: every assigned/stocked item exists in items.json
for c in clubs:
    for m in c["squad"]:
        assert m["held_item"] is None or m["held_item"] in items_out, m["held_item"]
    for iid in c["items"]:
        assert iid in items_out, iid
held_n = sum(1 for i in items_out.values() if i["class"] == "held")
usable_n = len(items_out) - held_n
equipped = sum(1 for c in clubs for m in c["squad"] if m["held_item"])
print(f"OK: {len(pokemon_all)} pokemon, {len(moves_out)} moves, {len(clubs)} clubs, "
      f"{len(free_agents)} free agents, {len(prospects)} prospects, "
      f"{len(items_out)} items ({held_n} held / {usable_n} usable), {equipped} mons equipped, "
      f"{len(natures_out)} natures, {len(abilities_out)} abilities")
