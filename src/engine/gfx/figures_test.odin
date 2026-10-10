package gfx

import "core:testing"
import rl "vendor:raylib"

@(test)
test_paper_billboard_flip_preserves_atlas_cell :: proc(t: ^testing.T) {
	figures: Paper_Figures
	figures.sources[0]={0,0,127,158}
	figures.sources[1]={160,0,149,156}
	for index in 0..<2 {
		source:=figures.sources[index]
		normal:=paper_figure_source(&figures,index)
		flipped:=paper_figure_source(&figures,index,true)
		testing.expect_value(t,normal,source)
		testing.expect_value(t,flipped,rl.Rectangle{source.x+source.width,source.y,-source.width,source.height})
		// The billboard UV endpoints reverse, but keep exactly the same bounds.
		testing.expect_value(t,flipped.x,normal.x+normal.width)
		testing.expect_value(t,flipped.x+flipped.width,normal.x)
	}
}
