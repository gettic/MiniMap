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

L.HELP_5 = "/mmap debug - hold the mouse over the minimap and type this: prints tooltip and minimap shape details for bug reports."
L.DEBUG_OWNER = "Tooltip owner: %s, shown: %s, lines: %s"
L.DEBUG_LINE = "  line %d: %s"
L.DEBUG_SECRET = "(hidden by the game)"
L.DEBUG_UNREADABLE = "(can't be read)"
L.DEBUG_SHAPE = "Minimap shape: %s (%s)"
L.DEBUG_SHAPE_OURS = "Mini Map's"
L.DEBUG_SHAPE_OTHER = "another addon's or the game's"
L.DEBUG_SHAPE_NONE = "not set"
L.DEBUG_BORDER = "Border art: %s; in use: %s"
L.DEBUG_NO_ATLAS = "NO ATLAS"
-- Where the border's slice margins came from.
L.FROM = {
	atlas = "from the atlas",
	atlaspx = "from the atlas, file pixels converted",
	share = "no slice data, cut at Mini Map's share",
	theme = "no slice data, Mini Map's own numbers",
}
-- Why a border atlas wasn't used.
L.REASON = {
	missing = "not in this game",
	nofile = "no file",
	badsize = "no size",
	badcoords = "no texture coordinates",
	nomargins = "no usable margins",
	nofit = "margins don't fit",
	error = "error while drawing",
}

L.HELP_ART = "/mmap art - list which border art this game has (for bug reports)."
L.ART_FOUND = "%s: found %sx%s, raw %s, file %s, slice %s"
L.ART_MISSING = "%s: missing"
L.ART_NO_SLICE = "none"
L.ART_IN_USE = "Border in use: %s"
L.ART_SKIPPED = "Not used: %s"

L.HELP_6 = "/mmap bookson or /mmap booksoff - Library Books' far-away minimap pins on the square's edge (on) or on its own circle (off)."
L.BOOKS_ON = "Library Books pins now follow the square minimap."
L.BOOKS_ON_IDLE = "Library Books pins will follow the square minimap (Library Books isn't loaded or the map isn't square now)."
L.BOOKS_OFF = "Library Books pins are left on their own circle."

L.HELP_7 = "/mmap zygoron or /mmap zygoroff - Zygor's \"Solid lines\" minimap path reaches the square's edge (on) or stops at Zygor's circle (off)."
L.ZYGOR_ON = "Zygor's solid minimap path now reaches the square's edge."
L.ZYGOR_ON_IDLE = "Zygor's solid minimap path will reach the square's edge (Zygor isn't loaded or the map isn't square now)."
L.ZYGOR_OFF = "Zygor's solid minimap path is left as Zygor draws it."
L.ZYGOR_BROKEN = "Zygor path fix turned off (Zygor has changed). /reload to try again."

L.PART_FAILED = "Part \"%s\" could not start (error shown by the game's error window)."
