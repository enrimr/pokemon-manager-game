# Simulation services (drop-in convention)

Any `*.gd` script placed in this folder is auto-loaded by GameState at career
start (new career AND save load), ticked daily, and persisted inside the save.
GameState never needs editing. The exact interface is documented in
docs/ARCHITECTURE.md under "Simulation services".
