extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const U=preload("res://domain/rules/undead_rules.gd")
const A=preload("res://domain/rules/spell_attributes.gd")
const BOUNTIES=["BG33_811","BG33_812","BG33_813","BG33_814","BG33_815"]
const HEROES=["hogg","eudora","hooktusk"]
const OPS=["neighbors_gold","discover_spell","lockbox","spell_bonus","next_coins","parrot","board_buff","spend_buff","ballad","cleave","bounty","extortion","give","privateer","spend_box","spend_bounty","gold_cards","discovered_buff","two_merge","wine","shard","pendant","first_free","hammer","shield","crowbar","deserter_portrait","pants","telescope","confidence","shop_growth","evolve","seafood","bounty_buff","left_buff","majority","coins","golden_buff","favor","touch","grifter","triple_reward"]
static func supports(d: Dictionary,e: Dictionary) -> bool:
 return (e.get("handler","")=="round9" and e.get("op","") in OPS) or (d.kind in ["hero","hero_power"] and e.get("handler","") in HEROES)
static func has_item(engine,p: Dictionary,op: String) -> bool:
 return p.trinkets.any(func(item):return engine.content.get_def(item.id).effects.any(func(e):return e.get("handler","")=="round9" and e.get("op","")==op))
static func pick(engine,pool: Array,stream: String="effects") -> Variant:
 return null if pool.is_empty() else pool[RNG.next(engine.state.streams,stream,pool.size())]
static func bounty_id(engine,p: Dictionary,stream: String="effects") -> String:
 var pool=BOUNTIES.filter(func(id):return engine.content.get_def(id).implemented and engine.content.eligible(engine.content.get_def(id),engine.state.enabled_tribes))
 return str(pick(engine,pool,stream)) if not pool.is_empty() else ""
static func bounties(engine,p: Dictionary,n: int,source: Dictionary={}) -> void:
 for unused in n:
  var id=bounty_id(engine,p)
  if id!="":engine.receive_card(p,engine.make_card(id,int(p.id)),source)
static func gold_pool(engine,p: Dictionary,spec: Dictionary,source: Dictionary={}) -> Array:
 var pool=[];var candidates=engine.generation_candidates(p,spec,source)
 if spec.get("route",false):
  candidates=[]
  for tier in range(1,5):candidates.append_array(engine.generation_candidates(p,{"tier":tier},source))
 for id in candidates:
  var d=engine.content.get_def(id)
  if spec.get("route",false) and int(d.tier)>4:continue
  if spec.get("typed",false) and engine.card_types({"def_id":id}).is_empty():continue
  if (spec.get("eudora",false) or spec.get("lockbox",false)) and d.get("base_id",id)=="BG32_236":continue
  var gold=id if d.get("golden",false) else str(d.get("golden_id",""))
  if gold!="" and engine.content.get_def(gold).get("implemented",false) and gold not in pool:pool.append(gold)
 return pool
static func gold_cards(engine,p: Dictionary,spec: Dictionary,source: Dictionary={}) -> void:
 var pool=gold_pool(engine,p,spec,source)
 for unused in int(spec.get("amount",1)):
  var id=pick(engine,pool)
  if id!=null:
   var card=engine.make_card(str(id),int(p.id))
   var source_base=engine.content.get_def(source.get("def_id",source.get("id",""))).get("base_id","")
   if (source_base=="BG36_343" and not spec.get("route",false)) or (spec.has("triple_reward") and not spec.triple_reward):engine.qualify_gold(card,"explicit_no_reward:"+str(source_base),true)
   else:card["gold_reward_source"]="generated:"+str(source.get("def_id",source.get("id","")))
   engine.receive_card(p,card,engine.Acquisition.context(engine,source,"treasure") if spec.get("lockbox",false) or spec.get("eudora",false) else source)
static func box(p: Dictionary) -> Dictionary:
 for c in p.hand+p.pending_rewards:
  if c.def_id=="BG36_520t":return c
 return {}
static func advance_box(engine,p: Dictionary,n: int) -> void:
 var c=box(p)
 if c.is_empty():return
 c["box_remaining"]=maxi(0,int(c.get("box_remaining",5))-n)
 engine.emit("LockboxAdvanced",int(p.id),{"instance_id":c.instance_id,"remaining":c.box_remaining,"amount":n})
 if int(c.box_remaining)>0:return
 
 p.hand.erase(c);p.pending_rewards.erase(c)
 engine.emit("LockboxOpened",int(p.id),{"instance_id":c.instance_id})
 gold_cards(engine,p,{"typed":true,"amount":1,"lockbox":true,"triple_reward":true},c)
static func lockbox(engine,p: Dictionary,n: int=1,advance: int=1,source: Dictionary={}) -> void:
 for unused in n:
  if box(p).is_empty():
   var c=engine.make_card("BG36_520t",int(p.id));c["box_remaining"]=4 if has_item(engine,p,"deserter_portrait") else 5
   engine.receive_card(p,c,source)
  else:advance_box(engine,p,advance)
static func end(engine,p: Dictionary) -> void:
 advance_box(engine,p,engine.Triggers.times(engine,p,"turn_end"))
static func extra(engine,p: Dictionary,spell: Dictionary) -> int:
 if str(spell.get("id","")) not in BOUNTIES:return 0
 var total=1
 for c in U.board(engine,p):
  if c.has("health") and int(c.health)<=0:continue
  for e in engine.Triggers.effects(engine,c):
   if e.get("op","")=="privateer":total=maxi(total,int(e.total))
 return total-1
static func spent(engine,p: Dictionary,n: int) -> void:
 if n<=0:return
 p["coins_spent_round"]=int(p.get("coins_spent_round",0))+n
 for c in p.board.duplicate():
  for e in engine.Triggers.effects(engine,c):
   if e.get("handler","")!="round9" or e.get("trigger","")!="coins_spent":continue
   c["pirate_spent"]=int(c.get("pirate_spent",0))+n
   while int(c.pirate_spent)>=int(e.threshold):
    c.pirate_spent-=int(e.threshold)
    if e.op=="spend_box":lockbox(engine,p,int(e.repeat),1,c)
    elif e.op=="spend_bounty":bounties(engine,p,int(e.amount),c)
    else:buff_board(engine,p,e,c)
 engine.trinket_effects(p,"payment")
 engine.emit("CoinPaymentCompleted",int(p.id),{"amount":n})
static func obtained(engine,p: Dictionary,c: Dictionary) -> void:
 if not U.tribe(engine,c,"海盗"):return
 for source in U.board(engine,p).duplicate():
  for e in engine.Triggers.effects(engine,source):
   if e.get("op","")=="grifter":
    source["pirate_obtained"]=int(source.get("pirate_obtained",0))+1
    if int(source.pirate_obtained)>=int(e.threshold):source.pirate_obtained-=int(e.threshold);engine.increase_coin_cap(p,int(e.amount))
 engine.trinket_effects(p,"pirate_obtained",c)
static func played(engine,p: Dictionary,c: Dictionary) -> void:
 if not engine.content.get_def(c.def_id).get("golden",false):return
 p["golden_played"]=int(p.get("golden_played",0))+1
 engine.emit("GoldenMinionPlayed",int(p.id),{"instance_id":c.instance_id,"total":p.golden_played})
static func discovered(engine,p: Dictionary) -> void:
 engine.emit("DiscoveryCompleted",int(p.id))
 engine.trigger(p,"discover_complete",{})
static func balance(engine,p: Dictionary) -> void:
 if int(p.coins)<15:return
 for item in p.trinkets.duplicate():
  if engine.content.get_def(item.id).effects.any(func(e):return e.get("op","")=="shard") and not item.get("shard_used",false):
   item["shard_used"]=true;gold_cards(engine,p,{"tier":5,"amount":1},item)
static func growth(engine,p: Dictionary,c: Dictionary) -> void:
 if engine.content.get_def(c.def_id).kind!="minion":return
 var v=Vector2i(int(p.get("shop_growth_attack",0)),int(p.get("shop_growth_health",0)))
 for layer in p.get("shop_tribe_growth",[]):
  if engine.Naga.types(engine,c).any(func(t):return t in layer.tribes):v+=Vector2i(int(layer.attack),int(layer.health))
 if v!=Vector2i.ZERO:engine.buff(c,v.x,v.y,"permanent","round9_shop")
static func buff_board(engine,p: Dictionary,e: Dictionary,source: Dictionary={}) -> void:
 var pool=U.board(engine,p).filter(func(c):return (not e.has("tribe") or U.tribe(engine,c,e.tribe)) and (not e.get("exclude_source",false) or int(c.instance_id)!=int(source.get("instance_id",-1))))
 for unused in int(e.get("repeat",1)):
  var chosen=RNG.shuffle(pool,engine.state.streams,"effects").slice(0,int(e.amount)) if e.has("amount") else pool
  var v=A.value(engine.current_spell,e,p)
  for c in chosen:engine.buff(c,v.x,v.y)
static func majority(engine,p: Dictionary,source: Dictionary) -> void:
 var counts={};var highest=0;var best=[]
 for c in U.board(engine,p):
  for t in engine.Naga.types(engine,c):counts[t]=int(counts.get(t,0))+1
 for t in counts:
  if int(counts[t])>highest:highest=int(counts[t]);best=[t]
  elif int(counts[t])==highest:best.append(t)
 if best.is_empty():return
 U.random_cards(engine,p,{"tribe":str(pick(engine,best))},source)
static func touch_targets(engine,p: Dictionary) -> Array:
 return p.shop.filter(func(c):
  var d=engine.content.get_def(c.def_id);var g=engine.content.get_def(str(d.get("golden_id","")))
  return d.get("kind","")=="minion" and not d.get("golden",false) and g.get("kind","")=="minion" and g.get("golden",false) and g.get("implemented",false) and g.get("base_id","")==d.get("base_id",d.id))
static func transform_gold(engine,c: Dictionary) -> void:
 var d=engine.content.get_def(c.def_id)
 if d.get("golden",false) or str(d.get("golden_id",""))=="":return
 c.def_id=d.golden_id;engine.qualify_gold(c,"converted");c.erase("shaker_round")
 engine.emit("CardTransformed",int(c.owner),{"instance_id":c.instance_id,"id":c.def_id})
 engine.Naga.recruit_entered(engine,engine.state.players[int(c.owner)],c)
static func evolve_pool(engine,p: Dictionary,c: Dictionary) -> Array:
 if c.is_empty():return []
 var d=engine.content.get_def(c.def_id)
 if d.get("kind","")!="minion":return []
 return engine.generation_candidates(p,{"tier":mini(int(d.tier)+1,6)},{}).filter(func(id):return not engine.content.get_def(id).golden and engine.content.get_def(id).base_id!=d.base_id)
static func valid_target(engine,p: Dictionary,d: Dictionary,c: Dictionary) -> bool:
 if d.get("unplayable",false):return false
 if d.effects.is_empty():return true
 if d.id=="BG28_830":return not touch_targets(engine,p).is_empty()
 if d.effects[0].get("op","")=="evolve":return not evolve_pool(engine,p,c).is_empty()
 return true
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
 if e.get("handler","")!="round9":return false
 var source=engine.effect_source;var item=source
 match str(e.op):
  "lockbox":lockbox(engine,p,int(e.get("repeat",1)),int(e.get("advance",1)),source)
  "bounty":bounties(engine,p,int(e.amount),source)
  "gold_cards":gold_cards(engine,p,e,source)
  "give":
   for unused in int(e.amount):engine.receive_card(p,engine.make_card(e.id,int(p.id)),source)
  "next_coins":p.next_coins+=int(e.amount)
  "spell_bonus":p["spell_bonus_attack"]=int(p.get("spell_bonus_attack",0))+int(e.attack)
  "discover_spell":engine.resolve_discovery(p,engine.Naga.spell_pool(engine,p),"pirate_spell",int(e.amount),source)
  "neighbors_gold":
   var board=U.board(engine,p);var index=board.find(c);var n=1+board.filter(func(x):return engine.content.get_def(x.def_id).golden).size()
   for i in [index-1,index+1]:
    if index>=0 and i>=0 and i<board.size():engine.buff(board[i],int(e.attack)*n,0)
  "board_buff","bounty_buff":buff_board(engine,p,e,source)
  "ballad":
   var t=engine.effect_target
   if not t.is_empty():
    for unused in int(e.repeat):engine.buff(t,0,1+int(p.get("coins_spent_round",0)))
  "discovered_buff":
   var scaled=e.duplicate(true);scaled["tribe"]="海盗";scaled["exclude_source"]=true;scaled.attack=int(e.attack)*(1+int(p.get("golden_played",0)));scaled.health=int(e.health)*(1+int(p.get("golden_played",0)));buff_board(engine,p,scaled,source)
  "wine":
   var spec=e.duplicate(true);spec["tribe"]="海盗";buff_board(engine,p,spec,item)
  "crowbar":
   if not U.board(engine,p).is_empty():engine.buff(U.board(engine,p)[0],int(e.attack),int(e.health))
  "shard":balance(engine,p)
  "pendant":
   var candidates=p.board.filter(func(x):return not engine.content.get_def(x.def_id).golden and int(engine.content.get_def(x.def_id).tier)<=int(e.max_tier))
   var t=pick(engine,candidates)
   if t!=null:transform_gold(engine,t)
  "hammer":
   var spec=e.duplicate(true);spec.attack=int(e.attack)*(1+int(p.get("golden_played",0)));spec.health=int(e.health)*(1+int(p.get("golden_played",0)));buff_board(engine,p,spec,item)
  "shield":
   var pool=RNG.shuffle(U.board(engine,p).filter(func(x):return U.tribe(engine,x,e.tribe)),engine.state.streams,"combat")
   for t in pool.slice(0,int(e.amount)):engine.add_keyword(t,"DIVINE_SHIELD")
  "deserter_portrait":advance_box(engine,p,1)
  "pants":
   var v=A.value(engine.current_spell,e,p);engine.buff(c,v.x,v.y)
   if "TAUNT" in engine.keywords(c):
    c.extra_keywords.erase("TAUNT");c.modifiers=c.modifiers.filter(func(m):return m.get("keyword","")!="TAUNT");c["removed_keywords"]=c.get("removed_keywords",[])+["TAUNT"]
    if c.has("keywords"):c.keywords.erase("TAUNT")
   else:
    if c.has("removed_keywords"):c.removed_keywords.erase("TAUNT")
    engine.add_keyword(c,"TAUNT")
  "telescope":
   var tier=mini(int(p.tier),6);var pool=engine.generation_candidates(p,{}).filter(func(id):return int(engine.content.get_def(id).tier)<=tier)
   
   var counts={};var best=[];var highest=0
   for t in engine.state.enabled_tribes:
    counts[t]=p.board.filter(func(x):return U.tribe(engine,x,t)).size()
    if counts[t]>highest:highest=counts[t];best=[t]
    elif counts[t]==highest and highest>0:best.append(t)
   if not best.is_empty():
    var tribe=pick(engine,best);pool=pool.filter(func(id):return tribe in engine.content.get_def(id).card_types or "全部种族" in engine.content.get_def(id).card_types)
   
   if tier<=3 and pool.is_empty():pool=["BG27_080"]
   engine.resolve_discovery(p,pool,"telescope",1,source)
  "confidence":p["confidence_next"]=int(p.get("confidence_next",0))+1
  "shop_growth":
   var v=A.value(engine.current_spell,e,p);p["shop_growth_attack"]=int(p.get("shop_growth_attack",0))+v.x;p["shop_growth_health"]=int(p.get("shop_growth_health",0))+v.y
   for t in p.shop:
    if engine.content.get_def(t.def_id).kind=="minion":engine.buff(t,v.x,v.y)
  "favor":
   var v=A.value(engine.current_spell,e,p);var types=engine.Naga.types(engine,c)
   if not p.has("shop_tribe_growth"):p["shop_tribe_growth"]=[]
   p.shop_tribe_growth.append({"tribes":types.duplicate(),"attack":v.x,"health":v.y})
   for t in p.shop:
    if engine.Naga.types(engine,t).any(func(x):return x in types):engine.buff(t,v.x,v.y)
  "evolve":
   var id=pick(engine,evolve_pool(engine,p,c))
   if id!=null:
    var value=engine.stats(c);var old_mods=c.modifiers.duplicate(true)
    var shop_evolution=str(engine.current_spell.get("id",""))=="BG30_804" and c in p.shop
    if shop_evolution:engine.retire_pool_unit(c,"BG30_804_shop")
    else:engine.return_pool(c)
    c.erase("parrot_damage");c.erase("parrot_done");c.erase("pirate_spent");c.erase("pirate_obtained")
    c.def_id=id;c.pool_base=id;c.pool_copies=1 if shop_evolution else 0;c.triple_receipt=false;c.gold_route="";c.enhanced_reborn_available=false;c.extra_keywords=[];c.erase("reborn_base_health");c.erase("shaker_round");c.erase("removed_keywords");c.modifiers=old_mods
    c.instance_id=int(engine.state.next_instance);engine.state.next_instance+=1
    var base=engine.stats(c);engine.buff(c,value.x-base.x,value.y-base.y)
    engine.Naga.recruit_entered(engine,p,c)
  "seafood":
   var keywords=[]
   for member in U.board(engine,p):
    for k in engine.keywords(member):
     if k not in ["BATTLECRY","DEATHRATTLE"] and k not in keywords:keywords.append(k)
   var n=1+keywords.size();var v=A.value(engine.current_spell,e,p)
   for unused in n:engine.buff(c,v.x,v.y)
  "left_buff":
   if not U.board(engine,p).is_empty():
    var v=A.value(engine.current_spell,e,p);engine.buff(U.board(engine,p)[0],v.x,v.y)
  "majority":majority(engine,p,source)
  "coins":engine.gain_coins(p,int(e.amount))
  "triple_reward":
   var key=str(engine.current_spell.get("reward_key",""))
   if not engine.state.has("reward_tokens_used"):engine.state["reward_tokens_used"]={}
   var repeat_key=key+":repeat:"+str(engine.current_spell.get("reward_repeat_index",0))
   var allowed=engine.current_spell.get("reward_cast_authorized",not engine.state.reward_tokens_used.has(key))
   if key!="" and allowed and not engine.state.reward_tokens_used.has(repeat_key):
    engine.state.reward_tokens_used[key]=true;engine.state.reward_tokens_used[repeat_key]=true
    engine.discover(p,int(engine.current_spell.get("reward_tier",mini(int(p.tier)+1,6))),engine.current_spell.get("reward_source",{}))
  "golden_buff":
   var v=A.value(engine.current_spell,e,p)
   for t in U.board(engine,p):
    engine.buff(t,v.x,v.y)
    if engine.content.get_def(t.def_id).golden:engine.buff(t,v.x,v.y)
  "touch":
   var t=pick(engine,touch_targets(engine,p))
   if t!=null:transform_gold(engine,t)
  "cleave","parrot","privateer","extortion","two_merge","first_free","grifter","spend_buff","spend_box","spend_bounty":pass
  _:return false
 return true
static func power_availability(engine,p: Dictionary) -> Dictionary:
 var handler=engine.hero_handler(p)
 if handler not in HEROES:return {}
 if handler=="hogg":return {"available":false,"reason":"PASSIVE_POWER","targets":[]}
 var cost=int(engine.power_cost(p));var targets=[]
 if handler=="hooktusk":
  for c in p.board:
   if not engine.discovery_candidates(p,{"tier":maxi(1,int(engine.content.get_def(c.def_id).tier)-1)}).is_empty():targets.append(int(c.instance_id))
 var legal=not gold_pool(engine,p,{"eudora":true}).is_empty() if handler=="eudora" else not targets.is_empty()
 var reason="POWER_ALREADY_USED" if engine.power_used(p) else "NOT_ENOUGH_COINS" if int(p.coins)<cost else "NO_LEGAL_CANDIDATE" if not legal else ""
 return {"available":reason=="","reason":reason,"targets":targets,"cost":cost,"handler":handler}
static func use_power(engine,p: Dictionary,args: Dictionary) -> String:
 var handler=engine.hero_handler(p);var query=power_availability(engine,p)
 if not query.available:return query.reason
 if handler=="eudora":
  p["eudora_digs"]=int(p.get("eudora_digs",0))+1
  if int(p.eudora_digs)>=4:p.eudora_digs=0;gold_cards(engine,p,{"eudora":true,"triple_reward":true})
 elif handler=="hooktusk":
  var id=int(args.get("target_id",-1))
  if id not in query.targets:return "BOARD_TARGET_REQUIRED"
  var c=engine.find_target(p,id);var tier=maxi(1,int(engine.content.get_def(c.def_id).tier)-1)
  var pool=engine.discovery_candidates(p,{"tier":tier})
  if pool.is_empty():return "NO_LEGAL_CANDIDATE"
  p.board.erase(c);engine.return_pool(c);engine.emit("MinionRemoved",int(p.id),{"instance_id":id})
  engine.resolve_discovery(p,pool,"hooktusk",1,engine.content.get_def(p.hero_id))
 else:return "PASSIVE_POWER"
 var cost=int(query.cost);p.coins-=cost;engine.consume_power(p);engine.Elementals.spent(engine,p,cost)
 engine.emit("HeroPowerUsed",int(p.id),{"hero":p.hero_id});return ""
static func damaged(engine,c: Dictionary,n: int) -> void:
 if n<=0:return
 var e=engine.Triggers.effects(engine,c).filter(func(x):return x.get("op","")=="parrot")
 if e.is_empty() or c.get("parrot_done",false):return
 c["parrot_damage"]=int(c.get("parrot_damage",0))+n
 var p=engine.state.players[int(c.owner)];var index=engine.find_index(p.board,int(c.instance_id))
 if index>=0:p.board[index]["parrot_damage"]=c.parrot_damage
 if int(c.parrot_damage)>=35:
  c["parrot_done"]=true
  if index>=0:p.board[index]["parrot_done"]=true
  for unused in int(e[0].amount):engine.receive_card(p,engine.make_card("BG28_830",int(p.id)),c)
 engine.emit("ParrotDamageProgress",int(c.owner),{"instance_id":c.instance_id,"damage":c.parrot_damage,"done":c.get("parrot_done",false)})
static func hero_description(engine,p: Dictionary) -> String:
 if engine.hero_handler(p)=="eudora":return ExternalText.phrase("domain_rules_pirate_rules.hero_description.abdfd1ffec87", "说明待补充 · %d") % (4-int(p.get("eudora_digs",0)))
 return str(engine.content.get_def(p.hero_id).get("text",""))
static func combat_result(engine,p: Dictionary,winner: int,side: int) -> void:
 var n=int(p.get("confidence_next",0));p["confidence_next"]=0
 if n>0:p.next_coins+=n*(3 if winner==side else 1 if winner<0 else 0)
