# The Wildkin

The Wildkin are the game's collectible heroes. Long ago the Scalari carried Earth's animals off aboard the Worldcoil Ark to remake them into soldiers. The experiments failed in the best way. The animals woke up upright, clever and super-powered, with their own big hearts instead of orders, and when the Ark broke apart over the Frontier they scattered across it.

Players meet them in the world, recruit them to a shared roster, and play as any of them, solo or in four-player co-op, including in the Starbowl arena. The tone is for ages six and up: bright, heroic and funny. Fights are with Hive *bots*; nobody is hurt, only knocked out.

## How collecting works

| Home | How a hero joins |
| --- | --- |
| Starter | On the roster from the first moment. |
| City plazas | Waiting on a district plaza, under a beam of light in their colour. Walk up and click to meet them. |
| The wilds | On the meadow ring 260–520 m from the spawn, under a beam of light. |
| Mountain caves | In a cache chamber of a cave system in the mountain ranges. |
| Starbowl | Joins when the party clears their arena wave (every third wave: 3, 6, 9 …). |

Joining unlocks the hero's form in the character creator, and **Pause > HEROES** lets any present player become any joined hero (P1–P4 tabs). Choosing **YOUR RANGER** returns that player to the character they made. The roster saves by hero name, so adding heroes never breaks old saves.

Every hero has three powers on Z / C / H (D-pad up, D-pad down, and D-pad up with the right stick held on a controller), plus passives: extra health, saber weight, energy regeneration, run speed, and flight for winged forms.

## The roster

| Hero | Form | Title | Role | Home | Z | C | H |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Bolt Quill | hedgehog | The Blue Blur | speedster | Starter | Spin Dash (launch) | Quill Storm (slam) | Homing Hop (launch) |
| Jinx Kitsu | fox | Foxfire Trickster | trickster | Starter | Fox Fire (chain) | Mirage Step (vanish) | Tail Whirl (slam) |
| Captain Shellshock | turtle | The Living Fortress | tank | Starter | Shell Guard (shield) | Shell Spin (launch) | Tidal Slam (slam) |
| Hopper Vex | rabbit | Moon Jumper | jumper | City plazas | Moon Leap (launch) | Thump Quake (slam) | Bunny Barrage (cone) |
| Rook Bandit | raccoon | Gadget Thief | gadgeteer | City plazas | Gizmo Turret (sentry) | Smoke Bomb (field) | Trash Toss (grenade) |
| Ribbit Rex | frog | Pond Thunder | jumper | The wilds | Super Hop (launch) | Tongue Lash (cone) | Splash Quake (slam) |
| Coil | snake | The Hypnotist | hypnotist | Mountain caves | Hypno Gaze (cone) | Venom Cloud (field) | Coil Strike (blink) |
| Gus Chompa | alligator | Swamp Tank | bruiser | The wilds | Jaw Snap (cone) | Death Roll (launch) | Swamp Stomp (slam) |
| Pip | possum | Never Really Gone | trickster | City plazas | Play Dead (vanish) | Junk Bomb (grenade) | Tail Trip (cone) |
| King Rory | lion | Heart of the Pride | leader | Mountain caves | Mighty Roar (cone) | Pounce (blink) | Pride Rally (heal) |
| Ellie Trunkwell | elephant | The Stampede | tank | The wilds | Trunk Blast (cone) | Stampede (launch) | Earthshaker (slam) |
| Boomer Jo | kangaroo | Outback Boxer | boxer | Starbowl | Haymaker (cone) | Pogo Bounce (launch) | Pouch Shield (shield) |
| Luna Howl | wolf | Moon Hunter | hunter | Mountain caves | Moon Howl (heal) | Pack Dash (blink) | Frost Bite (cone) |
| Ramtank | rhino | Unstoppable Horn | charger | Starbowl | Horn Charge (launch) | Iron Hide (shield) | Ground Crack (slam) |
| Bao Bamboo | panda | Kung-Fu Snack Master | brawler | City plazas | Bamboo Whirl (aura) | Belly Bounce (slam) | Snack Break (heal) |
| Kong Kobalt | gorilla | Mountain Fist | smasher | Mountain caves | Ground Pound (slam) | Boulder Toss (grenade) | Chest Drum (cone) |
| Skye Talon | eagle (flies) | Lord of the Updraft | flyer | The wilds | Dive Bomb (blink) | Gale Gust (cone) | Sky Lift (launch) |
| Blitz | hawk (flies) | Red Streak | flyer | Starbowl | Talon Strike (blink) | Feather Barrage (chain) | Updraft (launch) |
| Sage Hoot | owl (flies) | Night Scholar | mage | Mountain caves | Moon Lance (lance) | Night Veil (vanish) | Wisdom Ward (heal) |
| Echo Vesper | bat (flies) | Sound of the Night | flyer | Mountain caves | Sonic Screech (cone) | Echo Pulse (chain) | Night Glide (vanish) |
| Silk Webster | spider | The Loom | trapper | Mountain caves | Web Snare (field) | Web Swing (blink) | Spiderling Swarm (chain) |
| Kai Mantis | mantis | Calm Blade | blademaster | The wilds | Scythe Flurry (aura) | Mantis Leap (blink) | Zen Guard (shield) |
| Scarab Sol | beetle | Sun Shell | tank | Starbowl | Horn Toss (cone) | Solar Flare (lance) | Carapace (shield) |
| Buzz Honeyjet | bee (flies) | Sweet Sting | healer | City plazas | Honey Heal (heal) | Sting Swarm (chain) | Buzz Dash (blink) |
| Flutter Prism | butterfly (flies) | Rainbow Wing | mage | The wilds | Prism Dust (field) | Rainbow Beam (lance) | Wing Gust (cone) |
| Pinch | scorpion | Desert Guard | bruiser | Starbowl | Tail Sting (cone) | Sandstorm (field) | Pincer Slam (slam) |

Power mechanics are defined in `src/game/Specials.zig`:
- **grenade:** thrown, bursts.
- **sentry:** a turret.
- **shield:** overshield.
- **blink:** a dash that cuts through.
- **slam:** a shockwave around you.
- **lance:** a channelled beam.
- **launch:** a leap or charge, damaging along the way when it spins.
- **aura:** damage around you for a while.
- **field:** a lingering zone where you aim.
- **cone:** a blast in front, which pushes or pulls.
- **heal:** heals the party nearby.
- **chain:** zaps several bots.
- **vanish:** unseen by the Hive, and heals you.

## Bios

- **Bolt Quill** (hedgehog): Runs so fast the wind needs a nap. Spins into a ball and bowls through bots.
- **Jinx Kitsu** (fox): Throws dancing foxfire and vanishes in a puff of mirage.
- **Captain Shellshock** (turtle): Slow to start, impossible to stop. His shell is his shield and his bowling ball.
- **Hopper Vex** (rabbit): Bounces higher than the canopy and lands like thunder.
- **Rook Bandit** (raccoon): Builds turrets from junk and disappears in smoke before anyone notices.
- **Ribbit Rex** (frog): A tongue like a whip and a hop like a cannon.
- **Coil** (snake): One look into her spinning eyes and bots forget what they were doing.
- **Gus Chompa** (alligator): Big grin, bigger bite. Rolls like a log and stomps like a quake.
- **Pip** (possum): Plays dead, gets back up, and throws the bots' own junk at them.
- **King Rory** (lion): His roar shakes the Hive, and his rally gets the whole team back up.
- **Ellie Trunkwell** (elephant): Never forgets a face and never loses a shoving match.
- **Boomer Jo** (kangaroo): Pogo-bounces into the fight and lands a haymaker on the way down.
- **Luna Howl** (wolf): Leads the pack dash and heals friends with a moonlit howl.
- **Ramtank** (rhino): Points his horn at a problem and charges until it is not a problem.
- **Bao Bamboo** (panda): Spins a bamboo staff, bounces on her belly, and always shares her snacks.
- **Kong Kobalt** (gorilla): Pounds the ground, tosses boulders, and drums his chest so loud bots freeze.
- **Skye Talon** (eagle): Dives out of the sun and blows whole squads away with one wingbeat.
- **Blitz** (hawk): The fastest wings on the Frontier, and a sky full of feathers.
- **Sage Hoot** (owl): Reads the stars, casts moonlight lances, and wards the team with wisdom.
- **Echo Vesper** (bat): Hears a bot think from a mile away and answers with a sonic screech.
- **Silk Webster** (spider): Eight legs, eight plans. Webs that glow, snare and swing.
- **Kai Mantis** (mantis): Still as a leaf, then a whirlwind of scythes.
- **Scarab Sol** (beetle): Catches sunlight in her shell and fires it right back.
- **Buzz Honeyjet** (bee): Keeps the team buzzing with honey and the bots busy with stingers.
- **Flutter Prism** (butterfly): Every flap scatters prism dust; every glance can be a rainbow beam.
- **Pinch** (scorpion): Two pincers, one stinger, zero patience for bullies.

## Adding a hero

1. Add the form to `Profile.Species` (append, so saved profiles keep their meaning).
2. Give it features in `character/Beasts.zig`:
   - `family`, `scale` and `eyes`;
   - a case in `build`, made of oriented ellipsoids and chains bound to skeleton joints (ears, snout, tail, wings, extra limbs);
   - `winged` if it flies.
3. Add three powers to `Specials.Kind` and `Specials.info`. Each is a mechanic plus numbers; the test "every Wildkin power is affordable, distinct, and does what its mechanic says" checks that each one has an effect.
4. Add the hero to `Heroes.roster`, with colours, three powers, passives and a home. The roster test requires one hero per form, unique names and powers, and valid colours.
5. Check the look in a lineup capture (`-Dshowcase=48` to `51`), and add a showcase if a fifth lineup is needed.

Limits: the roster and the creator's form bits are `u32` (32 heroes and 32 forms). Character ids 24–31 draw up to eight unmet heroes near P1 at once.
