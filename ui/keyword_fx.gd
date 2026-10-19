extends RefCounted
const State=preload("res://ui/keyword_fx_state.gd")
const ROOT="res://assets/ui/runtime21/"
static var components={}
static var loaded=false
static func initialize() -> void:
	if loaded:return
	loaded=true
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"CONSUMER_MAP.json"))
	if manifest is Dictionary:components=manifest.get("records",{})
static func frame_index(key: String,time: float,reduced: bool=false) -> int:
	initialize();var spec=components.get(key,{})
	var count=int(spec.get("frame_count",1));var duration=float(spec.get("duration_ms",0))/1000.0
	if count<=1 or duration<=0 or reduced:return 0
	return mini(count-1,int(maxf(0,time)/duration*count)%count) if spec.get("loop",false) else mini(count-1,int(maxf(0,time)/duration*count))
static func image(host,key: String,time: float=0.0) -> Texture2D:
	initialize();var spec=components.get(key,{})
	if spec.is_empty():return null
	var index=frame_index(key,time,host.game.state.get("r134_reduced_motion",false))
	return host.ui_texture(spec.frames[index].consumer_key)
static func draw(canvas: CanvasItem,host,key: String,area: Rect2,time: float=0.0,color: Color=Color.WHITE) -> void:
	var texture=image(host,key,time)
	if texture:canvas.draw_texture_rect(texture,area,false,color)
static func body_rect(card_node) -> Rect2:
	var g=card_node.minion_geometry();var extent=card_node.canvas_size()
	var available=Rect2(3,1,extent.x-6,maxf(1,g.title.position.y-2))
	var side=minf(available.size.x,available.size.y+6)
	return Rect2(Vector2(available.get_center().x-side*0.5,available.end.y-side),Vector2.ONE*side)
static func back(card_node,view: Dictionary) -> void:
	var host=card_node.host;var area=body_rect(card_node);var time=host.keyword_fx.clock
	if "WINDFURY" in view.body:draw(card_node,host,"fx.windfury.wind_back.active",area,time)
	if "TAUNT" in view.body:draw(card_node,host,"fx.taunt.physical_frame.active",area)
static func portrait(card_node,texture: Texture2D,area: Rect2,view: Dictionary) -> void:
	if "TAUNT" not in view.body:
		card_node.draw_texture_rect(texture,area,false);return
	# Runtime-only portrait matte. The original image remains untouched; the
	# shield's physical rim stays visible around the portrait, never over a face.
	var body=body_rect(card_node);var center=body.get_center();var radius=body.size*Vector2(0.35,0.39)
	var points=PackedVector2Array();var uv=PackedVector2Array()
	for i in 64:
		var angle=TAU*i/64.0;var point=center+Vector2(cos(angle),sin(angle))*radius
		points.append(point);uv.append((point-area.position)/area.size)
	card_node.draw_polygon(points,PackedColorArray([Color.WHITE]),uv,texture)
static func attachment_rect(card_node,index: int,count: int) -> Rect2:
	var extent=card_node.canvas_size();var title=card_node.minion_geometry().title.position.y
	var side=28.0/card_node.visual_ratio();var half=side*0.5
	if count<=3:return Rect2(Vector2(extent.x*0.5+(index-(count-1)*0.5)*(side+2)-half,title-side-1),Vector2.ONE*side)
	# One compact perimeter, not a row below the card or a truncated field shelf.
	var center=Vector2(extent.x*0.5,(title+8)*0.5);var radius=Vector2(maxf(0,extent.x*0.5-half-1),maxf(0,(title-side-4)*0.5))
	var angle=PI*0.5+TAU*index/count
	return Rect2(center+Vector2(cos(angle),sin(angle))*radius-Vector2.ONE*half,Vector2.ONE*side)
static func marker(canvas: CanvasItem,host,entry: Dictionary,area: Rect2) -> void:
	var key=str(entry.key).to_lower();var time=host.keyword_fx.clock
	var factor=area.size.x/28.0
	draw(canvas,host,"fx.shared.backplate",area)
	if entry.get("glow",false):draw(canvas,host,"fx."+key+".conditional_glow.highlight",area.grow(6*factor),time)
	if entry.key=="ACTIVATE":
		if entry.state in ["available","used"]:draw(canvas,host,"fx.activate."+entry.state+"."+entry.state,area)
		var symbol=Rect2(area.position+Vector2(5,4)*factor,Vector2(18,18)*factor)
		draw(canvas,host,"fx.activate.symbol.active",symbol,0,Color(0.65,0.65,0.65) if entry.state=="unavailable" else Color.WHITE)
		if entry.state=="used":draw(canvas,host,"fx.activate.used_badge.used_badge",Rect2(area.position+Vector2(8,16)*factor,Vector2(21,12)*factor))
		if entry.state=="unavailable":draw(canvas,host,"fx.activate.unavailable_badge.unavailable_badge",Rect2(area.position+Vector2(16,16)*factor,Vector2(12,12)*factor))
	else:
		var role="active" if entry.key in ["VENOMOUS","POISONOUS"] else "symbol"
		var offset=Vector2(5,4) if entry.key=="DEATHRATTLE" else Vector2(5,5)
		draw(canvas,host,"fx."+key+"."+role+".active",Rect2(area.position+offset*factor,Vector2(18,18)*factor),time)
static func native_wind_curls(host) -> bool:
	initialize()
	var external=host.ExternalText.load_pack().get("assets",{})
	for key in ["fx.windfury.wind_back.active","fx.windfury.wind_front.active"]:
		for frame in components[key].frames:
			if external.has(frame.consumer_key):return false
	return true
static func front(card_node,view: Dictionary) -> void:
	var host=card_node.host;var area=body_rect(card_node);var time=host.keyword_fx.clock
	for pair in [["REBORN","fx.reborn.fractured_shell.active"],["DIVINE_SHIELD","fx.divine_shield.energy_shell.active"],["STEALTH","fx.stealth.smoke.active"],["WINDFURY","fx.windfury.wind_front.active"]]:
		if pair[0] in view.body:draw(card_node,host,pair[1],area,time)
	if "WINDFURY" in view.body and native_wind_curls(host):
		# Keep two readable wind curls on the front rim even when the subtle
		# raster back layer is hidden by a portrait/frame or motion is paused.
		var radius=area.size.x*0.46;var center=area.get_center()
		var drift=sin(time*TAU/1.2)*0.06
		for offset in [0.0,PI]:
			card_node.draw_arc(center,radius,offset-0.28+drift,offset+1.12+drift,28,Color("acebf1"),2.2,true)
			card_node.draw_arc(center,radius-4,offset-0.05+drift,offset+0.9+drift,24,Color(0.42,0.82,0.91,0.8),1.2,true)
	for effect in host.keyword_fx.active_for(int(card_node.card.instance_id)):
		if effect.role=="body":draw(card_node,host,effect.component,area,time-effect.start)
		elif effect.role=="venom":draw(card_node,host,effect.component,Rect2(Vector2(area.get_center().x-9,card_node.minion_geometry().title.position.y-19),Vector2(18,18)),time-effect.start)
	for index in view.markers.size():marker(card_node,host,view.markers[index],attachment_rect(card_node,index,view.markers.size()))
class HostMarkers extends Control:
	var painter: Callable
	var host
	var source={}
	var slot={}
	func entries() -> Array:
		var p=host.game.state.players[0];var combat=host.game.state.phase=="combat";var cutoff=int(host.combat_presentation.get("event_seq",host.game.state.event_seq))
		return State.power(host.game,p,slot,combat,cutoff) if not slot.is_empty() else State.triggers(host.game,p,source,host.registry.get_def(source.get("id","")).get("effects",[]),combat,cutoff)
	func _draw() -> void:
		var list=entries()
		for i in list.size():painter.call(self,host,list[i],Rect2(Vector2(i*29,0),Vector2(28,28)))
static func attach_host(parent: Control,host,source: Dictionary,slot: Dictionary={}) -> void:
	var layer=HostMarkers.new();layer.painter=marker;layer.host=host;layer.source=source;layer.slot=slot;layer.name="KeywordHostMarkers";layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer);layer.position=Vector2(1,1);layer.z_index=5;layer.size=Vector2(parent.size.x,28)
class EventCanvas extends Control:
	var only_choice=false
	var painter: Callable
	var texture_reader: Callable
	var host
	func subtract(rects: Array,cut: Rect2) -> Array:
		var result=[]
		for r in rects:
			var hit=r.intersection(cut)
			if not hit.has_area():result.append(r);continue
			for part in [Rect2(r.position,Vector2(r.size.x,hit.position.y-r.position.y)),Rect2(Vector2(r.position.x,hit.end.y),Vector2(r.size.x,r.end.y-hit.end.y)),Rect2(Vector2(r.position.x,hit.position.y),Vector2(hit.position.x-r.position.x,hit.size.y)),Rect2(Vector2(hit.end.x,hit.position.y),Vector2(r.end.x-hit.end.x,hit.size.y))]:
				if part.has_area():result.append(part)
		return result
	func safe_rects() -> Array:
		var table=host.screen.get_node_or_null("TavernTable")
		if table==null:return []
		var areas=[table.area(table.Layout.HAND)]
		if host.game.state.phase=="combat":areas.append_array([table.rect(146,206,916,206),table.rect(146,420,916,206)])
		else:areas.append_array([table.regions.board,table.regions.shop])
		var safe=[]
		for r in areas:safe.append(Rect2(r.position+table.global_position-global_position,r.size))
		var original=safe.duplicate()
		for value in table.cards:
			var node=value.node;var ratio=node.visual_ratio();var extent=node.canvas_size();var geometry=node.minion_geometry()
			safe=subtract(safe,Rect2(node.global_position-global_position,node.size))
			var art=geometry.art
			if host.registry.get_def(value.card.def_id).kind=="minion":art.size.y=minf(art.size.y,geometry.title.position.y-art.position.y-1)
			else:art=Rect2(extent.x*0.13,12,extent.x*0.74,extent.y*0.48)
			var body=Rect2(node.global_position-global_position+art.position*ratio,art.size*ratio)
			for region in original:
				var clipped=region.intersection(body)
				if clipped.has_area():safe.append(clipped)
			var protected_star=Rect2(node.global_position-global_position+Vector2(extent.x*0.5-20,-14)*ratio,Vector2(43,24)*ratio)
			safe=subtract(safe,protected_star)
		if is_instance_valid(host.toast):safe=subtract(safe,Rect2(host.toast.global_position-global_position,host.toast.size))
		return safe
	func mapped(texture: Texture2D,transform_value: Transform2D,areas: Array) -> void:
		var inverse=transform_value.affine_inverse()
		for area in areas:
			var points=PackedVector2Array([area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)])
			var uv=PackedVector2Array()
			for point in points:uv.append((inverse*point)/Vector2(512,256))
			draw_polygon(points,PackedColorArray([Color.WHITE]),uv,texture)
	func _draw() -> void:
		var safe=[]
		for effect in host.keyword_fx.active:
			if effect.role not in ["event","choice"] or (effect.role=="choice")!=only_choice:continue
			var texture=texture_reader.call(host,effect.component,host.keyword_fx.clock-effect.start)
			if texture==null:continue
			if only_choice:
				var options=get_parent().find_children("Choice_*","Button",true,false)
				for i in mini(2,options.size()):
					var target=Rect2(options[i].global_position-global_position,options[i].size).grow(-3)
					draw_texture_rect_region(texture,target,Rect2(52 if i==0 else 310,38,144,183))
				continue
			var a=effect.from-global_position;var b=effect.to-global_position
			if effect.from==Vector2.ZERO or effect.to==Vector2.ZERO or a==b:continue
			if safe.is_empty():safe=safe_rects()
			var source=Vector2(126,128);var target=Vector2(389,126)
			if effect.component=="fx.spellcraft.event.active":source=Vector2(126,148);target=Vector2(396,55)
			if effect.component=="fx.cleave.event.active":
				var factor=124.0/81.0
				mapped(texture,Transform2D(0,Vector2.ONE*factor,0,b-Vector2(387,71)*factor),safe);continue
			var scale_value=(b-a).length()/(target-source).length()
			var rotation_value=(b-a).angle()-(target-source).angle()
			var origin=a-(source*scale_value).rotated(rotation_value)
			mapped(texture,Transform2D(rotation_value,Vector2.ONE*scale_value,0,origin),safe)
