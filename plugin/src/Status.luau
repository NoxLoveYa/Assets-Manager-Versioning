-- Compares a live folder with its latest saved version.
local Diff = require(script.Parent.Diff)
local Repo = require(script.Parent.Repo)
local Serializer = require(script.Parent.Serializer)
local Store = require(script.Parent.Store)
local Util = require(script.Parent.Util)

local Status = {}

-- Yields. Returns Diff.describe's result plus `versions` (false when nothing was saved yet).
function Status.compute(root: Instance, pkg: string)
	local nodes = Serializer.collect(root, false, 120)
	local live = {}
	for _, node in nodes do
		live[node.id] = {
			h = Util.hash(Util.norm(Serializer.render(node))),
			n = node.name,
			p = node.parentId,
		}
	end

	local _, tip = Repo.current(pkg)
	local saved = if tip then Store.tree(pkg, tip) else nil
	if not saved then
		return { versions = false, added = {}, changed = {}, removed = {}, total = 0 }
	end
	local result = Diff.describe(saved, live)
	result.versions = true
	return result
end

return Status
