local HttpService = game:GetService("HttpService")

local Util = {}

Util.ID_ATTR = "AssetVersioningId"
Util.PKG_ATTR = "AssetVersioningPackage"
Util.ROOT_TAG = "AssetVersioningRoot"
Util.FOLDER_NAME = "AssetVersioning"
Util.MAX_SOURCE = 190000

function Util.newId(): string
	local guid = HttpService:GenerateGUID(false)
	guid = guid:gsub("%-", "")
	return guid:sub(1, 12):lower()
end

-- Safe for file names on every OS; used for package folders and snapshot module names.
function Util.safeName(name: string): string
	local s = name:gsub("[^%w _%-]", "_")
	s = s:gsub("^%s+", "")
	s = s:gsub("%s+$", "")
	s = s:sub(1, 40)
	if s == "" then
		s = "Item"
	end
	return s
end

-- Line endings can change when git checks files out on Windows; they never count as a difference.
function Util.norm(s: string): string
	local out = s:gsub("\r", "")
	return out
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_DECODE = {}
for i = 1, 64 do
	B64_DECODE[string.byte(B64, i)] = i - 1
end

function Util.base64Encode(b: buffer): string
	local len = buffer.len(b)
	local out = table.create(math.ceil(len / 3))
	local i = 0
	while i < len do
		local b1 = buffer.readu8(b, i)
		local b2 = if i + 1 < len then buffer.readu8(b, i + 1) else 0
		local b3 = if i + 2 < len then buffer.readu8(b, i + 2) else 0
		local n = b1 * 65536 + b2 * 256 + b3
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		local group = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
		if i + 1 < len then
			group ..= B64:sub(c3 + 1, c3 + 1)
		end
		if i + 2 < len then
			group ..= B64:sub(c4 + 1, c4 + 1)
		end
		table.insert(out, group)
		i += 3
	end
	return table.concat(out)
end

function Util.base64Decode(s: string): buffer
	local clean = s:gsub("[^A-Za-z0-9%+/]", "")
	local n = #clean
	local outLen = math.floor(n * 3 / 4)
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, n, 4 do
		local c1, c2, c3, c4 = string.byte(clean, i, i + 3)
		local v = B64_DECODE[c1] * 262144
			+ B64_DECODE[c2] * 4096
			+ (if c3 then B64_DECODE[c3] else 0) * 64
			+ (if c4 then B64_DECODE[c4] else 0)
		if o < outLen then
			buffer.writeu8(out, o, math.floor(v / 65536) % 256)
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, math.floor(v / 256) % 256)
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, v % 256)
		end
		o += 3
	end
	return out
end

return Util
