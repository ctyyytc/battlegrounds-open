extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
static func names_map() -> Dictionary:
 return {"DIVINE_SHIELD":ExternalText.ui("ui_card_presentation.<module>.364ecf3c3959", "圣盾"),"WINDFURY":ExternalText.ui("ui_card_presentation.<module>.bc1cb4e341a4", "风怒"),"REBORN":ExternalText.ui("ui_card_presentation.<module>.b5a9c20568b6", "复生"),"DEATHRATTLE":ExternalText.ui("ui_card_presentation.<module>.aa4caf1c9b7c", "亡语"),"TAUNT":ExternalText.ui("ui_card_presentation.<module>.0238d1e3da2c", "嘲讽"),"VENOMOUS":ExternalText.ui("ui_card_presentation.<module>.7d83e2137b93", "烈毒"),"POISONOUS":ExternalText.ui("ui_card_presentation.<module>.5fd90d5a7cd9", "剧毒"),"STEALTH":ExternalText.ui("ui_card_presentation.<module>.5aa6ed6e8167", "潜行")}

static func number(value: int) -> String:
 if value>-1000 and value<1000: return str(value)
 var magnitude=abs(value)
 var divisor=1000
 var suffix="K"
 if magnitude>=1000000000: divisor=1000000000; suffix="B"
 elif magnitude>=1000000: divisor=1000000; suffix="M"
 @warning_ignore("integer_division")
 var whole=magnitude/divisor
 @warning_ignore("integer_division")
 var tenth=(magnitude%divisor)/(divisor/10)
 return ("-" if value<0 else "")+str(whole)+"."+str(tenth)+suffix
static func effective(card: Dictionary,engine) -> Array:
 var recruit=engine.state.phase=="recruit" and engine.combat_context.is_empty()
 var keys=(engine.keywords(card) if recruit else card.get("keywords",engine.keywords(card))).duplicate()
 for pair in [["shield","DIVINE_SHIELD"],["venom","VENOMOUS"]]:
  if not recruit and card.has(pair[0]):
   keys.erase(pair[1])
   if card[pair[0]]: keys.append(pair[1])
 if engine.Triggers.has_deathrattle(engine,card) and "DEATHRATTLE" not in keys: keys.append("DEATHRATTLE")
 return keys
static func grave_warning(card: Dictionary,engine,zone: String) -> bool:
 return zone=="hand" and int(card.get("grave_round",-1))==int(engine.state.round) and not engine.content.get_def(card.def_id).get("golden",false)
static func turtle_sale_coins(card: Dictionary,engine,zone: String) -> int:
 # Read the same condition and sell effect as settlement; visual queries are pure.
 if zone!="board" or engine.state.get("phase","")!="recruit" or int(card.get("owner",-1))!=0:return 0
 var p=engine.state.players[0]
 if not p.alive or not p.get("last_combat_lost",false):return 0
 var d=engine.content.get_def(card.def_id)
 if str(d.get("base_id",d.id))!="BG24_018":return 0
 if not p.board.any(func(c):return int(c.instance_id)==int(card.instance_id)):return 0
 var extra=0
 for effect in engine.Triggers.effects(engine,card):
  if effect.get("trigger","")=="sell" and effect.get("handler","")=="round6" and effect.get("op","")=="sell_coins":extra+=int(effect.get("amount",1))-1
 return 1+extra if extra>0 else 0
static func status(card: Dictionary,engine) -> String:
 var active=[]
 if card.has("temporary_gold"):active.append(ExternalText.phrase("card_presentation.109944448a1f", "说明待补充 · %d") % int(card.temporary_gold.expires_round))
 if engine.CardLock.locked(engine,engine.state.players[int(card.owner)],card):active.append(engine.CardLock.description(engine,engine.state.players[int(card.owner)],card))
 var keys=effective(card,engine)
 var names=names_map()
 for k in names:
  if k in keys: active.append(ExternalText.term(str(k),names[k]))
 var used=[]
 if card.has("shield") and not card.shield and "DIVINE_SHIELD" in card.get("keywords",[]): used.append(ExternalText.ui("ui_card_presentation.status.da05cba64644", "圣盾已破除"))
 if card.has("venom") and not card.venom and "VENOMOUS" in card.get("keywords",[]): used.append(ExternalText.ui("ui_card_presentation.status.da70c9bfe4cc", "烈毒已消耗"))
 if card.get("reborn_consumed",false) and "REBORN" not in keys: used.append(ExternalText.ui("ui_card_presentation.status.15dce5b9cd68", "复生已消耗"))
 return ExternalText.ui("ui_card_presentation.status.ce5ac1ebdb86", "当前有效：")+("、".join(active) if not active.is_empty() else ExternalText.ui("ui_card_presentation.status.9ef65609bcf8", "无关键词"))+(ExternalText.ui("ui_card_presentation.status.03580d2892f2", "\n已耗状态：")+"、".join(used) if not used.is_empty() else "")
