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

L.HELP_4 = "/mmap pos - print where the minimap's Edit Mode frame is (for bug reports)."
L.POS_NONE = "The minimap's frame isn't there (or has no position yet)."
L.POS_POINT = "Anchor: %s to %s %s, x %.1f, y %.1f (scale %.2f)"
L.POS_EDGES = "Edges: left %.1f, right %.1f, top %.1f, bottom %.1f (screen: right %.1f, top %.1f)"
L.POS_CLAMP = "Clamp insets: left %.1f, right %.1f, top %.1f, bottom %.1f"

L.RESCANNED = "Looked for new minimap buttons: %d in the bar."
L.RESCAN_COMBAT = "Will look for new minimap buttons after combat."
L.SETUP_COMBAT = "Will finish setting up after combat."

L.SHAPE_CONFLICT = "%s also changes the minimap, so Mini Map leaves the minimap's shape alone."
L.BAR_CONFLICT = "%s also collects minimap buttons, so Mini Map's button bar is off."
L.OTHER_ADDON = "another addon"

L.HELP_5 = "/mmap ore - on/off: ore icon and short name, in your Mining skill's colour, on mining nodes' minimap tooltips."
L.ORE_ON = "Ore labels on: hold the mouse over a mining node on the minimap."
L.ORE_OFF = "Ore labels off."
L.ORE_MISSING = "Ore labels can't work on this game version (no minimap tooltip hook)."
L.ORE_MINING = "Mining" -- skill name, only used on clients with the old skills list

L.PART_FAILED = "Part \"%s\" could not start (error shown by the game's error window)."
