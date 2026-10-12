--[[
	Bufferizer
	Homogeneous array serialization
	By @bajsucks (Roblox: @baj_dev)
]]
local bufferize = {}
local schemas = require("@self/schemas")
local primitives = require("@self/primitives")
bufferize.primitives = primitives
bufferize.schemas = schemas
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
local function writeRow(buf: buffer, offset: number, map: { number }, ...): number
	local count = select("#", ...)
	if count ~= #map then
		error(`Schema expects {#map} values, got {count}`, 3)
	end
	for index = 1, #map do
		local nInfo = info[reverse[map[index]]]
		nInfo.Write(buf, offset, select(index, ...))
		offset += nInfo.Size
	end
	return offset
end

--[[
	Encodes homogeneous payload into a buffer.
]]
function bufferize.Encode<T>(Payload: { T }, Schema: Schema<T>): buffer
	Payload = Payload or {}
	local s = Size(Schema)
	local ts = s * #Payload
	local encode = Schema.encode or RAW

	local offset = 0
	local buf = buffer.create(ts)

	for _, v: T in Payload do
		offset = writeRow(buf, offset, Schema.map, encode(v))
	end
	return buf
end
--[[
	Decodes a buffer with homogeneous payload.
]]
function bufferize.Decode<T>(buf: buffer, Schema: Schema<T>): { T }
	local s = Size(Schema)
	local count = buffer.len(buf) // s
	local decode = Schema.decode or RAW

	local offset = 0
	local Payload = table.create(count)
	local vals = table.create(#Schema.map)

	for i = 1, count do
		for index = 1, #Schema.map do
			local EnumType = Schema.map[index]
			local Type = reverse[EnumType]
			local nInfo = info[Type]
			vals[index] = nInfo.Read(buf, offset)
			offset += nInfo.Size
		end
		Payload[i] = decode(table.unpack(vals))
		table.clear(vals)
	end

	return Payload
end

function bufferize.Schema<T>(map: { number }, encode: (value: T) -> ...number, decode: (...number) -> T): Schema<T>
	return { map = map, encode = encode, decode = decode }
end

return bufferize
