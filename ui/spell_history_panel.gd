extends Control
const ExternalText = preload("res://domain/resources/external_content.gd")
const SpellText=preload("res://ui/spell_presentation.gd")
var host
var page=0
var selected_seq=-1
const PAGE_SIZE=5
var scroll_areas: Array=[]
var middle_scroll: ScrollContainer
var middle_origin=Vector2.ZERO
var middle_start=0.0
func stop_middle_scroll() -> void:
 if is_instance_valid(middle_scroll):middle_scroll.mouse_default_cursor_shape=Control.CURSOR_ARROW
 middle_scroll=null
func scroll_at(position_value: Vector2) -> ScrollContainer:
 for area in scroll_areas:
  if is_instance_valid(area) and Rect2(Vector2.ZERO,area.size).has_point(area.get_global_transform_with_canvas().affine_inverse()*position_value):return area
 return null
func _input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.button_index==MOUSE_BUTTON_MIDDLE:
   if event.pressed:
    var area=scroll_at(event.position)
    if area==null:return
    middle_scroll=area;middle_origin=event.position;middle_start=area.get_v_scroll_bar().value
    area.mouse_default_cursor_shape=Control.CURSOR_VSIZE
   else:
    if not is_instance_valid(middle_scroll):return
    stop_middle_scroll()
   get_viewport().set_input_as_handled();return
  if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   var area=scroll_at(event.position)
   if area!=null:
    area.get_v_scroll_bar().value+=(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*72.0*maxf(1.0,event.factor)
    get_viewport().set_input_as_handled();return
 if event is InputEventMouseMotion and is_instance_valid(middle_scroll):
  middle_scroll.get_v_scroll_bar().value=middle_start+middle_origin.y-event.position.y
  get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
 if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT,NOTIFICATION_EXIT_TREE]:stop_middle_scroll()
func prepare_scroll(scroll: ScrollContainer) -> void:
 scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
 scroll.mouse_force_pass_scroll_events=false
 scroll_areas.append(scroll)
 var bar=scroll.get_v_scroll_bar();bar.custom_minimum_size.x=18
 var track=StyleBoxFlat.new();track.bg_color=Color("0b1622");track.set_corner_radius_all(6);bar.add_theme_stylebox_override("scroll",track)
 for state in ["grabber","grabber_highlight","grabber_pressed"]:
  var grip=StyleBoxFlat.new();grip.bg_color=host.BTheme.TEAL if state=="grabber" else host.BTheme.GOLD;grip.set_corner_radius_all(6)
  grip.content_margin_left=6;grip.content_margin_right=6;grip.content_margin_top=12;grip.content_margin_bottom=12
  bar.add_theme_stylebox_override(state,grip)
 if host.UISkin.has("scroll_track"):bar.add_theme_stylebox_override("scroll",host.UISkin.style("scroll_track"))
 for state in ["grabber","grabber_highlight","grabber_pressed"]:
  if host.UISkin.has("scroll_thumb"):bar.add_theme_stylebox_override(state,host.UISkin.style("scroll_thumb","pressed" if state=="grabber_pressed" else "hover" if state=="grabber_highlight" else "normal"))
func _ready() -> void:
 name="SpellHistoryOverlay";z_index=90
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter=Control.MOUSE_FILTER_STOP
 rebuild()
func readable(entry: Dictionary) -> String:
 var action={"cast":ExternalText.ui("ui_spell_history_panel.readable.593d013875d0", "施放"),"gain":ExternalText.ui("ui_spell_history_panel.readable.441c6ce24dbf", "获得"),"pending":ExternalText.ui("ui_spell_history_panel.readable.0a69ed50ce43", "获得 · 手满待领取"),"unavailable":ExternalText.ui("ui_spell_history_panel.readable.a9e7a2726363", "无实际收益")}.get(entry.action,entry.action)
 var phase={"recruit":ExternalText.ui("ui_spell_history_panel.readable.fd66d4f7a7a3", "招募"),"turn_end":ExternalText.ui("ui_spell_history_panel.readable.6c641cf8f1df", "回合结束"),"combat":ExternalText.ui("ui_spell_history_panel.readable.3c83193d1a3b", "战斗"),"turn_start":ExternalText.ui("ui_spell_history_panel.readable.5d18f496e3dd", "回合开始")}.get(entry.phase,entry.phase)
 var target=" → "+str(entry.target.name)+" #"+str(int(entry.target.instance_id)) if not entry.target.is_empty() else ""
 return ExternalText.ui("ui_spell_history_panel.readable.415156cf5a8a", "第%d回合 · %s · %s\n%s%s\n来源：%s%s") % [entry.round,phase,action,entry.name,target,entry.source.name,ExternalText.ui("ui_spell_history_panel.readable.940449be1eed", " · 追加施放%d") % entry.repeat_index if entry.action=="cast" and int(entry.repeat_index)>0 else ""]
func rebuild() -> void:
 stop_middle_scroll();scroll_areas.clear()
 for child in get_children():remove_child(child);child.queue_free()
 var shade=ColorRect.new();shade.color=Color(0,0,0,0.70);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
 var center=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);center.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(center)
 var panel=PanelContainer.new();panel.custom_minimum_size=Vector2(minf(1000,host.size.x-48),minf(700,host.size.y-48));panel.add_theme_stylebox_override("panel",host.BTheme.style());host.UISkin.panel(panel,"window");center.add_child(panel)
 var column=VBoxContainer.new();column.add_theme_constant_override("separation",12);panel.add_child(column)
 var entries=host.visible_spell_history();entries.reverse()
 page=clampi(page,0,maxi(0,ceili(entries.size()/float(PAGE_SIZE))-1));host.history_page=page
 var header=HBoxContainer.new();column.add_child(header)
 header.add_child(host.label(ExternalText.ui("ui_spell_history_panel.rebuild.f516f381aea3", "法术记录 · 最近160条"),24,host.GOLD));header.add_child(host.stretch());header.add_child(host.button(ExternalText.ui("ui_spell_history_panel.rebuild.a1e25e38896d", "关闭"),host.close_spell_history,"SpellHistoryClose"))
 var row=HBoxContainer.new();row.add_theme_constant_override("separation",16);row.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(row)
 var scroll=ScrollContainer.new();scroll.name="SpellHistoryRows";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.custom_minimum_size.x=380;scroll.size_flags_stretch_ratio=0.42;row.add_child(scroll);prepare_scroll(scroll)
 var list=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",8);scroll.add_child(list)
 var selected={}
 for entry in entries:
  if int(entry.seq)==selected_seq:selected=entry;break
 if selected.is_empty() and not entries.is_empty():selected=entries[page*PAGE_SIZE];selected_seq=int(selected.seq)
 host.history_selected_seq=selected_seq
 for i in range(page*PAGE_SIZE,mini((page+1)*PAGE_SIZE,entries.size())):
  var entry=entries[i]
  var b=host.button("",func():selected_seq=int(entry.seq);rebuild(),"SpellHistoryRow_"+str(int(entry.seq)))
  b.custom_minimum_size.y=132;b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  b.add_theme_stylebox_override("normal",host.box(Color("1d414c") if int(entry.seq)==selected_seq else host.BTheme.PANEL,host.GOLD if int(entry.seq)==selected_seq else host.MUTED))
  host.UISkin.button(b,"option_card")
  var label_node=host.label(readable(entry),16);label_node.name="RecordText";label_node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label_node.max_lines_visible=4;label_node.clip_text=true;label_node.mouse_filter=Control.MOUSE_FILTER_IGNORE
  b.add_child(label_node);label_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);label_node.offset_left=18;label_node.offset_right=-18;label_node.offset_top=18;label_node.offset_bottom=-18;list.add_child(b)
 if entries.is_empty():list.add_child(host.label(ExternalText.ui("ui_spell_history_panel.rebuild.67a9058b7dd4", "尚无法术记录。"),19))
 var detail_scroll=ScrollContainer.new();detail_scroll.name="SpellHistoryDetailScroll";detail_scroll.custom_minimum_size.x=460;detail_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail_scroll.size_flags_stretch_ratio=0.58;row.add_child(detail_scroll);prepare_scroll(detail_scroll)
 var detail=VBoxContainer.new();detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail.add_theme_constant_override("separation",8);detail_scroll.add_child(detail)
 if not selected.is_empty():
  var name_label=host.label(selected.name,23,host.GOLD);name_label.name="SpellHistoryPreviewName";name_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.add_child(name_label)
  if selected.action!="unavailable":detail.add_child(host.image_for(selected.id,Vector2(260,220)))
  var body=RichTextLabel.new();body.name="SpellHistoryPreviewBody";body.bbcode_enabled=true;body.scroll_active=false;body.fit_content=true;body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.mouse_filter=Control.MOUSE_FILTER_PASS;body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_theme_font_size_override("normal_font_size",18);detail.add_child(body)
  body.text=SpellText.escape(readable(selected))+"\n\n"+(SpellText.body(selected.spell,selected.player,true) if selected.action!="unavailable" else SpellText.escape(selected.reason))
  if selected.action=="pending":body.text+=ExternalText.ui("ui_spell_history_panel.rebuild.50a30d0e2f75", "\n\n手牌出现空位后领取；保留生成时的有效期。")
 var footer=HBoxContainer.new();column.add_child(footer)
 footer.add_child(host.button(ExternalText.ui("ui_spell_history_panel.rebuild.b9aa5ff8fbf4", "较新的记录"),func():page-=1;selected_seq=-1;rebuild(),"SpellHistoryNewer",page==0))
 footer.add_child(host.label(ExternalText.ui("ui_spell_history_panel.rebuild.d228ce8c9403", "第%d/%d页 · %d条可见记录") % [page+1,maxi(1,ceili(entries.size()/float(PAGE_SIZE))),entries.size()],17))
 footer.add_child(host.button(ExternalText.ui("ui_spell_history_panel.rebuild.bf908742f691", "较早的记录"),func():page+=1;selected_seq=-1;rebuild(),"SpellHistoryOlder",(page+1)*PAGE_SIZE>=entries.size()))

 column.add_child(host.label("滚轮滚动 · 按住中键拖动 · 可拖动右侧滚动条",14,host.BTheme.MUTED))
