--!strict
-- lune run scripts/check-place build.rbxlx   (exit 1 on any failure)
local process = require("@lune/process")

local PlaceCheck = require("./PlaceCheck")

local path = process.args[1] or "build.rbxlx"
local failures = PlaceCheck.run(PlaceCheck.load(path))
for _, failure in failures do
	print(`FAIL {failure}`)
end
print(if #failures == 0 then `PASS {path}: void-safety checks` else `{#failures} failure(s) in {path}`)
process.exit(if #failures == 0 then 0 else 1)
