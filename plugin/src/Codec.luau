-- Turns property values into Luau source text (and back, simply by running that text), and
-- knows which properties each class has.
local ReflectionService = game:GetService("ReflectionService")

local Codec = {}

local function num(n: number): string
	if n ~= n then
		return "(0/0)"
	end
	if n == math.huge then
		return "math.huge"
	elseif n == -math.huge then
		return "-math.huge"
	end
	if n == math.floor(n) and math.abs(n) < 1e9 then
		return string.format("%d", n)
	end
	local s = string.format("%.9g", n)
	local back = tonumber(s) :: number
	if back == n or string.unpack("f", string.pack("f", back)) == n then
		return s
	end
	return string.format("%.17g", n)
end

local function quote(s: string): string
	local escaped = s:gsub('[%c"\\]', function(c)
		if c == "\n" then
			return "\\n"
		elseif c == "\r" then
			return "\\r"
		elseif c == "\t" then
			return "\\t"
		elseif c == '"' then
			return '\\"'
		elseif c == "\\" then
			return "\\\\"
		end
		return string.format("\\%03d", string.byte(c))
	end)
	return '"' .. escaped .. '"'
end

Codec.quote = quote

local ENC = {}

ENC.boolean = function(v)
	return if v then "true" else "false"
end
ENC.number = num
ENC.string = quote

ENC.Vector3 = function(v)
	return `Vector3.new({num(v.X)}, {num(v.Y)}, {num(v.Z)})`
end
ENC.Vector2 = function(v)
	return `Vector2.new({num(v.X)}, {num(v.Y)})`
end
ENC.CFrame = function(v)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()
	if r00 == 1 and r01 == 0 and r02 == 0 and r10 == 0 and r11 == 1 and r12 == 0 and r20 == 0 and r21 == 0 and r22 == 1 then
		return `CFrame.new({num(x)}, {num(y)}, {num(z)})`
	end
	local parts = { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
	for i, n in parts do
		parts[i] = num(n)
	end
	return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
end
ENC.Color3 = function(v)
	return `Color3.new({num(v.R)}, {num(v.G)}, {num(v.B)})`
end
ENC.BrickColor = function(v)
	return `BrickColor.new({v.Number})`
end
ENC.UDim = function(v)
	return `UDim.new({num(v.Scale)}, {num(v.Offset)})`
end
ENC.UDim2 = function(v)
	return `UDim2.new({num(v.X.Scale)}, {num(v.X.Offset)}, {num(v.Y.Scale)}, {num(v.Y.Offset)})`
end
ENC.Rect = function(v)
	return `Rect.new({num(v.Min.X)}, {num(v.Min.Y)}, {num(v.Max.X)}, {num(v.Max.Y)})`
end
ENC.NumberRange = function(v)
	return `NumberRange.new({num(v.Min)}, {num(v.Max)})`
end
ENC.NumberSequence = function(v)
	local keys = {}
	for _, k in v.Keypoints do
		table.insert(keys, `NumberSequenceKeypoint.new({num(k.Time)}, {num(k.Value)}, {num(k.Envelope)})`)
	end
	return "NumberSequence.new({" .. table.concat(keys, ", ") .. "})"
end
ENC.ColorSequence = function(v)
	local keys = {}
	for _, k in v.Keypoints do
		table.insert(keys, `ColorSequenceKeypoint.new({num(k.Time)}, {ENC.Color3(k.Value)})`)
	end
	return "ColorSequence.new({" .. table.concat(keys, ", ") .. "})"
end
ENC.EnumItem = function(v)
	local enumType = tostring(v.EnumType)
	if v.Name:match("^[%a_][%w_]*$") then
		return `Enum.{enumType}.{v.Name}`
	end
	return `Enum.{enumType}:FromValue({v.Value})`
end
ENC.Font = function(v)
	return `Font.new({quote(v.Family)}, {ENC.EnumItem(v.Weight)}, {ENC.EnumItem(v.Style)})`
end
ENC.PhysicalProperties = function(v)
	return `PhysicalProperties.new({num(v.Density)}, {num(v.Friction)}, {num(v.Elasticity)}, {num(v.FrictionWeight)}, {num(v.ElasticityWeight)})`
end
ENC.Content = function(v)
	if v.SourceType == Enum.ContentSourceType.Uri then
		return `Content.fromUri({quote(v.Uri)})`
	elseif v.SourceType == Enum.ContentSourceType.None then
		return "Content.none"
	end
	return nil
end
ENC.Instance = function(v, refId)
	local id = refId and refId(v)
	if id then
		return "{ ref = " .. quote(id) .. " }"
	end
	return nil
end

-- Returns Luau source for the value, or nil if the value can't be saved.
-- refId maps an Instance to its snapshot id (so references between instances survive).
function Codec.encode(value: any, refId: ((Instance) -> string?)?): string?
	local f = ENC[typeof(value)]
	if f then
		return f(value, refId)
	end
	return nil
end

function Codec.same(a: any, b: any): boolean
	if a == b then
		return true
	end
	if a == nil or b == nil or typeof(a) == "Instance" or typeof(b) == "Instance" then
		return false
	end
	local ea, eb = Codec.encode(a), Codec.encode(b)
	return ea ~= nil and ea == eb
end

-- Handled separately, derived from other data, or not meaningful to save.
local SKIP = {
	Name = true,
	Parent = true,
	Source = true,
	UniqueId = true,
	Tags = true,
	Attributes = true,
	AttributesSerialize = true,
	SourceAssetId = true,
	HistoryId = true,
	ScriptGuid = true,
	LinkedSource = true,
	Capabilities = true,
	DefinesCapabilities = true,
	Sandboxed = true,
	ClassName = true,
}

local classCache = {}

-- { props = sorted property names, default = a fresh instance (or nil), defaultEnc = name -> encoded default }
function Codec.classInfo(className: string)
	local info = classCache[className]
	if info then
		return info
	end
	info = { props = {}, default = nil, defaultEnc = {} }

	local ok, list = pcall(function()
		return ReflectionService:GetPropertiesOfClass(className)
	end)
	if ok and list then
		for _, p in list do
			if p.Serialized and not SKIP[p.Name] then
				table.insert(info.props, p.Name)
			end
		end
		table.sort(info.props)
	end

	local created, inst = pcall(Instance.new, className)
	if created then
		info.default = inst
		for _, name in info.props do
			local readable, value = pcall(function()
				return inst[name]
			end)
			if readable then
				info.defaultEnc[name] = Codec.encode(value) or false
			end
		end
	end

	classCache[className] = info
	return info
end

return Codec
