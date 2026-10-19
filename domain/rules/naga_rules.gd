extends RefCounted
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const U=preload("res://domain/rules/undead_rules.gd")
const Attributes=preload("res://domain/rules/spell_attributes.gd")
const RANDOM_CRAFTS=["BG23_000t","BG31_924t","BG23_004t","BG23_007t","BG33_319t","BG23_008t","BG31_920t","BG32_835t"]
const CONJURER_EXCLUDED_SPELLS=["BG33_899","EBG_Spell_032","EBG_Spell_037","EBG_Spell_038","BG28_849","BG28_604"]
const FROST_EXCLUDED_SPELLS=["BG28_604"]
const OPS=["craft","tier_growth","shaker","shatter","discount","rider","whisper","recruiter","bruiser","conjurer","tidal","target_health","craft_buff","wave","strategic","strength","frost","board_spell","target_buff","armor","chef","random_craft","tide","queen","choice","seedling","nature","rider_portrait","sand","sushi","spellbook","forest","juggler_portrait","shakers","mortar","crown","ribbon","shatter_portrait","rune","wand","label","rider_health","target_trinket"]
static func supports(_d: Dictionary,e: Dictionary) -> bool:
 return e.get("handler","")=="round7" and e.get("op","") in OPS
static func has_item(engine,p: Dictionary,op: String) -> bool:
 return p.trinkets.any(func(item):return engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")==op))
static func types(engine,c: Dictionary) -> Array:
 var actual=engine.card_types(c)
 return engine.state.enabled_tribes.duplicate() if "全部种族" in actual else actual.filter(func(t):return t in engine.state.enabled_tribes)
static func recruit_entered(engine,p: Dictionary,c: Dictionary) -> void:
 if U.is_combat(engine) or engine.state.get("phase","")!="recruit":return
 var index=engine.find_index(p.board,int(c.get("instance_id",-1)))
 if index<0 or p.board[index].def_id!=c.get("def_id",""):return
 engine.run_effects(p,c,"spellcraft")
static func generated(engine,p: Dictionary,card: Dictionary) -> void:
 if not engine.content.get_def(card.def_id).get("is_spellcraft",false):return
 if not card.has("spellcraft_expires_round"):
  card["spellcraft_generated_phase"]="combat" if U.is_combat(engine) or engine.state.phase=="combat" else "recruit"
  card["spellcraft_expires_round"]=int(engine.state.round)+(1 if card.spellcraft_generated_phase=="combat" else 0)
static func expire(engine,p: Dictionary) -> void:
 for zone in ["hand","pending_rewards"]:
  var keep=[]
  for c in p[zone]:
   if engine.content.get_def(c.def_id).get("is_spellcraft",false) and int(c.get("spellcraft_expires_round",c.get("spellcraft_round",engine.state.round)))<=int(engine.state.round):
    engine.emit("SpellcraftDiscarded",int(p.id),{"instance_id":c.instance_id,"zone":zone,"expires_round":c.get("spellcraft_expires_round",engine.state.round)})
   else:keep.append(c)
  p[zone]=keep
static func scale(p: Dictionary) -> int:
 return 1+int(floor(float(p.spell_count)/3.0))
static func power_cost(engine,p: Dictionary,d: Dictionary) -> int:
 if d.kind=="minion":
  if engine.has_power(p,"TB_BaconShop_HP_014"):return 2
  if engine.Pirates.has_item(engine,p,"first_free") and ("海盗" in d.card_types or "全部种族" in d.card_types) and int(p.get("pirate_buy_round",0))!=int(engine.state.round):return 0
  return 2 if engine.R135.has(engine,p,"BG27_Reward_811") else 3
 if engine.has_handler(p,"tae") and int(p.get("tavern_bought",0))%3==2:return 0
 return maxi(0,int(d.get("cost",0))-int(p.get("next_spell_discount",0))-(1 if d.get("is_tavern_spell",false) and engine.R135.has(engine,p,"BG28_Reward_500") else 0))
static func aura(engine,p: Dictionary) -> Vector2i:
 var value=Vector2i.ZERO
 for item in p.trinkets:
  if engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")=="forest"):value+=Vector2i.ONE*(1+int(floor(float(item.get("forest_uses",0))/6.0)))
  if engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")=="crown") and int(item.get("crown_casts",0))>=14:value+=Vector2i(4,4)
 return value
static func derived(d: Dictionary,p: Dictionary) -> Vector2i:
 var value=Vector2i.ZERO
 for e in d.effects:
  if e.get("op","")=="bruiser":value+=Vector2i(int(e.attack),int(e.health))*int(p.tavern_spell_count)
 return value
static func pick(engine,pool: Array) -> Variant:
 return null if pool.is_empty() else pool[RNG.next(engine.state.streams,"effects",pool.size())]
static func random_craft(engine,p: Dictionary,n: int,source: Dictionary={}) -> void:
 var pool=RANDOM_CRAFTS.duplicate()
 if source.get("id",source.get("def_id",""))=="BG32_MagicItem_931":
  var tiers={"BG23_000t":1,"BG31_924t":2,"BG23_004t":3,"BG23_007t":3,"BG33_319t":4,"BG23_008t":5,"BG31_920t":5,"BG32_835t":5}
  pool=pool.filter(func(id):return int(tiers[id])<=int(p.tier))
 for unused in n:
  var id=pick(engine,pool)
  if id!=null:engine.receive_card(p,engine.make_card(id,int(p.id)),source)
static func spell_pool(engine,p: Dictionary,health_only: bool=false,target: Dictionary={}) -> Array:
 var result=[]
 for id in engine.content.pool("spell",engine.state.enabled_tribes):
  var d=engine.content.get_def(id)
  if int(d.tier)>int(p.tier):continue
  if health_only and not health_gain(engine,d):continue
  if not target.is_empty() and not valid_target(engine,p,d,target):continue
  result.append(id)
 return result
static func health_gain(engine,d: Dictionary) -> bool:
 for e in d.effects:
  if Attributes.eligible(d,e) and int(e.get("health",0))>0:return true
  if e.get("op","")=="choice":
   for id in e.ids:
    var branch=engine.content.get_def(id).duplicate(true);branch["is_tavern_spell"]=d.get("is_tavern_spell",false)
    if health_gain(engine,branch):return true
 return false
static func valid_target(engine,p: Dictionary,d: Dictionary,target: Dictionary) -> bool:
 if not engine.R136.valid_target(engine,p,d,target):return false
 if engine.R134.valid(engine,p,d,target)!="":return false
 if not engine.R13Items.valid_target(engine,p,d,target):return false
 if not engine.R13.valid_target(engine,p,d,target):return false
 var required=d.effects[0].get("target","none")
 if required in ["minion","friendly_minion","friendly_undead"]:
  if target.is_empty() or engine.content.get_def(target.get("def_id","")).get("kind","")!="minion":return false
  if required=="friendly_minion" and engine.find_index(U.board(engine,p),int(target.instance_id))<0:return false
  if required=="friendly_undead" and not U.valid_victim(engine,p,target):return false
 if not engine.Beasts.valid_target(engine,p,d,target):return false
 if not engine.Pirates.valid_target(engine,p,d,target) or not engine.Demons.valid_target(engine,p,d,target):return false
 if required in ["minion","friendly_minion","friendly_undead"] and d.effects[0].get("op","")=="chef":return not engine.card_types(target).is_empty() or recruiter_neutral_coin(engine,d,target)
 return true
static func recruiter_neutral_coin(engine,d: Dictionary,target: Dictionary) -> bool:
 if not d.get("recruiter_neutral_coin",false) or not U.is_combat(engine):return false
 var origin=engine.effect_source
 if engine.content.get_def(origin.get("def_id","")).get("base_id",origin.get("def_id",""))!="BG34_925" or not engine.card_types(target).is_empty():return false
 return int(target.get("owner",-1))==int(origin.get("owner",-2)) and U.board(engine,U.board_player(engine,int(origin.owner))).any(func(v):return int(v.instance_id)==int(target.instance_id))
static func conjurer_targets(engine,p: Dictionary,d: Dictionary,source: Dictionary) -> Array:
 var mode=d.effects[0].get("target","none")
 if mode=="none":return [{}]
 var candidates=U.board(engine,p).duplicate()
 if mode=="minion" and not U.is_combat(engine):candidates.append_array(p.shop)
 candidates=candidates.filter(func(v):return valid_target(engine,p,d,v))
 if not source.is_empty() and candidates.any(func(v):return int(v.instance_id)==int(source.get("instance_id",-1))):return [source]
 return candidates
static func conjurer_pool(engine,p: Dictionary,source: Dictionary) -> Array:
 return spell_pool(engine,p).filter(func(id):return id not in CONJURER_EXCLUDED_SPELLS and engine.content.get_def(id).get("is_tavern_spell",false) and not conjurer_targets(engine,p,engine.content.get_def(id),source).is_empty())
static func frost_pool(engine,p: Dictionary) -> Array:
 return spell_pool(engine,p,true).filter(func(id):return id not in FROST_EXCLUDED_SPELLS)
static func rune_candidates(engine,p: Dictionary,item: Dictionary) -> Array:
 var owned=p.trinkets.map(func(v):return v.id)
 return engine.content.pool("trinket",engine.state.enabled_tribes,false).filter(func(id):
  var d=engine.content.get_def(id)
  return d.size=="greater" and id not in owned and engine.R13Items.allowed(engine,p,d) and ("纳迦" in d.get("associated_pool_tribes",[]) or (d.get("bind_tribe",false) and d.get("associated_pool_tribes",[]).is_empty() and "纳迦" in engine.state.enabled_tribes)))
static func auto_cast(engine,p: Dictionary,id: String,target: Dictionary={},permanent: bool=false,conjurer: Dictionary={}) -> void:
 var d=engine.content.get_def(id).duplicate(true)
 if engine.Quilboar.choice(d):d["automatic"]=true
 if not conjurer.is_empty():d["conjurer_instance"]=int(conjurer.instance_id)
 if id=="BG28_518" and U.is_combat(engine) and not target.is_empty() and engine.card_types(target).is_empty():
  d["recruiter_neutral_coin"]=true
  d.recruiter_neutral_coin=recruiter_neutral_coin(engine,d,target)
 if not valid_target(engine,p,d,target):return
 if permanent:d["force_permanent"]=true
 if U.is_combat(engine):d["automatic"]=true
 engine.cast(p,d,target)
static func amount_value(engine,p: Dictionary,e: Dictionary) -> Vector2i:
 return Attributes.value(engine.current_spell,e,p)
static func buff(engine,c: Dictionary,v: Vector2i,permanent: bool=false,duration: String="permanent") -> void:
 if c.is_empty():return
 if U.is_combat(engine):U.local_buff(engine,c,v.x,v.y,permanent)
 else:engine.buff(c,v.x,v.y,duration)
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
 if e.get("handler","")!="round7":return false
 var amount=int(e.get("amount",1));var op=str(e.op);var target=engine.effect_target
 var source=engine.effect_source
 var permanent=engine.current_spell.get("force_permanent",false)
 match op:
  "craft":
   var card=engine.make_card(e.id,int(p.id));card["spellcraft_source"]=c.instance_id
   card["permanent_spellcraft"]=engine.Gifts.count(engine,c,4)>0 or (engine.content.get_def(c.def_id).get("base_id","")=="BG31_924" and has_item(engine,p,"juggler_portrait"))
   card["spellcraft_source_snapshot"]={"instance_id":c.instance_id,"def_id":c.def_id,"permanent":card.permanent_spellcraft}
   if engine.content.get_def(c.def_id).get("base_id","")=="BG31_920":card["strategic_tier"]=int(c.get("strategic_tier",1))
   engine.receive_card(p,card,source)
  "tier_growth":c["strategic_tier"]=mini(6,int(c.get("strategic_tier",1))+1)
  "discount":p["next_spell_discount"]=int(p.get("next_spell_discount",0))+amount
  "craft_buff","wave":
   var value=Vector2i(int(e.attack),int(e.health))*(1+int(floor(float(maxi(0,int(p.spell_count)-1))/3.0)) if e.get("scaling",false) else 1)
   var duration="permanent" if op=="wave" or engine.current_spell.get("permanent_spellcraft",false) else "next_turn"
   buff(engine,c,value,engine.current_spell.get("permanent_spellcraft",false),duration)
   if e.get("keyword","")!="":engine.add_keyword(c,e.keyword,duration)
   if op=="wave" and U.tribe(engine,c,"纳迦"):engine.add_keyword(c,"WINDFURY","next_turn")
  "strategic":
   U.random_cards(engine,p,{"tier":int(engine.current_spell.get("strategic_tier",1)),"tribe":"纳迦","amount":amount},engine.current_spell.get("spellcraft_source_snapshot",{}))
  "strength":p["spell_bonus_attack"]=int(p.get("spell_bonus_attack",0))+amount;p["spell_bonus_health"]=int(p.get("spell_bonus_health",0))+amount
  "frost":
   var pool=frost_pool(engine,p)
   for unused in amount:
    var id=pick(engine,pool)
    if id!=null:engine.receive_card(p,engine.make_card(id,int(p.id)),source)
  "target_buff","board_spell","queen","tide","nature":
   var value=amount_value(engine,p,e);var targets=[c]
   if op in ["board_spell","queen"]:targets=U.board(engine,p)
   if op=="nature":
    var selected=types(engine,c)
    targets=U.board(engine,p).filter(func(v):return types(engine,v).any(func(t):return t in selected))
    if engine.Fish.has(engine,p,"blessing"):targets.append_array(engine.Fish.hand(engine,p).filter(func(v):return types(engine,v).any(func(t):return t in selected)))
   var repetitions=int(e.get("repeat",1))+(int(e.get("repeat",1)) if op=="tide" and U.tribe(engine,c,"纳迦") else 0)
   for unused in repetitions:
    for v in targets:
     buff(engine,v,value,permanent)
     if op=="queen" and U.tribe(engine,v,"纳迦"):buff(engine,v,value,permanent)
     if e.get("keyword","")!="":engine.add_keyword(v,e.keyword)
  "armor":p.armor=5
  "chef":
   if engine.current_spell.get("recruiter_neutral_coin",false) and engine.card_types(c).is_empty():
    engine.receive_card(p,engine.make_card("BG28_810",int(p.id)),source)
    return true
	
   if engine.Shop132.outside(engine,c):
    var pool=engine.Shop132.fallback_pool(engine,p)
    var id=pick(engine,pool)
    if id!=null:engine.receive_card(p,engine.make_card(id,int(p.id)),source)
    return true
   var tribe=pick(engine,types(engine,c))
   if tribe!=null:
    var pool=engine.generation_candidates(p,{"tribe":tribe},engine.current_spell)
    var base=engine.content.get_def(c.def_id).get("base_id",c.def_id)
    pool=pool.filter(func(id):return engine.content.get_def(id).get("base_id",id)!=base)
    engine.emit("ChefTribeSelected",int(p.id),{"tribe":tribe,"candidate_count":pool.size()})
    var id=pick(engine,pool)
    if id!=null:engine.receive_card(p,engine.make_card(id,int(p.id)),source)
  "random_craft":random_craft(engine,p,amount,source)
  "choice":
   var options=[]
   for id in e.ids:options.append(engine.make_card(id,int(p.id)))
   if engine.resolution_phase=="turn_end" or engine.current_spell.get("automatic",false):
    var d=engine.content.get_def(pick(engine,options).def_id)
    for spec in d.effects:engine.effect(p,spec,c,engine.current_spell)
   else:engine.enqueue_choice(p,{"kind":"choose_one","options":options,"target_instance":c.instance_id,"spell_context":engine.current_spell.duplicate(true),"source":source.duplicate(true),"resolution_phase":engine.resolution_phase})
  "seedling":
   var pool=engine.discovery_candidates(p,{"tier":1},engine.current_spell)
   if engine.current_spell.get("automatic",false):
    var id=pick(engine,pool)
    if id!=null:engine.receive_card(p,engine.make_card(id,int(p.id)),source)
   else:engine.resolve_discovery(p,pool,"seedling",1,source)
  "rider":
   var value=Vector2i(int(e.attack),int(e.health))*scale(p)
   for v in U.board(engine,p):
    if U.tribe(engine,v,"纳迦"):
     buff(engine,v,value,has_item(engine,p,"rider_health"))
  "whisper","recruiter":
   var board=U.board(engine,p);var i=board.find(c);var neighbors=[]
   for j in ([i-1,i+1] if op=="whisper" else [i+1]):
    if i>=0 and j>=0 and j<board.size():neighbors.append(board[j])
   for v in neighbors:
    for unused in amount:auto_cast(engine,p,"BG28_845" if op=="whisper" else "BG28_518",v)
  "conjurer":
   for unused in amount:
    var id=pick(engine,conjurer_pool(engine,p,c))
    if id!=null:
     var selected=pick(engine,conjurer_targets(engine,p,engine.content.get_def(id),c))
     auto_cast(engine,p,id,selected,false,c)
    else:
     engine.emit("AutomaticSpellUnavailable",int(p.id),{"source_instance":c.instance_id,"remaining":amount-unused});break
  "sand","mortar","rune","wand","spellbook":
   if op=="sand" and (engine.content.get_def(c.get("def_id","")).get("kind","")!=e.get("count_card_kind","minion") or not U.tribe(engine,c,e.get("count_actual_tribe","纳迦"))):return true
   if op=="wand" and c.is_empty():return true
   var item=source;item["progress"]=int(item.get("progress",0))+int(e.get("spent",1))
   while int(item.progress)>=int(e.threshold):
    item.progress-=int(e.threshold)
    match op:
     "sand":random_craft(engine,p,1,item)
     "mortar":U.random_cards(engine,p,{"tribe":"纳迦"},item)
     "wand":engine.gain_coins(p,1)
     "spellbook":auto_cast(engine,p,"BG28_168")
     "rune":
      var pool=rune_candidates(engine,p,item)
      var id=pick(engine,pool)
      if id!=null:
       var slot=item.get("slot_size",item.size)
       engine.R13Items.install(engine,p,id,str(slot),"纳迦",int(item.instance_id))
       engine.emit("TrinketReplaced",int(p.id),{"id":id,"size":"greater"})
      else:item.progress=int(e.threshold);engine.emit("EmptyRunePool",int(p.id))
      break
  "target_trinket":
   if not c.is_empty():buff(engine,c,Vector2i(int(e.attack),int(e.health)))
  "ribbon":
   for v in U.board(engine,p):buff(engine,v,Vector2i(2,2) if U.is_combat(engine) else Vector2i.ONE,true)
  "shakers":
   var board=U.board(engine,p)
   if not board.is_empty():buff(engine,board[0],Vector2i(int(e.attack),int(e.health))*(1+int(source.get("shaker_casts",0))))
  "rider_portrait":
   for v in U.board(engine,p):
    if U.tribe(engine,v,"纳迦"):
     if not v.has("attached_effects"):v["attached_effects"]=[]
     v.attached_effects.append({"handler":"round7","op":"random_craft","trigger":"deathrattle","amount":1})
  "label":
   var pool=U.board(engine,p).filter(func(v):return U.tribe(engine,v,"纳迦"))
   if not pool.is_empty():
    for v in ([pool[0]] if pool.size()==1 else [pool[0],pool.back()]):buff(engine,v,Vector2i(int(v.attack),int(v.max_health)))
  "shaker","shatter","bruiser","tidal","target_health","sushi","forest","juggler_portrait","crown","shatter_portrait","rider_health":pass
  _:return false
 return true
static func hand_used(engine,p: Dictionary,card: Dictionary) -> void:
 var d=engine.content.get_def(card.def_id)
 if d.kind=="spell":
  p["hand_spells_used"]=int(p.get("hand_spells_used",0))+1
  if d.get("is_tavern_spell",false):
   p["tavern_used"]=int(p.get("tavern_used",0))+1
   for item in p.trinkets:
    if engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")=="forest"):item["forest_uses"]=int(item.get("forest_uses",0))+1
 if d.kind=="minion" and U.tribe(engine,card,"纳迦"):
  for c in U.board(engine,p).duplicate():
   for spec in engine.Triggers.effects(engine,c):
    if spec.get("op","")=="shatter":
     var value=Vector2i.ONE*int(spec.amount)*scale(p)
     buff(engine,c,value)
     if has_item(engine,p,"shatter_portrait"):
      var board=U.board(engine,p);var i=board.find(c)
      for j in [i-1]:
       if j>=0 and j<board.size():buff(engine,board[j],value)
 engine.trinket_effects(p,"card_used",card)
 if d.kind=="minion" and engine.has_handler(p,"chen") and U.tribe(engine,card,"元素"):
  p["chen_plays"]=int(p.get("chen_plays",0))+1
  if int(p.chen_plays)%3==0:p.upgrade_cost=maxi(0,int(p.upgrade_cost)-3)
static func spell_resolved(engine,p: Dictionary,spell: Dictionary,target: Dictionary) -> void:
 for item in p.trinkets:
  if engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")=="crown"):item["crown_casts"]=mini(14,int(item.get("crown_casts",0))+1)
  if engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")=="shakers"):item["shaker_casts"]=int(item.get("shaker_casts",0))+1
 var board=U.board(engine,p)
 for c in board.duplicate():
  for spec in engine.Triggers.effects(engine,c):
   match str(spec.get("op","")):
    "target_health":
     if not target.is_empty() and int(c.instance_id)==int(target.instance_id):buff(engine,c,Vector2i(0,int(spec.health)))
    "tidal":
     if not target.is_empty() and U.tribe(engine,target,"纳迦"):
      for v in board:buff(engine,v,Vector2i(int(spec.attack),int(spec.health)))
    "bruiser":
     if spell.get("is_tavern_spell",false) and U.is_combat(engine):
      var value=Vector2i(int(spec.attack),int(spec.health));buff(engine,c,value);c.derived_attack+=value.x;c.derived_health+=value.y
 
 var owned=board if U.is_combat(engine) else board+p.shop
 if spell.get("is_spellcraft",false) and not target.is_empty() and owned.any(func(v):return int(v.instance_id)==int(target.instance_id)):
  for spec in engine.Triggers.effects(engine,target):
   if spec.get("op","")=="shaker" and int(target.get("shaker_round",0))!=int(engine.state.round):
    target["shaker_round"]=int(engine.state.round)
    for unused in int(spec.amount):
     var copy=engine.make_card(spell.id,int(p.id))
     for key in ["permanent_spellcraft","spellcraft_source","spellcraft_source_snapshot","spellcraft_generated_phase","spellcraft_expires_round","strategic_tier"]:
      if spell.has(key):copy[key]=spell[key].duplicate(true) if spell[key] is Dictionary else spell[key]
     engine.receive_card(p,copy,target)
static func spent(engine,p: Dictionary,n: int) -> void:
 if n<=0:return
 for item in p.trinkets.duplicate():
  for raw in engine.content.get_def(item.id).effects:
   if raw.get("op","")=="spellbook":
    var e=raw.duplicate(true);e["spent"]=n;engine.effect(p,e,{},item)
static func extra(engine,p: Dictionary,spell: Dictionary) -> int:
 if not spell.get("is_spellcraft",false):return 0
 var result=0
 for item in p.trinkets:
  if engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")=="sushi"):
   if int(item.get("sushi_round",0))!=int(engine.state.round):item["sushi_round"]=int(engine.state.round);item["sushi_uses"]=0
   if int(item.get("sushi_uses",0))<2:item.sushi_uses+=1;result+=1
 return result
