-- Rebuilds a folder from its snapshot. Matches instances by id so existing ones are updated in
-- place instead of being recreated.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local SerializationService = game:GetService("SerializationService")

local Codec = require(script.Parent.Codec)
local Serializer = require(script.Parent.Serializer)
local Store = require(script.Parent.Store)
local Util = require(script.Parent.Util)

local Restore = {}

local function loadNodes(pkg: string)
	local nodes, unreadable = {}, {}
	for _, rec in Store.read(pkg) do
		local ok, data = pcall(function()
			-- A clone has no require cache, so edits made by Rojo/git are picked up.
			return require(rec.module:Clone())
		end)
		if ok and type(data) == "table" and type(data.id) == "string" then
			nodes[data.id] = data
		else
			table.insert(unreadable, rec.label)
		end
	end
	return nodes, unreadable
end

local function resolveLocation(location: { string }?): Instance
	local parent: Instance = game:GetService("ServerStorage")
	if not location or #location == 0 then
		return parent
	end
	local ok, service = pcall(function()
		return game:GetService(location[1])
	end)
	if not ok then
		return parent
	end
	parent = service
	for i = 2, #location do
		local child = parent:FindFirstChild(location[i])
		if not child then
			child = Instance.new("Folder")
			child.Name = location[i]
			child.Parent = parent
		end
		parent = child
	end
	return parent
end

local function setProp(inst: Instance, prop: string, value: any, failures: { string })
	local ok = pcall(function()
		(inst :: any)[prop] = value
	end)
	if not ok then
		table.insert(failures, `{inst.Name}.{prop}`)
	end
end

local function applyNode(inst: Instance, data, scope: Instance?, refs, failures: { string })
	if inst.Name ~= data.name then
		inst.Name = data.name
	end

	local info = Codec.classInfo(data.class)
	local want = data.props or {}
	for _, prop in info.props do
		local value = want[prop]
		if type(value) == "table" and value.ref then
			table.insert(refs, { inst = inst, prop = prop, id = value.ref })
		else
			if value == nil and info.default then
				local ok, def = pcall(function()
					return (info.default :: any)[prop]
				end)
				if ok then
					value = def
				end
			end
			local ok, cur = pcall(function()
				return (inst :: any)[prop]
			end)
			if ok and value == nil and cur ~= nil then
				-- Absent from the snapshot means "default", unless we never save that kind of value
				-- (then it's not ours to reset), or it points at something outside the folder.
				if typeof(cur) == "Instance" then
					if not (scope and (cur == scope or cur:IsDescendantOf(scope))) then
						ok = false
					end
				elseif Codec.encode(cur) == nil then
					ok = false
				end
			end
			if ok and not Codec.same(cur, value) then
				setProp(inst, prop, value, failures)
			end
		end
	end

	local attrs = data.attributes or {}
	for k, v in attrs do
		inst:SetAttribute(k, v)
	end
	for k in inst:GetAttributes() do
		if attrs[k] == nil and k ~= Util.ID_ATTR and k ~= Util.PKG_ATTR then
			inst:SetAttribute(k, nil)
		end
	end

	local wantTags = {}
	for _, tag in data.tags or {} do
		wantTags[tag] = true
		if not CollectionService:HasTag(inst, tag) then
			CollectionService:AddTag(inst, tag)
		end
	end
	for _, tag in CollectionService:GetTags(inst) do
		if not wantTags[tag] and tag ~= Util.ROOT_TAG then
			CollectionService:RemoveTag(inst, tag)
		end
	end

	if data.source ~= nil and inst:IsA("LuaSourceContainer") then
		local container = inst :: any
		if Util.norm(container.Source) ~= Util.norm(data.source) then
			container.Source = data.source
		end
	end
end

local function create(data, failures: { string }): Instance?
	if data.blob then
		local ok, inst = pcall(function()
			local list = SerializationService:DeserializeInstancesAsync(Util.base64Decode(table.concat(data.blob)))
			return list[1]
		end)
		if ok and inst then
			return inst
		end
		table.insert(failures, data.name .. " (could not rebuild shape)")
		return nil
	end
	local ok, inst = pcall(Instance.new, data.class)
	if ok then
		return inst
	end
	table.insert(failures, `{data.name} ({data.class} can't be created by plugins)`)
	return nil
end

-- Yields. existingRoot is the live folder, or nil to create it from scratch.
-- Returns { ok = true, failures = {...}, unreadable = {...} } or { ok = false, message }.
function Restore.run(pkg: string, existingRoot: Instance?)
	local nodes, unreadable = loadNodes(pkg)

	local rootData
	for _, d in nodes do
		if d.parent == nil then
			rootData = d
		end
	end
	if not rootData then
		return { ok = false, message = "This snapshot has no main folder file, so there is nothing to restore." }
	end

	local recording = ChangeHistoryService:TryBeginRecording("Restore snapshot")
	local failures = {}

	local ok, err = pcall(function()
		local live, oldDescendants = {}, {}
		if existingRoot then
			table.insert(oldDescendants, existingRoot)
			for _, d in existingRoot:GetDescendants() do
				table.insert(oldDescendants, d)
				local id = d:GetAttribute(Util.ID_ATTR)
				if type(id) == "string" and not live[id] then
					live[id] = d
				end
			end
			live[rootData.id] = existingRoot
		end
		local rootParent = if existingRoot then existingRoot.Parent else resolveLocation(rootData.location)

		-- 1. make sure every instance exists
		local keep = {}
		for id, data in nodes do
			local inst = live[id]
			local reuse = inst ~= nil and inst.ClassName == data.class
			if reuse and data.blob then
				local same, current = pcall(function()
					return table.concat(Serializer.blobOf(inst :: Instance)) == table.concat(data.blob)
				end)
				reuse = same and current
			end
			if reuse then
				keep[id] = inst
			else
				local fresh = create(data, failures)
				if fresh then
					fresh:SetAttribute(Util.ID_ATTR, id)
					keep[id] = fresh
				end
			end
		end

		-- 2. properties, attributes, tags, scripts
		local refs = {}
		for id, data in nodes do
			if keep[id] then
				applyNode(keep[id], data, existingRoot, refs, failures)
			end
		end

		-- 3. hierarchy, parents before children
		local children = {}
		for id, data in nodes do
			if data.parent then
				children[data.parent] = children[data.parent] or {}
				table.insert(children[data.parent], id)
			end
		end
		local rootInst = keep[rootData.id]
		if not rootInst then
			error("could not create the main folder")
		end
		rootInst.Parent = rootParent
		local queue = { rootData.id }
		local reached = { [rootData.id] = true }
		local head = 1
		while head <= #queue do
			local pid = queue[head]
			head += 1
			for _, cid in children[pid] or {} do
				if keep[cid] and not reached[cid] then
					reached[cid] = true
					if keep[cid].Parent ~= keep[pid] then
						keep[cid].Parent = keep[pid]
					end
					table.insert(queue, cid)
				end
			end
		end

		-- 4. references between instances (they can only be set once everything exists)
		for _, r in refs do
			setProp(r.inst, r.prop, keep[r.id], failures)
		end

		-- 5. remove what the snapshot doesn't have, and anything that never got placed
		local kept = {}
		for _, inst in keep do
			kept[inst] = true
		end
		for _, inst in oldDescendants do
			if not kept[inst] then
				inst:Destroy()
			end
		end
		for id, inst in keep do
			if not reached[id] then
				inst:Destroy()
			end
		end

		rootInst:SetAttribute(Util.PKG_ATTR, pkg)
		CollectionService:AddTag(rootInst, Util.ROOT_TAG)
	end)

	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end

	if not ok then
		return { ok = false, message = "Restore failed, nothing was changed: " .. tostring(err) }
	end
	return { ok = true, failures = failures, unreadable = unreadable }
end

return Restore
