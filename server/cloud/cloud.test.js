"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID, randomBytes } = require("node:crypto");
const { validatePayload } = require("./store");
const { accountFixture, BrowserSession, testDatabaseEnv } = require("../../tests/helpers/account_fixture");
const save = points => ({ schema_version: 1, current_run: {}, suspended_runs: {}, meta_progress: { points }, settings: { screen_hint: "hub" } });
test("cloud payload rejects device permissions, foreign Ranked ownership and malformed structures", () => {
  assert.doesNotThrow(() => validatePayload(save(10), "owner"));
  assert.throws(() => validatePayload({ ...save(10), settings: { developer_mode: true } }, "owner"));
  assert.throws(() => validatePayload({ ...save(10), current_run: { ranking: { ticket: { user_id: "another" } } } }, "owner"));
  assert.throws(() => validatePayload({ ...save(10), meta_progress: [] }, "owner"));
  assert.throws(() => validatePayload({ ...save(10), unexpected: true }, "owner"));
});
test("cloud owner isolation, CSRF, concurrent devices, retries, revisions, restoration and retention", { skip: !testDatabaseEnv() }, async () => {
  const fixture = await accountFixture();
  try {
    const guest = new BrowserSession(fixture.origin), a = new BrowserSession(fixture.origin), b = new BrowserSession(fixture.origin);
    await a.login(); await a.write("/api/account/username", { username: "CloudA" });
    fixture.mock.state.googleSubject = "cloud-user-b";
    await b.login(); await b.write("/api/account/username", { username: "CloudB" });
    const owner = (await a.profile()).user.id, other = (await b.profile()).user.id;
    const writer = randomUUID(), secondWriter = randomUUID();
    async function request(browser, method, path, body, account = owner, origin = fixture.origin) {
      const profile = await browser.profile();
      return browser.request("/api/cloud/" + path, { method, headers: { "X-QQ-Account": account, "X-QQ-Writer": writer, "X-QQ-Cloud-Version": "2", Origin: origin, "Content-Type": "application/json", "X-CSRF-Token": profile.csrfToken || "" }, ...(body ? { body: JSON.stringify(body) } : {}) });
    }
    assert.equal((await request(guest, "GET", "save")).status, 401);
    assert.equal((await request(b, "GET", "save", null, owner)).status, 409);
    assert.equal((await request(a, "POST", "claim", { writer_id: writer }, owner, "https://evil.invalid")).status, 403);
    assert.equal((await request(a, "POST", "claim", { writer_id: writer })).status, 200);
    const body = { writer_id: writer, base_revision: 0, request_id: randomUUID(), payload: save(50) };
    const first = await (await request(a, "PUT", "save", body)).json(); assert.equal(first.revision, 1);
    const retry = await (await request(a, "PUT", "save", body)).json(); assert.equal(retry.revision, 1);
    assert.equal((await request(a, "PUT", "save", { ...body, request_id: randomUUID() })).status, 409);
    assert.equal((await request(a, "POST", "claim", { writer_id: secondWriter })).status, 409);
    assert.equal((await request(a, "POST", "claim", { writer_id: secondWriter, takeover: true })).status, 200);
    assert.equal((await request(a, "PUT", "save", { ...body, base_revision: 1, request_id: randomUUID() })).status, 409);
    for (let index = 1; index <= 7; index++) {
      const response = await request(a, "PUT", "save", { writer_id: secondWriter, base_revision: index, request_id: randomUUID(), payload: save(50 + index) });
      assert.equal(response.status, 200);
    }
    const history = await (await request(a, "GET", "history")).json(); assert.equal(history.history.length, 5);
    const restored = await (await request(a, "POST", "restore", { writer_id: secondWriter, base_revision: 8, request_id: randomUUID(), revision: 4 })).json();
    assert.equal(restored.revision, 9); assert.equal(restored.payload.meta_progress.points, 53);
    const read = await (await request(a, "GET", "save")).json(); assert.equal(read.payload.meta_progress.points, 53);
    assert.equal((await (await request(b, "GET", "save", null, other)).json()).payload, null);
    assert.equal((await request(b, "POST", "restore", { writer_id: secondWriter, base_revision: 0, request_id: randomUUID(), revision: 4 }, other)).status, 409);
    await request(a, "POST", "release", { writer_id: secondWriter });
    assert.equal((await request(a, "PUT", "save", { ...body, base_revision: 9, writer_id: secondWriter, request_id: randomUUID() })).status, 409);
    assert.equal((await request(a, "POST", "claim", { writer_id: writer })).status, 200);
    await a.write("/api/account/logout"); assert.equal((await request(a, "GET", "save")).status, 401);
  } finally { await fixture.close(); }
});

test("guest transfers commit exactly once, bind the first owner and survive receipt loss", { skip: !testDatabaseEnv() }, async () => {
  const fixture = await accountFixture();
  try {
    const a = new BrowserSession(fixture.origin), b = new BrowserSession(fixture.origin);
    await a.login(); await a.write("/api/account/username", { username: "GuestOwnerA" });
    fixture.mock.state.googleSubject = "guest-owner-b";
    await b.login(); await b.write("/api/account/username", { username: "GuestOwnerB" });
    const users = await Promise.all([a.profile(), b.profile()]);
    const clients = [a, b], writers = [randomUUID(), randomUUID()];
    async function post(index, path, body, protocol = "2") {
      return clients[index].write("/api/cloud/" + path, body, { "X-QQ-Account": users[index].user.id, "X-QQ-Cloud-Version": protocol });
    }
    const identity = { origin_id: randomUUID(), secret: randomBytes(32).toString("base64url") };
    assert.equal((await post(0, "guest-ticket", { guest_identity: identity }, "1")).status, 426);
    const issued = await (await post(0, "guest-ticket", { guest_identity: identity })).json();
    const retryIssue = await (await post(1, "guest-ticket", { guest_identity: identity })).json();
    assert.equal(issued.guest_ticket.id, retryIssue.guest_ticket.id, "A restored pre-issuance source must retain the same server identity");
    const wrong = await post(1, "guest-ticket", { guest_identity: { ...identity, secret: randomBytes(32).toString("base64url") } });
    assert.equal(wrong.status, 404);
    for (let i = 0; i < 2; i++) assert.equal((await post(i, "claim", { writer_id: writers[i] })).status, 200);
    const body = i => ({ writer_id: writers[i], base_revision: 0, request_id: randomUUID(), guest_ticket: issued.guest_ticket, payload: save(50) });
    const rejected = await post(0, "import-guest", { ...body(0), base_revision: 99 });
    assert.equal(rejected.status, 409);
    assert.equal((await (await post(0, "guest-status", { guest_ticket: issued.guest_ticket })).json()).status, "available", "Failed writes must not consume a guest");
    const attempts = [body(0), body(1)];
    const responses = await Promise.all(attempts.map((value, i) => post(i, "import-guest", value)));
    assert.deepEqual(responses.map(response => response.status).sort(), [200, 409]);
    const winner = responses.findIndex(response => response.status === 200), loser = 1 - winner;
    const accepted = await responses[winner].json(), refused = await responses[loser].json();
    assert.equal(accepted.guest_receipt.owner_id, users[winner].user.id);
    assert.equal(refused.error, "guest_already_claimed");
    assert.equal(refused.guest_receipt.owner_id, users[winner].user.id);
    const counts = await fixture.store.pool.query("SELECT claimed_by,import_revision FROM qq_guest_transfers WHERE id=$1", [issued.guest_ticket.id]);
    assert.equal(counts.rows[0].claimed_by, users[winner].user.id);
    assert.equal(counts.rows[0].import_revision, 1);
    const newer = { writer_id: writers[winner], base_revision: 1, request_id: randomUUID(), payload: save(90) };
    const profile = await clients[winner].profile();
    const updated = await clients[winner].request("/api/cloud/save", { method: "PUT", headers: { Origin: fixture.origin, "Content-Type": "application/json", "X-CSRF-Token": profile.csrfToken, "X-QQ-Account": profile.user.id, "X-QQ-Cloud-Version": "2" }, body: JSON.stringify(newer) });
    assert.equal(updated.status, 200);
    const repeated = await (await post(winner, "import-guest", attempts[winner])).json();
    assert.equal(repeated.already_imported, true);
    assert.equal(repeated.revision, 2);
    assert.equal(repeated.payload.meta_progress.points, 90, "Retry after a lost receipt must not roll back later progress");
    const loserSave = (await fixture.store.pool.query("SELECT payload,revision FROM qq_cloud_saves WHERE user_id=$1", [users[loser].user.id])).rows[0];
    assert.equal(loserSave.payload, null); assert.equal(loserSave.revision, 0);
    const sourceLookup = await (await post(loser, "guest-status", { guest_ticket: identity })).json();
    assert.equal(sourceLookup.status, "claimed_elsewhere");
    const issuedAgain = await (await post(loser, "guest-ticket", { guest_identity: identity })).json();
    assert.equal(issuedAgain.guest_receipt.owner_id, users[winner].user.id);
    assert.equal((await post(loser, "import-guest", { ...attempts[loser], request_id: randomUUID() })).status, 409);
  } finally { await fixture.close(); }
});
