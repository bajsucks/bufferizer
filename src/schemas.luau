--[[
    encode - type -> schema
    decode - schema -> type
]]
local primitives = require("./primitives")
local p = primitives.types

export type Schema<T> = {
	map: { primitives.Column },
	encode: (value: T) -> ...any,
	decode: (...any) -> T,
}

-- datatypes resolve at call time so the module loads outside Roblox
local schemas: { [string]: Schema<any> } = {
	Vector2 = {
		map = { p.f32, p.f32 },
		encode = function(v: Vector2)
			return v.X, v.Y
		end,
		decode = function(x: number, y: number)
			return Vector2.new(x, y)
		end,
	},
	Vector3 = {
		map = { p.f32, p.f32, p.f32 },
		encode = function(v: Vector3)
			return v.X, v.Y, v.Z
		end,
		decode = function(x: number, y: number, z: number)
			return Vector3.new(x, y, z)
		end,
	},
	CFrame = {
		map = { p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32, p.f32 },
		encode = function(cf: CFrame)
			return cf:GetComponents()
		end,
		decode = function(
			x: number,
			y: number,
			z: number,
			r00: number,
			r01: number,
			r02: number,
			r10: number,
			r11: number,
			r12: number,
			r20: number,
			r21: number,
			r22: number
		)
			return CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		end,
	},
	Color3 = {
		map = { p.f32, p.f32, p.f32 },
		encode = function(c: Color3)
			return c.R, c.G, c.B
		end,
		decode = function(r: number, g: number, b: number)
			return Color3.new(r, g, b)
		end,
	},
	UDim = {
		map = { p.f32, p.i32 },
		encode = function(u: UDim)
			return u.Scale, u.Offset
		end,
		decode = function(scale: number, offset: number)
			return UDim.new(scale, offset)
		end,
	},
	UDim2 = {
		map = { p.f32, p.i32, p.f32, p.i32 },
		encode = function(u: UDim2)
			return u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset
		end,
		decode = function(xs: number, xo: number, ys: number, yo: number)
			return UDim2.new(xs, xo, ys, yo)
		end,
	},
	number = {
		map = { p.f64 },
	},
	jecs_id = {
		map = { p.u16, p.u8 },
		encode = function(i24: number)
			assert(i24 >= -0x800000 and i24 < 0x800000, `jecs_id expects an i24, got {i24}`)
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
