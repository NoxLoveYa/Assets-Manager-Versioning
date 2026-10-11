-- Immediate-mode panel: every state change rebuilds the view, which keeps theming and
-- state handling trivial.
local Diff = require(script.Parent.Diff)
local Util = require(script.Parent.Util)

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
local esc = UI.esc

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
		table.insert(lines, "  " .. esc(paths[i]))
	end
	if #paths > MAX_LISTED then
		table.insert(lines, `  ...and {#paths - MAX_LISTED} more`)
	end
	label(parent, table.concat(lines, "\n"), { size = 13, color = dim() })
end

local function listDiff(parent: Instance, d)
	if d.total == 0 then
		label(parent, "No changes to items.", { size = 13, color = dim() })
		return
	end
	listPaths(parent, "New", GREEN, d.added)
	listPaths(parent, "Changed", ORANGE, d.changed)
	listPaths(parent, "Removed", RED, d.removed)
end

-- A text box. Re-rendering while it has focus would throw the text away, so render() waits.
function UI:input(parent: Instance, placeholder: string, text: string, onChange: (string) -> ())
	local t = Instance.new("TextBox")
	t.Size = UDim2.new(1, 0, 0, 32)
	t.ClearTextOnFocus = false
	t.PlaceholderText = placeholder
	t.Text = text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Font = Enum.Font.BuilderSans
	t.TextSize = 15
	t.BackgroundColor3 = theme(G.InputFieldBackground)
	t.TextColor3 = theme(G.MainText)
	t.PlaceholderColor3 = dim()
	t.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = t
	local stroke = Instance.new("UIStroke")
	stroke.Color = theme(G.InputFieldBorder)
	stroke.Parent = t
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = t
	t.Parent = parent

	t:GetPropertyChangedSignal("Text"):Connect(function()
		onChange(t.Text)
	end)
	t.Focused:Connect(function()
		self.typing = true
	end)
	t.FocusLost:Connect(function()
		self.typing = false
		if self.pendingRender then
			self.pendingRender = false
			-- A click on a button also ends the typing; give it time to land first.
			task.delay(0.25, function()
				if not self.typing then
					self:render()
				end
			end)
		end
	end)
	return t
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
	label(parent, (if s.ok then "✓ " else "") .. esc(s.message), { color = if s.ok then GREEN else dim(), size = 14 })
	button(parent, buttonText, "primary", s.ok == true and not self.state.busy, self.handlers.onTrack)
end

function UI:mergeBlock(c: Instance, e)
	local h = self.handlers
	local p = e.pending
	label(c, `<b>Combining "{esc(p.plan.theirsBranch)}" into "{esc(p.plan.ourBranch)}"</b>`)
	label(c, "These items were changed in both places. Pick the one to keep for each:", { size = 14, color = dim() })
	local all = true
	for _, cf in p.plan.conflicts do
		local path = Diff.path(if cf.ours then p.plan.oursTree else p.plan.theirsTree, cf.id)
		local reason = if not cf.ours
			then "deleted in yours, changed in theirs"
			elseif not cf.theirs then "changed in yours, deleted in theirs"
			else "changed in both"
		label(c, `<b>{esc(path)}</b>  {reason}`, { size = 14 })
		local choice = p.choices[cf.id]
		if not choice then
			all = false
		end
		local r = row(c)
		button(r, "Keep mine", if choice == "ours" then "primary" else "secondary", true, function()
			h.onChoose(e, cf.id, "ours")
		end)
		button(r, "Use theirs", if choice == "theirs" then "primary" else "secondary", true, function()
			h.onChoose(e, cf.id, "theirs")
		end)
	end
	local r = row(c)
	button(r, "Finish combining", "primary", all and not e.busy, function()
		h.onFinishMerge(e)
	end)
	button(r, "Cancel", "secondary", not e.busy, function()
		h.onCancelMerge(e)
	end)
end

function UI:trackedCard(parent: Instance, e)
	local h = self.handlers
	local dirty = e.status == "dirty"
	local unsaved = e.status == "unsaved"
	local idle = not e.busy

	local color, text
	if e.busy then
		color, text = dim(), "Working..."
	elseif e.status == "checking" then
		color, text = dim(), "Checking for changes..."
	elseif e.status == "error" then
		color, text = RED, "Couldn't check this folder: " .. tostring(e.error)
	elseif unsaved then
		color, text = ORANGE, "No version saved yet. Press <b>Save version</b> to keep a first copy."
	elseif e.status == "clean" then
		color, text = GREEN, "Up to date. Matches your latest version."
	else
		color, text = ORANGE, plural(e.diff.total, "change", "changes") .. " since your latest version."
	end

	local c = card(parent, if dirty or unsaved then color else nil)
	label(c, esc(e.name), { size = 18, bold = true })
	label(c, esc(e.root:GetFullName()) .. "  ·  line: " .. esc(e.branch or "?"), { size = 12, color = dim() })
	label(c, "● " .. text, { color = color })

	if e.pending then
		self:mergeBlock(c, e)
		return
	end

	if idle and (dirty or unsaved) then
		self:input(c, "What did you change? (optional)", e.message or "", function(t)
			e.message = t
		end)
	end
	local buttons = row(c)
	button(buttons, "Save version", "primary", idle and (dirty or unsaved), function()
		h.onSave(e)
	end)
	if dirty then
		button(buttons, if e.showChanges then "Hide changes" else "See changes", "secondary", idle, function()
			h.onToggleChanges(e)
		end)
		button(buttons, "Discard changes", "secondary", idle and not e.confirmDiscard, function()
			h.onAskDiscard(e)
		end)
	end

	if e.confirmDiscard then
		label(
			c,
			"<b>Throw away your changes and go back to the latest version?</b>\nYou can still undo with Ctrl+Z.",
			{ color = ORANGE, size = 14 }
		)
		local r = row(c)
		button(r, "Yes, discard", "danger", true, function()
			h.onDiscard(e)
		end)
		button(r, "Cancel", "secondary", true, function()
			h.onCancelDiscard(e)
		end)
	end

	if e.showChanges and dirty then
		listPaths(c, "New in your folder", GREEN, e.diff.added)
		listPaths(c, "Changed", ORANGE, e.diff.changed)
		listPaths(c, "Missing from your folder", RED, e.diff.removed)
	end

	if not unsaved then
		local more = row(c)
		button(more, if e.showHistory then "Hide history" else "History", "secondary", idle, function()
			h.onToggleHistory(e)
		end)
		if #e.others > 0 then
			button(more, if e.showCombine then "Hide combine" else "Combine with another line", "secondary", idle, function()
				h.onToggleCombine(e)
			end)
		end
		button(more, "Export to file", "secondary", idle, function()
			h.onExport(e)
		end)
	end

	if e.showHistory then
		label(c, "<b>History</b> (latest first)")
		for i, m in e.history do
			label(
				c,
				`<b>{esc(m.message)}</b>{if i == 1 then "  (latest)" else ""}\n{esc(m.author)} · {Util.timeText(m.time)}`,
				{ size = 14 }
			)
			local r = row(c)
			button(r, if e.openVersion == m.id then "Hide changes" else "What changed", "secondary", idle, function()
				h.onOpenVersion(e, m.id)
			end)
			button(r, "Go back to this", "secondary", idle and e.confirmGoTo ~= m.id, function()
				h.onAskGoTo(e, m.id)
			end)
			if e.openVersion == m.id and e.versionDiff then
				listDiff(c, e.versionDiff)
			end
			if e.confirmGoTo == m.id then
				label(
					c,
					"<b>Replace this folder with that version?</b>\nUnsaved changes are lost. You can still undo with Ctrl+Z, and your saved versions stay.",
					{ color = ORANGE, size = 14 }
				)
				local confirm = row(c)
				button(confirm, "Yes, go back", "danger", true, function()
					h.onGoTo(e, m.id)
				end)
				button(confirm, "Cancel", "secondary", true, function()
					h.onCancelGoTo(e)
				end)
			end
		end
	end

	if e.showCombine then
		label(c, "<b>Combine</b>")
		label(c, "Bring the work from another place or line into this folder.", { size = 14, color = dim() })
		if e.status ~= "clean" then
			label(c, "Save a version first, so nothing you did is lost.", { size = 14, color = ORANGE })
		end
		for _, o in e.others do
			label(
				c,
				`<b>{esc(o.name)}</b>\nlatest: {esc(o.meta.message)} · {esc(o.meta.author)} · {Util.timeText(o.meta.time)}`,
				{ size = 14 }
			)
			if o.included then
				label(c, "Already included in your folder.", { size = 13, color = dim() })
			else
				button(c, "Combine into mine", "primary", e.status == "clean" and idle, function()
					h.onMerge(e, o.name)
				end)
			end
		end
	end
end

function UI:render()
	local s = self.state
	if not s then
		return
	end
	if self.typing then
		self.pendingRender = true
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
		"Keeps a history of your asset folders so you can see what changed, go back, and combine work from different places.",
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
		label(c, "<b>2.</b>  Press the button below. We save the first version for you.")
		self:selectionBlock(c, "Track this folder")
	end

	for _, e in s.tracked do
		self:trackedCard(scroll, e)
	end

	if #s.available > 0 then
		local c = card(scroll)
		label(c, "Saved folders not in this place", { size = 18, bold = true })
		label(
			c,
			"These folders have saved versions here (for example from an imported file) but aren't in the Explorer yet.",
			{ color = dim(), size = 14 }
		)
		for _, name in s.available do
			local r = row(c)
			label(r, esc(name), { bold = true }).Size = UDim2.new(1, -150, 0, 32)
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
		"<b>Same Team Create place:</b> nothing to do, everyone sees the same history.\n<b>Different places:</b> press <b>Export to file</b> on a folder, open the other place, press <b>Import a file</b> below, then use <b>Combine</b>.\nOnly import files from people you trust.",
		{ size = 14 }
	)
	button(share, "Import a file", "secondary", not s.busy, self.handlers.onImport)

	task.defer(function()
		scroll.CanvasPosition = position
	end)
end

function UI:setState(state)
	self.state = state
	self:render()
end

return UI
