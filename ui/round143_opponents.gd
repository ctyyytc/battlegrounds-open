extends RefCounted
const Text=preload("res://ui/spell_presentation.gd")
const ExternalText=preload("res://domain/resources/external_content.gd")
static func target(engine) -> Dictionary:
	if engine.state.phase=="combat":
		var ghost=engine.state.get("human_opponent_ghost",{})
		if not ghost.is_empty():return {"player":ghost,"ghost":true}
		if not engine.state.has("human_left"):return {}
		var pid=int(engine.state.human_right if int(engine.state.human_left)==0 else engine.state.human_left)
		return {"player":engine.state.players[pid],"ghost":false}
	var human=engine.state.players[0]
	if not human.alive:return {}
	if int(human.get("next_opponent",-1))>=0:return {"player":engine.state.players[int(human.next_opponent)],"ghost":false}
	var ghost=human.get("next_opponent_ghost",{})
	return {"player":ghost,"ghost":true} if not ghost.is_empty() else {}
static func detail(engine,p: Dictionary,ghost: bool=false) -> String:
	var escape=func(value):return Text.escape(str(value))
	var hero=engine.content.get_def(p.hero_id)
	var lines=["[b]"+escape.call(p.name)+" · "+escape.call(hero.name)+"[/b]",("幽灵 · 已淘汰 · 冻结快照" if ghost else "存活" if p.alive else "已淘汰"),"生命 %d · 护甲 %d · 酒馆 ★%d" % [p.health,p.armor,p.tier],"[b]实际英雄技能[/b]"]
	for id in engine.active_powers(p.duplicate(true)):
		var d=engine.content.get_def(id)
		lines.append(escape.call(d.name)+"："+escape.call(d.get("text","")))
	var summary=p.get("public_combat_summary",{})
	if summary.is_empty():lines.append("主要种族：未知（尚无战前公开摘要）")
	else:
		var tribes=summary.get("leaders",[])
		var name="混合："+" / ".join(ExternalText.terms_list(tribes)) if tribes.size()>1 else ExternalText.term(str(tribes[0])) if tribes.size()==1 else "全部种族" if int(summary.get("all_tribe_count",0))>0 else "无种族"
		lines.append("主要种族："+escape.call(name)+" · %d（场上共%d）" % [int(summary.count),int(summary.board_count)])
		lines.append("采样：第%d回合战斗开始前；全种族计入各已出现种族，多种族分别计数。" % int(summary.round))
	lines.append("[b]最近两场[/b]")
	var history=engine.Pairing.recent(engine,int(p.id))
	if history.is_empty():lines.append("未知（未记录历史）")
	for entry in history.slice(maxi(0,history.size()-2)):
		var opponent=engine.state.players[int(entry.opponent)]
		var outcome={"win":"胜","loss":"负","draw":"平"}.get(str(entry.outcome),"未知")
		lines.append("第%d回合 · %s%s · %s · %s%d" % [int(entry.round),escape.call(opponent.name),"（幽灵）" if entry.ghost else "",outcome,"造成伤害 " if entry.outcome=="win" else "承受伤害 " if entry.outcome=="loss" else "伤害 ",int(entry.damage)])
	if ghost:lines.append("身份及阵容来自已淘汰时冻结的幽灵快照。")
	return "\n".join(lines)
