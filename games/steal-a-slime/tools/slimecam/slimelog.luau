--[[
	slimelog (Client, dev tool): logs what one slime does every rendered frame, so motion bugs can be read as numbers.

	Run it in the Client datamodel of a playtest (Studio MCP execute_luau, or the command bar in a Play session).
	Settings via _G before running:
	  _G.SlimeLogSpecies = "froggo"   -- follow the nearest wild slime of this species (nil: the nearest slime)
	  _G.SlimeLogSeconds = 20         -- how long to log
	  _G.SlimeLogTarget = model       -- or log exactly this slime model
	Then read _G.SlimeLog.rows (a list of rows) or _G.SlimeLog.csv() (header + one line per frame).

	Columns, per rendered frame (read after every RenderStepped handler: the pose that frame draws):
	  t               seconds since the log started
	  left            seconds until the slime's LaneUntil (its walk ends / it drains); blank off the lane
	  state, tier     the State attribute and the LifeTier the runner gave it ("near" | "mid" | "far" | blank = no rig)
	  bx, by, bz      the Body (server pivot, replicated in steps)
	  dx, dy, dz      the drawn slime: the Body moved by its SkinRoot Transform (the rig), its foot centre
	  yaw, pitch, roll  the drawn slime's rotation, degrees (yaw is its heading in the world)
	  faceYaw         the face's turn on top of the skin (eyes lead), degrees
	  meshY, meshX    the Mesh part's size (squash shows as meshY changing; a bone-skinned mesh keeps its size)
	  scale           the model's scale (GetScale: the despawn shrink)
	  despawn         seconds until DespawnAt (the despawn telegraph), blank when not despawning
	  bodyX, bodyY    the Body's size
	  meshZ           the Mesh part's depth
	  mx, my, mz      where the Mesh part really is (the engine's own position: a joint shows one frame late)
	  meshLTM         the Mesh part's LocalTransparencyModifier (1 = hidden)
	  skinTx/Ty/Tz    the SkinRoot Transform's offset (the rig: lane smoothing, hop, lean)
	  faceTy          the FaceRoot Transform's height
	  squashY/X       a SpecialMesh squash scale, when the skin squashes through one
	  bones, boneMax  how many bones the skin has, and the largest bone offset this frame
	  tagX/Y/Z        where the name tag hangs (TagAnchor)
	  stage, kind, fidget, emote, yawW, spin   what the slime is doing (gait stage, hop kind, fidget, emote, turn
	                  weight, spin angle): only in a test build whose SlimeActor writes Dbg* attributes for a model
	                  with the PcwLog attribute (slimelog sets it); blank otherwise
	  eyesIn, lidsOut how far the Eyes bone has sunk in and the Lids bone slid out (a shut eye: both > 0)
	  eyePartsHidden  eye parts (EyeWhite*, Pupil*) hidden by Transparency / LocalTransparencyModifier, of all
	  face, closed    the expression the actor asks for and its closed amount (test build Dbg* attributes)
]]
local CS = game:GetService("CollectionService")
local RS = game:GetService("RunService")

local want = _G.SlimeLogSpecies
local seconds = _G.SlimeLogSeconds or 20
local cam = workspace.CurrentCamera

local function pick(): Model?
	local best, bestD = nil, math.huge
	for _, m in CS:GetTagged("Slime") do
		local b = m.PrimaryPart
		if b and (want == nil or m:GetAttribute("Species") == want) and m:GetAttribute("State") ~= "Carried" then
			local d = (b.Position - cam.CFrame.Position).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

local target = _G.SlimeLogTarget or pick() -- _G.SlimeLogTarget: log exactly this model
if not target then
	return "no slime to log"
end
local body = target.PrimaryPart :: BasePart
target:SetAttribute("PcwLog", true) -- a test build with the debug hook fills Dbg* attributes for this slime
local log = { rows = {}, species = target:GetAttribute("Species"), id = target:GetAttribute("SlimeId") }
_G.SlimeLog = log

local function r3(x: number): string
	return string.format("%.3f", x)
end
local function deg(x: number): string
	return string.format("%.1f", math.deg(x))
end

-- bones of the skin mesh (a bone-skinned slime squashes through these, not the Mesh size)
local bones = {}
for _, d in target:GetDescendants() do
	if d:IsA("Bone") then
		table.insert(bones, d)
	end
end
-- the eyes: bone-skinned faces sink their Eyes bone in and slide the Lids bone out to shut; part faces have eye parts
local eyeBone, lidBone = nil, nil
for _, b in bones do
	if b.Name == "Eyes" then
		eyeBone = b
	elseif b.Name == "Lids" then
		lidBone = b
	end
end
local eyeParts = {}
for _, d in target:GetDescendants() do
	if d:IsA("BasePart") and (string.find(d.Name, "^EyeWhite") or string.find(d.Name, "^Pupil")) then
		table.insert(eyeParts, d)
	end
end
local squashMesh = nil
do
	local m = target:FindFirstChild("Mesh")
	squashMesh = m and m:FindFirstChildWhichIsA("SpecialMesh")
end

local t0 = os.clock()
local conn
conn = RS.RenderStepped:Connect(function()
	task.defer(function()
		if os.clock() - t0 > seconds or not target.Parent then
			conn:Disconnect()
			log.done = true
			return
		end
		local skin = body:FindFirstChild("SkinRoot")
		local face = body:FindFirstChild("FaceRoot")
		local drawn = body.CFrame
		local faceYaw = 0
		if skin and skin:IsA("Motor6D") then
			drawn = body.CFrame * skin.C0 * skin.Transform
			if face and face:IsA("Motor6D") then
				local _, fy = (skin.Transform:Inverse() * face.Transform):ToEulerAnglesYXZ()
				faceYaw = fy
			end
		end
		local foot = drawn * CFrame.new(0, -body.Size.Y / 2, 0)
		local look = drawn.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		local pitch, _, roll = (if skin and skin:IsA("Motor6D") then skin.Transform else CFrame.new()):ToEulerAnglesYXZ()
		local mesh = target:FindFirstChild("Mesh")
		local okScale, scale = pcall(target.GetScale, target)
		local now = workspace:GetServerTimeNow()
		local untilAt = target:GetAttribute("LaneUntil")
		local despawnAt = target:GetAttribute("DespawnAt")
		table.insert(log.rows, {
			r3(os.clock() - t0),
			if type(untilAt) == "number" then r3(untilAt - now) else "",
			tostring(target:GetAttribute("State") or ""),
			tostring(target:GetAttribute("LifeTier") or ""),
			r3(body.Position.X),
			r3(body.Position.Y),
			r3(body.Position.Z),
			r3(foot.X),
			r3(foot.Y),
			r3(foot.Z),
			deg(yaw),
			deg(pitch),
			deg(roll),
			deg(faceYaw),
			if mesh and mesh:IsA("BasePart") then r3(mesh.Size.Y) else "",
			if mesh and mesh:IsA("BasePart") then r3(mesh.Size.X) else "",
			if okScale then r3(scale) else "",
			if type(despawnAt) == "number" then r3(despawnAt - now) else "",
			-- everything else that changes what is drawn
			r3(body.Size.X),
			r3(body.Size.Y),
			if mesh and mesh:IsA("BasePart") then r3(mesh.Size.Z) else "",
			if mesh and mesh:IsA("BasePart") then r3(mesh.Position.X) else "",
			if mesh and mesh:IsA("BasePart") then r3(mesh.Position.Y) else "",
			if mesh and mesh:IsA("BasePart") then r3(mesh.Position.Z) else "",
			if mesh and mesh:IsA("BasePart") then r3(mesh.LocalTransparencyModifier) else "",
			if skin and skin:IsA("Motor6D") then r3(skin.Transform.Position.X) else "",
			if skin and skin:IsA("Motor6D") then r3(skin.Transform.Position.Y) else "",
			if skin and skin:IsA("Motor6D") then r3(skin.Transform.Position.Z) else "",
			if face and face:IsA("Motor6D") then r3(face.Transform.Position.Y) else "",
			if squashMesh then r3(squashMesh.Scale.Y) else "",
			if squashMesh then r3(squashMesh.Scale.X) else "",
			tostring(#bones),
			(function()
				local worst = 0
				for _, b in bones do
					worst = math.max(worst, b.Transform.Position.Magnitude)
				end
				return r3(worst)
			end)(),
			(function()
				local a = body:FindFirstChild("TagAnchor")
				if a and a:IsA("Attachment") then
					local w = a.WorldPosition
					return r3(w.X) .. "," .. r3(w.Y) .. "," .. r3(w.Z)
				end
				return ",,"
			end)(),
			-- what the slime is doing (Dbg* attributes from a test build's SlimeActor debug hook; blank otherwise)
			tostring(target:GetAttribute("DbgStage") or ""),
			tostring(target:GetAttribute("DbgKind") or ""),
			tostring(target:GetAttribute("DbgFidget") or ""),
			tostring(target:GetAttribute("DbgEmote") or ""),
			tostring(target:GetAttribute("DbgYawW") or ""),
			tostring(target:GetAttribute("DbgSpin") or ""),
			if eyeBone then r3(eyeBone.Transform.Position.Magnitude) else "",
			if lidBone then r3(lidBone.Transform.Position.Magnitude) else "",
			(function()
				local hidden = 0
				for _, e in eyeParts do
					if e.LocalTransparencyModifier > 0.5 or e.Transparency > 0.5 then
						hidden += 1
					end
				end
				return tostring(hidden) .. "/" .. tostring(#eyeParts)
			end)(),
			tostring(target:GetAttribute("DbgFace") or ""),
			tostring(target:GetAttribute("DbgClosed") or ""),
		})
	end)
end)

function log.csv(): string
	local lines = {
		"t,left,state,tier,bx,by,bz,dx,dy,dz,yaw,pitch,roll,faceYaw,meshY,meshX,scale,despawn,"
			.. "bodyX,bodyY,meshZ,mx,my,mz,meshLTM,skinTx,skinTy,skinTz,faceTy,squashY,squashX,bones,boneMax,tagX,tagY,tagZ,"
			.. "stage,kind,fidget,emote,yawW,spin,eyesIn,lidsOut,eyePartsHidden,face,closed",
	}
	for _, row in log.rows do
		table.insert(lines, table.concat(row, ","))
	end
	return table.concat(lines, "\n")
end

return string.format("logging %s %s for %ds", tostring(log.species), tostring(log.id), seconds)
