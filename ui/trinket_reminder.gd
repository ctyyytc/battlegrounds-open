extends Control
## A read-only projection of synchronized purchase opportunities, never a command.
var host
var opportunity_id=""
static func owner_live(p: Dictionary,o: Dictionary) -> bool:
	if o.is_empty():return true
	for slot in p.get("power_slots",[]):
		if int(slot.slot_id)==int(o.get("slot_id",-1)):
			return int(slot.epoch)==int(o.get("epoch",-1)) and str(slot.active_power_id)==str(o.get("power_id",""))
	return false
static func unresolved(p: Dictionary,id: String) -> bool:
	var s=p.get("sessions",{}).get(id,{})
	return not s.get("resolved",false) and not s.get("cancelled",false)
static func voucher(engine,p: Dictionary,item: Dictionary) -> String:
	if item.get("id","")!="BG30_MagicItem_891" or not owner_live(p,item.get("power_owner",{})):return ""
	var due=int(item.get("acquired_round",int(item.get("next_round",int(engine.state.round)+2))-2))+2
	var id="voucher:"+str(item.get("instance_id",-1))
	return id if (item.get("voucher_open",false) or int(engine.state.round)>=due) and unresolved(p,id) else ""
static func entries(engine) -> Dictionary:
	var result={}
	if engine==null or engine.state.get("phase","")!="recruit" or engine.state.get("players",[]).is_empty():return result
	var p=engine.state.players[0]
	if not p.get("alive",false):return result
	for category in ["lesser","greater"]:
		var owned=p.get("trinkets",[]).filter(func(c):return str(c.get("slot_size",c.get("size","")))==category)
		if owned.is_empty():
			if int(engine.state.round)>=(6 if category=="lesser" else int(p.get("greater_unlock",9))) and unresolved(p,category):result[category]=category
		else:
			var id=voucher(engine,p,owned[0])
			if id!="":result[category]=id
	for slot in p.get("power_slots",[]):
		var entrance="power:"+str(slot.slot_id)
		var id="power:%d:%d" % [int(slot.slot_id),int(slot.epoch)]
		var op=p.get("r136_slots",{}).get("opportunities",{}).get(id,{})
		if not op.is_empty() and not op.get("purchased",false) and not op.get("cancelled",false) and owner_live(p,op.get("owner",{})) and int(engine.state.round)>=int(op.unlock_round) and unresolved(p,id):result[entrance]=id
		for item in p.get("trinkets",[]):
			var o=item.get("power_owner",{})
			if int(o.get("slot_id",-1))!=int(slot.slot_id):continue
			var voucher_id=voucher(engine,p,item)
			if voucher_id!="":result[entrance]=voucher_id;break
	return result
static func attach(button: Button,screen_host,id: String) -> void:
	if id=="":return
	var decoration=load("res://ui/trinket_reminder.gd").new();decoration.host=screen_host;decoration.opportunity_id=id;decoration.name="TrinketReminder"
	button.add_child(decoration);decoration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var badge=screen_host.label("待选",11,Color("ffe6a3"));badge.name="ReminderText";badge.mouse_filter=Control.MOUSE_FILTER_IGNORE;decoration.add_child(badge);badge.position=Vector2(2,-14)
	var session=screen_host.game.state.players[0].get("sessions",{}).get(id,{})
	var costs=session.get("options",[]).map(func(v):return str(int(v.cost))+"币")
	button.tooltip_text+="\n已解锁可选择 · "+(" / ".join(costs) if not costs.is_empty() else "打开后查看各候选费用")+"（余额不足仍保留机会）"
	button.set_meta("reminder_opportunity",id)
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;z_index=8
func _process(_delta: float) -> void:
	queue_redraw()
func _draw() -> void:
	var alpha=1.0
	var covered=host.ui_blocked() or host.get_node_or_null("ChoiceOverlay")!=null and not host.choice_view_is_hidden()
	if not host.reduced_motion_enabled and not covered:alpha=0.52+0.48*(0.5+0.5*sin(float(Time.get_ticks_msec()%1800)/1800.0*TAU))
	draw_style_box(border(Color(1,0.79,0.35,alpha)),Rect2(Vector2(-2,-2),size+Vector2(4,4)))
func border(color: Color) -> StyleBoxFlat:
	var style=StyleBoxFlat.new();style.bg_color=Color.TRANSPARENT;style.border_color=color;style.set_border_width_all(3);style.set_corner_radius_all(10);return style
