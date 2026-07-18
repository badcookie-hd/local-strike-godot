class_name LocalStrikeMaterialLibrary
extends RefCounted

const ROOT := "res://assets/textures/foundry/"

static var MATERIALS: Dictionary = {
	"concrete_worn": {"diff": "res://assets/textures/concrete_floor_worn_001_diff_1k.jpg", "normal": "res://assets/textures/concrete_floor_worn_001_normal_1k.jpg", "arm": "res://assets/textures/concrete_floor_worn_001_arm_1k.jpg", "roughness": 0.88, "metallic": 0.0, "scale": 0.28},
	"steel_plate": {"diff": "res://assets/textures/metal_plate_diff_1k.jpg", "normal": "res://assets/textures/metal_plate_normal_1k.jpg", "arm": "res://assets/textures/metal_plate_arm_1k.jpg", "roughness": 0.62, "metallic": 0.72, "scale": 0.34},
	"brick": _entry("brick_wall_001", 0.9, 0.0, 0.42),
	"rust": _entry("rusty_metal_02", 0.78, 0.58, 0.46),
	"corrugated": _entry("corrugated_iron_02", 0.66, 0.72, 0.38),
	"factory_wall": _entry("factory_wall", 0.9, 0.02, 0.34),
	"dirty_concrete": _entry("dirty_concrete", 0.94, 0.0, 0.3),
	"wood": _entry("wood_planks_dirt", 0.88, 0.0, 0.42),
	"rubber": _entry("rubber_tiles", 0.82, 0.0, 0.4),
	"metal_grate": _entry("metal_grate_rusty", 0.7, 0.64, 0.5),
	"painted_concrete": _entry("painted_concrete_02", 0.76, 0.02, 0.34),
	"hangar_floor": _entry("hangar_concrete_floor", 0.86, 0.0, 0.24)
}

static var _cache: Dictionary = {}

static func create(material_name: String, tint := Color.WHITE, uv_scale_multiplier := 1.0) -> StandardMaterial3D:
	var key := "%s:%s:%.3f" % [material_name, tint.to_html(), uv_scale_multiplier]
	if _cache.has(key):
		return _cache[key]
	var data: Dictionary = MATERIALS.get(material_name, MATERIALS["concrete_worn"])
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = load(str(data.diff))
	material.normal_enabled = true
	material.normal_texture = load(str(data.normal))
	material.normal_scale = 0.78
	var arm: Texture2D = load(str(data.arm))
	material.ao_enabled = true
	material.ao_texture = arm
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness = float(data.roughness)
	material.roughness_texture = arm
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.metallic = float(data.metallic)
	material.metallic_texture = arm
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	var scale := float(data.scale) * uv_scale_multiplier
	material.uv1_scale = Vector3(scale, scale, scale)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	_cache[key] = material
	return material

static func glass(tint := Color("78949c")) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(tint, 0.24)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.08
	material.metallic = 0.12
	material.refraction_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	material.refraction_scale = 0.035
	return material

static func oil() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.035, 0.04, 0.038, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.06
	material.metallic = 0.35
	return material

static func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.24
	material.emission_enabled = true
	material.emission = color * energy
	return material

static func _entry(id: String, roughness: float, metallic: float, scale: float) -> Dictionary:
	return {
		"diff": ROOT + id + "_diff_2k.jpg",
		"normal": ROOT + id + "_normal_2k.jpg",
		"arm": ROOT + id + "_arm_2k.jpg",
		"roughness": roughness,
		"metallic": metallic,
		"scale": scale
	}
