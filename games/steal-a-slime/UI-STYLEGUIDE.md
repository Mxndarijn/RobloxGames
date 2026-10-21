# UI styleguide (Steal a Slime)

How every screen in the game looks and reads. The values live in code: colours and fonts in `Widgets.Theme`, radii and outlines in `Widgets.KIT`, sizes in `Layout`. This guide says **which one to use when**. It names tokens and never repeats their values; change a value in code, not here.

Decided by Merijn on 2026-10-21. Screenshots of every screen as it is today: [UI gallery](https://claude.ai/artifact/S59FiwP847LSKKPTdJFCzS) (private to Merijn). What breaks these rules now is listed at the end.

## Principles

1. **One look for everything on the screen.** Menus, HUD, notices, popups and the loading screen use the same tokens and the same parts from `Widgets`. A new screen starts from `Widgets.panel`, `button`, `chip`, `status` and `rowFrame`, not from a raw `Frame`.
2. **Colour means something.** Each colour below has one job. If a colour is not doing that job, use the neutral ones (Bg, Row, Ink, Text, Muted).
3. **The world has its own look.** Signs, pad planks and slime tags in the 3D world are wood, goo and outlined text. They don't copy the menu cards. Screen UI and world UI never mix: no menu card floats in the world, no wood plank sits in the HUD.

## Colour roles

| Token | Use it for | Never for |
|---|---|---|
| `Ink` | Every outline, dark text on bright fills, sunken wells (`status`, `chip`), disabled buttons | Body text on Bg |
| `Bg` | Panel and card bodies | Buttons |
| `Row` | List rows and cards inside a panel | Panel bodies |
| `BgLight` | The highlighted or selected row | Plain rows |
| `Band` | A panel's header band and its corner icon tile | Rows, buttons |
| `Text` | Titles and body text | |
| `Muted` | Subtitles, hints, disabled labels, "you have $25" lines | Anything the player must read to act |
| `Gold` | Money: the coin, cash amounts, **collecting a reward** (Claim, Collect), info borders | Ordinary actions like Buy or Merge |
| `Accent` / `Good` | **The main action** on a card (Redeem, Buy, Merge), income, success ticks, progress fills | Rewards, warnings |
| `Bad` | **Losing something** (Drop, Sell), danger borders, alarms, "Missing" chips, the close X | Anything that only needs attention |
| `Warn` | Timers running out, locked-until hints | Buttons |
| `Info` | Secondary buttons (Pick for me, Auto-merge), counts and badges | Main actions |

`Good` and `Accent` are the same green on purpose: income and the main action share it. Never write a raw `Color3` in a panel; add a token to `Theme` if none fits.

## Type

- **Fredoka One** (`Theme.Font`) for titles, buttons, numbers, chips and HUD labels.
- **Gotham Medium** (`Theme.FontBody`) for sentences: descriptions, tutorial and tooltip body text.
- Sizes come from `Layout` or a frozen table at the top of the panel (`PANEL_CHROME.titleSize` for panel titles). Keep to these steps, largest first: panel title, card title, button, row title and chip, body, hint.
- **Nothing smaller than 14 design px on desktop**, and body text is never the smallest size on the card. A hint that has to be smaller than that is cut, not shrunk. Add the minimum as a `Layout` token when the first panel uses it.
- Titles and buttons have the Ink text stroke on bright fills (`Widgets.inkOn` does this).

## Writing

- **Sentence case** for every title, button, row and label: "Daily reward", "Welcome back", "Item shop", "Top earners", "Pick for me". Capitals only for names: SlimeDex, Goozilla, species names.
- **ALL CAPS only for the two alarms**: "STOLEN!" and "BOSS INCOMING". Nothing else shouts.
- **No "!" on buttons.** A button names what it does: "Claim", "Collect", "Redeem", "Sell $45". The result uses the same word ("Claimed").
- A disabled button says why and what's missing: "Need $39.9K more", "Rebirth 3 to unlock".
- Numbers go through `Format` (cash, timers, percentages), so "$1.5K", "4d 5h" and "7:56" look the same everywhere.
- Tooltips: name, one sentence on what it does, then the time left.

## Shapes and depth

- Radii from `Widgets.KIT`: the panel's own radius for panels, `rowRadius` for rows and cards, `radius` for buttons, wells and icon tiles, full pills for chips and badges.
- Outlines are always `Ink`: `KIT.stroke` on panels, buttons and tiles, `KIT.rowStroke` on rows.
- Depth comes from `Widgets.shade` (top light, bottom dark) on buttons, tiles and HUD chips. No drop shadows, no glows on screen UI.

## Buttons

- **One main button per card.** Its colour follows its meaning:
  - `Gold`: collect a reward (Claim, Collect).
  - `Accent`: every other main action (Redeem, Buy, Merge, a shop price).
  - `Bad`: lose something (Drop, Sell).
- Secondary buttons are `Info`. A card may have several.
- **Irreversible actions hold to confirm** (`Widgets.holdButton`): Rebirth, Sell.
- Disabled is `Theme.Disabled` with Muted text and the reason as its label, never a greyed-out main colour.
- A **state is not a button**: "Owned", "Max", "Locked" use `Widgets.status` (a sunken well). A **fact** in a header line ("Resets in 3:05", "0/7 done") is a `Widgets.chip`.
- Every tap target is at least `Layout.MIN_TOUCH` screen px.

## Menus

- Every menu is a `Widgets.panel`: header band, corner icon tile, sentence-case title, red X top-right. Esc and gamepad B close it too.
- **Two sizes:**
  - **Lists fill the window**: Goals, SlimeDex, Item shop, Upgrade shop, Bag and any menu that scrolls.
  - **Short cards fit their content** and are centred: Codes, Sound, Guide, Merge vat, Rebirth, and every popup (Daily reward, Welcome back).
  - Both start on the same top line, under the HUD. No menu is pinned to the screen's top edge or floats at its own height.
- Under the header: one line of facts as chips (balance, reset timer, found count), then the body.
- **Every list has an empty state**: one line saying what will be here and how to get the first one ("No items yet. Buy one at the Item shop."). An empty panel is never just blank space.

## Notices

Notices appear on their own; menus are opened by the player.

- **Border colour says what it is:** `Gold` border for info and tips (status tooltips, tutorial card, carry card, hotbar tip), `Bad` border for danger (steal banner, boss meter). Menus, HUD clusters and popups keep the plain Ink outline.
- **Where they go:**
  - Alarms (STOLEN!, boss) stack top-centre, under each other, in the banner stack.
  - Guidance (tutorial card, carry card) sits bottom-centre above the hotbar.
  - Tooltips open above the thing they explain and stay on screen.
  - Edge arrows (thief, home, next step) sit on the screen edge pointing at their target.
- **No toasts.** A notice that only reports something plays its sound. If players must see it, it gets a place above.
- A notice never covers the X of an open menu or the hotbar.

## HUD

- Fixed clusters: menu tiles left, money bottom-left, status icons bottom-right, hotbar bottom-centre, sound button top-right. Nothing new goes on the HUD without a slot in `Layout`.
- Status icons are bare icons with a timer pill under them, all the same way. No tile behind one and not the others.
- Badges on menu tiles: `Bad` "!" for something to do, `Info` for a count or percentage.

## World UI

- Built from wood, goo in the rarity colour, and outlined `Theme.Font` text (white with an Ink edge), as `SlimeInfoCard`, `SlimePadSign` and `PlotSigns` do.
- The key card over your own pad slime is the one screen-style card in the world, because it stands in for Roblox's prompt bubbles.
- Rarity colours come from `Config.RARITIES[tier].color`, never a local table.

## Loading screen

The first thing players see. It runs before `Widgets` arrives, so `first/LoadingLook.luau` keeps a copy of the palette and `tests/LoadingLook.spec` checks it matches `Theme`. Its colours are already right; its treatment should match the menus too: a `Band` to `Bg` shade on the background, the title with the Ink text stroke, and the Skip button drawn like a secondary button (`Info` fill, Ink outline, shade).

## Checklist for a UI change

- [ ] Built from `Widgets` parts, colours and fonts from `Theme`, sizes from `Layout` or a frozen table.
- [ ] One main button, coloured by meaning; irreversible actions hold to confirm.
- [ ] Sentence case, no "!" on buttons, numbers through `Format`.
- [ ] No text under the minimum size.
- [ ] Menu uses the right size (list or short card) and starts on the shared top line.
- [ ] Lists have an empty state.
- [ ] Notices have the right border and place, and don't cover the X or the hotbar.
- [ ] Checked at the `LayoutAssert` viewports, phone included.

## Where the game breaks these rules today

From the screenshots of `main` at d2f4514d (desktop). Each line names the rule it breaks.

| Screen | What is off | Rule |
|---|---|---|
| Codes, Guide, Merge, Upgrade shop, Top earners, Sound | Each floats at its own height; Sound is pinned to the top edge | Menus: shared top line |
| Daily reward, Welcome back | "Claim!", "Collect!" | Writing: no "!" on buttons |
| Daily reward, Item shop, Upgrade shop, Top earners, Merge vat, Welcome back! | Title Case titles, "!" in a title | Writing: sentence case |
| Tutorial card | Green border | Notices: gold for guidance |
| Boss meter | No border | Notices: red for danger |
| Friend status icon | Green tile behind it, the other status icons have none | HUD: status icons all bare |
| Bag | Empty panel with no message | Menus: empty state |
| Top earners card, old Shop card | Nothing opens them in this build | Delete them or give them an entry point |
| Goals, shops (row subtitles) | Text below the minimum size | Type: minimum size |
| Loading screen | Flat background, title without stroke, dark Skip well instead of a button | Loading screen: same treatment |
| Tutorial "Hide" button | Square tile style unlike other secondary buttons | Buttons: secondary is `Info` |

Not checked yet: phone and tablet layouts, the STOLEN! banner, the hint ring and the move-slime bar.
