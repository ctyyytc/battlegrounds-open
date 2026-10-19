extends RefCounted
## Preparation owns no MatchEngine and never consumes gameplay random streams.
const RNG=preload("res://domain/rules/deterministic_rng.gd")
const EngineRules=preload("res://domain/rules/match_engine.gd")
var seed_value: int=0
var tribes: Array=[]
var legal: Array=[]
var candidates: Array=[]
var epoch: int=0
var committed: bool=false
func prepare(registry,value: int) -> void:
	epoch+=1;committed=false;seed_value=value
	tribes=EngineRules.tribe_selection(registry.rules.validation_tribes,value).tribes
	legal=registry.pool("hero",tribes,false)
	candidates=sample(legal,value)
static func sample(pool: Array,value: int) -> Array:
	var streams={"hero_preparation":posmod(value,2147483646)+1}
	var remaining=pool.duplicate();var result=[]
	while not remaining.is_empty() and result.size()<3:
		var index=RNG.next(streams,"hero_preparation",remaining.size())
		result.append(remaining[index]);remaining.remove_at(index)
	return result
func accepts(id: String,token: int) -> bool:
	return token==epoch and not committed and id in legal
