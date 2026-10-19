extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
static func progress(d: Dictionary,c: Dictionary,p: Dictionary,round_number: int) -> String:
 var lines=[]
 for e in d.get("effects",[]):
  if e.get("handler","")!="round10":continue
  match str(e.get("op","")):
   "prince":lines.append(ExternalText.phrase("ui_demon_presentation.progress.7f9a7a556ef8", "说明待补充 · %d") % (int(e.amount)-(int(c.get("prince_used",0)) if int(c.get("prince_round",-1))==round_number else 0)))
   "give":
    if d.get("base_id","")=="BG36_733":lines.append(ExternalText.phrase("ui_demon_presentation.progress.518c6b47cf35", "说明待补充 · %d") % (4-int(c.get("cake_damage",0))))
   "void":lines.append(ExternalText.phrase("ui_demon_presentation.progress.52bb3884e61f", "说明待补充 · %d / %d / %d") % [int(c.get("void_bonus",2)),int(c.get("void_bonus",2)),3-int(c.get("void_hits",0))])
   "cheese":lines.append(ExternalText.phrase("demon_presentation.8d42ba84255e", "说明待补充 · %d / %d / %d") % [int(c.get("cheese_bonus",2)),int(c.get("cheese_bonus",2)),4-int(c.get("cheese_refreshes",0))])
   "eye":lines.append(ExternalText.phrase("ui_demon_presentation.progress.5e9ee9edb79a", "说明待补充 · %d") % (3-int(c.get("eye_purchases",0))%4))
   "life_demon","life_spell":lines.append(ExternalText.phrase("ui_demon_presentation.progress.5e9ee9edb79a", "说明待补充 · %d") % (0 if int(c.get("life_round",-1))==round_number and int(c.get("life_used",0))>0 else 1))
   "demons_eat","escape":lines.append(ExternalText.phrase("ui_demon_presentation.progress.c4842051c19c", "说明待补充")+(ExternalText.phrase("ui_demon_presentation.progress.6798e9bb07fd", "说明待补充") if int(c.get("demon_native_round",-1))==round_number else ExternalText.phrase("ui_demon_presentation.progress.d8c5f8fa85f5", "说明待补充"))+ExternalText.phrase("ui_demon_presentation.progress.2480aceb6197", "说明待补充 · %d") % int(e.cost))
 if c.get("gold_route","")=="恶魔":lines.append(ExternalText.phrase("ui_demon_presentation.progress.3f1b9a6ede98", "说明待补充")+(ExternalText.phrase("ui_demon_presentation.progress.6798e9bb07fd", "说明待补充") if int(c.get("demon_gold_round",-1))==round_number else ExternalText.phrase("ui_demon_presentation.progress.d8c5f8fa85f5", "说明待补充"))+ExternalText.phrase("ui_demon_presentation.progress.da20a7681a55", "说明待补充"))
 if p.has("fodder_windows"):
  var windows=[]
  for w in p.fodder_windows:windows.append(ExternalText.phrase("ui_demon_presentation.progress.d9ba59869acc", "说明待补充 · %d / %d") % [int(w.remaining),int(w.amount)])
  if not windows.is_empty() or int(p.get("fodder_overflow",0))>0:lines.append(ExternalText.phrase("ui_demon_presentation.progress.2205dd252637", "说明待补充")+"、".join(windows)+ExternalText.phrase("ui_demon_presentation.progress.db46287288ab", "说明待补充 · %d") % int(p.get("fodder_overflow",0)))
 return "\n".join(lines)
static func body(d: Dictionary,c: Dictionary,p: Dictionary,round_number: int,rich: bool=false) -> String:
 var text=str(d.get("text",""))
 for e in d.get("effects",[]):
  if e.get("op","")=="perfect":text=ExternalText.phrase("demon_presentation.9d1ebfe663a6", "说明待补充")+preload("res://ui/spell_presentation.gd").stats(d,e,p,rich)+ExternalText.phrase("ui_demon_presentation.body.3c95fa4e7a78", "说明待补充")
 return text+"\n"+progress(d,c,p,round_number)
