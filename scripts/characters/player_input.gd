extends RefCounted
class_name PlayerInput
## One player's input for the current physics frame. Player reads only this, never
## InputSetup directly. A local player fills it from its InputSetup source every
## frame; for a remote player (online play) the network layer fills it instead.

## Raw stick or key direction before camera rotation (x right, y down on screen).
var move := Vector2.ZERO
## True while the interact button is held.
var interact := false
## Held while raising a carried item (see Furniture).
var lift := false
## Action and Ping buttons, held (a press is a change from false to true).
var action := false
var ping := false
## Heave-ho: pressed together with a carrying partner.
var heave := false

## The three extra buttons as bits, for the network: 1 lift, 2 action, 4 ping, 8 heave.
func buttons_bits() -> int:
	return (1 if lift else 0) | (2 if action else 0) | (4 if ping else 0) | (8 if heave else 0)


func set_buttons_bits(bits: int) -> void:
	lift = bits & 1 != 0
	action = bits & 2 != 0
	ping = bits & 4 != 0
	heave = bits & 8 != 0
