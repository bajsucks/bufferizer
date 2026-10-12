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

if failures > 0 then
	print(`{failures} test(s) failed`)
	process.exit(1)
end
print("all tests passed")
