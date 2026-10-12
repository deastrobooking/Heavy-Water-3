# Detroit Arbor Reach

The first city is **Detroit, Michigan**, reimagined as the Detroit Arbor Reach: a bounded lower-canopy district around three resident Arbors. The city keeps Detroit's industrial and civic character, translated into living infrastructure: older Gothic civic landmarks and newer spired towers share the skyline with foundries, machine halls, pipe runs, rail yards, and Hive-vulnerable production blocks. A broad Detroit River runs past an industrial promenade and ferry pavilion; Belle Isle is a dry, wooded park island with paths and pedestrian approaches. Two large road bridges cross toward Windsor, with illuminated cable towers on the grand crossing. Six stable plaza anchors form a loop, with three generated towers, two trunk-ring plazas and their spurs, market canopies, and vine-supported bridge roads. The test Arbor's existing ramp and tower provide the walking entrance.

## Visit and build

1. From spawn, climb the test Arbor's spiral ramp and cross its original bridge to the tower. This is **plaza 0**, the entrance to the new road loop. You can also press **V** and fly up to a plaza, then switch back to walking.
2. Follow the loop through plazas **1 → 2 → 3 → 4 → 5 → 0**. Plazas 2 and 4 have short spurs to walkways around the narrow and spreading Arbors.
3. Press **2**, use **Tab** to select the rover, and aim at open plaza deck within 14 m. A green preview confirms support and clearance; left-click places it. Press **1**, aim at the rover, and click to enter. WASD drives, Space brakes, and click exits onto the deck.
4. Press **4** for bridges. Cyan markers appear at the six plaza centers. **Tab** chooses the structure: suspension, cable-stayed, arch, truss, or girder. Aim at a visible marker and click to select the source; aim at another marker to preview a span with its structure. Green is valid, red is rejected. Click to build. **0 → 3** is a valid shortcut in the default district; duplicate roads and obstructed routes are rejected with a reason on the HUD.
5. Right-click cancels a pending bridge. With no source selected, aim at one of your completed bridges nearby and right-click to remove it. The original district roads remain permanent.
6. **F5 / F9** saves and restores construction, machines, sap taps, and the player. Bridge endpoints persist as plaza IDs; collision and rendering are rebuilt from the same generator.

## The sky city

The district is a city in the sky, held up by steel and living roots. Around the canopy loop, the district skyline mixes modern Arbor towers, warm-windowed Gothic landmarks with lancet arches and clustered pinnacles, and broad industrial buildings with exhaust stacks, service pipes, and overhead transfer gantries. The east/northeast industrial belt gives Hive forces a believable foothold around the factories and rail works. Every road is a styled steel bridge, assigned by span length so that one district shows every style, longest first:

| Style | Structure | Colour |
| --- | --- | --- |
| Suspension | Twin towers rising from the forest floor with three crossbeams, parabolic main cables from anchorages over the tower saddles, hangers every ~9 m, and a stiffening girder | International orange |
| Cable-stayed | An H pylon at midspan with two fans of ten stays per side, on braced end piers | White |
| Arch | A steel arch rising 16–42 m over the deck, hangers every ~8 m, top struts, and braced abutment piers | Copper-teal |
| Truss | Warren truss side walls 8 m tall, overhead lateral bracing, on braced piers every ~60 m | Dark steel blue |
| Girder | A deep box girder on braced steel pole piers every ~48 m | Steel grey |

Roads without towers stand on **braced pole piers**: twin steel columns from concrete footings on the forest floor, X-braced in one or two stories, under a cap beam. Piers never stand inside a plaza or near a trunk. The free-standing Arbor junction plazas stand on four braced legs. Trunk spurs keep the original organic vine cables.

The skyline has **skyscrapers**, about twenty per district. Some stand alone on the forest floor, up to about 270 m to the spire. Each tower plaza also has a skyscraper beside it, joined by a walkable **sky lobby** deck at plaza level.

Modern towers have setback tiers, floor bands, corner fins, a crown, and a spire. The Gothic palette uses weathered warm-gray stone, narrow gold-lit windows, pointed arches, and clustered spires; the factory palette uses charcoal steel, oxidation-orange structure, repeated monitor bays, exposed flues, and red hazard lamps. Existing glass-teal, bronze, white/cyan and dark-steel palettes remain on modern towers.

Placement is seeded and validated. A tower keeps clear of every road and trunk spur, every plaza-to-plaza route a player could still bridge, plazas, trunks, the spawn area, and other towers. A player bridge through a tower is rejected with "A SKYSCRAPER BLOCKS THIS ROUTE".

At dusk the city lights up:

- warm window columns glow on every facade;
- red warning beacons light the spires;
- cyan light strips run along every road's rails;
- light strings follow suspension cables and arch ribs.

By day the window columns read as glass. Glow is surface emission; the renderer has no bloom.

Every structure keeps the same 14 m deck and a clear envelope above it: nothing solid within 6.5 m of the centre line, up to 6 m above the deck. Lanes, walkways, traffic, pedestrians, and players use every style the same way. Tests check the envelope for every style on every road and on the 0 → 3 span, check that towers and piers reach the ground, and check that a player stands on each style's lanes and walkways. The full walk and drive loops cross all of them.

## Traffic, pedestrians, and markets

Three cars and eight pedestrians live on the district. Cars are the rover's raycast vehicle, with no machine attached, steered by an autopilot along the right-hand 3.5 m lane. Each car picks a seeded destination plaza and takes the shortest route by road length, player bridges included. Pedestrians are the player's character controller walking at 1.5 m/s along either walkway, crossing plazas to a seeded next road.

Rigid bodies do not collide with each other, and characters are not bodies. So cars yield instead: they slow and stop short of anything in their lane within 16 m, including players, pedestrians, other cars and rovers. Plazas are first come, first served: a car arriving at a plaza waits at its edge while another car is inside. Two cars that block each other for 6 s stop yielding for 3 s, which the counters record as a deadlock broken.

When you build a bridge, traffic starts using it as soon as it is shorter. Removing a bridge first **closes** it: it leaves the route graph at once, traffic already on the deck finishes crossing, and it disappears when empty. A car whose route used the bridge replans from the plaza it is heading to; one that has not yet driven onto the deck replans from where it is. City life is not saved; loading restarts it on the loaded roads. Flipped or fallen cars and snagged pedestrians are recovered and counted, and the acceptance run requires zero recoveries.

The towers at plazas 1, 3 and 5 each have a stall under the market canopy with a keeper:

- **Selling parts:** salvaging a relic yields one part, and a stall buys every part you carry at 3–6 scrap each, depending on the stall and day.
- **Buying kits:** stalls sell kits of three market blueprints. The **proximity gate** opens for anyone near either side, the **street lamp** lights when someone is near, and the **signal relay** repeats bus channel 1 onto channel 2 with an indicator.
- **Stock and restock:** each stall stocks 0–3 of each kit per day, never nothing at all, at 80–125% of the base price. Days turn over at dawn, when every stall restocks with that day's seeded stock.
- **Using kits:** a kit places one machine from the build palette and is used up. Removing the machine returns the kit. Kit machines cannot be captured as prefabs.
- **Saving:** scrap, parts, held kits, stall stock and the day it was stocked are saved, along with each machine's kit flag.
- **Keepers:** clicking a stall greets its keeper: **Maro** (south, plaza 1) the tinker, **Ines** (north, plaza 3) the sap broker, and **Tavi** (west, plaza 5) the Rootdeep scout. Each conversation can open the trade panel. Maro also sells suit upgrades and armor suits. Keepers remember meeting you and react to salvage, finished shrines and bridges you build, and some replies come with a scrap gift once. Pedestrians stop to chat when clicked.
- **Co-op:** guests trade too, sharing P1's wallet. Aim at a stall and press **X**; the D-pad chooses a row, **X** trades, and **B** closes. A trading guest stands still. P1 on a controller uses the same buttons.

## Metro loop and the wider city plan

The first light-rail loop follows the six-plaza bridge circuit, above the road deck. Twin luminous guide rails, cross ties, and outboard support pylons keep the roadway clear. Walkable boarding platforms sit at the South, North, and West market towers. Their stops are available on the world map as **METRO: SOUTH LINE**, **NORTH LINE**, and **WEST LINE**; station arrivals find a clear patch of platform and leave each player's gear and motion intact. Existing ladders, ramps, patios, and grapple anchors connect the stations to the rooftop routes.

At the two Arbor junctions, the road and rail approaches enter short covered **Rootway galleries** at the tree-ring plazas. Repeating bronze ribs, riveted side bands, overhead twin rails, and crystal-set portal crests blend early industrial engineering with the living canopy. Each rib follows the arch cross-section and leaves the road envelope open; the gallery also uses matching static collision geometry so players can pass through. Sapphires, opals, and amber gems are embedded along both walls and gain emissive color at night. The gallery frames the approach into the root-ring plaza; it does not hollow out the tree trunk. Scattered tall trees are not generated within 26 m of a road deck or plaza (`District.nearRoad`, used by `Scatter.generate`), so no trunk or crown pokes through a road; candidate IDs are unchanged, so saved removals still apply.

This is the first transit corridor, not yet a train simulation. City growth is planned as contiguous rings around the canopy core: the skyscraper downtown and public venues, then walkable residential neighborhoods, productive farms, and finally the wilds boundary. The next playable city slice should add one downtown venue block (mall arcade and music stage), an accessible maintenance tunnel linking it to a subway platform, and a high-speed rail terminal. Subsequent routes can join other Earth cities and the spaceport once those destinations exist. Keep each station and venue as a reusable procedural module with explicit collision and fast-travel identity.

## Canopy parkour

Each of the three market towers now has a seeded vertical traversal route built from reusable city pieces: a ground ladder, a lower patio, a rising ramp, a narrow mini-bridge, an upper ladder, and a short jump gap between landing patios. Cyan crossbars mark grapple anchors. They use the existing grapple action, which can zip to a nearby anchor or swing from a long line; jump, sprint, wall-climb and mantle fill the gaps between routes. The ladders and patios share the district's static collision mesh, so they support both walking and grappling.

Approximate world positions (X, Z); the seed shifts tower positions slightly:

| Plaza | Location | X, Z |
| --- | --- | --- |
| 0 | Test Arbor entrance tower | −38, 22 |
| 1 | Southern market tower | 140, −80 |
| 2 | Narrow Arbor junction | 240, 90 |
| 3 | Northern market tower | 0, 340 |
| 4 | Spreading Arbor junction | −250, 300 |
| 5 | Western market tower | −240, 80 |

## Generation and validation

`procedural/District.zig` owns district generator v8, its layout graph, Detroit building styles, and shared geometry descriptions. `procedural/DetroitRiverfront.zig` builds the promenade, ferry terminal, Belle Isle park fixtures, pedestrian approaches, and two cross-river road bridges. `procedural/Hydrology.zig` and streamed chunks widen only Detroit's local river and leave Belle Isle terrain above the water. `procedural/CanopyCourse.zig` builds the ladder, patio, ramp, bridge, and grapple-anchor modules used at the market towers. `procedural/Metro.zig` builds the elevated rail loop and station decks; `procedural/Rootway.zig` builds ribbed, gem-set transit galleries at the Arbor-ring approaches. The seed varies the template and terrain-relative elevation. Generation validates before the catalog installs a render mesh or the Sandbox installs collision. Player-built canopy bridges still go through the existing checks before allocation or mutation.

The standard 14 m deck contains two 3.5 m traffic lanes, two 3 m walkways, and two 0.5 m rail strips. Roads have solid decks, rails and end pylons, with decorative vine cables and hangers. Plazas overlap road ends to avoid gaps. Tower bodies reach the ground; floor bands and market bays distinguish their roofs. Trunk plazas are segmented rings connected to their adjacent junctions.

Validation checks graph reachability, endpoint IDs, finite bounded positions, span length, grades of at most **6%**, trunk and plaza envelopes, road crossings, junction approach angles, trunk spurs, and reserved market bays. Terrain clearance is sampled every 4 m at the road center and both edges, requiring 6 m beneath the deck. The fixed legacy test-Arbor entrance still has its original 10% descending bridge and spiral ramp; it is outside the new district road rules.

The generated district uses one resident mesh and one static collider, including the fixed parkour course, Metro loop, Rootway galleries, Detroit skyline, and riverfront. Player bridges use existing block instances and their own mesh colliders. Save loading validates the graph and stages allocating collision work before replacing live state; a failed allocation preserves the current session. The district generator is **8** (v2 added styled bridges and skyline; v3 added glass bays and observatory crowns; v4 adds Metro rails and stations; v5 adds the Rootway galleries; v6 adds Detroit Gothic and industrial forms; v7 adds the wide river, Belle Isle and Windsor crossings; v8 corrects gallery ribs to leave the road passage open). The save format is **24**; district-generator-3 through -7 worlds migrate while retaining stable plaza and player-bridge endpoints and removals.

## Current limits

This is one fixed-topology district with seeded variation, not a city-wide layout search or streaming district system. Up to four added spans can be stored; actual valid choices depend on clearance and existing bridges. Crossings are conservatively rejected even when an overpass might be possible. Clearance validation covers the generated layout, not a swept volume against every movable player prop. Cable meshes do not simulate suspension. Traffic is three cars and eight pedestrians, with plaza priority and yielding but no traffic lights. The metro rails are static infrastructure and fast travel; no train simulation exists yet. Downtown/suburb/farm zoning, subway tunnels, maintenance spaces, venue interiors, and a high-speed rail connection to a built spaceport remain planned. Runtime tree growth, player-authored woody grafts, and district residency eviction remain future work.

Acceptance includes continuous walking and machine-powered driving around the complete road loop, exiting onto a deck, elevated rover placement, two-click bridge construction/removal, walking a new bridge, bridge save/load, and rejection without mutation on invalid input or allocation failure. See [validation](validation.md) for measured results.
