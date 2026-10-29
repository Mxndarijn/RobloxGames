--!strict
--[[
	LabelFitView (adapter, client)

	Fits pixel-sized BillboardGuis to the local screen (LabelFit): on a phone their pixels shrink so a tag
	takes the same share of the screen as on a monitor, and a tag can use a shorter MaxDistance there.

	Mark a label from any side with the pure helper (a server-built tag replicates its tag and attributes):

	    LabelFit.mark(gui)                                   -- shrink its pixels on a phone
	    LabelFit.mark(gui, { phoneDistance = 40 })           -- and a shorter MaxDistance there
	    LabelFit.mark(gui, { phoneDistance = 40, keepSize = true })   -- only the distance

	and run one fitter on the client:

	    local fitter = LabelFitView.new()   -- options: { tag, camera, fit = LabelFit.Options }
	    fitter.destroy()

	How it scales: the gui's pixel Size is multiplied by k and a UIScale of k is added under the gui. Its
	contents still lay out in the original pixel canvas (fixed TextSizes included) and are drawn k times
	smaller. When the owner sets a new Size later (a card that grows a row), that becomes the new base.
	Pixel tags only: a Size with stud (scale) parts is scaled the same way, which is rarely what you want.
]]

local CollectionService = game:GetService("CollectionService")

local LabelFit = if script then require(script.Parent.LabelFit) else require("./LabelFit")

local LabelFitView = {}

LabelFitView.TAG = LabelFit.TAG
LabelFitView.PHONE_DISTANCE = LabelFit.PHONE_DISTANCE -- number attribute: MaxDistance on a phone-sized screen
LabelFitView.KEEP_SIZE = LabelFit.KEEP_SIZE -- bool attribute: don't scale the pixels
LabelFitView.SCALE_NAME = "LabelFitScale" -- the UIScale this module adds

export type Options = {
	tag: string?,
	camera: (() -> Camera?)?, -- default: workspace.CurrentCamera
	fit: LabelFit.Options?,
}

export type Handle = {
	refit: () -> (),
	count: () -> number,
	destroy: () -> (),
}

type Entry = {
	gui: BillboardGui,
	baseSize: UDim2,
	baseDistance: number,
	written: UDim2?,
	writtenDistance: number?,
	scale: UIScale?,
	conns: { RBXScriptConnection },
}

function LabelFitView.new(options: Options?): Handle
	local o: Options = options or {}
	local tag = o.tag or LabelFitView.TAG
	local getCamera = o.camera or function()
		return workspace.CurrentCamera
	end
	local entries: { [BillboardGui]: Entry } = {}
	local conns: { RBXScriptConnection } = {}
	local viewportConn: RBXScriptConnection? = nil
	local watchedCamera: Camera? = nil

	local function viewportHeight(): number
		local camera = getCamera()
		return if camera then camera.ViewportSize.Y else LabelFit.DEFAULTS.referenceHeightPx :: number
	end

	local function apply(e: Entry, height: number)
		local gui = e.gui
		local phone = gui:GetAttribute(LabelFitView.PHONE_DISTANCE)
		local distance =
			LabelFit.maxDistance(e.baseDistance, if type(phone) == "number" then phone else nil, height, o.fit)
		if gui.MaxDistance ~= distance then
			e.writtenDistance = distance
			gui.MaxDistance = distance
		end
		local k = if gui:GetAttribute(LabelFitView.KEEP_SIZE) == true then 1 else LabelFit.pxScale(height, o.fit)
		local w, h = LabelFit.scalePx(e.baseSize.X.Offset, e.baseSize.Y.Offset, k)
		local size = UDim2.new(e.baseSize.X.Scale, w, e.baseSize.Y.Scale, h)
		if gui.Size ~= size then
			e.written = size
			gui.Size = size
		end
		if k == 1 then
			if e.scale then
				e.scale:Destroy()
				e.scale = nil
			end
		else
			local scale = e.scale
			if not scale or scale.Parent ~= gui then
				local made = Instance.new("UIScale")
				made.Name = LabelFitView.SCALE_NAME
				made.Parent = gui
				scale = made
				e.scale = made
			end
			(scale :: UIScale).Scale = k
		end
	end

	local function add(inst: Instance)
		if not inst:IsA("BillboardGui") or entries[inst] then
			return
		end
		local gui = inst :: BillboardGui
		local e: Entry = {
			gui = gui,
			baseSize = gui.Size,
			baseDistance = gui.MaxDistance,
			conns = {},
		}
		entries[gui] = e
		-- The owner may set a new size or range later: that becomes the new base.
		table.insert(
			e.conns,
			gui:GetPropertyChangedSignal("Size"):Connect(function()
				if gui.Size ~= e.written then
					e.baseSize = gui.Size
					apply(e, viewportHeight())
				end
			end)
		)
		table.insert(
			e.conns,
			gui:GetPropertyChangedSignal("MaxDistance"):Connect(function()
				if gui.MaxDistance ~= e.writtenDistance then
					e.baseDistance = gui.MaxDistance
					apply(e, viewportHeight())
				end
			end)
		)
		apply(e, viewportHeight())
	end

	local function remove(inst: Instance)
		local e = entries[inst :: any]
		if not e then
			return
		end
		entries[inst :: any] = nil
		for _, c in e.conns do
			c:Disconnect()
		end
	end

	local function refit()
		local height = viewportHeight()
		for _, e in entries do
			apply(e, height)
		end
	end

	local function watchCamera()
		local camera = getCamera()
		if camera == watchedCamera then
			return
		end
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		watchedCamera = camera
		if camera then
			viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
		end
		refit()
	end

	table.insert(conns, CollectionService:GetInstanceAddedSignal(tag):Connect(add))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(tag):Connect(remove))
	table.insert(conns, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera))
	for _, inst in CollectionService:GetTagged(tag) do
		add(inst)
	end
	watchCamera()

	local destroyed = false
	return {
		refit = refit,
		count = function()
			local n = 0
			for _ in entries do
				n += 1
			end
			return n
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			for _, c in conns do
				c:Disconnect()
			end
			if viewportConn then
				viewportConn:Disconnect()
			end
			for gui in entries do
				remove(gui)
			end
		end,
	}
end

return table.freeze(LabelFitView)
