-- Immediate-mode panel: every state change rebuilds the view, which keeps theming and
-- state handling trivial.
local G = Enum.StudioStyleGuideColor

local GREEN = Color3.fromRGB(76, 175, 80)
local ORANGE = Color3.fromRGB(235, 155, 30)
local RED = Color3.fromRGB(226, 82, 82)
local MAX_LISTED = 12

local UI = {}
UI.__index = UI

-- Instance names go into rich text labels, so markup characters must be escaped.
function UI.esc(s: string): string
	local out = s:gsub("&", "&amp;")
	out = out:gsub("<", "&lt;")
	out = out:gsub(">", "&gt;")
	return out
end

local function theme(c: Enum.StudioStyleGuideColor): Color3
	return settings().Studio.Theme:GetColor(c)
end

local function padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

local function stack(parent: Instance, gap: number)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap)
	l.Parent = parent
end

local function label(parent: Instance, text: string, opts: { size: number?, bold: boolean?, color: Color3? }?)
	opts = opts or {}
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1, 0, 0, 0)
	l.TextWrapped = true
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Font = if opts.bold then Enum.Font.BuilderSansBold else Enum.Font.BuilderSans
	l.TextSize = opts.size or 15
	l.TextColor3 = opts.color or theme(G.MainText)
	l.Text = text
	l.Parent = parent
	return l
end

local function card(parent: Instance, accent: Color3?)
	local f = Instance.new("Frame")
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.Size = UDim2.new(1, 0, 0, 0)
	f.BackgroundColor3 = theme(G.InputFieldBackground)
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent or theme(G.Border)
	stroke.Parent = f
	padding(f, 12)
	stack(f, 8)
	f.Parent = parent
	return f
end

local function row(parent: Instance)
	local r = Instance.new("Frame")
	r.BackgroundTransparency = 1
	r.AutomaticSize = Enum.AutomaticSize.Y
	r.Size = UDim2.new(1, 0, 0, 0)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Wraps = true
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, 8)
	l.Parent = r
	r.Parent = parent
	return r
end

-- kind: "primary" | "secondary" | "danger"
local function button(parent: Instance, text: string, kind: string, enabled: boolean, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.new(0, 0, 0, 32)
	b.AutoButtonColor = enabled
	b.BorderSizePixel = 0
	b.Font = Enum.Font.BuilderSansBold
	b.TextSize = 15
	b.Text = text
	if kind == "primary" then
		b.BackgroundColor3 = theme(G.DialogMainButton)
		b.TextColor3 = theme(G.DialogMainButtonText)
	elseif kind == "danger" then
		b.BackgroundColor3 = RED
		b.TextColor3 = Color3.new(1, 1, 1)
	else
		b.BackgroundColor3 = theme(G.Button)
		b.TextColor3 = theme(G.ButtonText)
	end
	if not enabled then
		b.BackgroundTransparency = 0.6
		b.TextTransparency = 0.5
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = b
	b.Parent = parent
	if enabled then
		b.Activated:Connect(onClick)
	end
	return b
end

local function dim(): Color3
	return theme(G.SubText)
end

local function plural(n: number, one: string, many: string): string
	return `{n} {if n == 1 then one else many}`
end

local function listPaths(parent: Instance, title: string, color: Color3, paths: { string })
	if #paths == 0 then
		return
	end
	label(parent, `<b>{title}</b> ({#paths})`, { color = color })
	local lines = {}
	for i = 1, math.min(#paths, MAX_LISTED) do
		table.insert(lines, "  " .. UI.esc(paths[i]))
	end
	if #paths > MAX_LISTED then
		table.insert(lines, `  ...and {#paths - MAX_LISTED} more`)
	end
	label(parent, table.concat(lines, "\n"), { size = 13, color = dim() })
end

function UI.new(widget: DockWidgetPluginGui, handlers)
	local self = setmetatable({}, UI)
	self.handlers = handlers

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	padding(scroll, 12)
	stack(scroll, 12)
	scroll.Parent = widget
	self.scroll = scroll

	settings().Studio.ThemeChanged:Connect(function()
		self:render()
	end)
	return self
end

function UI:selectionBlock(parent: Instance, buttonText: string)
	local s = self.state.selection
	label(parent, (if s.ok then "✓ " else "") .. UI.esc(s.message), { color = if s.ok then GREEN else dim(), size = 14 })
	button(parent, buttonText, "primary", s.ok == true and not self.state.busy, self.handlers.onTrack)
end

function UI:trackedCard(parent: Instance, e)
	local h = self.handlers
	local color, text
	if e.busy then
		color, text = dim(), "Working..."
	elseif e.status == "checking" then
		color, text = dim(), "Checking for changes..."
	elseif e.status == "error" then
		color, text = RED, "Couldn't check this folder: " .. tostring(e.error)
	elseif e.status == "unsaved" then
		color, text = ORANGE, "No snapshot yet. Press <b>Save snapshot</b> to keep a first copy."
	elseif e.status == "clean" then
		color, text = GREEN, "Up to date. Matches the last snapshot."
	else
		color, text = ORANGE, plural(e.diff.total, "difference", "differences") .. " from the last snapshot."
	end

	local c = card(parent, if e.status == "dirty" or e.status == "unsaved" then color else nil)
	label(c, e.name, { size = 18, bold = true })
	label(c, UI.esc(e.root:GetFullName()), { size = 12, color = dim() })
	label(c, "● " .. text, { color = color })

	local idle = not e.busy and (e.status == "dirty" or e.status == "unsaved")
	local buttons = row(c)
	button(buttons, "Save snapshot", "primary", idle, function()
		h.onSnapshot(e)
	end)
	if e.status == "dirty" then
		button(buttons, if e.showChanges then "Hide differences" else "See differences", "secondary", not e.busy, function()
			h.onToggleChanges(e)
		end)
		button(buttons, "Restore snapshot", "secondary", not e.busy and not e.confirmRestore, function()
			h.onAskRestore(e)
		end)
	end

	if e.confirmRestore then
		label(
			c,
			"<b>Replace this folder with the last snapshot?</b>\nEverything you changed since then is lost. You can still undo with Ctrl+Z.",
			{ color = ORANGE, size = 14 }
		)
		local confirm = row(c)
		button(confirm, "Yes, restore", "danger", true, function()
			h.onRestore(e)
		end)
		button(confirm, "Cancel", "secondary", true, function()
			h.onCancelRestore(e)
		end)
	end

	if e.showChanges and e.status == "dirty" then
		listPaths(c, "New in your folder", GREEN, e.diff.added)
		listPaths(c, "Changed", ORANGE, e.diff.changed)
		listPaths(c, "Missing from your folder", RED, e.diff.removed)
	end
end

function UI:render()
	local s = self.state
	if not s then
		return
	end
	local scroll = self.scroll
	local position = scroll.CanvasPosition

	for _, child in scroll:GetChildren() do
		if not (child:IsA("UIListLayout") or child:IsA("UIPadding")) then
			child:Destroy()
		end
	end
	scroll.BackgroundColor3 = theme(G.MainBackground)

	label(scroll, "Asset Versioning", { size = 22, bold = true })
	label(
		scroll,
		"Keeps a history of your asset folders so your team can see what changed, go back, and merge work from different places.",
		{ color = dim(), size = 14 }
	)

	if s.toast then
		local color = if s.toast.kind == "error" then RED elseif s.toast.kind == "success" then GREEN else dim()
		local t = card(scroll, color)
		label(t, s.toast.text, { color = color })
		button(t, "OK", "secondary", true, self.handlers.onDismissToast)
	end

	local hasAny = #s.tracked > 0 or #s.available > 0

	if not hasAny then
		local c = card(scroll)
		label(c, "Let's get started", { size = 18, bold = true })
		label(c, "<b>1.</b>  In the Explorer, click the folder that holds your assets (for example <i>Props</i>).")
		label(c, "<b>2.</b>  Press the button below. We save the first snapshot for you.")
		self:selectionBlock(c, "Track this folder")
	end

	for _, e in s.tracked do
		self:trackedCard(scroll, e)
	end

	if #s.available > 0 then
		local c = card(scroll)
		label(c, "Found in your project", { size = 18, bold = true })
		label(c, "These asset folders are saved in the project but aren't in this place yet.", { color = dim(), size = 14 })
		for _, name in s.available do
			local r = row(c)
			label(r, name, { bold = true }).Size = UDim2.new(1, -150, 0, 32)
			button(r, "Add to this place", "primary", not s.busy, function()
				self.handlers.onLoad(name)
			end)
		end
	end

	if hasAny then
		local c = card(scroll)
		label(c, "Track another folder", { size = 16, bold = true })
		self:selectionBlock(c, "Track this folder")
	end

	local share = card(scroll)
	label(share, "Sharing with your team", { size = 16, bold = true })
	label(
		share,
		"After <b>Save snapshot</b>:\n<b>1.</b>  Save your place (Ctrl+S).\n<b>2.</b>  Double-click <b>Save Versions.bat</b> in your project folder.\n<b>3.</b>  Teammates get your changes, then press <b>Restore snapshot</b> here.",
		{ size = 14 }
	)

	task.defer(function()
		scroll.CanvasPosition = position
	end)
end

function UI:setState(state)
	self.state = state
	self:render()
end

return UI
