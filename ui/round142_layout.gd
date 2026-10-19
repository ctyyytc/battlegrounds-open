extends RefCounted
const DESIGN=Vector2(1404,924)
const CARD=Vector2(124,164)
const WHOLE_HAND_ROW=Rect2(0,788,1404,144)
const HAND=Rect2(70.2,788,1263.6,144)
const BOARD=Rect2(146,416,916,196)
const SHOP=Rect2(146,202,916,198)
const DETAIL=Rect2(1080,206,324,326)
const SELL=Rect2(399,80,470,92)
const REFRESH=Rect2(884,80,170,44)
const FREEZE=Rect2(884,128,170,44)
static func row(area: Rect2,count: int,dimensions: Vector2=CARD) -> Array:
	var result=[]
	var width=minf(dimensions.x,(area.size.x-maxi(0,count-1)*8)/maxi(1,count))
	var dims=dimensions*width/dimensions.x
	var step=dims.x+8
	var first=area.position.x+(area.size.x-(count-1)*step-dims.x)*0.5
	for i in count:result.append(Rect2(Vector2(first+i*step,area.position.y+20),dims))
	return result
static func hand(area: Rect2,count: int) -> Array:
	var result=[]
	var width=minf(130,(area.size.x-maxi(0,count-1)*5)/maxi(1,count))
	var height=area.size.y
	var first=area.position.x+(area.size.x-count*width-maxi(0,count-1)*5)*0.5
	for i in count:result.append(Rect2(first+i*(width+5),area.position.y+area.size.y-height,width,height))
	return result
static func power(index: int,count: int) -> Rect2:
	var width=196.0 if count==1 else 172.0
	return Rect2(564+index*182.0,642,width,80)
