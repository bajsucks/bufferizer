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

local lists = bufferize.Schema({ bufferize.Array(p.u8), p.u8 }, function(v)
	return v[1], v[2]
end, function(items, tag)
	return { items, tag }
end)

do
	local payload = { { { 1, 2, 3 }, 9 }, { {}, 8 }, { { 4 }, 7 } }
	local buf = bufferize.Encode(payload, lists)
	checkEqual("array layout", buffer.tostring(buf), string.char(3, 1, 2, 3, 9, 0, 8, 1, 4, 7))
	checkSame("array rows round-trip", bufferize.Decode(buf, lists), payload)
	checkEqual("array size matches encode", bufferize.Size(lists, payload), buffer.len(buf))
	check("array rejects a non-table", not pcall(bufferize.Encode, { { "abc", 1 } }, lists))
	check("array rejects an unknown element", not pcall(bufferize.Array, 99))

	local corrupted = bufferize.Encode({ { { 1, 2, 3 }, 9 } }, lists)
	buffer.writeu8(corrupted, 0, 2)
	local ok, decoded = pcall(bufferize.Decode, corrupted, lists)
	check("corrupted array count is not silent", not ok or not same(decoded, { { { 1, 2, 3 }, 9 } }))
end

local series = bufferize.Schema({ bufferize.Array(p.zigzag) }, function(values)
	return values
end, function(values)
	return values
end)

do
	local payload = { { 0, -1, 2 ^ 40 }, {}, { -2 ^ 52, 1 } }
	checkSame("varint array round-trip", bufferize.Decode(bufferize.Encode(payload, series), series), payload)
end

local triplets = bufferize.Schema({ bufferize.FixedArray(p.u16, 3), p.u8 }, function(v)
	return v[1], v[2]
end, function(items, tag)
	return { items, tag }
end)

do
	local payload = { { { 1, 2, 3 }, 9 }, { { 4, 5, 6 }, 8 } }
	local buf = bufferize.Encode(payload, triplets)
	checkEqual("fixed array row size", bufferize.Size(triplets), 7)
	checkEqual("fixed array payload size", bufferize.Size(triplets, payload), 14)
	checkSame("fixed array round-trip", bufferize.Decode(buf, triplets), payload)
	check("fixed array count raises", not pcall(bufferize.Encode, { { { 1, 2 }, 9 } }, triplets))
	check("fixed array fractional count raises", not pcall(bufferize.FixedArray, p.u8, 1.5))
end

local words = bufferize.Schema({ bufferize.FixedArray(p.string, 2), p.u8 }, function(v)
	return v[1], v[2]
end, function(items, tag)
	return { items, tag }
end)

do
	local payload = { { { "", "hi" }, 1 }, { { string.rep("x", 300), "y" }, 2 } }
	checkEqual("variable fixed array size", bufferize.Size(words), nil)
	checkSame("variable fixed array round-trip", bufferize.Decode(bufferize.Encode(payload, words), words), payload)
end

local counters = bufferize.Schema({ bufferize.Anchored() }, function(value)
	return value
end, function(value)
	return value
end)

do
	local payload = { 10, 11, 12 }
	local buf = bufferize.Encode(payload, counters)
	checkEqual("anchored layout", buffer.tostring(buf), string.char(20, 2, 4))
	checkEqual("anchored row size", bufferize.Size(counters), nil)
	checkEqual("anchored payload size", bufferize.Size(counters, payload), buffer.len(buf))
	checkSame("anchored round-trip", bufferize.Decode(buf, counters), payload)
	checkSame(
		"anchored wide round-trip",
		bufferize.Decode(bufferize.Encode({ -2 ^ 31, 2 ^ 31, 0, -5 }, counters), counters),
		{ -2 ^ 31, 2 ^ 31, 0, -5 }
	)
end

local stamped = bufferize.Schema({ p.u8, bufferize.Anchored() }, function(v)
	return v[1], v[2]
end, function(tag, value)
	return { tag, value }
end)

do
	local payload = { { 1, 500 }, { 2, 499 }, { 3, 5000 } }
	checkSame("anchored after fixed round-trip", bufferize.Decode(bufferize.Encode(payload, stamped), stamped), payload)
end

do
	local payload = table.create(1000, 7)
	local buf = bufferize.Encode(payload, counters)
	checkEqual("anchored identical size", buffer.len(buf), 1000)
	checkSame("anchored identical round-trip", bufferize.Decode(buf, counters), payload)
end

do
	local first = bufferize.Encode({ 1000, 1001 }, counters)
	local second = bufferize.Encode({ 5, 6 }, counters)
	checkSame("anchored first call", bufferize.Decode(first, counters), { 1000, 1001 })
	checkSame("anchored second call", bufferize.Decode(second, counters), { 5, 6 })
end

do
	check("anchored rejects fractional", not pcall(bufferize.Encode, { 1.5 }, counters))
end

do
	local encoded = bufferize.Encode({ { "hello", 1 } }, text)
	local truncated = buffer.fromstring(buffer.readstring(encoded, 0, buffer.len(encoded) - 1))
	check("truncated variable buffer raises", not pcall(bufferize.Decode, truncated, text))
end

do
	local calls = 0
	local counted = bufferize.Schema({ p.varint }, function(value)
		calls += 1
		return value
	end, function(value)
		return value
	end)
	bufferize.Encode({ 1, 2, 3 }, counted)
	checkEqual("variable encode runs twice per row", calls, 6)

	calls = 0
	local through = bufferize.Schema({ p.u8 }, function(value)
		calls += 1
		return value
	end, function(value)
		return value
	end)
	bufferize.Encode({ 1, 2, 3 }, through)
	checkEqual("fixed encode runs once per row", calls, 3)
end

do
	check("non-multiple buffer raises", not pcall(bufferize.Decode, buffer.create(3), row))
end

do
	local jecs = bufferize.schemas.jecs_id
	local payload = { -8388608, -5, 0, 8388607 }
	checkSame("jecs_id round-trip", bufferize.Decode(bufferize.Encode(payload, jecs), jecs), payload)
	check("jecs_id rejects past i24", not pcall(bufferize.Encode, { 8388608 }, jecs))
	check("jecs_id rejects below i24", not pcall(bufferize.Encode, { -8388609 }, jecs))
end

do
	checkEqual("size per row", bufferize.Size(row), 13)
	checkEqual("size per row with payload", bufferize.Size(row, { { 1, 1.5, 2.5 }, { 2, 3.5, 4.5 } }), 26)
	checkEqual("size of variable schema", bufferize.Size(mixed), nil)
end

do
	local payload = { { 1, 0, 0.5 }, { 2, 300, 1.5 }, { 3, 2 ^ 40, 2.5 } }
	checkEqual("size of variable payload", bufferize.Size(mixed, payload), 39)
	checkEqual("size matches encode", bufferize.Size(mixed, payload), buffer.len(bufferize.Encode(payload, mixed)))
	checkEqual("size of empty payload", bufferize.Size(mixed, {}), 0)
end

if failures > 0 then
	print(`{failures} test(s) failed`)
	process.exit(1)
end
print("all tests passed")
