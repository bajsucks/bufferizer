# Bufferizer
Light, zero-dependency Luau SerDes library for homogeneous arrays.

## Install
### Forest
`forest i bajsucks/bufferizer`

### .rbxm
[Download the latest .rbxm release from Releases](https://github.com/bajsucks/bufferizer/releases/latest), or build from source via `rojo build`

## Use cases
- Networking and replication (especially ECS)
- Data saves, I guess?

## Usage
```luau
Bufferizer.Encode<T>(Payload: {T}, Schema: Schema<T>): buffer
Bufferizer.Decode<T>(buffer, Schema: Schema<T>): {T}
Bufferizer.Size<T>(Schema: Schema<T>, Payload: {T}?): number?
Bufferizer.schemas: {Schema<any>} -- out-of-the-box schemas
Bufferizer.primitives.types: {any} -- primitive column types (u8, i16, f32, string, etc.)
```

There is support for dynamic width data types:
- `varint` (int `0` to `2^53`)
- `zigzag` (int `-2^52` to `2^52`)
- `string`

Out-of-the-box schemas:
- `Vector2`
- `Vector3`
- `CFrame`
- `Color3`
- `UDim`
- `UDim2`
- `number` (f64)
- `jecs_id` (i24)

## Defining new schemas
If you want a custom type, you will have to create a schema.
For example, Vector3 schema:
```luau
-- p = Bufferizer.primitives.types

Bufferizer.Schema(
	{ p.f32, p.f32, p.f32 }, -- `map`, maps the primitives returned by `encode`
	function(v: Vector3) -- `encode`, converts the type into primitives
		return v.X, v.Y, v.Z
	end,
	Vector3.new -- `decode` converts the primitives back into the type
)
```
It's as simple as that!

You can also skip encode/decode when the schema has a single column:
```luau
-- p = Bufferizer.primitives.types

Bufferizer.Schema( -- Luau number
	{ p.f64 },
)
```

## Dynamic width types, Array, FixedArray and Anchored
`varint`, `zigzag` and `string` only write as many bytes as a value needs:
```luau
-- p = Bufferizer.primitives.types

local event = Bufferizer.Schema(
	{ p.string, p.u32, p.zigzag },
	function(e)
		return e.name, e.actor, e.score
	end,
	function(name: string, actor: number, score: number)
		return { name = name, actor = actor, score = score }
	end
)

local buf = Bufferizer.Encode(
	{
		{ name = "hit", actor = 12, score = -5 },
		{ name = "died", actor = 12, score = 2 ^ 40 },
	}, event
)

Bufferizer.Decode(buf, event) -- the same 2 rows
```

`Array` is a list per row. Every row reads its own count back, so rows may hold different amounts, and an empty list is fine:
```luau
-- p = Bufferizer.primitives.types

local inventory = Bufferizer.Schema(
	{ p.string, Bufferizer.Array(p.u16) },
	function(player)
		return player.name, player.items
	end,
	function(name: string, items: {number})
		return { name = name, items = items }
	end
)

local buf = Bufferizer.Encode({
	{ name = "pupa", items = {} },
	{ name = "lupa", items = { 4096, 4095, 4094 } },
}, inventory)

Bufferizer.Decode(buf, inventory) -- 2 rows, 2 different lengths
```
Elements of .Array() are primitives.

`FixedArray` is a list with a known count and no count prefix, so it stays fixed width:
```luau
-- p = Bufferizer.primitives.types

local box = Bufferizer.Schema(
	{ Bufferizer.FixedArray(p.f32, 3), Bufferizer.FixedArray(p.f32, 3) },
	function(b)
		return b.center, b.size
	end,
	function(center: {number}, size: {number})
		return { center = center, size = size }
	end
)

Bufferizer.Size(box) -- 24 bytes per row

local buf = Bufferizer.Encode({ { center = { 0, 0, 0 }, size = { 1, 2, 3 } } }, box)
Bufferizer.Decode(buf, box) -- { center = { 0, 0, 0 }, size = { 1, 2, 3 } }
```
A row with the wrong element count will throw an error.

`Anchored` writes the first row in full and then only how much each row changed from the one before it, which makes slow-moving columns (timestamps, ids) efficient:
```luau
-- p = Bufferizer.primitives.types
local log = Bufferizer.Schema({ p.string, Bufferizer.Anchored() }, function(entry)
	return entry.action, entry.tick
end, function(action, tick)
	return { action = action, tick = tick }
end)

local buf = Bufferizer.Encode({
	{ action = "spawn", tick = 1000000 },
	{ action = "move", tick = 1000001 },
	{ action = "move", tick = 1000002 },
}, log)

buffer.len(buf) -- 21 bytes, against 28 with i32 ticks
Bufferizer.Decode(buf, log) -- the same three rows
```
It can't be nested inside .Array() and takes ints.

First row can be `-2^52` to `2^52`, and each step between rows must stay within `2^52`.