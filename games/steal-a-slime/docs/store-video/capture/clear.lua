return function(world, player, now, ctx)
	local Spawner = require(script.Spawner)
	local WS = require(script.WeatherService)
	local t = now()
	local shifted = 0
	for i = 1, 400 do
		local raining, endsAt, nextAt = Spawner.rain(world, t)
		if not raining and nextAt and nextAt - t > 600 then break end
		world.startedAt -= 5
		shifted += 5
	end
	world.rainForcedUntil = nil
	if world.weather then
		world.weather.id = "Clear"
		world.weather.changeAt = math.huge
		world.weather.requested = nil
		WS.publish(world.weather, workspace, t)
	end
	return { shifted = shifted, weather = workspace:GetAttribute("Weather") }
end
