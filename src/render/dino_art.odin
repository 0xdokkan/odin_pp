package render

import rl "vendor:raylib"

// Four dinosaurs in pixel art, one shared canvas so they swap freely: a side
// view facing RIGHT, the feet on row 38, two frames of a walk (the legs and the
// tail alternate; on the second frame the back also rises by DINO_ART_BOB rows).
// Plain pixels, alpha 0 = transparent: the game cuts them out of paper itself
// and adds the ink outline, so none is drawn here. Every dinosaur carries a
// small saddle on its back; DINO_ART_SEAT is the pixel of the first frame where
// a rider's feet sit (the saddle's middle row: it is opaque on both frames).
//
// Original cartoons, drawn by code (a throwaway rasteriser built the grids
// below out of ellipses, polygons and thick lines, then shaded each part with a
// flat colour, a darker one under it and a lighter one on its top edge); the
// letters are looked up in dino_art_color.
DINO_ART_W :: 56
DINO_ART_H :: 40
DINO_ART_FRAMES :: 2

Dino_Art :: enum {
	Raptor, // slim, long tail, green with orange stripes, a big hooked toe claw
	Stego,  // bulky and low, big orange-red plates, a tail of four spikes
	Dilo,   // blue-green, two crests, a spread red-orange frill, a spit of venom
	Giga,   // the biggest: a huge toothed head, tiny arms, scars
}

// The pixel (x, y) on the back where the rider's feet sit, on the first frame.
@(rodata)
DINO_ART_SEAT := [Dino_Art][2]int{
	.Raptor = {24, 15},
	.Stego = {26, 15},
	.Dilo = {24, 16},
	.Giga = {24, 10},
}

// Rows the back rises on each frame (the seat's y on that frame is y - bob).
@(rodata)
DINO_ART_BOB := [Dino_Art][DINO_ART_FRAMES]int{
	.Raptor = {0, 1},
	.Stego = {0, 0},
	.Dilo = {0, 1},
	.Giga = {0, 1},
}

// One dinosaur's pixels on the shared canvas (row-major, DINO_ART_W wide).
dino_art_pixels :: proc(kind: Dino_Art, frame: int) -> (pixels: [DINO_ART_W*DINO_ART_H]rl.Color) {
	index := (frame%DINO_ART_FRAMES + DINO_ART_FRAMES)%DINO_ART_FRAMES
	for row, y in DINO_ART_ROWS[kind][index] {
		for x in 0..<min(len(row), DINO_ART_W) { pixels[y*DINO_ART_W+x] = dino_art_color(row[x]) }
	}
	return
}

dino_art_color :: proc(letter: u8) -> rl.Color {
	switch letter {
	case '0': return {232, 220, 192, 255}
	case '1': return {184, 168, 136, 255}
	case 'A': return {200, 192, 122, 255}
	case 'B': return {160, 154, 86, 255}
	case 'C': return {255, 154, 88, 255}
	case 'D': return {255, 194, 58, 255}
	case 'E': return {255, 160, 80, 255}
	case 'F': return {232, 80, 46, 255}
	case 'G': return {242, 106, 42, 255}
	case 'H': return {176, 58, 26, 255}
	case 'I': return {106, 216, 208, 255}
	case 'J': return {42, 160, 168, 255}
	case 'K': return {26, 108, 134, 255}
	case 'L': return {200, 232, 58, 255}
	case 'M': return {168, 42, 34, 255}
	case 'N': return {184, 232, 216, 255}
	case 'O': return {240, 255, 154, 255}
	case 'P': return {140, 176, 28, 255}
	case 'Q': return {136, 192, 184, 255}
	case 'R': return {138, 124, 112, 255}
	case 'S': return {90, 80, 72, 255}
	case 'T': return {192, 122, 106, 255}
	case 'U': return {58, 50, 46, 255}
	case 'V': return {216, 208, 192, 255}
	case 'W': return {74, 12, 20, 255}
	case 'X': return {144, 80, 70, 255}
	case 'Y': return {124, 112, 96, 255}
	case 'Z': return {168, 154, 132, 255}
	case 'a': return {143, 212, 90, 255}
	case 'b': return {79, 168, 58, 255}
	case 'c': return {255, 246, 192, 255}
	case 'd': return {24, 16, 24, 255}
	case 'e': return {47, 122, 44, 255}
	case 'f': return {122, 28, 36, 255}
	case 'g': return {138, 74, 42, 255}
	case 'h': return {192, 122, 72, 255}
	case 'i': return {200, 220, 120, 255}
	case 'j': return {255, 250, 240, 255}
	case 'k': return {240, 138, 36, 255}
	case 'l': return {142, 30, 30, 255}
	case 'm': return {210, 58, 42, 255}
	case 'n': return {90, 44, 24, 255}
	case 'o': return {154, 180, 90, 255}
	case 'p': return {244, 234, 208, 255}
	case 'q': return {196, 180, 140, 255}
	case 'r': return {255, 255, 255, 255}
	case 's': return {255, 154, 90, 255}
	case 't': return {164, 44, 24, 255}
	case 'u': return {226, 80, 42, 255}
	case 'v': return {242, 224, 168, 255}
	case 'w': return {192, 168, 104, 255}
	case 'x': return {164, 180, 92, 255}
	case 'y': return {85, 100, 42, 255}
	case 'z': return {122, 138, 60, 255}
	}
	return {}
}

@(rodata)
DINO_ART_ROWS := [Dino_Art][DINO_ART_FRAMES][DINO_ART_H]string{
	.Raptor = {
		{
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................aaaaaa..........",
			"......................................aabbbbbaaa........",
			".....................................abbbbbbbcdb........",
			"...................................aaebbbbbbbbbbaaae....",
			"..................................abbbeebbbbbbbbbbbe....",
			".................................abbbbeeeeeeeeeeeeee....",
			"e...............................abbbbbbeeeeeeefffff.....",
			".eea.................ghhhhhhg...bbbbbbee.....iiijij.....",
			"..eekaa..............lmmhhmml..abbbbbee.................",
			"...ekbbaka..........annnnnnnnaabbbbbbe..................",
			"....ekebbkaaaaa...aabbkkbbkkbbkkbbbbb...................",
			".....keeekbbkbbakabkkbbkkbbkkbbkkbbbb...................",
			".......eeebbkbbbkbbkkbbkkbbkkbbkkbbbb...................",
			".........eeekbbbkbbkkbbkkbbkkbbkkbbbe...................",
			"..........eeekeebkbbkkbbkkaakkbbkkbbe...................",
			"............ekeeekbbkkaakkbbkkbbkkbbb...................",
			"...............eeebbbbbbbbbbbabbbbebbb..................",
			".................oiibabbbaabbbabiio.bbb.................",
			"..................ooiabbebbabbbioo...bbp................",
			"....................oabbeebbabbo.......q................",
			".....................ebbbeebbae.........................",
			".....................ebbbbeebba.........................",
			"......................eebbbebbba........................",
			"......................eeeeeeabbbe.......................",
			"......................eeeeeebbbee.......................",
			".....................eeeee.abbee........................",
			"....................eeeee.abbee.........................",
			"...................eeeee.eaaeeppr.......................",
			"...................eeee..eeba....p......................",
			"....................eeeee.eabaaq.q......................",
			".....................eeeeeeebbbaqappq...................",
			"......................eeeeeeeeeeee...q..................",
			"........................................................",
		},
		{
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................aaaaaa..........",
			"......................................aabbbbbaaa........",
			".....................................abbbbbbbcdb........",
			"...................................aaebbbbbbbbbbaaae....",
			"..................................abbbeebbbbbbbbbbbe....",
			".................................abbbbeeeeeeeeeeeeee....",
			"................................abbbbbbeeeeeeefffff.....",
			".....................ghhhhhhg...bbbbbbee.....iiijij.....",
			".....................lmmhhmml..abbbbbee.................",
			"e...................annnnnnnnaabbbbbbe..................",
			".eea.....aaaaaa...aabbkkbbkkbbkkbbbbb...................",
			"..eekaaakbbbbbbaaabkkbbkkbbkkbbkkbbbb...................",
			"...ekbbbbkbbbbbbkbbkkbbkkbbkkbbkkbbbb...................",
			"....ekeeekbbkbbbkbbkkbbkkbbkkbbkkbbbe...................",
			".....keeeeeekeeekbbbkkaakkbbkkbbkkbbe...................",
			".........eeekeeeekbbkkbbkkaakkbbkkbbb...................",
			"...............eekbbabbbbbbbbbbbbbebbb..................",
			".................oiabbbaabbbabbbiio.bbb.................",
			"..................oabbbbbabbbiiioo...bbp................",
			"...................abbebbbbbbooo.......q................",
			"...................ebbbabbbbe...........................",
			"...................eebbabbbbee..........................",
			"....................eebabbeeeee.........................",
			".....................eeabbeeeeee........................",
			"......................ebbbe.eeeee.......................",
			"......................abbee.eeeee.......................",
			".....................abbee.eeeee........................",
			"....................abbee.eeeee.........................",
			"...................eaaeeppreee..........................",
			"...................eeba..eepe...........................",
			"....................eabaaqeqeee.........................",
			".....................ebbbaqappqeee......................",
			"......................eeeeeeeeeqee......................",
			"........................................................",
		},
	},
	.Stego = {
		{
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"...................sst..................................",
			"...................sut...........st.....................",
			"..................susut.........suut....................",
			"..............st..susut.........sust....................",
			".r...........suut.susut.........sust....................",
			".r...........sust.susut........suusut.sst...............",
			".r..r........sust.susut........suusut.sut...............",
			".v..r.......suusutsuuut........suusutsusut..............",
			"rvv.r..r....suusutsuuutghhhhhhgsuuuutsusut..............",
			"www.v..r..r.suuuutsuuuxlmmhhmmlsuuuutsusut..............",
			"y..rvv.vssr.suuuuxxxxxznnnnnnnnxxxxutsuuut..............",
			".yywwwrvvuv.suuxxzzzzzzzzzzzzzzzzzzxxsuuut..............",
			"..yyyxwwwrvvtxxzzzzzzzzzzzzzzzzzzzzzzxxuut..............",
			"...yyyyxxwwwxzzzzzzzzzzzzzzzzzzzzzzzzzzxtt..............",
			".....yyyyyxxzzzzzzzzzzzzzzzzzzzzzzzzzzzzxx..............",
			".......yyyzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz.ssst.........",
			".......ttxzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzxsuut.........",
			".......ttxzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzuuuut........",
			".........xzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzxuuut........",
			".........xzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzxuut........",
			".........yzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzxxxxxx.....",
			".........yzzxxxxxxzzzzzzzzzzzzzzzzxxxxxxzzzxxzzzzzzxx...",
			"..........yyzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzcdz...",
			"..........yxzzzzzzxzzzzzzzzzzzzzzxzzzzzzxzyzzzzzzzzzzy..",
			"...........xzzzzzzzzzzzzzzzzzzzzzxzzzzzzzzyzzzzzzzzzzy..",
			"...........yzzzzzzyAAAAAAAAAAAAAAyzzzzzzyyyyyzzzzzzyy...",
			"...........yzzzzzzyBBBAAAAAAAABBByzzzzzzyy.yyyyyyffff...",
			"............xzzzzzBBBBBBBBBBBBBBBBxzzzzz.....yyyyyy.....",
			"............xzzzzz...yBBBBBBBByyyyxzzzzz................",
			"............xzzzzz...yyyyyy...yyyyyyyyyy................",
			"............xzzzzz...qyqyqy...yyyypypypy................",
			"............yyyyyy............yyyyyy....................",
			"............pypypy............qyqyqy....................",
			"........................................................",
		},
		{
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"...................sst..................................",
			"...................sut...........st.....................",
			".r................susut.........suut....................",
			".r............st..susut.........sust....................",
			".r..r........suut.susut.........sust....................",
			".v..r........sust.susut........suusut.sst...............",
			"rvv.r..r.....sust.susut........suusut.sut...............",
			"www.v..r..r.suusutsuuut........suusutsusut..............",
			"y..rvv.v..r.suusutsuuutghhhhhhgsuuuutsusut..............",
			".yywwwrvv.v.suuuutsuuuxlmmhhmmlsuuuutsusut..............",
			"..yyyxwwwrvvsuuuuxxxxxznnnnnnnnxxxxutsuuut..............",
			"...yyyyxxwwwsuuxxzzzzzzzzzzzzzzzzzzxxsuuut..............",
			".....yyyyxuttxxzzzzzzzzzzzzzzzzzzzzzzxxuut..............",
			".......yyyutxzzzzzzzzzzzzzzzzzzzzzzzzzzxtt..............",
			".......suyxxzzzzzzzzzzzzzzzzzzzzzzzzzzzzxx..............",
			".......suuzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz.ssst.........",
			".......ttxzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzxsuut.........",
			".......ttxzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzuuuut........",
			".........xzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzxuuut........",
			".........xzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzxuut........",
			".........yzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzxxxxxx.....",
			".........yzzxxxxxxzzzzzzzzzzzzzzzzxxxxxxzzzxxzzzzzzxx...",
			"..........yyzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzcdz...",
			"..........yxzzzzzzxzzzzzzzzzzzzzzxzzzzzzxzyzzzzzzzzzzy..",
			"...........xzzzzzzzzzzzzzzzzzzzzzxzzzzzzzzyzzzzzzzzzzy..",
			"...........yzzzzzzyAAAAAAAAAAAAAAyzzzzzzyyyyyzzzzzzyy...",
			"...........yzzzzzzyBBBAAAAAAAABBByzzzzzzyy.yyyyyyffff...",
			"............xzzzzzBBBBBBBBBBBBBBBBxzzzzz.....yyyyyy.....",
			"............xzzzzz...yBBBBBBBByyyyxzzzzz................",
			"............yyyyyy...yyyyyy...yyyyxzzzzz................",
			"............pypypy...yyyyyy...qyqyxzzzzz................",
			".....................yyyyyy.......yyyyyy................",
			".....................qyqyqy.......pypypy................",
			"........................................................",
		},
	},
	.Dilo = {
		{
			"........................................................",
			"........................................................",
			"........................................................",
			"........................................................",
			"..................................CCD....EE.............",
			"................................DDFFDD...EGEEEE.........",
			"...............................CFDDFDDC..EDGGEGEE.......",
			"..............................DFFFDDFDFC.EGGGEDGG.......",
			"..............................DDDFFDFDDFCHHHHHHHH.......",
			".............................CFFDDFFDFDFFHHHHHHHH.......",
			".............................DFFFDDDDDDIIJJJJII.........",
			".............................DDDDDFDDDIJJJJJJJIII.......",
			".............................CFFDDDDIIKJJJJJJJcdJII.....",
			".............................CFFFFFIJJJKKJJJJJKKKKK.....",
			".............................DDDDDIJJJJKKKKKKffffff.L...",
			"K....................ghhhhhhgMFFFIJJJJJJKKKKKKNjNj..OL..",
			".K...................lmmhhmmlMFIIJJJJJJKM...NNNNN.....L.",
			".KKII.............IIInnnnnnnnIIJJJJJJJKK............O.P.",
			"..KKJIII.........IJJJJKKJJKKJJJJJJJJJKKM................",
			"...KKKKJIIIIIIIIIJKKJJJJJJJJJJKKJJJJJKM..............O..",
			"....KKKJJKKJJJJJJJJJJJJJJJJJJJJJJJJJJM..................",
			"......KKKJJJJJKKJJJJJJJJKKJJJJJJJJJJKM..................",
			".......KKKKKJJKJJJJJKKIIIIIIJJJJJJJJK...................",
			".........KKKKKKJJJJJJIJJJJJJIJJJJJJJ....................",
			"............KKKKKJJJIJJJJJJJJJJJJKJJJ...................",
			"...............QQQNNIJJJIIJJJINNQQQJJJ..................",
			".................QQQIJJKJJIJJJQQQ...JJp.................",
			"..................QQIJJKKJJIJKQQ........................",
			"..................KKKJJJKKKJII..........................",
			"...................KKKJJJKKJJJI.........................",
			"...................KKKKKKKKIJJJK........................",
			"....................KKKKKKKIJJKK........................",
			".....................KKKK..JJJK.........................",
			"....................KKKK..IJJK..........................",
			"...................KKKKK.KIIKK..........................",
			"...................KKKK..KIJI...........................",
			"....................KKKKKKKJJIII........................",
			".....................KKKKKKKJJJJIIppp...................",
			"......................KKKKKKKKKKKK......................",
			"........................................................",
		},
		{
			"........................................................",
			"........................................................",
			"........................................................",
			"..................................CCD....EE.............",
			"................................DDFFDD...EGEEEE.........",
			"...............................CFDDFDDC..EDGGEGEE.......",
			"..............................DFFFDDFDFC.EGGGEDGG.......",
			"..............................DDDFFDFDDFCHHHHHHHH.......",
			".............................CFFDDFFDFDFFHHHHHHHH.......",
			".............................DFFFDDDDDDIIJJJJII.........",
			".............................DDDDDFDDDIJJJJJJJIII.......",
			".............................CFFDDDDIIKJJJJJJJcdJII.....",
			".............................CFFFFFIJJJKKJJJJJKKKKK.....",
			".............................DDDDDIJJJJKKKKKKffffff.L...",
			".....................ghhhhhhgMFFFIJJJJJJKKKKKKNjNj..OL..",
			".....................lmmhhmmlMFIIJJJJJJKM...NNNNN.....L.",
			"..................IIInnnnnnnnIIJJJJJJJKK............O.P.",
			"K................IJJJJKKJJKKJJJJJJJJJKKM................",
			".K.....IIIIIIIIIIJKKJJJJJJJJJJKKJJJJJKM..............O..",
			".KKIIIIJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJM..................",
			"..KKKKKJJJJJJJKKJJJJJJJJKKJJJJJJJJJJKM..................",
			"...KKKKJJKKJJJKJJJJJKKIIIIJJJJJJJJJJK...................",
			".....KKKKKKKJJKJJJJIJJJJJJIJJJJJJJJJ....................",
			".......KKKKKKKKKKJJJJJJJJJJIJJJJJKJJJ...................",
			"............KKKQQQIJJJIIJJJJNNNNQQQJJJ..................",
			".................QIJJKJJIJJJQQQQQ...JJp.................",
			"..................KJJKJJJJJJQQQQ........................",
			"..................KJJJIJJJJKKK..........................",
			"...................KJJIJJJKKKK..........................",
			"...................KKKIJJIKKKKK.........................",
			"....................KKJJJKKKKKKK........................",
			".....................IJJKK.KKKKK........................",
			".....................JJJK..KKKK.........................",
			"....................IJJK..KKKK..........................",
			"...................KIIKK.KKKKK..........................",
			"...................KIJI..KKKK...........................",
			"....................KJJIIIKKKKKK........................",
			".....................KJJJJIIpppKKK......................",
			"......................KKKKKKKKKKKK......................",
			"........................................................",
		},
	},
	.Giga = {
		{
			"........................................................",
			"........................................................",
			".............................................RRRR.......",
			".........................................RRRRSSSSRTR....",
			"........................................RSSSSSSSSSTTR...",
			"........................................SSSSSSSSSSSTSR..",
			".......................................RSSSSSSUUUSSTTU..",
			"......................................RSSSSSSSSccSSSTSR.",
			"......................................USSSSSSSSddSSSSSS.",
			".....................ghhhhhhg.....RRRRUSSSSSSSSSSSSSSSS.",
			"................RRRR.lmmhhmmlRRRRRUUSSSRSSSSSSSSSSSUUUU.",
			"..........RRRRRRSSSRRnnnnnnnnUSUUSUSSSSUSSSSUUUUUUUUUUU.",
			".......RRRSSSSSSSRRTTSUSSUSSUSSUSSSSSSSUUUUUUUUUUUU.....",
			"...RRRRSSSSSSSSRRSSUTTSSSSSSSSSSSSSSSSSSUUUUjfjfjfjfjfj.",
			"RRRSSSSSSSSSSSRSUUSSSTTSSSSSSSSSSSSSSSSSSSSSVWVWVWVWVWV.",
			"RSSSSSSSSSSSSRSSUSSSSSTTSSSXXSSSSSSSSSSSSRRRSjSjSjSjSjU.",
			"USSSSSSSSSSSRUUSSSSSSSSTTSSSXXSSSSSSSSSSUUUSSSSSSSSSUU..",
			"UUSSSSSSSSSSRUSSSSSSSSSSSSSSSXXSSSSSSSSSSUUUUUUUUUUUU...",
			"UUUSSSSSSSSSRSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSUUUUUUUUU....",
			".UUUSSSSSSSSRSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSY............",
			"..UUUSSSSSSSRSSSSSSSSSRRRRRSSSSSSSSSSSSSSSZY............",
			"...UUUUSSSSSUSZSSSSSSRSSSSSRRSSSSSSSSSSSSSYY............",
			"....UUUUUSSSUUYZZSSSRSSSSSSSSRSSSSSSSSSSSSS.............",
			".....UUUUUUSUUYYYZZRSSSSSSSSSSRSSSSSSSZZYSSS............",
			".......UUUUUUUYYYYRSSSSSSSSSSSSSZZZZZZYYYYSS0...........",
			".........UUUUUYYYYRSSSSSSSSSSSSRYYYYYYYYYY.11...........",
			"...........UUUUYYYRSSSSSSSSSSSSSYYYYYYYYY...............",
			".............UUUUYRSSSSSSSSSSSSSYYYYYYYY................",
			"...............UUURSSSSSSSRRSSSUYYYYYY..................",
			"................UUUSSSSSSRSSRRRRR.......................",
			"................UUUUSSSSUSSSSSSSSR......................",
			".................UUUUSSSUUSSSSSSSSU.....................",
			".................UUUUUSSSRSSSSSSSUU.....................",
			"..................UUUUUUUUSSSSSSUU......................",
			"...................UUUUUURRRSSSUU.......................",
			"....................UUUUURSSRRUU........................",
			"....................UUUUUUSSSSRRRRRRR...................",
			".....................UUUUUUUSSSSSSSSS000................",
			"......................UUUUUUUUSSSSSSS111................",
			"..........................UUUUUUUUUUU...................",
		},
		{
			"........................................................",
			".............................................RRRR.......",
			".........................................RRRRSSSSRTR....",
			"........................................RSSSSSSSSSTTR...",
			"........................................SSSSSSSSSSSTSR..",
			".......................................RSSSSSSUUUSSTTU..",
			"......................................RSSSSSSSSccSSSTSR.",
			"......................................USSSSSSSSddSSSSSS.",
			".....................ghhhhhhg.....RRRRUSSSSSSSSSSSSSSSS.",
			"................RRRR.lmmhhmmlRRRRRUUSSSRSSSSSSSSSSSUUUU.",
			"...........RRRRRSSSRRnnnnnnnnUSUUSUSSSSUSSSSUUUUUUUUUUU.",
			"..........RSSSSSSRRTTSUSSUSSUSSUSSSSSSSUUUUUUUUUUUU.....",
			".........RSSSSSRRSSUTTSSSSSSSSSSSSSSSSSSUUUUjfjfjfjfjfj.",
			".......RRSSSSSRSUUSSSTTSSSSSSSSSSSSSSSSSSSSSVWVWVWVWVWV.",
			"......RSSSSSSRSSUSSSSSTTSSSXXSSSSSSSSSSSSRRRSjSjSjSjSjU.",
			"...RRRSSSSSSRUUSSSSSSSSTTSSSXXSSSSSSSSSSUUUSSSSSSSSSUU..",
			"RRRSSSSSSSSSRUSSSSSSSSSSSSSSSXXSSSSSSSSSSUUUUUUUUUUUU...",
			"RSSSSSSSSSSSRSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSUUUUUUUUU....",
			"USSSSSSSSSSSRSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSY............",
			"UUSSSSSSSSSSRSSSSSSSSRRRRRSSSSSSSSSSSSSSSSZY............",
			"UUUSSSSSSSSSUSZSSSSRRSSSSSRSSSSSSSSSSSSSSSYY............",
			".UUUSSSSSSSSUUYZZSRSSSSSSSSRSSSSSSSSSSSSSSS.............",
			"..UUUSSSSSSSUUYYYRSSSSSSSSSSRSSSSSSSSSZZYSSS............",
			"...UUUUUUUSSSUYYYSSSSSSSSSSSSRSSZZZZZZYYYYSS0...........",
			"....UUUUUUUUUUYYRSSSSSSSSSSSSSZZYYYYYYYYYY.11...........",
			".....UUUUUUUUUUYRSSSSSSSSSSSSSYYYYYYYYYYY...............",
			"..........UUUUUURSSSSSSSSSSSSSYYYYYYYYYY................",
			"...............UUSSSSSSSRRSSSSYYYYYYYY..................",
			"................USSSSSSRSSRSSUYY........................",
			"................UUSSSSUSSSSRRUUUU.......................",
			".................UUSSSUSSSSSSRUUUU......................",
			".................UUUUSSRSSSSSSUUUUU.....................",
			"..................UUUUUSSSSSSUUUUUU.....................",
			"...................UUURSSSSSUUUUUU......................",
			".....................RRRSSSUUUUUU.......................",
			"....................URSSRRUUUUUU........................",
			"....................UUSSSSRRRRRRRUUUU...................",
			".....................UUUSSSSSSSSS000UU..................",
			"......................UUUUSSSSSSS111U111................",
			"..........................UUUUUUUUUUU...................",
		},
	},
}
