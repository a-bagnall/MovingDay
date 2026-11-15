extends RefCounted
class_name PlayerInput
## One player's input for the current physics frame. Player reads only this, never
## InputSetup directly. A local player fills it from its InputSetup source every
## frame; for a remote player (online play) the network layer fills it instead.

## Raw stick or key direction before camera rotation (x right, y down on screen).
var move := Vector2.ZERO
## True while the interact button is held.
var interact := false
