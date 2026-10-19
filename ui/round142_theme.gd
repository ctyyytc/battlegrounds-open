extends RefCounted
# Frozen r2 assets. Presentation only; external definitions and portraits stay intact.
const ROOT="res://assets/ui/round142_b/"
const ICON_ROOT="res://assets/ui/round143_icons/"
const PANEL=Color("102330")
const RAISED=Color("1a3341")
const BORDER=Color("85744f")
const TEXT=Color("eeeadd")
const MUTED=Color("bdcbd0")
const TEAL=Color("7edccc")
const GOLD=Color("dfc583")
static var textures={}
static var paths={}
static func texture(id: String) -> Texture2D:
	if paths.is_empty():
		var manifest=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"ASSET_MANIFEST.json"))
		for item in manifest.records:
			var path=ROOT+str(item.get("raster_path",item.path))
			paths[item.id]=path
			if item.get("asset_key")!=null:paths[item.asset_key]=path
		if FileAccess.file_exists(ICON_ROOT+"ASSET_MANIFEST.json"):
			var icons=JSON.parse_string(FileAccess.get_file_as_string(ICON_ROOT+"ASSET_MANIFEST.json"))
			for item in icons.records:
				var path=ICON_ROOT+str(item.png)
				paths[item.id]=path
				var alias="button_"+str(item.semantic) if item.role!="opponent_marker" else str(item.semantic)
				if item.semantic in ["next_opponent","current_opponent","ghost"]:alias=str(item.semantic)
				paths[alias+"."+str(item.state)]=path
				if item.get("legacy_theme_alias")!=null:paths[item.legacy_theme_alias]=path
	if not paths.has(id):return null
	if not textures.has(id):
		textures[id]=load(paths[id])
	return textures[id]
static func icon(id: String,state: String="normal") -> Texture2D:
	var value=texture(id+"."+state)
	return value if value else texture(id)
static func style(id: String="panel_base") -> StyleBoxTexture:
	var s=StyleBoxTexture.new();s.texture=texture(id)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:s.set_texture_margin(side,18)
	s.content_margin_left=16;s.content_margin_right=16;s.content_margin_top=12;s.content_margin_bottom=12
	return s
