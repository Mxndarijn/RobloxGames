--!strict
--[[
	ObbyVineSend (pure, no Roblox API at load time; contract/obby.md §5 "Vine ropes for everyone")

	When the local runner's client tells the server which vine rope it hangs on (Request ObbyVine), so other clients
	draw that rope carrying them. Only the latest hold is sent, one request in flight at a time and never faster than
	the server's rate limit (Validate.ACTIONS.ObbyVine), so a quick let go and grab sends just the grab. A hold the
	server has not published back (the Player's ObbyVine attribute) after RESEND seconds is sent again.

	  ObbyVineSend.new() -> State
	  ObbyVineSend.next(state, want, shown, clock) -> string?
	      what to send now (a rope part id, "" = let go), or nil; `want` is the rope held now ("" = none), `shown`
	      the published attribute ("" = none). Marks it sent; call `done` when the request returns
	  ObbyVineSend.done(state)
]]

local Validate = if script then require(script.Parent.Parent.Shared.Validate) else require("../../shared/Validate")

local ObbyVineSend = {}

ObbyVineSend.GAP = Validate.ACTIONS.ObbyVine + 0.02 -- seconds between two sends (just over the server's limit)
ObbyVineSend.RESEND = 1 -- seconds a sent hold may stay unpublished before it is sent again

export type State = { sent: string, at: number, busy: boolean }

function ObbyVineSend.new(): State
	return { sent = "", at = -math.huge, busy = false }
end

function ObbyVineSend.next(state: State, want: string, shown: string, clock: number): string?
	if state.busy or clock - state.at < ObbyVineSend.GAP then
		return nil
	end
	if want == shown and want == state.sent then
		return nil
	end
	if want == state.sent and want ~= shown and clock - state.at < ObbyVineSend.RESEND then
		return nil
	end
	if want == shown and want ~= state.sent then
		-- the server already shows it (a run that ended cleared it, as we let go): nothing to send
		state.sent = want
		return nil
	end
	state.sent = want
	state.at = clock
	state.busy = true
	return want
end

function ObbyVineSend.done(state: State)
	state.busy = false
end

return table.freeze(ObbyVineSend)
