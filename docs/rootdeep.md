# Rootdeep shrines

The Rootdeep is the forest floor under the canopy city. Two shrines stand there: seed vaults built entirely from the machine kit. Every shrine is generated from the world seed, and a solver proves it can be solved before it is placed.

## Play a shrine

1. Look for two long, moss-roofed stone halls on the forest floor, 110–260 m from spawn. The smoke log and `Sandbox.shrines` give their exact positions for a seed. Walk in through the open doorway.
2. Each hall is a chain of rooms, three or four of them. A sliding door between rooms opens when its logic is satisfied. Each door reads one or two conditions:
   - **Latches**, toggled by red buttons on the left walls. Pressing again toggles back.
   - **Weight plates** on the right side, pressed only by a **crate** resting on them. Standing on a plate does nothing.
   - A condition may be inverted, so some doors are open until a latch is set.
3. Carry crates with the hands tool: click to lift, click to drop. A crate held high is carried over your head.
4. The last room holds the **seed vault**, a gold button on the back wall. Opening it lights the seed lamp and adds the shrine's reward blueprint to your build palette: **rootsong_hearth** (shrine 0) or **rootsong_call** (shrine 1). Both are Rootsong designs; see [Arbor genomes and sap](arbors.md#rootsong).
5. Stuck? The blue **reset** button beside the entrance returns the shrine's crates to their starting places and resets every latch and door. Crates you carried out of the shrine stay outside.

Shrines belong to the world. The build tool cannot remove or capture them or place anything inside them. The wire tool cannot rewire them, and their channels cannot be retuned. Free flight (V) is a noclip debug mode and can still bypass walls.

## Generation and verification

`procedural/Shrine.zig`, shrine generator v1:

- **Candidates:** a seeded candidate picks 3–4 rooms, 1–3 latches with their buttons, 0–2 plates each with a crate, and one or two terms per door. A term is a latch or plate, possibly inverted.
- **Solver:** a breadth-first search over room, latch bits and each crate's place. A crate is on a room floor, on a plate, or carried; the whole state fits in 2,048 codes. The actions are press, pick up, drop on the floor, drop on a plate, move through an open door, and open the vault. A carried crate does not press a plate.
- **Acceptance:** a candidate is accepted only if the solver reaches the vault, the first door starts shut, every latch and plate is used by some door, the room layout fits, and the shortest solution is at least 6 actions. Of the first six accepted candidates, the one with the longest shortest solution is built. If no candidate passes in 400 attempts, a fixed verified shrine is used; this happened for about 1% of seeds.
- **Witness:** the shortest plan is kept with the shrine as the verifier's proof.

Measured over 300 seeds, every shrine is solvable and its plan replays legally. The median shortest solution is 8 actions, the longest 16, and 187 of 300 need 8 or more.

Compilation turns the puzzle into an ordinary blueprint, validated by `Blueprint.fromDoc`:

- **Structure:** floor, roof, side and back walls, and doorway walls as structure parts.
- **Doors:** a generator powers the doors and the seed lamp. Each door is an actuator driven by one logic device: a term is `input > 0.5`, an inverted term `0.5 > input`, and two terms multiply.
- **Latches and plates:** buttons drive latches, and plates are the new `plate` device kind. A plate reports pressed while a crate centre is over its footprint and up to 1.2 m above it; people do not count.
- **Vault:** the vault button toggles a `sealed` latch that lights the seed lamp. The world marks the shrine complete when `sealed` is set.
- **Layout:** each room keeps a clear walkway on its centre line. Buttons and plates sit on rows 2.5 m either side of the room centre, and crates start between those rows, so everything can be reached without crossing another object.

## Placement and saves

For each shrine the Sandbox checks 16 seeded sites, keeps those at least 70 m from every trunk, 50 m from every plaza, and 90 m from the other shrine, and builds on the flattest. The floor sits at the highest terrain under the footprint. Crates are ordinary world crates.

Save format 9 tags shrine machines. Their doors, latches, and sealed vault persist as machine state, crates persist as crates, and the reward persists in the prefab library. The layout itself is regenerated from the seed. Content version 7 added the shrines and reward blueprints.

## Acceptance

- **Verification over seeds:** every one of 300 generated shrines is verified solvable, its plan replays through the rules, and its blueprint validates. Unsolvable or trivially open designs are rejected by the solver.
- **In the world:** a headless test plays each placed shrine's own verified plan in the real Sandbox, with walking, aiming, pressing buttons, and carrying crates onto plates and through real doors. After every action, every door's actual state must match the puzzle model.
- **Completion:** both shrines complete, grant their Rootsong blueprints, and keep completion through save/load. The shrines refuse removal and capture, and reset restores crates, latches, and doors.

## Limits

There are two shrines per world, in a fixed Rootdeep with no streaming or Rootdeep-specific terrain. Rooms form a straight chain with no branching or vertical puzzles. Plates weigh crates only. There are no genome-fragment rewards yet; rewards are blueprints. There is no in-game map marker, and guests can press buttons but cannot carry crates.
