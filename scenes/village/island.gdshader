shader_type canvas_item;
// PLACEHOLDER island look (plan.md §4, visual step 1) until the baked island art exists.
// Paints every pixel of the sea, the coast, rock cliffs, sandy beaches and grass, using a small
// data texture made once by island_map.gd. Only the water animates; nothing here is game state.
// Distances are in grid cells unless the name ends in "px" (pixels in the village, at zoom 1).

uniform sampler2D terrain : filter_linear, repeat_disable; // r = distance to the coast (negative on land), g = beachiness 0..1
uniform vec2 terrain_origin;  // grid cell at the texture's first pixel
uniform vec2 terrain_size;    // texture size in cells
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec4 plot_rect;       // buildable plot: x, y, width, height in cells
uniform vec2 tile_px = vec2(64.0, 32.0);
uniform vec2 shadow_px = vec2(0.9, 0.11);  // where shadows fall, per px of height (Iso.SHADOW)
uniform vec2 sun_dir = vec2(-0.86, 0.51);  // toward the sun, in grid directions (set from Iso.SHADOW)
uniform float cliff_px = 40.0;  // how high rocky coast stands above the sea (set from island_map.gd)
uniform float beach_px = 7.0;   // how high sandy coast stands above the sea (set from island_map.gd)
uniform bool detail = true;     // the "Water detail" setting: false skips ripples and wave marks

const vec3 DEEP = vec3(0.05, 0.22, 0.36);
const vec3 MID = vec3(0.08, 0.38, 0.55);
const vec3 SHALLOW = vec3(0.16, 0.62, 0.69);
const vec3 SHORE = vec3(0.47, 0.82, 0.77);
const vec3 FOAM = vec3(0.95, 0.98, 1.0);
const vec3 SAND = vec3(0.91, 0.83, 0.6);
const vec3 SAND_DARK = vec3(0.74, 0.62, 0.4);
const vec3 DIRT = vec3(0.56, 0.45, 0.3);
const vec3 GRASS_DARK = vec3(0.3, 0.52, 0.22);
const vec3 GRASS_LIGHT = vec3(0.47, 0.71, 0.3);
const vec3 ROCK_DARK = vec3(0.3, 0.27, 0.25);
const vec3 ROCK_LIGHT = vec3(0.66, 0.62, 0.55);
const float CELL_PX = 40.0;  // roughly how many px one cell spans on screen

varying vec2 world;  // this pixel's position in the village (same units as Iso.to_world)

void vertex() {
	world = VERTEX;
}

vec2 to_cell(vec2 px) {
	return vec2(px.x / tile_px.x + px.y / tile_px.y, px.y / tile_px.y - px.x / tile_px.x);
}

// The cloudy pattern at point p. `scale` = pattern units per px, `blur` = px per screen pixel.
// Together they choose how blurred a copy to read, so fine detail doesn't sparkle when zoomed out.
float noise_at(vec2 p, float scale, float blur) {
	float texels = scale * blur * float(textureSize(noise, 0).x);
	return textureLod(noise, p, log2(max(texels, 1.0))).r;
}

vec2 terrain_uv(vec2 cell) {
	return (cell - terrain_origin + 0.5) / terrain_size;
}

// Distance to the coast (negative on land), with a little wobble so the shore doesn't follow the grid.
float coast(vec2 cell) {
	return texture(terrain, terrain_uv(cell)).r + (noise_at(cell * 0.11, 0.11 / CELL_PX, 1.0) - 0.5) * 0.45;
}

float coast_px(vec2 px) {
	return coast(to_cell(px));
}

// Land is raised above the sea, so below a front edge you see its side (the cliff face).
// Returns how many px above this point the land's edge is, or -1 if there is no land within `lift_px`.
float edge_above(vec2 px, float lift_px, float here) {
	if (here > lift_px / tile_px.y * 1.42 + 0.6) {
		return -1.0;  // too far from the coast for any cliff to reach
	}
	float last_t = 0.0;
	float last_d = here;
	for (int i = 1; i <= 8; i++) {
		float t = lift_px * float(i) / 8.0;
		float d = coast_px(px - vec2(0.0, t));
		if (d < 0.0) {
			return mix(last_t, t, last_d / (last_d - d));  // land between the last two checks: find the edge
		}
		last_t = t;
		last_d = d;
	}
	return -1.0;
}

// The side of the raised land: rock on cliffs, a short sandy slope on beaches.
vec3 cliff_color(vec2 px, float t, float lift_px, float beach, float blur) {
	// Which way the face points decides how much sun it gets.
	vec2 edge = to_cell(px - vec2(0.0, t));
	float e = 0.08;
	vec2 slope = vec2(coast(edge + vec2(e, 0.0)) - coast(edge - vec2(e, 0.0)),
			coast(edge + vec2(0.0, e)) - coast(edge - vec2(0.0, e)));
	float sun = dot(normalize(slope + vec2(0.0001)), sun_dir) * 0.5 + 0.5;
	float down = clamp(t / lift_px, 0.0, 1.0);  // 0 = top of the face, 1 = the water line
	float layers = noise_at(px * vec2(0.006, 0.045), 0.045, blur);
	float cracks = noise_at(px * vec2(0.05, 0.006) + vec2(0.37), 0.05, blur);
	vec3 rock = mix(ROCK_DARK, ROCK_LIGHT, sun) * (0.78 + 0.35 * layers) * (0.88 + 0.18 * cracks);
	vec3 c = mix(rock, mix(SAND_DARK, SAND, sun), beach);
	c *= mix(1.0, mix(0.62, 0.85, beach), down * down);  // less light reaches the bottom
	float lip = 1.0 - smoothstep(1.5, 3.5, t);  // grass hanging over the top edge
	return mix(c, GRASS_DARK * 0.8, lip * (1.0 - beach));
}

// Grass, a lighter lawn on the buildable plot, and sand or dirt along the shore.
vec3 ground_color(vec2 px, vec2 cell, float here, float beach, float blur) {
	float patches = noise_at(cell * 0.045, 0.045 / CELL_PX, blur);
	float tufts = noise_at(px * 0.021, 0.021, blur);
	vec3 grass = mix(GRASS_DARK, GRASS_LIGHT, 0.3 + 0.45 * smoothstep(0.2, 0.8, patches));
	grass *= 0.93 + 0.14 * tufts;
	vec2 inside = min(cell - (plot_rect.xy - 0.5), (plot_rect.xy + plot_rect.zw - 0.5) - cell);
	float plot = smoothstep(-0.25, 0.25, min(inside.x, inside.y));
	grass = mix(grass, mix(grass, GRASS_LIGHT, 0.3), plot);
	float inland = -here;
	float width = mix(0.15, 1.3, beach) + (noise_at(cell * 0.2, 0.2 / CELL_PX, blur) - 0.5) * 0.5 * beach;
	float shore = 1.0 - smoothstep(width * 0.6, width, inland);
	vec3 c = mix(grass, mix(DIRT, SAND, beach) * (0.93 + 0.12 * tufts), shore);
	return c * (1.0 + 0.1 * (1.0 - smoothstep(0.0, 0.1, inland)));  // sunlit lip right at the edge
}

// A random-looking number 0..1 for each grid box `id` (`salt` picks a different one). Pure maths, no texture.
float box_random(vec2 id, float salt) {
	vec3 p = fract(vec3(id.xyx + salt * 17.0) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Short curved wave marks scattered over the sea, each drifting and fading in and out in turn.
// Hidden when zoomed far out, where they would be too small to see and would only flicker.
float wave_marks(vec2 px, float blur) {
	vec2 box = vec2(64.0, 32.0);
	vec2 id = floor(px / box);
	float life = fract(TIME * 0.22 + box_random(id, 0.0));  // each mark lives about 4.5 seconds
	vec2 center = (id + 0.5) * box + (vec2(box_random(id, 0.31), box_random(id, 0.67)) - 0.5) * vec2(30.0, 14.0);
	vec2 q = px - center - vec2(life * 8.0 - 4.0, 0.0);
	float line = 1.0 - smoothstep(0.5, 1.3, abs(q.y - (0.035 * q.x * q.x - 1.0)));  // a gentle arch
	float ends = 1.0 - smoothstep(4.0, 8.0, abs(q.x));
	float present = step(0.45, box_random(id, 0.93));  // about half the boxes have one
	return line * ends * sin(life * 3.1416) * present * (1.0 - smoothstep(1.2, 2.2, blur));
}

// The sea: lighter where shallow, drifting ripples, and near the island its shadow and foam.
vec3 water_color(vec2 px, vec2 cell, float foot, float lift_px, float beach, float here, float blur) {
	float depth = foot / mix(1.0, 1.8, beach);  // sandy shores shelve out further
	vec3 c = mix(SHORE, SHALLOW, smoothstep(0.0, 0.9, depth));
	c = mix(c, MID, smoothstep(0.7, 3.0, depth));
	c = mix(c, DEEP, smoothstep(2.5, 8.0, depth));

	// Two drifting layers of ripples, plus little wave marks out at sea (skipped on "Low" water
	// detail, which saves work on slow phones).
	if (detail) {
		float r1 = noise_at(cell * 0.09 + TIME * vec2(0.010, 0.004), 0.09 / CELL_PX, blur);
		float r2 = noise_at(cell * 0.13 + vec2(0.5) - TIME * vec2(0.004, 0.009), 0.13 / CELL_PX, blur);
		float ripple = r1 + r2 - 1.0;
		c *= 1.0 + ripple * 0.05;
		c += vec3(0.04, 0.06, 0.07) * smoothstep(0.1, 0.5, ripple);
		if (foot > 0.8) {  // not in the surf, where foam covers them anyway
			c = mix(c, vec3(0.85, 0.95, 1.0), wave_marks(px, blur) * 0.35 * smoothstep(0.8, 2.5, foot));
		}
	}

	if (foot > 3.0) {
		return c;  // far out at sea: no shadow or foam to add
	}
	float shade = 1.0 - smoothstep(-0.15, 0.3, coast_px(px - vec2(0.0, lift_px) - shadow_px * lift_px));
	c *= 1.0 - 0.28 * shade;

	float breakup = noise_at(cell * 0.35 + vec2(TIME * 0.02), 0.35 / CELL_PX, blur);
	float ring = 1.0 - smoothstep(0.06, 0.24 + 0.22 * breakup + 0.06 * sin(TIME * 1.3 + breakup * 6.0), foot);
	float waves = smoothstep(0.75, 0.95, sin(foot * 7.0 + TIME * 1.8 + breakup * 4.0));
	waves *= (1.0 - smoothstep(0.25, 1.2, foot)) * (0.4 + 0.6 * breakup);
	float back = 1.0 - smoothstep(0.0, 0.15, here);  // surf where hidden back cliffs meet the sea
	float foam = clamp(max(ring, waves * 0.6) + back * 0.7, 0.0, 1.0);
	return mix(c, FOAM, foam * 0.85);
}

void fragment() {
	vec2 cell = to_cell(world);
	float here = coast(cell);
	float beach = texture(terrain, terrain_uv(cell)).g;
	float lift_px = mix(cliff_px, beach_px, beach);
	// Measured here, before any branching (screen-pixel sizes can't be measured inside branches):
	float blur = max(abs(dFdx(world.x)), abs(dFdy(world.x)));  // px per screen pixel (1 / zoom)
	float aa = blur * 0.035;  // about one screen pixel, in cells: used to soften jagged edges

	vec3 c;
	if (here < 0.0) {
		c = ground_color(world, cell, here, beach, blur);
	} else {
		float t = edge_above(world, lift_px, here);
		vec3 outside;
		if (t >= 0.0) {
			outside = cliff_color(world, t, lift_px, beach, blur);
		} else {
			float foot = coast_px(world - vec2(0.0, lift_px));  // distance from the island's foot at sea level
			outside = water_color(world, cell, foot, lift_px, beach, here, blur);
			if (foot < aa) {  // right at the cliff's foot: soften the edge
				outside = mix(cliff_color(world, lift_px, lift_px, beach, blur), outside, foot / aa);
			}
		}
		c = here < aa ? mix(ground_color(world, cell, here, beach, blur), outside, here / aa) : outside;
	}
	COLOR = vec4(c, 1.0);
}
