extends RefCounted
const EFFECT_KINDS=["triple","undead","tavern_spell","fish","demon_damage","tagged_minion","seedling","medivh","round8_discovery","pirate_spell","telescope","hooktusk","sylvanas","choose_one","gold_route","quilboar_gold","r13_seven","r13_gift","r13_globe","r13_factory","r13_hearth","r13_transform","r13_replace","r132_power","r132_element","r132_conviction","r132_start","r132_copy","r132_cookie","r132_naga","r132_elise"]
static func enqueue(engine,p: Dictionary,choice: Dictionary) -> void:
	engine.state["selection_seq"]=int(engine.state.get("selection_seq",0))+1
	choice["root_action_id"]=engine.state.get("active_root",engine.cause)
	choice["session_id"]="selection:%d:%d" % [int(p.id),int(engine.state.selection_seq)]
	choice["revision"]=0
	refresh(choice)
	var chain=engine.state.get("auto_chain",{})
	var owned=int(p.id)==0 and chain.get("input_origin","")=="right_click" and chain.get("root_action_id","")==choice.root_action_id
	choice["input_origin"]="right_click" if owned else "manual"
	choice["auto_policy"]="random_legal_effect_option" if owned else "manual"
	var automatic=engine.state.get("automatic_spell_source",{})
	if int(automatic.get("player_id",-1))==int(p.id):
		choice["automatic_source"]=automatic.duplicate(true)
		choice["input_origin"]="yogg_automatic";choice["auto_policy"]="random_legal_effect_option"
	p.choices.append(choice)
	engine.emit("SelectionEnqueued",int(p.id),{"kind":choice.kind,"session_id":choice.session_id,"root_action_id":choice.root_action_id,"semantics":choice.selection_semantics})
static func refresh(choice: Dictionary) -> void:
	choice["selection_semantics"]="entity_target" if choice.kind in ["choose_target","round13_gold_target","r132_target"] else "effect_option" if choice.kind in EFFECT_KINDS else "unknown"
	if choice.kind=="quest_offer":choice.selection_semantics="quest_offer";choice.auto_policy="manual"
	if choice.kind in ["r136_teach","r136_locket"]:choice.selection_semantics="effect_option"
	if choice.kind.begins_with("r134_"):choice.selection_semantics="effect_option"
	if choice.kind in ["r133_route","r133_secret","r133_ticket_discovery","r133_flight_discovery"]:choice.selection_semantics="effect_option"
static func paid_identity(engine,p: Dictionary,session: Dictionary) -> void:
	engine.state["selection_seq"]=int(engine.state.get("selection_seq",0))+1
	session["session_id"]="paid:%d:%d" % [int(p.id),int(engine.state.selection_seq)]
	session["root_action_id"]=engine.state.get("active_root",engine.cause)
	session["selection_semantics"]="paid_offer";session["auto_policy"]="manual"
static func eligible(engine,p: Dictionary,choice: Dictionary) -> Array:
	var result=[]
	for i in choice.options.size():
		if choice.kind in ["r133_route","r133_secret"] and engine.R133.option_error(engine,p,choice,i)!="":continue
		if choice.kind=="r132_power":
			if choice.options[i].def_id not in engine.R132.source_pool(engine,p,str(choice.source)):continue
		elif choice.kind=="r132_target":
			if engine.R132.target_error(engine,p,choice,int(choice.options[i].instance_id))!="":continue
		elif choice.get("round8",false) and choice.kind=="choose_one":
			var selected=choice.duplicate(true);selected["selected_indices"]=range(choice.options.size()) if choice.get("double",false) else [i]
			if engine.Quilboar.need_target(engine,p,selected,engine.find_target(p,int(choice.get("target_instance",-1)))) and (p.board+p.shop).all(func(c):return engine.Quilboar.need_target(engine,p,selected,c)):continue
		elif choice.kind=="choose_one":
			var branch=engine.content.get_def(choice.options[i].def_id)
			if engine.Quilboar.requires_target(branch) and not engine.Naga.valid_target(engine,p,branch,engine.find_target(p,int(choice.get("target_instance",-1)))):continue
		elif choice.kind in ["gold_route","quilboar_gold"]:
			if engine.find_target(p,int(choice.source_instance)).is_empty():continue
		elif choice.kind=="r13_replace":
			if engine.R13Items.item(engine,p,int(choice.source_instance)).is_empty():continue
		elif choice.kind=="r13_transform":
			if engine.find_target(p,int(choice.target_instance)).is_empty():continue
		elif choice.kind=="round13_gold_target":
			var c=engine.find_target(p,int(choice.options[i].instance_id))
			if c.is_empty() or not engine.R13.gold_target(engine,p,c):continue
		result.append(i)
	return result
static func step(engine,kind: String,args: Dictionary,pid: int=0) -> String:
	
	# apply_command appends immutable log entries. A rollback needs their cursors,
	# not deep copies of the entire match history for each choice and auto-sale.
	var before=engine.action_state();var event_count=engine.events.size();var command_count=engine.command_log.size()
	var history=engine.spell_history.duplicate();var receipts=engine.receipts.duplicate()
	var context=[engine.effect_target,engine.effect_source,engine.current_spell,engine.committing_choice,engine.resolution_phase,engine.cast_destroy_succeeded]
	var error=engine.apply_command(engine.state.players[pid],kind,args)
	if error!="":
		engine.state=before;engine.events.resize(event_count);engine.spell_history=history;engine.receipts=receipts;engine.command_log.resize(command_count)
		engine.effect_target=context[0];engine.effect_source=context[1];engine.current_spell=context[2];engine.committing_choice=context[3];engine.resolution_phase=context[4];engine.cast_destroy_succeeded=context[5]
	return error
