package combatdebug

import "core:fmt"
import "core:os"
import "core:encoding/json"
import game "../game"

write_clock_metrics :: proc(player: ^game.Player, seed: u64, output: string) -> bool {
	report := struct {schema_version: int, seed: u64, config: game.Tactical_Config, metrics: game.Tactical_Metrics}{
		3, seed, player.tactical.config, player.tactical.metrics}
	data, err := json.marshal(report)
	if err != nil { return false }
	defer delete(data)
	base := output
	if len(base) == 0 { base = fmt.tprintf("odin_pp_m7_%d", seed) }
	for index in 0..<8192 {
		path := fmt.tprintf("%s.m7_%d.json", base, index)
		file, err := os.open(path, {.Write, .Create, .Excl})
		if err == .Exist { continue }
		if err != nil { return false }
		count, write_err := os.write(file, data)
		close_err := os.close(file)
		if write_err != nil || close_err != nil || count != len(data) { return false }
		fmt.printf("wrote %s\n", path)
		return true
	}
	return false
}
