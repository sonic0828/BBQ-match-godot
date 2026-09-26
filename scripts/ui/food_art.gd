class_name FoodArt
extends RefCounted

const REGIONS = {
	"L": Rect2(52, 14, 126, 265), "C": Rect2(242, 12, 137, 268),
	"J": Rect2(432, 17, 138, 263), "S": Rect2(603, 17, 112, 263),
	"W": Rect2(922, 19, 166, 259), "M": Rect2(1216, 15, 126, 265),
	"E": Rect2(39, 285, 134, 252), "O": Rect2(206, 291, 159, 249)
}
const COMBO_REGIONS = {
	"L": Rect2(0, 104, 248, 234), "C": Rect2(248, 104, 241, 234),
	"J": Rect2(489, 104, 240, 234), "S": Rect2(729, 104, 238, 234),
	"W": Rect2(967, 104, 240, 234), "M": Rect2(1207, 104, 241, 234),
	"E": Rect2(0, 340, 248, 223), "O": Rect2(248, 340, 241, 223)
}
static var textures: Dictionary = {}
static var combo_textures: Dictionary = {}
static var grill_texture: AtlasTexture

static func food(id: String) -> Texture2D:
	if not textures.has(id):
		var atlas = AtlasTexture.new()
		atlas.atlas = load("res://assets/art/foods.png")
		atlas.region = REGIONS[id]
		atlas.filter_clip = true
		textures[id] = atlas
	return textures[id]

static func combo(id: String) -> Texture2D:
	if not combo_textures.has(id):
		var atlas = AtlasTexture.new()
		atlas.atlas = load("res://assets/art/food-combo-sprite.png")
		atlas.region = COMBO_REGIONS[id]
		atlas.filter_clip = true
		combo_textures[id] = atlas
	return combo_textures[id]

static func grill() -> Texture2D:
	if grill_texture == null:
		grill_texture = AtlasTexture.new()
		grill_texture.atlas = load("res://assets/art/grill.png")
		grill_texture.region = Rect2(89, 285, 1078, 692)
		grill_texture.filter_clip = true
	return grill_texture
