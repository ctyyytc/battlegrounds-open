extends RefCounted


const POWER="TB_BaconShop_HP_039t"
const EXCLUDED=["EBG_Spell_032","BG33_899","BG28_604","EBG_Spell_037","BG36_880","BG28_607","BG30_804"]
static func destructive(d: Dictionary,definitions: Dictionary={},seen: Array=[]) -> bool:
	if d.id in seen:return false
	seen=seen.duplicate();seen.append(d.id)
	if d.id in EXCLUDED:return true
	for e in d.get("effects",[]):
		if e.get("handler","") in ["slaughter","destroy_generate","destroy_copy","destroy_discover","activate_destroy"] or e.get("op","") in ["avalanche","invoke"]:return true
		if e.get("op","")=="choice":
			for id in e.get("ids",[]):
				if definitions.has(id) and destructive(definitions[id],definitions,seen):return true
	return false
static func targets(engine,p: Dictionary,d: Dictionary) -> Array:
	if engine.Quilboar.choice(d):
		var automatic=d.duplicate(true);automatic["automatic"]=true
		if engine.Quilboar.double_source(engine,p,automatic).double:
			var candidates=engine.Undead.board(engine,p).duplicate()
			if not engine.Undead.is_combat(engine):candidates.append_array(p.shop)
			candidates.append({})
			return candidates.filter(func(c):return d.effects[0].ids.all(func(id):return engine.Naga.valid_target(engine,p,engine.content.get_def(id),c)))
		var options=[]
		for id in d.effects[0].ids:
			for c in targets(engine,p,engine.content.get_def(id)):
				if not options.any(func(v):return int(v.get("instance_id",-1))==int(c.get("instance_id",-1))):options.append(c)
		return options
	var required=str(d.effects[0].get("target","none"))
	if required=="none":return [{}] if engine.Naga.valid_target(engine,p,d,{}) else []
	var candidates=engine.Undead.board(engine,p).duplicate()
	if required=="minion" and not engine.Undead.is_combat(engine):candidates.append_array(p.shop)
	return candidates.filter(func(c):return engine.Naga.valid_target(engine,p,d,c))
static func pool(engine,p: Dictionary) -> Array:
	return engine.Naga.spell_pool(engine,p).filter(func(id):
		var d=engine.content.get_def(id)
		return d.get("is_tavern_spell",false) and not destructive(d,engine.content.definitions) and not targets(engine,p,d).is_empty())
static func trigger(engine,p: Dictionary,source_id: String=POWER,token_prefix: String="yogg") -> bool:
	var ids=pool(engine,p)
	if ids.is_empty():
		engine.emit("AutomaticSpellUnavailable",int(p.id),{"source_power_id":source_id,"reason":"NO_LEGAL_YOGG_SPELL"});return false
	var before=engine.snapshot()
	var live_state=engine.state;var players=engine.state.players
	var id=ids[engine.RNG.next(engine.state.streams,"effects",ids.size())]
	if cast_spell(engine,p,id,source_id,token_prefix):return true
	restore_snapshot(engine,before,live_state,players)
	engine.emit("AutomaticSpellUnavailable",int(p.id),{"id":id,"source_power_id":source_id,"reason":"AUTOMATIC_RESOLUTION_BLOCKED"});return false
static func cast_spell(engine,p: Dictionary,id: String,source_id: String=POWER,token_prefix: String="yogg") -> bool:
	if id not in pool(engine,p):return false
	var d=engine.content.get_def(id).duplicate(true)
	var before=engine.snapshot()
	var live_state=engine.state;var players=engine.state.players
	var legal=targets(engine,p,d)
	var target=legal[engine.RNG.next(engine.state.streams,"effects",legal.size())]
	var previous_context=engine.state.get("automatic_spell_source",{}).duplicate(true)
	var previous_source=engine.effect_source
	engine.state["automatic_source_seq"]=int(engine.state.get("automatic_source_seq",0))+1
	var context={"power_id":source_id,"player_id":int(p.id),"token":"%s:%d:%d" % [token_prefix,int(p.id),int(engine.state.automatic_source_seq)]}
	engine.state["automatic_spell_source"]=context
	engine.effect_source={"def_id":source_id,"owner":int(p.id)}
	d["automatic"]=true;d["automatic_source"]="yogg" if source_id==POWER else "wheel"
	engine.cast(p,d,target)
	engine.drain_rewards(p)
	var error=finish_choices(engine,p,context)
	if error!="" or engine.state.has("confirmation") or engine.state.phase=="diagnostic":
		restore_snapshot(engine,before,live_state,players)
		engine.effect_source=previous_source
		engine.emit("AutomaticSpellUnavailable",int(p.id),{"id":id,"source_power_id":source_id,"reason":error if error!="" else "AUTOMATIC_RESOLUTION_BLOCKED"});return false
	if previous_context.is_empty():engine.state.erase("automatic_spell_source")
	else:engine.state["automatic_spell_source"]=previous_context
	engine.effect_source=previous_source
	return true
static func restore_snapshot(engine,before: Dictionary,live_state: Dictionary,players: Array) -> void:
	
	for i in players.size():players[i].clear();players[i].merge(before.state.players[i].duplicate(true))
	live_state.clear();live_state.merge(before.state.duplicate(true));live_state.players=players;engine.state=live_state
	engine.events=before.events;engine.spell_history=before.spell_history;engine.receipts=before.receipts;engine.command_log=before.command_log
static func finish_choices(engine,p: Dictionary,context: Dictionary) -> String:
	var source_id=str(context.get("power_id",POWER))
	for unused in 128:
		var at=-1
		for i in p.choices.size():
			if p.choices[i].get("automatic_source",{}).get("token","")==context.token:at=i;break
		if at<0:return ""
		var choice=p.choices[at];p.choices.remove_at(at);p.choices.push_front(choice)
		var legal=engine.Choices.eligible(engine,p,choice)
		if legal.is_empty():return "NO_LEGAL_AUTOMATIC_OPTION"
		var before=engine.snapshot()
		var selected=legal[engine.RNG.next(engine.state.streams,"effects",legal.size())]
		var error=engine.Choices.step(engine,"choose_target" if choice.kind=="choose_target" and choice.get("round8",false) else "choose",{"index":selected,"session_id":choice.session_id},int(p.id))
		if error!="":
			engine.state=before.state;engine.events=before.events;engine.spell_history=before.spell_history;engine.receipts=before.receipts;engine.command_log=before.command_log
			return error
		engine.emit("AutomaticSourceChoiceResolved",int(p.id),{"source_power_id":source_id,"kind":choice.kind,"session_id":choice.session_id,"index":selected})
		p=engine.state.players[int(p.id)]
		engine.drain_rewards(p)
	return "AUTOMATIC_CHOICE_BUDGET"
