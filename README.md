# MovingDay!

Local 2-player co-op moving-company game built in Godot 4.7 (Jolt Physics). Carry furniture out of the house and into the truck without breaking it.

## Run

Open the project in Godot 4.7 and press F5.

## Controls

The game starts in the main menu. Hold the interact button there to claim a player slot (first to join is P1), then stand on a run slot pad and press interact. An empty slot starts a new run; a saved one opens its details (day, wallet, contracts completed, earnings, damage, last saved) with Continue, Delete and Back. Move with the arrow keys or d-pad and press Enter or gamepad A; Delete asks for confirmation and frees the slot. A run is a series of days, each a job. Every 3 days the players visit the hub (walk onto the truck pad together to start the next job). The game saves only at the start and end of a day. You can play a whole run solo: a lone player can carry two-player items, but only at a slow walk, and nothing heavy is ever stuck to another item.

| Source | Move | Interact (grab / drop) | Lift (hold) | Action | Ping |
| --- | --- | --- | --- | --- | --- |
| Keyboard 1 | WASD | E | Q | R | F |
| Keyboard 2 | Arrow keys | Enter | Right Shift | Right Ctrl | / |
| Gamepad | Left stick | A | Left trigger | X | Y |

Hold Lift while carrying to raise the item over rails and counters (it costs grip, so it is a move, not a pose). Ping drops a marker in your colour ahead of you, or on the item you face, for a few seconds, and everyone sees it. Your colour shows as a ring under your feet; pick it on the Wardrobe pad with up/down (left/right still picks the animal). With empty hands, Action shoves whatever is in front of you: a teammate gets knocked back, and furniture slides (sturdy things shrug it off, fragile things tend to break). It has a one-second cooldown. While carrying a light one-player item (10 kg or less), hold Action to wind up and release to throw it; a quick tap is a short toss. Damage on landing uses the normal impact rules.

Characters: a new player picks one on joining (left/right to choose, interact to confirm), and anyone can change it later on the pink Wardrobe pad. Everyone sees everyone's pick, online too. Each character is scaled to a set height in `scripts/characters/character_catalog.gd`; if one looks backwards in game, change its `yaw` there.

From day 3 some furniture is stuck together in pink-gummed pairs (more every 5 days). Every 3 days, at the hub, the host gets a **Pick One** card: three modifiers side by side (left/right to look, Enter or gamepad A to pick). Each is a detriment that adds chaos for the rest of the run. The ones in play show as tags during a job, in the hub, and on the run slot's details card. Perks (helpful, earned by levelling up) are a separate, future system.

## Running costs and how a run ends

At the end of every day the company pays running costs ($150 on day 1, +$60 each day; Greedy Landlord makes it 35% more). The briefing shows them, and the hub shows what a day costs. If that takes the wallet below zero the company is bankrupt: the run slot is deleted, the **Run Over** screen shows how it went, and everyone returns to the main menu. Each ended run is also appended to `run_history.jsonl` in the user data folder (Godot: Project > Open User Data Folder) so you can compare playtests.

## Tuning

All the balance numbers (day length, pay, running costs, modifier strengths, shop prices, sticky pairs) live in `scripts/progression/balance.gd`. Pick One and shop text is built from them, so changing a number is one edit. Note `DAY_LENGTH` is 10 seconds (one contract a day) and day 1 is a single Box; both are flags there for the testing phase.

Heavy items need two players (one player can lift them, but loses grip easily). Press interact on the results screen to continue. Press F3 for a debug overlay showing grip, damage and impact values.

## Online (LAN or internet)

In the main menu, stand on the blue **Online** pad and press interact to open a small host/join panel (close it with Close or Esc; that does not disconnect). One player hosts, the others join by typing the host's address. Everyone connected appears in the main menu room, and each machine can have several local players: any mix of local and online players works, up to 4 in total. Only the host picks a run; everyone is then taken to the briefing and through the run together (any player can press continue on the briefing, only the host starts a job from the hub).

In a job the host runs the furniture physics, grip, damage and delivery, and streams the result to the other machines; each machine moves its own players. It is built for a LAN or a low-latency connection: carrying feels best when the round trip is short. Nobody can join while a run is in progress, so connect everyone in the main menu first. A run is saved only on the host.
