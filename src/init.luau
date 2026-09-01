--[[
	Bufferizer
	Homogenous array serialization
	By @bajsucks (Roblox: @baj_dev)
]]
local bufferize = {}
local schemas = require(script.schemas)
local primitives = require(script.primitives)
local info = primitives.info
local reverse = primitives.reverse
local RAW = primitives.RAW

type Schema<T> = schemas.Schema<T>

-- Returns the size of the type in bytes
local function Size(Map)
	local size = 0
	for _, primitive in Map.map do
		local str = reverse[primitive]
		size += info[str].Size
	end
	return size
end

function bufferize.Encode<T>(Payload: { T }, Schema: Schema<T>): buffer
	Payload = Payload or {}
	local s = Size(Schema)
	local ts = s * #Payload
	local buf = buffer.create(ts)
	local offset = 0
	local encode = Schema.encode or RAW
	for _, v: T in Payload do
		for index, number in select(encode(v)) do
			local EnumType = Schema.map[index]
			local Type = reverse[EnumType]
			local nInfo = info[Type]
			nInfo.Write(buf, offset, number)
			offset += nInfo.Size
		end
	end
	return buf
end

function bufferize.Decode<T>(buf: buffer, Schema: Schema<T>): { T }
	local s = Size(Schema)
	local count = buffer.len(buf) // s
	local Payload = table.create(count)
	local offset = 0
	local decode = Schema.decode or RAW

	for _ = 1, count do
		local vals = {}
		for index = 1, #Schema.map do
			local EnumType = Schema.map[index]
			local Type = reverse[EnumType]
			local nInfo = info[Type]
			vals[index] = nInfo.Read(buf, offset)
			offset += nInfo.Size
		end
		table.insert(Payload, decode(table.unpack(vals)))
	end

	return Payload
end

function bufferize.Schema<T>(map: { number }, encode: (value: T) -> ...number, decode: (...number) -> T): Schema<T>
	return { map = map, encode = encode, decode = decode }
end

return bufferize
