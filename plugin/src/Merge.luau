-- Three-way merge of two version lines. Pure logic: no Instances, so it can be tested anywhere.
-- Trees are id -> { h = content hash, n = name, p = parent id }.
local Merge = {}

local SEP = "\30"

-- id -> distance (in versions) from `id`, including itself.
function Merge.ancestors(getParents: (string) -> { string }, id: string)
	local dist, queue, head = { [id] = 0 }, { id }, 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for _, p in getParents(cur) do
			if dist[p] == nil then
				dist[p] = dist[cur] + 1
				table.insert(queue, p)
			end
		end
	end
	return dist
end

-- The shared version closest to both lines (nil if they have no common history).
function Merge.base(getParents: (string) -> { string }, a: string, b: string): string?
	local ofA, ofB = Merge.ancestors(getParents, a), Merge.ancestors(getParents, b)
	local best, bestScore
	for id, da in ofA do
		local db = ofB[id]
		if db then
			local score = da + db
			if not bestScore or score < bestScore or (score == bestScore and id < best) then
				best, bestScore = id, score
			end
		end
	end
	return best
end

-- A node as a flat key -> text map, so every field can be merged on its own.
local function flatten(node)
	local f = {
		name = node.name,
		class = node.class,
		parent = node.parentId or "",
		loc = if node.location then table.concat(node.location, SEP) else "",
		source = node.source,
		blob = if node.blob then table.concat(node.blob) else nil,
	}
	for k, v in node.props do
		f["p:" .. k] = v
	end
	for k, v in node.attrs do
		f["a:" .. k] = v
	end
	for _, t in node.tags do
		f["t:" .. t] = "1"
	end
	return f
end

local function unflatten(id: string, f)
	local node = {
		id = id,
		class = f.class,
		name = f.name,
		parentId = if f.parent ~= "" then f.parent else nil,
		props = {},
		attrs = {},
		tags = {},
		source = f.source,
	}
	if node.parentId == nil then
		node.location = if f.loc == "" then {} else string.split(f.loc, SEP)
	end
	if f.blob then
		node.blob = {}
		for i = 1, #f.blob, 120 do
			table.insert(node.blob, f.blob:sub(i, i + 119))
		end
	end
	for k, v in f do
		local kind, rest = k:sub(1, 2), k:sub(3)
		if kind == "p:" then
			node.props[rest] = v
		elseif kind == "a:" then
			node.attrs[rest] = v
		elseif kind == "t:" then
			table.insert(node.tags, rest)
		end
	end
	table.sort(node.tags)
	return node
end

-- nil when the same field was changed differently on both sides.
local function mergeFields(b, o, t)
	b = b or {}
	local keys = {}
	for _, m in { b, o, t } do
		for k in m do
			keys[k] = true
		end
	end
	local out = {}
	for k in keys do
		local bv, ov, tv = b[k], o[k], t[k]
		if ov == tv then
			out[k] = ov
		elseif ov == bv then
			out[k] = tv
		elseif tv == bv then
			out[k] = ov
		else
			return nil
		end
	end
	return out
end

-- load(hash) -> node or nil; put(node) -> tree entry (stores the merged item).
-- Returns the merged tree (without the conflicts) and the list of conflicts.
function Merge.plan(base, ours, theirs, load, put)
	local ids = {}
	for _, tree in { base, ours, theirs } do
		for id in tree do
			ids[id] = true
		end
	end

	local merged, conflicts = {}, {}
	for id in ids do
		local b, o, t = base[id], ours[id], theirs[id]
		local bh, oh, th = b and b.h, o and o.h, t and t.h
		if oh == th then
			merged[id] = o
		elseif oh == bh then
			merged[id] = t
		elseif th == bh then
			merged[id] = o
		else
			local done = false
			if o and t then
				local bn = if b then load(bh) else nil
				local on, tn = load(oh), load(th)
				if on and tn and (bn or not b) then
					local fields = mergeFields(if bn then flatten(bn) else nil, flatten(on), flatten(tn))
					if fields then
						merged[id] = put(unflatten(id, fields))
						done = true
					end
				end
			end
			if not done then
				table.insert(conflicts, { id = id, base = b, ours = o, theirs = t })
			end
		end
	end
	return merged, conflicts
end

-- choices: id -> "ours" | "theirs". Anything not chosen keeps ours.
function Merge.resolve(merged, conflicts, choices)
	for _, c in conflicts do
		merged[c.id] = if choices[c.id] == "theirs" then c.theirs else c.ours
	end
	return merged
end

-- Drops items whose folder no longer exists (deleted on one side, filled on the other).
-- Returns the cleaned tree and how many items were dropped.
function Merge.prune(tree)
	local children, queue = {}, {}
	for id, e in tree do
		if e.p then
			children[e.p] = children[e.p] or {}
			table.insert(children[e.p], id)
		else
			table.insert(queue, id)
		end
	end
	local keep, head = {}, 1
	for _, id in queue do
		keep[id] = true
	end
	while head <= #queue do
		local id = queue[head]
		head += 1
		for _, cid in children[id] or {} do
			if not keep[cid] then
				keep[cid] = true
				table.insert(queue, cid)
			end
		end
	end
	local out, dropped = {}, 0
	for id, e in tree do
		if keep[id] then
			out[id] = e
		else
			dropped += 1
		end
	end
	return out, dropped
end

return Merge
