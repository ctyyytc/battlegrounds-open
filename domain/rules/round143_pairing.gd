extends RefCounted
# One authoritative plan per recruit population. Queries never draw RNG.
# Exhaustive perfect matchings (at most 105 for eight seats), not per-seat greed.
static func living(engine) -> Array:
	return engine.state.players.filter(func(p):return p.alive).map(func(p):return int(p.id))
static func recent(engine,pid: int) -> Array:
	return engine.state.get("pairing_history",{}).get(str(pid),[])
static func valid(engine) -> bool:
	var plan=engine.state.get("pairing_plan",{})
	return int(plan.get("round",-1))==int(engine.state.round) and plan.get("living",[])==living(engine)
static func ensure(engine) -> void:
	if not valid(engine):plan(engine)
static func enumerate_pairs(ids: Array) -> Array:
	if ids.is_empty():return [[]]
	var out=[];var a=ids[0]
	for i in range(1,ids.size()):
		var rest=ids.slice(1);rest.erase(ids[i])
		for tail in enumerate_pairs(rest):out.append([[a,ids[i]]]+tail)
	return out
static func opponent_id(pair: Array,pid: int,ghost: Dictionary) -> int:
	var other=int(pair[1] if int(pair[0])==pid else pair[0])
	return int(ghost.get("id",-1)) if other==-1 else other
static func score(engine,pairs: Array,ghost: Dictionary,count: int) -> Array:
	var result=[0,0,0,0,0,0]
	for pair in pairs:
		for pid in pair:
			if int(pid)<0:continue
			var history=recent(engine,int(pid));var oid=opponent_id(pair,int(pid),ghost)
			if pair.has(-1):
				for entry in history.slice(-3):
					if entry.ghost:result[4]+=1
				result[5]=history.filter(func(entry):return entry.ghost).size()
			for distance in range(1,mini(3,history.size())+1):
				if int(history[-distance].opponent)==oid:
					if distance==1 and count>2:result[0]+=1
					else:result[distance]+=1
	return result
static func less(a: Array,b: Array) -> bool:
	for i in a.size():
		if a[i]!=b[i]:return a[i]<b[i]
	return false
static func circle(engine,ids: Array) -> Array:
	if not engine.state.has("pairing_cycle"):
		engine.state["pairing_cycle"]={"order":engine.RNG.shuffle(ids,engine.state.streams,"pairing"),"start_round":int(engine.state.round)}
	var cycle=engine.state.pairing_cycle;var ring=cycle.order.duplicate()
	var phase=posmod(int(engine.state.round)-int(cycle.start_round),ring.size()-1)
	for unused in phase:ring.insert(1,ring.pop_back())
	var pairs=[]
	for i in int(ring.size()/2):pairs.append([ring[i],ring[ring.size()-1-i]])
	return pairs
static func plan(engine) -> void:
	var ids=living(engine);var pairs=[];var ghost={};var chosen_score=[0,0,0,0,0,0];var reason="";var candidates=[]
	if ids.size()==engine.state.players.size():
		pairs=circle(engine,ids)
	else:
		var seats=ids.duplicate()
		if seats.size()%2==1:seats.append(-1)
		var ghosts=engine.state.ghosts if seats.has(-1) else [{}]
		if ghosts.is_empty():ghosts=[{}]
		var best=[]
		for g in ghosts:
			for matching in enumerate_pairs(seats):
				var value=score(engine,matching,g,ids.size())
				if best.is_empty() or less(value,best):best=value;candidates=[]
				if value==best:candidates.append({"pairs":matching,"ghost":g})
		if not candidates.is_empty():
			var selected=candidates[engine.RNG.next(engine.state.streams,"pairing",candidates.size())]
			pairs=selected.pairs;ghost=selected.ghost.duplicate(true);chosen_score=best
		if chosen_score[0]>0:reason="HARD_CONSTRAINT_UNSATISFIABLE"
		elif chosen_score.slice(1,4).any(func(v):return v>0):reason="RECENT_WINDOW_RELAXED_GLOBAL_MINIMUM"
	var order=[]
	for pair in pairs:
		if int(pair[0])==-1:pair.reverse()
		for pid in pair:
			if int(pid)>=0:order.append(int(pid))
		var a=engine.state.players[int(pair[0])]
		if int(pair[1])>=0:
			var b=engine.state.players[int(pair[1])]
			a["next_opponent"]=int(b.id);b["next_opponent"]=int(a.id)
			a.erase("next_opponent_ghost");b.erase("next_opponent_ghost")
		else:
			a["next_opponent"]=-1;a["next_opponent_ghost"]=ghost.duplicate(true);a["next_opponent_board"]=ghost.get("board",[]).duplicate(true)
	engine.state["recruit_pairings"]=order
	engine.state["pairing_plan"]={"version":143,"round":int(engine.state.round),"living":ids,"pairs":pairs,"ghost":ghost,"score":chosen_score,"relaxation":reason,"candidate_ties":candidates.size()}
static func migrate(engine) -> void:
	if engine.state.has("pairing_plan"):return
	# Preserve an old save's preview and pairing RNG. Unknown history stays unknown.
	var ids=living(engine);var order=engine.state.get("recruit_pairings",[])
	if order.size()!=ids.size() or ids.any(func(pid):return order.count(pid)!=1):ensure(engine);return
	var pairs=[];var ghost=engine.state.ghosts.back().duplicate(true) if ids.size()%2==1 and not engine.state.ghosts.is_empty() else {}
	for i in range(0,order.size(),2):pairs.append([int(order[i]),int(order[i+1]) if i+1<order.size() else -1])
	if ids.size()==engine.state.players.size():
		# Anchor the cycle to the saved pairs without drawing RNG or changing preview.
		var left=[];var right=[]
		for pair in pairs:left.append(pair[0]);right.push_front(pair[1])
		engine.state["pairing_cycle"]={"order":left+right,"start_round":int(engine.state.round)}
	engine.state["pairing_plan"]={"version":143,"round":int(engine.state.round),"living":ids,"pairs":pairs,"ghost":ghost,"score":[],"relaxation":"LEGACY_HISTORY_UNKNOWN"}
	for pair in pairs:
		if int(pair[1])==-1:engine.state.players[int(pair[0])]["next_opponent_ghost"]=ghost.duplicate(true)
static func summary(engine,p: Dictionary) -> Dictionary:
	var counts={};var all_count=0
	for card in p.board:
		var types=engine.card_types(card)
		if "全部种族" in types:all_count+=1;continue
		for tribe in types:
			if tribe not in ["中立","NEUTRAL",""]:counts[tribe]=int(counts.get(tribe,0))+1
	for tribe in counts:counts[tribe]+=all_count
	var maximum=all_count
	for value in counts.values():maximum=maxi(maximum,int(value))
	var leaders=counts.keys().filter(func(t):return int(counts[t])==maximum);leaders.sort()
	return {"round":int(engine.state.round),"sample":"combat_start","leaders":leaders,"count":maximum,"all_tribe_count":all_count,"board_count":p.board.size()}
static func capture(engine) -> void:
	for p in engine.state.players:
		if p.alive:p["public_combat_summary"]=summary(engine,p)
static func record(engine,a: Dictionary,b: Dictionary,result: Dictionary,ghost: bool) -> void:
	if not engine.state.has("pairing_history"):engine.state["pairing_history"]={}
	for side in (1 if ghost else 2):
		var p=a if side==0 else b;var other=b if side==0 else a
		var key=str(p.id)
		if not engine.state.pairing_history.has(key):engine.state.pairing_history[key]=[]
		var outcome="draw" if int(result.winner)<0 else "win" if int(result.winner)==side else "loss"
		engine.state.pairing_history[key].append({"round":int(engine.state.round),"opponent":int(other.id),"ghost":ghost,"outcome":outcome,"damage":int(result.damage) if outcome!="draw" else 0})
		# Bounded serializable history, enough for UI and the three-match window.
		if engine.state.pairing_history[key].size()>16:engine.state.pairing_history[key].pop_front()
