shader_type canvas_item;
render_mode unshaded;
void fragment() {
 vec2 p=(UV-vec2(0.5))*2.0;
 float r=length(p);
 float mask=1.0-smoothstep(0.91,1.0,r);
 float rim=smoothstep(0.72,0.94,r)*mask;
 float gloss=pow(max(0.0,1.0-length((p-vec2(-0.3,-0.38))*vec2(1.2,2.8))),3.0);
 float band=pow(max(0.0,1.0-abs(p.y+p.x*0.42+0.35)*9.0),3.0);
 COLOR=vec4(mix(vec3(1.0,0.83,0.38),vec3(1.0,1.0,0.9),gloss),mask*(0.15+gloss*0.35+band*0.09)+rim*0.34);
}
