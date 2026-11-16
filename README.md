# MovingDay!

Local 2-player co-op moving-company game built in Godot 4.7 (Jolt Physics). Carry furniture out of the house and into the truck without breaking it.

## Run

Open the project in Godot 4.7 and press F5.

## Controls

The game starts in the main menu. Hold the interact button there to claim a player slot (first to join is P1), then stand on a run slot pad and press interact. An empty slot starts a new run; a saved one opens its details (day, wallet, contracts completed, earnings, damage, last saved) with Continue, Delete and Back. Move with the arrow keys or d-pad and press Enter or gamepad A; Delete asks for confirmation and frees the slot. A run is a series of days, each a job. Every 3 days the players visit the hub (walk onto the truck pad together to start the next job). The game saves only at the start and end of a day.

| Source | Move | Interact (grab / drop) |
| --- | --- | --- |
| Keyboard | WASD | E |
| Keyboard | Arrow keys | Enter |
| Gamepad | Left stick | A |

Heavy items need two players (one player can lift them, but loses grip easily). Press interact on the results screen to continue. Press F3 for a debug overlay showing grip, damage and impact values.

## Online (LAN or internet)

In the main menu, stand on the blue **Online** pad and press interact to open a small host/join panel (close it with Close or Esc; that does not disconnect). One player hosts, the others join by typing the host's address. Everyone connected appears in the main menu room, and each machine can have several local players: any mix of local and online players works, up to 4 in total. Only the host picks a run; everyone is then taken to the briefing and through the run together (any player can press continue on the briefing, only the host starts a job from the hub).

In a job the host runs the furniture physics, grip, damage and delivery, and streams the result to the other machines; each machine moves its own players. It is built for a LAN or a low-latency connection: carrying feels best when the round trip is short. Nobody can join while a run is in progress, so connect everyone in the main menu first. A run is saved only on the host.
