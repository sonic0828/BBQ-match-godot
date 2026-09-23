class_name FoodArt
extends RefCounted

const REGIONS = {
	"L": Rect2(52, 14, 126, 265), "C": Rect2(242, 12, 137, 268),
	"J": Rect2(432, 17, 138, 263), "S": Rect2(603, 17, 112, 263),
	"W": Rect2(922, 19, 166, 259), "M": Rect2(1216, 15, 126, 265),
	"E": Rect2(39, 285, 134, 252), "O": Rect2(206, 291, 159, 249)
}
static var textures: Dictionary = {}
static var grill_texture: AtlasTexture

static func food(id: String) -> Texture2D:
	if not textures.has(id):
		var atlas = AtlasTexture.new()
		atlas.atlas = load("res://assets/art/foods.png")
		atlas.region = REGIONS[id]
		atlas.filter_clip = true
		textures[id] = atlas
	return textures[id]

static func grill() -> Texture2D:
	if grill_texture == null:
		grill_texture = AtlasTexture.new()
		grill_texture.atlas = load("res://assets/art/grill.png")
		grill_texture.region = Rect2(89, 285, 1078, 692)
		grill_texture.filter_clip = true
	return grill_texture
