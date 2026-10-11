-- Moves the history of one folder between places as a plain .rbxm file.
local SerializationService = game:GetService("SerializationService")
local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local StudioService = game:GetService("StudioService")

local Repo = require(script.Parent.Repo)
local Store = require(script.Parent.Store)
local Util = require(script.Parent.Util)

local Bundle = {}

local ATTR = "AssetVersioningBundle"

-- Yields (file dialog). Returns { ok, message }.
function Bundle.export(plugin: Plugin, pkg: string)
	local pf = Store.pkg(pkg)
	if not pf then
		return { ok = false, message = "Nothing saved for this folder yet." }
	end
	local copy = pf:Clone()
	copy:SetAttribute(ATTR, pkg)
	copy:SetAttribute("Head", nil)
	copy.Parent = ServerStorage

	local previous = Selection:Get()
	Selection:Set({ copy })
	local ok, saved = pcall(function()
		return plugin:PromptSaveSelectionAsync(pkg .. " versions")
	end)
	Selection:Set(previous)
	copy:Destroy()

	if not ok then
		return { ok = false, message = "Couldn't create the file: " .. tostring(saved) }
	end
	if not saved then
		return { ok = false, cancelled = true, message = "Export cancelled." }
	end
	return { ok = true, message = `The history of "{pkg}" was saved to a file. Open the other place and press Import.` }
end

local function absorb(folder: Instance)
	local pkg = Util.safeName(folder:GetAttribute(ATTR) :: string)
	local pf = Store.pkg(pkg, true) :: Instance
	local objects = Store.objects(pkg)
	local localObjects, localCommits = pf:FindFirstChild("Objects") :: Instance, pf:FindFirstChild("Commits") :: Instance

	for _, o in (folder:FindFirstChild("Objects") or folder):GetChildren() do
		if o:IsA("ModuleScript") and not objects[o.Name] then
			o.Parent = localObjects
			objects[o.Name] = o
		end
	end

	local newVersions = 0
	local commits = folder:FindFirstChild("Commits")
	if commits then
		for _, c in commits:GetChildren() do
			if not localCommits:FindFirstChild(c.Name) then
				c.Parent = localCommits
				newVersions += 1
			end
		end
	end

	local lines = {}
	local incoming = folder:FindFirstChild("Branches")
	if incoming then
		local mine = Store.branches(pkg)
		for _, v in incoming:GetChildren() do
			if v:IsA("StringValue") and Store.meta(pkg, v.Value) then
				local current = mine[v.Name]
				if current == nil or (current ~= v.Value and Repo.isAncestor(pkg, current, v.Value)) then
					Store.setBranch(pkg, v.Name, v.Value)
					table.insert(lines, v.Name)
				elseif current ~= v.Value and not Repo.isAncestor(pkg, v.Value, current) then
					local name, n = v.Name .. " (imported)", 2
					while mine[name] and mine[name] ~= v.Value do
						name = `{v.Name} (imported {n})`
						n += 1
					end
					Store.setBranch(pkg, name, v.Value)
					table.insert(lines, name)
				end
			end
		end
	end
	folder:Destroy()
	return { name = pkg, versions = newVersions, branches = lines }
end

-- Yields (file dialog). Returns { ok, message, imported = { {name, versions, branches} } }.
function Bundle.import()
	local ok, file = pcall(function()
		return StudioService:PromptImportFileAsync({ "rbxm" })
	end)
	if not ok then
		return { ok = false, message = "Couldn't open the file: " .. tostring(file) }
	end
	if not file then
		return { ok = false, cancelled = true, message = "Import cancelled." }
	end

	local read, list = pcall(function()
		return SerializationService:DeserializeInstancesAsync(buffer.fromstring(file:GetBinaryContents()))
	end)
	if not read then
		return { ok = false, message = "That file couldn't be read: " .. tostring(list) }
	end

	local imported = {}
	for _, inst in list do
		if inst:IsA("Folder") and type(inst:GetAttribute(ATTR)) == "string" then
			table.insert(imported, absorb(inst))
		else
			inst:Destroy()
		end
	end
	if #imported == 0 then
		return { ok = false, message = "That file isn't an exported Asset Versioning history." }
	end
	return { ok = true, imported = imported }
end

return Bundle
