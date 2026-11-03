--!strict
--[[
	ObbyBannerFade (pure, no Roblox API at load time)

	Which obby picture sign banners the local runner sees. A banner the runner has walked past still hangs in the
	third-person camera's view behind them, right between the camera and the runner, so it fades out on that runner's
	client once they are past it and fades back in when they are before it again (a reset to the start, a walk back).
	visuals/client/ObbySignFade applies this to the built banners each frame; tunables are Config.OBBY.BANNER_FADE.
	A memory section's route (parts with a `reveal` line) follows the same rules with Config.OBBY.ROUTE_REVEAL
	(`ObbyBannerFade.ROUTE`): shown while the runner is before its line, hidden once past it.

	Every function takes an optional `tune` (default BANNER_FADE).

	  ObbyBannerFade.hidden(was, rootX, bannerX, tune?) -> boolean
	      whether a banner at course x `bannerX` is hidden for a root at course x `rootX` (nil: no runner on the
	      course, so shown), given whether it was hidden: it hides beyond HIDE_PAST and shows again within SHOW_PAST,
	      so a runner standing at the edge doesn't make it flicker
	  ObbyBannerFade.step(alpha, hidden, dt, tune?) -> number
	      the fade (0 shown .. 1 gone) after `dt` seconds moving towards `hidden`, a full fade in SECONDS
	  ObbyBannerFade.transparency(base, alpha) -> number
	      a property whose shown value is `base` at fade `alpha`
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

local ObbyBannerFade = {}

export type Tune = { HIDE_PAST: number, SHOW_PAST: number, SECONDS: number }

ObbyBannerFade.BANNER = Config.OBBY.BANNER_FADE :: Tune
ObbyBannerFade.ROUTE = Config.OBBY.ROUTE_REVEAL :: Tune

function ObbyBannerFade.hidden(was: boolean, rootX: number?, bannerX: number, tune: Tune?): boolean
	if rootX == nil then
		return false
	end
	local t = tune or ObbyBannerFade.BANNER
	local past = rootX - bannerX
	return past > (if was then t.SHOW_PAST else t.HIDE_PAST)
end

function ObbyBannerFade.step(alpha: number, hidden: boolean, dt: number, tune: Tune?): number
	local t = tune or ObbyBannerFade.BANNER
	local target = if hidden then 1 else 0
	if t.SECONDS <= 0 then
		return target
	end
	local move = math.max(dt, 0) / t.SECONDS
	if alpha < target then
		return math.min(alpha + move, target)
	end
	return math.max(alpha - move, target)
end

function ObbyBannerFade.transparency(base: number, alpha: number): number
	return base + (1 - base) * math.clamp(alpha, 0, 1)
end

return table.freeze(ObbyBannerFade)
