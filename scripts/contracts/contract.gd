extends Resource
class_name Contract
## Data for one moving job. Kept separate from the house so contract content can
## change independently of the test level and its scoring implementation.

@export var contract_number := 1
@export var client_name := "The Henderson Family"
@export_multiline var letter_text := "Hello movers,\n\nWe are moving across town and need the furniture from our house delivered safely. Please take extra care with the television and the old standing lamp.\n\nThank you!"
@export var payout := 500.0
