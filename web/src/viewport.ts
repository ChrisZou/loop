// DOM rects and fixed positions use layout coordinates; visual viewport offsets
// define the visible box. Clamp against that box without adding offsets twice.
export function clampPosition(rect:{left:number;bottom:number},size:{width:number;height:number},box:{width:number;height:number;left:number;top:number}){
 const width=Math.min(size.width,Math.max(0,box.width-24)),height=Math.min(size.height,Math.max(0,box.height-24));
 return {left:Math.max(box.left+12,Math.min(rect.left,box.left+box.width-width-12)),top:Math.max(box.top+12,Math.min(rect.bottom+8,box.top+box.height-height-12))};
}
