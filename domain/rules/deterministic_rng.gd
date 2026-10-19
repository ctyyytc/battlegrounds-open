extends RefCounted

const MOD = 2147483647
static func next(streams: Dictionary,key: String,bound: int) -> int:
	assert(bound>0)
	var value = int(streams.get(key,1))
	var limit = (MOD-1)-((MOD-1)%bound)
	while true:
		value = (value*48271)%MOD
		if value-1 < limit: break
	streams[key]=value
	return (value-1)%bound
static func shuffle(items: Array, streams: Dictionary,key: String) -> Array:
	var result=items.duplicate()
	for i in range(result.size()-1,0,-1):
		var j=next(streams,key,i+1)
		var tmp=result[i]; result[i]=result[j]; result[j]=tmp
	return result

