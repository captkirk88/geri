package graphics

import "../app"
import "../asset"
import camera "../camera"
import "../ecs"
import "../ecs/params"
import transform "../transform"
import "base:runtime"
import "core:image"
import "core:math/linalg"
import "core:sync"
import "./components"

get_pixel :: proc(img: ^image.Image, x, y: int) -> [4]f32 {
	idx := (y * img.width + x) * 4
	if idx < 0 || idx + 3 >= len(img.pixels.buf) do return {0, 0, 0, 0}
	return {
		f32(img.pixels.buf[idx + 0]) / 255.0,
		f32(img.pixels.buf[idx + 1]) / 255.0,
		f32(img.pixels.buf[idx + 2]) / 255.0,
		f32(img.pixels.buf[idx + 3]) / 255.0,
	}
}

project_point_2d :: proc(vp: linalg.Matrix4f32, p: [2]f32) -> [2]f32 {
	p4 := [4]f32{p.x, p.y, 0.0, 1.0}
	res4 := vp * p4
	if res4.w != 0.0 do return res4.xy / res4.w
	return res4.xy
}

project_point_3d :: proc(vp: linalg.Matrix4f32, p: [3]f32) -> [3]f32 {
	p4 := [4]f32{p.x, p.y, p.z, 1.0}
	res4 := vp * p4
	if res4.w != 0.0 do return res4.xyz / res4.w
	return res4.xyz
}

draw_sprite_2d :: proc(
	batch: ^Batch2D,
	img: ^image.Image,
	local_to_world: linalg.Matrix4f32,
	size: [2]f32,
	origin: [2]f32,
	color_tint: [4]f32,
	vp: linalg.Matrix4f32,
) {
	if img == nil || len(img.pixels.buf) == 0 do return

	pixel_w := size.x / f32(img.width)
	pixel_h := size.y / f32(img.height)

	mvp := vp * local_to_world

	for py in 0 ..< img.height {
		px := 0
		for px < img.width {
			col := get_pixel(img, px, py)
			if col.a == 0 {
				px += 1
				continue
			}

			run := 1
			for px + run < img.width {
				next_col := get_pixel(img, px + run, py)
				if next_col == col {
					run += 1
				} else {
					break
				}
			}

			lx0 := (f32(px) - origin.x * f32(img.width)) * pixel_w
			lx1 := (f32(px + run) - origin.x * f32(img.width)) * pixel_w
			ly0 := (origin.y * f32(img.height) - f32(py + 1)) * pixel_h
			ly1 := (origin.y * f32(img.height) - f32(py)) * pixel_h

			c := col * color_tint

			p0 := project_point_2d(mvp, {lx0, ly0})
			p1 := project_point_2d(mvp, {lx1, ly0})
			p2 := project_point_2d(mvp, {lx1, ly1})
			p3 := project_point_2d(mvp, {lx0, ly1})

			base_idx := u32(len(batch.vertices))
			append(&batch.vertices,
				Vertex2D{position = p0, color = c},
				Vertex2D{position = p1, color = c},
				Vertex2D{position = p2, color = c},
				Vertex2D{position = p3, color = c},
			)
			append(&batch.indices,
				base_idx + 0, base_idx + 1, base_idx + 2,
				base_idx + 0, base_idx + 2, base_idx + 3,
			)

			px += run
		}
	}
}

draw_sprite_3d :: proc(
	batch: ^Batch3D,
	img: ^image.Image,
	local_to_world: linalg.Matrix4f32,
	size: [2]f32,
	origin: [2]f32,
	color_tint: [4]f32,
	vp: linalg.Matrix4f32,
) {
	if img == nil || len(img.pixels.buf) == 0 do return

	pixel_w := size.x / f32(img.width)
	pixel_h := size.y / f32(img.height)

	mvp := vp * local_to_world

	for py in 0 ..< img.height {
		px := 0
		for px < img.width {
			col := get_pixel(img, px, py)
			if col.a == 0 {
				px += 1
				continue
			}

			run := 1
			for px + run < img.width {
				next_col := get_pixel(img, px + run, py)
				if next_col == col {
					run += 1
				} else {
					break
				}
			}

			lx0 := (f32(px) - origin.x * f32(img.width)) * pixel_w
			lx1 := (f32(px + run) - origin.x * f32(img.width)) * pixel_w
			ly0 := (origin.y * f32(img.height) - f32(py + 1)) * pixel_h
			ly1 := (origin.y * f32(img.height) - f32(py)) * pixel_h

			c := col * color_tint

			p0 := project_point_3d(mvp, {lx0, ly0, 0.0})
			p1 := project_point_3d(mvp, {lx1, ly0, 0.0})
			p2 := project_point_3d(mvp, {lx1, ly1, 0.0})
			p3 := project_point_3d(mvp, {lx0, ly1, 0.0})

			base_idx := u32(len(batch.vertices))
			append(&batch.vertices,
				Vertex3D{position = p0, color = c},
				Vertex3D{position = p1, color = c},
				Vertex3D{position = p2, color = c},
				Vertex3D{position = p3, color = c},
			)
			append(&batch.indices,
				base_idx + 0, base_idx + 1, base_idx + 2,
				base_idx + 0, base_idx + 2, base_idx + 3,
			)

			px += run
		}
	}
}

resolve_camera_vp :: proc(world: ^ecs.World, camera_entity: ecs.Entity) -> linalg.Matrix4f32 {
	if world == nil do return linalg.MATRIX4F32_IDENTITY

	// Try resolving the specific requested local camera entity
	if camera_entity.id > 0 {
		cam := ecs.world_get_component(world, camera_entity, camera.Camera)
		t := ecs.world_get_component(world, camera_entity, transform.Transform)
		if cam != nil && t != nil {
			return camera.get_view_projection(cam^, t^)
		}
	}

	// Fallback: search for first camera in the world
	for arch in ecs.query(world, transform.Transform, camera.Camera) {
		transforms := ecs.arch_get_field(arch, transform.Transform)
		cameras := ecs.arch_get_field(arch, camera.Camera)
		if len(cameras) > 0 {
			return camera.get_view_projection(cameras[0], transforms[0])
		}
	}

	return linalg.MATRIX4F32_IDENTITY
}

@(tag = "system")
sprite_animation_system :: proc(
	world: ^ecs.World,
	dt_res: params.Res(app.DeltaTime),
) {
	if world == nil || dt_res.ptr == nil do return
	dt := dt_res.ptr.f32_seconds

	server := ecs.world_get_resource(world, asset.AssetServer)
	if server == nil do return

	// Find the SpriteAnimation AssetManager
	sync.mutex_lock(&server.mutex)
	mgr_val, has_mgr := server.managers[typeid_of(components.SpriteAnimation)]
	sync.mutex_unlock(&server.mutex)
	if !has_mgr || mgr_val.manager_ptr == nil do return
	anim_mgr := (^asset.AssetManager(components.SpriteAnimation))(mgr_val.manager_ptr)

	for arch in ecs.query(world, components.AnimatedSprite) {
		sprites := ecs.arch_get_field(arch, components.AnimatedSprite)
		for i in 0 ..< len(sprites) {
			sprite := &sprites[i]
			if !sprite.playing do continue

			// Get the SpriteAnimation asset
			sync.mutex_lock(&anim_mgr.mutex)
			anim, ok := anim_mgr.assets[sprite.animation.id]
			sync.mutex_unlock(&anim_mgr.mutex)
			if !ok || len(anim.frames) == 0 do continue

			sprite.timer += dt
			
			for {
				duration := anim.delays[sprite.current_frame]
				if sprite.timer >= duration {
					sprite.timer -= duration
					sprite.current_frame += 1
					if sprite.current_frame >= len(anim.frames) {
						if sprite.loop {
							sprite.current_frame = 0
						} else {
							sprite.current_frame = len(anim.frames) - 1
							sprite.playing = false
							sprite.timer = 0
							break
						}
					}
				} else {
					break
				}
			}
		}
	}
}

@(tag = "system")
sprite_render_system :: proc(
	world: ^ecs.World,
	batch2d: params.Res(Batch2D),
	batch3d: params.Res(Batch3D),
) {
	if world == nil do return
	server := ecs.world_get_resource(world, asset.AssetServer)
	if server == nil do return

	// Get image manager
	sync.mutex_lock(&server.mutex)
	img_mgr_val, has_img_mgr := server.managers[typeid_of(image.Image)]
	anim_mgr_val, has_anim_mgr := server.managers[typeid_of(components.SpriteAnimation)]
	sync.mutex_unlock(&server.mutex)

	if !has_img_mgr do return
	img_mgr := (^asset.AssetManager(image.Image))(img_mgr_val.manager_ptr)
	anim_mgr: ^asset.AssetManager(components.SpriteAnimation)
	if has_anim_mgr && anim_mgr_val.manager_ptr != nil {
		anim_mgr = (^asset.AssetManager(components.SpriteAnimation))(anim_mgr_val.manager_ptr)
	}

	// 1. Draw static Sprites
	for arch in ecs.query(world, transform.Transform, components.Sprite) {
		transforms := ecs.arch_get_field(arch, transform.Transform)
		sprites := ecs.arch_get_field(arch, components.Sprite)

		for i in 0 ..< len(transforms) {
			t := transforms[i]
			sprite := sprites[i]

			// Get image asset
			sync.mutex_lock(&img_mgr.mutex)
			img, ok := img_mgr.assets[sprite.image.id]
			sync.mutex_unlock(&img_mgr.mutex)
			if !ok do continue

			vp := resolve_camera_vp(world, sprite.camera)
			local_to_world := t.world_matrix

			if sprite.render_space == ._2D {
				if batch2d.ptr != nil {
					draw_sprite_2d(batch2d.ptr, &img, local_to_world, sprite.size, sprite.origin, sprite.color, vp)
				}
			} else {
				if batch3d.ptr != nil {
					draw_sprite_3d(batch3d.ptr, &img, local_to_world, sprite.size, sprite.origin, sprite.color, vp)
				}
			}
		}
	}

	// 2. Draw Animated Sprites
	if anim_mgr == nil do return
	for arch in ecs.query(world, transform.Transform, components.AnimatedSprite) {
		transforms := ecs.arch_get_field(arch, transform.Transform)
		sprites := ecs.arch_get_field(arch, components.AnimatedSprite)

		for i in 0 ..< len(transforms) {
			t := transforms[i]
			sprite := sprites[i]

			// Get animation asset
			sync.mutex_lock(&anim_mgr.mutex)
			anim, ok := anim_mgr.assets[sprite.animation.id]
			sync.mutex_unlock(&anim_mgr.mutex)
			if !ok || len(anim.frames) == 0 do continue

			// Get active frame image
			frame_id := anim.frames[sprite.current_frame]
			sync.mutex_lock(&img_mgr.mutex)
			img, img_ok := img_mgr.assets[frame_id.id]
			sync.mutex_unlock(&img_mgr.mutex)
			if !img_ok do continue

			vp := resolve_camera_vp(world, sprite.camera)
			local_to_world := t.world_matrix

			if sprite.render_space == ._2D {
				if batch2d.ptr != nil {
					draw_sprite_2d(batch2d.ptr, &img, local_to_world, sprite.size, sprite.origin, sprite.color, vp)
				}
			} else {
				if batch3d.ptr != nil {
					draw_sprite_3d(batch3d.ptr, &img, local_to_world, sprite.size, sprite.origin, sprite.color, vp)
				}
			}
		}
	}
}
