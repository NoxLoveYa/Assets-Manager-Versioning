-- Compares two version trees. A tree is id -> { h = content hash, n = name, p = parent id }.
local Diff = {}

function Diff.equal(a, b): boolean
	for id, e in a do
		if not b[id] or b[id].h ~= e.h then
			return false
		end
	end
	for id in b do
		if not a[id] then
			return false
		end
	end
	return true
end

-- Readable path of an item, relative to the tracked folder.
function Diff.path(tree, id: string): string
	local e = tree[id]
	if not e then
		return "?"
	end
	local parts, guard = {}, 0
	while e and e.p and guard < 200 do
		table.insert(parts, 1, e.n)
		e = tree[e.p]
		guard += 1
	end
	if #parts == 0 then
		return tree[id].n .. " (the folder itself)"
	end
	return table.concat(parts, "/")
end

-- { added, changed, removed (sorted lists of paths), total }
function Diff.describe(old, new)
	local r = { added = {}, changed = {}, removed = {}, total = 0 }
	for id, e in new do
		local o = old[id]
		if not o then
			table.insert(r.added, Diff.path(new, id))
		elseif o.h ~= e.h then
			table.insert(r.changed, Diff.path(new, id))
		end
	end
	for id in old do
		if not new[id] then
			table.insert(r.removed, Diff.path(old, id))
		end
	end
	table.sort(r.added)
	table.sort(r.changed)
	table.sort(r.removed)
	r.total = #r.added + #r.changed + #r.removed
	return r
end

return Diff
