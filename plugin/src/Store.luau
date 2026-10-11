-- Everything lives in the place itself, under ServerStorage/AssetVersioning/<Folder name>/:
--   Objects/<hash>      one ModuleScript per distinct item (identical items are stored once)
--   Commits/<id>        one Folder per saved version: attributes (Parents, Message, Author, Time)
--                       plus ModuleScripts T1, T2... listing which object each item uses
--   Branches/<name>     StringValue pointing at the latest version of a line of work
--   Head (attribute)    the line this place is working on
local ServerStorage = game:GetService("ServerStorage")

local Codec = require(script.Parent.Codec)
local Util = require(script.Parent.Util)

local quote = Codec.quote

local Store = {}

local CHUNK = 150000

local function child(parent: Instance, name: string, className: string, create: boolean?): Instance?
	local c = parent:FindFirstChild(name)
	if not c and create then
		c = Instance.new(className)
		c.Name = name
		c.Parent = parent
	end
	return c
end

function Store.root(create: boolean?): Instance?
	return child(ServerStorage, Util.FOLDER_NAME, "Folder", create)
end

function Store.pkg(name: string, create: boolean?): Instance?
	local root = Store.root(create)
	if not root then
		return nil
	end
	local pf = child(root, name, "Folder", create)
	if pf and create then
		child(pf, "Objects", "Folder", true)
		child(pf, "Commits", "Folder", true)
		child(pf, "Branches", "Folder", true)
	end
	return pf
end

-- Names of every folder that has saved versions in this place.
function Store.packages(): { string }
	local names = {}
	local root = Store.root()
	if root then
		for _, pf in root:GetChildren() do
			local commits = pf:FindFirstChild("Commits")
			if pf:IsA("Folder") and commits and #commits:GetChildren() > 0 then
				table.insert(names, pf.Name)
			end
		end
	end
	table.sort(names)
	return names
end

-- hash -> ModuleScript
function Store.objects(pkg: string)
	local out = {}
	local pf = Store.pkg(pkg)
	local folder = pf and pf:FindFirstChild("Objects")
	if folder then
		for _, m in folder:GetChildren() do
			out[m.Name] = m
		end
	end
	return out
end

-- Returns true if the object was new.
function Store.putObject(pkg: string, index, hash: string, text: string): boolean
	if index[hash] then
		return false
	end
	local pf = Store.pkg(pkg, true) :: Instance
	local m = Instance.new("ModuleScript")
	m.Name = hash
	m.Source = text
	m.Parent = pf:FindFirstChild("Objects")
	index[hash] = m
	return true
end

function Store.loadObject(index, hash: string)
	local m = index[hash]
	if not m then
		return nil
	end
	-- A clone has no require cache, and works even if the original is being replaced.
	local ok, data = pcall(function()
		return require(m:Clone())
	end)
	if ok and type(data) == "table" and type(data.id) == "string" then
		return data
	end
	return nil
end

-- tree -> list of module sources, each small enough for a script.
function Store.chunkTree(tree): { string }
	local ids = {}
	for id in tree do
		table.insert(ids, id)
	end
	table.sort(ids)

	local chunks, lines, size = {}, { "return {" }, 8
	local function flush()
		table.insert(lines, "}")
		table.insert(chunks, table.concat(lines, "\n"))
		lines, size = { "return {" }, 8
	end
	for _, id in ids do
		local e = tree[id]
		local line = "[" .. quote(id) .. "]={" .. quote(e.h) .. "," .. quote(e.n) .. "," .. (if e.p then quote(e.p) else "false") .. "},"
		if size + #line > CHUNK and size > 8 then
			flush()
		end
		table.insert(lines, line)
		size += #line + 1
	end
	flush()
	return chunks
end

-- commit = { id, parents = {ids}, message, author, time, tree }
function Store.writeCommit(pkg: string, commit)
	local pf = Store.pkg(pkg, true) :: Instance
	local f = Instance.new("Folder")
	f.Name = commit.id
	f:SetAttribute("Parents", table.concat(commit.parents, ","))
	f:SetAttribute("Message", commit.message)
	f:SetAttribute("Author", commit.author)
	f:SetAttribute("Time", commit.time)
	for i, source in Store.chunkTree(commit.tree) do
		local m = Instance.new("ModuleScript")
		m.Name = "T" .. i
		m.Source = source
		m.Parent = f
	end
	f.Parent = pf:FindFirstChild("Commits")
end

local function commitFolder(pkg: string, id: string): Instance?
	local pf = Store.pkg(pkg)
	local commits = pf and pf:FindFirstChild("Commits")
	return commits and commits:FindFirstChild(id)
end

-- Cheap: reads attributes only.
function Store.meta(pkg: string, id: string)
	local f = commitFolder(pkg, id)
	if not f then
		return nil
	end
	local parents = {}
	for p in tostring(f:GetAttribute("Parents") or ""):gmatch("[^,]+") do
		table.insert(parents, p)
	end
	return {
		id = id,
		parents = parents,
		message = tostring(f:GetAttribute("Message") or ""),
		author = tostring(f:GetAttribute("Author") or "unknown"),
		time = tonumber(f:GetAttribute("Time")) or 0,
	}
end

local treeCache = setmetatable({}, { __mode = "k" })

-- A version never changes after it is written, so its tree is cached.
function Store.tree(pkg: string, id: string)
	local f = commitFolder(pkg, id)
	if not f then
		return nil
	end
	if treeCache[f] then
		return treeCache[f]
	end
	local modules = {}
	for _, m in f:GetChildren() do
		if m:IsA("ModuleScript") then
			table.insert(modules, m)
		end
	end
	table.sort(modules, function(a, b)
		return (tonumber(a.Name:sub(2)) or 0) < (tonumber(b.Name:sub(2)) or 0)
	end)
	local tree = {}
	for _, m in modules do
		local ok, part = pcall(function()
			return require(m:Clone())
		end)
		if not ok or type(part) ~= "table" then
			return nil
		end
		for itemId, e in part do
			tree[itemId] = { h = e[1], n = e[2], p = e[3] or nil }
		end
	end
	treeCache[f] = tree
	return tree
end

-- name -> version id
function Store.branches(pkg: string)
	local out = {}
	local pf = Store.pkg(pkg)
	local folder = pf and pf:FindFirstChild("Branches")
	if folder then
		for _, v in folder:GetChildren() do
			if v:IsA("StringValue") then
				out[v.Name] = v.Value
			end
		end
	end
	return out
end

function Store.setBranch(pkg: string, name: string, commitId: string)
	local pf = Store.pkg(pkg, true) :: Instance
	local v = child(pf:FindFirstChild("Branches") :: Instance, name, "StringValue", true) :: StringValue
	v.Value = commitId
end

function Store.tip(pkg: string, branch: string?): string?
	if not branch then
		return nil
	end
	return Store.branches(pkg)[branch]
end

function Store.head(pkg: string): string?
	local pf = Store.pkg(pkg)
	local head = pf and pf:GetAttribute("Head")
	return if type(head) == "string" then head else nil
end

function Store.setHead(pkg: string, branch: string)
	local pf = Store.pkg(pkg, true) :: Instance
	pf:SetAttribute("Head", branch)
end

-- Cheap fingerprint of all history, to notice changes made by teammates (Team Create).
function Store.signature(): string
	local root = Store.root()
	if not root then
		return ""
	end
	local parts = {}
	for _, pf in root:GetChildren() do
		local commits, branches = pf:FindFirstChild("Commits"), pf:FindFirstChild("Branches")
		table.insert(parts, pf.Name .. ":" .. (if commits then #commits:GetChildren() else 0) .. ":" .. tostring(pf:GetAttribute("Head")))
		if branches then
			for _, b in branches:GetChildren() do
				if b:IsA("StringValue") then
					table.insert(parts, b.Name .. "=" .. b.Value)
				end
			end
		end
	end
	return table.concat(parts, "|")
end

return Store
