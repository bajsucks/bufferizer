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
bufferize.Array = primitives.Array
bufferize.FixedArray = primitives.FixedArray
local RAW = primitives.RAW
local codecOf = primitives.codecOf

type Schema<T> = schemas.Schema<T>
type Codec = primitives.Codec
type Column = primitives.Column
type Anchors = primitives.Anchors

local function resolve(Schema: Schema<any>): { Codec }
	assert(#Schema.map > 0, "Schema has no columns")
	local codecs = table.create(#Schema.map)
	for index, column in Schema.map do
		codecs[index] = if type(column) == "number" then codecOf(column) else column
	end
	return codecs
end

local function rowSize(codecs: { Codec }): number?
	local size = 0
	for _, codec in codecs do
		if codec.Variable then
			return nil
		end
		size += codec.Size
	end
	return size
end

local function measureRow(codecs: { Codec }, row: number, anchors: Anchors?, ...): number
	local count = select("#", ...)
	if count ~= #codecs then
		error(`Schema expects {#codecs} values, got {count}`, 3)
	end

	local size = 0
	for index = 1, #codecs do
		local codec = codecs[index]
		if codec.Variable then
			local measure = codec.Measure :: (any, number?, Anchors?) -> number
			size += measure(select(index, ...), row, anchors)
		else
			size += codec.Size
		end
	end
	return size
end

local function writeRow(buf: buffer, offset: number, codecs: { Codec }, row: number, anchors: Anchors?, ...): number
	local count = select("#", ...)
	if count ~= #codecs then
		error(`Schema expects {#codecs} values, got {count}`, 3)
	end

	for index = 1, #codecs do
		local codec = codecs[index]
		local value = select(index, ...)
		if codec.Variable then
			offset += codec.Write(buf, offset, value, row, anchors) :: number
		else
			codec.Write(buf, offset, value)
			offset += codec.Size
		end
	end
	return offset
end

local function measurePayload(codecs: { Codec }, Payload: { any }, encode): number
	local total = 0
	local anchors: Anchors = table.create(#codecs)
	for row, value in Payload do
		total += measureRow(codecs, row, anchors, encode(value))
	end
	return total
end

--[[
	Encodes homogeneous payload into a buffer.
]]
function bufferize.Encode<T>(Payload: { T }, Schema: Schema<T>): buffer
	Payload = Payload or {}
	local encode = Schema.encode or RAW
	local codecs = resolve(Schema)
	local size = rowSize(codecs)

	if size then
		local buf = buffer.create(size * #Payload)
		local offset = 0
		for _, v: T in Payload do
			offset = writeRow(buf, offset, codecs, 0, nil, encode(v))
		end
		return buf
	end

	local buf = buffer.create(measurePayload(codecs, Payload, encode))
	local anchors: Anchors = table.create(#codecs)
	local offset = 0
	for row, v: T in Payload do
		offset = writeRow(buf, offset, codecs, row, anchors, encode(v))
	end
	return buf
end

--[[
	Decodes a buffer with homogeneous payload.
]]
function bufferize.Decode<T>(buf: buffer, Schema: Schema<T>): { T }
	local decode = Schema.decode or RAW
	local codecs = resolve(Schema)
	local length = buffer.len(buf)
	local vals = table.create(#codecs)
	local size = rowSize(codecs)

	if size then
		if length % size ~= 0 then
			error(`Buffer length {length} is not a multiple of the row size {size}`, 2)
		end

		local count = length // size
		local Payload = table.create(count)
		local offset = 0
		for index = 1, count do
			for column = 1, #codecs do
				local codec = codecs[column]
				vals[column] = codec.Read(buf, offset)
				offset += codec.Size
			end
			Payload[index] = decode(table.unpack(vals, 1, #codecs))
			table.clear(vals)
		end
		return Payload
	end

	local anchors: Anchors = table.create(#codecs)
	local Payload = {}
	local offset = 0
	local index = 0
	while offset < length do
		index += 1
		for column = 1, #codecs do
			local codec = codecs[column]
			if codec.Variable then
				local value, consumed = codec.Read(buf, offset, index, anchors)
				vals[column] = value
				offset += consumed
			else
				vals[column] = codec.Read(buf, offset)
				offset += codec.Size
			end
		end
		Payload[index] = decode(table.unpack(vals, 1, #codecs))
		table.clear(vals)
	end
	return Payload
end

--[[
	Returns how many bytes a payload will take up once serialized.
	If no payload is provided, will return the size of the row instead.
	@return The size of payload/row in bytes. In row mode, if any column is variable, returns nil.
]]
function bufferize.Size<T>(Schema: Schema<T>, Payload: { T }?): number?
	local codecs = resolve(Schema)
	local size = rowSize(codecs)

	if Payload == nil then
		return size
	end
	if size then
		return size * #Payload
	end
	return measurePayload(codecs, Payload, Schema.encode or RAW)
end

function bufferize.Schema<T>(map: { Column }, encode: (value: T) -> ...any, decode: (...any) -> T): Schema<T>
	return { map = map, encode = encode, decode = decode }
end

return bufferize
