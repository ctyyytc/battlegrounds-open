extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const A=preload("res://domain/rules/spell_attributes.gd")
static func number(base: int,extra: int,rich: bool) -> String:
 if extra==0:return "+"+str(base)
 return "+%d(%s%s)" % [base+extra,"[color=#ffffff]%d[/color]" % base if rich else str(base),"[color=#7ee58d]+%d[/color]" % extra if rich else "+"+str(extra)]
static func gains(d: Dictionary,e: Dictionary,p: Dictionary,rich: bool) -> String:
 var b=A.base(e);var extra=A.bonus(d,e,p)
 return number(b.x,extra.x,rich)+ExternalText.phrase("ui_naga_presentation.gains.ab962f82e917", "说明待补充")+number(b.y,extra.y,rich)+ExternalText.phrase("ui_naga_presentation.gains.2ae654064e55", "说明待补充")
static func body(d: Dictionary,c: Dictionary,p: Dictionary,rich: bool=false) -> String:
 var op=str(d.effects[0].get("op","")) if not d.effects.is_empty() else ""
 var scale=1+int(floor(float(p.get("spell_count",0))/3.0))
 var n=3-int(p.get("spell_count",0))%3
 var m=2 if d.get("golden",false) else 1
 match op:
  "chef":
   if c.get("recruiter_neutral_coin",false):return ExternalText.phrase("naga_presentation.00f249bed105", "说明待补充")
  "craft":
   var base=d.get("base_id","")
   if base=="BG31_920":return ExternalText.phrase("naga_presentation.0e5d8c33dbe7", "说明待补充 · %d / %d") % [m,int(c.get("strategic_tier",1))]
   if base=="BG31_924":return ExternalText.phrase("naga_presentation.7e494e2b9318", "说明待补充 · %s / %s / %d") % [number(m,m*(scale-1),rich),number(m,m*(scale-1),rich),n]
  "shatter":return ExternalText.phrase("naga_presentation.ec1f12263a75", "说明待补充 · %s / %s / %d") % [number(m,m*(scale-1),rich),number(m,m*(scale-1),rich),n]
  "rider":return ExternalText.phrase("naga_presentation.133ec83408c7", "说明待补充 · %s / %s / %d") % [number(2*m,2*m*(scale-1),rich),number(m,m*(scale-1),rich),n]
  "bruiser":return ExternalText.phrase("naga_presentation.5b9006d3f6d1", "说明待补充 · %d / %d / %d / %d") % [2*m,m,2*m*int(p.get("tavern_spell_count",0)),m*int(p.get("tavern_spell_count",0))]
  "shaker":return str(d.text)+(ExternalText.phrase("ui_naga_presentation.body.c60ba46cbebe", "\n说明待补充") if int(c.get("shaker_round",0))==int(p.get("presentation_round",-1)) else ExternalText.phrase("ui_naga_presentation.body.35db9fd7b9e3", "\n说明待补充"))
  "strategic":return ExternalText.phrase("ui_naga_presentation.body.f9659c3b3d5a", "说明待补充 · %d / %d") % [int(d.effects[0].amount),int(c.get("strategic_tier",1))]
  "craft_buff":
   var e=d.effects[0];var factor=scale if e.get("scaling",false) else 1
   if e.get("scaling",false):return ExternalText.phrase("naga_presentation.8d31f638db2e", "说明待补充 · %s / %s / %d") % [number(int(e.attack),int(e.attack)*(factor-1),rich),number(int(e.health),int(e.health)*(factor-1),rich),n]
  "target_buff","board_spell","tide","queen","nature":
   var gains=gains(d,d.effects[0],p,rich)
   var prefix={"target_buff":ExternalText.phrase("ui_naga_presentation.body.60bb67facf9e", "说明待补充"),"board_spell":ExternalText.phrase("ui_naga_presentation.body.685f1f483a55", "说明待补充"),"tide":ExternalText.phrase("ui_naga_presentation.body.60bb67facf9e", "说明待补充"),"queen":ExternalText.phrase("ui_naga_presentation.body.685f1f483a55", "说明待补充"),"nature":ExternalText.phrase("naga_presentation.76fbe68311a6", "说明待补充")}[op]
   return prefix+gains+(ExternalText.phrase("ui_naga_presentation.body.5637a054a1ec", "说明待补充") if d.effects[0].get("keyword","")=="TAUNT" else "")+"。"+(ExternalText.phrase("ui_naga_presentation.body.adbfc7d23573", "说明待补充") if int(d.effects[0].get("repeat",1))==2 else "")+(ExternalText.phrase("naga_presentation.ab64869dedfd", "说明待补充") if op=="tide" else "")+(ExternalText.phrase("naga_presentation.716d558ef8ad", "说明待补充") if op=="queen" else "")
 return str(d.get("text",""))
static func item(d: Dictionary,c: Dictionary,p: Dictionary,round_number: int) -> String:
 var text=str(d.text)
 for e in d.effects:
  match str(e.get("op","")):
   "sand","mortar","rune","wand","spellbook":return text+ExternalText.phrase("ui_naga_presentation.item.5098fec04d9d", "说明待补充 · %d / %s") % [int(e.threshold)-int(c.get("progress",0)),ExternalText.phrase("ui_naga_presentation.item.6b2abf981966", "说明待补充") if e.op=="spellbook" else ExternalText.phrase("ui_naga_presentation.item.e97e2d9cfb73", "说明待补充") if e.op=="sand" else ExternalText.phrase("ui_naga_presentation.item.f9b8399e9afc", "说明待补充") if e.op=="wand" else ExternalText.phrase("ui_naga_presentation.item.d7567c5bc296", "说明待补充")]
   "forest":return ExternalText.phrase("naga_presentation.2b47ef7824cf", "说明待补充 · %d / %d / %d") % [1+int(floor(float(c.get("forest_uses",0))/6.0)),1+int(floor(float(c.get("forest_uses",0))/6.0)),6-int(c.get("forest_uses",0))%6]
   "crown":return ExternalText.phrase("naga_presentation.424923e00384", "说明待补充") if int(c.get("crown_casts",0))>=14 else ExternalText.phrase("naga_presentation.acec5310ffc0", "说明待补充 · %d") % (14-int(c.get("crown_casts",0)))
   "sushi":return ExternalText.phrase("naga_presentation.813a832ec430", "说明待补充 · %d") % (2-int(c.get("sushi_uses",0)) if int(c.get("sushi_round",0))==round_number else 2)
   "shakers":return ExternalText.phrase("naga_presentation.2a6abd0091b1", "说明待补充 · %d / %d / %d") % [3*(1+int(c.get("shaker_casts",0))),3*(1+int(c.get("shaker_casts",0))),3*int(c.get("shaker_casts",0))]
 return text
