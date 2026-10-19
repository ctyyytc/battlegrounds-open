extends Control
# Presentation only. Receipts are already committed; this node never dispatches rules.
var host
var active=[]
var receipt_cutoff=0
var clock=0.0
var engine_identity=0
var phase=""
var emitted=0
func _ready() -> void:
	name="ConsumptionFeedback";mouse_filter=Control.MOUSE_FILTER_IGNORE;z_index=72
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func synchronize() -> void:
	if host==null or host.game==null or not host.in_match:skip_all();return
	if engine_identity!=host.game.get_instance_id():
		engine_identity=host.game.get_instance_id();skip_all();receipt_cutoff=int(host.game.state.event_seq)
	if phase!=str(host.game.state.phase):skip_all();phase=str(host.game.state.phase)
func feedback(events: Array,anchors: Dictionary) -> void:
	synchronize()
	for event in events:
		if int(event.seq)<=receipt_cutoff:continue
		receipt_cutoff=int(event.seq)
		if int(event.owner)!=0 or event.get("phase","")!="recruit" or event.kind not in ["ShopMinionConsumed","DevourResolved"]:continue
		var data=event.payload;var source=data.get("consumed_snapshot",{})
		if source.is_empty():continue
		var target=int(data.get("source_instance",-1)) if event.kind=="ShopMinionConsumed" else int(data.get("target_instance",-1))
		if target<0:continue
		var from_point=anchors.get(int(source.instance_id),Vector2(host.size.x*0.5,host.size.y*0.3))
		var to_point=anchors.get(target,host.keyword_fx_anchor(target))
		if to_point==Vector2.ZERO:continue
		var start=clock
		if not active.is_empty():start=maxf(start,float(active[-1].start)+float(active[-1].spacing))
		var reduced=host.game.state.get("r134_reduced_motion",false)
		var hold=0.24 if reduced or not host.fast_mode_enabled else 0.18 if host.fast_mode_level>=2 else 0.20
		var flight=0.08 if reduced else 0.14 if host.fast_mode_level>=2 else 0.18 if host.fast_mode_enabled else 0.24
		var absorb=0.08 if reduced else 0.10 if host.fast_mode_enabled else 0.16
		var spacing=0.12 if reduced or host.fast_mode_level>=2 else 0.14 if host.fast_mode_enabled else 0.18
		active.append({"seq":event.seq,"snapshot":source.duplicate(true),"target":target,"from":from_point,"to":to_point,"start":start,"hold":hold,"flight":flight,"duration":hold+flight+absorb,"spacing":spacing,"reduced":reduced,"attack":data.attack,"health":data.health})
		emitted+=1
func skip_all() -> void:active.clear();queue_redraw()
func _process(delta: float) -> void:
	synchronize()
	if host==null or host.game==null or not host.in_match:return
	# These receipts have already settled. Game pause stops rules and the timer,
	# while this local presentation clock still finishes and retires its sprites.
	clock+=maxf(0,delta)
	active=active.filter(func(v):return clock-float(v.start)<float(v.duration))
	queue_redraw()
func _draw() -> void:
	if host==null or host.game==null or not host.in_match:return
	for entry in active:
		var elapsed=clock-float(entry.start)
		if clock<float(entry.start):continue
		var from_point=entry.from-global_position;var to_point=entry.to-global_position
		var travel=clampf((elapsed-float(entry.hold))/float(entry.flight),0,1);var eased=travel*travel*(3-2*travel)
		var point=from_point if entry.reduced else from_point.lerp(to_point,eased)+Vector2(0,-48*sin(travel*PI))
		var alpha=1-travel if entry.reduced else 1.0 if travel<0.8 else (1-travel)*5
		if travel<1:
			var size_value=Vector2(104,134)*(1.0 if entry.reduced else lerpf(1,0.12,eased))
			var area=Rect2(point-size_value*0.5,size_value)
			draw_style_box(host.box(Color("243839"),Color("acdeb8"),8),area)
			var image=host.texture_for_path(host.registry.art_path(entry.snapshot.def_id))
			if image:draw_texture_rect(image,Rect2(area.position+size_value*Vector2(0.04,0.16),size_value*Vector2(0.92,0.66)),false,Color(1,1,1,alpha))
			if not entry.reduced:draw_line(point,to_point,Color(0.6,0.9,0.7,0.35*travel*(1-travel)),2,true)
			var caption=host.registry.get_def(entry.snapshot.def_id).get("name",entry.snapshot.def_id)
			draw_string(get_theme_default_font(),area.position+Vector2(3,16),caption,HORIZONTAL_ALIGNMENT_CENTER,size_value.x-6,12,Color(0.85,1,0.88,alpha))
			draw_string(get_theme_default_font(),area.position+Vector2(3,size_value.y-5),"%d / %d" % [int(entry.attack),int(entry.health)],HORIZONTAL_ALIGNMENT_CENTER,size_value.x-6,16,Color(0.85,1,0.88,alpha))
		if elapsed>=float(entry.hold)+float(entry.flight):
			var pulse=clampf((elapsed-float(entry.hold)-float(entry.flight))/(float(entry.duration)-float(entry.hold)-float(entry.flight)),0,1)
			draw_arc(to_point,22+pulse*27,0,TAU,48,Color(0.65,1,0.77,1-pulse),3,true)
			draw_string(get_theme_default_font(),to_point+Vector2(-45,-30-pulse*24),"+%d/+%d" % [int(entry.attack),int(entry.health)],HORIZONTAL_ALIGNMENT_CENTER,90,20,Color(0.75,1,0.8,1-pulse))
