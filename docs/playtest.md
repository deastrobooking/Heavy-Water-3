# Playtest checklist

**For:** the owner's hands-on sessions. About 25 minutes; skip a section if you are short of time. Nothing in the game had been played by hand before 2026-10-23, so every check here is new evidence.

**How to record:**
- Tick **Pass** or **Fail** per line.
- Add a short note to anything that felt wrong, even when it "worked": too slow, too easy, unreadable, confusing.
- Hand the sheet back. Results go into [validation](validation.md) as a dated entry and become the tuning list in the [roadmap](roadmap.md).

**Setup:**
- Install the current build from the repository root: `python3 tools/zig.py build -Doptimize=ReleaseFast`.
- Start with `./zig-out/bin/heavy-water`, then NEW GAME.
- Have a controller connected for section 8, and a second one for section 9 if you can.

## 1. Movement (3 min)
| # | Do | Expect | Pass | Fail | Note |
| --- | --- | --- | --- | --- | --- |
| 1.1 | Walk, sprint (Shift), standing jump (Space) | Responsive; standing jump about a two-storey height (5 m) | ☐ | ☐ | |
| 1.2 | Sprint, then jump | A very high, long leap (about 16 m) that still feels controllable on landing | ☐ | ☐ | |
| 1.3 | Hold back and jump; double-tap Ctrl | Backflip; a powered dash | ☐ | ☐ | |
| 1.4 | G (grapple) at a tree or tower; F at a ledge | Grapple pulls you there; F mantles up | ☐ | ☐ | |
| 1.5 | V (flight), Shift to boost, E/Q up and down, V to land | Flight feels stable; landing is easy | ☐ | ☐ | |
| 1.6 | Jump animation | Readable push-off, float and landing; nothing stiff or broken | ☐ | ☐ | |

## 2. Fighting (5 min)
Walk out of the city to the nearest Hive nest (the quest log or the world map shows it).

| # | Do | Expect | Pass | Fail | Note |
| --- | --- | --- | --- | --- | --- |
| 2.1 | Key 5, saber combo (click, click, click) | Cuts connect with a short pause, damage numbers and a little shake; the pad rumbles | ☐ | ☐ | Rate impact 1–5: |
| 2.2 | Right click to guard as a bolt arrives, then just in time to parry | Guard blocks most; a parry sends it back | ☐ | ☐ | |
| 2.3 | Tab to the blaster; hold click to charge, then release | Charged shot clearly stronger | ☐ | ☐ | |
| 2.4 | Z, C, H specials | Grenade, turret and shield all useful; recharge times feel right | ☐ | ☐ | |
| 2.5 | Fight a trooper up close; parry when the orange gem appears over it | You can see its melee coming in time; a parry staggers it | ☐ | ☐ | |
| 2.6 | Destroy the nest | Satisfying payoff: sound, burst, loot message with scrap and parts | ☐ | ☐ | |
| 2.7 | Get knocked out once on purpose | You recover sensibly; it doesn't feel punishing or confusing | ☐ | ☐ | |
| 2.8 | Overall | Is combat fun? What is missing most? | ☐ | ☐ | |

## 3. Detroit (6 min)
| # | Do | Expect | Pass | Fail | Note |
| --- | --- | --- | --- | --- | --- |
| 3.1 | Pause, QUEST LOG | Clear next objective | ☐ | ☐ | |
| 3.2 | Talk to Maro, Ines or Tavi (hands, key 1, click) and start an investigation | Conversation readable; you know where to go | ☐ | ☐ | |
| 3.3 | Follow it to the first evidence point | The way there is findable without help | ☐ | ☐ | |
| 3.4 | Find a discovery cage, climb its tower course, step on the plate, reach the cage within 8 s | Course is fun and fair; you can't just jump to the plate; the gate opens | ☐ | ☐ | |
| 3.5 | Climb to the skyscraper roofs (fly, grapple or a sky lobby) and walk a skyway to the next tower | Skyways are level and connect; a collar around a taller tower lets you step off | ☐ | ☐ | |
| 3.6 | Look around the skyline | Some towers are round, green-terraced eco towers; the city reads well | ☐ | ☐ | |

## 4. Building and defense (5 min)
| # | Do | Expect | Pass | Fail | Note |
| --- | --- | --- | --- | --- | --- |
| 4.1 | Key 7; place, remove and turn blocks; Shift+Tab to change style | Placement is where you aim; the ghost helps | ☐ | ☐ | |
| 4.2 | Shift+click two corners to fill a box | Fills; no noticeable hitch | ☐ | ☐ | Hitch? |
| 4.3 | Tab to a sentry turret and a solar array; build both | Cost shown; both build | ☐ | ☐ | |
| 4.4 | Build a shield generator; stay nearby about 2.5 min for a raid | Warning, raid arrives, turret and shield fight back | ☐ | ☐ | Too easy or too hard? |
| 4.5 | Tab to PLANTS; plant a few | They appear where aimed; they cost a nature block | ☐ | ☐ | |

## 5. Look and sound (2 min)
| # | Do | Expect | Pass | Fail | Note |
| --- | --- | --- | --- | --- | --- |
| 5.1 | Find a glowing sap meadow (lowland near the city) by day, then wait or play into night | Plants read by day; pods, vines and veins glow at night | ☐ | ☐ | |
| 5.2 | Overall look | What looks flat or wrong first? (shadows, haze, colours, ground) | ☐ | ☐ | |
| 5.3 | Sound and music | Hits, booms and music balanced | ☐ | ☐ | |

## 6. Character (1 min)
| # | Do | Expect | Pass | Fail | Note |
| --- | --- | --- | --- | --- | --- |
| 6.1 | F4: change face style, face mark and eye colour | Changes show clearly on the head zoom | ☐ | ☐ | |

## 7. Saving (1 min)
| # | Do | Expect | Pass | Fail | Note |
| --- | --- | --- | --- | --- | --- |
| 7.1 | F5, move away, F9 | You're back where you saved, with what you had | ☐ | ☐ | |

## 8. Controller only (2 min)
| # | Do | Expect | Pass | Fail | Note |
| --- | --- | --- | --- | --- | --- |
| 8.1 | Play sections 1–2 briefly on a pad: A jump, B dodge, RT fire, RB saber, D-pad specials | Everything reachable; nothing awkward | ☐ | ☐ | |
| 8.2 | Menu button for pause; navigate menus | Works without the mouse | ☐ | ☐ | |

## 9. Two players (optional, 3 min)
| # | Do | Expect | Pass | Fail | Note |
| --- | --- | --- | --- | --- | --- |
| 9.1 | Second pad: press its menu button | Split screen; P2 spawns beside you | ☐ | ☐ | |
| 9.2 | P2 fights, uses the fabricator kiosk, builds with LT + D-pad left | P2's loot and blocks are P2's own | ☐ | ☐ | |
| 9.3 | Frame rate with two views | Smooth | ☐ | ☐ | |

## Top three things to fix
1.
2.
3.
