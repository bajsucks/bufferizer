# Bufferizer

Light, zero-dependency Luau SerDes library for homogeneous arrays.

Install with Wally: Add "baj/bufferizer@^0.1.0" to your wally.toml and run `wally install`.

Install manually: Download the latest .rbxm release from Releases, or build from source via `rojo build`

## Use cases
- Networking and replication (especially ECS)
- Data saves, I guess?

## Usage
```luau
Bufferizer.Encode<T>(Payload: {T}, Schema): buffer
Bufferizer.Decode<T>(buffer, Schema): {T}
```

Out-of-the-box types:
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
{
	map = { p.f32, p.f32, p.f32 },
	encode = function(v: Vector3)
		return v.X, v.Y, v.Z
	end,
	decode = Vector3.new,
}
```
`map` maps the primitives returned by `encode`,
`encode` converts the type into primitives,
`decode` converts the primitives back into the type.
It's as simple as that!

You can also skip encode/decode for pure primitives.
Example: 64-bit float schema:
```luau
{
	map = { p.f64 }
}
```