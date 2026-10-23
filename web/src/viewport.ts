// DOM rects and fixed positions use layout coordinates; visual viewport offsets
// define the visible box. Clamp against that box without adding offsets twice.
export function clampPosition(
 rect:{left:number;bottom:number;top?:number},
 size:{width:number;height:number},
 box:{width:number;height:number;left:number;top:number},
 options?:{preferAbove?:boolean}
){
 const width=Math.min(size.width,Math.max(0,box.width-24)),height=Math.min(size.height,Math.max(0,box.height-24));
 const left=Math.max(box.left+12,Math.min(rect.left,box.left+box.width-width-12));
 const below=rect.bottom+8;
 // preferAbove: put ＋批注 above the selection so iOS Copy/Look Up (usually below) does not cover it.
 if(options?.preferAbove && typeof rect.top==='number'){
  const above=rect.top-height-8;
  if(above>=box.top+12)return{left,top:above};
 }
 return{left,top:Math.max(box.top+12,Math.min(below,box.top+box.height-height-12))};
}
