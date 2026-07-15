class_name LocalStrikeQualityManager
extends RefCounted

enum Profile { HIGH, MEDIUM, LOW }

static func apply_profile(
	viewport: Viewport,
	environment: Environment,
	sun: DirectionalLight3D,
	profile: int,
	effects: Node = null
) -> void:
	var quality := clampi(profile, Profile.HIGH, Profile.LOW)
	var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	match quality:
		Profile.HIGH:
			viewport.msaa_3d = Viewport.MSAA_4X
			viewport.scaling_3d_scale = 1.0
			viewport.positional_shadow_atlas_size = 4096
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 64.0
			environment.ssao_enabled = true
			environment.ssil_enabled = not compatibility
			environment.ssr_enabled = not compatibility
			environment.glow_enabled = true
			environment.fog_enabled = compatibility
			environment.volumetric_fog_enabled = not compatibility
		Profile.MEDIUM:
			viewport.msaa_3d = Viewport.MSAA_2X
			viewport.scaling_3d_scale = 0.9
			viewport.positional_shadow_atlas_size = 2048
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 48.0
			environment.ssao_enabled = true
			environment.ssil_enabled = false
			environment.ssr_enabled = false
			environment.glow_enabled = true
			environment.fog_enabled = true
			environment.volumetric_fog_enabled = false
		_:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.scaling_3d_scale = 0.78
			viewport.positional_shadow_atlas_size = 1024
			sun.shadow_enabled = false
			environment.ssao_enabled = false
			environment.ssil_enabled = false
			environment.ssr_enabled = false
			environment.glow_enabled = false
			environment.fog_enabled = false
			environment.volumetric_fog_enabled = false
	if effects != null and effects.has_method("set_quality"):
		effects.set_quality(quality, compatibility)

