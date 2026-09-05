class_name Palette
extends RefCounted
## Default skin colours, chosen to stay distinct in print and for common colour-vision deficiency.

const COLORS: Array[Color] = [
	Color("1f8a8a"),  # teal   (Tori)
	Color("e0a030"),  # amber  (Uke 1)
	Color("7b5ea7"),  # violet (Uke 2)
	Color("4f9d4f"),  # green  (Uke 3)
	Color("d1607a"),  # rose   (Uke 4)
]


static func color_for_index(i: int) -> Color:
	return COLORS[i % COLORS.size()]
