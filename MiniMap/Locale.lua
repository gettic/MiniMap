-- Mini Map: every text the player can see (English).
local ADDON, ns = ...

local L = {}
ns.L = L

L.PREFIX = "|cffffd100Mini Map:|r"

L.HELP_1 = "Move and size the minimap in Edit Mode (Esc > Edit Mode)."
L.HELP_2 = "/mmap rescan - put new minimap buttons into the bar now."
L.HELP_3 = "/mmap names - hold the mouse over a button and type this to see its name."

L.NAMES_NONE = "No frame under the mouse. Hold the mouse over the button, then press Enter."
L.NAMES_LINE = "%s (%s, %.0f x %.0f)"
L.NAMES_UNNAMED = "(no name)"
L.NAMES_TEXHEAD = "Textures of the frame under the mouse:"
L.NAMES_TEXTURE = "  %s [%s] %.0f x %.0f, %s, crop %.2f-%.2f / %.2f-%.2f, %s, alpha %.2f"
L.NAMES_NOTEX = "  (no textures)"
L.NAMES_NOART = "no art"
L.NAMES_SHOWN = "shown"
L.NAMES_HIDDEN = "hidden"

L.RESCANNED = "Looked for new minimap buttons: %d in the bar."
L.RESCAN_COMBAT = "Will look for new minimap buttons after combat."
L.SETUP_COMBAT = "Will finish setting up after combat."

L.SHAPE_CONFLICT = "%s also changes the minimap, so Mini Map leaves the minimap's shape alone."
L.BAR_CONFLICT = "%s also collects minimap buttons, so Mini Map's button bar is off."
L.OTHER_ADDON = "another addon"

L.PART_FAILED = "Part \"%s\" could not start (error shown by the game's error window)."
