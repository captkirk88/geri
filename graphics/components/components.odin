package components

import "../../asset"
import "../../ecs"
import cimage "core:image"
import linalg "core:math/linalg"

RenderSpace :: enum {
	_2D,
	_3D,
}

Sprite :: struct {
	image:        asset.AssetId(cimage.Image),
	size:         linalg.Vector2f32,
	origin:       linalg.Vector2f32,
	color:        [4]f32,
	render_space: RenderSpace,
	camera:       ecs.Entity,
}

new_sprite :: proc(
	image: asset.AssetId(cimage.Image),
	size, origin: linalg.Vector2f32,
	color: [4]f32 = {1, 1, 1, 1},
	render_space: RenderSpace = ._2D,
	camera: ecs.Entity = {},
) -> Sprite {
	return Sprite {
		image = image,
		size = size,
		origin = origin,
		color = color,
		render_space = render_space,
		camera = camera,
	}
}

SpriteAnimation :: struct {
	frames: []asset.AssetId(cimage.Image),
	delays: []f32, // in seconds
}

AnimatedSprite :: struct {
	animation:     asset.AssetId(SpriteAnimation),
	current_frame: int,
	timer:         f32, // in seconds
	playing:       bool,
	loop:          bool,
	size:          linalg.Vector2f32,
	origin:        linalg.Vector2f32,
	color:         [4]f32,
	render_space:  RenderSpace,
	camera:        ecs.Entity,
}

new_animated_sprite :: proc(
	animation: asset.AssetId(SpriteAnimation),
	size, origin: linalg.Vector2f32,
	playing := true,
	loop := true,
	color: [4]f32 = {1, 1, 1, 1},
	render_space: RenderSpace = ._2D,
	camera: ecs.Entity = {},
) -> AnimatedSprite {
	return AnimatedSprite {
		animation = animation,
		current_frame = 0,
		timer = 0,
		playing = playing,
		loop = loop,
		size = size,
		origin = origin,
		color = color,
		render_space = render_space,
		camera = camera,
	}
}
Point_Light :: struct {
	intensity: f32,
	color:     [3]f32,
	radius:    f32,
}

// Component to target specific models with explicit lighting instead of global origin
Light_Target :: struct {
	light_entities: [4]ecs.Entity,
	num_targets:    i32,
}
