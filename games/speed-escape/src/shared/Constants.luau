--!strict
-- Gameplay tunables shared between server and client.

local Constants = {
	-- Stages built by Shared.StageGenerator (5..8). Stage 8 reaches the 14-stud max gap.
	STAGE_COUNT = 8,
	-- Default Roblox jump; StageGenerator's gap maths assumes this value.
	JUMP_POWER = 50,
	-- Folder/RemoteEvent names under ReplicatedStorage.
	REMOTES_FOLDER = "Remotes",
	WIN_EVENT = "WinEvent",
	-- Persistence.
	DATASTORE_NAME = "SpeedEscape_v1",
	DATASTORE_MODE_ATTRIBUTE = "DataStoreMode",
}

return table.freeze(Constants)
