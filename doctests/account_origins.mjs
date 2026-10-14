import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const c = vm.createContext({});
vm.runInContext(readFileSync(new URL('../src/qml/AccountOrigin.js', import.meta.url),'utf8').replace('.pragma library',''), c);
const card = {signer:'keycard_module',available:false,origin:{devices:[{kind:'keycard',id:'instance:abcdef123456',name:'Travel'},{kind:'keycard',id:'identity:98765432',name:'Backup'}],phrase:{id:'seed12345678'}}};
assert.equal(c.summary(card,'0x123','Savings','0x123…789'), 'Keycard “Travel” · abcdef12 / Keycard “Backup” · 98765432 — Wallet · seed1234 — Savings — 0x123…789');
const source = {signer:'keystore_module',origin:{devices:[{kind:'keystore',id:'local'}],phrase:{id:'verified123',name:'Family'}}};
assert.equal(c.source(source),'This device (Keystore) — Wallet “Family” · verified');
assert.equal(c.source({signer:'keystore_module',origin:{kind:'imported-json'}}), 'This device (Keystore) — Imported file · no phrase recorded');
assert.equal(c.source({signer:'keycard_module'}), 'Keycard (unidentified) — Wallet unknown');
assert.equal(c.source({}), 'Device unknown — Wallet unknown');
assert.equal(c.account('0x123','','0x123…789'),'0x123…789');
console.log('Account origin display checks passed');

assert.equal(c.showWallet(source,[source]),true); // Preserve a user-given wallet name.
const second = {signer:'keystore_module',origin:{devices:[{kind:'keystore',id:'local'}],phrase:{id:'different'}}};
assert.equal(c.showWallet(source,[source,second,card]),true);
assert.equal(c.showWallet(card,[source,second,card]),false);

const usb = {signer:"keycard_shell_module",origin:{devices:[{kind:"keycard_shell",id:"serial1234"}],phrase:{id:"shell:serial1234:abcd1234",name:"Travel"}}};
assert.equal(c.device(usb), "Keycard Shell (USB) · serial12");
assert.equal(c.showWallet(usb,[usb]),true);
