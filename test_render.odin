package test_render

import "core:testing"
import graphics "src/graphics"

main :: proc() {
	t := testing.T{}
	graphics.test_render_pipeline_initialization(&t)
}
