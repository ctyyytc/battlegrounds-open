extends RefCounted
# Presentation-only composition. No engine/player references or random calls.
const ROOT="res://assets/ui/round143_skin/r2/"
static var records={}
static var textures={}
static var initialized=false
const ALIASES={"icon_socket_gold":"icon_seat_gold","icon_socket_teal":"icon_seat_teal","icon_socket_ice":"icon_seat_ice"}
class Trim extends Control:
	var color=Color("77edce")
	func _draw() -> void:
		var margin=4.0;var cut=minf(10,size.y*0.2);var end=size-Vector2(margin,margin)
		var points=PackedVector2Array([Vector2(margin+cut,margin),Vector2(end.x-cut,margin),Vector2(end.x,margin+cut),Vector2(end.x,end.y-cut),Vector2(end.x-cut,end.y),Vector2(margin+cut,end.y),Vector2(margin,end.y-cut),Vector2(margin,margin+cut),Vector2(margin+cut,margin)])
		draw_polyline(points,color,1.5,true)
static func trim(button: Button,color: Color,node_name: String="AvailabilityBorder") -> void:
	var border=Trim.new();border.name=node_name;border.color=color;border.mouse_filter=Control.MOUSE_FILTER_IGNORE
	button.add_child(border);border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);border.resized.connect(border.queue_redraw)
static func load_manifest() -> void:
	if initialized:return
	initialized=true
	if not FileAccess.file_exists(ROOT+"ASSET_MANIFEST.json"):return
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"ASSET_MANIFEST.json"))
	for item in manifest.get("records",[]):
		var key=str(item.get("consumer_key",item.id));var state=str(item.get("state","normal"))
		records[key if state=="normal" else key+"__"+state]=item
static func has(key: String) -> bool:
	load_manifest();return records.has(ALIASES.get(key,key))
static func data(key: String,state: String="normal") -> Dictionary:
	load_manifest()
	key=str(ALIASES.get(key,key))
	return records.get(key+"__"+state,records.get(key,{}))
static func texture(key: String,state: String="normal") -> Texture2D:
	var item=data(key,state)
	if item.is_empty():return null
	var path=ROOT+str(item.get("png",item.get("path","")))
	if not textures.has(path):textures[path]=load(path)
	return textures[path]
static func style(key: String,state: String="normal") -> StyleBoxTexture:
	var item=data(key,state);var image=texture(key,state)
	if image==null:return null
	var result=StyleBoxTexture.new();result.texture=image
	var margins=item.get("texture_margins",[18,18,18,18])
	var content=item.get("content_margins",[12,6,12,6])
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		result.set_texture_margin(side,float(margins[side]));result.set_content_margin(side,float(content[side]))
	return result
static func button(button: Button,role: String="button_secondary") -> void:
	if not has(role):return
	button.set_meta("skin_role",role)
	for state in ["normal","hover","pressed","disabled","focus"]:
		if state=="focus" and not records.has(role+"__focus"):
			var focus=StyleBoxFlat.new();focus.bg_color=Color.TRANSPARENT;focus.border_color=Color("a7d3d7");focus.set_border_width_all(1);focus.set_corner_radius_all(7);button.add_theme_stylebox_override(state,focus);continue
		var image=style(role,state)
		if image:button.add_theme_stylebox_override(state,image)
	button.add_theme_color_override("font_color",Color("f0e5cd"));button.add_theme_color_override("font_hover_color",Color("fff7df"))
	button.add_theme_color_override("font_disabled_color",Color("9eabae"))
static func panel(node: Control,key: String="panel_detail") -> void:
	var image=style(key)
	if image:node.add_theme_stylebox_override("panel",image);node.set_meta("skin_role",key)
static func frame(parent: Control,key: String,area: Rect2,node_name: String="") -> TextureRect:
	var image=TextureRect.new();image.name=node_name if node_name!="" else "Skin_"+key
	image.texture=texture(key);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(image);image.position=area.position;image.size=area.size
	return image
static func mask_portrait(art: TextureRect) -> void:
	if not has("portrait_alpha_mask"):return
	var material=ShaderMaterial.new();material.shader=preload("res://ui/round143_portrait_mask.gdshader")
	material.set_shader_parameter("portrait_mask",texture("portrait_alpha_mask"));art.material=material
	art.stretch_mode=TextureRect.STRETCH_SCALE
	if art.texture:material.set_shader_parameter("source_size",art.texture.get_size())
	var resize=func():material.set_shader_parameter("portrait_size",Vector2(maxf(1,art.size.x),maxf(1,art.size.y)))
	resize.call();art.resized.connect(resize)
static func install_theme(theme: Theme) -> void:
	if not has("button_secondary"):return
	for state in ["normal","hover","pressed","disabled","focus"]:theme.set_stylebox(state,"Button",style("button_compact",state))
	for type in ["PanelContainer","Panel","PopupPanel","TooltipPanel"]:theme.set_stylebox("panel",type,style("window" if type in ["PopupPanel","TooltipPanel"] else "panel_detail"))
	for state in ["normal","focus","read_only"]:theme.set_stylebox(state,"LineEdit",style("nameplate"))
	for state in ["scroll","grabber","grabber_highlight","grabber_pressed"]:
		var key="scroll_track" if state=="scroll" else "scroll_thumb"
		if has(key):theme.set_stylebox(state,"VScrollBar",style(key,"pressed" if state=="grabber_pressed" else "hover" if state=="grabber_highlight" else "normal"))
