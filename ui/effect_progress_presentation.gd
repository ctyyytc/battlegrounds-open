extends RefCounted
const ExternalText = preload("res://domain/resources/external_content.gd")
static func supported(d: Dictionary) -> bool:
	return d.get("effects",[]).any(func(e):return e.get("op","")=="upgrade_effect")
static func body(d: Dictionary,card: Dictionary,compact: bool=false) -> String:
	var tier=int(card.get("discovery_tier",1));var amount=2 if d.get("golden",false) else 1
	if compact:return ExternalText.phrase("effect_progress_presentation.4e60ca4c330c", "说明待补充 · %d / %d") % [amount,tier]
	return ExternalText.phrase("effect_progress_presentation.bb2b3aafe435", "说明待补充 · %d / %d") % [amount,tier]
