-- Compares a live folder with its last snapshot.
local Serializer = require(script.Parent.Serializer)
local Store = require(script.Parent.Store)
local Util = require(script.Parent.Util)

local Status = {}

local function relPath(root: Instance, inst: Instance): string
	if inst == root then
		return root.Name .. " (the folder itself)"
	end
	local parts = {}
	local p: Instance? = inst
	while p and p ~= root do
		table.insert(parts, 1, p.Name)
		p = p.Parent
	end
	return table.concat(parts, "/")
end

-- Yields. Returns { added, changed, removed (lists of readable paths), stored (module count), total }.
function Status.compute(root: Instance, pkg: string)
	local nodes = Serializer.collect(root, false, 120)
	local stored = Store.read(pkg)

	local storedCount = 0
	for _ in stored do
		storedCount += 1
	end

	local result = { added = {}, changed = {}, removed = {}, stored = storedCount, total = 0 }
	local seen = {}
	for _, node in nodes do
		seen[node.id] = true
		local rec = stored[node.id]
		if not rec then
			table.insert(result.added, relPath(root, node.inst))
		elseif Util.norm(rec.source) ~= Util.norm(Serializer.render(node)) then
			table.insert(result.changed, relPath(root, node.inst))
		end
	end
	for id, rec in stored do
		if not seen[id] then
			table.insert(result.removed, rec.label)
		end
	end

	table.sort(result.added)
	table.sort(result.changed)
	table.sort(result.removed)
	result.total = #result.added + #result.changed + #result.removed
	return result
end

return Status
