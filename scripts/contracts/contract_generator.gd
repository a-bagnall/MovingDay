extends RefCounted
class_name ContractGenerator
## Small fixed contract pool for the single test house. Replace this with
## procedural property/client generation when the later house milestone lands.

const CONTRACT_POOL: Array[Dictionary] = [
	{
		"client_name": "The Henderson Family",
		"letter_text": "Hello movers,\n\nWe are moving across town and need the furniture from our house delivered safely. Please take extra care with the television and the old standing lamp.\n\nThank you!",
		"payout": 500.0,
	},
	{
		"client_name": "Margaret Whitaker",
		"letter_text": "Dear moving team,\n\nI am downsizing and need everything moved before the end of the day. The cabinet is particularly important to me, so please handle it carefully.\n\nKind regards, Margaret",
		"payout": 560.0,
	},
	{
		"client_name": "Juniper Street Cafe",
		"letter_text": "Hi there,\n\nWe are relocating our small cafe. The fridge and seating need to arrive in one piece so we can reopen tomorrow. A quick job would be appreciated!\n\nThanks,\nThe Juniper Street team",
		"payout": 625.0,
	},
	{
		"client_name": "The Parkers",
		"letter_text": "Hello,\n\nWe have a busy day ahead and would love to get settled into our new place as soon as possible. Please move everything listed in the house.\n\nAll the best,\nThe Parkers",
		"payout": 540.0,
	},
]


static func generate_contract(contract_number: int) -> Contract:
	var data: Dictionary = CONTRACT_POOL[posmod(contract_number - 1, CONTRACT_POOL.size())]
	var contract := Contract.new()
	contract.contract_number = contract_number
	contract.client_name = str(data["client_name"])
	contract.letter_text = str(data["letter_text"])
	contract.payout = float(data["payout"]) * Balance.CONTRACT_PAYOUT_MULTIPLIER
	return contract
