# Bufferizer

Light, zero-dependency Luau SerDes library for homogeneous arrays.

Install with Wally: Add "bajsucks/bufferizer@^0.1.0" to your wally.toml and run `wally install`.

Install manually: Download the latest .rbxm release from Releases, or build from source via `rojo build`

## Use cases
- Networking and replication (especially ECS)
- Data saves, I guess?

## Usage
```luau
Bufferizer.Encode<T>(Payload: {T}, Schema: Schema<T>): buffer
Bufferizer.Decode<T>(buffer, Schema: Schema<T>): {T}
Bufferizer.schemas: {Schema<any>} -- out-of-the-box schemas
Bufferizer.primitives.types: {any} -- primitive number types (u8, i16, f32, etc.)
```

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

You can also skip encode/decode for pure primitives:
```luau
-- p = Bufferizer.primitives.types
Bufferizer.Schema( -- Luau number
	{ p.f64 },
)
```