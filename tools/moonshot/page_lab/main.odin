// Isolated Fase 1 driver. PAGE_LAB_BENCHMARK=true selects the scene's timed
// protocol; without it the same scene writes its deterministic smoke captures.
package main

import "core:fmt"
import "core:os"
import app "../../../src/engine/app"
import host "../../../src/engine/host"
import run "../../../src/run"

main :: proc() {
	status := page_lab_driver()
	if status != 0 { os.exit(status) }
}

@(private)
page_lab_driver :: proc() -> int {
	if len(os.args) != 1 {
		fmt.eprintln("Il driver pagina non accetta argomenti; usa PAGE_LAB_BENCHMARK a compilazione.")
		return 2
	}
	h, ok := host.create({
		window = {
			title = "Odin PP - laboratorio pagina / driver",
			initial_width = 1280, initial_height = 720,
			canvas_width = 1920, canvas_height = 1080,
			minimum_window_width = 640, minimum_window_height = 360,
			target_fps = 60, initial_scale_mode = .Fit, pixel_art = true,
		},
		profile_path = "", enable_audio = false,
		force_focus = true, keep_running = true,
	})
	if !ok {
		fmt.eprintln("Laboratorio pagina: impossibile aprire la finestra.")
		return 2
	}
	defer host.destroy(h)
	// Fix both logical coordinates and actual raster pixels: Retina scaling,
	// resizing or another monitor must not silently change the measured target.
	h.window.fixed_canvas_size = {1920, 1080}
	app.refresh_viewport(&h.window)
	if h.window.canvas_degraded || h.window.canvas.texture.width != 1920 || h.window.canvas.texture.height != 1080 {
		fmt.eprintln("Laboratorio pagina: canvas reale 1920x1080 non disponibile.")
		return 2
	}
	fmt.printf("PAGE LAB DRIVER logical=%dx%d raster=%dx%d profile=off audio=off\n",
		h.window.config.canvas_width, h.window.config.canvas_height,
		h.window.canvas.texture.width, h.window.canvas.texture.height)
	if !host.push_scene(h, run.page_lab_scene(true)) {
		fmt.eprintln("Laboratorio pagina: impossibile aprire la scena.")
		return 2
	}
	host.run(h)
	return 0
}
