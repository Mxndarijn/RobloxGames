--!strict
--[[
	Migrations: versioned save upgrades and field sanitizers.

		local data, status = Migrations.run(raw, {
			[0] = function(raw) raw.coins = raw.cash; return raw end, -- 0 -> 1
			[1] = function(raw) raw.pets = raw.pets or {}; return raw end, -- 1 -> 2
		}, 2)

	run upgrades a stored table one step at a time: `steps[v]` turns a version-v table into version v+1, and run
	stamps the version field (default "version") after each step. A table without a version field counts as
	version 0. Status:
	  "ok"    data is at `latest`. Steps get a shallow copy of the input, so top-level edits never reach the
	          caller's table; a step that edits nested tables should copy them first.
	  "fresh" input is nil, not a table, or has an unusable version; data is nil: start from defaults.
	  "newer" the stored version is above `latest` (a newer build wrote it); data is the input, untouched.
	          The caller must not save over it.
	A missing step between the stored version and `latest` is a programming error and raises.

	Sanitizers turn untrusted stored values into safe ones:
	  num(v, default, min?, max?)  finite number clamped to [min, max], else default.
	  str(v, default, maxLen?)     string cut to maxLen characters, else default.
	  enum(v, allowed, default)    v when it is in `allowed` (a list or a set), else default.
]]

export type Step = (raw: { [any]: any }) -> { [any]: any }
export type Steps = { [number]: Step }
export type Status = "ok" | "fresh" | "newer"

local Migrations = {}

local function isInteger(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v == math.floor(v)
end

function Migrations.run(raw: any, steps: Steps, latest: number, versionField: string?): ({ [any]: any }?, Status)
	if not isInteger(latest) or latest < 0 then
		error("Migrations.run: latest must be a non-negative integer", 2)
	end
	if type(raw) ~= "table" then
		return nil, "fresh"
	end
	local field = versionField or "version"
	local stored = raw[field]
	local version: number
	if stored == nil then
		version = 0
	elseif isInteger(stored) and stored >= 0 then
		version = stored
	else
		return nil, "fresh"
	end
	if version > latest then
		return raw, "newer"
	end
	local out = table.clone(raw)
	while version < latest do
		local step = steps[version]
		if type(step) ~= "function" then
			error(`Migrations.run: no step from version {version}`, 2)
		end
		local result = step(out)
		if type(result) ~= "table" then
			error(`Migrations.run: step from version {version} did not return a table`, 2)
		end
		version += 1
		out = result
		out[field] = version
	end
	return out, "ok"
end

function Migrations.num(v: any, default: number, min: number?, max: number?): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	local n = v
	if min ~= nil and n < min then
		n = min
	end
	if max ~= nil and n > max then
		n = max
	end
	return n
end

function Migrations.str(v: any, default: string, maxLen: number?): string
	if type(v) ~= "string" then
		return default
	end
	if maxLen ~= nil and #v > maxLen then
		return string.sub(v, 1, math.max(0, maxLen))
	end
	return v
end

function Migrations.enum<T>(v: any, allowed: { [any]: any }, default: T): T
	if v == nil then
		return default
	end
	if allowed[v] == true or table.find(allowed :: { any }, v) ~= nil then
		return v
	end
	return default
end

return table.freeze(Migrations)
