# Design decisions

The two source documents — the concept plan and the complete design document —
disagree with each other in about a dozen places, mostly because the design
document revises earlier numbers without deleting them. This file records every
conflict, what the code does, and how to change it if I picked wrong.

**None of these are locked in.** Every one lives in `src/shared/Config.luau` or
`src/shared/KillerData.luau`.

---

## 1. The noise scale — two incompatible systems

Section V of the design document gives one table:

> Walking: 5 noise/second · Running: 25/second · Doors: +30 · Jumping: +15
> Tiers: 0–10 quiet, 11–30 moderate, 31+ chase

The later "NOISE SYSTEM" section gives a different one:

> Walking: +0.5/sec · Running: +2/sec · Opening Door: +15 · Collecting Item: +10
> Breaking Mirror: +25 · Brewing Potion: +40 over 10s · Adjusting Clock: +50
> Falling/Jumping: +8 · Creaky Floor: +12
> Tiers: 0–9 quiet, 10–29 moderate, 30–49 loud, 50+ very loud

**Used: the second.** It's more detailed, it covers actions the first doesn't
(brewing, the clock, creaky floors), and its four tiers pair with the four-colour
meter the UI section describes. The two are not compatible — mixing them would
mean walking for ten seconds hits "chase".

The consequence worth knowing: on this scale, **walking is nearly free** (0.5/sec
against a 0.5/sec decay while still) and **discrete actions are what get you
killed**. Adjusting the clock is a one-shot +50, which puts you straight into
"monsters rush from anywhere on the map". That's the design working as intended,
but it makes the clock objective genuinely frightening, so test it before you
soften it.

`Config.Noise`

---

## 2. Stake tiers — two tables

| | Doc section IX | Doc "COMBAT SYSTEM" |
|---|---|---|
| Common | 30–40 dmg, no stun, 100 coins | 30 dmg, 10s stun, 50 coins |
| Uncommon | 45–60 dmg, 2s stun, 350 coins | 45 dmg, 15s stun, 150 coins |
| Rare | 65–75 dmg, 5s stun, 800 coins | 60 dmg, 20s stun, 300 coins |
| Legendary | 80–90 dmg, 10s stun, 2000 coins | 90 dmg, 30s stun, 750 coins |

**Used: the second.** Both agree on the 3-second cooldown and the 30–90 damage
range the concept plan states, but the second has far longer stuns, which fits
the stated intent much better — *"stakes are defensive, not offensive"*, *"used to
create escape windows"*. A 2-second stun doesn't create an escape window from
something moving at 22 studs/second.

The first table's prices are also steep against the payouts (a 2000-coin
Legendary at ~100 coins a round is twenty rounds of grinding).

`Config.Stakes.Tiers`

---

## 3. Consumable prices — reversed between sections

| | Doc section IX | Doc "Consumable Items" |
|---|---|---|
| 2× Speed Potion | 150 | 200 |
| Health Potion | 200 | 100 |

**Used: the second** (Speed 200, Health 100), for consistency with the stake
table, which also came from the later section. The health potion being the
cheaper of the two also reads right — it's the panic button, and it should be
affordable.

`Config.Shop`

---

## 4. Coins per revive — 10 or 20

Section VIII says *"+10 Coins to reviver"*. The round-end award table says
*"Per revive: +20 coins"*.

**Used: 20**, from the award table, because that table is the complete payout
specification and the other is a passing mention. Reviving is the hardest thing
the game asks of a player and it should pay accordingly.

`Config.Revival.CoinsPerRevive`, `Config.Economy.CoinsPerRevive`

---

## 5. Results screen duration — 5 or 15 seconds

The round-end section says *"5-second results display"*; the state machine says
*"Display End Screen (15 seconds)"*.

**Used: 15.** Twelve players' worth of ranked rows with counting coin totals does
not fit in five seconds.

`Config.Round.ResultsSeconds`

---

## 6. Safe zone duration — 15, 20, or 30 seconds

The helper NPC section says safe zones last 15 seconds in one line and 30 in the
next. Robby's own profile says 20.

**Used: 20**, from Robby's profile, which is the most specific of the three.

`Config.Helpers.SafeZoneDuration`

---

## 7. The family roster — how many killers, and what are they called?

This is the biggest one.

The concept plan says **7 killers**: Bob, Billy, Barbarba, Robbert, Robby, Benny,
Babby. It then says two of them (Robby, Benny) chose to help humans — which
leaves 5 hunters.

The design document spells the same people as Bob, Barbara, Billy, Robert, Robby,
Benny, Baby, and separately lists the killer pool as "Bob, Barbara, Billy,
Robert, Bobby, Baby" — a six-name list including *both* "Bobby" and "Baby".

Then the killer profiles describe:
- **Bobby (The Forgotten Child)** — child-sized, crawls on all fours, uses vents
- **Baby (The Innocent Corrupted)** — child-like, doll movements, hums lullabies,
  very fast, small detection range

These are almost certainly the same character written up twice under two
spellings of the same name.

**Used: 5 killers + 2 helpers.**

| Killer | HP | Chase speed | Hearing |
|---|---|---|---|
| Bob | 620 | 21 | 50 |
| Barbara | 620 | 22 | 45 |
| Billy | 430 | 20 | 40 |
| Robert | 430 | 19 | 55 |
| Baby | 430 | 23 | 30 |

Baby carries **both** descriptions merged: she's the fastest killer with the
worst hearing, *and* she can use crawlspace patrol nodes that nobody else can
reach.

**If you want six killers instead:** copy the `Baby` entry in
`src/shared/KillerData.luau`, rename it `Bobby`, and remove
`CanUseCrawlspaces = true` from one of the two. The roster is read from that
table, so nothing else needs touching.

Names are standardised to the design document's spellings (Barbara, Robert)
rather than the concept plan's (Barbarba, Robbert), which read as typos.

`src/shared/KillerData.luau`

---

## 8. Speeds: "Medium" versus numbers

The killer profiles give speeds twice — once as numbers (Bob 21, Barbara 22,
Billy 20, Robert 19) and once as words ("Medium", "Medium-Fast", "Fast",
"Medium"). The two orderings contradict each other: Billy is "Fast" in words but
20 in numbers, slower than Bob's 21.

**Used: the numbers**, since they're precise and the words aren't. Baby has no
number given, only "Very Fast" — she's set to **23**, making her the fastest,
which matches both her description and her tiny hearing range (a fast killer who
can't hear you is a very different threat from a slow one who can).

Note that every killer's chase speed is at or below the player sprint speed of
24. That's deliberate: a straight footrace is survivable, so chases are decided
by geometry and noise rather than raw speed. Raise these above 24 and the game
becomes much harder very quickly.

`src/shared/KillerData.luau`

---

## 9. Injured players: frozen or crawling?

The death and revival section says the downed player *"Cannot move or interact"*.
The Flee-the-Facility inspiration section suggests *"Injured players could slowly
crawl toward teammates... adds agency and desperation"*.

**Used: frozen** (`CrawlSpeed = 0`), following the specification rather than the
suggestion. But it's one number: set `Config.Revival.CrawlSpeed = 4` and downed
players crawl. Worth trying — the inspiration section is right that it adds
something.

`Config.Revival.CrawlSpeed`

---

## 10. Things I added that neither document specifies

Called out so you can remove them if they're not wanted:

**Sprint stamina** (`Config.Player.StaminaEnabled`). Neither document mentions
stamina. Without it, the optimal play is to hold Shift permanently and simply
accept a pegged noise meter, which flattens the whole stealth system into a
footrace. Stamina forces sprinting to be a decision. Set `StaminaEnabled = false`
for the literal design-document behaviour.

**Backup vision** (`Config.Killer.Vision`). The killers are blind by design and I
kept that, but a 14-stud, 70-degree cone exists so that standing directly in
front of one isn't literally free. Set `Enabled = false` for pure sound-only
hunting.

**The imposter helper.** The Identity Fraud section *suggests* a 5% chance that
"Robby" is actually Robert in disguise, with red eyes as the tell. It's listed as
inspiration rather than as a feature, but it's implemented, at the suggested 5%.
`Config.Helpers.ImposterChance = 0` turns it off.

**Long-hide suspicion.** The Doors section suggests that hiding in one spot for
30+ seconds should make monsters suspicious. Implemented: camping a spot doubles
the chance a passing killer searches it.
`Config.Killer.LongHideSuspicionSeconds`.

**Cross carry weight.** The document says collecting crosses *"weighs down player
slightly (slower movement)"* without a number. Implemented as a 10% speed penalty
per cross carried, compounding, capped at six. `Config.Objectives.Crosses`.

**Ranking weight.** The results screen ranks by "tasks + revives" without saying
how they're weighted. Revives count double, on the grounds that crossing a dark
house to pick someone up is a bigger ask than taking a bottle off a shelf.
`StatsService.REVIVE_RANK_WEIGHT`.

---

## 11. Where the Three.js mockups overrode the PDFs

A later set of mockups (`house.js`, `characters.js`, `props.js` and friends)
arrived after the PDFs, authored directly in Roblox studs. Where they disagree
with the design documents, **the mockups win** — they're the more recent
statement of intent. Three cases:

| | PDF said | Mockup says | Used |
|---|---|---|---|
| Baby's chase speed | "Very Fast" (read as 23) | 20 studs/s | **20** |
| Baby's hearing | "Small" (read as 30) | 40 studs | **40** |
| Safe zone duration | 15 / 20 / 30 | 30 seconds | **30** |

The mockups also supplied things the PDFs never specified, which are now the
source of truth in `src/server/Build/HouseData.luau`:

- The House's real four-floor layout, room bounds and wall openings
- All fifteen hiding spots, by type and position
- Nine noisy floor patches with their exact footprints
- Three safe zones, each with the three entrances the PDF asked for
- Exactly 15 bottle, 14 cross and 5 mirror positions — matching the objective
  goals precisely, so each objective now draws from its own designed pool
- A hand-authored patrol loop per killer, replacing the zone-guessing heuristic

Two things I changed from the mockup, both because a visual mockup doesn't have
to be walkable and a game does:

- **The cellar stair was turned.** As drawn it descended from the Cellar Stair
  room and surfaced in the kitchen. It now runs -Z and arrives in the Boiler
  Room.
- **Stairwell openings were cut.** The mockup's floor slabs are solid, so the
  grand stair, cellar stair and attic ladder all arrived into the underside of
  the storey above. `HouseData.FloorHoles` now cuts three openings, and
  `MapBuilder` subtracts them from the slabs.

## 12. Not built yet

- **The Yard, Menen's Lair, The Graveyard.** Listed as future maps in the
  document. They're in `Config.Maps` with `Enabled = false`, so they show in the
  vote UI as "Coming soon". Build one, save it to `ServerStorage/Maps/<Id>`, flip
  the flag.
- **Ava's dialogue** is written and wired (`AvaService`), but she only appears on
  a map with a `DH_AvaGrave` part — so, the Graveyard, when it exists.
- **"The Full Family Dinner"** finale (all five killers at once) — a stretch idea
  from The Mimic section. Nothing implements it; `Config.Killer.MaxActive` would
  need raising and the round would need a separate mode.
- **Proximity voice as noise.** The Bear section suggests routing Roblox's
  spatial voice volume into the noise meter. Not implemented; it needs voice chat
  enabled on the experience first.
- **The cursed-player mechanic** from the same section. Not implemented.
