export type SlotData = {
	player: Player?,
	userId: number?,
	isBot: boolean,
	name: string,
	hearts: number?,
	customData: { [string]: any }?,
}

export type QueueState = "Waiting" | "Starting" | "InMatch"

export type PadConfig = {
	requiredPlayers: number?,
	allowVsAi: boolean?,
	snapToPad: boolean?,
	lockMovement: boolean?,
	rewardText: string?,
	arenaName: string?,
}

export type MatchSession = {
	id: string,
	pad: Instance,
	slot1: SlotData,
	slot2: SlotData,
	state: QueueState,
	data: { [string]: any },
	FinishMatch: (self: MatchSession, winnerSlot: number?) -> (),
	CancelMatch: (self: MatchSession) -> (),
}

return {}
