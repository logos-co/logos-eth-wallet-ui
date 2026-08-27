#!/usr/bin/env python3
"""Headless UI assertions for eth_wallet_ui, driven over the QML inspector on port 3768.

Run against a `logos-standalone-app` started with QT_QPA_PLATFORM=offscreen and
QML_INSPECTOR_PORT=3768, with all seven modules staged as the -dev variant, and a local
Anvil on chain 11155111 with Multicall3 planted. See .agents/p10-ui-evidence.md.

Every negative here is a real control: the empty-history check is paired with an assertion
that the same item is INVISIBLE on the other tab, because `findByProperty` ignores
visibility and would otherwise pass against a populated list.
"""

sys.path.insert(0, __import__("os").path.dirname(__file__))
from inspector import call
FAIL=[]
def oid(n):
    m=(call("findByProperty",{"property":"objectName","value":n}).get("matches") or [])
    return m[0]["id"] if m else None
def props(n):
    i=oid(n)
    if i is None: return {}
    raw=call("getProperties",{"objectId":i}).get("properties") or {}
    return {d["name"]:d.get("value") for d in raw} if isinstance(raw,list) else raw
def check(label,got,want,mode="eq"):
    ok=(got==want) if mode=="eq" else (str(want) in str(got))
    print(("  PASS  " if ok else "  FAIL  ")+label+f"   got={got!r}")
    if not ok: FAIL.append(label)
def tab(i):
    r=call("callMethod",{"objectId":oid("ethWalletRoot"),"method":"selectTab","args":[i]})
    time.sleep(0.5)
    return r

# setup through the view's own backend
call("evaluate",{"expression":'logos.callModule("keystore_module","import_private_key",["ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80","pw123456"])'})
call("evaluate",{"expression":'logos.module("eth_wallet_ui").setRpcUrl(11155111,"http://127.0.0.1:8545")'})
call("evaluate",{"expression":'logos.module("eth_wallet_ui").setActiveChain(11155111)'})
time.sleep(3)

print("1) the tab actually moves, and the chip is on BOTH tabs")
for i,name in enumerate(["Tokens","Activity"]):
    tab(i)
    check(f"pages.currentIndex after selectTab({i})", props("pages").get("currentIndex"), i)
    check(f"chip on {name}", props("chainChip").get("text"), "SEPOLIA · TESTNET")

print("2) empty history, asserted by PROPERTY on the Activity tab")
tab(1)
check("historyEmpty.visible", props("historyEmpty").get("visible"), True)
print("   control: it must be FALSE on the Tokens tab, or the assertion proves nothing")
tab(0)
check("historyEmpty.visible on Tokens", props("historyEmpty").get("visible"), False)

print("3) the Send button names the network")
call("callMethod",{"objectId":oid("openSendButton"),"method":"clicked","args":[]}); time.sleep(1)
check("submit label", props("sendSubmitButton").get("text"), "Send on Sepolia (testnet)")

print("4) the seven advanced fee controls")
for n in ["tierSlow","tierNormal","tierFast","maxFeeField","maxPriorityFeeField","gasLimitField","nonceField"]:
    check(f"control {n}", oid(n) is not None, True)

print("5) fee provenance on screen")
check("fee basis", props("feeSourceLabel").get("text"), "Fee basis", "contains")

print("6) the BACKEND's refusal surfaces — priority fee above max fee")
call("evaluate",{"expression":'logos.module("eth_wallet_ui").quote(JSON.stringify({from:"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",to:"0x70997970C51812dc3A010C7d01b50e0d17dc79C8",amount:"1000",maxFeePerGas:"1000",maxPriorityFeePerGas:"999999999"}))'})
time.sleep(1.5)
check("refusal text", props("errorLabel").get("text"), "maxPriorityFeePerGas cannot exceed maxFeePerGas", "contains")
check("errorLabel visible", props("errorLabel").get("visible"), True)

print("7) insufficient funds also comes from the backend")
call("evaluate",{"expression":'logos.module("eth_wallet_ui").quote(JSON.stringify({from:"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",to:"0x70997970C51812dc3A010C7d01b50e0d17dc79C8",amount:"99999000000000000000000"}))'})
time.sleep(1.5)
check("insufficient funds", props("errorLabel").get("text"), "insufficient funds", "contains")

print()
print("RESULT:", "ALL PASS" if not FAIL else f"{len(FAIL)} FAILED -> {FAIL}")
sys.exit(1 if FAIL else 0)
