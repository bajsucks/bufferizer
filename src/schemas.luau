--[[
    encode - type -> schema
    decode - schema -> type
]]
local primitives = require(script.Parent.primitives)
local p = primitives.types

export type Schema<T> = {
	map: { number },
	encode: (value: T) -> ...any,
	decode: (...any) -> T,
}

local schemas: { [string]: Schema<any> } = {
	Vector2 = {
		map = { p.f32, p.f32 },
		encode = function(v: Vector2)
			return v.X, v.Y
		end,
		decode = Vector2.new,
	},
	Vector3 = {
		map = { p.f32, p.f32, p.f32 },
		encode = function(v: Vector3)
			return v.X, v.Y, v.Z
		end,
		decode = Vector3.new,
	},
	CFrame = {
		map = { p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32 },
		encode = function(cf: CFrame)
			return cf:GetComponents()
		end,
		decode = CFrame.new,
	},
	Color3 = {
		map = { p.f32, p.f32, p.f32 },
		encode = function(c: Color3)
			return c.R, c.G, c.B
		end,
		decode = Color3.new,
	},
	UDim = {
		map = { p.f32, p.i32 },
		encode = function(u: UDim)
			return u.Scale, u.Offset
		end,
		decode = UDim.new,
	},
	UDim2 = {
		map = { p.f32, p.i32, p.f32, p.i32 },
		encode = function(u: UDim2)
			return u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset
		end,
		decode = UDim2.new,
	},
	number = {
		map = { p.f64 },
	},
	jecs_id = {
		map = { p.u16, p.u8 },
		encode = function(i24: number)
			local u24 = bit32.band(i24, 0xFFFFFF)
			return bit32.band(u24, 0xFFFF), bit32.rshift(u24, 16)
		end,
		decode = function(u16: number, u8: number)
			local u24 = bit32.bor(u16, bit32.lshift(u8, 16))
			return if u24 >= 0x800000 then u24 - 0x1000000 else u24
		end,
	},
}
return schemas
