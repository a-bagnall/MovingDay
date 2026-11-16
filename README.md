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

Characters: a new player picks one on joining (left/right to choose, interact to confirm), and anyone can change it later on the pink Wardrobe pad. Everyone sees everyone's pick, online too. Each character is scaled to a set height in `scripts/characters/character_catalog.gd`; if one looks backwards in game, change its `yaw` there.

From day 3 some furniture is stuck together in pink-gummed pairs (more every 5 days). Every 3 days, at the hub, the host gets a **Pick One** card: three modifiers side by side (left/right to look, Enter or gamepad A to pick). Each is a detriment that adds chaos for the rest of the run. The ones in play show as tags during a job, in the hub, and on the run slot's details card. Perks (helpful, earned by levelling up) are a separate, future system.

Heavy items need two players (one player can lift them, but loses grip easily). Press interact on the results screen to continue. Press F3 for a debug overlay showing grip, damage and impact values.

## Online (LAN or internet)

In the main menu, stand on the blue **Online** pad and press interact to open a small host/join panel (close it with Close or Esc; that does not disconnect). One player hosts, the others join by typing the host's address. Everyone connected appears in the main menu room, and each machine can have several local players: any mix of local and online players works, up to 4 in total. Only the host picks a run; everyone is then taken to the briefing and through the run together (any player can press continue on the briefing, only the host starts a job from the hub).

In a job the host runs the furniture physics, grip, damage and delivery, and streams the result to the other machines; each machine moves its own players. It is built for a LAN or a low-latency connection: carrying feels best when the round trip is short. Nobody can join while a run is in progress, so connect everyone in the main menu first. A run is saved only on the host.
