local types = {
	u8 = 1,
	u16 = 2,
	u32 = 3,
	i8 = 4,
	i16 = 5,
	i32 = 6,
	f32 = 7,
	f64 = 8,
	varint = 9,
	zigzag = 10,
	string = 11,
}

local reverse = {
	[1] = "u8",
	[2] = "u16",
	[3] = "u32",
	[4] = "i8",
	[5] = "i16",
	[6] = "i32",
	[7] = "f32",
	[8] = "f64",
	[9] = "varint",
	[10] = "zigzag",
	[11] = "string",
}

export type Anchors = { [any]: number }

export type Codec = {
	Size: number,
	Variable: boolean?,
	Write: (buf: buffer, offset: number, value: any, row: number?, anchors: Anchors?) -> number?,
	Read: (buf: buffer, offset: number, row: number?, anchors: Anchors?) -> ...any,
	Measure: ((value: any, row: number?, anchors: Anchors?) -> number)?,
}

export type Column = number | Codec

--[[
	Whether a number has no fractional part.
]]
local function isIntegral(value: number): boolean
	return value % 1 == 0
end

local function writeVarint(buf: buffer, offset: number, value: number): number
	assert(isIntegral(value) and value >= 0, "varint requires a non-negative integer")

	local size = 0
	repeat
		local byte = value % 128
		value //= 128
		if value > 0 then
			byte += 128
		end
		buffer.writeu8(buf, offset + size, byte)
		size += 1
	until value <= 0
	return size
end

local function readVarint(buf: buffer, offset: number): (number, number)
	local value = 0
	local shift = 0
	local size = 0
	while true do
		local byte = buffer.readu8(buf, offset + size)
		size += 1
		value += (byte % 128) * 2 ^ shift
		if byte < 128 then
			break
		end
		shift += 7
	end
	return value, size
end

local function varintSize(value: number): number
	assert(isIntegral(value) and value >= 0, "varint requires a non-negative integer")

	local size = 1
	while value >= 128 do
		value //= 128
		size += 1
	end
	return size
end

local function zigzag(value: number): number
	assert(isIntegral(value), "zigzag requires an integer")
	return if value >= 0 then value * 2 else -value * 2 - 1
end

local function unzigzag(value: number): number
	return if value % 2 == 0 then value / 2 else -(value + 1) / 2
end

--[[
	Size is the fixed width, or the nominal width when Variable.
	Variable codecs return their width from Write and Read; Measure sizes a value without writing.
]]
local info: { [string]: Codec } = {
	u8 = { Size = 1, Write = buffer.writeu8, Read = buffer.readu8 },
	u16 = { Size = 2, Write = buffer.writeu16, Read = buffer.readu16 },
	u32 = { Size = 4, Write = buffer.writeu32, Read = buffer.readu32 },
	i8 = { Size = 1, Write = buffer.writei8, Read = buffer.readi8 },
	i16 = { Size = 2, Write = buffer.writei16, Read = buffer.readi16 },
	i32 = { Size = 4, Write = buffer.writei32, Read = buffer.readi32 },
	f32 = { Size = 4, Write = buffer.writef32, Read = buffer.readf32 },
	f64 = { Size = 8, Write = buffer.writef64, Read = buffer.readf64 },
	varint = { Size = 1, Variable = true, Write = writeVarint, Read = readVarint, Measure = varintSize },
	zigzag = {
		Size = 1,
		Variable = true,
		Write = function(buf: buffer, offset: number, value: number): number
			return writeVarint(buf, offset, zigzag(value))
		end,
		Read = function(buf: buffer, offset: number): (number, number)
			local value, size = readVarint(buf, offset)
			return unzigzag(value), size
		end,
		Measure = function(value: number): number
			return varintSize(zigzag(value))
		end,
	},
	string = {
		Size = 1,
		Variable = true,
		Write = function(buf: buffer, offset: number, value: string): number
			local header = writeVarint(buf, offset, #value)
			buffer.writestring(buf, offset + header, value)
			return header + #value
		end,
		Read = function(buf: buffer, offset: number): (string, number)
			local length, header = readVarint(buf, offset)
			return buffer.readstring(buf, offset + header, length), header + length
		end,
		Measure = function(value: string): number
			return varintSize(#value) + #value
		end,
	},
}

local function codecOf(column: number): Codec
	local name = reverse[column]
	local codec = name and info[name]
	assert(codec, `Unknown primitive {column}`)
	return codec
end

--[[
	Checks that an array value is a table, and that it holds count elements when given.
]]
local function checkElements(value: any, count: number?): { any }
	assert(type(value) == "table", `Array column expects a table, got {type(value)}`)
	if count then
		local length = #value
		assert(length == count, `FixedArray expects {count} elements, got {length}`)
	end
	return value
end

local function writeElements(buf: buffer, offset: number, codec: Codec, value: { any }): number
	local size = codec.Size
	local written = 0
	for index = 1, #value do
		if codec.Variable then
			written += codec.Write(buf, offset + written, value[index]) :: number
		else
			codec.Write(buf, offset + written, value[index])
			written += size
		end
	end
	return written
end

local function readElements(buf: buffer, offset: number, codec: Codec, count: number): ({ any }, number)
	local value = table.create(count)
	local size = codec.Size
	local consumed = 0

	if codec.Variable then
		for index = 1, count do
			local element, width = codec.Read(buf, offset + consumed)
			value[index] = element
			consumed += width
		end
	else
		for index = 1, count do
			value[index] = codec.Read(buf, offset + consumed)
			consumed += size
		end
	end
	return value, consumed
end

local function measureElements(codec: Codec, value: { any }): number
	if not codec.Variable then
		return #value * codec.Size
	end

	local measure = codec.Measure :: (any) -> number
	local total = 0
	for index = 1, #value do
		total += measure(value[index])
	end
	return total
end

--[[
	A column of arrays, prefixed with their element count.
]]
local function Array(element: number): Codec
	local codec = codecOf(element)

	return {
		Size = 1,
		Variable = true,
		Write = function(buf: buffer, offset: number, value: { any }): number
			local header = writeVarint(buf, offset, #checkElements(value))
			return header + writeElements(buf, offset + header, codec, value)
		end,
		Read = function(buf: buffer, offset: number): (any, number)
			local count, header = readVarint(buf, offset)
			local value, consumed = readElements(buf, offset + header, codec, count)
			return value, header + consumed
		end,
		Measure = function(value: { any }): number
			return varintSize(#checkElements(value)) + measureElements(codec, value)
		end,
	}
end

--[[
	A column of arrays with a fixed element count, written without a prefix.
	Stays fixed width while its elements are.
]]
local function FixedArray(element: number, count: number): Codec
	assert(isIntegral(count) and count >= 0, "FixedArray requires a non-negative count")
	local codec = codecOf(element)

	if not codec.Variable then
		return {
			Size = count * codec.Size,
			Write = function(buf: buffer, offset: number, value: { any })
				writeElements(buf, offset, codec, checkElements(value, count))
			end,
			Read = function(buf: buffer, offset: number): { any }
				local value = readElements(buf, offset, codec, count)
				return value
			end,
		}
	end

	return {
		Size = count,
		Variable = true,
		Write = function(buf: buffer, offset: number, value: { any }): number
			return writeElements(buf, offset, codec, checkElements(value, count))
		end,
		Read = function(buf: buffer, offset: number): (any, number)
			return readElements(buf, offset, codec, count)
		end,
		Measure = function(value: { any }): number
			return measureElements(codec, checkElements(value, count))
		end,
	}
end

return {
	types = types,
	reverse = reverse,
	info = info,
	codecOf = codecOf,
	Array = Array,
	FixedArray = FixedArray,
	isIntegral = isIntegral,
	RAW = function<T>(n: T)
		return n
	end,
}
