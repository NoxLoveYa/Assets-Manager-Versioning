local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")

local Bundle = require(script.Bundle)
local Repo = require(script.Repo)
local Restore = require(script.Restore)
local Status = require(script.Status)
local Store = require(script.Store)
local UI = require(script.UI)
local Util = require(script.Util)

local esc = UI.esc

local toolbar = plugin:CreateToolbar("Asset Versioning")
local toggle = toolbar:CreateButton("Versioning", "Save, compare and restore your asset folders", "", "Versioning")
toggle.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync(
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
		local e = entries[name] or { name = name, status = "checking", history = {}, others = {}, message = "" }
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
		local ok, result = pcall(function()
			local diff = Status.compute(e.root, e.name)
			local branch, tip = Repo.current(e.name)
			return {
				diff = diff,
				branch = branch,
				tip = tip,
				history = Repo.history(e.name, tip, 15),
				others = Repo.others(e.name, branch, tip),
			}
		end)
		if e.token ~= mine or e.busy then
			return
		end
		if ok then
			e.diff, e.branch, e.tip, e.history, e.others = result.diff, result.branch, result.tip, result.history, result.others
			e.status = if not result.diff.versions then "unsaved" elseif result.diff.total == 0 then "clean" else "dirty"
			if e.status ~= "dirty" then
				e.showChanges = false
				e.confirmDiscard = false
			end
		else
			e.status = "error"
			e.error = tostring(result)
		end
		render()
	end)
end

local function checkAll()
	for _, e in state.tracked do
		check(e)
	end
end

local recheckToken = 0
local function recheckSoon(delaySeconds: number?)
	recheckToken += 1
	local mine = recheckToken
	task.delay(delaySeconds or 0.8, function()
		if mine == recheckToken and widget.Enabled then
			for _, e in state.tracked do
				if not e.busy and not e.pending then
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
	local store = Store.root()
	if store and (inst == store or inst:IsDescendantOf(store)) then
		return false, "That's where versions are stored. Pick your asset folder instead."
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
		text ..= `\n\n{#result.unreadable} saved item(s) could not be read: {esc(table.concat(result.unreadable, ", "))}.`
	end
	return text, if #result.failures > 0 or #result.unreadable > 0 then "info" else "success"
end

local function save(e)
	e.busy = true
	e.confirmDiscard = false
	render()
	task.spawn(function()
		local result = Repo.save(e.root, e.name, e.message or "")
		e.busy = false
		if result.ok then
			e.message = ""
			toast(`Version of "{esc(e.name)}" saved.`, "success")
		elseif result.nothing then
			toast(result.message, "info")
		else
			toast(esc(result.message), "error")
		end
		check(e)
	end)
end

-- Makes the live folder match `tree`.
local function applyTree(e, tree, doneText: string)
	e.busy = true
	e.confirmDiscard = false
	e.confirmGoTo = nil
	render()
	task.spawn(function()
		local result = Restore.run(e.name, e.root, tree)
		e.busy = false
		if result.ok then
			local text, kind = describeProblems(result, doneText)
			toast(text, kind)
		else
			toast(esc(result.message), "error")
		end
		refreshList()
		checkAll()
	end)
end

local function finishMerge(e, plan, choices)
	e.busy = true
	render()
	task.spawn(function()
		local ok, res = pcall(function()
			if plan.kind == "fastforward" then
				return Repo.fastForward(e.name, plan)
			end
			return Repo.finishMerge(e.name, plan, choices)
		end)
		if not ok then
			e.busy, e.pending = false, nil
			toast("Combining failed, nothing was changed: " .. esc(tostring(res)), "error")
			check(e)
			return
		end
		local restored = Restore.run(e.name, e.root, res.tree)
		e.busy, e.pending, e.showCombine = false, nil, false
		if restored.ok then
			local done = `Combined "{esc(plan.theirsBranch)}" into "{esc(plan.ourBranch)}".`
			if res.dropped > 0 then
				done ..= `\n{res.dropped} item(s) were left out because their folder was deleted on one side.`
			end
			local text, kind = describeProblems(restored, done)
			toast(text, kind)
		else
			toast("The versions were combined but the folder couldn't be updated: " .. esc(restored.message), "error")
		end
		refreshList()
		checkAll()
	end)
end

local function startMerge(e, theirsBranch: string)
	e.busy = true
	render()
	task.spawn(function()
		local ok, plan = pcall(Repo.planMerge, e.name, theirsBranch)
		e.busy = false
		if not ok then
			toast("Couldn't combine: " .. esc(tostring(plan)), "error")
			check(e)
		elseif plan.kind == "error" then
			toast(esc(plan.message), "error")
			check(e)
		elseif plan.kind == "noop" then
			toast("Everything from that line is already in your folder.", "info")
			check(e)
		elseif plan.kind == "plan" and #plan.conflicts > 0 then
			e.pending = { plan = plan, choices = {} }
			render()
		else
			finishMerge(e, plan, {})
		end
	end)
end

local function load(name: string)
	state.busy = true
	render()
	task.spawn(function()
		local ok, result = pcall(function()
			local tree = Repo.adopt(name)
			if not tree then
				return { ok = false, message = "That folder's history could not be read." }
			end
			return Restore.run(name, nil, tree)
		end)
		state.busy = false
		if ok and result.ok then
			local text, kind = describeProblems(result, `"{esc(name)}" was added to this place.`)
			toast(text, kind)
		else
			toast(esc(if ok then result.message else tostring(result)), "error")
		end
		refreshList()
		checkAll()
	end)
end

local function track()
	local inst = state.selection.inst
	if not inst or not state.selection.ok or state.busy then
		return
	end
	local pkg = Util.safeName(inst.Name)
	if entries[pkg] or Store.pkg(pkg) then
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
		e.message = "First version"
		save(e)
	end
end

local function exportFile(e)
	task.spawn(function()
		local result = Bundle.export(plugin, e.name)
		if not result.cancelled then
			toast(esc(result.message), if result.ok then "success" else "error")
		end
	end)
end

local function importFile()
	state.busy = true
	render()
	task.spawn(function()
		local result = Bundle.import()
		state.busy = false
		if result.ok then
			local lines = {}
			for _, i in result.imported do
				table.insert(lines, `"{esc(i.name)}": {i.versions} new version(s)`)
			end
			toast("Imported. " .. table.concat(lines, ", ") .. ".\nUse Combine on a folder, or Add to this place below.", "success")
		elseif result.cancelled then
			render()
		else
			toast(esc(result.message), "error")
		end
		refreshList()
		checkAll()
	end)
end

ui = UI.new(widget, {
	onTrack = track,
	onSave = save,
	onLoad = load,
	onExport = exportFile,
	onImport = importFile,
	onToggleChanges = function(e)
		e.showChanges = not e.showChanges
		render()
	end,
	onAskDiscard = function(e)
		e.confirmDiscard = true
		render()
	end,
	onCancelDiscard = function(e)
		e.confirmDiscard = false
		render()
	end,
	onDiscard = function(e)
		local tree = if e.tip then Store.tree(e.name, e.tip) else nil
		if tree then
			applyTree(e, tree, `"{esc(e.name)}" is back to its latest version.`)
		else
			toast("The latest version could not be read.", "error")
		end
	end,
	onToggleHistory = function(e)
		e.showHistory = not e.showHistory
		e.openVersion, e.versionDiff, e.confirmGoTo = nil, nil, nil
		render()
	end,
	onOpenVersion = function(e, id)
		if e.openVersion == id then
			e.openVersion, e.versionDiff = nil, nil
		else
			e.openVersion, e.versionDiff = id, Repo.describeVersion(e.name, id)
		end
		render()
	end,
	onAskGoTo = function(e, id)
		e.confirmGoTo = id
		render()
	end,
	onCancelGoTo = function(e)
		e.confirmGoTo = nil
		render()
	end,
	onGoTo = function(e, id)
		local tree = Store.tree(e.name, id)
		if tree then
			applyTree(e, tree, `"{esc(e.name)}" now matches that version. Press Save version to keep it as the newest.`)
		else
			toast("That version could not be read.", "error")
		end
	end,
	onToggleCombine = function(e)
		e.showCombine = not e.showCombine
		render()
	end,
	onMerge = startMerge,
	onChoose = function(e, id, side)
		e.pending.choices[id] = side
		render()
	end,
	onFinishMerge = function(e)
		finishMerge(e, e.pending.plan, e.pending.choices)
	end,
	onCancelMerge = function(e)
		e.pending = nil
		render()
		check(e)
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

-- Teammates (Team Create) can add versions at any time, so watch for that.
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
