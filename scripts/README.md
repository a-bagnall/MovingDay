# MovingDay!

Local 2-player co-op moving-company game built in Godot 4.7 (Jolt Physics). Carry furniture out of the house and into the truck without breaking it.

## Run

Open the project in Godot 4.7 and press F5.

## Controls

The game starts in the main menu. Hold the interact button there to claim a player slot (first to join is P1), then stand on a run slot pad and press interact to start a new run or continue a saved one. A run is a series of days, each a job. Every 3 days the players visit the hub (walk onto the truck pad together to start the next job). The game saves only at the start and end of a day.

| Source | Move | Interact (grab / drop) |
| --- | --- | --- |
| Keyboard | WASD | E |
| Keyboard | Arrow keys | Enter |
| Gamepad | Left stick | A |

Heavy items need two players (one player can lift them, but loses grip easily). Press interact on the results screen to continue. Press F3 for a debug overlay showing grip, damage and impact values.

## Online (LAN or internet)

In the main menu, stand on the blue **Online** pad and press interact to open a small host/join panel (close it with Close or Esc; that does not disconnect). One player hosts, the others join by typing the host's address. Everyone connected appears in the main menu room, and each machine can have several local players: any mix of local and online players works, up to 4 in total. Only the host picks a run. **Jobs are not synchronised between machines yet**, so a run cannot start while other machines are connected.
