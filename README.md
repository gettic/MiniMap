# Mini Map

A square minimap with a bar under it that holds the minimap buttons. A World of Warcraft addon for **WoW Forever**.

> **Beta.** Version 0.1.0-beta.1 is the first release and is still being tested in the game. Please report anything that looks wrong on the [Issues](https://github.com/gettic/MiniMap/issues) page.

- [What it does](#what-it-does)
- [Install](#install)
- [How to use it](#how-to-use-it)
- [Other minimap addons](#other-minimap-addons)
- [Known limits](#known-limits)
- [For people who change the code](#for-people-who-change-the-code)
- [Licence](#licence)

## What it does

| Part | What you get |
|---|---|
| Square map | The round minimap becomes square, with a thin Blizzard metal border. It stays square with "Rotate Minimap" on. |
| Button bar | A bar under the map collects the minimap buttons of your other addons, in alphabetical order, so they don't sit around the map's edge. |
| Header | Blizzard's own zone name, clock, calendar, tracking and addon-compartment buttons stay where Blizzard puts them. |
| Coordinates | If you show player coordinates, they sit inside the map's bottom edge, so they don't cover the bar. |
| Edit Mode | You still move and size the minimap with Blizzard's Edit Mode. The border and the bar follow it. |

The bar hides itself when it has no buttons. Blizzard's event button also goes into the bar while an event is on.

## Install

**With an addon manager:** find **Mini Map** in its list and install it. While Mini Map is in beta, use the manager's beta channel.

**By hand:**
1. Download the zip from the [Releases](https://github.com/gettic/MiniMap/releases) page.
2. Unzip it into your WoW Forever `Interface\AddOns` folder, so you get `Interface\AddOns\MiniMap\`.
3. Restart the game, or type `/reload` if you're already logged in.

## How to use it

Mini Map works by itself as soon as you log in. There are no settings to change.

**Move or size the minimap:** open Edit Mode (**Esc > Edit Mode**) and click the minimap.

| Edit Mode option | What happens |
|---|---|
| Drag to move | The map, its border and the button bar move together. |
| Size | The map, border, bar and buttons scale together. |
| Header Underneath | The header goes under the map, and the button bar moves above the map. |
| Rotate Minimap | The map turns inside the square. |
| Icon Size | The map markers resize as normal. |

**Chat command:**

| Command | What it does |
|---|---|
| `/mmap` | Shows a short help. |
| `/mmap rescan` | Puts minimap buttons that showed up late into the bar now. In combat, it waits until combat ends. |

Mini Map already looks for new buttons a few times after login and when another addon loads, so you rarely need `/mmap rescan`.

## Other minimap addons

- If another addon that changes the minimap is loaded (for example SexyMap, BasicMinimap or ElvUI), Mini Map leaves the minimap's shape alone and says so in chat.
- If another addon that collects minimap buttons is loaded (for example MinimapButtonButton or HidingBar), Mini Map turns its own bar off and says so in chat.

## Known limits

- **Corner clicks don't ping.** The game only pings inside a circle, so clicking in the square map's corners doesn't send a ping.
- **The bar can hang off the screen.** Edit Mode's selection box covers the map but not the bar. If you put the minimap right at the bottom edge of the screen, the bar can end up partly off-screen. Move the map up a little.
- **Some buttons may not be collected.** Mini Map picks up buttons by their name. A button with an unusual name stays where its addon put it.

## For people who change the code

The addon is in the `MiniMap` folder. It needs no libraries.

| File | What's in it |
|---|---|
| `MiniMap_Forever.toc` | Addon info and load order. |
| `Locale.lua` | Every text the player sees. |
| `Theme.lua` | All art, sizes and colours in one table. |
| `Core.lua` | Start-up, saved settings, combat queue, other-addon check, `/mmap`. |
| `Square.lua` | Square mask, hiding the round art, border, coordinates. |
| `IconBar.lua` | Finding minimap buttons and laying out the bar. |

Saved settings: `MiniMapForeverDB` (account-wide). Position and size are saved by Edit Mode, not by Mini Map.

## Licence

All rights reserved. See [LICENSE](LICENSE).
