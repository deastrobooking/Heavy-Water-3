# Character and environment visual pass

**Status:** active visual pass, 2026-10-05. The human Ranger anchor and first armor-tier pass are implemented. Next is a clean character presentation review, then the Frontier environment materials and composition pass.

## Design verdict

The project has unusually broad visual systems already: procedural humans and Wildkin, layered clothing and armor, Arbors, a six-plaza city, mountains, rivers, waterfalls, vehicles, Hive nests, and Scalari ships. Their technical range is ahead of their visual finish. The current captures still read as an engine prototype because key surfaces look like debug materials, procedural shapes repeat without a clear focal hierarchy, and character gear reads as rounded blocks placed over a narrow mannequin.

“Serious” should mean clear intent, credible construction, and expressive characters. It does not mean grimdark. Keep the world's warmth, wonder, and all-ages heroism, while making its people and places feel lived in and designed for a purpose.

## What the current captures show

Reviewed the ReleaseSafe Metal captures at 2560×1600: `-Dshowcase=17` (armor lineup), `-Dshowcase=7` (district overview), and `-Dcharacter-showcase=4` (feminine Ranger in the creator).

- **Human proportions and faces:** the human Ranger used 7.5 head heights and read as realistic and uncanny (see the 2026-10-11 stylization pass below: now 5.9 to 6.5 per face style). In the capture the eyes and small lower-face features read as a dark, simplified mask, while the long, thin neck makes the head feel detached. Masculine/feminine identity is expressed heavily through torso and bust proportions. Keep the current adult ratio as the baseline and improve the face, neck-to-shoulder transition, pose, and fitted silhouette.
- **Armor and clothing:** the lineup has useful distinct suit names, but broad rounded plates and large visor shells dominate the body. The undersuit, fabric, hard plates, and powered accents lack a strong material hierarchy; bright white armor loses surface detail in daylight and neon accents compete with the face. Joint articulation and fastening logic are hard to read at a glance.
- **Character presentation:** the creator preview gives most of the screen to a dense control panel, leaving the actual head and suit small. The stationary front pose does not help judge silhouette, facial expression, or equipment fit. Art review needs clean front, side, and three-quarter views without gameplay clutter.
- **Ground and atmosphere:** the overview's broad turquoise surface and obvious repeating checker read as a placeholder floor. The current two-texel checker is blended into every surface. Heavy blue-green haze also erases city and terrain contrast before the scene gains useful depth.
- **City and transport:** tower silhouettes have promise, but glass extrusions repeat, while the road loop dominates the overview as a broad unsupported ribbon. Roads, bridges, and ramps need visible supports, lanes, edge protection, transitions, and a relationship to the inhabited districts.
- **Arbors and foliage:** the giant trunks provide a memorable scale anchor, but the overview shows small canopy shapes detached from the branch mass. Keep diagnosing placement and LOD in captures while shaping the target around broad connected crown clusters, visible load-bearing limbs, and bridge approaches that meet living anchors.
- **World composition:** the panorama has attractive mountain silhouettes and the roads, trees, and river systems establish a strong science-fantasy premise. They do not yet compose into a strong foreground, middle distance, and landmark sequence. The same mint ground, pale sky, and cyan glass flatten distinct regions into one color field.

These findings are visual-review observations, not claims that the underlying world or character systems are missing. Most of the proposed work should reuse their generators, meshes, profiles, and renderer.

## Art direction to hold

Build a grounded, hopeful science-fantasy look: panoramic natural forms, deliberate contour drawing, broad readable color shapes, and engineered details that make physical sense. Keep the three-dimensional forms and painterly cel lighting. Use quiet expanses to sell scale, then concentrate detail at faces, machinery, and landmarks. Avoid literal imitation of any one artist.

- **Humans:** anime action proportions (about 6 heads, large eyes, short neck, big hands and feet; superseded the 7.5-head baseline on 2026-10-11); make faces readable and masculine/feminine variation restrained; fit practical field clothing and armor to the body.
- **Wildkin:** retain their bold animal silhouettes and warmth. Their exaggeration is a deliberate species design, not a human proportion template.
- **Frontier materials:** bark and mineral earth, charcoal or deep navy technical fabric, warm titanium/ceramic plates, oxidized copper, and a single controlled lumen accent per suit.
- **Hive and Scalari:** separate the modified-insect Hive from its reptilian founders. Hive gear should feel grown, chitinous, and utilitarian. Scalari ships and armor can use obsidian/black with lacquered red and one intentional violet, green, or amber accent; avoid putting the whole palette on one asset.
- **Environment:** give each shot one primary landmark and a readable route to it. Keep terrain and foliage variation low contrast at distance and richer near the player. Roads and buildings need believable contact, structure, and scale.
- **Canopy city:** treat the crown as a layered habitat, with visible branch structure beneath connected foliage, terraces and small parkour routes, and bridges that mix grown fibers with engineered joints. Lumen markers and grapple rings should guide movement without turning the treetops into neon infrastructure.
- **Rendering:** retain the existing warm/cool toon ramp and selective silhouette outline. Use vertex color or subtle low-frequency surface variation to replace the checker; do not add a texture stack, bloom, or more outlines before the materials and values read correctly.

## Work order

### 1. Establish a character anchor

Use one masculine and one feminine human Ranger with open faces and the same base rig. The 7.5-head proportion was the control and is now replaced by the stylized preset table. Refine the skull, jaw, cheek, nose bridge, eyelids/brows, and ear placement so expression survives at creator and gameplay distances. Improve the neck-to-shoulder transition and use posture and fitted clothing alongside facial structure for identity; reduce the reliance on dark eye patches and bust volume as the primary feminine cue. Keep variation in skin, hair, and presentation choices.

Acceptance: front, side, and three-quarter captures show the same recognizable adult character; face landmarks remain readable at gameplay scale; both presentations share credible anatomy; the neutral and locomotion poses do not detach the head or distort the face.

### 2. Rebuild one complete suit before adding options

Take the field jacket through undersuit, boots, gloves, harness, pouches, hard plates, and helmet. Make the exo rig, hardsuit, and vanguard read as three different protection levels by silhouette and coverage, not by enlarging the same rounded shapes. Fit visors to the skull and make closure, joints, fasteners, seams, and material changes visible. Choose a restrained base palette and reserve the accent for sensors, life-support status, or team identity.

Acceptance: the silhouette reads at 20–30 m; gear stays attached during walk, run, jump, aim, saber, and flight poses; white and dark variants retain surface detail under day and dusk lighting; the face remains the first focal point when unhelmeted.

### 3. Fix the environment's material baseline

Replace the 2×2 checker surface treatment with subtle ground variation that supports the existing biome colors. Review terrain, road, water, bark, glass, metal, fabric, and chitin as separate material families. Tune haze so it preserves aerial depth without washing the first kilometer into one pale color. Investigate the detached-looking Arbor canopy pieces and correct their geometry, placement, or LOD as appropriate.

Acceptance: no broad surface reads as a debug grid; nearby ground has detail without visual noise; distant terrain keeps a clear silhouette; tree crowns connect to the branch mass at gameplay and overview distances; river and snow remain distinct from the land around them. Canopy routes show believable attachment, support, and safe player-scale landings.

### 4. Make one district composition feel intentional

Choose one road-to-plaza-to-tower route as the authored benchmark. Refine a compact set of tower forms, bridge supports, roadway barriers/markings, signs, lamps, and market details. Give the large raceway loop visible structure and a clear connection to the city, or reduce its visual dominance in the overview. Re-compose the camera around the Arbor, one tower, the route, and the mountain/water backdrop instead of exposing every system in one shot.

Acceptance: a street-level image reads as an inhabited place; an overview has one landmark and distinct near/middle/far layers; highways and bridges appear supported and safe to traverse; repeated procedural buildings vary in silhouette without losing district identity.

### 5. Lock the review gates and then extend to other factions

Create repeatable captures for character front/side/three-quarter, armor lineup, street level, district overview, river/falls, mountain skyline, Hive nest, and Scalari fleet. Review each in daylight and dusk, then in four-player split-screen. Extend the approved material, proportion, and faction rules to Wildkin, Hive units, vehicles, and Scalari characters/ships only after the human and Frontier anchors pass.

Acceptance: reviewers can identify focal subject, faction, and material purpose in a two-second read; no major silhouette or environment landmark is lost in split-screen; representative scenes keep the current renderer/streaming performance budgets.

## First implementation slice

The first implementation slice changed the human character anchor while preserving the adult proportion benchmark and profile/save format. It refines open-face features and head/neck attachment, grounds the field-jacket details with a fitted harness, and fits the visor and sealed shell to head landmarks. The next increment differentiated the three protection levels described in work order 2.

Reproducible character and environment review captures:

```sh
MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dcapture-frame=120 -Dcharacter-showcase=4 -Daudio=false -Doptimize=ReleaseSafe
MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dcapture-frame=120 -Dshowcase=17 -Daudio=false -Doptimize=ReleaseSafe
MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dcapture-frame=120 -Dshowcase=7 -Daudio=false -Doptimize=ReleaseSafe
```

The current renderer's performance and platform constraints remain binding. Art direction should improve color, geometry, and composition before adding expensive per-pixel effects or high-frequency assets.

## Implementation progress

The 2026-10-11 night flora increment ties foliage flecks and ground-level glow patches to the shared sky night factor. Leaves and grass tips carry sparse, gently pulsing mint-cyan emissive flecks; level grassy terrain gets scattered small light pools, while steep rock and snow remain dark. The shader uses the existing emissive material path and no extra texture or draw. A ReleaseSafe Metal API Validation capture of `-Dshowcase=8` was inspected at night; the glows read against the dark city without washing out the scene. Validation details are in [validation](../validation.md#nighttime-bioluminescent-flora).

The 2026-10-11 energy weapon pass adds a fabricable energy net for airborne Hive units. A fast lattice projectile damages every flyer in its wide path and snares surviving flyers for 1.45 seconds, making them easier to finish with normal weapons. The held saber is now a curved, oversized segmented plasma greatblade with a pale hot spine; combat reach was extended to match, and slash afterimages are wider, longer, and use the selected weapon accent. Metal API Validation captured and reviewed the combat scene. The broad silhouette matches the requested scale; close-up blade contour and physical controller feel remain open review items. Details are in [validation](../validation.md#energy-net-and-greatblade).

The 2026-10-11 Wildkin and weapon pass adds family-wide anatomy details through shared, joint-bound helpers: mammals gain paws, small claws and a reduced chest bib; reptiles and amphibians gain short belly bands and toe claws; birds gain a compact feather-colored bib and talons; insects and arachnids gain a smaller thorax and shoulder/forearm plates. Held weapon parts now select the existing block, gem, or spike meshes, giving saber blades and long gun barrels tapered profiles while retaining block-built grips and rails. `-Dshowcase=48` and `-Dshowcase=37` were captured on Metal with API validation enabled. The captures compile and render cleanly; the Wildkin lineup faces away from the camera and shares a visually busy city backdrop, so species faces and material separation still need a clean art-review stage. At that time the saber still read as a simple energy bar; the newer greatblade pass above replaces it. No balance or damage values changed in that earlier pass.

The 2026-10-11 anime stylization pass makes the human hero read as stylized action (Dragon Ball Z, Mega Man, Gundam) rather than realistic. The head is now a keyframed, data-driven profile (`HeadSpec`): fuller cranium, soft chin, shorter neck (0.18 to 0.28 body units, was 0.36), 5.9 to 6.5 heads tall (was 7.5), larger hands and feet. Eyes are about 50 percent larger (size 0.20 to 0.22, was 0.13 to 0.15), brows are tapered tilted strokes with a ridge on the mesh, the 0.05H nose bump is a 0.014H tip with a shadow mark, and a sixth face style, `hero`, adds a square jaw, heavy angled brows and upswept eyes. The five older styles were reworked on the same table. Captures: classic, hero, alien and soft on Metal at creator distance. Open: the creator camera is far from the face, so brows and mouth are only a few pixels; a close face stage is still needed, and hair and helmets still need a fit pass against the larger head.

The first character slice is implemented and reviewed against ReleaseSafe Metal captures:

- Human eye decals now use less oversized irises, warmer linework, and softer brows and mouth color. The generated face has shallow orbital, cheek, brow, bridge, and nose-tip relief; the neck is slightly fuller and joins closer to the skull. Human Rangers remain 7.5 heads tall, and feminine presentation now relies less on chest volume.
- Field-jacket chest details are body-scaled chamfered fabric panels fitted against the generated outer shell, joined by a diagonal load-bearing strap, and checked for surface clearance and palette alignment. The paired floating ellipsoids that read as chest pods are removed.
- Visor and sealed helmet dimensions now use head landmarks. The visor is an eye band fitted within the skull width; the sealed shell uses the same head unit instead of full body height.
- Profile fields and save compatibility are unchanged. `python3 tools/zig.py build test` passes, and `-Dcharacter-showcase=4`, `-Dshowcase=16`, and `-Dshowcase=17` were captured with Metal validation enabled.

The second character increment is implemented: the exo rig leaves the torso and thighs in the undersuit, the hardsuit uses the standard armor span, and the vanguard extends shoulder, forearm, thigh, and shin coverage. Hard plates sit closer to the body with smaller domes, more restrained tier-specific metal colors, and articulated breaks. The armor lineup now uses one neutral under-suit color, open faces, and a closer camera so protection coverage is the main comparison. `coverage_extent` belongs to the generated garment description; player profile and save fields are unchanged. ReleaseSafe Metal captures for `-Dshowcase=16` and `17` show the tiers at useful scale.

The visual review gate remains open: the cuirass front still reads as a broad, smooth shell, and the close-up stage is cluttered by nearby city props. Refine torso seams so they follow the cuirass deformation, then add clean front, side, and three-quarter character views. The creator still gives little screen area to the head. The Frontier material and district work follows those character anchors; the checker ground, heavy haze, tree-crown attachment, and over-dominant raceway remain visible in the environment capture.

The October 11 character increment adds warm, broken comb-strand glints to the Ranger's baked hair colors. This keeps the highlights on the GPU-skinned game path, which has no per-character UV texture. The highlight follows the generated clump UVs and front-facing normals; the adult human proportions and existing face/eye construction stay intact. Review the full face and cel-light balance in a clean close-up before changing the shared scene ramp.

The 2026-10-11 canopy increment replaces four-sided leaf crystals on generated Arbors with larger, irregular eight-facet foliage clusters and a two-sided color treatment. It is a geometry direction pass only: no capture has yet confirmed that the clusters visually join the branch mass or retain a good distant silhouette. The market-tower parkour course adds ladders, patios, ramps, mini-bridges, jump gaps, and grapple markers to the district geometry; material balance, collision feel, and route readability still need hands-on review.

The 2026-10-11 jeweled armor increment adds three unlockable plate silhouettes—Gem Aegis, Starforge and Deep Prism—built to the existing masculine and feminine body proportions. Their chest settings use hand-built radial gem facets; the creator can select lumen, ruby, sapphire, emerald, amethyst or citrine and choose brilliant, star or teardrop cuts. Capture `-Dshowcase=61` with Metal API Validation confirms the creator rows and the red ruby setting at game scale. The current shot is still partially covered by the creator panel and shows one armor clearly; a clean lineup and close review of all three silhouettes remain open.
