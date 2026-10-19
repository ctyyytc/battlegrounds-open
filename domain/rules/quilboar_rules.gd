extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
static func steal_targets(engine,p: Dictionary) -> Array:
 return p.shop.filter(func(c):return engine.content.get_def(c.def_id).get("kind","")=="minion")
const U=preload("res://domain/rules/undead_rules.gd")
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const A=preload("res://domain/rules/spell_attributes.gd")
const OPS=["give","gem","gem_power","gem_aura","gem_neighbors","self_gems","attack_gem","choice","quota","choice_gems","random_choice","random_tribe","cap","free_refresh","board_gems","auto_barrage","bristles","fel","target_buff","board_buff","time_delay","discover_exact","discover_choice","steal","coins","transfer","barrage","random_buff","bread","ink","piggy","golem","jar","earring","rallies","double_choice","felblade"]
static func supports(d: Dictionary,e: Dictionary) -> bool:
 return d.kind in ["minion","spell","trinket"] and e.get("handler","")=="round8" and e.get("op","") in OPS
static func choice(d: Dictionary) -> bool:
 return d.get("effects",[]).any(func(e):return e.get("op","")=="choice")
static func category(d: Dictionary) -> bool:
 return choice(d) and d.get("choose_one_category",d.get("id","")!="BG31_893")
static func op_effects(engine,c: Dictionary,op: String) -> Array:
 var d=engine.content.get_def(c.get("def_id",c.get("id","")))
 return d.get("effects",[]).filter(func(e):return e.get("handler","")=="round8" and e.get("op","")==op)
static func item(engine,p: Dictionary,op: String) -> bool:
 return p.trinkets.any(func(c):return not op_effects(engine,c,op).is_empty())
static func gem_bonus(engine,p: Dictionary) -> Vector2i:
 var result=Vector2i(int(p.get("gem_attack",0)),int(p.get("gem_health",0)))
 for trinket in p.trinkets:
  for e in op_effects(engine,trinket,"gem_aura"):result+=Vector2i(int(e.attack),int(e.health))
 return result
static func contribution(c: Dictionary,permanent_only: bool=false) -> Vector2i:
 var v=Vector2i.ZERO
 for entry in c.get("gem_contributions",[]):
  if not permanent_only or entry.get("permanent",true):v+=Vector2i(int(entry.attack),int(entry.health))
 return v
static func gem_buff(engine,c: Dictionary,v: Vector2i,permanent: bool=false) -> void:
 if c.is_empty():return
 var combat=U.is_combat(engine)
 var retained=engine.Gifts.count(engine,c,28) if combat else 0
 U.local_buff(engine,c,v.x,v.y,permanent)
 if not c.has("gem_contributions"):c["gem_contributions"]=[]
 var actual=v*(1+retained)
 c.gem_contributions.append({"attack":actual.x,"health":actual.y,"permanent":not combat or permanent or retained>0})
 if combat and (permanent or retained>0) and not U.board_player(engine,int(c.owner)).get("is_ghost",false):
  var original=engine.state.players[int(c.owner)].board
  var i=engine.find_index(original,int(c.instance_id))
  if i>=0:
   if not original[i].has("gem_contributions"):original[i]["gem_contributions"]=[]
   original[i].gem_contributions.append({"attack":actual.x,"health":actual.y,"permanent":true})
 engine.emit("GemContributionAdded",int(c.owner),{"instance_id":c.instance_id,"attack":actual.x,"health":actual.y,"permanent":not combat or permanent or retained>0})
static func auto_gems(engine,p: Dictionary,c: Dictionary,amount: int,source: Dictionary,permanent: bool=false) -> void:
 if c.is_empty():return
 var spell=engine.content.get_def("BG20_GEM").duplicate(true)
 spell["automatic"]=true;spell["counts_player_cast"]=false;spell["force_permanent"]=permanent
 var prior=engine.effect_source;engine.effect_source=source
 for unused in amount:engine.cast(p,spell,c)
 engine.effect_source=prior
static func enhance(engine,p: Dictionary,a: int,h: int) -> void:
 p["gem_attack"]=int(p.get("gem_attack",0))+a;p["gem_health"]=int(p.get("gem_health",0))+h
 engine.emit("GemPowerChanged",int(p.id),{"attack":a,"health":h,"total_attack":p.gem_attack,"total_health":p.gem_health})
static func neighbors(engine,p: Dictionary,c: Dictionary) -> Array:
 var board=U.board(engine,p);var i=engine.find_index(board,int(c.get("instance_id",-1)));var result=[]
 for j in [i-1,i+1]:
  if i>=0 and j>=0 and j<board.size():result.append(board[j])
 return result
static func transfer_neighbors(engine,p: Dictionary,c: Dictionary) -> Array:
 var cards=U.board(engine,p)
 if engine.find_index(cards,int(c.get("instance_id",-1)))<0 and not U.is_combat(engine):cards=p.shop
 var minions=cards.filter(func(v):return engine.content.get_def(v.def_id).kind=="minion")
 var i=engine.find_index(minions,int(c.get("instance_id",-1)));var result=[]
 for j in [i-1,i+1]:
  if i>=0 and j>=0 and j<minions.size():result.append(minions[j])
 return result
static func choice_pool(engine,p: Dictionary,source: Dictionary={}) -> Array:
 var result=engine.generation_candidates(p,{},source).filter(func(id):return category(engine.content.get_def(id)))
 for id in engine.Naga.spell_pool(engine,p):
  if category(engine.content.get_def(id)):result.append(id)
 result.sort();return result
static func give_random_choice(engine,p: Dictionary,n: int,source: Dictionary={}) -> void:
 var pool=choice_pool(engine,p,source)
 for unused in n:
  var id=engine.Naga.pick(engine,pool)
  if id!=null:engine.receive_card(p,engine.make_card(id,int(p.id)),source)
static func quota(engine,c: Dictionary) -> int:
 var es=op_effects(engine,c,"quota")
 if es.is_empty():return 0
 if int(c.get("choice_quota_round",-1))!=int(engine.state.round):
  c["choice_quota_round"]=int(engine.state.round);c["choice_quota"]=int(es[0].amount)
 return int(c.get("choice_quota",0))
static func double_source(engine,p: Dictionary,root: Dictionary) -> Dictionary:
 if not category(root):return {"double":false}
 if root.get("double_choose",false) or item(engine,p,"double_choice"):return {"double":true}
 if root.get("automatic",false):return {"double":false}
 for c in U.board(engine,p):
  var remaining=int(c.get("choice_quota",0)) if int(c.get("choice_quota_round",-1))==int(engine.state.round) else (int(op_effects(engine,c,"quota")[0].amount) if not op_effects(engine,c,"quota").is_empty() else 0)
  if remaining>0:return {"double":true,"quota_instance":int(c.instance_id),"remaining":remaining}
 return {"double":false}
static func automatic_choice(engine,p: Dictionary,d: Dictionary,target: Dictionary) -> Dictionary:
 if not choice(d) or not d.get("automatic",false) or d.has("selected_choice_ids"):return {"spell":d,"target":target}
 var ids=d.effects[0].ids
 var ds=double_source(engine,p,d)
 if d.get("automatic_source","")=="yogg":
  var candidates=U.board(engine,p).duplicate()
  if not U.is_combat(engine):candidates.append_array(p.shop)
  candidates.append({})
  var legal_ids=ids.filter(func(id):return candidates.any(func(c):return engine.Naga.valid_target(engine,p,engine.content.get_def(id),c)))
  var selected=ids.duplicate() if ds.double else [legal_ids[RNG.next(engine.state.streams,"effects",legal_ids.size())]] if not legal_ids.is_empty() else []
  var legal=candidates.filter(func(c):return not selected.is_empty() and selected.all(func(id):return engine.Naga.valid_target(engine,p,engine.content.get_def(id),c)))
  target=legal[RNG.next(engine.state.streams,"effects",legal.size())] if not legal.is_empty() else {}
  d["selected_choice_ids"]=selected
  engine.emit("AutomaticChoiceSelected",int(p.id),{"id":d.id,"branches":selected,"target_instance":target.get("instance_id",-1),"source_power_id":"TB_BaconShop_HP_039t"})
  return {"spell":d,"target":target}
 var indices=range(ids.size()) if ds.double else [RNG.next(engine.state.streams,"effects",ids.size())]
 var selected=[];var targeted=false
 for i in indices:
  selected.append(ids[i]);targeted=targeted or requires_target(engine.content.get_def(ids[i]))
 if targeted:
  var candidates=U.board(engine,p).duplicate()
  if not U.is_combat(engine):candidates.append_array(p.shop)
  candidates=candidates.filter(func(v):return selected.all(func(id):return engine.Naga.valid_target(engine,p,engine.content.get_def(id),v)))
  var preferred=candidates.filter(func(v):return int(v.instance_id)==int(d.get("conjurer_instance",-1)))
  if not preferred.is_empty():target=engine.Naga.pick(engine,preferred)
  elif target.is_empty() or not selected.all(func(id):return engine.Naga.valid_target(engine,p,engine.content.get_def(id),target)):
   var chosen=engine.Naga.pick(engine,candidates);target=chosen if chosen!=null else {}
 else:target={}
 d["selected_choice_ids"]=selected
 engine.emit("AutomaticChoiceSelected",int(p.id),{"id":d.id,"branches":selected,"target_instance":target.get("instance_id",-1),"conjurer_instance":d.get("conjurer_instance",-1)})
 return {"spell":d,"target":target}
static func empty_beetle(engine,p: Dictionary,card: Dictionary) -> bool:
 var d=engine.play_definition(card)
 if d.get("base_id",d.id)!="BG27_084":return false
 return d.effects[0].ids.all(func(id):return (p.board+p.shop).all(func(c):return not engine.Naga.valid_target(engine,p,engine.content.get_def(id),c)))
static func begin_hand(engine,p: Dictionary,card: Dictionary,args: Dictionary) -> void:
 var d=engine.play_definition(card).duplicate(true)
 d["played_from_hand"]=true;d["root_instance"]=int(card.instance_id)
 d["choice_before_instance"]=int(engine.state.next_instance)
 d["placement_index"]=int(args.get("index",p.board.size()))
 if card.get("double_choose",false):d["double_choose"]=true
 var aura=engine.spell_aura(p);d["aura_attack"]=aura.x;d["aura_health"]=aura.y
 
 open_choice(engine,p,d,d.effects[0],{},card,true)
static func open_choice(engine,p: Dictionary,d: Dictionary,e: Dictionary,target: Dictionary,source: Dictionary,from_hand: bool=false) -> void:
 d=d.duplicate(true)
 if source.get("double_choose",false):d["double_choose"]=true
 if d.kind=="minion" and not from_hand and engine.resolution_phase!="turn_end":
  for existing in p.choices:
   if existing.get("round8",false) and existing.get("root",{}).get("id","")==d.id and int(existing.get("source",{}).get("instance_id",-1))==int(source.get("instance_id",-2)):
    existing["branch_repetitions"]=int(existing.get("branch_repetitions",1))+1;return
 var ds=double_source(engine,p,d)
 var session={"kind":"choose_one","round8":true,"options":[],"root":d.duplicate(true),"source":source.duplicate(true),"target_instance":target.get("instance_id",-1),"from_hand":from_hand,"double":ds.double,"quota_instance":ds.get("quota_instance",-1),"resolution_phase":engine.resolution_phase}
 for id in e.ids:session.options.append(engine.make_card(id,int(p.id)))
 if engine.resolution_phase=="turn_end" or d.get("automatic",false):
  var indices=range(session.options.size()) if ds.double else [RNG.next(engine.state.streams,"effects",session.options.size())]
  for i in indices:
   var branch=engine.content.get_def(session.options[i].def_id)
   var chosen=target
   if requires_target(branch) and chosen.is_empty():chosen=engine.Naga.pick(engine,U.board(engine,p))
   if chosen==null:chosen={}
   if requires_target(branch) and not engine.Naga.valid_target(engine,p,branch,chosen):continue
   for spec in branch.effects:engine.effect(p,spec,chosen,source)
  return
 if ds.double:
  session["selected_indices"]=range(session.options.size())
  if not need_target(engine,p,session,target):commit(engine,p,session,target);return
  session.kind="choose_target";session.options=(p.board+p.shop).filter(func(v):return engine.content.get_def(v.def_id).kind=="minion" and not need_target(engine,p,session,v))
 engine.enqueue_choice(p,session)
static func requires_target(d: Dictionary) -> bool:
 return d.get("effects",[]).any(func(e):return e.get("target","none") in ["minion","friendly_minion","friendly_undead"])
static func need_target(engine,p: Dictionary,session: Dictionary,target: Dictionary) -> bool:
 for i in session.get("selected_indices",[]):
  var id=session.root.effects[0].ids[i]
  var branch=engine.content.get_def(id)
  if requires_target(branch) and not engine.Naga.valid_target(engine,p,branch,target):return true
 return false
static func resolve_choice(engine,p: Dictionary,session: Dictionary,args: Dictionary) -> String:
 var index=int(args.get("index",-1))
 if session.kind=="quilboar_gold":
  var source=engine.find_target(p,int(session.source_instance))
  if source.is_empty():return "ROUTE_SOURCE_MISSING"
  if index==0:
   if not source.has("attached_effects"):source["attached_effects"]=[]
   source.attached_effects.append({"handler":"round8","op":"random_choice","trigger":"rally","amount":1})
  else:enhance(engine,p,2,2)
  p.choices.pop_front();engine.emit("QuilboarRouteGranted",int(p.id),{"instance_id":source.instance_id,"option":index});return ""
 if session.kind=="choose_one":session["selected_indices"]=range(session.root.effects[0].ids.size()) if session.double else [index]
 var target=engine.find_target(p,int(session.get("target_instance",-1)))
 if session.kind=="choose_target":
  target=engine.find_target(p,int(args.target_id)) if args.has("target_id") else engine.find_target(p,int(session.options[index].instance_id))
  if target.is_empty() or need_target(engine,p,session,target):return "INVALID_SPELL_TARGET"
 if need_target(engine,p,session,target):
  var candidates=(p.board+p.shop).filter(func(c):return engine.content.get_def(c.def_id).kind=="minion" and not need_target(engine,p,session,c))
  if candidates.is_empty():return "NO_LEGAL_TARGET"
  session.kind="choose_target";session.options=candidates;session["revision"]=int(session.get("revision",0))+1;engine.Choices.refresh(session)
  return ""
 p.choices.pop_front();commit(engine,p,session,target);return ""
static func commit(engine,p: Dictionary,session: Dictionary,target: Dictionary) -> void:
 var root=session.root.duplicate(true)
 root["selected_choice_ids"]=[]
 for i in session.selected_indices:root.selected_choice_ids.append(root.effects[0].ids[i])
 if int(session.get("quota_instance",-1))>=0:
  var c=engine.find_target(p,int(session.quota_instance))
  if not c.is_empty():c.choice_quota=maxi(0,quota(engine,c)-1)
 var previous_phase=engine.resolution_phase;engine.resolution_phase=session.resolution_phase
 if session.from_hand:
  var i=engine.find_index(p.hand,int(root.root_instance));var held=p.hand[i];p.hand.remove_at(i)
  if root.kind=="minion":
   p.hand.insert(i,held)
   var prior=engine.current_spell;engine.current_spell=root;engine.committing_choice=root
   engine.apply_command(p,"play",{"instance_id":held.instance_id,"index":int(root.placement_index),"target_id":int(target.get("instance_id",-1))})
   engine.committing_choice={};engine.current_spell=prior
  else:
   engine.emit("CardPlayedFromHand",int(p.id),{"id":root.id})
   engine.gift_card_played(p,held)
   engine.cast(p,root,target);engine.Naga.hand_used(engine,p,held)
 else:
  var prior=engine.current_spell;engine.current_spell=root
  for unused in int(session.get("branch_repetitions",1)):
   for id in root.selected_choice_ids:
    for spec in engine.content.get_def(id).effects:engine.effect(p,spec,target,session.source)
  engine.current_spell=prior
 choice_used(engine,p,root,session.source)
 engine.resolution_phase=previous_phase
 engine.drain_rewards(p);engine.check_triples(p)
 engine.emit("ChoiceEffectResolved",int(p.id),{"id":root.id,"branches":root.selected_choice_ids})
static func choice_used(engine,p: Dictionary,root: Dictionary,source: Dictionary) -> void:
 if not category(root):return
 for c in U.board(engine,p).duplicate():
  for e in op_effects(engine,c,"choice_gems"):engine.effect(p,e,c,c)
 engine.emit("ChoiceRootUsed",int(p.id),{"id":root.id,"source":source.get("instance_id",-1)})
static func hand_used(engine,p: Dictionary,card: Dictionary) -> void:
 var d=engine.content.get_def(card.def_id)
 if d.kind=="minion" and not choice(d) and card.get("double_choose",false):card.erase("double_choose")
static func gold(engine,p: Dictionary,card: Dictionary) -> void:
 engine.enqueue_choice(p,{"kind":"quilboar_gold","round8":true,"source_instance":card.instance_id,"options":["quilboar.choice_gems","quilboar.choice_stats"]})
static func inherited(material: Dictionary,merged: Dictionary) -> void:
 for field in ["gem_contributions","bread_rewards"]:
  if material.has(field):
   if not merged.has(field):merged[field]=[]
   merged[field].append_array(material[field].filter(func(e):return field!="gem_contributions" or e.get("permanent",true)).duplicate(true))
 if material.get("double_choose",false):merged["double_choose"]=true
static func refresh(engine,p: Dictionary) -> void:
 for v in p.shop:
  if engine.content.get_def(v.def_id).kind!="minion":continue
  for saved in p.get("gem_barrages",[]):
   var prior=engine.effect_source;engine.effect_source=saved.source
   var spell=engine.content.get_def("BG20_GEM").duplicate(true);spell["automatic"]=true;spell["counts_player_cast"]=false
   spell["gem_value"]={"attack":int(saved.attack)+gem_bonus(engine,p).x,"health":int(saved.health)+gem_bonus(engine,p).y}
   engine.cast(p,spell,v);engine.effect_source=prior
static func turn_start(engine,p: Dictionary) -> void:
 for c in p.board:quota(engine,c)
 var keep=[]
 for delayed in p.get("time_delays",[]):
  if int(delayed.round)>int(engine.state.round):keep.append(delayed);continue
  for unused in int(delayed.repeat):
   for c in p.board:U.local_buff(engine,c,int(delayed.attack),int(delayed.health))
 p["time_delays"]=keep
 for c in p.board+p.hand+p.pending_rewards+p.shop:
  for reward in c.get("bread_rewards",[]):
   if int(reward.round)==int(engine.state.round) and int(p.get("last_combat_outcome",-1))==1:engine.buff(c,int(reward.attack),int(reward.health))
  if c.has("bread_rewards"):c.bread_rewards=c.bread_rewards.filter(func(e):return int(e.round)>int(engine.state.round))
static func friendly_attack(engine,p: Dictionary,attacker: Dictionary) -> void:
 for c in U.board(engine,p).duplicate():
  for e in op_effects(engine,c,"attack_gem"):
   if c.instance_id!=attacker.instance_id:auto_gems(engine,p,attacker,int(e.amount),c)
 for trinket in p.trinkets:
  for e in op_effects(engine,trinket,"jar"):
   trinket["combat_uses"]=int(trinket.get("combat_uses",0))+1
   if int(trinket.combat_uses)>=int(e.threshold):
    trinket.combat_uses=0
    for c in U.board(engine,p).duplicate():
     if U.tribe(engine,c,"野猪人"):auto_gems(engine,p,c,int(e.amount),trinket)
static func dead(engine,p: Dictionary,dead_card: Dictionary) -> void:
 for trinket in p.trinkets:
  for e in op_effects(engine,trinket,"golem"):
   if not U.tribe(engine,dead_card,"野猪人") or not U.is_combat(engine):continue
   var board=U.board(engine,p);var side=engine.combat_context.players.find(p)
   if board.size()>=int(engine.combat_context.capacities[side]):continue
   var value=contribution(dead_card)
   var c=engine.make_card("BG30_MagicItem_442t",int(p.id));c["modifiers"]=[{"attack":value.x-1,"health":value.y-1,"duration":"permanent","source":"blood_golem"}]
   var token=engine.Combat.unit(engine,c)
   board.append(token);engine.emit("MinionSummoned",int(p.id),{"instance_id":token.instance_id,"origin":"blood_golem","attack":value.x,"health":value.y})
static func player_cast(engine,p: Dictionary,spell: Dictionary,target: Dictionary) -> void:
 if not spell.get("counts_player_cast",true):return
 for c in U.board(engine,p).duplicate():
  for e in op_effects(engine,c,"fel"):
   c["fel_progress"]=int(c.get("fel_progress",0))+1
   if int(c.fel_progress)>=int(e.threshold):c.fel_progress=0;consume_shop(engine,p,c,int(e.amount))
  if not target.is_empty() and c.instance_id==target.instance_id:
   for e in op_effects(engine,c,"bristles"):
    for neighbor in neighbors(engine,p,c):auto_gems(engine,p,neighbor,int(e.amount),c)
 for trinket in p.trinkets:
  for e in op_effects(engine,trinket,"earring"):
   trinket["gem_progress"]=int(trinket.get("gem_progress",0))+1
   while int(trinket.gem_progress)>=int(e.threshold):
    trinket.gem_progress-=int(e.threshold)
    for c in U.board(engine,p).duplicate():auto_gems(engine,p,c,int(e.amount),trinket)
  for e in op_effects(engine,trinket,"felblade"):
   if not target.is_empty() and engine.find_index(p.shop,int(target.instance_id))>=0:
    var demon=engine.Naga.pick(engine,U.board(engine,p))
    if demon!=null:consume_shop(engine,p,demon,1,target)
static func consume_shop(engine,p: Dictionary,c: Dictionary,multiplier: int,selected: Dictionary={}) -> void:
 var target=selected if not selected.is_empty() else engine.Naga.pick(engine,p.shop.filter(func(v):return engine.content.get_def(v.def_id).kind=="minion"))
 if target==null or target.is_empty():return
 engine.Demons.consume(engine,p,c,target,multiplier)
static func execute(engine,p: Dictionary,e: Dictionary,c: Dictionary) -> bool:
 if e.get("handler","")!="round8" and not (e.get("handler","")=="round7" and e.get("op","")=="choice"):return false
 var n=int(e.get("amount",1));var source=engine.effect_source;var target=engine.effect_target
 var board=U.board(engine,p)
 match str(e.op):
  "gem":
   var v=Vector2i(int(engine.current_spell.get("gem_value",{}).get("attack",1+gem_bonus(engine,p).x)),int(engine.current_spell.get("gem_value",{}).get("health",1+gem_bonus(engine,p).y)))
   gem_buff(engine,c,v,engine.current_spell.get("force_permanent",false))
  "give":
   for unused in n:engine.receive_card(p,engine.make_card(e.id,int(p.id)),source)
  "gem_power":enhance(engine,p,int(e.get("attack",0)),int(e.get("health",0)))
  "gem_neighbors","bristles":
   for neighbor in neighbors(engine,p,c):auto_gems(engine,p,neighbor,n,source)
  "self_gems":auto_gems(engine,p,c,n,source,e.get("permanent",false))
  "board_gems","choice_gems":
   for v in board.duplicate():
    if e.op=="board_gems" or (v.instance_id!=c.instance_id and U.tribe(engine,v,"野猪人")):auto_gems(engine,p,v,n,source)
  "random_choice":give_random_choice(engine,p,n,source)
  "choice":
   if engine.current_spell.has("selected_choice_ids"):
    for id in engine.current_spell.selected_choice_ids:
     var branch=engine.content.get_def(id)
     for spec in branch.effects:engine.effect(p,spec,engine.effect_target if requires_target(branch) else c,source)
   else:
    var d=engine.current_spell if not engine.current_spell.is_empty() else engine.content.get_def(c.def_id)
    open_choice(engine,p,d,e,c if not c.is_empty() and d.kind=="spell" else target,source)
  "random_tribe":U.random_cards(engine,p,e,source)
  "cap":engine.increase_coin_cap(p,n)
  "free_refresh":p.free_refresh+=n
  "auto_barrage":
   var d=engine.content.get_def("BG34_689").duplicate(true);d["automatic"]=true
   for unused in n:engine.cast(p,d,{})
  "target_buff","board_buff","random_buff","bread","time_delay":
   var v=A.value(engine.current_spell,e,p)
   if e.op=="time_delay":
    if not p.has("time_delays"):p["time_delays"]=[]
    p.time_delays.append({"round":int(engine.state.round)+1,"attack":v.x,"health":v.y,"repeat":int(e.repeat)})
   else:
    var targets=[c] if e.op in ["target_buff","bread"] else board.duplicate()
    if e.op=="random_buff":targets=RNG.shuffle(targets,engine.state.streams,"effects").slice(0,n)
    for unused in int(e.get("repeat",1)):
     for vcard in targets:U.local_buff(engine,vcard,v.x,v.y,engine.current_spell.get("force_permanent",false))
    if e.op=="bread" and not c.is_empty():
     if not c.has("bread_rewards"):c["bread_rewards"]=[]
     var later=A.value(engine.current_spell,{"handler":"round8","op":"bread","attack":4,"health":6},p)
     c.bread_rewards.append({"round":int(engine.state.round)+1,"attack":later.x,"health":later.y})
  "discover_exact","discover_choice":
   var pool=[]
   if e.op=="discover_choice":pool=choice_pool(engine,p,source)
   elif e.get("kind","minion")=="minion":pool=engine.discovery_candidates(p,{"tier":int(p.tier)},source)
   else:pool=engine.Naga.spell_pool(engine,p).filter(func(id):return int(engine.content.get_def(id).tier)==int(p.tier))
   var context=source.duplicate(true)
   if e.get("lock",false):context["reward_locked_until"]=int(engine.state.round)+1
   if e.get("double",false):context["reward_double_choose"]=true
   if engine.current_spell.get("automatic",false):
    var id=engine.Naga.pick(engine,pool)
    if id!=null:
     var reward=engine.make_card(id,int(p.id));reward_metadata(reward,context);engine.receive_card(p,reward,context)
   else:engine.resolve_discovery(p,pool,"round8_discovery",1,context)
  "steal":
   var stolen=engine.Naga.pick(engine,steal_targets(engine,p))
   if stolen!=null:p.shop.erase(stolen);engine.receive_card(p,stolen,source);engine.emit("ShopMinionStolen",int(p.id),{"instance_id":stolen.instance_id})
  "coins":engine.gain_coins(p,n)
  "barrage":
   var v=A.value(engine.current_spell,e,p)
   if not p.has("gem_barrages"):p["gem_barrages"]=[]
   p.gem_barrages.append({"attack":v.x,"health":v.y,"source":source.duplicate(true)})
  "transfer":
   auto_gems(engine,p,c,n,source)
   for neighbor in transfer_neighbors(engine,p,c):
    var value=contribution(neighbor)
    if value==Vector2i.ZERO:continue
    U.local_buff(engine,neighbor,-value.x,-value.y)
    if U.is_combat(engine):neighbor.gem_contributions=[]
    else:neighbor.gem_contributions=[]
    gem_buff(engine,c,value)
    engine.emit("GemContributionTransferred",int(p.id),{"from":neighbor.instance_id,"to":c.instance_id,"attack":value.x,"health":value.y})
  "ink":enhance(engine,p,int(e.attack),int(e.health))
  "piggy":
   for v in board:
    if U.tribe(engine,v,"野猪人"):
     if not v.has("attached_effects"):v["attached_effects"]=[]
     v.attached_effects.append({"handler":"round8","op":"give","trigger":"deathrattle","id":"BG20_GEM","amount":n})
  "rallies":
   for v in board.duplicate():engine.run_effects(p,v,"rally")
  "quota","gem_aura","fel","attack_gem","jar","earring","golem","double_choice","felblade":pass
  _:return false
 return true
static func reward_metadata(card: Dictionary,source: Dictionary) -> void:
 if source.has("reward_locked_until"):card["locked_until_round"]=int(source.reward_locked_until)
 if source.get("reward_double_choose",false):card["double_choose"]=true
