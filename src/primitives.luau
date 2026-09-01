return {
	types = {
		u8 = 1,
		u16 = 2,
		u32 = 3,
		i8 = 4,
		i16 = 5,
		i32 = 6,
		f32 = 7,
		f64 = 8,
	},
	reverse = {
		[1] = "u8",
		[2] = "u16",
		[3] = "u32",
		[4] = "i8",
		[5] = "i16",
		[6] = "i32",
		[7] = "f32",
		[8] = "f64",
	},
	info = {
		u8 = { Size = 1, Write = buffer.writeu8, Read = buffer.readu8 },
		u16 = { Size = 2, Write = buffer.writeu16, Read = buffer.readu16 },
		u32 = { Size = 4, Write = buffer.writeu32, Read = buffer.readu32 },
		i8 = { Size = 1, Write = buffer.writei8, Read = buffer.readi8 },
		i16 = { Size = 2, Write = buffer.writei16, Read = buffer.readi16 },
		i32 = { Size = 4, Write = buffer.writei32, Read = buffer.readi32 },
		f32 = { Size = 4, Write = buffer.writef32, Read = buffer.readf32 },
		f64 = { Size = 8, Write = buffer.writef64, Read = buffer.readf64 },
	},
	RAW = function<T>(n: T)
		return n
	end,
}
