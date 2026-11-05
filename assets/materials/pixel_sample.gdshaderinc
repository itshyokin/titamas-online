// Pixel-art texture sampling: shows textures as if they were `pixel_texels` texels across
// (per repeat), with hard square texels, whatever their real resolution. 0 = normal.
// Set from Settings (Graphics → Pixel textures) through the global shader uniform.
global uniform float pixel_texels;

// `repeats`: how many 4 m tiles one UV repeat covers (props whose texture spans the whole
// model pass their size / 4 so their texels match the terrain's).
vec4 px_sample_scaled(sampler2D tex, vec2 uv, float repeats) {
	if (pixel_texels <= 0.0) {
		return texture(tex, uv);
	}
	vec2 size = vec2(textureSize(tex, 0));
	// Mip level of the chosen pixel size, or coarser when far away (avoids shimmer).
	float base = log2(max(size.x / (pixel_texels * max(repeats, 0.01)), 1.0));
	vec2 dx = dFdx(uv * size);
	vec2 dy = dFdy(uv * size);
	float screen_lod = 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-8));
	float lod = floor(max(base, screen_lod) + 0.5);
	vec2 n = size / exp2(lod);
	vec2 snapped = (floor(uv * n) + 0.5) / n;
	return textureLod(tex, snapped, lod);
}

vec4 px_sample(sampler2D tex, vec2 uv) {
	return px_sample_scaled(tex, uv, 1.0);
}
