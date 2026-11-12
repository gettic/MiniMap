-- Mini Map: every text the player can see (English).
local ADDON, ns = ...

local L = {}
ns.L = L

L.PREFIX = "|cffffd100Mini Map:|r"

L.HELP_1 = "Move and size the minimap in Edit Mode (Esc > Edit Mode)."
L.HELP_2 = "/mmap rescan - put new minimap buttons into the bar now."

L.RESCANNED = "Looked for new minimap buttons: %d in the bar."
L.RESCAN_COMBAT = "Will look for new minimap buttons after combat."
L.SETUP_COMBAT = "Will finish setting up after combat."

L.SHAPE_CONFLICT = "%s also changes the minimap, so Mini Map leaves the minimap's shape alone."
L.BAR_CONFLICT = "%s also collects minimap buttons, so Mini Map's button bar is off."
L.OTHER_ADDON = "another addon"

L.PART_FAILED = "Part \"%s\" could not start (error shown by the game's error window)."
