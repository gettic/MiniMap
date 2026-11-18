# Mini Map

A square minimap with a bar under it that holds the minimap buttons. A World of Warcraft addon for **WoW Forever**.

Version 0.2.0. Please report anything that looks wrong on the [Issues](https://github.com/gettic/MiniMap/issues) page.

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
| Square map | The round minimap becomes square, with a thin Blizzard tooltip-style border around it. It stays square with "Rotate Minimap" on. |
| No round ring | The round ring the game draws along the map edge around big quest and dig-site areas is hidden. The area itself still shows. |
| Button bar | A bar under the map collects the minimap buttons of your other addons, in alphabetical order, so they don't sit around the map's edge. This includes buttons made with LibDBIcon (for example Questie, TomTom, GatherMate2 and HandyNotes), Zygor's icon and All The Things' button. Every button gets the same square 24 px slot, with the icon cropped to fill it and the same hover and press look. Buttons that appear late are picked up too. Buttons in the bar can't be dragged. |
| Header | The zone name, clock, calendar and tracking buttons sit in their own framed strip just above the map. The zone and clock plate stretches to fill the strip between the tracking and calendar buttons, so long zone names fit. The whole group (tracking, zone and clock plate, calendar) is centred in the strip, with the same space on both sides. The clock sits at its right end. |
| Corner buttons | The mail icon sits in the map's top-left corner and the addon compartment (the addon counter) in the bottom-right corner. The + / - zoom buttons show in the top-right corner when you hover the map: + upper-left, - lower-right, spaced like Blizzard's bottom-right layout. |
| Day/night disc | Blizzard's day/night disc sits in the map's bottom-left corner. |
| Coordinates | If you show player coordinates, they sit inside the map's bottom edge, so they don't cover the bar. A small see-through dark box behind them makes them easier to read. |
| Edit Mode | You still move and size the minimap with Blizzard's Edit Mode. The border and the bar follow it, and Edit Mode's box fits the map, header and bar. |
| Stays in place | After the UI is hidden and shown, a UI scale change or another addon's "blocked action", the map (and anything snapped to it, such as the buffs) goes back to the spot saved in Edit Mode. This happens out of combat and outside Edit Mode. |
| Mouse guard | Mini Map makes sure the minimap itself takes the mouse, puts back its click area if something shrank it, and turns off the mouse on the game's invisible holder frames around the map (such as the minimap cluster) and on any other big invisible frame lying over it, so clicks (pings) and tooltips reach the map. It doesn't run in combat. While Edit Mode is open the holders get their mouse back, so you can still select and move the minimap; it turns them off again when Edit Mode closes. |
| Layer | The map, its border, the header strip, the bar and the buttons sit in the background layer, so other addons' windows always draw over them. |

The bar hides itself when it has no buttons. Blizzard's event button also goes into the bar while an event is on.

## Install

**With an addon manager:** find **Mini Map** in its list and install it.

**By hand:**
1. Download the zip from the [Releases](https://github.com/gettic/MiniMap/releases) page.
2. Unzip it into your WoW Forever `Interface\AddOns` folder, so you get `Interface\AddOns\MiniMap\`.
3. Restart the game, or type `/reload` if you're already logged in.

## How to use it

Mini Map works by itself as soon as you log in. The only settings are the two compatibility switches (see [Other minimap addons](#other-minimap-addons); `/mmap bookson` and `/mmap zygoron`).

**Move or size the minimap:** open Edit Mode (**Esc > Edit Mode**) and click the minimap.

| Edit Mode option | What happens |
|---|---|
| Drag to move | The map, its border and the button bar move together. |
| Size | The map, border, bar and buttons scale together. |
| Header Underneath | The header strip goes under the map and the button bar above it. The mail icon moves to the bottom-left corner and the day/night disc to the top-left corner. The addon compartment stays bottom-right and the zoom buttons top-right. |
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
| `/mmap bookson` / `/mmap booksoff` | Turns the Library Books pin fix on or off (see [Library Books](#library-books)). |
| `/mmap zygoron` / `/mmap zygoroff` | Turns the Zygor solid-line fix on or off (see [Zygor](#zygor)). |
| `/mmap art` | Lists which border and header button art this game has and says the action bar art is switched off. Include it in a bug report about the border. |
| `/mmap mouse` | Live mouse check for 30 seconds (type it again to stop). Move the mouse onto the minimap and off again. Each time what is under the mouse changes, it prints what that is, whether the minimap sees the mouse, and where the mouse and the minimap are. Include it in a bug report about clicks or tooltips. |
| `/mmap debug` | Hold the mouse over the spot where a minimap tooltip is missing and type it. Prints the tooltip's lines, the map's shape, the frames under the mouse, the minimap's click and hover state, whether the minimap's tooltip is running, a "Map position" line (position, size and scale), a "Border art" line, a "Header" line (screen positions of the strip, tracking button, zone plate and calendar, and the space left and right), a "Place:" line (the map's anchor, Edit Mode's saved anchor, the clamp, the buffs' anchor, and how often the map was moved back), and a "Mouse fixes by Mini Map" line. Include it in a bug report about tooltips, pings or the map's shape. |
| `/mmap selftest` | Mini Map checks itself (map position, header centring, mouse over the map, zoom buttons, border, coordinates box, button bar, and the Zygor and Library Books parts) and prints PASS, FAIL or SKIP for each check, then one result line. The same text opens in a small box: press Ctrl+C to copy it and send it with a bug report. It changes nothing. In combat it waits until combat ends. If Edit Mode is open, it asks you to close it and type the command again. |

Mini Map already looks for new buttons a few times after login and when another addon loads, so you rarely need `/mmap rescan`.

## Other minimap addons

- If another addon that changes the minimap is loaded (for example SexyMap, BasicMinimap or ElvUI), Mini Map leaves the minimap's shape alone and says so in chat.
- If another addon that collects minimap buttons is loaded (for example MinimapButtonButton or HidingBar), Mini Map turns its own bar off and says so in chat.

### Library Books

Works with Library Books by Taraezor. Its far-away minimap pins sit on the square map's edge instead of a curve, and books in the map's corners show at their real spot. Its pins also sit in the map's layer, under the coordinates and under other addons' windows. Mini Map doesn't change Library Books itself, it only moves its pins on the minimap.

Keep Library Books' **Minimap Border Clamp** option on (its default; `/books o` > Minimap (Advanced)). With it off, Library Books hides the corner pins.

On by default. `/mmap booksoff` turns it off and `/mmap bookson` turns it on again. The choice is saved.

### Zygor

Compatible with Zygor Guides (WoW Forever). When Zygor's "Ant trail style:" is set to **Solid lines** (Zygor options > Maps), the path line on the minimap reaches the square map's edge instead of stopping at a circle. Parts of the route that only pass through a corner of the map, away from you, get a plain solid line in the path's colour (Zygor draws nothing there). The "Ant trails" style is already square by itself. Mini Map doesn't change Zygor itself, it only lengthens Zygor's own minimap line.

On by default. `/mmap zygoroff` turns it off and `/mmap zygoron` turns it on again. The choice is saved.

## Known limits

- **Corner clicks don't ping.** The game only pings inside a circle, so clicking in the square map's corners doesn't send a ping.
- **Some markers may still stop at a circle.** The game draws some markers itself, such as party dots and town or flight-master arrows. Mini Map can't change that, so they may still stop at a circle instead of the square's edge.
- **One shift after updating.** On the first load after you update, the map may shift once. If you had dragged the map back after an earlier jump, it may also sit about 27 px higher once. Move it back into place once and save Edit Mode.
- **Gathering dots may be missing in the corners.** The game only shows its own gathering dots (ore, herbs) inside its round tracking range, so they may not show in the square map's corners.
- **Zygor corner route parts look different.** Parts of the route in a far corner are a plain solid line, not Zygor's dashed line.
- **Library Books corner dots may look smaller.** Dots in the corners from other zones may look slightly smaller.
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
| `SelfTest.lua` | `/mmap selftest`: read-only checks and the copy box. |
| `Compat_LibraryBooks.lua` | Moves Library Books' far-away pins onto the square's edge. |
| `Compat_Zygor.lua` | Lengthens Zygor's "Solid lines" minimap path to the square's edge. |

Saved settings: `MiniMapForeverDB` (account-wide). Position and size are saved by Edit Mode, not by Mini Map. Mini Map only keeps the size of Edit Mode's box (`editFit`), so the map stays in its corner after a reload, and the two switches `booksNudge` and `zygorLines`.

## Licence

All rights reserved. See [LICENSE](LICENSE).
