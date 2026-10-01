# Phase 16: UDP networking

**Goal:** online play for up to four players, matching the local co-op cap, on the engine's deterministic fixed step. It must stay responsive at real-world latency and loss, and every client action is validated by the host.

## Today

- **Simulation:** a single process with a deterministic 60 Hz fixed step (`Time.fixed_dt`). The traversal controller (`Player.step`), machines, physics, and city life step allocation-free.
- **Players:** local co-op runs up to three `Guest` players with their own input. Saves are complete JSON world documents. Every build, wire, trade, and bridge action already goes through validators that reject without mutating.
- **Missing:** a transport, replication, prediction, and interpolation.

## Design

### Topology

- **Listen server:** the host's game is authoritative. Up to three remote clients join, each taking a guest slot, so remote players reuse `Guest` with its input fed from the network instead of a pad. A dedicated, headless server is a later slice that reuses the same code; the simulation already runs without a window in tests.
- **Joining:** the host sends the current world as a save document (the existing format, compressed) over the reliable channel, then streams snapshots. The client loads it with the normal save loader, which validates everything and rejects mismatched seeds, generators, content, or mods.

### Transport

- **Sockets:** UDP through Zig 0.16's `std.Io.net` datagram sockets (`IpAddress.bind`, `Socket.send`, `Socket.receiveTimeout`), in native Zig on a network thread. `std.Io` is passed explicitly, as everywhere else.
- **Packet:** a protocol ID and version, connection salt, sequence number, latest acknowledged sequence, a 32-bit ack bitfield, then messages. Packets stay under 1,200 bytes to avoid fragmentation, and large messages such as the join world are split into fragments.
- **Channels:**
  - *Unreliable-sequenced:* client input commands and server snapshots; old ones are dropped.
  - *Reliable-ordered:* join, leave, build, wire, trade, bridge, chat, and mod list. Messages are resent until acknowledged; actions require confirmation.
- **Connection:** a handshake with a challenge token, timeouts, and graceful disconnect. A disconnected guest leaves as a local pad unplug does.

### Replication

- **Client to server:** input commands each tick: `Input` fields, look angles, and action edges, with a tick number. The last few commands are repeated in every packet so a lost packet costs nothing.
- **Server to client:** snapshots at 30 Hz with entity states: players (position, velocity, motion, traversal, view yaw and pitch), vehicles (rigid poses), crates, machine outputs that are visible (actuator positions, lamp levels), city-life cars and pedestrians, shrine doors, and market stock. Each snapshot is delta-encoded against the last snapshot the client acknowledged, and quantized (positions to 1 mm, quaternions in smallest-three form).
- **Entity identity:** existing stable IDs (machine slots, crate slots, guest index, life indices, bridge slots), and asset GUIDs from phase 13 where content is referenced.

### Responsiveness

- **Client-side prediction for the local player:** the client runs the same `Player.step` on its own input immediately. On each snapshot it rewinds to the acknowledged state and replays its unacknowledged inputs (reconciliation). Small errors are corrected smoothly over about 100 ms, and large ones snap.
- **Interpolation for everything else:** remote entities render about 100 ms behind the newest snapshot, interpolated between two snapshots; quaternions use slerp. Brief gaps are extrapolated for at most 250 ms, then frozen.
- **Server-side checks:** the server applies each action at the client's tick when it is within a lag-compensation window. Positions and velocities are clamped to what the controller allows, so a client cannot teleport.

### Testing without a network

- **Simulated link:** the transport is an interface. A deterministic in-process link with seeded latency, jitter, loss, duplication, and reordering lets one test run a server Sandbox and client Sandboxes side by side, with no sockets and no flakiness.
- **Loopback:** one smoke test uses real UDP sockets on loopback.

## Slices

1. **Transport.** Packet format, acks and resends, channels, fragmentation, handshake and timeouts, and the simulated link. Tests cover reliable delivery at 20% loss and ordering under reordering.
2. **Join and snapshots.** World transfer through the save format, remote guests driven by network input, and snapshots with interpolation of remote entities.
3. **Prediction and reconciliation** for the local player across all traversal states (grapple, climb, glide), with error metrics.
4. **Actions and replication of world changes.** Build, wire, trade, bridges, shrine interactions, and city life sent through reliable messages validated by the server. Late join while the world changes.
5. **Dedicated headless server** and a basic lobby (direct IP first).

## Acceptance

- **Transport:** at 150 ms round trip, 5% loss, and 20 ms jitter on the simulated link, every reliable message arrives exactly once and in order. Snapshot bandwidth stays under 64 kbit/s per client with four players and city life running.
- **Prediction:** the local player's predicted position stays within 5 cm of the server's state 99% of the time while running, jumping, climbing, and grappling. Corrections never exceed 1 m outside teleports.
- **Interpolation:** remote players animate smoothly, with no visible pops above a 2 cm-per-frame jerk threshold at 60 Hz and 5% loss.
- **Authority:** a client sending invalid actions (overlapping placement, bad wiring, trading without scrap, an out-of-range teleport) is refused, and the world matches the server's.
- **Real sockets:** a loopback smoke run with two processes completes a join, a walk, a button press that opens the powered door on both, and a disconnect, with no validation errors.

## Risks

- **Divergence:** predicted and server results can drift. Mitigation: the controller is deterministic on one machine, prediction is corrected rather than trusted, and divergence metrics are tested.
- **Bandwidth:** busy worlds can exceed the budget. Mitigation: delta compression, quantization, relevance limits (only nearby city life), and measured budgets.
- **Security:** a public server needs more than validation. Out of scope for this phase: no authentication or encryption beyond the handshake token. Play is direct-connect between trusted peers.

**Out of scope:** matchmaking, NAT traversal, rollback netcode for combat, and more than four players.
