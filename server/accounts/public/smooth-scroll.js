"use strict";
(() => {
  const duration = 160, motions = new Map();
  let frame = 0;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const limit = (node, axis) => Math.max(0, axis === 'top' ? node.scrollHeight-node.clientHeight : node.scrollWidth-node.clientWidth);
  const value = (node, axis) => axis === 'top' ? node.scrollTop : node.scrollLeft;
  function cancel() { motions.clear(); cancelAnimationFrame(frame); frame=0; }
  function tick(now) {
    frame=0;
    for (const [node, motion] of motions) {
      if (!node.isConnected || Math.abs(value(node,motion.axis)-motion.last)>1) { motions.delete(node); continue; }
      const ratio=Math.max(0,Math.min(1,(now-motion.start)/duration)), target=Math.min(limit(node,motion.axis),motion.target);
      const next=motion.from+(target-motion.from)*(1-Math.pow(1-ratio,3));
      if(motion.axis==='top') node.scrollTop=next; else node.scrollLeft=next;
      motion.last=value(node,motion.axis);
      if(ratio>=1) motions.delete(node);
    }
    if(motions.size) frame=requestAnimationFrame(tick);
  }
  document.addEventListener('wheel', event => {
    if(event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey || reduced.matches) return;
    if(event.target.closest?.('select,input[type="number"],input[type="range"]')) return;
    const horizontal=Math.abs(event.deltaX)>Math.abs(event.deltaY) || event.shiftKey;
    const delta=horizontal ? (event.deltaX || event.deltaY) : event.deltaY;
    if(!delta) return;
    for(let node=event.target instanceof Element ? event.target : event.target.parentElement;node;node=node.parentElement) {
      const axes=horizontal ? ['left','top'] : ['top','left'];
      for(const axis of axes) {
        const style=getComputedStyle(node), root=node===document.scrollingElement;
        if(!root && !/(auto|scroll)/.test(axis==='top'?style.overflowY:style.overflowX)) continue;
        const current=value(node,axis), max=limit(node,axis);
        if(max<=0) continue;
        if(delta>0 && current>=max-1 || delta<0 && current<=0) break;
        let amount=delta;
        if(event.deltaMode===1) amount*=parseFloat(style.lineHeight)||16;
        if(event.deltaMode===2) amount*=axis==='top'?node.clientHeight:node.clientWidth;
        const old=motions.get(node), same=old?.axis===axis && Math.abs(current-old.last)<=1;
        const base=same && Math.sign(old.target-current)===Math.sign(amount) ? old.target : current;
        const target=Math.max(0,Math.min(max,base+amount));
        if(!same || target!==old.target) motions.set(node,{axis,from:current,target,last:current,start:performance.now()});
        if(!frame) frame=requestAnimationFrame(tick);
        event.preventDefault(); return;
      }
      if(node instanceof HTMLDialogElement && node.open) { event.preventDefault(); return; }
    }
  },{passive:false});
  document.addEventListener('pointerdown',cancel,{passive:true});
  document.addEventListener('keydown',cancel,{passive:true});
  addEventListener('pagehide',cancel);
  reduced.addEventListener('change',cancel);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)cancel();});
})();
