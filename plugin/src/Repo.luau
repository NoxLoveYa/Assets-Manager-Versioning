-- Versions, history and lines of work (branches) for one tracked folder.
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Diff = require(script.Parent.Diff)
local Merge = require(script.Parent.Merge)
local Serializer = require(script.Parent.Serializer)
local Store = require(script.Parent.Store)
local Util = require(script.Parent.Util)

local Repo = {}

local function parentsOf(pkg: string)
	return function(id: string): { string }
		local m = Store.meta(pkg, id)
		return if m then m.parents else {}
	end
end

-- Is version `a` part of the history of version `b`?
function Repo.isAncestor(pkg: string, a: string, b: string): boolean
	return Merge.ancestors(parentsOf(pkg), b)[a] ~= nil
end

-- The line of work this folder is on, and its latest version.
function Repo.current(pkg: string): (string, string?)
	local branch = Store.head(pkg) or Util.placeBranch()
	return branch, Store.tip(pkg, branch)
end

-- Latest versions first, following the main line (up to `limit`).
function Repo.history(pkg: string, tip: string?, limit: number)
	local out, id = {}, tip
	while id and #out < limit do
		local m = Store.meta(pkg, id)
		if not m then
			break
		end
		table.insert(out, m)
		id = m.parents[1]
	end
	return out
end

-- Other lines of work: { name, tip, meta, included } where `included` means nothing to bring in.
function Repo.others(pkg: string, branch: string, tip: string?)
	local out = {}
	local mine = if tip then Merge.ancestors(parentsOf(pkg), tip) else {}
	for name, id in Store.branches(pkg) do
		local meta = Store.meta(pkg, id)
		if name ~= branch and meta then
			table.insert(out, { name = name, tip = id, meta = meta, included = mine[id] ~= nil })
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- What a version changed compared with the one before it.
function Repo.describeVersion(pkg: string, id: string)
	local m = Store.meta(pkg, id)
	local tree = Store.tree(pkg, id)
	if not m or not tree then
		return { added = {}, changed = {}, removed = {}, total = 0 }
	end
	local before = if m.parents[1] then Store.tree(pkg, m.parents[1]) else nil
	return Diff.describe(before or {}, tree)
end

local function finish(recording, ok: boolean)
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
end

-- Yields. Returns { ok = true, id } or { ok = false, message, nothing? }.
function Repo.save(root: Instance, pkg: string, message: string)
	local author = Util.author()
	local recording = ChangeHistoryService:TryBeginRecording("Save version")

	local ok, result = pcall(function()
		local nodes = Serializer.collect(root, true)
		Store.pkg(pkg, true)
		local index = Store.objects(pkg)

		local tree = {}
		for _, node in nodes do
			local text = Serializer.render(node)
			if #text > Util.MAX_SOURCE then
				return {
					ok = false,
					message = `"{node.name}" is too big to save (a single item can't hold that much data). Split it up or move it out of the tracked folder.`,
				}
			end
			local hash = Util.hash(Util.norm(text))
			Store.putObject(pkg, index, hash, text)
			tree[node.id] = { h = hash, n = node.name, p = node.parentId }
		end

		local branch, tip = Repo.current(pkg)
		local old = if tip then Store.tree(pkg, tip) else nil
		if old and Diff.equal(old, tree) then
			return { ok = false, nothing = true, message = "Nothing changed since the latest version." }
		end

		local id = Util.newId()
		Store.writeCommit(pkg, {
			id = id,
			parents = if tip then { tip } else {},
			message = if message ~= "" then message else "Saved version",
			author = author,
			time = os.time(),
			tree = tree,
		})
		Store.setBranch(pkg, branch, id)
		Store.setHead(pkg, branch)
		return { ok = true, id = id }
	end)

	finish(recording, ok and result.ok)
	if not ok then
		return { ok = false, message = "Something went wrong while saving: " .. tostring(result) }
	end
	return result
end

-- Re-attach a folder that has history but is not in the Explorer: continue this place's own
-- line if it has one, otherwise start it from the newest version. Returns the tree to restore.
function Repo.adopt(pkg: string)
	local branches = Store.branches(pkg)
	local mine = Util.placeBranch()
	local tip = branches[mine]
	if not tip then
		local newest, newestTime = nil, -1
		for _, id in branches do
			local m = Store.meta(pkg, id)
			if m and m.time > newestTime then
				newest, newestTime = id, m.time
			end
		end
		if not newest then
			return nil
		end
		tip = newest
		Store.setBranch(pkg, mine, tip)
	end
	Store.setHead(pkg, mine)
	return Store.tree(pkg, tip)
end

-- Works out what combining another line into this one needs.
-- kind: "noop" (already included) | "fastforward" | "plan" (has .conflicts) | "error"
function Repo.planMerge(pkg: string, theirsBranch: string)
	local ourBranch, ours = Repo.current(pkg)
	local theirs = Store.tip(pkg, theirsBranch)
	if not ours or not theirs then
		return { kind = "error", message = "Save a version of this folder first." }
	end
	local getParents = parentsOf(pkg)
	if Merge.ancestors(getParents, ours)[theirs] then
		return { kind = "noop" }
	end
	local oursTree, theirsTree = Store.tree(pkg, ours), Store.tree(pkg, theirs)
	if not oursTree or not theirsTree then
		return { kind = "error", message = "A saved version could not be read." }
	end
	if Merge.ancestors(getParents, theirs)[ours] then
		return { kind = "fastforward", ourBranch = ourBranch, theirsBranch = theirsBranch, theirs = theirs, theirsTree = theirsTree }
	end

	local baseId = Merge.base(getParents, ours, theirs)
	local baseTree = if baseId then Store.tree(pkg, baseId) or {} else {}
	local index = Store.objects(pkg)
	local function load(hash: string)
		local data = Store.loadObject(index, hash)
		return if data then Serializer.nodeFromData(data) else nil
	end
	local function put(node)
		local text = Serializer.render(node)
		local hash = Util.hash(Util.norm(text))
		Store.putObject(pkg, index, hash, text)
		return { h = hash, n = node.name, p = node.parentId }
	end
	local merged, conflicts = Merge.plan(baseTree, oursTree, theirsTree, load, put)
	return {
		kind = "plan",
		ourBranch = ourBranch,
		theirsBranch = theirsBranch,
		ours = ours,
		theirs = theirs,
		oursTree = oursTree,
		theirsTree = theirsTree,
		merged = merged,
		conflicts = conflicts,
	}
end

-- Writes the combined version. Returns { id, tree, dropped }.
function Repo.finishMerge(pkg: string, plan, choices)
	local author = Util.author()
	Merge.resolve(plan.merged, plan.conflicts, choices)
	local tree, dropped = Merge.prune(plan.merged)
	local id = Util.newId()
	Store.writeCommit(pkg, {
		id = id,
		parents = { plan.ours, plan.theirs },
		message = `Combined with {plan.theirsBranch}`,
		author = author,
		time = os.time(),
		tree = tree,
	})
	Store.setBranch(pkg, plan.ourBranch, id)
	return { id = id, tree = tree, dropped = dropped }
end

function Repo.fastForward(pkg: string, plan)
	Store.setBranch(pkg, plan.ourBranch, plan.theirs)
	return { id = plan.theirs, tree = plan.theirsTree, dropped = 0 }
end

return Repo
