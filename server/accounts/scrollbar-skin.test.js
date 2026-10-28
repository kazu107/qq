"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { createQqServer } = require("../server");

test("Blender scrollbar textures are served identically to Godot assets", async t => {
  const app = createQqServer({ env: {} });
  await new Promise(resolve => app.server.listen(0, "127.0.0.1", resolve));
  t.after(async () => { app.server.closeAllConnections(); await new Promise(resolve => app.server.close(resolve)); });
  const origin = `http://127.0.0.1:${app.server.address().port}`;
  const css = await fetch(origin + "/account/style.css").then(response => response.text());
  for (const orientation of ["v", "h"]) {
    for (const state of ["track", "grabber", "highlight", "pressed"]) {
      const file = `scrollbar_${orientation}_${state}.png`;
      const response = await fetch(`${origin}/account/scrollbars/${file}?v=13`);
      assert.equal(response.status, 200);
      assert.equal(response.headers.get("content-type"), "image/png");
      const png = Buffer.from(await response.arrayBuffer());
      assert.deepEqual(png, fs.readFileSync(path.resolve(__dirname, "../../assets/icons/controls", file)));
      assert.equal(png.readUInt32BE(16), orientation === "v" ? 24 : 160);
      assert.equal(png.readUInt32BE(20), orientation === "v" ? 160 : 24);
      assert(css.includes(file), "CSS must use " + file);
      assert.equal((await fetch(`${origin}/account/scrollbars/${file}`, { method: "HEAD" })).status, 200);
      assert.equal((await fetch(`${origin}/account/scrollbars/${file}`, { method: "POST" })).status, 405);
    }
  }
  assert(css.includes("scrollbar-width:thin") && css.includes("width:12px; height:12px"));
});
