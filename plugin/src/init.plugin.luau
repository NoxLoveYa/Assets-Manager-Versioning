local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")

local Restore = require(script.Restore)
local Snapshot = require(script.Snapshot)
local Status = require(script.Status)
local Store = require(script.Store)
local UI = require(script.UI)
local Util = require(script.Util)

local esc = UI.esc

local toolbar = plugin:CreateToolbar("Asset Versioning")
local toggle = toolbar:CreateButton("Versioning", "Save, compare and restore your asset folders", "", "Versioning")
toggle.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"AssetVersioning",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Left, false, false, 360, 600, 300, 300)
)
widget.Title = "Asset Versioning"
widget.Name = "AssetVersioning"

local entries = {} -- package name -> persistent card state
local state = { tracked = {}, available = {}, selection = {}, toast = nil, busy = false }
local ui

local function render()
	ui:setState(state)
end

local toastToken = 0
local function toast(text: string, kind: string)
	toastToken += 1
	local mine = toastToken
	state.toast = { text = text, kind = kind }
	render()
	if kind ~= "error" then
		task.delay(15, function()
			if toastToken == mine then
				state.toast = nil
				render()
			end
		end)
	end
end

local function refreshList()
	local roots = {}
	for _, inst in CollectionService:GetTagged(Util.ROOT_TAG) do
		local pkg = inst:GetAttribute(Util.PKG_ATTR)
		if type(pkg) == "string" and not roots[pkg] and inst:IsDescendantOf(game) then
			roots[pkg] = inst
		end
	end

	state.tracked = {}
	for name, root in roots do
		local e = entries[name] or { name = name, status = "checking" }
		e.root = root
		entries[name] = e
		table.insert(state.tracked, e)
	end
	for name in entries do
		if not roots[name] then
			entries[name] = nil
		end
	end
	table.sort(state.tracked, function(a, b)
		return a.name < b.name
	end)

	state.available = {}
	for _, name in Store.packages() do
		if not roots[name] then
			table.insert(state.available, name)
		end
	end
end

local function check(e)
	e.token = (e.token or 0) + 1
	local mine = e.token
	task.spawn(function()
		local ok, result = pcall(Status.compute, e.root, e.name)
		if e.token ~= mine or e.busy then
			return
		end
		if ok then
			e.diff = result
			e.status = if result.stored == 0 then "unsaved" elseif result.total == 0 then "clean" else "dirty"
			if e.status ~= "dirty" then
				e.showChanges = false
			end
		else
			e.status = "error"
			e.error = tostring(result)
		end
		render()
	end)
end

local recheckToken = 0
local function recheckSoon(delaySeconds: number?)
	recheckToken += 1
	local mine = recheckToken
	task.delay(delaySeconds or 0.8, function()
		if mine == recheckToken and widget.Enabled then
			for _, e in state.tracked do
				if not e.busy then
					check(e)
				end
			end
		end
	end)
end

local function validate(inst: Instance): (boolean, string)
	if inst.Parent == game or inst == game then
		return false, "Pick a folder inside a service, not the service itself."
	end
	local store = Store.folder()
	if store and (inst == store or inst:IsDescendantOf(store)) then
		return false, "That's where snapshots are stored. Pick your asset folder instead."
	end
	if CollectionService:HasTag(inst, Util.ROOT_TAG) then
		return false, inst.Name .. " is already tracked."
	end
	local p = inst.Parent
	while p and p ~= game do
		if CollectionService:HasTag(p, Util.ROOT_TAG) then
			return false, inst.Name .. " is inside the tracked folder " .. p.Name .. "."
		end
		p = p.Parent
	end
	for _, d in inst:GetDescendants() do
		if CollectionService:HasTag(d, Util.ROOT_TAG) then
			return false, inst.Name .. " contains the tracked folder " .. d.Name .. "."
		end
	end
	return true, `Ready: {inst:GetFullName()} ({#inst:GetDescendants() + 1} items)`
end

local function updateSelection()
	local sel = Selection:Get()
	if #sel == 0 then
		state.selection = { ok = false, message = "Nothing selected yet. Click your asset folder in the Explorer." }
	elseif #sel > 1 then
		state.selection = { ok = false, message = "Several things are selected. Click just one folder." }
	else
		local ok, message = validate(sel[1])
		state.selection = { ok = ok, message = message, inst = sel[1] }
	end
end

local function snapshot(e)
	e.busy = true
	e.confirmRestore = false
	render()
	task.spawn(function()
		local result = Snapshot.save(e.root, e.name)
		e.busy = false
		if result.ok then
			toast(
				`Snapshot of "{esc(e.name)}" saved. Now save your place (Ctrl+S) and double-click Save Versions.bat.`,
				"success"
			)
		else
			toast(esc(result.message), "error")
		end
		check(e)
	end)
end

local function describeProblems(result, doneText: string)
	local text = doneText
	if #result.failures > 0 then
		local shown = {}
		for i = 1, math.min(#result.failures, 4) do
			table.insert(shown, esc(result.failures[i]))
		end
		text ..= `\n\n{#result.failures} setting(s) could not be applied, for example: {table.concat(shown, ", ")}.`
	end
	if #result.unreadable > 0 then
		text ..= `\n\n{#result.unreadable} snapshot file(s) could not be read: {esc(table.concat(result.unreadable, ", "))}. Check the project for merge conflicts.`
	end
	return text, if #result.failures > 0 or #result.unreadable > 0 then "info" else "success"
end

local function restore(e)
	e.busy = true
	e.confirmRestore = false
	render()
	task.spawn(function()
		local result = Restore.run(e.name, e.root)
		e.busy = false
		if result.ok then
			local text, kind = describeProblems(result, `"{esc(e.name)}" now matches the last snapshot.`)
			toast(text, kind)
		else
			toast(esc(result.message), "error")
		end
		refreshList()
		for _, other in state.tracked do
			check(other)
		end
	end)
end

local function load(name: string)
	state.busy = true
	render()
	task.spawn(function()
		local result = Restore.run(name, nil)
		state.busy = false
		if result.ok then
			local text, kind = describeProblems(result, `"{esc(name)}" was added to this place.`)
			toast(text, kind)
		else
			toast(esc(result.message), "error")
		end
		refreshList()
		for _, e in state.tracked do
			check(e)
		end
	end)
end

local function track()
	local inst = state.selection.inst
	if not inst or not state.selection.ok or state.busy then
		return
	end
	local pkg = Util.safeName(inst.Name)
	if entries[pkg] or Store.packageFolder(pkg) then
		toast(`There is already a tracked folder called "{esc(pkg)}". Rename yours first so they don't get mixed up.`, "error")
		return
	end

	local recording = ChangeHistoryService:TryBeginRecording("Track folder")
	inst:SetAttribute(Util.PKG_ATTR, pkg)
	CollectionService:AddTag(inst, Util.ROOT_TAG)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	refreshList()
	updateSelection()
	local e = entries[pkg]
	if e then
		snapshot(e)
	end
end

ui = UI.new(widget, {
	onTrack = track,
	onSnapshot = snapshot,
	onRestore = restore,
	onLoad = load,
	onToggleChanges = function(e)
		e.showChanges = not e.showChanges
		render()
	end,
	onAskRestore = function(e)
		e.confirmRestore = true
		render()
	end,
	onCancelRestore = function(e)
		e.confirmRestore = false
		render()
	end,
	onDismissToast = function()
		state.toast = nil
		render()
	end,
})

local function open()
	refreshList()
	updateSelection()
	render()
	recheckSoon(0.1)
end

toggle.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggle:SetActive(widget.Enabled)
	if widget.Enabled then
		open()
	end
end)
toggle:SetActive(widget.Enabled)

Selection.SelectionChanged:Connect(function()
	if widget.Enabled then
		updateSelection()
		render()
	end
end)

local function onTagsChanged()
	if widget.Enabled then
		refreshList()
		updateSelection()
		render()
		recheckSoon(0.3)
	end
end
CollectionService:GetInstanceAddedSignal(Util.ROOT_TAG):Connect(onTagsChanged)
CollectionService:GetInstanceRemovedSignal(Util.ROOT_TAG):Connect(onTagsChanged)

-- Anything undoable may have changed a tracked folder.
ChangeHistoryService.OnRecordingFinished:Connect(function()
	recheckSoon()
end)
ChangeHistoryService.OnUndo:Connect(function()
	recheckSoon()
end)
ChangeHistoryService.OnRedo:Connect(function()
	recheckSoon()
end)

-- Rojo (git pulls, merges) rewrites snapshot files without any undo step, so watch for that.
task.spawn(function()
	local last = Store.signature()
	while true do
		task.wait(2)
		if widget.Enabled then
			local now = Store.signature()
			if now ~= last then
				last = now
				refreshList()
				render()
				recheckSoon(0.3)
			end
		end
	end
end)

if widget.Enabled then
	open()
end
