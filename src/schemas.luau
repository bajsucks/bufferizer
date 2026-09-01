--[[
    encode - type -> schema
    decode - schema -> type
]]
local primitives = require(script.Parent.primitives)
local p = primitives.types

export type Schema = { map: { number }, encode: (any) -> any, decode: (any) -> any }

local schemas: { [string]: Schema } = {
	Vector3 = {
		map = { p.f32, p.f32, p.f32 },
		encode = function(v: Vector3)
			return v.X, v.Y, v.Z
		end,
		decode = Vector3.new,
	},
	number = {
		map = { p.f64 },
		encode = p.RAW,
		decode = p.RAW,
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
