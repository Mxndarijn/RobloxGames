--!strict
-- RequestText: refusal reasons leaving the server (the Request result, ShopEvent Denied) as Localize messages,
-- so each client draws them in its own language. The matching is shared/ReasonText.
local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local ReasonText = if Shared then require(Shared.ReasonText) else require("../shared/ReasonText")

local RequestText = {}

-- The message for reason `text`, or `text` when no reason entry matches (ReasonText.message).
function RequestText.message(text: any): any
	return ReasonText.message(text)
end

-- A Request result ready for the client: a refusal's message as a Localize message, `reason` its English.
function RequestText.result(res: any): any
	return ReasonText.result(res)
end

return table.freeze(RequestText)
