# Space habitat network: Project Helios

**Status:** future worldbuilding and gameplay plan, plus an early procedural art-review model (`-Dshowcase=66`). The rotating cylinder and Mother are renderable, but there is no playable orbital region, construction interaction, validated vehicle scale, or engineering simulation. The current MVP remains Earth's first city liberation loop; this visual prototype does not move orbital gameplay ahead of it.

Project Helios adapts the supplied megastructure proposal into a staged, evidence-led direction for Heavy Water. The artistic ambition is a growing network of industrial spaceports, robotic foundries, rotating neighborhoods, and green interior landscapes. Engineering claims are kept separate from speculative game technology.

## Science boundary

The reference concept is a rotating cylinder, in the family of the 1975 NASA/Stanford space-settlement study. Rotation can provide *apparent* gravity at the inside surface; the habitat does not have a planet's mass or natural gravity. For radius \(R\), angular speed \(\omega\), and target surface acceleration \(a\):

\[ a=\omega^2R, \qquad T=2\pi\sqrt{R/a} \]

This is established mechanics. It does not establish that a structure of a given size is safe, affordable, or comfortable to live in.

| Illustrative radius at 1 g | Rotation | Rim speed | What the number means |
| --- | ---: | ---: | --- |
| 500 m | 1.34 rpm | 70 m/s | Small reference habitat geometry; human comfort and buildability remain unproven |
| 5 km | 0.42 rpm | 221 m/s | Large speculative cylinder |
| 20 km | 0.21 rpm | 443 m/s | Helios-20 reference; 100 km length gives about 12,566 km² of inner cylindrical surface |

The surface-area figure is circumference times length. It excludes end structures and says nothing about how much land is actually usable. Rotation, floor curvature, gravity gradients, Coriolis effects, vibration, docking and human adaptation all matter. Human-factors limits for long-duration artificial gravity are not settled by the kinematic equation.

The attached Helios memo's material strengths, pressure, shield areal density, total shield mass, and 20 km radius are **scenario assumptions**, not qualified design values. Its thin-shell relationships are useful for early sensitivity studies, but omit or simplify joints, buckling, fatigue, defects, impact damage, dynamic modes, pressure containment, construction tolerances and repair. Do not present its mass estimates as a verified bill of materials.

### Rules for science-grounded worldbuilding

- **Start with resource surveys.** A body containing water or useful elements is not automatically a mine. Concentration, depth, local form, extraction energy, equipment life, transport delta-v, processing yields, and contamination constraints determine usefulness. NASA describes lunar, Martian and asteroid volatiles as incompletely characterized; its analog demonstrations are not long-duration industrial operations.
- **Treat shielding as a dose problem.** Galactic cosmic rays, solar particle events and local trapped radiation have different spectra. Material and thickness interact with those particles and can produce secondary radiation. No fixed blanket thickness guarantees safety everywhere; give habitats a modeled storm shelter and require location- and mission-specific dose analysis before setting a shield mass.
- **Separate the pressure vessel from the shield.** A pressure boundary, load-bearing rotating structure, thermal control, impact protection and radiation shielding have different jobs. Heavy shielding on a rotating structure changes its loads; a stationary shield around a rotating habitat needs its own supported geometry and clearance. Neither arrangement is a free layer added after the design.
- **Budget energy and heat together.** Solar flux falls with the inverse square of distance from the Sun. Solar arrays and concentrators suit many inner-system uses; reliable outer-system industry needs a separately justified power source. Almost all consumed energy becomes heat that must be radiated away. Large radiators, coolant loops, storage, shadowing and maintenance belong in every industrial outpost design.
- **Use local feedstock where it closes a real logistics loop.** Regolith may supply construction aggregate, oxygen-bearing minerals, glass precursors and metals after energy-intensive processing; water ice can supply water and, after electrolysis, oxygen and hydrogen if a deposit is accessible. Carbon, nitrogen, crop nutrients, high-performance fibers, electronics and precision parts may remain imported for a long time. A laboratory material strength is not a large-structure allowable.
- **Keep ecosystems and people in the design.** A closed, self-sufficient biosphere over generations is not demonstrated. Begin with monitored life-support loops, redundant stores, food reserves, quarantine, medical capacity, repair access and independent refuge volumes. Grow forests and parks only inside commissioned, pressure-safe districts with water, light and nutrient budgets.
- **Respect orbital mechanics and planetary protection.** Interplanetary cargo needs trajectories, propulsion, transfer time, navigation, collision avoidance and stationkeeping; orbital depots do not remove those costs. Prospecting and extraction should preserve science targets, disclose operations, avoid harmful interference and mitigate debris.

## Helios reference architecture

Keep **Helios-20** as an aspirational comparison case, not the first habitat or a construction promise: a 20 km radius, 100 km long rotating cylinder at 1 g. Its kinematics imply about 0.21 rpm and 443 m/s at the rim. Its structure, radiation environment, thermal system, ecological closure, assembly sequence and economics are open research problems.

The baseline development strategy is a **federation of independently isolatable modules**, with several modest habitats and service stations before any one enormous cylinder. A network lets construction be incremental and failures local. It also avoids treating a single pressure shell or biosphere as the only home for a population.

Keep rotating and nonrotating functions visibly distinct:

- **Service hub:** docking, cargo receipt, zero-g workshops, communications, navigation, storage and emergency vehicles.
- **Power and thermal yard:** generation and storage sized for the local orbit, coolant distribution, radiator panels and replaceable service units.
- **Resource yard:** prospecting instruments, mining robots, sample handling, assay lab, excavation, sorting and small processing demonstrations.
- **Habitation modules:** pressure-rated, compartmentalized rooms and greenhouses. Early habitats may be nonrotating and accept microgravity operations; later rotating modules test artificial gravity as a system.
- **Shielding and refuge:** water and other hydrogen-rich stores where practical, local storm shelters, standoff protection, impact sensing and repair access, validated against modeled radiation and debris conditions.
- **Industrial assembly:** trusses, tanks, robot arms, printers, welders, inspection drones, cargo tugs and inventory yards. Printing is one manufacturing process among many, not a universal replacement for refining, joining, inspection and repair.

The popular visual image of one enormous cylinder stays available for the game's distant future. The near-term design language should show construction in cells: exposed truss first, pressure module and services next, shield and radiator added with independent access, then greenhouse or civic landscape after commissioning.

### The Mother and the first visual prototype

In this setting, **Rand Corporation** is a fictional mega-corporation whose roaming factory-habitat is called **the Mother**. It carries a lived-in rotating drum, a separate nonrotating access spine, cargo cassettes, assembly gantries, collector booms, radiators and multiple drive bells. Its story role is to survey, mine, fabricate and seed smaller habitats, while its own people live aboard during long journeys. Treat it as a mobile industrial city and shipyard, not a magic printer: feedstock, power, heat rejection, repair, crew safety and resupply stay visible constraints. Its governance and relationship to the Solar Compact belong in the campaign story, not a claim that one company should own settlement rights.

The first model is a deliberately compressed procedural art asset, not a scale drawing. `src/vehicle/HeliosMeshes.zig` produces a standalone shielded habitat cylinder and the larger Mother from shared pressure-drum components, replaceable outer panels, exposed hoops, end spokes, access spines and separate emissive service geometry. The Mother adds factory gantries, cargo pods, collector/radiator hardware and four aft drive bells. The model is available in the asset catalog and in `-Dshowcase=66` for visual review. Dimensions, rotation, hull thickness, shielding, power output and propulsion are art choices here and must not be read as engineering specifications. No habitable interior, rotation animation, docking, flight controls, or construction loop is implemented yet.

Keep the standalone habitat and Mother related but visually distinct: the habitat is a compact settlement with readable repeating neighborhood cells; the Mother is longer, asymmetrical around its nonrotating service spine, and visibly carries work equipment. Future iterations should make the cylinder's inhabited inner surface legible through cutaway/interior views before adding more exterior detail. Construction gameplay should assemble independent pressure and service modules and commission them through the staged gates below.

## Staged expansion, gated by evidence

Progress by capabilities demonstrated, not by calendar dates. Each gate should produce a playable slice and an engineering reason to unlock the next scale.

1. **Cislunar service outpost.** Establish a small docking and repair station with communications, power, storage and a cargo route. The player clears a Scalari raid, repairs a radiator or relay, and brings a damaged tug home. This is the first station-building slice after the Earth loop.
2. **Survey and prospect.** Deploy mapping and sampling robots at a selected lunar site or near-Earth object. The mission identifies a specific deposit, returns assay data and records uncertainty. No building recipe should assume an unverified reserve.
3. **Small-scale resource demonstration.** Extract and process a bounded batch of a chosen resource. Track energy, consumables, yield, contamination and equipment wear. A failed assay or low-yield site redirects the colony plan instead of silently yielding unlimited ore.
4. **Robotic construction yard.** Use refined local feedstock for carefully chosen noncritical structures such as berms, pads, shielding mass or simple panels, while importing precision seals, electronics and high-performance components. Inspect and pressure-test crewed modules before opening them.
5. **Rotating habitat demonstrator.** Assemble a small isolated ring/cylinder or tethered test pair, with nonrotating access and deliberate spin-up/spin-down procedures. Validate structural margins, balance, disturbance loads, access, evacuation, human-factors limits and maintenance before increasing radius or population.
6. **Network of settlements.** Link independent habitats, depots, yards and surface camps by scheduled cargo routes. Add local governance, shared safety standards, rescue agreements and resource-use rules. Expand from cislunar space toward surveyed near-Earth objects, then the belt and outer system where their local energy and logistics justify it.
7. **Megastructure research decision.** Compare Helios-20 with many smaller cylinders using full mass, energy, transport, thermal, radiation, risk, ecological and lifecycle models. Proceed only if the smaller-scale record supports the assumptions. A cluster remains a valid answer; the biggest single structure is not the objective.

These stages are a design sequence, not a prediction that the technology or economy will exist on a particular date.

## Solar-system placement

Treat the eight planets and named moons as campaign destinations and local flight regions, not as commitments to build a city on every body. Start with destinations that teach the infrastructure chain. The named locations below are candidate story roles; siting a real facility requires trajectory, radiation, thermal, communications, resource and planetary-protection analysis.

| Region | Early game role | Constraints that should shape the build |
| --- | --- | --- |
| Earth orbit / Earth–Moon space | First cargo hub, repair yard, lunar communications and prospecting | Launch mass, traffic, debris and safe return; lunar resource quality is site-specific |
| Moon | Surface survey, small extraction trials, construction-material demonstrations | Abrasive dust, extreme thermal cycles, low gravity, difficult polar lighting and volatile uncertainty |
| Near-Earth objects | Robotic reconnaissance and carefully selected sample/resource missions | Object-specific composition and orbit; rotation, anchoring, dust/ejecta and transport must be solved |
| Mars system | Regional science, surface support and eventually local resource loops | Long resupply, radiation, dust, low pressure; Martian atmospheric CO₂ processing does not by itself create a self-sufficient colony |
| Main asteroid belt / Ceres | Later distributed mining, refining and industrial depots if economics close | Long routes, sparse infrastructure, varied feedstock, power and thermal management |
| Venus and Mercury vicinity | Specialized orbital industry; Venus cloud habitats as a speculative settlement niche | Severe thermal and chemical environments, atmosphere handling, corrosion, power and heat rejection |
| Jupiter system | Remote science and selected logistics, with careful radiation-aware siting | Radiation environment varies strongly by orbit; do not place a crewed settlement in a hazardous orbit for convenience |
| Saturn system / Titan | Cold-region chemistry, science and remote logistics; Gaia remains a fictional major habitat setting | Weak sunlight, long logistics chain, cryogenic operations and protection of scientifically valuable environments |
| Uranus, Neptune and Kuiper Belt | Far-future robotic science and small, high-autonomy outposts | Very weak solar input, long communication delays, sparse repair and resupply |

Solar power and fission rely on known physical processes, but neither implies a ready-to-deploy industrial power plant for every orbit; each site still needs a concrete system and reliability case. Fusion remains a future technology assumption here. The existing **0.5c fusion-pulse drive** remains an explicit fictional fast-travel convention, not a real propulsion prediction. Use campaign fast travel between bounded regions and local flight around a destination; do not imply that the game simulates relativistic travel or real orbital transfers.

### Fit with Gaia and terraforming

Keep Gaia's current Earth-radius globe, Saturn-space placement and mile-high geodesic enclosure as **high science-fiction**. It is a setting-scale artificial planet, not the direct engineering consequence of a rotating habitat proposal. The more science-grounded habitat path is a collection of modular pressure volumes and rotating settlements. Gaia can be the dramatic exception that inspires the Compact's habitat industry without being treated as proven technology.

Terraforming remains staged regional environmental engineering. The first Venus settlement is a floating pressure habitat, not a terraformed surface. For Mars and other bodies, local sealed habitats and infrastructure come before claims of planet-wide climate control. Any later terraforming arc must account for energy, volatile inventories, atmospheric escape/retention, ecological uncertainty, timescale and the consent of residents and indigenous life if discovered.

## Player-facing construction loop

Use one reusable, modular objective chain across colonies:

1. **Survey:** place scanners, read terrain/orbit hazards, scan a deposit and compare measured data with uncertain estimates.
2. **Plan:** choose a site and a bounded build cell; check power, cargo, anchoring, thermal view, pressure boundary, route clearance and environmental restrictions.
3. **Supply:** mine, process, manufacture or import named component batches. Cargo has mass and provenance at mission scale, but early gameplay can use transparent resource units instead of pretending to solve industrial economics.
4. **Assemble:** assign specialized survey, haul, print, weld, seal, inspection and repair bots. Players can reroute power/materials, defend a crew, operate equipment or recover a disabled robot.
5. **Commission:** inspect joints, verify pressure and life support, test power and cooling, validate shielding, then open the completed safe volume. Failed checks leave the module isolated until repaired.
6. **Operate and govern:** maintain the station, choose who receives scarce power and materials, preserve rescue capacity, publish resource records and resolve Compact votes about expansion or protected regions.

Reusable build families: docking collar, cargo truss, power/storage, radiator, communications/navigation, workshop, assay lab, mine/sorter, refinery, propellant tank, pressure room, storm shelter, greenhouse, rotating ring segment, spin interface, inspection/repair bay and waste-recovery plant. Make each module readable through its purpose and service connections; do not allow a single generic block to satisfy every colony need.

The construction crew should stay a small deterministic team in the active region. Its worker roles can be enabled, upgraded, rerouted or rescued; there is no need to simulate millions of individual robots. Successful construction adds a traversable service or habitat module to the local scene and a documented capability to the campaign state.

## Science and gameplay acceptance gates

- A station module cannot be commissioned while required power, thermal rejection, pressure checks, shielding analysis, or rescue capacity are missing.
- Resource estimates include uncertainty; assay results can invalidate a site or reduce its yield without corrupting saved world state.
- A mining recipe states what it produces, what energy/consumables it uses, and where the source material came from.
- A habitat can be isolated into safe compartments; damage to one module does not automatically destroy the network.
- Rotating-habitat gameplay separates rotating and nonrotating access, accounts for balance and spin state, and keeps the artificial-gravity display consistent with \(a=\omega^2R\).
- Construction and resource rights are visible civic decisions. Protected science sites, debris controls, transparent claims and emergency rescue access are part of the Compact's law.
- The first real playable slice is one local station loop with a bounded build cell, real interactions, save round-trip and Metal visual validation. Do not gate the Earth MVP on it.

## Sources and confidence

- **NASA SP-413**, [*Space Settlements: A Design Study*](https://ntrs.nasa.gov/citations/19770014162), published in 1977: historical design study and systems thinking, not a current certified design.
- NASA, [In-Situ Resource Utilization overview](https://www.nasa.gov/overview-in-situ-resource-utilization/): describes resource use as a technology-development area and explicitly notes unresolved questions about volatile location, form, concentration and extraction.
- NASA, [OLTARIS radiation assessment tool](https://oltaris.larc.nasa.gov/): models radiation effects across selectable environments, materials, geometries and biological/electronic responses; supports the need for tailored analysis rather than a single shield-thickness rule.
- NASA, [Moon to Mars Architecture](https://www.nasa.gov/moontomarsarchitecture-components/): stages capabilities and treats robotics, communications, habitation, ISRU, infrastructure, logistics, power and transportation as coupled sub-architectures.
- NASA, [Artemis Accords](https://www.nasa.gov/artemis-accords/): space resources are framed alongside peaceful use, coordination, scientific data, heritage, deconfliction and debris mitigation.
- NASA/TM-2005-213559, [artificial-gravity design discussion](https://ntrs.nasa.gov/citations/20050160960): emphasizes that health requirements and acceptable rotation/radius combinations remain uncertain and interrelated.

The numerical rotation values in this plan are calculations from the stated idealized equation. Resource inventories, industrial yield, structural strength, long-term biological closure, costs and construction schedules remain unknown until a specific site and design are studied.
