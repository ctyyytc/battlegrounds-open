extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
static func locked(engine,p: Dictionary,c: Dictionary) -> bool:
	if int(c.get("locked_until_round",0))>int(engine.state.round):return true
	var lock=c.get("card_lock",{})
	return int(lock.get("round",0))>int(engine.state.round) or int(lock.get("tier",0))>int(p.tier) or int(lock.get("debt",0))>0
static func update(engine,p: Dictionary,event: Dictionary={}) -> void:
	for c in p.hand+p.board+p.pending_rewards:
		var lock=c.get("card_lock",{})
		if event.get("kind","")=="CoinsSpent" and lock.has("debt"):
			var receipt=str(event.seq)
			if lock.get("last_payment_receipt","")!=receipt:
				lock.debt=maxi(0,int(lock.debt)-int(event.payload.amount));lock["last_payment_receipt"]=receipt
		if (c.has("card_lock") or c.has("locked_until_round")) and not locked(engine,p,c):
			c.erase("card_lock");c.erase("locked_until_round");engine.emit("CardUnlocked",int(p.id),{"instance_id":c.instance_id})
static func description(engine,p: Dictionary,c: Dictionary) -> String:
	var lock=c.get("card_lock",{})
	var lines=[]
	var turn=maxi(int(c.get("locked_until_round",0)),int(lock.get("round",0)))
	if turn>int(engine.state.round):lines.append(ExternalText.phrase("domain_rules_card_lock.description.5a1886c04742", "说明待补充 · %d") % turn)
	if int(lock.get("tier",0))>int(p.tier):lines.append(ExternalText.phrase("domain_rules_card_lock.description.cc8d880f9e06", "说明待补充 · %d") % int(lock.tier))
	if int(lock.get("debt",0))>0:lines.append(ExternalText.phrase("domain_rules_card_lock.description.db9bb3427a2b", "说明待补充 · %d") % int(lock.debt))
	return "；".join(lines)
