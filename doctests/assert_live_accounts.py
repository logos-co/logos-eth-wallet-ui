#!/usr/bin/env python3
"""The regression: rename an account in the keystore and the wallet goes on showing the old
name until its view is closed and reopened.

Run against a `logos-standalone-app` started with QT_QPA_PLATFORM=offscreen and the wallet's
modules staged, plus `keystore_custodian` — the doc-test fixture that holds the Tier D
custodian role, because `set_label` refuses every other caller including this view. Point the
harness at that app with LOGOS_INSPECTOR_PORT; it writes REAL keystore state, so only ever
aim it at a fixture you started yourself.

This script NEVER calls refresh(). That absence is the assertion: every check below has to be
carried by the event, and section 4 fails the run if a refresh ever creeps in.

What settles vacuity is not the window but the A/B. Measured on 2026-09-01, aarch64-darwin:
against a keystore whose `set_label` emits nothing, section 2 fails and the picker still reads
`0x3C44…93BC` after 6.2s while 1 and 5 still pass — the user's report exactly. Against a view
that does not subscribe, 6 checks fail across 1, 2 and 3.
"""

import json, os, sys, time
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from inspector import call

# Anvil account #2 — deterministic, and not one assert_ui.py imports, so the two harnesses
# can share a fixture without either one's roster assertions counting the other's account.
KEY = "5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
PW = "pw123456"
NAME = "Treasury"
WINDOW = 6.0

FAIL = []
TOTAL = [0]
def check(label, got, want, mode="eq"):
    TOTAL[0] += 1
    ok = (got == want) if mode == "eq" else (str(want) in str(got))
    print(("  PASS  " if ok else "  FAIL  ") + label + "   got=%r want=%r" % (got, want))
    if not ok:
        FAIL.append(label)

def oid(n):
    m = (call("findByProperty", {"property": "objectName", "value": n}).get("matches") or [])
    return m[0]["id"] if m else None

def props(n):
    i = oid(n)
    if i is None:
        return {}
    raw = call("getProperties", {"objectId": i}).get("properties") or {}
    return {d["name"]: d.get("value") for d in raw} if isinstance(raw, list) else raw

def ev(expr):
    """Evaluate in the VIEW's own scope, so root's properties and functions are in scope.
    Everything goes through JSON.stringify: `evaluate` answers the literal string
    "<QJSValue>" for an array, and a check that iterates THAT walks its characters and
    passes against anything."""
    raw = call("evaluate", {"objectId": oid("ethWalletRoot"),
                            "expression": "JSON.stringify(%s)" % expr}).get("result")
    try:
        return json.loads(raw)
    except (TypeError, ValueError):
        return None

def unwrap(raw):
    """`evaluate` JSON-encodes whatever the expression returned, and these replies are
    themselves JSON strings — so the value arrives quoted twice."""
    for _ in range(2):
        if not isinstance(raw, str):
            break
        try:
            raw = json.loads(raw)
        except ValueError:
            break
    return raw if isinstance(raw, dict) else {"raw": raw}

def custodian(method, args):
    """Drive the keystore through the module that holds the custodian role. Nothing here may
    call keystore_module directly: this view is not the custodian and would be refused."""
    return unwrap(call("evaluate", {"expression": 'logos.callModule("keystore_custodian","%s",%s)'
                                    % (method, json.dumps(args))}).get("result"))

def until(pred, window=WINDOW):
    """The value once `pred` accepts it, and how long that took. Polling the VIEW is not
    polling the wallet: the harness reads a published property, it never asks for a re-read."""
    start = time.time()
    while time.time() - start < window:
        v = pred()
        if v is not None:
            return v, time.time() - start
        time.sleep(0.25)
    return None, time.time() - start

print("0) the view is up, and the custodian fixture is the one that may write")
check("the wallet view is loaded", oid("ethWalletRoot") is not None, True)
# The role is the keystore's own state, not a file to stage: name the fixture through the
# ungated `configure`. That document is TOTAL — a role it does not name is held by nobody —
# so the approver is restated at its default rather than left out. Then read the name back
# rather than trusting the reply.
ROLES = {"approver": "signer_ui", "custodian": "keystore_custodian"}
named = unwrap(call("evaluate", {"expression":
    'logos.callModule("keystore_module","configure",%s)'
    % json.dumps([json.dumps(ROLES)])}).get("result"))
check("the keystore accepted the roles", named.get("ok"), True)
check("and emptied neither, which a partial document would have",
      (named.get("approver"), named.get("custodian")),
      (ROLES["approver"], ROLES["custodian"]))
who = custodian("identity", [])
check("keystore_custodian holds the custodian role",
      who.get("identity") and who.get("identity") == who.get("custodian"), True)

print("1) an account IMPORTED elsewhere appears without this view being told to look")
before = ev("accounts") or []
imported = custodian("import_key", [KEY, PW])
check("the custodian's import succeeded", imported.get("ok"), True)
addr = imported.get("address") or ""
found, secs = until(lambda: True if any(a.lower() == addr.lower() for a in (ev("accounts") or []))
                    else None)
check("the roster grew on its own in %.1fs" % secs, found, True)
check("...and it grew by exactly the imported account", len(ev("accounts") or []), len(before) + 1)

print("2) the RENAME — the case the user reported")
print("   `set_label` moves no count, so a subscriber diffing counts would see nothing here")
named = custodian("name_account", [addr, NAME, PW])
check("the custodian's rename succeeded", named.get("ok"), True)
shown, secs = until(lambda: NAME if ev("accountDisplay('%s')" % addr) == NAME else None)
check("the picker's name for that account changed on its own in %.1fs" % secs, shown, NAME)
check("...and the picker's own model carries it", props("accountPicker").get("model"), NAME, "contains")

print("3) the picker and the address beside it do not disagree")
sel = ev("selected") or ""
check("the picker has a row for the selected account", ev("accountIndex('%s')" % sel) >= 0, True)
check("the address label is the selected account", props("addressLabel").get("text"),
      ev("shortAddr('%s')" % sel))
print("   control: the address is NOT the name — they are two controls answering two questions")
check("the address label is still an address", props("addressLabel").get("text"), "0x", "contains")

print("4) the control — this script never asked for a re-read")
# Spelled in pieces so the check cannot match itself, which is how the first version of it
# reported its own text as a violation.
body = Path(__file__).read_text().split(chr(34) * 3, 2)[2]
for name in ["refresh", "select" + "Account", "load" + "Accounts"]:
    check("nothing here drives %s()" % name, name + "(" in body, False)
check("...and the checks above were not vacuous", ev("accounts") is not None, True)

print("5) a DELETE reaches the view the same way, and moves the selection with it")
# Without this the shrink below is vacuous: a roster that never grew is already "shrunk",
# which is exactly how the un-subscribed control read.
check("the account is on the roster to begin with",
      any(a.lower() == addr.lower() for a in (ev("accounts") or [])), True)
gone = custodian("delete", [addr, PW])
check("the custodian's delete succeeded", gone.get("ok"), True)
left, secs = until(lambda: True if not any(a.lower() == addr.lower()
                                           for a in (ev("accounts") or [])) else None)
check("the roster shrank on its own in %.1fs" % secs, left, True)
sel = ev("selected") or ""
accounts = ev("accounts") or []
check("the selection is one of the accounts that are left",
      (ev("accountIndex('%s')" % sel) >= 0) if accounts else sel == "", True)

print()
if FAIL:
    print("FAILED %d of %d: %s" % (len(FAIL), TOTAL[0], "; ".join(FAIL)))
    sys.exit(1)
print("all %d checks passed" % TOTAL[0])
