extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
const WARM=Color("e97061")
static func payment(engine,f: Dictionary) -> Dictionary:
	var life=bool(f.get("life",false));var cost=int(f.get("cost",0));var damage=f.get("damage",{})
	var amount=int(damage.get("amount",0));var text=str(cost)+ExternalText.ui("ui_life_payment_presentation.payment.3ebb80ebb72c", "币")
	if f.get("free",false):text=ExternalText.ui("ui_life_payment_presentation.payment.198654340123", "免费%d次") % int(f.get("free_count",0)) if f.kind=="refresh" else (ExternalText.ui("ui_life_payment_presentation.payment.0789750337aa", "0生命") if life else ExternalText.ui("ui_life_payment_presentation.payment.0fa50da99935", "0币"))
	elif life:text=ExternalText.ui("ui_life_payment_presentation.payment.a21176536aff", "免疫0伤") if damage.get("immune",false) else str(cost)+ExternalText.ui("ui_life_payment_presentation.payment.2ae654064e55", "生命")
	var detail="";var source=str(f.get("source_id",""))
	if source!="":detail=engine.content.get_def(source).name+(ExternalText.ui("ui_life_payment_presentation.payment.9aefbe749973", " · 剩%d次") % int(f.remaining) if int(f.get("remaining",-1))>=0 else "")
	var notes=[detail] if detail!="" else []
	if f.kind=="refresh":
		for q in f.get("prince_quotas",[]):notes.append(engine.content.get_def(q.id).name+ExternalText.ui("ui_life_payment_presentation.payment.d8f88c412741", " #%d · 剩%d次") % [int(q.instance_id),int(q.remaining)])
		if not f.get("prince_quotas",[]).is_empty():detail=ExternalText.ui("ui_life_payment_presentation.payment.a68b82e01913", "免费%d · 生命%d") % [int(f.free_count),int(f.prince_total)]
	if life:
		notes.append(ExternalText.phrase("life_payment_presentation.d58f6c10dbf5", "说明待补充 · %d / %d / %d") % [cost,int(damage.armor),int(damage.health)])
		if damage.immune:notes.append(ExternalText.phrase("life_payment_presentation.58e8671ae0c8", "说明待补充"))
		if amount==0 and not damage.immune:notes.append(ExternalText.phrase("life_payment_presentation.388f8ca6147c", "说明待补充"))
		if f.get("rewind",false):notes.append(ExternalText.phrase("life_payment_presentation.4c8477e464b9", "说明待补充"))
	elif f.get("free",false):notes.append(ExternalText.phrase("life_payment_presentation.a0633135bbaa", "说明待补充"))
	if not f.get("available",true):notes.append({"NOT_ENOUGH_HEALTH":ExternalText.ui("ui_life_payment_presentation.payment.c8bb68f4b439", "生命和护甲不足"),"NOT_ENOUGH_COINS":ExternalText.ui("ui_life_payment_presentation.payment.05107fb17ce5", "铸币不足"),"HAND_FULL":ExternalText.ui("ui_life_payment_presentation.payment.6d85d4649732", "手牌已满"),"MANDATORY_CHOICE":ExternalText.ui("ui_life_payment_presentation.payment.ef084e3642e6", "请先完成当前选择"),"WRONG_PHASE":ExternalText.ui("ui_life_payment_presentation.payment.4baf28c76cea", "当前阶段不可操作")}.get(f.get("reason",""),str(f.get("reason",""))))
	return {"text":text,"detail":detail,"tooltip":"\n".join(notes),"warm":life and amount>0,"life":life,"available":bool(f.get("available",false))}
static func risk(f: Dictionary) -> Dictionary:
	if not f.get("active",false):return {"text":"","tooltip":"","warm":false}
	var parts=[];var notes=[];var immune=bool(f.immune)
	if int(f.trigger_hits)>0:
		parts.append(ExternalText.ui("ui_life_payment_presentation.risk.a21176536aff", "免疫0伤") if immune else ExternalText.ui("ui_life_payment_presentation.risk.12bc1a20965f", "入场%d伤") % int(f.trigger_hits))
		notes.append(ExternalText.phrase("life_payment_presentation.69476da31161", "说明待补充 · %d") % int(f.trigger_hits))
	if int(f.discoveries)>0:
		parts.append(ExternalText.ui("ui_life_payment_presentation.risk.91734622e50d", "发现免疫") if immune else ExternalText.ui("ui_life_payment_presentation.risk.54791434b693", "发现后受伤"))
		notes.append(ExternalText.phrase("life_payment_presentation.ca697b795a08", "说明待补充 · %d") % int(f.discoveries))
	if immune:notes.append(ExternalText.phrase("life_payment_presentation.fb89f2a407eb", "说明待补充"))
	return {"text":" · ".join(parts),"tooltip":"\n".join(notes),"warm":not immune}
