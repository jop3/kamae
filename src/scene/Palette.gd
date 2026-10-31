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


## Default realistic looks, by the same index as the colours: Tori an older man with short hair,
## the Ukes younger and each different, so who is who reads from the people as well as the belts.
const APPEARANCES: Array[Dictionary] = [
	{"look": "realistic", "skin": "middleage_caucasian_male", "hair": "short02", "hair_color": "#9a9590", "eyes": "grey"},
	{"look": "realistic", "skin": "young_caucasian_male", "hair": "short04", "eyes": "blue"},
	{"look": "realistic", "skin": "young_asian_male", "hair": "short01", "eyes": "brown"},
	{"look": "realistic", "skin": "young_african_male", "hair": "short04", "hair_color": "#3a3a3a", "eyes": "brown"},
	{"look": "realistic", "skin": "young_caucasian_female", "hair": "ponytail01", "eyes": "green"},
]


static func appearance_for_index(i: int) -> Dictionary:
	return APPEARANCES[i % APPEARANCES.size()].duplicate()
