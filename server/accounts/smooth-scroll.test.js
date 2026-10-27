"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const path = require("node:path");

function fixture() {
  class Element {
    constructor(parent = null) { this.parentElement=parent; this.isConnected=true; this.scrollTop=0; this.scrollLeft=0; this.scrollHeight=2000; this.clientHeight=200; this.scrollWidth=300; this.clientWidth=300; this.protected=false; }
    closest() { return this.protected ? this : null; }
  }
  class Dialog extends Element { constructor(parent) { super(parent); this.open=true; this.scrollHeight=this.clientHeight; } }
  const root=new Element(), handlers={}, frames=new Map(), reduced={matches:false,addEventListener(){}};
  let now=0, serial=0;
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,"public/smooth-scroll.js"),"utf8"), {
    Element, HTMLDialogElement:Dialog, Math,
    document:{scrollingElement:root,hidden:false,addEventListener(name,fn){handlers[name]=fn;}},
    addEventListener(name,fn){handlers[name]=fn;}, matchMedia:()=>reduced,
    getComputedStyle:()=>({overflowY:"auto",overflowX:"auto",lineHeight:"24px"}),
    performance:{now:()=>now},requestAnimationFrame(fn){const id=++serial;frames.set(id,fn);return id;},cancelAnimationFrame(id){frames.delete(id);},
  });
  return { root, Element, Dialog, handlers, reduced,
    wheel(node=root,delta=120,extra={}) { const event={target:node,deltaY:delta,deltaX:0,deltaMode:0,defaultPrevented:false,preventDefault(){this.defaultPrevented=true;},...extra};handlers.wheel(event);return event; },
    step(ms){now+=ms;const callbacks=[...frames.values()];frames.clear();for(const fn of callbacks)fn(now);},
    pending:()=>frames.size,
  };
}

test("HTML wheel interpolation preserves distance, coalesces bursts and reverses promptly",()=>{
  const f=fixture();assert.equal(f.wheel().defaultPrevented,true);assert.equal(f.root.scrollTop,0);
  f.step(40);assert(f.root.scrollTop>0&&f.root.scrollTop<120);f.step(120);assert.equal(f.root.scrollTop,120);assert.equal(f.pending(),0);
  f.wheel();f.wheel();f.step(160);assert.equal(f.root.scrollTop,360);
  f.wheel();f.step(20);const current=f.root.scrollTop;f.wheel(f.root,-120);f.step(20);assert(f.root.scrollTop<current);
  f.step(160);assert.equal(f.pending(),0);
});

test("HTML nested edges chain outwards instead of switching to the child's other axis",()=>{
  const f=fixture(), child=new f.Element(f.root);child.scrollTop=1800;child.scrollWidth=900;
  f.wheel(child);f.step(160);assert.equal(f.root.scrollTop,120);assert.equal(child.scrollLeft,0);
  child.scrollTop=0;f.wheel(child,80,{shiftKey:true});f.step(160);assert.equal(child.scrollLeft,80);assert.equal(child.scrollTop,0);
  const dialog=new f.Dialog(f.root);const event=f.wheel(dialog);assert.equal(event.defaultPrevented,true);f.step(160);assert.equal(f.root.scrollTop,120);
});

test("HTML native controls, reduced motion, dragging and external jumps take precedence",()=>{
  const f=fixture(), field=new f.Element(f.root);field.protected=true;
  assert.equal(f.wheel(field).defaultPrevented,false);assert.equal(f.wheel(f.root,100,{ctrlKey:true}).defaultPrevented,false);
  f.reduced.matches=true;assert.equal(f.wheel().defaultPrevented,false);f.reduced.matches=false;
  f.wheel();f.root.scrollTop=500;f.step(160);assert.equal(f.root.scrollTop,500);assert.equal(f.pending(),0);
  f.wheel();f.handlers.pointerdown();f.step(160);assert.equal(f.root.scrollTop,500);
  f.wheel();f.handlers.keydown();f.step(160);assert.equal(f.root.scrollTop,500);
  f.wheel();f.root.isConnected=false;f.step(160);assert.equal(f.pending(),0);
});

test("HTML line/page wheel units and fractional movement are retained",()=>{
  const f=fixture();f.wheel(f.root,2,{deltaMode:1});f.step(160);assert.equal(f.root.scrollTop,48);
  f.wheel(f.root,1,{deltaMode:2});f.step(160);assert.equal(f.root.scrollTop,248);
  f.wheel(f.root,.25);f.step(160);assert.equal(f.root.scrollTop,248.25);
});
