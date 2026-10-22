package application

import "core:fmt"
import campaign "../campaign"
import world "../expedition"
import activities "../activities"
import game "../game"
import host "../engine/host"
import ui "../engine/ui"

@(private)
Hub_Secret :: struct {biome:campaign.Biome,site:int}

@(private)
hub_known_secrets :: proc(c:^campaign.Campaign)->(entries:[int(campaign.Biome.Count)*world.MAX_SITES]Hub_Secret,count:int) {
	for b in campaign.Biome.Cyber..<campaign.Biome.Count {
		for index in 0..<world.MAX_SITES {
			if campaign.secret_known(c,b,index) {entries[count]={b,index};count+=1}
		}
	}
	return
}

@(private)
hub_secret_name :: proc(index:int)->string {
	switch index {
	case 12:return "Cache nascosta"
	case 13:return "Archivio nascosto"
	case 14:return "Frammento di memoria"
	case 15:return "Tunnel"
	}
	return "Luogo ricordato"
}

@(private)
hub_biome_arcades :: proc(b:campaign.Biome)->(indices:[2]int,count:int) {
	index:=activities.minigame_index_by_id(world.metadata(b).arcade)
	if index>=0 {indices[count]=index;count+=1}
	if b==.City {indices[count]=activities.minigame_index_by_id("ring");count+=1}
	return
}

@(private)
hub_unlocked_arcades :: proc(c:^campaign.Campaign)->(indices:[activities.MINIGAME_COUNT]int,count:int) {
	seen:[activities.MINIGAME_COUNT]bool
	for b in campaign.Biome.Cyber..<campaign.Biome.Count {
		if !c.won[b] {continue}
		entries,n:=hub_biome_arcades(b)
		for index in entries[:n] {if !seen[index] {seen[index]=true;indices[count]=index;count+=1}}
	}
	return
}

@(private)
hub_record_line :: proc(c:^campaign.Campaign,index:int)->string {
	r:=c.records[index]
	return fmt.tprintf("%d / 3 stelle   |   record %d",r.best_stars,r.best_score) if r.plays>0 else "Nessun record"
}

@(private)
hub_galaxy_hover :: proc(h:^Campaign_Hub,frame:^host.Frame,b:campaign.Biome) {
	ctx:=frame.ui;p:=ctx.theme.palette
	indices,n:=hub_biome_arcades(b)
	height:=f32(91+n*38)
	box:=ui.panel(ctx,{clamp(frame.mouse.x+18,34,338),clamp(frame.mouse.y-height-14,140,432-height),320,height},alt=true)
	ui.label(ctx,ui.cut_top(&box,23),campaign.biome_name(b),.Body,p.text)
	ui.label(ctx,ui.cut_top(&box,25),world.metadata(b).boss,.Small,p.focus)
	for index in indices[:n] {
		info,_:=activities.minigame_info(index)
		ui.label(ctx,ui.cut_top(&box,19),info.title,.Small,p.text)
		ui.label(ctx,ui.cut_top(&box,19),hub_record_line(&h.progress,index),.Small,p.text_dim)
	}
}

@(private)
hub_page_controls :: proc(ctx:^ui.Context,bounds:ui.Rect,page:^int,count,per_page:int) {
	pages:=max(1,(count+per_page-1)/per_page);page^=clamp(page^,0,pages-1)
	row:=bounds;left:=ui.cut_left(&row,38);right:=ui.cut_right(&row,38)
	if ui.button(ctx,left,"<",page^>0,false,.Small) {page^-=1}
	ui.label(ctx,row,fmt.tprintf("%d / %d",page^+1,pages),.Small,ctx.theme.palette.text_dim,.Center)
	if ui.button(ctx,right,">",page^+1<pages,false,.Small) {page^+=1}
}

@(private)
hub_progress :: proc(h:^Campaign_Hub,frame:^host.Frame) {
	ctx:=frame.ui;p:=ctx.theme.palette;c:=&h.progress
	left:=ui.panel(ctx,{30,146,300,324})
	ui.label(ctx,ui.cut_top(&left,30),"LA TUA MEMORIA",.Large,p.text)
	ui.label(ctx,ui.cut_top(&left,26),fmt.tprintf("%d estrazioni / %d morti",c.total_wins,c.deaths),.Body,p.text_dim)
	count:=0;for found in c.discovered {if found {count+=1}}
	ui.label(ctx,ui.cut_top(&left,26),fmt.tprintf("%d / %d carte scoperte",count,int(game.Card_Id.Count)),.Body,p.focus)
	won:=0;for b in campaign.Biome.Cyber..<campaign.Biome.Secret {if c.won[b] {won+=1}}
	ui.label(ctx,ui.cut_top(&left,25),fmt.tprintf("%d / 11 biomi vinti",won),.Small,p.text_dim)
	minutes:=int(c.play_seconds)/60
	ui.label(ctx,ui.cut_top(&left,25),fmt.tprintf("Tempo: %dh %02dm",minutes/60,minutes%60),.Small,p.text_dim)
	if c.normal_ending {ui.paragraph(ctx,ui.cut_top(&left,44),fmt.tprintf("Serie %d / record %d\nUna vittoria in ogni ricordo.",c.streak,c.best_streak),.Small,p.warning)}
	lab:=ui.cut_bottom(&left,34);ui.cut_bottom(&left,10)
	if ui.button(ctx,ui.cut_bottom(&left,34),"ARCHIVIO / MOSTRA EFFETTO",true,false,.Small) {h.page=.Storage;h.inventory.panel=.Archive}
	if ui.button(ctx,lab,"PROVA MECCANICHE",true,false,.Small) {
		launcher:=launcher_create(h.options);launcher_start_run(launcher,frame,true);delete(launcher.status);free(launcher)
	}
	right:=ui.panel(ctx,{348,146,582,324});tabs:=ui.cut_top(&right,32)
	for title,i in ([2]string{"SEGRETI TROVATI","RECORD DEI CABINATI"}) {
		if ui.button(ctx,ui.column(tabs,2,i,8),title,true,h.progress_tab==i,.Small) {h.progress_tab=i;h.progress_page=0}
	}
	ui.cut_top(&right,12);footer:=ui.cut_bottom(&right,28);ui.cut_bottom(&right,8)
	if h.progress_tab==0 {
		entries,n:=hub_known_secrets(c);hub_page_controls(ctx,footer,&h.progress_page,n,6)
		if n==0 {ui.paragraph(ctx,right,"Esplora oltre i sentieri. I luoghi segreti trovati restano qui anche dopo una morte.",.Body,p.text_dim)}
		for i in h.progress_page*6..<min(n,(h.progress_page+1)*6) {
			entry:=entries[i];row:=ui.cut_top(&right,31)
			ui.label(ctx,ui.cut_left(&row,252),campaign.biome_name(entry.biome),.Small,p.focus)
			ui.label(ctx,row,hub_secret_name(entry.site),.Small,p.text_dim)
		}
	} else {
		indices,n:=hub_unlocked_arcades(c);hub_page_controls(ctx,footer,&h.progress_page,n,4)
		if n==0 {ui.paragraph(ctx,right,"Estrai da un bioma per conservare il suo cabinato. I record includono le partite nell'hub.",.Body,p.text_dim)}
		for i in h.progress_page*4..<min(n,(h.progress_page+1)*4) {
			index:=indices[i];info,_:=activities.minigame_info(index);r:=c.records[index]
			row:=ui.cut_top(&right,48)
			ui.label(ctx,ui.cut_top(&row,21),info.title,.Body,p.text)
			ui.label(ctx,row,fmt.tprintf("%s   |   %d partite / %d vittorie",hub_record_line(c,index),r.plays,r.wins),.Small,p.text_dim)
		}
	}
}

@(private)
hub_arcade :: proc(h:^Campaign_Hub,frame:^host.Frame) {
	ctx:=frame.ui;p:=ctx.theme.palette
	ui.label(ctx,{34,143,890,26},"CABINATI / Record personali, nessun premio e nessun oggetto a rischio",.Small,p.text_dim)
	indices,count:=hub_unlocked_arcades(&h.progress)
	hub_page_controls(ctx,{340,439,280,28},&h.arcade_page,count,8)
	if count==0 {ui.paragraph(ctx,{35,210,750,80},"Vinci una spedizione per conservare il suo cabinato nell'hub.",.Body,p.text_dim)}
	for i in h.arcade_page*8..<min(count,(h.arcade_page+1)*8) {
		index:=indices[i];info,_:=activities.minigame_info(index);local:=i%8
		box:=ui.panel(ctx,{34+f32(local%2)*450,177+f32(local/2)*64,430,58})
		button:=ui.cut_right(&box,78);ui.cut_right(&box,10)
		ui.label(ctx,ui.cut_top(&box,20),info.title,.Small,p.text)
		ui.label(ctx,box,hub_record_line(&h.progress,index),.Small,p.text_dim)
		if ui.button(ctx,button,"GIOCA",true,false,.Small) {host.push(frame,info.create({seed=h.options.seed~u64(h.clock*1000)}))}
	}
}
