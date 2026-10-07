-- Snapshots live in ServerStorage/AssetVersioning/<Package>/ as ModuleScripts named "<Name>~<id>".
-- Rojo maps that folder to disk, which is how git gets to see them.
local ServerStorage = game:GetService("ServerStorage")

local Util = require(script.Parent.Util)

local Store = {}

function Store.folder(create: boolean?): Folder?
	local f = ServerStorage:FindFirstChild(Util.FOLDER_NAME)
	if not f and create then
		f = Instance.new("Folder")
		f.Name = Util.FOLDER_NAME
		f.Parent = ServerStorage
	end
	return f
end

function Store.packageFolder(pkg: string, create: boolean?): Instance?
	local root = Store.folder(create)
	if not root then
		return nil
	end
	local f = root:FindFirstChild(pkg)
	if not f and create then
		f = Instance.new("Folder")
		f.Name = pkg
		f.Parent = root
	end
	return f
end

-- Names of every package that has snapshot files in this place.
function Store.packages(): { string }
	local names = {}
	local root = Store.folder()
	if root then
		for _, f in root:GetChildren() do
			if f:IsA("Folder") and #f:GetChildren() > 0 then
				table.insert(names, f.Name)
			end
		end
	end
	table.sort(names)
	return names
end

-- id -> { module, label, source }
function Store.read(pkg: string)
	local out = {}
	local pf = Store.packageFolder(pkg)
	if pf then
		for _, m in pf:GetChildren() do
			if m:IsA("ModuleScript") then
				local label, id = m.Name:match("^(.*)~(%w+)$")
				if id then
					out[id] = { module = m, label = label, source = m.Source }
				end
			end
		end
	end
	return out
end

-- Cheap fingerprint of everything stored, to notice when Rojo updates the files.
function Store.signature(): string
	local root = Store.folder()
	if not root then
		return ""
	end
	local count, hash = 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("ModuleScript") then
			count += 1
			hash = (hash * 31 + #d.Source + #d.Name) % 2147483647
		end
	end
	return count .. ":" .. hash
end

-- rendered: id -> { name, source }. Only touches modules whose text actually changed.
function Store.write(pkg: string, rendered)
	local pf = Store.packageFolder(pkg, true) :: Instance
	local existing = Store.read(pkg)
	local created, updated, removed = 0, 0, 0

	for id, r in rendered do
		local modName = Util.safeName(r.name) .. "~" .. id
		local rec = existing[id]
		if rec then
			if rec.module.Name ~= modName then
				rec.module.Name = modName
			end
			if Util.norm(rec.source) ~= Util.norm(r.source) then
				rec.module.Source = r.source
				updated += 1
			end
		else
			local m = Instance.new("ModuleScript")
			m.Name = modName
			m.Source = r.source
			m.Parent = pf
			created += 1
		end
	end

	for id, rec in existing do
		if not rendered[id] then
			rec.module:Destroy()
			removed += 1
		end
	end

	return { created = created, updated = updated, removed = removed }
end

return Store
