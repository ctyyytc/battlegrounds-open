extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const A=preload("res://domain/rules/spell_attributes.gd")
static func number(base: int,spell: int,gem: int,rich: bool) -> String:
 var sum=base+spell+gem
 if spell==0 and gem==0:return "+"+str(sum)
 var parts="[color=#ffffff]%d[/color]" % base if rich else str(base)
 if spell!=0:parts+=("[color=#7ee58d]%+d[/color]" % spell if rich else "%+d" % spell)
 if gem!=0:parts+=("[color=#f2c15b]%+d[/color]" % gem if rich else "%+d" % gem)
 return "+%d(%s)" % [sum,parts]
static func gains(d: Dictionary,e: Dictionary,p: Dictionary,rich: bool,gem: bool=false) -> String:
 var b=A.base(e);var a=A.bonus(d,e,p)
 var g=Vector2i(int(p.get("presentation_gem_attack",p.get("gem_attack",0))),int(p.get("presentation_gem_health",p.get("gem_health",0)))) if gem else Vector2i.ZERO
 return number(b.x,a.x,g.x,rich)+ExternalText.phrase("ui_quilboar_presentation.gains.ab962f82e917", "说明待补充")+number(b.y,a.y,g.y,rich)+ExternalText.phrase("ui_quilboar_presentation.gains.2ae654064e55", "说明待补充")
static func body(d: Dictionary,c: Dictionary,p: Dictionary,rich: bool=false) -> String:
 var text=str(d.get("text",""))
 if d.effects.is_empty():return text
 var e=d.effects[0];var op=str(e.get("op",""))
 match op:
  "gem":
   if c.has("gem_value"):return ExternalText.phrase("quilboar_presentation.16990bc8947f", "说明待补充 · %d / %d") % [c.gem_value.attack,c.gem_value.health]
   return ExternalText.phrase("ui_quilboar_presentation.body.60bb67facf9e", "说明待补充")+gains(d,e,p,rich,true)+"。"
  "barrage":return ExternalText.phrase("quilboar_presentation.c5b853f977c4", "说明待补充")+gains(d,e,p,rich,true)+ExternalText.phrase("ui_quilboar_presentation.body.23a08ff3a050", "说明待补充")
  "target_buff","board_buff","random_buff","time_delay","bread":
   var gain=gains(d,e,p,rich)
   var prefix={"target_buff":ExternalText.phrase("ui_quilboar_presentation.body.60bb67facf9e", "说明待补充"),"board_buff":ExternalText.phrase("ui_quilboar_presentation.body.685f1f483a55", "说明待补充"),"random_buff":ExternalText.phrase("quilboar_presentation.708238ecef04", "说明待补充"),"time_delay":ExternalText.phrase("quilboar_presentation.fdf94b5398f0", "说明待补充"),"bread":ExternalText.phrase("ui_quilboar_presentation.body.60bb67facf9e", "说明待补充")}[op]
   return prefix+gain+"。"+(ExternalText.phrase("ui_quilboar_presentation.body.adbfc7d23573", "说明待补充") if int(e.get("repeat",1))==2 else "")+(ExternalText.phrase("quilboar_presentation.f8cb97858158", "说明待补充")+gains(d,{"handler":"round8","op":"bread","attack":4,"health":6},p,rich)+"。" if op=="bread" else "")
  "quota":
   var remaining=int(c.get("choice_quota",e.amount)) if int(c.get("choice_quota_round",-1))==int(p.get("presentation_round",-2)) else int(e.amount)
   return ExternalText.phrase("quilboar_presentation.8f786b854b29", "说明待补充 · %d / %d") % [int(e.amount),remaining]
  "fel":return text+ExternalText.phrase("ui_quilboar_presentation.body.18384b71b5f3", "说明待补充 · %d") % (int(e.threshold)-int(c.get("fel_progress",0)))
  "ink":return text+ExternalText.phrase("ui_quilboar_presentation.body.00f476e6331e", "说明待补充 · %d") % (int(e.threshold)-int(c.get("avenge_round8",0)))
  "earring":return text+ExternalText.phrase("ui_quilboar_presentation.body.957e2ff3448c", "说明待补充 · %d") % (int(e.threshold)-int(c.get("gem_progress",0)))
  "jar":return ExternalText.phrase("quilboar_presentation.0a3dfb75e8e7", "说明待补充 · %d") % (int(e.threshold)-int(c.get("combat_uses",0)))
  "choice":
   if d.get("id","")=="BG31_880":return ExternalText.phrase("quilboar_presentation.c611fd7c97b9", "说明待补充")+gains(d,{"handler":"round8","op":"target_buff","attack":3,"health":1},p,rich)+ExternalText.phrase("ui_quilboar_presentation.body.e452ff98ee7d", "说明待补充")+gains(d,{"handler":"round8","op":"target_buff","attack":1,"health":3},p,rich)+"。"
   if d.get("id","")=="BG31_881":return ExternalText.phrase("quilboar_presentation.e64aae102a8e", "说明待补充")+gains(d,{"handler":"round8","op":"board_buff","attack":2,"health":2},p,rich)+ExternalText.phrase("quilboar_presentation.b789ac718c3d", "说明待补充")
   if d.get("id","")=="BG31_886":return ExternalText.phrase("quilboar_presentation.c611fd7c97b9", "说明待补充")+gains(d,{"handler":"round8","op":"target_buff","attack":6,"health":6},p,rich)+ExternalText.phrase("quilboar_presentation.71c65f14410d", "说明待补充")+gains(d,{"handler":"round8","op":"board_buff","attack":2,"health":2},p,rich)+"。"
 var notes=[]
 if c.has("locked_until_round"):notes.append(ExternalText.phrase("ui_quilboar_presentation.body.ef4567b0b986", "说明待补充 · %d") % int(c.locked_until_round))
 if c.has("card_lock"):
  var lock=c.card_lock
  if int(lock.get("round",0))>int(p.get("presentation_round",0)):notes.append(ExternalText.phrase("ui_quilboar_presentation.body.5a1886c04742", "说明待补充 · %d") % int(lock.round))
  if int(lock.get("tier",0))>int(p.get("tier",0)):notes.append(ExternalText.phrase("ui_quilboar_presentation.body.cc8d880f9e06", "说明待补充 · %d") % int(lock.tier))
  if int(lock.get("debt",0))>0:notes.append(ExternalText.phrase("quilboar_presentation.e80935781a06", "说明待补充 · %d") % int(lock.debt))
 if c.get("double_choose",false):notes.append(ExternalText.phrase("quilboar_presentation.b94e2e2a7e0c", "说明待补充"))
 if not c.get("gem_contributions",[]).is_empty():
  var a=0;var h=0
  for v in c.gem_contributions:a+=int(v.attack);h+=int(v.health)
  notes.append(ExternalText.phrase("ui_quilboar_presentation.body.45bb55bd4f3e", "说明待补充 · %d / %d") % [a,h])
 return text+("\n"+" · ".join(notes) if not notes.is_empty() else "")
