extends RefCounted
const Pairing=preload("res://domain/rules/round143_pairing.gd")
const ExternalText = preload("res://domain/resources/external_content.gd")
const R136=preload("res://domain/rules/round136_rewards.gd")
const R136Slots=preload("res://domain/rules/round136_slots.gd")
const R135=preload("res://domain/rules/round135_quests.gd")
const R134=preload("res://domain/rules/round134_prizes.gd")
const Yogg=preload("res://domain/rules/yogg_automatic.gd")
const Registry=preload("res://domain/rules/content_registry.gd")
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const Special=preload("res://domain/rules/special_rules.gd")
const Selection=preload("res://domain/rules/selection_service.gd")
const Combat=preload("res://domain/rules/combat_service.gd")
const EffectDispatcher=preload("res://domain/rules/effect_dispatcher.gd")
const ActionAvailability=preload("res://domain/rules/action_availability.gd")
const Triggers=preload("res://domain/rules/trigger_rules.gd")
const Gifts=preload("res://domain/rules/dark_gift_rules.gd")
const Elementals=preload("res://domain/rules/elemental_rules.gd")
const Quilboar=preload("res://domain/rules/quilboar_rules.gd")
const Naga=preload("res://domain/rules/naga_rules.gd")
const SpellHistory=preload("res://domain/rules/spell_history.gd")
const Pirates=preload("res://domain/rules/pirate_rules.gd")
const Beasts=preload("res://domain/rules/beast_rules.gd")
const Fish=preload("res://domain/rules/murloc_rules.gd")
const Demons=preload("res://domain/rules/demon_rules.gd")
const Payment=preload("res://domain/rules/recruit_payment.gd")
const R13Items=preload("res://domain/rules/round13_trinkets.gd")
const R13=preload("res://domain/rules/round13_minions.gd")
const Heroes7=preload("res://domain/rules/round7_heroes.gd")
const Powers=preload("res://domain/rules/power_slots.gd")
const R133=preload("res://domain/rules/round133_rules.gd")
const Secrets133=preload("res://domain/rules/round133_secrets.gd")
const R132=preload("res://domain/rules/round132_powers.gd")
const Shop132=preload("res://domain/rules/round132_shop.gd")
const CardLock=preload("res://domain/rules/card_lock.gd")
const Combat132=preload("res://domain/rules/round132_combat.gd")
var power_context: Dictionary={}
var content
var state: Dictionary = {}
var events: Array = []
var spell_history: Array=[]
var committing_choice: Dictionary={}
const Persistence=preload("res://domain/rules/save_journal.gd")
var persistence_epoch: int=0
var persistence_cache: Dictionary={}
var receipts: Dictionary = {}
var command_log: Array = []
const UNDO_HISTORY_LIMIT=3
var undo_history: Array=[]
var undo_checkpoint: Dictionary:
	get:return {} if undo_history.is_empty() else undo_history[-1]
var undo_tracking_enabled: bool=true
var cause: String = ""
var draining_effects: bool=false
const Undead=preload("res://domain/rules/undead_rules.gd")
var combat_context: Dictionary={}
var effect_target: Dictionary={}
var effect_source: Dictionary={}
var resolution_phase: String=""
var current_spell: Dictionary={}
var cast_destroy_succeeded: bool=false
const Acquisition=preload("res://domain/rules/acquisition_source.gd")
const Fast=preload("res://domain/rules/fast_action_policy.gd")
const Choices=preload("res://domain/rules/choice_automation.gd")
const Core=preload("res://domain/rules/core_protection.gd")
const Continuation=preload("res://domain/rules/action_continuation.gd")
var settlement_depth: int=0
var checking_triples: bool=false
func auto_play_args(p: Dictionary,card: Dictionary) -> Dictionary:
	var args={"instance_id":card.instance_id,"index":p.board.size()}
	var d=play_definition(card)
	if d.effects.any(func(e):return e.handler=="magnetic"):
		for c in p.board:
			if legal_magnetic_target(p,card,c):args["target_id"]=c.instance_id;return args
	if requires_battlecry_target(d):
		for c in p.board+p.shop:
			var candidate=args.duplicate();candidate["target_id"]=c.instance_id
			if validate_hand_play(p,candidate).is_empty():return candidate
	return args
func enqueue_choice(p: Dictionary,choice: Dictionary) -> void:
	Choices.enqueue(self,p,choice)
func legacy_auto_target(root: String="") -> bool:
	var chain=state.get("auto_chain",{})
	return chain.get("target_policy","")=="legacy_first_legal" and (root=="" or root==chain.get("root_action_id",""))
func start_auto_chain(p: Dictionary,instance_id: int,confirmed: bool=false) -> String:
	if R134.sale_blocked(p):return "WHEEL_ANIMATION_PENDING"
	if int(p.id)!=0 or state.phase!="recruit":return "WRONG_PHASE"
	if int(state.get("fast_mode_level",0))!=2:return "FAST_MODE_DISABLED"
	if state.has("auto_chain") or not p.choices.is_empty():return "AUTO_CHAIN_BUSY"
	for session in p.sessions.values():
		if not session.resolved and not session.get("deferred",false):return "UNRELATED_SESSION"
	var i=find_index(p.hand,instance_id)
	if i<0:return "CARD_NOT_IN_HAND"
	var card=p.hand[i]
	if play_definition(card).kind!="minion":return "MINION_REQUIRED"
	var policy=Fast.classify(self,p,card,true)
	if not policy.reasons.is_empty() or policy.unknown_dynamic:return "FAST_EFFECT_REQUIRES_MANUAL"
	var args=auto_play_args(p,card);var error=validate_hand_play(p,args)
	if not error.is_empty():return error
	if not confirmed and Continuation.request(self,p,card,"sell",{"kind":"auto_start","input_origin":"right_click","instance_id":instance_id,"play_args":args,"mode":"play_then_sell","target_policy":"legacy_first_legal"}):return ""
	state["auto_chain"]=Fast.chain(self,p,"play_then_sell",instance_id,"legacy_first_legal")
	error=apply_command(p,"play",args)
	if not error.is_empty():state.erase("auto_chain");return error
	return ""
func advance_auto_chain(_p: Dictionary) -> void:
	
	while state.has("auto_chain") and not state.has("confirmation") and state.phase=="recruit":
		var p=state.players[0];var chain=state.auto_chain
		if int(chain.steps)>=128:stop_auto_chain("PROGRESS_BUDGET");return
		drain_effects();resume_tails(p)
		settle_recruit_deaths()
		if state.phase!="recruit":return
		if state.has("confirmation"):return
		check_triples(p);drain_rewards(p)
		if not p.choices.is_empty():
			var choice=p.choices[0];Choices.refresh(choice)
			if choice.get("root_action_id","")!=chain.root_action_id or not choice.has("session_id") or choice.get("auto_policy","")!="random_legal_effect_option":stop_auto_chain("UNRELATED_CHOICE");return
			var kind="choose";var args={};var legal=[];var rng_before=state.streams.duplicate(true)
			if choice.selection_semantics=="entity_target":
				if not legacy_auto_target():chain.stage="manual_target";return
				if choice.kind=="choose_target":
					var candidates=(p.board+p.shop).filter(func(c):return content.get_def(c.def_id).kind=="minion" and not Quilboar.need_target(self,p,choice,c))
					if candidates.is_empty():stop_auto_chain("NO_LEGAL_TARGET");return
					kind="choose_target";args={"target_id":candidates[0].instance_id}
				else:
					legal=Choices.eligible(self,p,choice)
					if legal.is_empty():stop_auto_chain("NO_LEGAL_TARGET");return
					args={"index":legal[0]}
			elif choice.selection_semantics=="effect_option":
				legal=Choices.eligible(self,p,choice)
				if legal.is_empty():stop_auto_chain("NO_LEGAL_OPTION");return
				args={"index":legal[RNG.next(state.streams,"choice",legal.size())]}
			else:stop_auto_chain("UNKNOWN_SESSION");return
			var identity={"root_action_id":choice.root_action_id,"session_id":choice.session_id,"revision":choice.revision,"kind":choice.kind,"eligible_indices":legal,"chosen_index":args.get("index",-1),"target_id":args.get("target_id",-1),"RNG_before":rng_before,"RNG_after":state.streams.duplicate(true)}
			var error=Choices.step(self,kind,args)
			if not error.is_empty():state.streams=rng_before;stop_auto_chain(error);return
			state.auto_chain.steps+=1;state.auto_chain.stage="settle"
			emit("AutoSelectionResolved",0,identity);settle_recruit_deaths();continue
		if chain.mode=="play_then_sell" and not chain.sold:
			if R134.sale_blocked(p):stop_auto_chain("WHEEL_ANIMATION_PENDING");return
			var i=find_index(p.board,int(chain.instance_id))
			if i<0:chain.sold=true;emit("AutoChainSourceGone",0,{"instance_id":chain.instance_id});continue
			if Continuation.request(self,p,p.board[i],"sell",{"kind":"command","command":"auto_sell","payload":{"instance_id":chain.instance_id}}):return
			var error=Choices.step(self,"auto_sell",{"instance_id":chain.instance_id})
			if error!="":stop_auto_chain(error);return
			state.auto_chain.steps+=1;settle_recruit_deaths();continue
		emit("AutoChainFinished",0,{"instance_id":chain.instance_id,"mode":chain.mode});state.erase("auto_chain")
func resume_tails(p: Dictionary) -> void:
	if state.has("confirmation"):return
	if state.has("cast_tail"):
		var tail=state.cast_tail;state.erase("cast_tail")
		var target=find_target(p,int(tail.target_instance))
		cast(p,tail.spell,tail.get("target",{}) if target.is_empty() else target,int(tail.repeat),int(tail.next_effect),true,int(tail.times))
	if state.has("confirmation"):return
	if state.has("play_tail"):
		var tail=state.play_tail;state.erase("play_tail")
		var c=find_target(p,int(tail.instance_id))
		if c.is_empty():c=tail.get("card",{})
		if not c.is_empty():
			if tail.get("choice_play",false):run_effects(p,c,"choice_play",{},true,1)
			if tail.get("choice_play",false) and int(c.get("grave_round",0))==int(state.round):Undead.recruit_destroy(self,p,c)
			if state.has("confirmation"):state["play_tail"]={"owner":p.id,"instance_id":c.instance_id,"card":c,"choice_play":false};return
			grant_triple_reward(p,c);Demons.feed(self,p)
func stop_auto_chain(reason: String="MANUAL_STOP") -> void:
	if state.has("auto_chain"):emit("AutoChainStopped",0,{"reason":reason,"root_action_id":state.auto_chain.root_action_id})
	state.erase("auto_chain")
func capacity(cards: Array) -> int:
	return Special.capacity(cards)
func recruit_reborn(dead: Dictionary) -> Dictionary:
	var child=Combat.reborn(self,Combat.unit(self,dead))
	child.erase("attack"); child.erase("health"); child.erase("max_health"); child.erase("keywords"); child.erase("shield"); child.erase("venom");child.erase("poison")
	child.extra_keywords.erase("REBORN")
	child["reborn_consumed"]=true
	return child
func _init(registry = null) -> void:
	content=registry if registry!=null else Registry.new()
static func tribe_selection(approved: Array,seed_value: int) -> Dictionary:
	var streams={"tribes":posmod(seed_value+131071,2147483646)+1}
	var tribes=RNG.shuffle(approved,streams,"tribes").slice(0,5) if approved.size()>5 else approved.duplicate()
	return {"tribes":tribes,"stream":streams.tribes}
func start(seed_value: int,hero_id: String="BG32_HERO_001") -> String:
	var selected=tribe_selection(content.rules.validation_tribes,seed_value).tribes
	if hero_id not in content.pool("hero",selected,false):return "ILLEGAL_HERO_FOR_MATCH"
	persistence_epoch+=1;persistence_cache={}
	undo_history.clear()
	state={"schema_version":1,"rules_version":content.pack.rules_version,"content_hash":content.content_hash,"numeric_profile_hash":content.numeric_profile_hash,"seed":seed_value,
		"revision":0,"round":1,"phase":"recruit","remaining_ms":150000,"paused":false,"next_instance":1,"event_seq":0,
		"round_start_autosave":{"round":1,"status":"pending"},
		"enabled_tribes":content.rules.validation_tribes.duplicate(),"streams":{},"players":[],"pool":{},"results":[],"ghosts":[],"champion":-1,"effect_queue":[]}
	var selection=tribe_selection(content.rules.validation_tribes,seed_value)
	state.streams["tribes"]=selection.stream;state.enabled_tribes=selection.tribes
	for i in 8: state.streams["shop"+str(i)]=posmod(seed_value+i*7919,2147483646)+1
	for stream in ["combat","pairing","choice","effects"]: state.streams[stream]=posmod(seed_value+stream.hash(),2147483646)+1
	var heroes=content.pool("hero",state.enabled_tribes,false)
	if hero_id in heroes:heroes.erase(hero_id); heroes.push_front(hero_id)
	for i in 8:
		var h=content.get_def(heroes[i%heroes.size()])
		state.players.append({"id":i,"name":ExternalText.phrase("domain_rules_match_engine.start.7239450b723d", "说明待补充") if i==0 else ExternalText.phrase("domain_rules_match_engine.start.2bb5b7aadde5", "说明待补充")+str(i),"hero_id":h.id,
			"health":int(h.health),"armor":int(h.armor),"tier":1,"coins":3,"cap_bonus":0,"turn_start_coin_cap":3,"current_coin_cap":3,"upgrade_cost":5,
			"hand":[],"board":[],"shop":[],"pending_rewards":[],"frozen":false,"alive":true,"rank":0,
			"free_refresh":0,"next_coins":0,"elementals_played":0,"elemental_bonus_attack":0,"elemental_bonus_health":0,"ball_sold_count":0,
			"undead_attack":0,"undead_health":0,"spell_count":0,"tavern_spell_count":0,"power_used":false,"power_used_game":false,
			"choices":[],"sessions":{},"trinkets":[],"voucher_sources":[],"trinket_refreshes":0,"gift_refreshes":0,"gifts_bought":0,"gift_round":0})
	for id in content.pool("minion",state.enabled_tribes):
		state.pool[id]=int(content.rules.pool_copies[int(content.get_def(id).tier)-1])
	events=[]; spell_history=[]; receipts={}; command_log=[]
	for p in state.players: Powers.ensure(self,p);Fish.initialize(self,p);Demons.turn_start(self,p);refill_shop(p,false,true,false,"initial_setup")
	R132.pairings(self)
	for p in state.players: R132.initialize(self,p);R136Slots.sync(self,p);R132.turn_start(self,p);turn_start_judgment(p)
	emit("MatchStarted",0,{"seed":seed_value,"mode":"validation_pool"})
	return ""
func round_start_settled() -> bool:
	if state.get("phase","")!="recruit" or settlement_depth>0 or draining_effects:return false
	if state.players[0].has("hero_gift_due"):return false
	for key in ["round_start_cursor","recruit_end_pending","confirmation","auto_chain","play_tail","cast_tail","devour_tail"]:
		if state.has(key):return false
	return state.get("effect_queue",[]).is_empty() and state.players[0].choices.is_empty() and not R134.pending(state.players[0])
func emit(kind: String,owner: int,payload: Dictionary = {}) -> void:
	state.event_seq+=1
	events.append({"seq":state.event_seq,"kind":kind,"owner":owner,"round":state.round,"phase":state.phase,"cause_id":cause,"root_cause_id":cause,"payload":payload.duplicate(true)})
	if kind in ["AutomaticSpellUnavailable","EmptyDiscoveryPool"] and owner==0 and not events[-1].payload.has("presentation"):
		events[-1].payload["presentation"]=SpellHistory.context(self,state.players[owner],{},effect_source)
	SpellHistory.append(self,events[-1])
	var fact=events[-1].duplicate(true)
	R132.event(self,fact)
	R133.event(self,fact)
	R135.event(self,fact)
	if kind in ["CoinsSpent","TavernUpgraded"] and owner>=0 and owner<state.players.size():CardLock.update(self,state.players[owner],fact)
func make_card(id: String,owner: int,copies: int=0) -> Dictionary:
	if id=="BG32_236":id="BG32_236_G"
	var d=content.get_def(id)
	var card={"instance_id":int(state.next_instance),"def_id":id,"owner":owner,"pool_base":d.get("pool_stock_id",d.get("base_id",id)),
		"pool_copies":copies,"modifiers":[],"extra_keywords":[],"gold_route":"","enhanced_reborn_available":false,"triple_receipt":false,"gifts":[]}
	state.next_instance+=1
	Fish.generated(self,state.players[owner],card)
	Quilboar.quota(self,card)
	qualify_gold(card,"created")
	return card
func exclude_gold_reward(card: Dictionary,source: String) -> void:
	card.triple_receipt=false
	card.erase("triple_reward_key");card.erase("gold_reward_source")
	card["gold_reward_excluded"]=source
func qualify_gold(card: Dictionary,source: String,no_reward: bool=false) -> void:
	var d=content.get_def(card.def_id)
	if d.get("kind","")!="minion" or not d.get("golden",false):return
	if no_reward or d.get("base_id","")=="BG32_236":
		exclude_gold_reward(card,source);return
	if card.has("gold_reward_excluded") or card.has("triple_reward_key"):return
	card.triple_receipt=true;card["triple_reward_key"]="gold:"+str(card.instance_id);card["gold_reward_source"]=source
func qualify_gold_copy(card: Dictionary,source: String) -> void:
	card.erase("triple_reward_key");card.triple_receipt=false;qualify_gold(card,source)
func stats(card: Dictionary,purpose: String="current") -> Vector2i:
	var d=content.get_def(card.def_id)
	if Beasts.immune(self,card):return Vector2i(0,2 if d.golden else 1)
	var p=state.players[int(card.owner)]
	for context_player in combat_context.get("players",[]):
		if int(context_player.id)==int(card.owner): p=context_player; break
	var base=card.get("base_override",{})
	var result=Vector2i(int(base.get("attack",d.get("attack",0))),int(card.get("reborn_base_health",base.get("health",d.get("health",0)))))
	for e in d.effects:
		if e.handler=="elemental_counter": result+=int(p.elementals_played)*Special.ice_gain(d.golden,int(p.elemental_bonus_attack),int(p.elemental_bonus_health))
	for m in card.modifiers: result+=Vector2i(int(m.get("attack",0)),int(m.get("health",0)))
	result+=Beasts.derived(self,p,card,purpose)
	result+=Gifts.derived(self,p,card)
	result+=Naga.derived(d,p)
	for spec in d.effects:
		if spec.get("op","")=="extortion":result+=Vector2i(int(spec.attack),int(spec.health))*int(p.get("golden_played",0))
	if d.get("base_id","")=="BG25_008":
		var multiplier=2 if d.golden else 1
		result+=Vector2i(4*multiplier*int(p.get("knight_deaths",0))+int(p.get("knight_extra_attack",0)),2*multiplier*int(p.get("knight_deaths",0))+int(p.get("knight_extra_health",0)))
	if d.get("base_id","")=="BG_TTN_401":
		var n=maxi(0,int(p.get("automaton_summons",0))-(1 if card.get("automaton_counted",false) else 0))
		result+=Vector2i(3,2)*n*(2 if d.golden else 1)
	if "亡灵" in card_types(card) or "全部种族" in card_types(card): result+=Vector2i(int(p.undead_attack),int(p.get("undead_health",0)))
	for item in p.trinkets:
		for e in content.get_def(item.id).effects:
			if e.handler=="tribe_attack" and (e.tribe in card_types(card) or "全部种族" in card_types(card)): result.x+=int(e.amount)
	return result
func coin_capacity(p: Dictionary) -> int:
	return int(p.get("current_coin_cap",mini(int(state.round)+2,10)+int(p.cap_bonus)))
func increase_coin_cap(p: Dictionary,amount: int) -> void:
	var previous=coin_capacity(p)
	p.cap_bonus+=amount
	p["current_coin_cap"]=previous+amount
	emit("CoinCapChanged",int(p.id),{"previous":previous,"current":p.current_coin_cap,"amount":amount})
func keywords(card: Dictionary) -> Array:
	var result=content.get_def(card.def_id).get("keywords",[]).duplicate()
	for k in card.get("removed_keywords",[]):result.erase(k)
	if card.get("reborn_consumed",false): result.erase("REBORN")
	for k in card.extra_keywords:
		if not k in result: result.append(k)
	for m in card.modifiers:
		if m.has("keyword") and not m.keyword in result: result.append(m.keyword)
	return result
func buff(card: Dictionary,a: int,h: int,duration: String="permanent",source: String="effect",quest_gain: bool=true) -> void:
	if Beasts.immune(self,card):return
	if not combat_context.is_empty() and card.has("attack"):
		Undead.local_buff(self,card,a,h);return
	
	var layers=card.modifiers
	if not layers.is_empty() and layers[-1].size()==4 and layers[-1].has("attack") and layers[-1].has("health") and layers[-1].get("duration","")==duration and layers[-1].get("source","")==source:
		layers[-1].attack+=a;layers[-1].health+=h
	else:layers.append({"attack":a,"health":h,"duration":duration,"source":source})
	if combat_context.is_empty():R13Items.amalgam_gain(self,card,a,h)
	if quest_gain:R135.stat_gain(self,card,a,h)
	emit("StatsChanged",int(card.owner),{"instance_id":card.instance_id,"attack":a,"health":h,"duration":duration})
func add_keyword(card: Dictionary,keyword: String,duration: String="permanent") -> void:
	if not combat_context.is_empty() and card.has("keywords"):
		if keyword not in card.keywords: card.keywords.append(keyword)
		if keyword=="DIVINE_SHIELD": card.shield=true
		if keyword=="VENOMOUS": card.venom=true
		if keyword=="POISONOUS": card["poison"]=true
		if Gifts.count(self,card,28)>0:
			var p=state.players[int(card.owner)];var index=find_index(p.board,int(card.instance_id))
			if index>=0: add_keyword(p.board[index],keyword)
		return
	if duration=="permanent":
		if keyword not in card.extra_keywords: card.extra_keywords.append(keyword)
	else: card.modifiers.append({"keyword":keyword,"duration":duration})
func return_pool(card: Dictionary) -> void:
	for attached in card.get("attached_pool",[]): return_pool_copies(str(attached.id),int(attached.copies))
	if int(card.pool_copies)>0:
		return_pool_copies(str(card.pool_base),int(card.pool_copies))
func return_pool_copies(id: String,amount: int) -> void:
	# A generated card can retire a family whose available stock is already zero.
	# Reserve that loss against its next return without exposing negative stock.
	var debt=state.get("pool_retirement_debt",{})
	var offset=mini(amount,int(debt.get(id,0)))
	if offset>0:
		debt[id]=int(debt[id])-offset
		if int(debt[id])==0:debt.erase(id)
	state.pool[id]=int(state.pool.get(id,0))+amount-offset
func retire_pool_unit(card: Dictionary,reason: String) -> void:
	var id=str(card.pool_base)
	return_pool(card)
	card.pool_copies=0;card["attached_pool"]=[]
	# Spells and out-of-pool tokens have no finite shared stock to retire.
	if content.get_def(card.def_id).get("kind","")!="minion" or not state.pool.has(id):return
	var removed=0
	if int(state.pool[id])>0:state.pool[id]-=1;removed=1
	elif owned_pool_copies(id)>int(state.get("pool_retirement_debt",{}).get(id,0)):
		if not state.has("pool_retirement_debt"):state["pool_retirement_debt"]={}
		state.pool_retirement_debt[id]=int(state.pool_retirement_debt.get(id,0))+1
		removed=1
	emit("PoolUnitRetired",int(card.owner),{"id":id,"amount":removed,"reason":reason,"available":int(state.pool[id]),"debt":int(state.get("pool_retirement_debt",{}).get(id,0))})
func owned_pool_copies(id: String) -> int:
	var amount=0
	for p in state.players:
		var owned=[]
		for zone in ["shop","board","hand","pending_rewards"]:owned.append_array(p[zone])
		for choice in p.choices:owned.append_array(choice.get("options",[]).filter(func(c):return c is Dictionary and c.has("pool_copies")))
		for c in owned:
			if str(c.get("pool_base",""))==id:amount+=int(c.get("pool_copies",0))
			for attached in c.get("attached_pool",[]):
				if str(attached.id)==id:amount+=int(attached.copies)
	return amount
func refill_shop(p: Dictionary,keep: bool,notify: bool=true,preserve_individual: bool=false,reason: String="ordinary") -> bool:
	return Demons.refill(self,p,keep,notify,"",preserve_individual,reason)
func receive_card(p: Dictionary,card: Dictionary,source: Dictionary={}) -> String:
	var ticket_fact=R133.capture(self,p,card)
	R133.strip(card)
	Fish.generated(self,p,card)
	Naga.generated(self,p,card)
	var origin=Acquisition.context(self,source)
	var spellcraft=bool(content.get_def(card.def_id).get("is_spellcraft",false))
	if origin.origin_kind=="unclassified_special":emit("AcquisitionSourceMissing",int(p.id),{"instance_id":card.instance_id,"root_action_id":cause})
	card["acquisition_source"]=origin
	var presentation=SpellHistory.context(self,p,card,source) if int(p.id)==0 and content.get_def(card.def_id).kind=="spell" else {}
	var result="granted"
	if p.hand.size()<int(content.rules.hand_limit) and not ((spellcraft or origin.origin_kind in ["darkmoon_prize","quest_reward"]) and not p.pending_rewards.is_empty()):
		p.hand.append(card)
		emit("HandEntered",int(p.id),{"instance_id":card.instance_id,"id":card.def_id})
		emit("CardGranted",int(p.id),{"id":card.def_id,"instance_id":card.instance_id,"origin":origin,"presentation":presentation})
	elif spellcraft or Acquisition.protected(origin):
		result="queued";p.pending_rewards.append(card)
		emit("RewardQueued",int(p.id),{"id":card.def_id,"instance_id":card.instance_id,"origin":origin,"presentation":presentation})
	else:
		return_pool(card)
		emit("CardBurned",int(p.id),{"id":card.def_id,"instance_id":card.instance_id,"origin":origin,"presentation":presentation})
		return "burned"
	R133.acquired(self,p,card,ticket_fact)
	check_triples(p)
	Pirates.obtained(self,p,card)
	return result
func drain_rewards(p: Dictionary) -> void:
	if settlement_depth>0 or draining_effects or not state.get("effect_queue",[]).is_empty() or not p.choices.is_empty() or state.has("confirmation"):return
	while p.hand.size()<int(content.rules.hand_limit) and not p.pending_rewards.is_empty():
		var card=p.pending_rewards.pop_front();p.hand.append(card)
		emit("HandEntered",int(p.id),{"instance_id":card.instance_id,"id":card.def_id})
		emit("RewardDelivered",int(p.id),{"instance_id":card.instance_id})
		check_triples(p)
		if not p.choices.is_empty() or state.has("confirmation"):break
func gain_coins(p: Dictionary,amount: int) -> void:
	
	
	p.coins=int(p.coins)+amount
	Pirates.balance(self,p)
func find_index(zone: Array,id: int) -> int:
	for i in zone.size():
		if int(zone[i].instance_id)==id: return i
	return -1
func find_target(p: Dictionary,id: int) -> Dictionary:
	for c in p.board+p.shop:
		if int(c.instance_id)==id and (content.get_def(c.def_id).kind=="minion" or c in p.shop and content.get_def(c.def_id).get("is_tavern_spell",false)): return c
	return {}
func action_state() -> Dictionary:
	# Finished combat playback is immutable during recruit. Keep its identity in
	# local rollback/preview copies; external snapshot() still copies everything.
	if state.get("phase","")!="recruit" or not state.has("combat_frames"):return state.duplicate(true)
	var live=state.duplicate();live.erase("combat_frames")
	var copied=live.duplicate(true);var ordered=state.duplicate()
	ordered.merge(copied,true)
	return ordered
func undo_ready() -> bool:
	if state.get("phase","")!="recruit" or state.has("round_start_cursor") or state.has("recruit_end_pending") or state.get("r134_end_requested",false):return false
	if not undo_checkpoint.is_empty() and int(undo_checkpoint.round)==int(state.round):return true
	var marker=state.get("round_start_autosave",{})
	return round_start_settled() or (int(marker.get("round",-1))==int(state.round) and marker.get("status","") in ["saved","failed","legacy_complete","loaded_complete"])
func undo_info() -> Dictionary:
	var reason="" if undo_ready() else "本回合开始尚未结算完成" if state.get("phase","")=="recruit" else "战斗或回合结束后不可撤销"
	if reason=="" and (undo_checkpoint.is_empty() or int(undo_checkpoint.round)!=int(state.round)):reason="本回合暂无可撤销操作"
	return {"available":reason=="","depth":undo_history.size(),"label":str(undo_checkpoint.get("label","")),"reason":reason}
func undo_continuation(kind: String,args: Dictionary) -> bool:
	if undo_checkpoint.is_empty():return false
	if kind in ["choose","choose_target","confirm_action","cancel_confirmation","cancel_choice"]:
		return str(state.get("active_root",""))==str(undo_checkpoint.root)
	if kind in ["open_choice","resolve_choice","refresh_choice","defer_choice"]:
		var session=state.players[0].sessions.get(R136Slots.normalize(self,state.players[0],str(args.get("category",""))),{})
		return str(session.get("root_action_id",""))==str(undo_checkpoint.root)
	return false
func undo_changed(before: Dictionary) -> bool:
	# Events, receipts and root bookkeeping alone are not a new player action.
	var left=before.duplicate();var right=state.duplicate()
	for key in ["revision","event_seq","active_root","confirmation_tickets"]:left.erase(key);right.erase(key)
	return left!=right
func undo_last() -> Dictionary:
	var info=undo_info()
	if not info.available:return {"accepted":false,"error_code":"UNDO_UNAVAILABLE","reason":info.reason,"new_revision":state.revision}
	var checkpoint=undo_history.pop_back()
	state=checkpoint.state;events.resize(int(checkpoint.events));command_log.resize(int(checkpoint.commands))
	spell_history=checkpoint.history;receipts=checkpoint.receipts
	persistence_epoch+=1;persistence_cache={}
	cause="";effect_target={};effect_source={};current_spell={};committing_choice={};power_context={};combat_context={}
	resolution_phase="";cast_destroy_succeeded=false;draining_effects=false;settlement_depth=0;checking_triples=false
	return {"accepted":true,"error_code":"","new_revision":state.revision,"undone":checkpoint.label}
func submit(command: Dictionary) -> Dictionary:
	var id=str(command.get("command_id",""))
	if id.is_empty(): return {"accepted":false,"error_code":"MISSING_COMMAND_ID"}
	if receipts.has(id):
		if receipts[id].command!=command: return {"accepted":false,"error_code":"COMMAND_ID_COLLISION"}
		return receipts[id].response.duplicate(true)
	if int(command.get("expected_revision",-1))!=int(state.revision): return {"accepted":false,"error_code":"STALE_REVISION"}
	var pid=int(command.get("player_id",-1))
	if pid<0 or pid>=8: return {"accepted":false,"error_code":"INVALID_PLAYER"}
	var kind=str(command.get("kind",""))
	if kind=="undo":return undo_last() if pid==0 else {"accepted":false,"error_code":"NOT_HOST"}
	var clock_command=str(command.get("kind","")) in ["tick","pause","wheel_advance"]
	if clock_command and (pid!=0 or state.phase!="recruit"):return {"accepted":false,"error_code":"NOT_HOST" if pid!=0 else "WRONG_PHASE"}
	var before={} if clock_command else action_state()
	var event_start=events.size()
	# History entries are immutable; only append/pop_front changes this array.
	var history_before=[] if clock_command else spell_history.duplicate()
	var root_kinds=["buy","sell","play","fast_play","fast_play_sell","move","shop_move","refresh","upgrade","power","activate","freeze","open_choice","resolve_choice","refresh_choice","defer_choice","choose","choose_target","confirm_action","cancel_confirmation","cancel_choice"]
	var capture=undo_tracking_enabled and pid==0 and not command.get("internal",false) and kind in root_kinds and undo_ready() and not undo_continuation(kind,command.get("payload",{}))
	# Reuse the transaction rollback state; append-only records need only a cursor.
	var checkpoint={"state":before,"events":event_start,"commands":command_log.size(),"history":history_before,"receipts":receipts.duplicate(),"round":state.round,"root":id,"label":kind} if capture else {}
	cause=id
	if pid==0 and not clock_command and not state.has("active_root"):
		state["active_root"]=id;state["confirmation_tickets"]={}
	settlement_depth+=1
	var error=apply_command(state.players[pid],str(command.get("kind","")),command.get("payload",{}))
	settlement_depth-=1
	if error.is_empty() and state.phase=="recruit" and state.players[pid].alive and not clock_command:
		R132.changed(self,state.players[pid])
		R133.changed(self,state.players[pid])
		if str(command.get("kind","")) not in ["wheel_skip","wheel_present"]:R134.advance(self,state.players[pid])
		check_triples(state.players[pid])
		if state.players[pid].board.size()>capacity(state.players[pid].board):error="RESULT_EXCEEDS_CAPACITY"
	if not error.is_empty():
		state=before
		events.resize(event_start)
		spell_history=history_before
		return {"accepted":false,"error_code":error,"new_revision":state.revision}
	settle_recruit_deaths()
	if not clock_command:
		for player in state.players:
			if player.alive:drain_rewards(player)
	R132.resume_devour(self)
	if not clock_command and pid==0 and settlement_depth==0 and state.has("auto_chain") and not state.has("confirmation"):advance_auto_chain(state.players[0])
	if state.has("round_start_cursor"):advance_round_start()
	if state.has("recruit_end_pending"):finish_recruit_end()
	else:
		for player in state.players:R135.safe(self,player)
	if pid==0 and not clock_command and state.players[0].choices.is_empty() and not state.has("confirmation") and not state.has("auto_chain") and not state.has("recruit_end_pending"):
		state.erase("active_root");state["confirmation_tickets"]={}
	state.revision+=1
	var result={"accepted":true,"error_code":"","new_revision":state.revision,"event_start":event_start,"event_end":events.size()}
	receipts[id]={"command":command.duplicate(true),"response":result.duplicate(true)}
	if not command.get("internal",false): command_log.append(command.duplicate(true))
	if kind in ["end","continue"] or state.phase!="recruit" or (not before.is_empty() and int(state.round)!=int(before.round)):
		undo_history.clear()
	elif capture and undo_changed(before):
		undo_history.append(checkpoint)
		if undo_history.size()>UNDO_HISTORY_LIMIT:undo_history.pop_front()
	return result
func act(pid: int,kind: String,payload: Dictionary={}) -> Dictionary:
	return submit({"command_id":"local:"+str(int(state.revision)+1)+":"+str(pid)+":"+kind,"expected_revision":state.revision,"player_id":pid,"kind":kind,"payload":payload})
func apply_command(p: Dictionary,kind: String,args: Dictionary) -> String:
	if state.has("devour_tail") and kind not in ["choose","choose_target","confirm_action","cancel_confirmation","tick","pause","wheel_advance","wheel_skip","wheel_present"]:return "DEVOUR_SETTLEMENT_PENDING"
	if state.has("round_start_cursor") and kind not in ["choose","choose_target","confirm_action","cancel_confirmation","tick","pause"]:return "TURN_START_PENDING"
	if state.has("recruit_end_pending"):
		if kind=="end":finish_recruit_end();return ""
		if kind not in ["choose","choose_target","confirm_action","cancel_confirmation","tick","pause","wheel_advance","wheel_skip","wheel_present"]:return "MANDATORY_CHOICE"
	
	if kind in ["sell","auto_sell","fast_play_sell"] and R134.sale_blocked(p):return "WHEEL_ANIMATION_PENDING"
	if R134.sale_blocked(p):
		if kind in ["play","fast_play"]:
			var i=find_index(p.hand,int(args.get("instance_id",-1)))
			if i>=0 and play_definition(p.hand[i]).get("effects",[]).any(func(e):return e.get("op","") in ["avalanche","invoke"]):return "WHEEL_ANIMATION_PENDING"
		if kind=="power":
			var slot=Powers.selected(self,p,int(args.get("slot_id",0)))
			if slot.get("active_power_id","")=="BG20_HERO_301p":return "WHEEL_ANIMATION_PENDING"
		if kind in ["choose","choose_target"] and not p.choices.is_empty() and p.choices[0].get("kind","")=="r132_target" and p.choices[0].get("op","")=="swallow":return "WHEEL_ANIMATION_PENDING"
	var right_action=kind=="fast_play" and args.get("right_click",false) or kind=="sell" and args.get("right_click",false)
	if int(p.id)==0 and int(state.get("fast_mode_level",0))==2 and not state.has("auto_chain") and p.choices.is_empty() and right_action:
		state["auto_chain"]=Fast.chain(self,p,"play_only",int(args.get("instance_id",-1)))
	var error=_apply_command(p,kind,args)
	if error=="" and state.has("auto_chain") and kind in ["play","fast_play","fast_play_sell"] and not p.choices.is_empty():
		var choice=p.choices[0]
		if choice.get("from_hand",false) and Choices.eligible(self,p,choice).is_empty():return "NO_LEGAL_TARGET"
	return error
func resolve_combat_power_choice(p: Dictionary,args: Dictionary) -> String:
	var choice=p.choices[0]
	if args.has("session_id") and str(args.session_id)!=str(choice.get("session_id","")):return "STALE_CHOICE"
	if int(choice.get("combat_round",state.round))!=int(state.round):return "STALE_COMBAT_CHOICE"
	var slot=Powers.selected(self,p,int(choice.slot_id))
	if slot.is_empty() or slot.active_power_id!="BG21_HERO_000p" or int(slot.epoch)!=int(choice.epoch):return "STALE_POWER_EPOCH"
	var index=int(args.get("index",-1))
	if index<0 or index>=choice.options.size():return "INVALID_OPTION"
	if choice.options[index].def_id not in ["BG21_HERO_000p_t1","BG21_HERO_000_Buddyt","BG21_HERO_000_Buddyt2"]:return "INVALID_OPTION"
	return R132.resolve(self,p,choice,index)
func resolve_acquisition_choice(p: Dictionary,choice: Dictionary,index: int) -> String:
	if R132.cat_copy(choice):
		var error=R132.cat_reward_error(self,p,choice)
		if error!="":return error
		
		
		var origin=Acquisition.context(self,{"def_id":"TB_BaconShop_HP_080"},"cat_elimination_reward")
		origin["eliminated_player_id"]=int(str(choice.copy_source).trim_prefix("eliminated:"))
		origin["selection_session_id"]=str(choice.session_id)
		var delivered=receive_card(p,choice.options[index],origin)
		if delivered not in ["granted","queued"]:return "CAT_REWARD_NOT_RECEIVED"
		for i in choice.options.size():
			if i!=index:return_pool(choice.options[i])
		p.choices.pop_front()
		if not p.has("cat_rewards_claimed"):p["cat_rewards_claimed"]={}
		p.cat_rewards_claimed[str(choice.copy_source).trim_prefix("eliminated:")]=str(choice.session_id)
		Fish.discovered(self,p,choice.options[index]);check_triples(p);emit("ChoiceResolved",int(p.id));Pirates.discovered(self,p)
		return ""
	var discovery_snapshot={}
	for i in choice.options.size():
		if i==index:
			R13Items.selected(self,p,choice,choice.options[i])
			discovery_snapshot=choice.options[i].duplicate(true)
			receive_card(p,choice.options[i],choice.get("acquisition_source",Acquisition.context(self,{},"ordinary")))
			if choice.kind=="demon_damage":Demons.hurt(self,p,int(content.get_def(choice.options[i].def_id).tier),choice.get("damage_source",{}))
		else:return_pool(choice.options[i])
	p.choices.pop_front()
	R135.discovered(self,p,discovery_snapshot,str(choice.kind),str(choice.get("session_id","")))
	Fish.discovered(self,p,choice.options[index]);check_triples(p);emit("ChoiceResolved",int(p.id));Pirates.discovered(self,p)
	return ""
func resolve_combat_cat_choice(p: Dictionary,args: Dictionary) -> String:
	var choice=p.choices[0]
	if args.has("session_id") and str(args.session_id)!=str(choice.get("session_id","")):return "STALE_CHOICE"
	var error=R132.cat_reward_error(self,p,choice)
	if error!="":return error
	var index=int(args.get("index",-1))
	if index<0 or index>=choice.options.size():return "INVALID_OPTION"
	return resolve_acquisition_choice(p,choice,index)
func _apply_command(p: Dictionary,kind: String,args: Dictionary) -> String:
	if kind=="fast_play":
		if int(p.id)!=0 or state.phase!="recruit":return "WRONG_PHASE"
		if int(state.get("fast_mode_level",0))!=2:return "FAST_MODE_DISABLED"
		var i=find_index(p.hand,int(args.get("instance_id",-1)))
		if i<0:return "CARD_NOT_IN_HAND"
		if args.get("right_click",false):
			var classification=Fast.classify(self,p,p.hand[i])
			if not classification.reasons.is_empty() or classification.unknown_dynamic:return "FAST_EFFECT_REQUIRES_MANUAL"
		return _apply_command(p,"play",args)
	if kind=="auto_sell":
		if not state.has("auto_chain"):return "NO_AUTO_CHAIN"
		var chain=state.auto_chain
		if chain.get("mode","")!="play_then_sell" or chain.sold or int(args.instance_id)!=int(chain.instance_id) or chain.root_action_id!=state.get("active_root",""):return "INVALID_AUTO_SALE"
		var i=find_index(p.board,int(args.instance_id));var card={} if i<0 else p.board[i]
		state.auto_chain.sold=true
		if not card.is_empty():sell_card(p,card)
		return ""
	if kind in ["confirm_action","cancel_confirmation"]:return Continuation.resolve(self,p,args,kind=="cancel_confirmation")
	if state.has("confirmation") and kind=="wheel_advance":return ""
	if state.has("confirmation") and int(p.id)==0 and kind not in ["tick","pause"]:return "AWAIT_CONFIRMATION"
	if kind=="fast_play_sell":return start_auto_chain(p,int(args.get("instance_id",-1)))
	if kind in ["sell","activate","play"] and Core.enabled(self,p):
		var target=find_target(p,int(args.get("instance_id",-1))) if kind=="sell" else find_target(p,int(args.get("target_id",-1)))
		var action="sell" if kind=="sell" else "destroy"
		var destructive=kind=="sell"
		if kind=="activate" and not target.is_empty():
			var source=find_target(p,int(args.get("instance_id",-1)))
			destructive=not source.is_empty() and content.get_def(source.def_id).effects.any(func(e):return e.handler=="activate_destroy")
		if kind=="play":
			var validation=validate_hand_play(p,args)
			if not validation.is_empty():return validation
			var i=find_index(p.hand,int(args.get("instance_id",-1)))
			if i>=0:
				var d=play_definition(p.hand[i])
				if d.kind=="spell":
					for spec in d.effects:
						if spec.get("op","") in ["avalanche","invoke"]:action="sell";destructive=true
						if spec.handler in ["slaughter","destroy_generate"]:destructive=true
		if destructive and Continuation.request(self,p,target,action,{"kind":"command","command":kind,"payload":args}):return ""
	if kind=="continue":
		if int(p.id)!=0 or state.phase!="combat": return "WRONG_PHASE"
		if not p.choices.is_empty() and (p.choices[0].kind=="r132_conviction" or R132.cat_copy(p.choices[0])):return "MANDATORY_CHOICE"
		next_round(); return ""
	if kind=="choose" and state.phase=="combat" and p.alive and not state.results.is_empty() and not p.choices.is_empty() and R132.cat_copy(p.choices[0]):
		return resolve_combat_cat_choice(p,args)
	if kind=="choose" and state.phase=="combat" and p.alive and not state.results.is_empty() and not p.choices.is_empty() and p.choices[0].kind=="r132_conviction":
		return resolve_combat_power_choice(p,args)
	if state.phase!="recruit" or (not p.alive and kind not in ["end","tick","pause"]): return "WRONG_PHASE"
	if kind=="reward_anomaly":R133.anomaly_command(p,bool(args.get("closed",true)));return ""
	if kind=="pause":
		if int(p.id)!=0: return "NOT_HOST"
		state.paused=not state.paused; return ""
	if kind=="wheel_advance":
		if int(p.id)!=0:return "NOT_HOST"
		if not state.paused:
			for player in state.players:
				if player.alive:
					var task=R134.presenting(player)
					R134.advance(self,player,64 if task.get("skip_requested",false) else 8,false)
		if state.get("r134_end_requested",false) and not state.players.any(func(player):return R134.pending(player)):
			state.erase("r134_end_requested");return _apply_command(p,"end",{})
		return ""
	if kind=="wheel_skip":return R134.skip_animation(p,str(args.get("receipt","")))
	if kind=="wheel_present":
		R134.ensure(p)
		for task in p.r134.wheel:
			if task.receipt==str(args.get("receipt","")):
				task.ui_elapsed=maxf(float(task.ui_elapsed),float(args.get("elapsed",0)));task.ui_phase=str(args.get("phase","spin"));task.read=bool(args.get("read",false))
		return ""
	if kind=="tick":
		if int(p.id)!=0: return "NOT_HOST"
		if not state.paused:
			for player in state.players:
				if player.alive:R134.advance(self,player,1,false)
		if not state.paused: state.remaining_ms=maxi(0,int(state.remaining_ms)-clampi(int(args.get("ms",0)),0,1000))
		return ""
	if kind=="cancel_choice":
		if not p.choices.is_empty() and p.choices[0].kind=="r132_target":
			p.choices.pop_front();stop_auto_chain("CHOICE_CANCELLED");return ""
		if p.choices.is_empty() or not p.choices[0].get("round8",false) or not p.choices[0].get("from_hand",false):return "NO_CANCELLABLE_CHOICE"
		state.next_instance=int(p.choices[0].root.choice_before_instance)
		p.choices.pop_front();stop_auto_chain("CHOICE_CANCELLED");return ""
	if kind=="choose_target":
		var error=choice_target_error(p,args)
		if error!="":return error
		if p.choices[0].kind=="r132_target":
			var choice=p.choices[0]
			return R132.resolve(self,p,choice,choice.options.find_custom(func(c):return int(c.instance_id)==int(args.target_id)))
		return Quilboar.resolve_choice(self,p,p.choices[0],args)
	if kind=="choose":
		if p.choices.is_empty(): return "NO_CHOICE"
		var choice=p.choices[0]
		if args.has("session_id") and str(args.session_id)!=str(choice.get("session_id","")):return "STALE_CHOICE"
		var index=int(args.get("index",-1))
		if index<0 or index>=choice.options.size(): return "INVALID_OPTION"
		if choice.get("round8",false):return Quilboar.resolve_choice(self,p,choice,args)
		var new_choice=R136.resolve(self,p,choice,index)
		if new_choice!="UNHANDLED":return new_choice
		var quest_choice=R135.resolve(self,p,choice,index)
		if quest_choice!="UNHANDLED":return quest_choice
		var r134_choice=R134.resolve(self,p,choice,index)
		if r134_choice!="UNHANDLED":return r134_choice
		var r133_choice=R133.resolve(self,p,choice,index)
		if r133_choice!="UNHANDLED":return r133_choice
		var power_choice=R132.resolve(self,p,choice,index)
		if power_choice!="UNHANDLED":return power_choice
		if choice.kind in ["r13_replace","r13_transform"]:return R13Items.special_choice(self,p,choice,index)
		if choice.kind=="round13_gold_target":return R13.resolve_target(self,p,choice,index)
		if choice.kind=="gold_route":
			var source=find_target(p,int(choice.source_instance))
			if source.is_empty(): return "ROUTE_SOURCE_MISSING"
			grant_gold(p,source,str(choice.options[index]));p.choices.pop_front();return ""
		if choice.kind=="choose_one":
			p.choices.pop_front()
			var selected=content.get_def(choice.options[index].def_id)
			var previous_phase=resolution_phase;resolution_phase=choice.get("resolution_phase","")
			var previous_spell=current_spell;current_spell=choice.get("spell_context",{})
			var choice_target=find_target(p,int(choice.get("target_instance",-1)))
			for spec in selected.effects:effect(p,spec,choice_target,choice.get("source",{}))
			current_spell=previous_spell
			resolution_phase=previous_phase
			emit("ChoiceEffectResolved",int(p.id),{"id":selected.id});return ""
		return resolve_acquisition_choice(p,choice,index)
	if not p.choices.is_empty(): return "MANDATORY_CHOICE"
	if kind in ["open_choice","defer_choice","refresh_choice","resolve_choice"]:
		return Selection.command(self,p,kind,args)
	if kind=="end":
		if int(p.id)!=0: return "NOT_HOST"
		for player in state.players:
			if player.alive:R134.advance(self,player,32,false)
		if state.players.any(func(player):return R134.pending(player)):
			state["r134_end_requested"]=true;state.paused=false;return ""
		
		state.paused=false
		for i in range(1,8):
			if state.players[i].alive: run_ai(i)
		
		cause="round:"+str(state.round)
		state["triples_deferred_round"]=int(state.round)
		resolution_phase="turn_end"
		for player in state.players:
			if player.alive:
				Selection.close_recruit(self,player)
				R134.end(self,player)
				Naga.expire(self,player)
				trigger(player,"turn_end",{})
				trinket_effects(player,"turn_end")
				Gifts.boundary(self,player,"turn_end")
				Heroes7.end(self,player)
				Pirates.end(self,player)
		for player in state.players:
			if player.alive:drain_effects();R132.last_end(self,player)
		resolution_phase=""
		state["recruit_end_pending"]={"powers_restored":false}
		finish_recruit_end();return ""
	if int(state.round)<int(p.get("skip_recruit_until",0)) and kind not in ["freeze","choose"]:return "RECRUIT_SKIPPED"
	if kind=="freeze":
		p.frozen=not p.frozen; emit("FreezeChanged",int(p.id)); return ""
	if kind=="refresh":
		if p.trinkets.any(func(v):return v.id=="BG35_MagicItem_930" and v.get("whistle_ready",false)):
			R13Items.button_refresh(self,p);return ""
		var payment=Payment.refresh(self,p)
		if not payment.available:return str(payment.reason)
		var cost=int(payment.cost)
		var plan=payment.plan
		if plan.life:
			if int(p.health)+int(p.armor)<cost:return "NOT_ENOUGH_HEALTH"
			var source=plan.card
			if int(source.get("prince_round",-1))!=int(state.round):source["prince_round"]=int(state.round);source["prince_used"]=0
			source.prince_used+=1;Demons.hurt(self,p,cost)
		else:
			if int(p.coins)<cost:return "NOT_ENOUGH_COINS"
			p.coins-=cost;Elementals.spent(self,p,cost)
		if cost==0: p.free_refresh-=1
		if not R13Items.button_refresh(self,p):refill_shop(p,false)
		return ""
	if kind=="upgrade":
		if int(p.tier)>=6: return "MAX_TIER"
		if int(p.coins)<int(p.upgrade_cost): return "NOT_ENOUGH_COINS"
		var spent=int(p.upgrade_cost)
		p.coins-=spent; p.tier+=1
		Elementals.spent(self,p,spent)
		p.upgrade_cost=int(content.rules.upgrade_costs[int(p.tier)-1])
		if has_handler(p,"upgrade_coins"): gain_coins(p,2)
		trinket_effects(p,"upgraded")
		emit("TavernUpgraded",int(p.id),{"tier":p.tier}); return ""
	if kind=="buy":
		var index=find_index(p.shop,int(args.get("instance_id",-1)))
		if index<0: return "CARD_NOT_IN_SHOP"
		if p.hand.size()>=16: return "HAND_FULL"
		var card=p.shop[index]
		var d=content.get_def(card.def_id)
		var payment=Payment.buy(self,p,card)
		if not payment.available:return str(payment.reason)
		var cost=int(payment.cost)
		var payment_plan=payment.plan
		var life_payment=payment_plan.life
		if life_payment:
			var armor_cost=mini(int(p.armor),cost)
			var life_cost=cost-armor_cost
			if int(p.health)<life_cost:return "NOT_ENOUGH_HEALTH"
			Demons.hurt(self,p,cost)
			emit("HealthPurchasePaid",int(p.id),{"cost":cost,"armor":armor_cost,"health":life_cost})
		else:
			if p.coins<cost: return "NOT_ENOUGH_COINS"
			p.coins-=cost
		var ticket_fact=R133.capture(self,p,card)
		p.shop.remove_at(index);Fish.leave_shop(card);R133.strip(card);p.hand.append(card)
		emit("HandEntered",int(p.id),{"instance_id":card.instance_id,"id":card.def_id})
		R135.bought(self,p,card,d)
		R133.acquired(self,p,card,ticket_fact)
		if not life_payment:Elementals.spent(self,p,cost)
		for source in p.board:
			if d.kind=="minion" and source.has("next_purchase_multiplier"):
				var value=Elementals.Gain.from_source(self,p,stats(card)*int(source.next_purchase_multiplier),{},source);buff(source,value.x,value.y);source.erase("next_purchase_multiplier")
		if d.kind=="minion":
			Pirates.obtained(self,p,card)
			if Undead.tribe(self,card,"海盗"):p["pirate_buy_round"]=int(state.round)
			if has_handler(p,"hogg") and Undead.tribe(self,card,"海盗"):gain_coins(p,1)
		R13.bought(self,p,card)
		check_triples(p)
		Heroes7.bought(self,p,d)
		emit("CardBought",int(p.id),{"id":card.def_id,"instance_id":card.instance_id,"kind":d.kind,"types":d.get("card_types",[]),"cost":cost,"base_cost":d.get("cost",3)})
		if d.kind=="minion":trinket_effects(p,"minion_bought",card)
		Fish.bought(self,p,card);R13Items.bought(self,p)
		Demons.bought(self,p,payment_plan)
		check_triples(p); return ""
	if kind=="play":
		var token_index=find_index(p.hand,int(args.get("instance_id",-1)))
		if token_index>=0 and R133.token_blocked(self,p,p.hand[token_index]):return ""
		if token_index>=0 and R134.blocked(self,p,p.hand[token_index]):return ""
		var play_error=validate_hand_play(p,args)
		if not play_error.is_empty(): return play_error
		var index=find_index(p.hand,int(args.get("instance_id",-1)))
		if index<0: return "CARD_NOT_IN_HAND"
		var card=p.hand[index]
		var d=play_definition(card)
		var empty_beetle=Quilboar.choice(d) and committing_choice.is_empty() and Quilboar.empty_beetle(self,p,card)
		if Quilboar.choice(d) and committing_choice.is_empty() and not empty_beetle:
			Quilboar.begin_hand(self,p,card,args);return ""
		if empty_beetle:
			d=d.duplicate(true);d["selected_choice_ids"]=[]
			var ds=Quilboar.double_source(self,p,d)
			var quota_card=find_target(p,int(ds.get("quota_instance",-1)))
			if not quota_card.is_empty():quota_card.choice_quota=maxi(0,Quilboar.quota(self,quota_card)-1)
			committing_choice=d
		var play_listeners={}
		for listener in p.board:play_listeners[int(listener.instance_id)]=card_gifts(listener).duplicate(true)
		if d.kind=="minion":
			var victim=find_target(p,int(args.get("target_id",-1)))
			if d.effects.any(func(e):return e.handler=="magnetic") and not victim.is_empty():
				if not legal_magnetic_target(p,card,victim): return "MAGNETIC_TARGET_REQUIRED"
				p.hand.remove_at(index); attach_magnetic(p,victim,card)
				emit("CardPlayedFromHand",int(p.id),{"id":d.id,"instance_id":card.instance_id})
				gift_card_played(p,card,play_listeners); grant_triple_reward(p,card); return ""
			if p.board.size()>=Special.capacity(p.board): return "BOARD_FULL"
			effect_target=victim
			p.hand.remove_at(index)
			p.board.insert(clampi(int(args.get("index",p.board.size())),0,p.board.size()),card)
			if "元素" in d.card_types or "全部种族" in d.card_types: p.elementals_played+=1
			emit("CardPlayedFromHand",int(p.id),{"id":d.id})
			emit("MinionPlayedFromHand",int(p.id),{"instance_id":card.instance_id,"id":card.def_id,"battlecry":Triggers.effects(self,card).any(func(e):return e.get("trigger","")=="battlecry")})
			Pirates.played(self,p,card)
			grant_gold(p,card)
			automaton_summoned(p,card)
			Beasts.summoned(self,p,card)
			Naga.recruit_entered(self,p,card)
			trigger(p,"minion_played",card)
			trinket_effects(p,"minion_played",card)
			gift_card_played(p,card,play_listeners)
			run_effects(p,card,"battlecry")
			if state.has("confirmation"):
				state["play_tail"]={"owner":p.id,"instance_id":card.instance_id,"card":card,"choice_play":true};return ""
			if not empty_beetle:run_effects(p,card,"choice_play",{},true,1)
			effect_target={}
			if empty_beetle:
				committing_choice={};Quilboar.choice_used(self,p,d,card)
			if int(card.get("grave_round",0))==int(state.round): Undead.recruit_destroy(self,p,card)
			if state.has("confirmation"):
				state["play_tail"]={"owner":p.id,"instance_id":card.instance_id,"card":card,"choice_play":false};return ""
			grant_triple_reward(p,card)
			Demons.feed(self,p)
		else:
			var target=find_target(p,int(args.get("target_id",-1)))
			if Quilboar.choice(d):
				Quilboar.begin_hand(self,p,card,args);return ""
			if not Naga.valid_target(self,p,d,target):return "INVALID_SPELL_TARGET"
			if d.effects[0].get("target","none")=="minion" and target.is_empty(): return "TARGET_REQUIRED"
			if d.effects[0].get("target","")=="friendly_undead" and not Undead.valid_victim(self,p,target): return "FRIENDLY_UNDEAD_REQUIRED"
			p.hand.remove_at(index)
			emit("CardPlayedFromHand",int(p.id),{"id":d.id})
			gift_card_played(p,card,play_listeners)
			var spell=d.duplicate(true)
			spell["played_from_hand"]=true
			spell["r134_card"]=card
			if card.get("permanent_spellcraft",false): spell["permanent_spellcraft"]=true
			for key in ["spellcraft_source","spellcraft_source_snapshot","spellcraft_generated_phase","spellcraft_expires_round","strategic_tier","reward_tier","reward_source","reward_key","r133_reward"]:
				if card.has(key):spell[key]=card[key]
			cast(p,spell,target)
			Naga.hand_used(self,p,card)
		Quilboar.hand_used(self,p,card)
		drain_rewards(p); check_triples(p); return ""
	if kind=="activate":
		var index=find_index(p.board,int(args.get("instance_id",-1)))
		if index<0: return "CARD_NOT_ON_BOARD"
		var r6=p.board[index]
		var mode=str(args.get("ability","native"))
		if mode not in ["native","gold"]:return "INVALID_ACTIVATE_ABILITY"
		if mode=="gold" and r6.gold_route!="恶魔":return "NO_GOLD_ROUTE"
		if r6.gold_route=="恶魔" and (mode=="gold" or content.get_def(r6.def_id).effects.filter(func(e):return e.get("trigger","")=="activate").is_empty()):return Demons.activate(self,p,r6,"gold")
		if not Beasts.activate_query(self,p,r6).is_empty():return Beasts.activate(self,p,r6,args)
		if not Fish.activate_query(self,p,r6).is_empty():return Fish.activate(self,p,r6,args)
		if not Demons.activate_query(self,p,r6,"native").is_empty():return Demons.activate(self,p,r6,"native")
		var pirate_operations=Triggers.effects(self,r6).filter(func(e):return e.get("handler","")=="round9" and e.get("trigger","")=="activate")
		if not pirate_operations.is_empty():
			var query=activate_availability(int(p.id),int(r6.instance_id))
			if not query.available:return str(query.reason)
			if int(args.get("target_id",-1))!=-1:return "NO_TARGET_REQUIRED"
			var cost=int(pirate_operations[0].cost);p.coins-=cost;r6["activated_round"]=int(state.round);Elementals.spent(self,p,cost)
			for e in pirate_operations:effect(p,e,r6,r6)
			drain_rewards(p);check_triples(p);emit("MinionActivated",int(p.id),{"instance_id":r6.instance_id});return ""
		var naga_operations=Triggers.effects(self,r6).filter(func(e):return e.get("handler","")=="round7" and e.get("trigger","")=="activate")
		if not naga_operations.is_empty():
			var available=activate_availability(int(p.id),int(r6.instance_id))
			if not available.available:return str(available.reason)
			if int(args.get("target_id",-1))!=-1:return "NO_TARGET_REQUIRED"
			var cost=int(naga_operations[0].cost)
			p.coins-=cost;r6["activated_round"]=int(state.round);Elementals.spent(self,p,cost)
			for e in naga_operations:effect(p,e,r6)
			drain_rewards(p);check_triples(p);emit("MinionActivated",int(p.id),{"instance_id":r6.instance_id});return ""
		var operations=Triggers.effects(self,r6).filter(func(e):return e.get("handler","")=="round6" and e.get("trigger","")=="activate")
		if not operations.is_empty():
			var available=activate_availability(int(p.id),int(r6.instance_id))
			if not available.available: return str(available.reason)
			var target_id=int(args.get("target_id",-1))
			if operations[0].get("target","none") in ["other_friendly","other_minion"] and target_id not in available.targets: return "OTHER_BOARD_TARGET_REQUIRED"
			p.coins-=int(operations[0].cost);r6["activated_round"]=int(state.round)
			Elementals.spent(self,p,int(operations[0].cost))
			effect_target=find_target(p,target_id)
			for e in operations: effect(p,e,r6)
			effect_target={};drain_rewards(p);check_triples(p)
			emit("MinionActivated",int(p.id),{"instance_id":r6.instance_id}); return ""
		var available=activate_availability(int(p.id),int(args.get("instance_id",-1)))
		if not available.available: return str(available.reason)
		var source=p.board[index]
		var effects=content.get_def(source.def_id).effects.filter(func(e):return e.get("trigger","")=="activate")
		if effects.is_empty(): return "NO_ACTIVATE_EFFECT"
		if int(source.get("activated_round",0))==int(state.round): return "ALREADY_ACTIVATED"
		var victim=find_target(p,int(args.get("target_id",-1)))
		if not Undead.valid_different_victim(self,p,victim,source): return "DIFFERENT_FAMILY_REQUIRED"
		if p.coins<int(effects[0].cost): return "NOT_ENOUGH_COINS"
		p.coins-=int(effects[0].cost); source["activated_round"]=int(state.round)
		Elementals.spent(self,p,int(effects[0].cost))
		add_keyword(victim,"REBORN")
		Undead.recruit_destroy(self,p,victim); buff(source,int(effects[0].attack),int(effects[0].health))
		drain_rewards(p); check_triples(p); emit("MinionActivated",int(p.id),{"instance_id":source.instance_id}); return ""
	if kind=="sell":
		var index=find_index(p.board,int(args.get("instance_id",-1)))
		if index<0:return "CARD_NOT_ON_BOARD"
		return "" if sell_card(p,p.board[index]) else "CARD_NOT_ON_BOARD"
	if kind=="move":
		var index=find_index(p.board,int(args.get("instance_id",-1)))
		if index<0: return "CARD_NOT_ON_BOARD"
		var dest=clampi(int(args.get("index",index)),0,p.board.size()-1)
		var card=p.board.pop_at(index); p.board.insert(dest,card)
		emit("BoardReordered",int(p.id)); return ""
	if kind=="power": return use_power(p,args)
	if kind=="shop_move":
		var error=shop_move_error(p,args)
		if error!="":return error
		var slots=[];var minions=[]
		for i in p.shop.size():
			if content.get_def(p.shop[i].def_id).kind=="minion":slots.append(i);minions.append(p.shop[i])
		var from=find_index(minions,int(args.instance_id));var card=minions.pop_at(from);var dest=int(args.index);minions.insert(dest,card)
		for i in slots.size():p.shop[slots[i]]=minions[i]
		emit("ShopReordered",int(p.id),{"instance_id":card.instance_id,"from":from,"to":dest,"order":minions.map(func(c):return c.instance_id)});return ""
	return "UNKNOWN_COMMAND"
func hero_handler(p: Dictionary) -> String:
	return Powers.handler(self,p)
func active_powers(p: Dictionary) -> Array:
	return Powers.active(self,p)
func has_power(p: Dictionary,id: String) -> bool:
	return Powers.owns(self,p,id)
func has_handler(p: Dictionary,handler: String) -> bool:
	return Powers.has_handler(self,p,handler)
func power_definition(p: Dictionary) -> Dictionary:
	return Powers.definition(self,p)
func power_cost(p: Dictionary) -> int:
	return R132.cost(self,p,Powers.selected(self,p))
func power_used(p: Dictionary,whole_game: bool=false) -> bool:
	return Powers.used(self,p,whole_game)>0
func consume_power(p: Dictionary,whole_game: bool=false) -> void:
	Powers.consume(self,p,whole_game)
func use_power(p: Dictionary,args: Dictionary) -> String:
	var slot_id=int(args.get("slot_id",0));var slot=Powers.selected(self,p,slot_id)
	if slot.is_empty():return "INVALID_POWER_SLOT"
	if args.has("epoch") and int(args.epoch)!=int(slot.epoch):return "STALE_POWER_EPOCH"
	var old=power_context.get(int(p.id),0);power_context[int(p.id)]=slot_id
	var result=_use_power(p,args)
	power_context[int(p.id)]=old
	return result
func _use_power(p: Dictionary,args: Dictionary) -> String:
	var opportunity=R136Slots.power_op(self,p,int(Powers.selected(self,p).get("slot_id",0)))
	if opportunity!="":return R13Items.command(self,p,"open_choice",{"category":opportunity})
	if power_definition(p).get("id","")=="BG30_HERO_304p":return R13Items.command(self,p,"open_choice",{"category":"marin"})
	var h=power_definition(p)
	var handler=hero_handler(p)
	var availability=ActionAvailability.selected_power(self,p)
	if not availability.available: return str(availability.reason)
	if power_definition(p).get("id","") in R133.ROOTS:return R133.use(self,p)
	if power_definition(p).effects.any(func(e):return e.get("handler","")=="round132"):return R132.use(self,p,args)
	if handler in ["snake","teron","sylvanas"]:return Beasts.power(self,p,args)
	if hero_handler(p)=="barov":return Fish.power(self,p,args)
	if hero_handler(p)=="rat":return Demons.use_power(self,p)
	if handler in Pirates.HEROES:return Pirates.use_power(self,p,args)
	if handler in Heroes7.HANDLERS:return Heroes7.use(self,p,args)
	var target=find_target(p,int(args.get("target_id",-1)))
	match handler:
		"xyrella":
			if p.hand.size()>=16: return "HAND_FULL"
			var index=find_index(p.shop,int(args.get("target_id",-1)))
			if index<0 or not ActionAvailability.legal_power_target(self,p,int(args.get("target_id",-1)),handler): return "SHOP_TARGET_REQUIRED"
			var value=stats(target)
			buff(target,2-value.x,2-value.y)
			p.shop.remove_at(index); receive_card(p,target,content.get_def(p.hero_id))
		"coin_cap": increase_coin_cap(p,1)
		"random_spell":
			var pool=random_power_spells(p)
			if pool.is_empty():return "NO_LEGAL_CANDIDATE"
			receive_card(p,make_card(pool[RNG.next(state.streams,"effects",pool.size())],int(p.id)),content.get_def(p.hero_id))
		"reborn":
			if not ActionAvailability.legal_power_target(self,p,int(args.get("target_id",-1)),handler): return "TARGET_REQUIRED"
			add_keyword(target,"REBORN","next_turn")
		"golden":
			if not ActionAvailability.legal_power_target(self,p,int(args.get("target_id",-1)),handler): return "BOARD_TARGET_REQUIRED"
			var d=content.get_def(target.def_id)
			if d.golden or d.golden_id=="": return "ALREADY_GOLDEN"
			target.def_id=d.golden_id;qualify_gold(target,"hero_golden")
			
			var old_instance=int(target.instance_id)
			target.instance_id=int(state.next_instance);state.next_instance+=1;target.erase("shaker_round")
			emit("CardTransformed",int(p.id),{"previous_instance":old_instance,"instance_id":target.instance_id,"id":target.def_id})
			Naga.recruit_entered(self,p,target)
			Powers.ledger(self,p).game_used=1
		_: return "POWER_NOT_IMPLEMENTED"
	p.coins-=power_cost(p); consume_power(p)
	Elementals.spent(self,p,power_cost(p))
	check_triples(p)
	emit("HeroPowerUsed",int(p.id),{"hero":p.hero_id})
	return ""
func trigger(p: Dictionary,trigger_name: String,subject: Dictionary) -> void:
	
	for card in p.board.duplicate(): run_effects(p,card,trigger_name,subject,false)
	drain_effects()
func run_effects(p: Dictionary,card: Dictionary,trigger_name: String,subject: Dictionary={},drain: bool=true,override_times: int=-1) -> void:
	var selected=Triggers.deathrattle_effects(self,card) if trigger_name=="deathrattle" else Triggers.effects(self,card).filter(func(e):return e.get("trigger","")==trigger_name)
	if trigger_name=="battlecry":
		var choices=selected.filter(func(e):return e.get("op","")=="choice")
		selected=selected.filter(func(e):return e.get("op","")!="choice")
		for spec in choices:effect(p,spec,card,card)
	var repeated=[]
	var sale_target=Fish.learned_sale_target(self,p,card) if trigger_name=="battlecry" and Fish.learned_sale(self,card) else -2
	for unused in (Triggers.times(self,p,trigger_name) if override_times<0 else override_times): repeated.append_array(selected.duplicate(true))
	if not selected.is_empty() and trigger_name in ["battlecry","deathrattle"]:
		count_trigger(p,trigger_name,Triggers.times(self,p,trigger_name) if override_times<0 else override_times)
		if trigger_name=="battlecry":emit("BattlecryTriggered",int(p.id),{"source_instance":card.instance_id,"times":Triggers.times(self,p,trigger_name) if override_times<0 else override_times})
	for e in repeated:
		if e.get("trigger","")!=trigger_name: continue
		if e.get("exclude_source",false) and int(subject.get("instance_id",-1))==int(card.instance_id): continue
		if e.has("tribe") and trigger_name in ["minion_played","minion_sold"]:
			if subject.is_empty(): continue
			var types=card_types(subject)
			if e.tribe not in types and "全部种族" not in types: continue
		var selected_target=effect_target
		if sale_target!=-2:
			e["learned_sale_target"]=sale_target;selected_target=Fish.learned_sale_card(self,p,sale_target)
		if sale_target==-2 and trigger_name=="battlecry" and selected_target.is_empty() and e.get("target","") in ["minion","friendly_minion","friendly_undead"]:
			var candidates=battlecry_candidates(p,card,e)
			if candidates.is_empty():emit("BattlecrySkippedNoTarget",int(p.id),{"source_instance":card.instance_id});continue
			selected_target=candidates[0] if legacy_auto_target() and int(p.id)==0 else candidates[RNG.next(state.streams,"effects",candidates.size())]
		state.effect_queue.append({"owner":int(p.id),"source_instance":int(card.instance_id),"target":card,"source":card,"effect_target":selected_target,"bindings":{"target":queued_binding(card),"source":queued_binding(card),"effect_target":queued_binding(selected_target)},"spec":e.duplicate(true),"root_action_id":state.get("active_root",cause),"trigger":trigger_name,"resolution_phase":resolution_phase if resolution_phase!="" else ("turn_end" if trigger_name=="turn_end" else "")})
	if drain: drain_effects()
func queued_binding(card: Dictionary) -> Dictionary:
	
	if card.is_empty():return {}
	for i in combat_context.get("players",[]).size():
		for live in combat_context.boards[i]:
			if is_same(live,card):return {"scope":"combat","owner":int(combat_context.players[i].id),"zone":"board","instance":int(card.instance_id)}
	for player in state.players:
		for zone in ["board","hand","shop","pending_rewards"]:
			for live in player[zone]:
				if is_same(live,card):return {"scope":"recruit","owner":int(player.id),"zone":zone,"instance":int(card.instance_id)}
	return {} 
func legacy_queued_binding(job: Dictionary,role: String) -> Dictionary:
	
	
	var card=job.get(role,{})
	if card.is_empty() or (role!="effect_target" and (job.get("trigger","")=="sell" or int(card.get("instance_id",-1))!=int(job.get("source_instance",-2)))):return {}
	var owner=int(card.get("owner",job.owner));var instance=int(card.get("instance_id",-1))
	if card.has("attack"):
		for i in combat_context.get("players",[]).size():
			if int(combat_context.players[i].id)!=owner:continue
			for live in combat_context.boards[i]:
				if int(live.instance_id)==instance:return {"scope":"combat","owner":owner,"zone":"board","instance":instance}
		return {}
	if owner<0 or owner>=state.players.size():return {}
	for zone in (["board","shop"] if role=="effect_target" else ["board"]):
		for live in state.players[owner][zone]:
			if int(live.instance_id)==instance and live.def_id==card.get("def_id",""):return {"scope":"recruit","owner":owner,"zone":zone,"instance":instance}
	return {}
func queued_card(job: Dictionary,role: String) -> Dictionary:
	var saved=job.get(role,job.get("target",{}) if role=="source" else {})
	var binding=job.bindings.get(role,{}) if job.has("bindings") else legacy_queued_binding(job,role)
	if binding.is_empty():return saved
	var zone=[];var owner=int(binding.owner)
	if binding.scope=="combat":
		for i in combat_context.get("players",[]).size():
			if int(combat_context.players[i].id)==owner:zone=combat_context.boards[i];break
	elif owner>=0 and owner<state.players.size():zone=state.players[owner].get(binding.zone,[])
	for card in zone:
		if int(card.instance_id)==int(binding.instance):return card
	
	
	return saved
func drain_effects() -> void:
	if draining_effects: return
	draining_effects=true
	var count=0
	while not state.effect_queue.is_empty() and count<4096 and not state.has("confirmation"):
		var job=state.effect_queue.pop_front()
		emit("EffectResolved",int(job.owner),{"source_instance":job.source_instance,"handler":job.spec.handler,"trigger":job.trigger})
		var previous_phase=resolution_phase;resolution_phase=job.get("resolution_phase","")
		var previous_target=effect_target;effect_target=queued_card(job,"effect_target")
		var target=queued_card(job,"target");var source=queued_card(job,"source")
		if not job.spec.has("learned_sale_target") and legacy_auto_target(job.get("root_action_id","")) and job.trigger=="battlecry" and job.spec.get("target","") in ["minion","friendly_minion","friendly_undead"]:
			var live=battlecry_candidates(state.players[int(job.owner)],source,job.spec)
			if live.is_empty():count+=1;effect_target=previous_target;resolution_phase=previous_phase;continue
			effect_target=live[0]
		effect(state.players[int(job.owner)],job.spec,target,source)
		effect_target=previous_target;resolution_phase=previous_phase
		count+=1
	if not state.effect_queue.is_empty() and not state.has("confirmation"):
		state["diagnostic_queue"]=state.effect_queue.duplicate(true)
		state.effect_queue.clear()
		state["rules_error"]="EFFECT_BUDGET"
		state.phase="diagnostic"
		emit("RulesBudgetExceeded",0,{"seed":state.seed,"queue":state.diagnostic_queue})
	draining_effects=false
func effect(p: Dictionary,e: Dictionary,target: Dictionary,source: Dictionary={}) -> void:
	if e.get("handler","")=="round132" and e.get("op","")=="identity":
		R132.discover_power(self,p,"identity",int(p.power_slots[-1].slot_id));return
	if state.has("confirmation"):return
	if Continuation.before_effect(self,p,e,target,source):return
	var previous_source=effect_source
	effect_source=target if source.is_empty() else source
	if not EffectDispatcher.execute(self,p,e,target):
		state["rules_error"]="UNSUPPORTED_RUNTIME_EFFECT:"+str(e.get("handler",""))
		state.phase="diagnostic"
		emit("RulesCapabilityRejected",int(p.id),{"handler":str(e.get("handler","")),"trigger":str(e.get("trigger",""))})
	effect_source=previous_source
func cast(p: Dictionary,spell: Dictionary,target: Dictionary,start_repeat: int=0,start_effect: int=0,resumed: bool=false,frozen_times: int=-1) -> void:
	spell=spell.duplicate(true)
	if not resumed and not Naga.valid_target(self,p,spell,target):return
	var previous_target=effect_target
	if not resumed:
		var aura=spell_aura(p);spell["aura_attack"]=aura.x;spell["aura_health"]=aura.y
		var honey=R13Items.aura(self,p);spell["non_honey_aura_attack"]=aura.x-honey.x;spell["non_honey_aura_health"]=aura.y-honey.y
		if spell.has("reward_key"):
			if not state.has("reward_tokens_used"):state["reward_tokens_used"]={}
			var key=str(spell.reward_key);spell["reward_cast_authorized"]=key!="" and not state.reward_tokens_used.has(key)
			if spell.reward_cast_authorized:state.reward_tokens_used[key]=true
	var automatic=Quilboar.automatic_choice(self,p,spell,target);spell=automatic.spell;target=automatic.target
	var presentation=SpellHistory.context(self,p,spell) if int(p.id)==0 else {}
	var target_view=SpellHistory.actor(self,target) if not target.is_empty() else {}
	effect_target=target
	var friendly=not target.is_empty() and find_index(Undead.board(self,p),int(target.instance_id))>=0
	var times=frozen_times if frozen_times>=0 else (1 if not spell.get("counts_player_cast",true) else 1+R136.extra_cast(self,p,spell)+R13Items.extra_cast(self,p,spell)+Special.extra_casts(Undead.board(self,p),content.definitions,spell,friendly)+Naga.extra(self,p,spell)+Pirates.extra(self,p,spell))
	if spell.get("is_darkmoon_prize",false) or spell.id==R134.TOKEN:times=1
	for i in range(start_repeat,times):
		spell["reward_repeat_index"]=i
		if not (resumed and i==start_repeat):
			var honey=R13Items.aura(self,p);spell.aura_attack=int(spell.get("non_honey_aura_attack",spell.get("aura_attack",0)))+honey.x;spell.aura_health=int(spell.get("non_honey_aura_health",spell.get("aura_health",0)))+honey.y
			if not presentation.is_empty():presentation.spell.aura_attack=spell.aura_attack;presentation.spell.aura_health=spell.aura_health
		if i>start_repeat and not Naga.valid_target(self,p,spell,target):break
		if spell.id=="BG28_830" and Pirates.touch_targets(self,p).is_empty():
			emit("AutomaticSpellUnavailable",int(p.id),{"id":spell.id,"repeat_index":i,"reason":"NO_TOUCH_TARGET"});break
		var player_cast=spell.get("counts_player_cast",true)
		if player_cast and not (resumed and i==start_repeat):p.spell_count+=1
		if player_cast and spell.get("is_tavern_spell",false) and not (resumed and i==start_repeat): p.tavern_spell_count+=1
		if not presentation.is_empty():
			presentation.player.spell_count=int(p.spell_count);presentation.player.tavern_spell_count=int(p.tavern_spell_count)
		if not (resumed and i==start_repeat):emit("SpellCast",int(p.id),{"id":spell.id,"repeat_index":i,"root_cast_id":cause,"is_tavern_spell":spell.get("is_tavern_spell",false),"counts_player_cast":player_cast})
		var previous_spell=current_spell
		current_spell=spell
		effect_target=target
		var friendly_cast=not target.is_empty() and find_index(Undead.board(self,p),int(target.instance_id))>=0
		cast_destroy_succeeded=i>0 and spell.effects[0].handler=="destroy_generate"
		if spell.effects[0].handler=="destroy_generate" and i==0: cast_destroy_succeeded=Undead.valid_victim(self,p,target)
		for ei in range(start_effect if resumed and i==start_repeat else 0,spell.effects.size()):
			effect(p,spell.effects[ei],target,spell)
			if state.has("confirmation"):
				state["cast_tail"]={"spell":spell,"target_instance":target.get("instance_id",-1),"target":target,"repeat":i,"next_effect":ei+1,"times":times}
				current_spell=previous_spell;effect_target=previous_target;return
		current_spell=previous_spell
		if player_cast:trinket_effects(p,"spell_cast",target)
		if spell.get("is_tavern_spell",false):
			if player_cast:p["last_tavern_spell"]=spell.id
			if player_cast:
				trinket_effects(p,"tavern_spell_cast",target)
				trigger(p,"tavern_spell_cast",target)
		if not target.is_empty() and find_index(Undead.board(self,p),int(target.instance_id))>=0: run_effects(p,target,"targeted_spell")
		if player_cast:Naga.spell_resolved(self,p,spell,target);Fish.spell_resolved(self,p,target)
		if player_cast:Quilboar.player_cast(self,p,spell,target)
		R13Items.after_spell(self,p,spell,target,friendly_cast)
		if player_cast:Demons.feed(self,p)
		emit("SpellResolved",int(p.id),{"id":spell.id,"repeat_index":i,"presentation":presentation,"target":target_view})
	effect_target=previous_target
func spell_aura(p: Dictionary) -> Vector2i:
	var value=Naga.aura(self,p)+R13Items.aura(self,p)+R136.aura(self,p)
	for c in Undead.board(self,p):
		for e in Triggers.effects(self,c):
			if e.get("op","")=="spell_aura": value+=Vector2i(int(e.get("attack",0)),int(e.get("health",0)))
	return value
func grant_gold(p: Dictionary,card: Dictionary,selected_route: String="") -> void:
	if card.get("all_tribes",false): return
	var route_def=content.get_def(card.def_id).duplicate();route_def.card_types=card_types(card)
	var routes=Special.eligible_routes(route_def,state.enabled_tribes)
	if routes.is_empty():return
	if card.gold_route=="海盗":Pirates.gold_cards(self,p,{"max_tier":"player_tier","amount":1,"route":true},card);return
	if card.gold_route=="野猪人":Quilboar.gold(self,p,card);return
	if card.gold_route!="": return
	if routes.size()>1 and selected_route=="":
		enqueue_choice(p,{"kind":"gold_route","source_instance":card.instance_id,"options":routes});return
	card.gold_route=selected_route if selected_route in routes else routes[0]
	var previous_keywords=keywords(card)
	match str(card.gold_route):
		"龙": add_keyword(card,"DIVINE_SHIELD"); add_keyword(card,"WINDFURY")
		"元素": add_keyword(card,"WINDFURY")
		"亡灵": add_keyword(card,"REBORN"); card.enhanced_reborn_available=true
		"鱼人":
			if content.get_def(card.def_id).get("base_id","")=="BG33_318":add_keyword(card,"DIVINE_SHIELD");add_keyword(card,"WINDFURY")
			else:add_keyword(card,"VENOMOUS")
		"野猪人": Quilboar.gold(self,p,card)
		"海盗": Pirates.gold_cards(self,p,{"max_tier":"player_tier","amount":1,"route":true},card)
	card["gold_route_added_keywords"]=keywords(card).filter(func(k):return k not in previous_keywords)
	emit("GoldenRouteGranted",int(p.id),{"instance_id":card.instance_id,"route":card.gold_route})
func random_power_spells(p: Dictionary) -> Array:
	return content.pool("spell",state.enabled_tribes).filter(func(id):return int(content.get_def(id).tier)<=int(p.tier))
func check_triples(p: Dictionary) -> void:
	# End receipts stay settled, but their ordinary materials must still fight.
	# State-backed protection survives effect queues, end barriers and saves.
	if checking_triples or resolution_phase=="turn_end" or state.phase=="combat" or state.has("recruit_end_pending") or int(state.get("triples_deferred_round",-1))>=int(state.round):return
	checking_triples=true
	_check_triples(p)
	checking_triples=false
func _check_triples(p: Dictionary) -> void:
	var groups={}
	var surprises=[]
	for c in p.board+p.hand:
		
		if CardLock.locked(self,p,c):continue
		var d=content.get_def(c.def_id)
		if d.kind!="minion" or d.get("golden",false) or d.get("golden_id","")=="": continue
		if not groups.has(d.base_id): groups[d.base_id]=[]
		groups[d.base_id].append(c)
		if d.base_id=="BG26_175": surprises.append(c)
	var ordered=p.board+p.hand
	var candidates=[]
	for id in groups:
		var eligible=groups[id]
		if id!="BG26_175" and Undead.tribe(self,groups[id][0],"元素"):
			eligible=ordered.filter(func(c):return c in groups[id] or c in surprises)
		var needed=2 if R135.has(self,p,"BG24_Reward_350") or has_power(p,"BG34_HERO_002p") or Pirates.has_item(self,p,"two_merge") and Undead.tribe(self,groups[id][0],"海盗") else 3
		var materials=eligible.slice(0,needed)
		if materials.size()<needed or not materials.any(func(c):return c in groups[id]):continue
		candidates.append({"base":id,"materials":materials,"order":materials.map(func(c):return ordered.find(c))})
	
	candidates.sort_custom(func(a,b):
		for i in mini(a.order.size(),b.order.size()):
			if a.order[i]!=b.order[i]:return a.order[i]<b.order[i]
		return str(a.base)<str(b.base))
	for selected in candidates.slice(0,1):
		var id=selected.base;var materials=selected.materials
		var merged=make_card(content.get_def(id).golden_id,int(p.id))
		merged.triple_receipt=true
		merged["triple_reward_key"]="triple:"+str(merged.instance_id)
		for c in materials:
			# A copied ordinary material earns a fresh receipt through merging.
			# The copy's own reward exclusion does not belong to the new gold card.
			if c.has("gold_reward_excluded") and c.gold_reward_excluded!="hero_copy":exclude_gold_reward(merged,str(c.gold_reward_excluded))
			Quilboar.inherited(c,merged)
			merged["behemoth_count"]=int(merged.get("behemoth_count",0))+int(c.get("behemoth_count",0))
			for key in ["parrot_damage","pirate_spent","pirate_obtained"]:
				if c.has(key):merged[key]=maxi(int(merged.get(key,0)),int(c[key]))
			if c.get("parrot_done",false):merged["parrot_done"]=true
			if c.has("discovery_tier"):merged["discovery_tier"]=maxi(int(merged.get("discovery_tier",1)),int(c.discovery_tier))
			if c.has("strategic_tier"):merged["strategic_tier"]=maxi(int(merged.get("strategic_tier",1)),int(c.strategic_tier))
			p.hand.erase(c); p.board.erase(c)
			if c.pool_base==merged.pool_base: merged.pool_copies+=int(c.pool_copies)
			elif int(c.pool_copies)>0:
				if not merged.has("attached_pool"):merged["attached_pool"]=[]
				merged.attached_pool.append({"id":c.pool_base,"copies":c.pool_copies,"source_instance":c.instance_id})
			for gift in card_gifts(c): merged.gifts.append(gift.duplicate(true))
			for m in c.modifiers:
				if m.get("duration","permanent")=="permanent": merged.modifiers.append(m.duplicate(true))
			for attached in c.get("attached_pool",[]):
				if not merged.has("attached_pool"): merged["attached_pool"]=[]
				merged.attached_pool.append(attached.duplicate(true))
			for k in c.extra_keywords:
				if k not in merged.extra_keywords: merged.extra_keywords.append(k)
			for inherited in c.get("attached_effects",[]):
				if not merged.has("attached_effects"): merged["attached_effects"]=[]
				merged.attached_effects.append(inherited.duplicate(true))
		receive_card(p,merged,Acquisition.context(self,{},"triple_body"))
		emit("TripleCreated",int(p.id),{"id":merged.def_id})
		_check_triples(p)
		return
func grant_triple_reward(p: Dictionary,card: Dictionary) -> void:
	if card.has("gold_reward_excluded"):
		exclude_gold_reward(card,str(card.gold_reward_excluded));return
	if not card.get("triple_receipt",false):return
	var key=str(card.get("triple_reward_key","legacy:"+str(card.instance_id)))
	card["triple_reward_key"]=key;card.triple_receipt=false
	if not state.has("triple_rewards_used"):state["triple_rewards_used"]={}
	if state.triple_rewards_used.has(key):return
	state.triple_rewards_used[key]=true
	if R13Items.has(self,p,R134.TOME):
		R134.give(self,p,R134.TOKEN,R134.TOME,key)
		emit("TomeTripleRewardGranted",int(p.id),{"key":key,"source_instance":card.instance_id});return
	if has_power(p,"BG34_HERO_002p"):
		receive_card(p,make_card("BG28_810",int(p.id)),Acquisition.context(self,card,"gold_play_reward"))
		emit("DoubleSpeedCoinGranted",int(p.id),{"key":key,"source_instance":card.instance_id});return
	var reward=make_card("BG_TRIPLE_REWARD_R92",int(p.id))
	reward["reward_tier"]=mini(int(p.tier)+1,6);reward["reward_key"]=key
	reward["reward_source"]={"def_id":card.def_id,"instance_id":card.instance_id,"owner":p.id}
	receive_card(p,reward,Acquisition.context(self,card,"gold_play_reward"))
	emit("TripleRewardCardGranted",int(p.id),{"source_instance":card.instance_id,"instance_id":reward.instance_id,"tier":reward.reward_tier,"key":key})
func discover(p: Dictionary,tier: int,source: Dictionary={}) -> void:
	var eligible=discovery_candidates(p,{"tier":tier},source).filter(func(id):return int(state.pool.get(id,0))>0)
	resolve_discovery(p,eligible,"triple",1,source,false,tier,true)
func resolve_discovery(p: Dictionary,pool: Array,kind: String,amount: int=1,source: Dictionary={},marked: bool=false,tier: int=-1,stock: bool=false) -> void:
	for unused in amount:
		var candidates=pool.filter(func(id):return not stock or int(state.pool.get(id,0))>0)
		if candidates.is_empty():
			emit("EmptyDiscoveryPool",int(p.id),{"kind":kind,"tier":tier});continue
		if resolution_phase=="turn_end":
			var id=candidates[RNG.next(state.streams,"effects",candidates.size())]
			if stock:state.pool[id]-=1
			var card=make_card(id,int(p.id),1 if stock else 0)
			Quilboar.reward_metadata(card,source)
			if marked:card["grave_round"]=int(state.round)
			var discovery_snapshot=card.duplicate(true)
			receive_card(p,card,source)
			R135.discovered(self,p,discovery_snapshot,kind,"converted:"+str(state.event_seq))
			if kind=="demon_damage":Demons.hurt(self,p,int(content.get_def(id).tier),source)
			emit("DiscoveryConverted",int(p.id),{"kind":kind,"id":id,"source_instance":source.get("instance_id",-1),"resolution_phase":resolution_phase})
			Pirates.discovered(self,p);Fish.discovered(self,p,card)
		else:
			var options=[]
			while not candidates.is_empty() and options.size()<3:
				var id=candidates.pop_at(RNG.next(state.streams,"choice",candidates.size()))
				if stock:state.pool[id]-=1
				var card=make_card(id,int(p.id),1 if stock else 0)
				Quilboar.reward_metadata(card,source)
				if marked:card["grave_round"]=int(state.round)
				options.append(card)
			enqueue_choice(p,{"kind":kind,"tier":tier,"options":options,"source_instance":source.get("instance_id",-1),"damage_source":source.duplicate(true),"acquisition_source":Acquisition.context(self,source),"root_action_id":state.get("active_root",cause)})
			emit("ChoiceOpened",int(p.id),{"kind":kind,"marked":marked})
func sale_snapshot(card: Dictionary) -> Dictionary:
	var temporary=[];var sum=Vector2i.ZERO
	for modifier in card.modifiers:
		if modifier.get("duration","permanent")!="permanent":
			var value=Vector2i(int(modifier.get("attack",0)),int(modifier.get("health",0)))
			sum+=value;temporary.append(modifier.duplicate(true))
	var p=state.players[int(card.owner)]
	var aura=Beasts.goldrinn_aura(self,p,card)
	if aura!=Vector2i.ZERO:
		sum+=aura;temporary.append({"attack":aura.x,"health":aura.y,"duration":"next_turn","source":"goldrinn_aura"})
	return {"permanent":stats(card)-sum,"temporary":temporary,"source_instance":card.instance_id}
func transfer_sale_stats(p: Dictionary,snapshot: Dictionary,origin: String) -> void:
	for other in p.board:
		if Undead.tribe(self,other,"元素"):
			for modifier in snapshot.temporary:buff(other,int(modifier.get("attack",0)),int(modifier.get("health",0)),str(modifier.duration),origin)
			buff(other,snapshot.permanent.x,snapshot.permanent.y,"permanent",origin)
			emit("SaleStatsTransferred",int(p.id),{"source_instance":snapshot.source_instance,"target_instance":other.instance_id,"origin":origin})
			return
	emit("SaleStatsNoReceiver",int(p.id),{"source_instance":snapshot.source_instance,"origin":origin})
func sell_card(p: Dictionary,card: Dictionary) -> bool:
	if R134.sale_blocked(p):return false
	var index=find_index(p.board,int(card.get("instance_id",-1)))
	if index<0:return false
	var snapshot=sale_snapshot(card)
	p.board.remove_at(index)
	return_pool(card); gain_coins(p,1)
	Heroes7.sold(self,p);Fish.sold(self,p)
	if card.gold_route=="元素":transfer_sale_stats(p,snapshot,"elemental_sale")
	emit("MinionSold",int(p.id),{"instance_id":card.instance_id,"id":card.def_id})
	run_effects(p,card,"sell")
	if d_has_ball(card):
		p.ball_sold_count+=1
		emit("BallSoldCountChanged",int(p.id),{"count":p.ball_sold_count,"source_instance":card.instance_id})
	trinket_effects(p,"minion_sold",card)
	trigger(p,"minion_sold",card); drain_rewards(p); return true
func player_view(pid: int) -> Dictionary:
	var view={"revision":state.revision,"round":state.round,"phase":state.phase,"self":state.players[pid].duplicate(true),"opponents":[]}
	for p in state.players:
		if int(p.id)!=pid: view.opponents.append({"id":p.id,"health":p.health,"armor":p.armor,"tier":p.tier,"alive":p.alive,"board":p.board.duplicate(true)})
	return view
func run_ai(pid: int) -> void:
	for step in 45:
		var view=player_view(pid)
		var p=view.self
		var action={}
		if not p.choices.is_empty():
			var indices=Choices.eligible(self,state.players[pid],state.players[pid].choices[0]) if p.choices[0].kind in ["r133_route","r133_secret"] else [0]
			if indices.is_empty():return
			action={"kind":"choose","payload":{"index":indices[0]}}
		else:
			for category in ["marin","buttons","lesser","greater","voucher"]:
				if p.sessions.has(category) and not p.sessions[category].resolved:
					for i in p.sessions[category].options.size():
						if int(p.sessions[category].options[i].cost)<=int(p.coins):
							action={"kind":"resolve_choice","payload":{"category":category,"index":i,"revision":p.sessions[category].get("revision",0)}}; break
				elif R13Items.available(self,p,category) and not p.trinkets.any(func(t):return t.get("slot_size",t.size)==category):
					action={"kind":"open_choice","payload":{"category":category}}
				if not action.is_empty(): break
		if action.is_empty() and not p.hand.is_empty():
			var c={}
			
			for held in p.hand:
				if content.get_def(held.def_id).get("unplayable",false):continue
				var held_def=content.get_def(held.def_id)
				if held_def.get("is_darkmoon_prize",false) and held_def.kind=="spell":
					var candidates=[{}] if held_def.effects[0].get("target","none")=="none" else p.board+p.shop
					if candidates.all(func(t):return validate_hand_play(state.players[pid],{"instance_id":held.instance_id,"target_id":t.get("instance_id",-1)})!=""):continue
				var needs_undead=held_def.effects.any(func(e):return e.get("target","")=="friendly_undead")
				if needs_undead and not p.board.any(func(victim):return Undead.valid_victim(self,p,victim,held)): continue
				c=held; break
			var d=content.get_def(c.def_id) if not c.is_empty() else {"kind":"special"}
			if d.get("unplayable",false):d={"kind":"special"}
			if d.kind=="minion" and p.board.size()<Special.capacity(p.board):
				var play_args={"instance_id":c.instance_id}
				for spec in d.effects:
					if spec.get("trigger","")=="battlecry" and spec.get("target","") in ["minion","friendly_minion"]:
						var legal=battlecry_candidates(state.players[pid],c,spec)
						if not legal.is_empty():play_args["target_id"]=legal[0].instance_id
				if d.effects.any(func(e):return e.get("target","")=="friendly_undead"):
					for victim in p.board:
						if Undead.valid_victim(self,p,victim,c): play_args["target_id"]=victim.instance_id; break
				if not d.effects.any(func(e):return e.get("target","")=="friendly_undead") or play_args.has("target_id"): action={"kind":"play","payload":play_args}
			elif d.kind=="spell":
				if d.effects[0].get("target","none")=="none": action={"kind":"play","payload":{"instance_id":c.instance_id}}
				elif d.effects[0].get("target","")=="friendly_undead":
					for victim in p.board:
						if Undead.valid_victim(self,p,victim): action={"kind":"play","payload":{"instance_id":c.instance_id,"target_id":victim.instance_id}}; break
				else:
					for target in p.board+p.shop:
						var play_args={"instance_id":c.instance_id,"target_id":target.instance_id}
						if validate_hand_play(state.players[pid],play_args)=="":action={"kind":"play","payload":play_args};break
			elif d.kind=="minion" and p.board.size()>=Special.capacity(p.board):
				var weakest=p.board[0]
				for b in p.board:
					if stats(b).x+stats(b).y<stats(weakest).x+stats(weakest).y: weakest=b
				if stats(c).x+stats(c).y>stats(weakest).x+stats(weakest).y: action={"kind":"sell","payload":{"instance_id":weakest.instance_id}}
		if action.is_empty():
			for c in p.board:
				for ability in (["native","gold"] if c.gold_route=="恶魔" else ["native"]):
					var available=activate_availability(pid,int(c.instance_id),ability)
					if available.available:
						action={"kind":"activate","payload":{"instance_id":c.instance_id,"ability":ability,"target_id":available.targets[0] if not available.targets.is_empty() else -1}};break
				if not action.is_empty():break
		if action.is_empty() and int(p.tier)<6 and p.coins>=p.upgrade_cost and p.board.size()>=3 and (int(state.round)%2==0 or p.upgrade_cost<=1):
			action={"kind":"upgrade"}
		if action.is_empty() and p.hand.size()<16:
			var best={}
			var score=-1
			for c in p.shop:
				var d=content.get_def(c.def_id)
				if d.kind!="minion" or not Payment.buy(self,state.players[pid],c).available: continue
				var value=stats(c).x+stats(c).y+int(d.tier)
				if p.board.size()>=capacity(p.board) and p.hand.size()>2: continue
				if value>score: score=value; best=c
			if not best.is_empty(): action={"kind":"buy","payload":{"instance_id":best.instance_id}}
		if action.is_empty():
			for slot in state.players[pid].power_slots:
				var available=ActionAvailability.power(self,state.players[pid],int(slot.slot_id))
				if available.available:
					var target_id=int(available.targets[0]) if not available.targets.is_empty() else -1
					if slot.active_power_id=="BG21_HERO_020p":
						# Cookie should cook shop stock, not dismantle its combat board.
						var food={};var food_score=0
						for candidate in p.shop:
							if int(candidate.instance_id) not in available.targets:continue
							var value=stats(candidate).x+stats(candidate).y+int(content.get_def(candidate.def_id).tier)
							if food.is_empty() or value<food_score:food=candidate;food_score=value
						if food.is_empty():continue
						target_id=int(food.instance_id)
					action={"kind":"power","payload":{"slot_id":slot.slot_id,"epoch":slot.epoch}}
					if target_id>=0:action.payload["target_id"]=target_id
					break
		if action.is_empty():
			for c in p.board:
				var available=activate_availability(pid,int(c.instance_id))
				if available.available:
					action={"kind":"activate","payload":{"instance_id":c.instance_id,"target_id":available.targets[0] if not available.targets.is_empty() else -1}};break
				if c.gold_route=="恶魔":
					var gold=activate_availability(pid,int(c.instance_id),"gold")
					if gold.available:action={"kind":"activate","payload":{"instance_id":c.instance_id,"ability":"gold"}};break
		if action.is_empty() and (p.coins>0 or p.free_refresh>0): action={"kind":"refresh"}
		if action.is_empty(): break
		var response=submit({"command_id":"ai:"+str(pid)+":"+str(state.revision),"expected_revision":state.revision,"player_id":pid,"kind":action.kind,"payload":action.get("payload",{}),"internal":true})
		if not response.accepted: break
	for unused in 64:
		if state.players[pid].choices.is_empty(): break
		var choice_response=submit({"command_id":"ai-choice:"+str(pid)+":"+str(state.revision),"expected_revision":state.revision,"player_id":pid,"kind":"choose","payload":{"index":0},"internal":true})
		if not choice_response.accepted:
			emit("AIChoiceRejected",pid,{"reason":choice_response.error_code,"phase":state.phase}); break
func eliminate_player(p: Dictionary,rank: int,origin: String) -> void:
	if not p.alive and int(p.rank)>0:return
	var eliminated=p.board.duplicate(true)
	p["eliminated_board"]=eliminated
	if p.alive:
		for receiver in state.players:
			if receiver.alive and int(receiver.id)!=int(p.id) and has_power(receiver,"TB_BaconShop_HP_080"):
				if eliminated.is_empty():receive_card(receiver,make_card("TB_BaconShop_HP_080t",int(receiver.id)),{"def_id":"TB_BaconShop_HP_080"})
				else:R132.copy_discover(self,receiver,eliminated,"eliminated:"+str(p.id),false)
	Combat132.after_battle(self,p)
	Powers.restore_temporary(self,p)
	p.alive=false;p.rank=rank
	state.ghosts.append(p.duplicate(true))
	for zone in [p.hand,p.board,p.shop,p.pending_rewards]:
		for c in zone:return_pool(c);c.pool_copies=0
	for choice in p.choices:
		for c in choice.options:return_pool(c)
	p.shop=[];p.choices=[]
	emit("PlayerEliminated",int(p.id),{"rank":rank,"origin":origin})
func settle_recruit_deaths() -> void:
	if state.phase!="recruit":return
	var dying=state.players.filter(func(p):return int(p.health)<=0 and int(p.rank)==0)
	if dying.is_empty():return
	var rank=state.players.filter(func(p):return p.alive or p in dying).size()
	for p in dying:eliminate_player(p,rank,"recruit_damage")
	Pairing.ensure(self)
	var alive=state.players.filter(func(p):return p.alive)
	var human_died=dying.any(func(p):return int(p.id)==0)
	if human_died or alive.size()<=1:
		state.champion=int(alive[0].id) if alive.size()==1 else -1
		if alive.size()==1:alive[0].rank=1
		state["match_over"]=true;state.phase="finished"
		stop_auto_chain("PLAYER_ELIMINATED");state.erase("confirmation")
		state.erase("cast_tail");state.erase("play_tail");state.erase("active_root")
		state["confirmation_tickets"]={};state.effect_queue=[]
		emit("MatchEnded",0,{"origin":"recruit_damage","rank":state.players[0].rank,"champion":state.champion})
func recruit_end_waiting() -> bool:
	return state.has("devour_tail") or state.has("confirmation") or state.has("cast_tail") or state.has("play_tail") or state.has("auto_chain") or not state.get("effect_queue",[]).is_empty() or state.players.any(func(p):return p.alive and (not p.choices.is_empty() or R134.pending(p)))
func finish_recruit_end() -> void:
	if not state.has("recruit_end_pending") or state.phase!="recruit":return
	if state.has("confirmation") or state.players.any(func(p):return p.alive and not p.choices.is_empty()):return
	var saved_depth=settlement_depth;settlement_depth=0
	drain_effects()
	if not recruit_end_waiting():
		for player in state.players:
			if player.alive:check_triples(player);drain_rewards(player)
	if not recruit_end_waiting():
		
		for player in state.players:
			if player.alive:R135.safe(self,player)
		for player in state.players:
			if player.alive:check_triples(player);drain_rewards(player)
	if not recruit_end_waiting() and not state.recruit_end_pending.powers_restored:
		state.recruit_end_pending.powers_restored=true
		for player in state.players:Powers.restore_temporary(self,player,"recruit_end")
	if not recruit_end_waiting():
		
		for player in state.players:
			if player.alive:Naga.expire(self,player)
	settlement_depth=saved_depth
	if recruit_end_waiting():return
	state.erase("recruit_end_pending")
	resolve_round()
func resolve_round() -> void:
	settle_recruit_deaths()
	if state.phase=="finished":return
	Pairing.ensure(self)
	if state.pairing_plan.get("relaxation","")=="HARD_CONSTRAINT_UNSATISFIABLE":
		emit("PairingConstraintBlocked",0,{"plan":state.pairing_plan.duplicate(true)})
		return
	Pairing.capture(self)
	state.phase="combat"
	emit("RecruitEnded",0)
	var living=[]
	for p in state.players:
		if p.alive: living.append(int(p.id))
	var frozen_plan=state.pairing_plan.duplicate(true)
	var results=[]
	var human_frames=[]
	var damages={}
	for pair in frozen_plan.pairs:
		var a=state.players[int(pair[0])]
		var b
		var ghost=false
		if int(pair[1])>=0: b=state.players[int(pair[1])]
		else:
			if frozen_plan.ghost.is_empty():continue
			b=frozen_plan.ghost.duplicate(true); b["is_ghost"]=true; ghost=true
		a["previous_recruit_board"]=b.board.duplicate(true)
		if not ghost:b["previous_recruit_board"]=a.board.duplicate(true)
		var result=Combat.fight(self,a,b)
		Pirates.combat_result(self,a,int(result.winner),0)
		if not ghost:Pirates.combat_result(self,b,int(result.winner),1)
		a["last_combat_outcome"]=1 if int(result.winner)==0 else (0 if int(result.winner)==1 else -1)
		if not ghost:b["last_combat_outcome"]=1 if int(result.winner)==1 else (0 if int(result.winner)==0 else -1)
		a["last_combat_lost"]=int(result.winner)==1
		if not ghost: b["last_combat_lost"]=int(result.winner)==0
		var cap=99
		if living.size()>4: cap=5 if state.round<=3 else (10 if state.round<=7 else 15)
		if result.winner==0: result.damage=mini(int(result.damage),cap)
		elif result.winner==1: result.damage=mini(int(result.damage),cap)
		Pairing.record(self,a,b,result,ghost)
		if result.winner==0 and not ghost: damages[b.id]=result.damage
		elif result.winner==1: damages[a.id]=result.damage
		if int(a.id)==0 or (int(b.id)==0 and not ghost):
			human_frames=result.frames
			state["human_left"]=int(a.id); state["human_right"]=int(b.id)
			state["human_opponent_ghost"]=b.duplicate(true) if ghost else {}
		result.erase("frames"); results.append(result)
	state["combat_frames"]=human_frames
	for pid in damages:
		var p=state.players[int(pid)]
		var damage=int(damages[pid])
		if R13Items.battle_damage(self,p,damage):continue
		var armor_loss=mini(int(p.armor),damage)
		p.armor-=armor_loss; p.health-=damage-armor_loss
		emit("HeroDamaged",int(pid),{"damage":damage})
	for p in state.players:
		if p.alive and int(p.health)<=0:
			eliminate_player(p,living.size(),"combat_damage")
	state.results=results
	var alive=[]
	for p in state.players:
		if p.alive: alive.append(p.id)
	if alive.size()<=1:
		state.champion=alive[0] if alive.size()==1 else -1
		if alive.size()==1: state.players[int(alive[0])].rank=1
		state["match_over"]=true
	emit("CombatEnded",0,{"results":results})
func next_round() -> void:
	undo_history.clear()
	# Resolve AI battle rewards against the still-live borrowed epoch first.
	for player in state.players:
		if int(player.id)>0 and player.alive and not settle_start_choices(player):return
	for player in state.players:Powers.restore_temporary(self,player,"all" if state.get("match_over",false) else "before_start")
	if state.get("match_over",false):state.phase="finished";return
	state.round+=1;state.phase="recruit";state.remaining_ms=150000
	state["round_start_autosave"]={"round":int(state.round),"status":"pending"}
	# Freeze before start effects/forced discoveries can query or reveal the rival.
	R132.pairings(self)
	state["round_start_cursor"]={"player":0,"stage":0}
	advance_round_start()
func advance_round_start() -> void:
	if not state.has("round_start_cursor"):return
	var cursor=state.round_start_cursor
	while int(cursor.player)<state.players.size():
		var p=state.players[int(cursor.player)]
		if not p.alive:cursor.player+=1;cursor.stage=0;continue
		if int(cursor.stage)==0:
			cursor.stage=1
			R136.revert(self,p)
			if int(p.get("goldrinn_expires",-1))<=int(state.round):p["goldrinn_attack"]=0;p["goldrinn_health"]=0
			p["turn_start_coin_cap"]=mini(int(state.round)+2,10)+int(p.cap_bonus)
			p["current_coin_cap"]=int(p.turn_start_coin_cap)
			p.coins=int(p.turn_start_coin_cap)+int(p.next_coins);p.next_coins=0;p["coins_spent_round"]=0
			p.upgrade_cost=maxi(0,int(p.upgrade_cost)-1);p.power_used=false
			for c in p.hand+p.board+p.shop:c.modifiers=c.modifiers.filter(func(m):return m.get("duration","permanent")!="next_turn")
			Quilboar.turn_start(self,p);p["corrosion_bonus"]=0
			# Frost also copies at turn start without a refresh. A real refill
			# already resolved it through ShopRefreshed, so never do both.
			if not refill_shop(p,p.frozen,true,true,"turn_start"):R132.frost_shop(self,p)
			check_triples(p);drain_rewards(p);trigger(p,"turn_start",{});trigger(p,"spellcraft",{})
			trinket_effects(p,"turn_start");Heroes7.start(self,p);Demons.turn_start(self,p);R136Slots.start(self,p)
		if int(cursor.stage)==1:
			if not settle_start_choices(p):return
			if not R135.turn_start(self,p):
				if int(p.id)>0 and not p.choices.is_empty() and settle_start_choices(p):continue
				return
			cursor.stage=2
		if int(cursor.stage)==2:
			cursor.stage=3
			cursor["start_finalize_pending"] = true
			CardLock.update(self,p);R132.changed(self,p);R132.turn_start(self,p,false);R133.turn_start(self,p);R134.start(self,p)
			for c in p.board+p.hand:
				if c.has("locked_until_round") and int(c.locked_until_round)<=int(state.round):c.erase("locked_until_round");emit("CardUnlocked",int(p.id),{"instance_id":c.instance_id})
			turn_start_judgment(p);Gifts.boundary(self,p,"turn_start");R135.safe(self,p,true)
		if int(cursor.stage)==3:
			if not settle_start_choices(p):return
			cursor.stage=4
			# Includes late start rewards before the cube offers a replacement.
			if cursor.get("start_finalize_pending",false):R13Items.start_after(self,p)
		if int(cursor.stage)==4:
			if not settle_start_choices(p):return
			cursor.stage=5
			# Old stage-3 saves already issued Nguyen's discovery; do not issue it again.
			if cursor.get("start_finalize_pending",false):
				Powers.restore_temporary(self,p)
				R132.nguyen_start(self,p)
		if not settle_start_choices(p):return
		cursor.player+=1;cursor.stage=0;cursor.erase("start_finalize_pending")
	state.erase("round_start_cursor");emit("TurnStarted",0,{"round":state.round});R132.pairings(self)
func settle_start_choices(p: Dictionary) -> bool:
	if state.has("confirmation"):return false
	if int(p.id)==0:return p.choices.is_empty()
	for unused in 128:
		if p.choices.is_empty():return true
		var choice=p.choices[0];var ids=Choices.eligible(self,p,choice)
		if ids.is_empty():return false
		if Choices.step(self,"choose",{"index":ids[0],"session_id":choice.session_id},int(p.id))!="":return false
	return false
func turn_start_judgment(p: Dictionary) -> void:
	
	Pirates.balance(self,p)
	emit("TurnStartJudgment",int(p.id))
	check_triples(p)
func snapshot() -> Dictionary:
	return {"state":state.duplicate(true),"events":events.duplicate(true),"spell_history":spell_history.duplicate(true),"receipts":receipts.duplicate(true),"command_log":command_log.duplicate(true)}
func restore(data: Dictionary) -> String:
	if not data.has("state") or data.state.get("schema_version",0)!=1: return "INCOMPATIBLE_SCHEMA"
	if data.state.get("numeric_profile_hash","")!=content.numeric_profile_hash:return "NUMERIC_PROFILE_MISMATCH"
	if data.state.get("content_hash","")!=content.content_hash and data.state.get("content_hash","") not in content.pack.get("compatible_content_hashes",[]): return "CONTENT_VERSION_MISMATCH"
	if data.state.get("rules_version","")!=content.pack.rules_version and data.state.get("rules_version","") not in content.pack.get("compatible_rules_versions",[]):return "RULES_VERSION_MISMATCH"
	if data.state.get("players",[]).size()!=8: return "INVALID_SAVE"
	if data.state.has("round_start_cursor"):
		var cursor=data.state.round_start_cursor
		if not cursor is Dictionary or int(cursor.get("player",-1)) not in range(0,8) or int(cursor.get("stage",-1)) not in range(0,6):return "INVALID_START_CURSOR"
	var live_instances={}
	for player in data.state.players:
		var power_error=Powers.validate(self,player,data.state.get("enabled_tribes",[]))
		if power_error!="":return power_error
		for zone in ["hand","board","shop","pending_rewards"]:
			if not player.get(zone) is Array: return "INVALID_SAVE_ZONE"
			for card in player[zone]:
				if not card is Dictionary or not content.definitions.has(card.get("def_id","")): return "INVALID_SAVE_CARD"
				var iid=int(card.get("instance_id",-1))
				if iid<0 or live_instances.has(iid):return "DUPLICATE_SAVE_INSTANCE"
				live_instances[iid]=true
				if not card.get("modifiers") is Array or not card.get("extra_keywords") is Array: return "INVALID_SAVE_CARD_STATE"
				if not card.get("gifts",[]) is Array: return "INVALID_SAVE_GIFTS"
				for gift in card.get("gifts",[]):
					if not gift is Dictionary or int(gift.get("id",0))<1 or int(gift.get("id",0))>44 or int(gift.get("acquired_round",0))<1: return "INVALID_SAVE_GIFTS"
		if not player.get("sessions") is Dictionary: return "INVALID_SAVE_CHOICES"
		for session in player.sessions.values():
			if not session.get("options") is Array: return "INVALID_SAVE_CHOICES"
			for option in session.options:
				if not content.definitions.has(option.get("id","")): return "INVALID_SAVE_CHOICE_ID"
	data=data.duplicate(true)
	for player in data.state.players:
		if not player.has("ball_sold_count"):
			if player.has("ball_attack") or player.has("ball_health"):
				var history=data.get("events",[])
				if history.is_empty() or not history.any(func(event):return event.get("kind","")=="MatchStarted") or int(history[0].get("seq",0))!=1 or int(history[-1].get("seq",0))!=int(data.state.get("event_seq",-1)):return "LEGACY_BALL_HISTORY_UNAVAILABLE"
				var n=0;var previous=0
				for event in history:
					if int(event.get("seq",0))!=previous+1:return "LEGACY_BALL_HISTORY_UNAVAILABLE"
					previous=int(event.seq)
					if event.get("kind","")=="MinionSold" and int(event.get("owner",-1))==int(player.id) and content.get_def(str(event.payload.get("id",""))).get("base_id","") in ["BG31_816","BG31_818","BG36_181"]:n+=1
				player["ball_sold_count"]=n
			else:player["ball_sold_count"]=0
		player.erase("ball_attack");player.erase("ball_health")
	data=normalize_numbers(data)
	undo_history.clear()
	persistence_epoch+=1;persistence_cache={}
	state=data.state.duplicate(true); state.content_hash=content.content_hash;state.rules_version=content.pack.rules_version
	for player in state.players:
		# Older saves did not retain the start-of-turn cap. Keep them loadable;
		# the next turn records the exact cap before any start effects or bonus coins.
		if not player.has("turn_start_coin_cap"):player["turn_start_coin_cap"]=mini(int(state.round)+2,10)+int(player.cap_bonus)
		if not player.has("current_coin_cap"):player["current_coin_cap"]=mini(int(state.round)+2,10)+int(player.cap_bonus)
		var legacy_powers=not player.has("power_slots")
		Powers.ensure(self,player)
		if legacy_powers:R132.changed(self,player)
		player["undead_health"]=int(player.get("undead_health",0))
		for zone in [player.hand,player.board,player.shop,player.pending_rewards]:
			for card in zone:
				if card.get("triple_receipt",false) and not card.has("triple_reward_key"):card["triple_reward_key"]="legacy:"+str(card.instance_id)
				for gift in card_gifts(card):
					if int(gift.id)==2 and not gift.has("attack"):
						var acquired=int(gift.acquired_round);gift["attack"]=3 if acquired>=5 else 2;gift["health"]=4 if acquired>=5 else 3 if acquired==4 else 2
	
	for id in content.pool("minion",state.enabled_tribes):
		if not state.pool.has(id) and int(content.get_def(id).tier)<=6: state.pool[id]=int(content.rules.pool_copies[int(content.get_def(id).tier)-1])
	
	
	var ambiguous=state.has("auto_chain") and (int(state.auto_chain.get("v",1))<3 or state.auto_chain.get("input_origin","")!="right_click")
	var held=state.get("confirmation",{})
	if held.get("resume",{}).get("kind","")=="auto_start" and held.resume.get("input_origin","")!="right_click":
		ambiguous=true
		held.resume={"kind":"legacy_play","play_args":held.resume.get("play_args",{"instance_id":held.target_instance})}
	if ambiguous:
		state.erase("auto_chain")
		for choice in state.players[0].choices:
			choice["auto_policy"]="manual";choice["input_origin"]="legacy_unknown"
		if held.get("resume",{}).get("command","")=="auto_sell":held.resume={"kind":"legacy_hold"}
	events=data.get("events",[]).duplicate(true)
	spell_history=[]
	for event in events:SpellHistory.append(self,event)
	receipts=data.get("receipts",{}).duplicate(true); command_log=data.get("command_log",[]).duplicate(true)
	R132.migrate_devour(self)
	for player in state.players:R136Slots.sync_vouchers(self,player)
	if state.phase=="recruit":
		for player in state.players:R132.retry_hero_gift(self,player)
	Pairing.migrate(self)
	settle_recruit_deaths()
	var checkpoint=state.get("round_start_autosave",{})
	if not checkpoint is Dictionary or int(checkpoint.get("round",-1))!=int(state.round) or checkpoint.get("status","") not in ["pending","saved","failed","legacy_complete","loaded_complete"]:
		state["round_start_autosave"]={"round":int(state.round),"status":"pending" if state.has("round_start_cursor") else "legacy_complete"}
	elif checkpoint.status=="pending" and round_start_settled():
		# A loaded, already-complete checkpoint must not rewrite the same round.
		checkpoint.status="loaded_complete"
	return ""
func save_to(path: String) -> Error:
	
	var prepared=Persistence.prepare(self,path)
	if prepared.error!=OK:return prepared.error
	var raw=var_to_bytes(prepared.body)
	var size_bytes=PackedByteArray();size_bytes.resize(8);size_bytes.encode_u64(0,raw.size())
	var body=size_bytes+raw.compress(FileAccess.COMPRESSION_ZSTD)
	var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(body)
	var envelope="BG92SAVE\n".to_utf8_buffer()+digest.finish().hex_encode().to_utf8_buffer()+body
	var file=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return FileAccess.get_open_error()
	file.store_buffer(envelope); file.close()
	if FileAccess.get_file_as_bytes(path+".tmp")!=envelope:return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		var err=DirAccess.copy_absolute(path,path+".bak")
		if err!=OK: return err
	var committed=DirAccess.rename_absolute(path+".tmp",path)
	if committed==OK:persistence_cache[path]=prepared.cache
	return committed
func load_from(path: String) -> String:
	if not FileAccess.file_exists(path): return "SAVE_NOT_FOUND"
	var bytes=FileAccess.get_file_as_bytes(path)
	if bytes.slice(0,9).get_string_from_utf8()=="BG92SAVE\n":
		var body=bytes.slice(73);var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(body)
		if digest.finish().hex_encode()!=bytes.slice(9,73).get_string_from_utf8():return "CHECKSUM_MISMATCH"
		if body.size()<8:return "INVALID_SAVE"
		var decoded=body.slice(8).decompress(int(body.decode_u64(0)),FileAccess.COMPRESSION_ZSTD)
		if decoded.is_empty():return "INVALID_SAVE"
		var data=bytes_to_var(decoded)
		if data is Dictionary and data.has("journal"):
			var loaded=Persistence.read(path,data)
			if loaded.error!="":return str(loaded.error)
			var error=restore(loaded.data)
			if error=="":loaded.cache["epoch"]=persistence_epoch;persistence_cache[path]=loaded.cache
			return error
		return restore(data) if data is Dictionary else "INVALID_SAVE"
	var envelope=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not envelope is Dictionary or not envelope.has("body") or not envelope.has("sha256"): return "INVALID_SAVE"
	if str(envelope.body).sha256_text()!=envelope.sha256: return "CHECKSUM_MISMATCH"
	var data=JSON.parse_string(envelope.body)
	if not data is Dictionary: return "INVALID_SAVE"
	return restore(data)


static func normalize_numbers(value):
	if value is float and value==floor(value): return int(value)
	if value is Array:
		var result=[]
		for x in value: result.append(normalize_numbers(x))
		return result
	if value is Dictionary:
		var result={}
		for key in value: result[key]=normalize_numbers(value[key])
		return result
	return value

func trinket_effects(p: Dictionary,trigger_name: String,subject: Dictionary={},only: Dictionary={}) -> void:
	var items=[only] if not only.is_empty() else p.trinkets.duplicate()
	if trigger_name=="turn_end":
		var originals=items.duplicate()
		for unused in range(1,Triggers.times(self,p,"turn_end")): items.append_array(originals)
	for item in items:
		if trigger_name=="obtain":
			if item.get("r13_obtained",false):continue
			item["r13_obtained"]=true
		for raw in content.get_def(item.id).effects:
			var matches=raw.get("trigger","")==trigger_name or (raw.get("trigger","")=="obtain_and_start" and trigger_name in ["obtain","turn_start"])
			if not matches: continue
			
			if raw.get("handler","")=="buff" and subject.is_empty(): continue
			if raw.has("tribe") and trigger_name=="minion_played":
				if subject.is_empty() or (raw.tribe not in card_types(subject) and "全部种族" not in card_types(subject)): continue
			var e=raw.duplicate(true)
			if e.get("bound_tribe",false): e["tribe"]=item.bound_tribe
			effect(p,e,subject,item)
	if trigger_name=="obtain":Pirates.balance(self,p)
func gift_card_played(p: Dictionary,played: Dictionary={},listeners: Variant=null) -> void:
	Fish.played(self,p,played)
	Gifts.used(self,p,played,listeners)
	if content.get_def(played.def_id).kind=="minion":Naga.hand_used(self,p,played)
func count_trigger(p: Dictionary,kind: String,amount: int) -> void:
	var previous={}
	for card in Undead.board(self,p): previous[int(card.instance_id)]=Gifts.derived(self,p,card)
	p[kind+"_count"]=int(p.get(kind+"_count",0))+amount
	if not combat_context.is_empty():
		for card in Undead.board(self,p):
			var delta=Gifts.derived(self,p,card)-previous.get(int(card.instance_id),Vector2i.ZERO)
			card.attack+=delta.x;card.health+=delta.y;card.max_health+=delta.y
	emit("TriggerCountChanged",int(p.id),{"trigger":kind,"amount":amount,"total":p[kind+"_count"]})
func automaton_summoned(p: Dictionary,c: Dictionary) -> void:
	if content.get_def(c.def_id).get("base_id","")!="BG_TTN_401":return
	c["automaton_counted"]=true;p["automaton_summons"]=int(p.get("automaton_summons",0))+1
	if not combat_context.is_empty():
		for other in Undead.board(self,p):
			if int(other.instance_id)!=int(c.instance_id) and content.get_def(other.def_id).get("base_id","")=="BG_TTN_401":
				var mult=2 if content.get_def(other.def_id).golden else 1;Undead.local_buff(self,other,3*mult,2*mult)
func card_types(card: Dictionary) -> Array:
	return ["全部种族"] if card.get("all_tribes",false) else card.get("type_override",content.get_def(card.def_id).get("card_types",[]))
func play_definition(card: Dictionary) -> Dictionary:
	return Fish.learned_definition(self,card)
func attach_magnetic(p: Dictionary,target: Dictionary,card: Dictionary) -> void:
	var value=stats(card); buff(target,value.x,value.y)
	for k in keywords(card):
		if k!="MAGNETIC": add_keyword(target,k)
	if not target.has("attached_effects"): target["attached_effects"]=[]
	for e in Triggers.effects(self,card):
		if e.handler!="magnetic":
			var inherited=e.duplicate(true); inherited["attached_source_instance"]=card.instance_id; inherited["attached_source_id"]=card.def_id
			target.attached_effects.append(inherited)
	if not target.has("attached_pool"): target["attached_pool"]=[]
	target.attached_pool.append({"id":card.pool_base,"copies":card.pool_copies,"source_instance":card.instance_id})
	for gift in card_gifts(card): target.gifts.append(gift.duplicate(true))
	emit("MagneticAttached",int(p.id),{"instance_id":card.instance_id,"id":card.def_id,"target":target.instance_id,"attack":value.x,"health":value.y})
static func card_gifts(card: Dictionary) -> Array:
	if card.has("gifts"): return card.gifts
	
	if int(card.get("gift_id",0))>0: return [{"id":int(card.gift_id),"acquired_round":int(card.get("gift_acquired_round",1))}]
	return []

func discovery_candidates(p: Dictionary,spec: Dictionary,source: Dictionary={}) -> Array:
	var options=generation_candidates(p,spec,source)
	if not spec.has("tier"): options=options.filter(func(id):return int(content.get_def(id).tier)<=int(p.tier))
	var d=content.get_def(str(source.get("def_id",source.get("id",""))))
	if d.get("kind","")=="minion":
		var family=str(d.get("base_id",d.get("id","")))
		options=options.filter(func(id):return str(content.get_def(id).get("base_id",id))!=family)
	return options
func requires_battlecry_target(d: Dictionary) -> bool:
	return d.get("effects",[]).any(func(e):return e.get("trigger","")=="battlecry" and e.get("target","") in ["minion","friendly_minion","friendly_undead"])
func d_has_ball(card: Dictionary) -> bool:
	return content.get_def(card.def_id).get("base_id","") in ["BG31_816","BG31_818","BG36_181"]
func battlecry_candidates(p: Dictionary,source: Dictionary,e: Dictionary) -> Array:
	if e.get("op","")=="learned":
		var spell=content.get_def(source.get("learned_spell",""))
		return (p.board+p.shop).filter(func(c):return Naga.valid_target(self,p,spell,c))
	var mode=str(e.get("target",""))
	var candidates=p.board+p.shop if mode=="minion" else p.board.duplicate()
	if mode not in ["minion","friendly_minion","friendly_undead"]:return []
	candidates=candidates.filter(func(c):return int(c.instance_id)!=int(source.get("instance_id",-1)) and content.get_def(c.def_id).kind=="minion")
	if e.has("tribe"):candidates=candidates.filter(func(c):return Undead.tribe(self,c,e.tribe))
	if e.get("op","")=="sanders":candidates=candidates.filter(func(c):return R13.gold_target(self,p,c))
	if mode=="friendly_undead":candidates=candidates.filter(func(c):return Undead.valid_victim(self,p,c,source))
	return candidates
func validate_hand_play(p: Dictionary,args: Dictionary,placement_only: bool=false) -> String:
	var index=find_index(p.hand,int(args.get("instance_id",-1)))
	if index<0: return "CARD_NOT_IN_HAND"
	var card=p.hand[index]; var d=play_definition(card)
	if CardLock.locked(self,p,card):return "CARD_LOCKED"
	var prize_error=R134.valid(self,p,d,find_target(p,int(args.get("target_id",-1))))
	if prize_error!="":return prize_error
	if d.id=="EBG_Spell_037" and R132.source_pool(self,p,"identity").is_empty():return "NO_LEGAL_CANDIDATE"
	if d.id=="BG28_512" and Quilboar.steal_targets(self,p).is_empty():return "NO_LEGAL_TARGET"
	if d.get("unplayable",false):return "CARD_UNPLAYABLE"
	if d.id=="BG28_830" and Pirates.touch_targets(self,p).is_empty():return "NO_TOUCH_TARGET"
	if d.kind=="spell" and not Demons.valid_target(self,p,d,find_target(p,int(args.get("target_id",-1)))):return "INVALID_SPELL_TARGET"
	if d.kind=="spell" and not Pirates.valid_target(self,p,d,find_target(p,int(args.get("target_id",-1)))):return "INVALID_SPELL_TARGET"
	if d.kind=="spell" and not Beasts.valid_target(self,p,d,find_target(p,int(args.get("target_id",-1)))):return "INVALID_SPELL_TARGET"
	if d.kind=="spell" and Quilboar.choice(d):return ""
	var victim=find_target(p,int(args.get("target_id",-1)))
	if d.kind=="minion":
		if d.effects.any(func(e):return e.handler=="magnetic") and not victim.is_empty():
			if not legal_magnetic_target(p,card,victim): return "MAGNETIC_TARGET_REQUIRED"
			return ""
		if p.board.size()>=capacity(p.board): return "BOARD_FULL"
		if placement_only: return ""
		for e in d.effects:
			if e.get("trigger","")!="battlecry": continue
			var mode=str(e.get("target",""))
			if mode in ["minion","friendly_minion","friendly_undead"]:
				var candidates=battlecry_candidates(p,card,e)
				if candidates.is_empty() and victim.is_empty() and int(args.get("target_id",-1))<0:continue
				if victim.is_empty() or not candidates.any(func(c):return int(c.instance_id)==int(victim.instance_id)):return "FRIENDLY_UNDEAD_REQUIRED" if mode=="friendly_undead" else "TARGET_REQUIRED"
	else:
		var mode=str(d.effects[0].get("target","none"))
		if mode=="minion" and victim.is_empty(): return "TARGET_REQUIRED"
		if mode=="friendly_minion" and (victim.is_empty() or find_index(p.board,int(victim.instance_id))<0): return "BOARD_TARGET_REQUIRED"
		if mode=="friendly_undead" and not Undead.valid_victim(self,p,victim): return "FRIENDLY_UNDEAD_REQUIRED"
		if d.effects[0].get("op","")=="chef" and card_types(victim).is_empty():return "INVALID_SPELL_TARGET"
	return ""
func legal_magnetic_target(p: Dictionary,source: Dictionary,target: Dictionary) -> bool:
	if find_index(p.board,int(target.instance_id))<0:return false
	return Undead.tribe(self,target,"机械") or (content.get_def(source.def_id).get("base_id","")=="BG_DEEP_015" and Undead.tribe(self,target,"亡灵"))
func preview_placement(pid: int,args: Dictionary) -> Dictionary:
	if pid<0 or pid>=state.players.size(): return {"accepted":false,"error_code":"INVALID_PLAYER"}
	var p=state.players[pid]
	var error="WRONG_PHASE" if state.phase!="recruit" or not p.alive else "MANDATORY_CHOICE" if not p.choices.is_empty() else validate_hand_play(p,args,true)
	return {"accepted":error.is_empty(),"error_code":error}
func generation_candidates(p: Dictionary,spec: Dictionary,source: Dictionary={}) -> Array:
	var options=[]
	var source_def=content.get_def(str(source.get("def_id",source.get("id",""))))
	var source_base=str(source_def.get("base_id",source_def.get("id","")))
	for id in content.pool("minion",state.enabled_tribes):
		var d=content.get_def(id)
		
		if not spec.has("tier") and int(d.tier)>int(p.tier): continue
		if source_def.get("kind","")=="minion" and str(d.get("base_id",id))==source_base: continue
		
		
		if spec.get("random_tier",false) and int(d.tier)>int(p.tier): continue
		if spec.get("exclude_source_base",false) and str(d.get("base_id",id))==source_base: continue
		if spec.get("max_tier","")=="player_tier" and int(d.tier)>int(p.tier): continue
		if spec.has("tribe") and spec.tribe not in d.card_types and "全部种族" not in d.card_types: continue
		if spec.has("tier") and int(spec.tier)!=int(d.tier): continue
		if spec.get("deathrattle",false) and not d.effects.any(func(x):return x.get("trigger","")=="deathrattle"):continue
		if spec.get("battlecry",false) and not d.effects.any(func(x):return x.get("trigger","")=="battlecry"): continue
		options.append(id)
	return options

func activate_availability(pid: int,source_id: int,ability: String="native") -> Dictionary:
	if pid<0 or pid>=state.players.size(): return {"available":false,"targets":[],"reason":"INVALID_PLAYER"}
	var p=state.players[pid]; var index=find_index(p.board,source_id)
	if state.phase!="recruit" or not p.alive: return {"available":false,"targets":[],"reason":"WRONG_PHASE"}
	if not p.choices.is_empty(): return {"available":false,"targets":[],"reason":"MANDATORY_CHOICE"}
	if index<0: return {"available":false,"targets":[],"reason":"CARD_NOT_ON_BOARD"}
	var source=p.board[index]; var effects=content.get_def(source.def_id).effects.filter(func(e):return e.get("trigger","")=="activate")
	if ability not in ["native","gold"]:return {"available":false,"targets":[],"reason":"INVALID_ACTIVATE_ABILITY"}
	if ability=="gold" and source.gold_route!="恶魔":return {"available":false,"targets":[],"reason":"NO_GOLD_ROUTE"}
	if source.gold_route=="恶魔" and (ability=="gold" or effects.is_empty()):return Demons.activate_query(self,p,source,"gold")
	var beast_query=Beasts.activate_query(self,p,source)
	if not beast_query.is_empty():return beast_query
	var fish_query=Fish.activate_query(self,p,source)
	if not fish_query.is_empty():return fish_query
	var demon_query=Demons.activate_query(self,p,source,"native")
	if not demon_query.is_empty():return demon_query
	if effects.is_empty(): return {"available":false,"targets":[],"reason":"NO_ACTIVATE_EFFECT"}
	if int(source.get("activated_round",0))==int(state.round): return {"available":false,"targets":[],"reason":"ALREADY_ACTIVATED"}
	if int(p.coins)<int(effects[0].cost): return {"available":false,"targets":[],"reason":"NOT_ENOUGH_COINS"}
	if effects[0].get("handler","")=="round9":
		var legal=effects[0].get("op","")!="discover_spell" or not Naga.spell_pool(self,p).is_empty()
		return {"available":legal,"targets":[-1] if legal else [],"reason":"" if legal else "NO_LEGAL_CANDIDATE"}
	if effects[0].get("handler","")=="round7" and effects[0].get("op","")=="conjurer":
		var legal=not Naga.conjurer_pool(self,p,source).is_empty()
		return {"available":legal,"targets":[-1] if legal else [],"reason":"" if legal else "NO_LEGAL_CANDIDATE"}
	if effects[0].get("handler","")=="round6":
		var legal=[]
		if effects[0].get("target","none") in ["other_friendly","other_minion"]:
			var candidates=p.board+(p.shop if effects[0].target=="other_minion" or effects[0].get("op","")=="activate_set" else [])
			for victim in candidates:
				if int(victim.instance_id)!=source_id and content.get_def(victim.def_id).kind=="minion": legal.append(int(victim.instance_id))
		else: legal=[-1]
		if effects[0].get("op","")=="activate_steal" and not p.shop.any(func(c):return content.get_def(c.def_id).kind=="minion"): legal=[]
		return {"available":not legal.is_empty(),"targets":legal,"reason":"" if not legal.is_empty() else "NO_LEGAL_TARGET"}
	var targets=[]
	for victim in p.board:
		if Undead.valid_different_victim(self,p,victim,source): targets.append(int(victim.instance_id))
	return {"available":not targets.is_empty(),"targets":targets,"reason":"" if not targets.is_empty() else "NO_LEGAL_TARGET"}
func choice_target_error(p: Dictionary,args: Dictionary) -> String:
	if state.phase!="recruit" or not p.alive:return "WRONG_PHASE"
	if p.choices.is_empty():return "NO_CHOICE"
	var session=p.choices[0]
	if session.kind=="r132_target":return R132.target_error(self,p,session,int(args.get("target_id",-1)),args)
	if session.kind!="choose_target" or not session.get("round8",false):return "CHOICE_TARGET_NOT_PENDING"
	var target=find_target(p,int(args.get("target_id",-1)))
	return "INVALID_SPELL_TARGET" if target.is_empty() or Quilboar.need_target(self,p,session,target) else ""
func shop_move_error(p: Dictionary,args: Dictionary) -> String:
	if state.phase!="recruit" or not p.alive:return "WRONG_PHASE"
	if not p.choices.is_empty():return "MANDATORY_CHOICE"
	var minions=p.shop.filter(func(c):return content.get_def(c.def_id).kind=="minion")
	if find_index(minions,int(args.get("instance_id",-1)))<0:return "SHOP_MINION_REQUIRED"
	if int(args.get("index",-1))<0 or int(args.index)>=minions.size():return "INVALID_SHOP_POSITION"
	return ""
func preview_action(pid: int,kind: String,payload: Dictionary={}) -> Dictionary:
	if kind=="shop_move":
		if pid<0 or pid>=state.players.size():return {"accepted":false,"error_code":"INVALID_PLAYER"}
		var error=shop_move_error(state.players[pid],payload);return {"accepted":error=="","error_code":error}
	if kind in ["refresh","buy"]:
		if pid<0 or pid>=state.players.size():return {"accepted":false,"error_code":"INVALID_PLAYER"}
		var p=state.players[pid];var selected={}
		if kind=="buy":
			var i=find_index(p.shop,int(payload.get("instance_id",-1)))
			if i>=0:selected=p.shop[i]
		var facts=Payment.refresh(self,p) if kind=="refresh" else Payment.buy(self,p,selected)
		return {"accepted":facts.available,"error_code":facts.reason}
	if kind=="choose_target":
		if pid<0 or pid>=state.players.size():return {"accepted":false,"error_code":"INVALID_PLAYER"}
		var error=choice_target_error(state.players[pid],payload)
		return {"accepted":error=="","error_code":error}
	if kind=="activate":
		var availability=activate_availability(pid,int(payload.get("instance_id",-1)),str(payload.get("ability","native")))
		var error=str(availability.reason)
		if availability.available and int(payload.get("target_id",-1)) not in availability.targets: error="DIFFERENT_FAMILY_REQUIRED"
		return {"accepted":error.is_empty(),"error_code":error}
	
	if kind=="play":
		if pid<0 or pid>=state.players.size(): return {"accepted":false,"error_code":"INVALID_PLAYER"}
		var p=state.players[pid]
		var play_error="WRONG_PHASE" if state.phase!="recruit" or not p.alive else "MANDATORY_CHOICE" if not p.choices.is_empty() else validate_hand_play(p,payload)
		if play_error.is_empty() and p.board.any(func(c):return c.get("gold_route","")=="野兽"):
			var sim=get_script().new(content);sim.undo_tracking_enabled=false;sim.state=action_state()
			return sim.act(pid,kind,payload)
		return {"accepted":play_error.is_empty(),"error_code":play_error}
	
	var simulation=get_script().new(content)
	simulation.undo_tracking_enabled=false
	simulation.state=action_state()
	simulation.spell_history=spell_history.duplicate()
	return simulation.act(pid,kind,payload)
