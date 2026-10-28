"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const vm=require("node:vm");
const fs=require("node:fs");
const path=require("node:path");

function fixture() {
  const elements=[];
  class Element {
    constructor(tag) { this.tag=tag;this.dataset={};this.hidden=false;this.listeners={};this.attributes={};this.children=[];this.srcWrites=0;elements.push(this);
      if(tag==="iframe") {this.contentWindow={location:{href:"about:blank"},postMessage(){},focus(){}};this.contentDocument={documentElement:{lang:"ja"}};}
    }
    append(...nodes){this.children.push(...nodes);}
    addEventListener(event,fn){this.listeners[event]=fn;}
    setAttribute(key,value){this.attributes[key]=value;}
    focus(){}
    set src(value){this._src=value;this.srcWrites++;}
    get src(){return this._src;}
  }
  const document={head:new Element("head"),body:new Element("body"),documentElement:{lang:"ja"},createElement:tag=>new Element(tag),addEventListener(){},activeElement:null};
  const window={addEventListener(){}};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,"public/services.js"),"utf8"),{document,window,location:{origin:"https://game.example"},crypto:{randomUUID:()=>"test-writer"},URL,URLSearchParams,structuredClone,Map,JSON,Array});
  return {window,elements,get:id=>elements.find(node=>node.id===id),frame:kind=>elements.find(node=>node.tag==="iframe"&&node.src.startsWith("/"+kind+"?")),
    load(frame,kind,language,htmlLanguage=language){frame.contentWindow.location.href=`https://game.example/${kind}?lang=${language}`;frame.contentDocument.documentElement.lang=htmlLanguage;frame.listeners.load();},
  };
}

test("service frames never reveal the previous language while a new document loads",()=>{
  const f=fixture();f.window.qqServices.open("account","ja");const frame=f.frame("account");
  assert.equal(frame.hidden,true);assert.equal(f.get("qq-service-loading").hidden,false);
  f.load(frame,"account","ja");assert.equal(frame.hidden,false);
  f.window.qqServices.close();f.window.qqServices.open("account","en");
  assert.equal(frame.hidden,true);assert.equal(f.get("qq-service-loading").textContent,"Loading...");
  assert.equal(f.get("qq-service-panel").attributes["aria-busy"],"true");
  f.load(frame,"account","ja");assert.equal(frame.hidden,true,"late old-language load was revealed");
  f.load(frame,"account","en","ja");assert.equal(frame.hidden,true,"untranslated HTML was revealed");
  f.load(frame,"account","en");assert.equal(frame.hidden,false);assert.equal(f.get("qq-service-loading").hidden,true);
  const requests=frame.srcWrites;f.window.qqServices.close();f.window.qqServices.open("account","en");
  assert.equal(frame.srcWrites,requests,"same-language cached frame was reloaded");assert.equal(frame.hidden,false);
});

test("late inactive-frame loads and rapid language changes cannot reveal the wrong document",()=>{
  const f=fixture();f.window.qqServices.open("account","ja");const account=f.frame("account");f.load(account,"account","ja");
  f.window.qqServices.open("account","en");f.window.qqServices.open("rankings","en");const ranking=f.frame("rankings");
  f.load(account,"account","en");assert.equal(account.hidden,true);assert.equal(ranking.hidden,true);assert.equal(f.get("qq-service-loading").hidden,false);
  f.window.qqServices.open("rankings","ja");f.load(ranking,"rankings","en");assert.equal(ranking.hidden,true);
  f.load(ranking,"rankings","ja");assert.equal(ranking.hidden,false);assert.equal(account.hidden,true);
});
