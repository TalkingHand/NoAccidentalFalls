# No Accidental Falls

A Project Zomboid Build 42 mod that stops you from dying because you walked one step too far on a balcony or a roof.

## What it changes

- **No walking off edges.** Where the floor ends and there is open air below (a balcony without a railing, a roof edge, an unfinished upper floor), you stop at the edge as if there were a wall. Walking, running and sprinting all stop there, and you can still walk along the edge. Stairs, ladders, sheet ropes, windows and fence climbs work as before (at the top of a ladder you can step closer to the edge so the climb down still starts).
- **Climbs onto a drop (optional).** Vanilla already refuses to vault a railing while running when the other side is a drop, and never lets you climb a tall wall onto one. What it still allows is a deliberate climb: holding the interact key (E) at a railing, or choosing *Climb over* / *Climb through* from the menu. A sandbox option decides whether those still work over a drop (default: yes). With it off, they are refused with a short message over your head, unless the window or railing has a sheet rope.

## Sandbox options

| Option | Default | Meaning |
|---|---|---|
| Block walking off edges | on | Stop at open-air edges. |
| Guard climbs over a drop | on | Check fence/railing climbs and window climbs. |
| Allow deliberate climbs over a drop | on | Holding E or using the menu still climbs over a drop. Off: refused (windows and railings with a sheet rope stay allowed). |

## How it works

Every frame, before the game moves you, the mod keeps the centre of your character 0.25 tiles away from any edge whose neighbouring square has no floor (the same way vanilla keeps you off the side walls of stairs). A fall never starts, so there is nothing to roll back. "No floor" uses vanilla's own rule for safe climbs (`IsoPlayer.isSafeToClimbOver`: no solid floor and no stairs below). As a backup, if you still get over an edge within a few frames of standing on floor, you are put back on it. In tests that backup never had to act.

Falls the mod does not cause are left alone: a floor that collapses under you, being pushed, falling while climbing.

## Compatibility

- Lua only, client side. No vanilla files are replaced. The climb check wraps `ISClimbOverFence:isValid` and `ISClimbThroughWindow:isValid` after every mod has loaded.
- Safe to add to or remove from a save.
- Checked in single player: real key presses (walk, run, sprint, diagonal, railing, ground fence, E climbs), climbing a ladder up and down at a roof edge, stairs and an upper-floor window of a real house (with and without a sheet rope, down and back up), a railing with a sheet rope, and a floor removed under the player (you still fall). Gamepad and multiplayer: not tested yet. Your own position is computed on your client in multiplayer too, so it should behave the same.

## Install

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3841006282), or copy `Contents/mods/NoAccidentalFalls` into `%USERPROFILE%\Zomboid\mods\`.

## Testing

`bash tests/tools/livetest.sh` in this folder: `pzt live` (PZTestHarness) plus `tests/tools/keys.ps1`, which brings the test game to the front and presses W/A/S/D/Shift/Alt/E for real. Scenarios: a level-1 platform with open edges and a railing; guard off falls (control), walk east, run north, diagonal into a corner, sprint at the railing, ground-floor vault, long E allowed and refused, the menu climb action, window and floor rules, a ladder at the edge (up and down, guard off and on), a floor removed under the player, a railing with a sheet rope, and a real house nearby (stairs, an upper-floor window with and without a sheet rope). `NAFTest.manual()` builds the same platform for trying it by hand.

## Support

If this mod helps you, you can support it via [Ko-fi](https://ko-fi.com/talkinghands2285) or [PayPal](https://www.paypal.com/paypalme/TalkingHands619/3). It's optional; every feature stays free.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/talkinghands2285)
