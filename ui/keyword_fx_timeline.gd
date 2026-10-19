extends RefCounted
# View lifetime only. Nothing in this object is serialized into the match.
const Art=preload("res://ui/keyword_fx.gd")
const State=preload("res://ui/keyword_fx_state.gd")
var clock=0.0
var allow_paused_motion=false
var engine_identity=0
var phase=""
var seen={}
var active=[]
var emitted=0
func synchronize(engine) -> void:
	if engine_identity!=engine.get_instance_id():
		engine_identity=engine.get_instance_id();seen.clear();active.clear();phase=str(engine.state.phase)
		# Restored/opened matches display state, never replay their history.
		for event in engine.events:seen["event:"+str(event.seq)]=true
	if phase!=str(engine.state.phase):active.clear();phase=str(engine.state.phase)
func advance(delta: float,paused: bool) -> void:
	if not paused or allow_paused_motion:clock+=maxf(0,delta)
	active=active.filter(func(v):return clock-v.start<v.duration)
func add_once(identity: String,component: String,owner_instance: int,role: String="body",from_point: Vector2=Vector2.ZERO,to_point: Vector2=Vector2.ZERO) -> bool:
	if seen.has(identity):return false
	seen[identity]=true
	Art.initialize();var spec=Art.components.get(component,{})
	if spec.is_empty():return false
	active.append({"identity":identity,"component":component,"instance":owner_instance,"role":role,"start":clock,"duration":float(spec.duration_ms)/1000.0,"from":from_point,"to":to_point});emitted+=1
	return true
func active_for(instance: int) -> Array:return active.filter(func(v):return int(v.instance)==instance)
func prune(host) -> void:
	var ids=host.keyword_fx_anchors().keys()
	active=active.filter(func(v):return int(v.instance)<0 or int(v.instance) in ids)
func events(host,events_value: Array,anchors: Dictionary,visible_combat: bool=false) -> void:
	for event in events_value:
		if int(event.owner)!=0 or (event.get("phase","")=="combat" and not visible_combat):continue
		var id="event:"+str(event.seq)
		if seen.has(id):continue
		seen[id]=true
		var payload=event.payload
		if event.kind=="MagneticAttached":
			var target=int(payload.target);var origin=int(payload.instance_id)
			add_once(id+":MAGNETIC","fx.magnetic.event.active",target,"event",anchors.get(origin,Vector2.ZERO),anchors.get(target,Vector2.ZERO))
		if event.kind in ["CardGranted","RewardDelivered"] and int(event.owner)==0:
			var target=int(payload.get("instance_id",-1));var spell=host.keyword_fx_card(target)
			if not spell.is_empty() and host.registry.get_def(spell.def_id).get("is_spellcraft",false):
				var source=payload.get("presentation",{}).get("origin",spell.get("spellcraft_source_snapshot",{}))
				var source_id=int(source.get("instance_id",-1));var a=anchors.get(source_id,host.keyword_fx_source_anchor(source))
				var b=host.keyword_fx_anchor(target)
				if a!=Vector2.ZERO and b!=Vector2.ZERO:add_once(id+":SPELLCRAFT","fx.spellcraft.event.active",target,"event",a,b)
func shown_events(host,frame: Dictionary) -> void:
	var limit=int(frame.get("event_seq",0));var previous=0
	var frames=host.game.state.get("combat_frames",[])
	if host.frame_index>0 and host.frame_index-1<frames.size():previous=int(frames[host.frame_index-1].get("event_seq",0))
	var shown=host.game.events.filter(func(e):return int(e.seq)>previous and int(e.seq)<=limit and int(e.get("round",0))==int(host.game.state.round) and e.get("phase","")=="combat")
	events(host,shown,host.keyword_fx_anchors(),true)
func combat(host,frame: Dictionary,frame_identity: String) -> void:
	var data=frame.get("presentation",{})
	if data.is_empty():return
	var before=data.get("before",{});var damaged=data.get("damaged",{})
	var originals={}
	for c in before.get("left",[])+before.get("right",[]):originals[int(c.instance_id)]=c
	var previous_frame=host.game.state.get("combat_frames",[])[maxi(0,host.frame_index-1)] if not host.game.state.get("combat_frames",[]).is_empty() else before
	var previous_units={}
	for c in previous_frame.get("left",[])+previous_frame.get("right",[]):previous_units[int(c.instance_id)]=c
	for c in damaged.get("left",[])+damaged.get("right",[]):
		var old=originals.get(int(c.instance_id),{})
		if old.is_empty():continue
		for test in [["shield","fx.divine_shield.consume_event.consumed"],["venom","fx.venomous.consumed.active"]]:
			if old.get(test[0],false) and not c.get(test[0],false):add_once(frame_identity+":"+str(c.instance_id)+":"+test[0],test[1],int(c.instance_id),"body" if test[0]=="shield" else "venom")
		if "STEALTH" in previous_units.get(int(c.instance_id),old).get("keywords",[]) and "STEALTH" not in c.get("keywords",[]):add_once(frame_identity+":"+str(c.instance_id)+":reveal","fx.stealth.reveal.active",int(c.instance_id))
	for feedback in data.get("feedback",[]):
		if feedback.get("kind","")=="reborn":add_once(frame_identity+":reborn:"+str(feedback.get("instance_id",-1)),"fx.reborn.consume_event.consumed",int(feedback.get("instance_id",-1)))
	var attacker=int(data.get("attacker",-1));var old=originals.get(attacker,{})
	if not old.is_empty() and host.game.Triggers.effects(host.game,old).any(func(e):return e.get("op","")=="cleave"):
		add_once(frame_identity+":CLEAVE","fx.cleave.event.active",attacker,"event",combat_anchor(host,before,attacker),combat_anchor(host,before,int(data.get("target",-1))))
func combat_anchor(host,frame: Dictionary,instance: int) -> Vector2:
	var live=host.keyword_fx_anchor(instance)
	if live!=Vector2.ZERO:return live
	var table=host.screen.get_node_or_null("TavernTable")
	if table==null:return Vector2.ZERO
	var own_left=int(host.game.state.human_left)==0
	for side in ["left","right"]:
		var units=frame.get(side,[]);var index=units.find_custom(func(v):return int(v.instance_id)==instance)
		if index<0:continue
		var own=(side=="left")==own_left;var y=440.0 if own else 226.0
		var positions=table.Layout.row(table.rect(146,y-20,916,table.Layout.CARD.y+40),units.size(),table.Layout.CARD)
		return table.global_position+positions[index].position+Vector2(table.Layout.CARD.x*0.5,13+(table.Layout.CARD.y-45)*0.5)
	return Vector2.ZERO
func cancel_intent() -> void:active=active.filter(func(v):return v.component not in ["fx.magnetic.event.active","fx.choose_one.event.active"])
