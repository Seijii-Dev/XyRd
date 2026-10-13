import {test} from "node:test";
import assert from "node:assert/strict";
import {defaults,choices,validate,migrateSettings} from "../src/lib/workflow";

test("Tailscale and reduced settings defaults",()=>{
  assert.equal(defaults.akses,"tailscale");
  assert.deepEqual(choices.akses,["tailscale"]);
  assert.equal(defaults.runner,"github");
  assert.ok(!("storage_boost" in defaults));
  assert.ok(!("samp" in defaults));
  assert.equal(validate({...defaults,microphone:"no"}).microphone,"no");
});

test("legacy removed options are rejected",()=>{
  assert.throws(()=>validate({...defaults,storage_boost:"ya"}));
  assert.throws(()=>validate({...defaults,samp:"ya"}));
});

test("legacy access settings migrate to Tailscale",()=>{
  const m=migrateSettings({akses:"all",tunnel_provider:"ngrok",hostname:"old-host"});
  assert.equal(m.akses,"tailscale");
  assert.equal(m.runner,"github");
  assert.equal(m.rdp_user,"SeijiAdmin");
  assert.ok(!("tunnel_provider" in m));
});
