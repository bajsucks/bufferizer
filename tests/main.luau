local process = require("@lune/process")

local primitives = require("../src/primitives")
local bufferize = require("../src")

local p = primitives.types
local failures = 0

local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
	end
	print(`{if ok then "ok" else "not ok"} - {name}`)
end

local function checkEqual(name: string, actual: any, expected: any)
	local ok = actual == expected
	if not ok then
		name = `{name}: {tostring(actual)} ~= {tostring(expected)}`
	end
	check(name, ok)
end

local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if #a ~= #b then
		return false
	end
	for index = 1, #a do
		if not same(a[index], b[index]) then
			return false
		end
	end
	return true
end

local function checkSame(name: string, actual: any, expected: any)
	check(name, same(actual, expected))
end

local row = bufferize.Schema({ p.u8, p.f32, p.f64 }, function(v)
	return v[1], v[2], v[3]
end, function(a, b, c)
	return { a, b, c }
end)

do
	local buf = bufferize.Encode({ { 7, 1.5, 2.5 } }, row)
	local expected = buffer.create(13)
	buffer.writeu8(expected, 0, 7)
	buffer.writef32(expected, 1, 1.5)
	buffer.writef64(expected, 5, 2.5)
	checkEqual("fixed layout", buffer.tostring(buf), buffer.tostring(expected))
	checkSame("fixed round-trip", bufferize.Decode(buf, row), { { 7, 1.5, 2.5 } })
end

do
	local payload = { { 1, 1.5, 2.5 }, { 2, 3.5, 4.5 }, { 3, 5.5, 6.5 } }
	local buf = bufferize.Encode(payload, row)
	checkEqual("multi-row length", buffer.len(buf), 39)
	checkSame("multi-row round-trip", bufferize.Decode(buf, row), payload)
end

do
	local raw = bufferize.Schema({ p.f64 })
	checkSame("raw schema round-trip", bufferize.Decode(bufferize.Encode({ 1.5, 2.5 }, raw), raw), { 1.5, 2.5 })
end

do
	local buf = bufferize.Encode({}, row)
	checkEqual("empty payload length", buffer.len(buf), 0)
	checkSame("empty payload round-trip", bufferize.Decode(buf, row), {})
end

do
	local bad = bufferize.Schema({ p.u8, p.u8 }, function()
		return 1
	end)
	check("arity mismatch raises", not pcall(bufferize.Encode, { 0 }, bad))
end

local function checkCodec(name: string, codecName: string, value: any, expected: any)
	local codec = primitives.info[codecName]
	local size = codec.Measure(value)
	local buf = buffer.create(size)
	local written = codec.Write(buf, 0, value)
	local read, consumed = codec.Read(buf, 0)
	check(`{name} width`, written == size and consumed == size and buffer.len(buf) == size)
	checkEqual(`{name} value`, read, expected)
end

for _, value in { 0, 1, 127, 128, 16383, 16384, 2 ^ 31, 2 ^ 53 } do
	checkCodec(`varint {value}`, "varint", value, value)
end

for _, value in { 0, 1, -1, 127, -128, 16383, 16384, 2 ^ 31, -2 ^ 31, 2 ^ 52, -2 ^ 52 } do
	checkCodec(`zigzag {value}`, "zigzag", value, value)
end

do
	local bytes = table.create(256)
	for index = 1, 256 do
		bytes[index] = index - 1
	end
	local allBytes = string.char(table.unpack(bytes))
	checkCodec("string empty", "string", "", "")
	checkCodec("string ascii", "string", "hello", "hello")
	checkCodec("string all bytes", "string", allBytes, allBytes)
	checkCodec("string 1 MiB", "string", string.rep("x", 1024 * 1024), string.rep("x", 1024 * 1024))
end

do
	local buf = buffer.create(2)
	primitives.info.varint.Write(buf, 0, 300)
	checkEqual("varint encoding", buffer.tostring(buf), string.char(0xAC, 0x02))

	local signed = buffer.create(1)
	primitives.info.zigzag.Write(signed, 0, -1)
	checkEqual("zigzag encoding", buffer.tostring(signed), string.char(1))
end
do
	local buf = buffer.create(8)
	check("varint rejects negative", not pcall(primitives.info.varint.Write, buf, 0, -1))
	check("varint rejects fractional", not pcall(primitives.info.varint.Write, buf, 0, 1.5))
	check("zigzag rejects fractional", not pcall(primitives.info.zigzag.Write, buf, 0, 1.5))
end

local mixed = bufferize.Schema({ p.u16, p.varint, p.f64 }, function(v)
	return v[1], v[2], v[3]
end, function(id, count, score)
	return { id, count, score }
end)

do
	local payload = {
		{ 1, 0, 0.5 },
		{ 2, 127, 1.5 },
		{ 3, 300, 2.5 },
		{ 4, 2 ^ 40, 3.5 },
	}
	checkSame("variable rows round-trip", bufferize.Decode(bufferize.Encode(payload, mixed), mixed), payload)
end

local text = bufferize.Schema({ p.string, p.u8 }, function(v)
	return v[1], v[2]
end, function(value, tag)
	return { value, tag }
end)

do
	local payload = { { "", 1 }, { "hello", 2 }, { string.rep("x", 1024), 3 }, { string.char(0, 255, 0), 4 } }
	checkSame("string rows round-trip", bufferize.Decode(bufferize.Encode(payload, text), text), payload)
end

do
	local buf = bufferize.Encode({}, mixed)
	checkEqual("empty variable length", buffer.len(buf), 0)
	checkSame("empty variable round-trip", bufferize.Decode(buf, mixed), {})
end

do
	local encoded = bufferize.Encode({ { "hello", 1 } }, text)
	local truncated = buffer.fromstring(buffer.readstring(encoded, 0, buffer.len(encoded) - 1))
	check("truncated variable buffer raises", not pcall(bufferize.Decode, truncated, text))
end

do
	check("non-multiple buffer raises", not pcall(bufferize.Decode, buffer.create(3), row))
end

if failures > 0 then
	print(`{failures} test(s) failed`)
	process.exit(1)
end
print("all tests passed")
