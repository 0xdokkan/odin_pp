package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"

// A raw throw without committed effects (for example the dice laboratory).
// Gameplay supplies Dice_Outcome, including bonuses, instead of this label.
@(private)
draw_shock_floor_result_label :: proc(renderer: ^Dice_Renderer, layout: Dice_Pool_Layout, progress: f32, roll: game.Dice_Roll) {
    theme := renderer.theme if renderer != nil else nil
    title := fmt.ctprintf("%s / RISULTATO BASE", die_label(roll.sides))
    value := roll.total
    result := "LANCIO / TEMPO SOSPESO" if progress < DICE_PHYSICS_REVEAL_PROGRESS else fmt.ctprintf("DADO %d / PRIMA DEI BONUS",value)
    size := c.int(max(f32(12),14*layout.scale))
    x := c.int(layout.ground.x)
    y := c.int(layout.ground.y-layout.pixels_per_world*1.75)
    width := max(menu_measure_text(theme,title,size),menu_measure_text(theme,result,size))+24
    rl.DrawRectangle(x-width/2,y-8,width,size*2+28,{7,15,25,235})
    menu_text(theme,title,x-menu_measure_text(theme,title,size)/2,y,size,GOTHIC_BLUE)
    menu_text(theme,result,x-menu_measure_text(theme,result,size)/2,y+size+8,size,GOTHIC_PAPER)
}
