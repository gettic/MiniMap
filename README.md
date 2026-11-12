# Mini Map

A square minimap with a bar under it that holds the minimap buttons. A World of Warcraft addon for **WoW Forever**.

> **Beta.** Version 0.1.0-beta.10 is still being tested in the game. Please report anything that looks wrong on the [Issues](https://github.com/gettic/MiniMap/issues) page.

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
| Square map | The round minimap becomes square, with a thin Blizzard tooltip-style border. It stays square with "Rotate Minimap" on. |
| Button bar | A bar under the map collects the minimap buttons of your other addons, in alphabetical order, so they don't sit around the map's edge. This includes buttons made with LibDBIcon (for example Questie, TomTom, GatherMate2 and HandyNotes), Zygor's icon and All The Things' button. Every button gets the same square 24 px slot, with the icon cropped to fill it and the same hover and press look. Buttons that appear late are picked up too. Buttons in the bar can't be dragged. |
| Header | The zone name, clock, calendar and tracking buttons sit in their own bordered strip just above the map. |
| Corner buttons | The mail icon sits in the map's top-left corner and the addon compartment in the top-right corner. |
| Day/night disc | Blizzard's day/night disc sits in the map's bottom-left corner. |
| Coordinates | If you show player coordinates, they sit inside the map's bottom edge, so they don't cover the bar. |
| Edit Mode | You still move and size the minimap with Blizzard's Edit Mode. The border and the bar follow it, and Edit Mode's box fits the map, header and bar. |
| Layer | The map, its border, the header strip, the bar and the buttons sit in the background layer, so other addons' windows always draw over them. |

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
| Header Underneath | The header strip goes under the map and the button bar above it. The mail icon moves to the bottom-left corner and the day/night disc to the top-left corner. The addon compartment stays top-right, so it never covers the zoom buttons. |
| Selection box | The box covers the map, its header strip and the button bar, so you can move the map flush into a screen corner. It snaps by those visible edges. |
| Rotate Minimap | The map turns inside the square. |
| Icon Size | The map markers resize as normal. |

**Chat command:**

| Command | What it does |
|---|---|
| `/mmap` | Shows a short help. |
| `/mmap rescan` | Puts minimap buttons that showed up late into the bar now. In combat, it waits until combat ends. |
| `/mmap names` | Hold the mouse over a minimap button and type it to see the button's name, and its textures (size, art, crop, shown, alpha). If a button isn't picked up or looks wrong, tell us what it prints so we can fix it. |
| `/mmap pos` | Prints where the minimap's Edit Mode frame is, the screen size and the clamp. Include it in a bug report about the minimap's position. |

Mini Map already looks for new buttons a few times after login and when another addon loads, so you rarely need `/mmap rescan`.

## Other minimap addons

- If another addon that changes the minimap is loaded (for example SexyMap, BasicMinimap or ElvUI), Mini Map leaves the minimap's shape alone and says so in chat.
- If another addon that collects minimap buttons is loaded (for example MinimapButtonButton or HidingBar), Mini Map turns its own bar off and says so in chat.

## Known limits

- **Corner clicks don't ping.** The game only pings inside a circle, so clicking in the square map's corners doesn't send a ping.
- **Some buttons may not be collected.** Mini Map picks up buttons by their name. A button with an unusual name stays where its addon put it. Use `/mmap names` over it and report what it prints on the [Issues](https://github.com/gettic/MiniMap/issues) page.

## For people who change the code

The addon is in the `MiniMap` folder. It needs no libraries.

| File | What's in it |
|---|---|
| `MiniMap_Forever.toc` | Addon info and load order. |
| `Locale.lua` | Every text the player sees. |
| `Theme.lua` | All art, sizes and colours in one table. |
| `Core.lua` | Start-up, saved settings, combat queue, other-addon check, `/mmap`. |
| `Square.lua` | Square mask, hiding the round art, border, coordinates, header strip, corner buttons, day/night disc, layer. |
| `IconBar.lua` | Finding minimap buttons and laying out the bar. |

Saved settings: `MiniMapForeverDB` (account-wide). Position and size are saved by Edit Mode, not by Mini Map.

## Licence

All rights reserved. See [LICENSE](LICENSE).
