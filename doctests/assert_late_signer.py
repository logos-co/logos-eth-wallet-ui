"""Run against a fresh isolated Basecamp profile with Ethereum and Keycard installed.

Seed a public Keycard account fixture before launch; pass its address on the command line.
The profile must not have opened either app yet. No card or signing is required.
LOGOS_INSPECTOR_PORT selects the test instance.
"""
import argparse
import json
import time
from inspector import call

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("address")
args = parser.parse_args()
expected = args.address.lower()


def evaluate(object_id, expression):
    reply = call("evaluate", {"objectId": object_id, "expression": expression}, timeout=55)
    assert "error" not in reply, reply
    return reply.get("result")


content = call("findByType", {"typeName": "ContentViews"})["matches"][0]["id"]
evaluate(content, 'backend.loadUiModule("eth_wallet_ui")')
for _ in range(100):
    roots = call("findByProperty", {"property": "objectName", "value": "ethWalletRoot"})
    if roots.get("count") == 1:
        break
    time.sleep(.2)
root = roots["matches"][0]["id"]
# Let initial discovery fail before loading a provider with an existing account.
time.sleep(8)
assert expected not in [a.lower() for a in json.loads(evaluate(root, "JSON.stringify(accounts)"))]
selected = evaluate(root, "selected")
evaluate(content, 'backend.loadUiModule("keycard_ui")')
# Includes the manager's 30-second unavailable-provider retry interval.
deadline = time.monotonic() + 65
while time.monotonic() < deadline:
    accounts = json.loads(evaluate(root, "JSON.stringify(accounts)"))
    if expected in [a.lower() for a in accounts]:
        break
    time.sleep(1)
else:
    raise AssertionError("Saved Keycard account was not discovered after its provider loaded")
if selected:
    assert evaluate(root, "selected") == selected, "Discovery changed the selected account"
origin = json.loads(evaluate(root, "JSON.stringify(accountWallet(" + json.dumps(args.address) + "))"))
assert origin["signer"] in ("keycard_module", "keycard_shell_module"), origin
# Disconnected accounts must remain selectable for viewing balances and history.
evaluate(root, "backend.selectAccount(" + json.dumps(args.address) + ")")
assert evaluate(root, "selected").lower() == expected
evaluate(root, "backend.refreshAccounts()")
time.sleep(16)
assert evaluate(root, "selected").lower() == expected, "Repeated discovery reset the selection"
print("PASS: late Keycard discovery, provider identity, selection preservation, and disconnected-account selection")
