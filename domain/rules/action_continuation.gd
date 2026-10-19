extends RefCounted
const Core=preload("res://domain/rules/core_protection.gd")
static func request(engine,p: Dictionary,target: Dictionary,action: String,resume: Dictionary) -> bool:
	if target.is_empty() or not Core.enabled(engine,p):return false
	var info=Core.inspect(engine,p,target,action)
	if not info.protected:return false
	var ticket=action+":"+str(target.instance_id)
	var previous=engine.state.get("confirmation_tickets",{}).get(ticket,{})
	if previous.get("actual",[])==[info.actual.x,info.actual.y] and previous.get("reasons",[])==info.reasons:return false
	engine.state["confirmation"]={"id":engine.cause+":"+ticket,"root_action_id":engine.state.get("active_root",engine.cause),"target_instance":target.instance_id,"target_id":target.def_id,"action":action,"reasons":info.reasons,"resume":resume.duplicate(true),"owner":p.id}
	engine.emit("ConfirmationRequested",int(p.id),engine.state.confirmation)
	return true
static func effect_victim(engine,p: Dictionary,e: Dictionary,target: Dictionary) -> Dictionary:
	if e.get("op","")=="avalanche":return {"card":engine.effect_target,"action":"sell"}
	if e.get("op","")=="invoke":return {"card":target,"action":"sell"}
	if e.get("handler","") in ["destroy_copy","destroy_discover"]:return {"card":engine.effect_target,"action":"destroy"}
	if e.get("handler","") in ["slaughter","destroy_generate"]:return {"card":target,"action":"destroy"}
	return {}
static func before_effect(engine,p: Dictionary,e: Dictionary,target: Dictionary,source: Dictionary) -> bool:
	var chain=engine.state.get("auto_chain",{})
	if chain.get("allow_effect_once",false):chain.erase("allow_effect_once")
	elif chain.get("mode","")=="play_then_sell" and engine.Fast.exception(e)!="":
		engine.state["confirmation"]={"id":engine.cause+":manual_effect:"+str(engine.state.event_seq),"root_action_id":chain.root_action_id,"target_instance":target.get("instance_id",-1),"target_id":source.get("def_id",source.get("id","")),"action":"manual_effect","reasons":[engine.Fast.exception(e)],"owner":p.id,"resume":{"kind":"effect","spec":e.duplicate(true),"target":target.duplicate(true),"source":source.duplicate(true),"effect_target":engine.effect_target.duplicate(true),"spell":engine.current_spell.duplicate(true),"phase":engine.resolution_phase,"cast_destroy_succeeded":engine.cast_destroy_succeeded}}
		engine.emit("ManualEffectBoundary",int(p.id),engine.state.confirmation);return true
	var victim=effect_victim(engine,p,e,target)
	if victim.is_empty():return false
	return request(engine,p,victim.card,victim.action,{"kind":"effect","spec":e,"target":target,"source":source,"effect_target":engine.effect_target,"spell":engine.current_spell,"phase":engine.resolution_phase,"cast_destroy_succeeded":engine.cast_destroy_succeeded})
static func resolve(engine,p: Dictionary,args: Dictionary,cancel: bool) -> String:
	if not engine.state.has("confirmation"):return "NO_CONFIRMATION"
	var held=engine.state.confirmation
	if str(args.get("confirmation_id",""))!=str(held.id):return "STALE_CONFIRMATION"
	engine.state.erase("confirmation")
	if cancel:
		
		if engine.state.has("play_tail"):
			var tail=engine.state.play_tail;var played=engine.find_target(p,int(tail.instance_id))
			if played.is_empty():played=tail.get("card",{})
			if not played.is_empty():engine.grant_triple_reward(p,played)
		for choice in p.choices:
			if choice.get("root_action_id","")==held.root_action_id and choice.kind not in ["choose_one","choose_target","gold_route","quilboar_gold","r13_replace","round13_gold_target"]:
				for c in choice.options:engine.return_pool(c)
		p.choices=p.choices.filter(func(c):return c.get("root_action_id","")!=held.root_action_id)
		engine.state.effect_queue=engine.state.effect_queue.filter(func(job):return job.get("root_action_id","")!=held.root_action_id)
		engine.state.erase("play_tail");engine.state.erase("cast_tail");engine.state.erase("auto_chain");engine.state.erase("active_root");engine.state["confirmation_tickets"]={}
		engine.emit("ConfirmationCancelled",int(p.id),{"id":held.id,"preserved_committed_effects":true});return ""
	var target=engine.find_target(p,int(held.target_instance))
	if target.is_empty():
		
		var i=engine.find_index(p.hand,int(held.target_instance))
		if i>=0 and held.resume.kind in ["auto_start","legacy_play"]:target=p.hand[i]
	if target.is_empty() and held.action!="manual_effect":
		engine.state.erase("auto_chain");engine.state.erase("play_tail");engine.state.erase("cast_tail")
		engine.emit("ConfirmationStopped",int(p.id),{"id":held.id,"reason":"TARGET_MISSING"});return ""
	if not engine.state.has("confirmation_tickets"):engine.state["confirmation_tickets"]={}
	if held.action!="manual_effect":
		var inspected=Core.inspect(engine,p,target,held.action)
		engine.state.confirmation_tickets[held.action+":"+str(held.target_instance)]={"actual":[inspected.actual.x,inspected.actual.y],"reasons":inspected.reasons}
	elif engine.state.has("auto_chain"):engine.state.auto_chain["allow_effect_once"]=true
	var resume=held.resume
	match str(resume.kind):
		"legacy_play":
			var error=engine.apply_command(p,"play",resume.play_args)
			if not error.is_empty():return error
		"command":
			var error=engine.apply_command(p,resume.command,resume.payload)
			if not error.is_empty():return error
		"auto_start":engine.start_auto_chain(p,resume.instance_id,true)
		"recruit_destroy":engine.Undead.recruit_destroy(engine,p,target)
		"effect":
			var old_target=engine.effect_target;var old_spell=engine.current_spell;var old_phase=engine.resolution_phase
			engine.effect_target=engine.find_target(p,int(resume.effect_target.get("instance_id",-1)))
			engine.current_spell=resume.spell;engine.resolution_phase=resume.phase;engine.cast_destroy_succeeded=resume.cast_destroy_succeeded
			var actual=engine.find_target(p,int(resume.target.get("instance_id",-1)))
			var source=engine.find_target(p,int(resume.source.get("instance_id",-1)))
			if source.is_empty():source=resume.source
			engine.effect(p,resume.spec,resume.target if actual.is_empty() else actual,source)
			engine.effect_target=old_target;engine.current_spell=old_spell;engine.resolution_phase=old_phase
	engine.drain_effects()
	engine.resume_tails(p)
	engine.emit("ConfirmationResolved",int(p.id),{"id":held.id,"instance_id":held.target_instance})
	return ""
