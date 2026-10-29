# UI styleguide (Steal a Slime)

How every screen in the game looks and reads. The look is **Goo**: the UI is made of slime. Glass panels, mint jelly buttons, Ink outlines, gold money. The values live in code: colours in `Shared/GooPalette` (screen UI reads them through `Widgets.Theme`), fonts in `Widgets.Theme`, radii and outlines in `Widgets.KIT`, sizes in `Layout`. This guide says **which one to use when**. It names tokens and never repeats their values; change a value in code, not here.

Decided by Merijn on 2026-10-21; the Goo look was chosen the same week. Mockups of every Goo screen and the kit recipes: [Goo canvas](https://claude.ai/artifact/VYUA8sfDux2gNnBHwf26M1). Screenshots from before the redesign: [UI gallery](https://claude.ai/artifact/S59FiwP847LSKKPTdJFCzS). Both are private to Merijn. What still breaks these rules is listed at the end.

## Principles

1. **One look for everything on the screen.** Menus, HUD, notices, popups and the loading screen use the same tokens and the same parts from `Widgets`. A new screen starts from `Widgets.panel`, `button`, `chip`, `status` and `rowFrame`, not from a raw `Frame`.
2. **Colour means something.** Each colour below has one job. If a colour is not doing that job, use the neutral ones (Bg, Row, Ink, Text, Muted).
3. **Only what you can press is jelly.** Buttons, menu tiles and the tabs you can tap are shaded, shiny jelly. Something you can't press (a state, a fact, a disabled button) is a flat sunken Ink well with the same outline.
4. **The world wears the same goo, not the same cards.** Signs, pad planks and slime tags use the Goo colours and outlined text, on their own shapes (`GooBoard`, jelly signs, goo-dipped planks). No menu card floats in the world; no wood plank sits in the HUD.

## Colour roles

| Token | Use it for | Never for |
|---|---|---|
| `Ink` | Every outline, dark text on bright fills, sunken wells (`status`, `chip`), disabled buttons | Body text on Bg |
| `Bg` | The glass panel and card bodies | Buttons |
| `Row` | List rows and cards inside a panel | Panel bodies |
| `BgLight` | The highlighted or selected row | Plain rows |
| `Band` | A panel's mint header band, its goo lip and drips, its corner icon tile | Rows, buttons |
| `Glass` | A see-through row on a card (at `GooPalette.GLASS_TRANSPARENCY`): HUD status bubbles, key card rows | Panel bodies |
| `Text` | Titles and body text | |
| `Muted` | Subtitles, hints, disabled labels, "you have $25" lines | Anything the player must read to act |
| `Gold` / `GoldDeep` | Money: the coin (GoldDeep is its edge), cash amounts, **collecting a reward** (Claim, Collect), the ring on info and guidance notices | Ordinary actions like Buy or Merge |
| `Accent` / `Good` | **The main action** on a card (Redeem, Buy, Merge), income, success ticks, progress fills | Rewards, warnings |
| `Bad` | **Losing something** (Drop, Sell), the ring on danger notices, alarms, "Missing" chips, the close X | Anything that only needs attention |
| `Warn` | Timers running out, locked-until hints | Buttons |
| `Info` | Secondary buttons (Pick for me, Auto-merge), counts and badges, the boss meter's goo | Main actions |

`Good`, `Accent` and `Band` are the same mint on purpose: income, the main action and the header share it. Never write a raw `Color3` in a panel or a world script; add the colour to `GooPalette` (and a `Theme` token for screen UI) if none fits.

## Type

- **Fredoka One** (`Theme.Font`) for titles, buttons, numbers, chips and HUD labels.
- **Nunito Bold** (`Theme.FontBody`, a `FontFace`) for sentences: descriptions, tutorial and tooltip body text. `Widgets.label` uses it unless a `Font` or `FontFace` is given.
- Sizes come from `Layout` or a frozen table at the top of the panel (`PANEL_CHROME.titleSize` for panel titles). Keep to these steps, largest first: panel title, card title, button, row title and chip, body, hint.
- **Nothing smaller than 14 design px on desktop**, and body text is never the smallest size on the card. A hint that has to be smaller than that is cut, not shrunk. Add the minimum as a `Layout` token when the first panel uses it.
- Titles and buttons have the Ink text stroke on bright fills (`Widgets.inkOn` does this).

## Writing

- **Sentence case** for every title, button, row and label: "Daily reward", "Welcome back", "Item shop", "Upgrade shop", "Pick for me". Capitals only for names: SlimeDex, Goozilla, species names.
- **ALL CAPS only for the two alarms**: "STOLEN!" and "BOSS INCOMING". Nothing else shouts.
- **No "!" on buttons.** A button names what it does: "Claim", "Collect", "Redeem", "Sell $45". The result uses the same word ("Claimed").
- A disabled button says why and what's missing: "Need $39.9K more", "Rebirth 3 to unlock".
- Numbers go through `Format` (cash, timers, percentages), so "$1.5K", "4d 5h" and "7:56" look the same everywhere.
- Tooltips: name, one sentence on what it does, then the time left.

## Shapes and depth

- **Pills and circles** for buttons, wells, chips, badges and status bubbles (`Widgets.pill`). Panels use `KIT.panelRadius`, rows and cards `KIT.rowRadius`, icon tiles `KIT.radius`, the hotbar plate and its slots `KIT.plateRadius` / `KIT.slotRadius`.
- Outlines are always `Ink`: `KIT.stroke` on panels, buttons and tiles, `KIT.rowStroke` on rows.
- **Jelly** is `Widgets.shade` (top light, bottom dark). No white glint lines. Only pressable things get it.
- **Glass** is `Bg` or `Glass` with transparency, never blur. The HUD's status bubbles are glass (`Layout.STATUS_BUBBLE`).
- **Goo edge**: a panel's band drips onto the body (`Widgets.gooEdge`, sized by `Layout.GOO_EDGE`): each drip is one blob, a soft shoulder under the band, a thick neck and a round drop. No dotted lip, no shine dots. Every menu in one ScreenGui shares one edge, moved into whichever panel is open, to stay inside the UI budget.
- **Notice rings**: `Widgets.ring` puts the colour ring (Gold or Bad) inside an Ink ring. Notices use `Layout.NOTICE_RADIUS`.
- No drop shadows and no glows on screen UI.

### Roblox limits the look is built around

- One `UICorner` per frame, the same on every corner. A shape with different corners is two frames.
- One `UIStroke` per frame. A second ring needs a wrapper frame (that is what `Widgets.ring` does).
- A `UIGradient` multiplies the frame's colour, so shading stops are grey brightness factors.
- Every instance counts against `ui-perf-budget.json`. Share parts (the goo edge) instead of stacking decoration layers.

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
  - **Lists fill the window**: Goals, SlimeDex, Plot skins, Item shop, Upgrade shop, Bag and any menu that scrolls.
  - **Short cards fit their content** and are centred: Codes, Sound, Guide, Merge vat, Rebirth, and every popup (Daily reward, Welcome back).
  - Both start on the same top line, under the HUD. No menu is pinned to the screen's top edge or floats at its own height.
- Under the header: one line of facts as chips (balance, reset timer, found count), then the body.
- **Every list has an empty state**: one line saying what will be here and how to get the first one ("No items yet. Buy one at the Item shop."). An empty panel is never just blank space.

## Notices

Notices appear on their own; menus are opened by the player.

- **Border colour says what it is:** `Gold` border for info and tips (status tooltips, the tutorial notice card, carry card, hotbar tip), `Bad` border for danger (steal banner, boss meter). Menus, HUD clusters and popups keep the plain Ink outline.
- **Where they go:**
  - Alarms (STOLEN!, boss) stack top-centre, under each other, in the banner stack.
  - The tutorial is a Gold notice card just above the hotbar (above the carry card while carrying); the carry card sits bottom-centre above the hotbar.
  - Tooltips open above the thing they explain and stay on screen.
  - Edge arrows (thief, home, next step) sit on the screen edge pointing at their target.
- **No toasts.** A notice that only reports something plays its sound. If players must see it, it gets a place above.
- A notice never covers the X of an open menu or the hotbar.

## HUD

- Fixed clusters: menu tiles left, money bottom-left, status icons bottom-right, hotbar bottom-centre, sound button top-right. Nothing new goes on the HUD without a slot in `Layout`.
- Status icons sit in glass bubbles with a mint timer pill under them, all the same way. A bubble's ring turns `Gold` while its tooltip shows.
- Menu tiles are mint jelly (`NavTile`); money is a glass pill with the gold coin.
- Edge arrows (home, tutorial) hide while a menu or popup is open (`Constants.MENU_OPEN_ATTRIBUTE`).
- Badges on menu tiles: `Bad` "!" for something to do, `Info` for a count or percentage.

## World UI

- World scripts read colours from `Shared/GooPalette` directly (the server and the visuals have no `Widgets`).
- Text is outlined Fredoka: white with an Ink edge, Ink on bright goo.
- Boards (plot signs, podiums, the ritual sign) are a `GooBoard`: a glass card with an Ink edge and a mint band that drips. Shop stands carry a jelly sign (`Props.standSign`): mint for the Item shop, gold for the Upgrade shop. Icons that clash as emoji are drawn instead (`Shared/GooIcons`, the Upgrade shop's arrow).
- On your own plot the next pad you can buy has a mint outline and a "Buy pad $X" tag (`NextPadMarker`); gold "Next pad $X" while you can't afford it.
- Slime tags (`SlimeInfoCard`): the rarity on a pill of its colour, the name, the income in mint, and a gold "Buy" chip while it is for sale and you stand close; where tags overlap only the nearest shows. Pad planks (`SlimePadSign`) are wood dipped in goo of the rarity colour.
- The key card over your own pad slime is the one screen-style card in the world, because it stands in for Roblox's prompt bubbles: glass rows with jelly key chips.
- The "Your plot" tag is your avatar in a mint jelly badge; the edge arrow home uses the same badge with a house.
- Rarity colours come from `Config.RARITIES[tier].color`, never a local table.

## Loading screen

The first thing players see, built by `first/LoadingScreen.luau`: a `Bg` to `BgDeep` backdrop, the title in mint with the Ink stroke, a goo bar in an Ink tube, and Skip as a secondary jelly button. It runs before `Shared` replicates, so `first/LoadingLook.luau` keeps its own copy of the palette and `tests/ui/LoadingLook.spec` checks it still matches `GooPalette`.

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

The Goo redesign (the kit, the HUD and notices, copy and per-screen layouts, world labels and the loading screen, and the clean-up) fixed every line of the first audit: sentence case and no "!" everywhere, gold and pink notice rings, matching status bubbles, an empty Bag message, nothing under `Layout.MIN_TEXT`, the Goo loading screen, and the unreachable Top earners and old Shop cards are gone.

Not checked again since: the shared top line for every short card, and phone and tablet layouts beyond the `LayoutAssert` viewports.
