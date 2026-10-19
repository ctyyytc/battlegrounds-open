extends RefCounted

const PROTECTED=["quest_reward","darkmoon_prize","trinket","apprentice","triple_body","gold_play_reward","paid_gift","treasure","unclassified_special","hero_start","cat_elimination_reward","r133_ticket_token","r133_ticket_discovery","r133_flight_spell","r133_flight_discovery","shop_batch_transfer"]
static func context(engine,source: Dictionary,kind: String="") -> Dictionary:
	if source.has("origin_kind") and source.has("producer_id") and kind.is_empty():return source.duplicate(true)
	var producer=source if not source.is_empty() else engine.effect_source
	var id=str(producer.get("def_id",producer.get("id","")))
	if kind.is_empty():
		kind=str(producer.get("origin_kind",""))
		if kind.is_empty():kind="unclassified_special" if id.is_empty() else "trinket" if engine.content.get_def(id).get("kind","")=="trinket" else "ordinary"
	return {"origin_kind":kind,"producer_id":id,"producer_instance":producer.get("instance_id",-1),"root_action_id":engine.cause}
static func protected(context: Dictionary) -> bool:
	return context.get("origin_kind","") in PROTECTED
