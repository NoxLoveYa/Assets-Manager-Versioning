local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Serializer = require(script.Parent.Serializer)
local Store = require(script.Parent.Store)
local Util = require(script.Parent.Util)

local Snapshot = {}

-- Yields. Returns { ok = true, created, updated, removed } or { ok = false, message }.
function Snapshot.save(root: Instance, pkg: string)
	local recording = ChangeHistoryService:TryBeginRecording("Save snapshot")

	local ok, result = pcall(function()
		local nodes = Serializer.collect(root, true)
		local rendered = {}
		for _, node in nodes do
			local source = Serializer.render(node)
			if #source > Util.MAX_SOURCE then
				return {
					ok = false,
					message = `"{node.name}" is too big to save (a single item can't hold that much data). Split it up or move it out of the tracked folder.`,
				}
			end
			rendered[node.id] = { name = node.name, source = source }
		end
		local counts = Store.write(pkg, rendered)
		counts.ok = true
		return counts
	end)

	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok and result.ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end

	if not ok then
		return { ok = false, message = "Something went wrong while saving: " .. tostring(result) }
	end
	return result
end

return Snapshot
