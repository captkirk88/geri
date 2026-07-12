package components

import "../../asset"
import cimage "core:image"
import linalg "core:math/linalg"

Sprite :: struct {
	image:  asset.AssetId(cimage.Image),
	size:   linalg.Vector2f32,
	origin: linalg.Vector2f32,
}

new_sprite :: proc(image: asset.AssetId(cimage.Image), size, origin: linalg.Vector2f32) -> Sprite {
	return Sprite{image = image, size = size, origin = origin}
}
