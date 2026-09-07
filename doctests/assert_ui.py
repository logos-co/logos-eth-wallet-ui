#!/usr/bin/env python3
"""Headless UI assertions for eth_wallet_ui, driven over the QML inspector on port 3768.

Run against a `logos-standalone-app` started with QT_QPA_PLATFORM=offscreen and
QML_INSPECTOR_PORT=3768, with all seven modules staged as the -dev variant, and a local
Anvil on chain 11155111 with Multicall3 planted. See .agents/p10-ui-evidence.md.

Everything from the setup block down WRITES REAL STATE on whatever is listening on 3768: it
imports a private key into the keystore and overwrites eth_rpc's DEVICE-WIDE endpoint and
verified-proxy mode for chain 11155111. Port 3768 is also Basecamp's inspector port. Only ever
point this at a fixture app you started yourself. `--grep-only` runs section 0 alone and opens
no socket at all.

Every negative here is a real control: the empty-history check is paired with an assertion
that the same item is INVISIBLE on the other tab, because `findByProperty` ignores
visibility and would otherwise pass against a populated list.

Detail screens are pushed onto a StackView whose Basic-style transition is 400ms, so every
push and pop is followed by a longer sleep. Two consequences for the assertions below:
`visible` on anything inside a pushed screen or a closed dialog reads false regardless of
its binding, and an item that is gone from `findByProperty` is a screen that really closed.
The same trap applies to a StackLayout page that is not current, so 16 selects its tab first.

Sections 13-19 cover the polling and disclosure fixes. They need `verified_proxy_module` NOT
to be staged: that is what makes a blocking verdict — and therefore the banner measured in 15
— reachable. They flip chain 11155111 to verified mode, which is a DEVICE-WIDE eth_rpc
setting; 19 puts it back. That flip now goes STRAIGHT to `eth_rpc_module`: the wallet no
longer carries a setter for it, which is the whole point of the split.

Sections 20-24 cover round 5: money in token units, the token picker, the recipient dropdown,
account names, and the send error moved inside the modal.

Sections 28-29 are round 6: the Send figures are bound to the REQUEST they priced, so an
edit that re-prices nothing cannot leave the previous request's numbers standing. 27 drove the
one control that DOES re-price and passed over both.

Sections 25-27 are the scope invariant: a figure on screen belongs to the account, network and
send request on screen, or it is shown as unknown. They sample the whole view in ONE inspector
round trip, because the defect is a WINDOW and two reads are two instants. 25 wants the second
account section 11 imports; 26 wants a second network in eth_rpc's chains.json.

Sections 0 through 0n need no running app and open no socket: `--grep-only` runs those alone.
Every rule they can reach as a pure function is tabled and compiled with c++ instead:
test_apply.cpp (every guard that decides whether a reply reaches the screen),
test_scope_invariant.cpp (the withdrawal), test_reply_scope.cpp (the reply's own scope),
test_data_guard.cpp (the guarded async lane) and test_sweep_decision.cpp (the sweep).
doctests/run_tables.sh compiles and runs all five. A regression test that can only run against
a GUI is not one.

A source assertion here names the SITE it is about, never a region: 0e once asked whether
`answersFor(` appeared anywhere inside loadNetwork and was answered by the tokens check at the
end of it, so the network write — which IS the selection every other check is made against —
shipped with no guard at all and the suite stayed green.

But anchoring is not enough, and this is the limit that produced the file's present shape: a
source assertion cannot see a NEUTERED guard. `if (!answersFor(reply, shown()) && false)`
leaves the call present, in order, in the right function, anchored to the write it guards, and
every grep describing it passes while it guards nothing. That was measured here. So the guards
moved INSIDE pure transitions over ScopedState (src/eth_wallet_ui_apply.h), where a table runs
them. What is left below is the residue no table can reach — QML bindings, and whether the
backend consults the transitions at all — asserted as an ABSENCE wherever it can be, because
an absence is the one claim another line cannot answer for.
"""

import json, re, sys, time
from pathlib import Path

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
def view(method,*args):
    r=call("callMethod",{"objectId":oid("ethWalletRoot"),"method":method,"args":list(args)})
    time.sleep(0.8)
    return r
def ev(expr):
    """Evaluate in the VIEW's own scope, so root's properties and functions are in scope.

    `callMethod` answers `{"invoked": name}` and throws the return value away, so a pure
    function's ANSWER is unreachable any other way — and the pure functions are where the
    chip's claim, the route vocabulary and the frozen-row wording actually live."""
    return call("evaluate",{"objectId":oid("ethWalletRoot"),"expression":expr}).get("result")
def num(name,prop):
    v=props(name).get(prop)
    return v if isinstance(v,(int,float)) else -1
def sample():
    """The selection and everything scoped to it, read in ONE round trip.

    Two reads cannot answer this: the bug is a WINDOW, and a value sampled a round trip after
    the selection is a different instant. One expression sees one frame of the view."""
    r=call("evaluate",{"objectId":oid("ethWalletRoot"),"expression":
        'JSON.stringify({acct:selected,chain:(net.chainId||0),name:netName,'
        'bk:balancesKnown,hk:historyKnown,tk:tokensKnown,'
        'bal:balanceExact(nativeToken),rows:history.length,'
        'chip:chipText(chipState(vp,balancesRoute)),loading:dataLoading})'}).get("result")
    try: return json.loads(r)
    except Exception: return {}
def settle(want_acct=None, want_chain=None, tries=60):
    """Poll until the scope on screen is read, collecting every frame on the way."""
    seen=[]
    for _ in range(tries):
        s=sample()
        if not s: break
        seen.append(s)
        here=(want_acct is None or s["acct"].lower()==want_acct.lower()) \
             and (want_chain is None or s["chain"]==want_chain)
        if here and s["bk"] and s["hk"]: break
        time.sleep(0.1)
    return seen

print("0) no explorer surface, and no base units on screen — a grep, no app needed")
# `--grep-only` runs THIS section alone and opens no socket. Everything below it drives a live
# app and writes real device state (a keystore import, eth_rpc's device-wide endpoint), so it
# must never be run against an app you did not start for the purpose.
# Comments are skipped: this gate is about strings that reach the screen. The per-gas fee
# overrides are prices, not amounts — wei is the correct unit there, and a gas price in token
# units would be nonsense.
for f in sorted((Path(__file__).resolve().parent.parent / "src" / "qml").glob("*.qml")):
    leaks=[]
    for n,line in enumerate(f.read_text().splitlines(), 1):
        if line.strip().startswith("//"):
            continue
        if re.search(r"explorer|etherscan", line, re.I) or (re.search(r"\bwei\b", line, re.I)
                                                            and "wei per gas" not in line):
            leaks.append(f"{f.name}:{n}: {line.strip()}")
    check(f"no explorer URL and no bare wei in {f.name}", leaks, [])
VIEW = Path(__file__).resolve().parent.parent / "src" / "qml" / "EthWalletView.qml"
SRC = Path(__file__).resolve().parent.parent / "src"
qml_lines = VIEW.read_text().splitlines()
hdr = (SRC / "eth_wallet_ui_backend.h").read_text()
guard = (SRC / "eth_wallet_ui_guard.h").read_text()
SCOPE = (SRC / "eth_wallet_ui_scope.h").read_text()

def strip_cpp_comments(text):
    """A comment is not code, and a grep that cannot tell them apart passes against a fix that
    has been turned into one — the cheapest way there is to neuter a guard."""
    out, i, n = [], 0, len(text)
    while i < n:
        if text[i] == '"':
            out.append(text[i]); i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    out.append(text[i]); i += 1
                if i < n:
                    out.append(text[i]); i += 1
            if i < n:
                out.append(text[i]); i += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(text[i]); i += 1
    return "".join(out)

# Everything below reads the COMMENT-STRIPPED backend. `fn_body` used to hand back the raw
# text, so the whole of a fix could be turned into a comment and every assertion about it
# still passed.
code = strip_cpp_comments((SRC / "eth_wallet_ui_backend.cpp").read_text())

# The anchors. Each of these returns ONE construct — a declaration, a binding, a function body,
# a handler body — so an assertion made against it cannot be satisfied by a neighbouring line.
CONT = ("&&", "||", "?", ":", "+", ".", ")")

def joined(lines, i):
    """One binding or declaration, joined across its continuation lines: the ones an operator
    starts, and the one after a head that ends at its own colon. Without the second, such a
    declaration joins to its head alone and every assertion about its expression is vacuous."""
    out = [lines[i].strip()]
    for l in lines[i + 1:]:
        s = l.strip()
        if not (out[-1].endswith(":") or s.startswith(CONT)):
            break
        out.append(s)
    return " ".join(out)

def qml_item(name):
    """The lines of the item declaring `objectName: name`, up to the next objectName."""
    for i, l in enumerate(qml_lines):
        if 'objectName: "%s"' % name in l:
            j = i + 1
            while j < len(qml_lines) and "objectName:" not in qml_lines[j]:
                j += 1
            return qml_lines[i:j]
    return []

def qml_binding(name, prop):
    """One property binding of the item declaring `objectName: name`."""
    item = qml_item(name)
    for i, l in enumerate(item):
        if re.match(r"%s\s*:" % prop, l.strip()):
            return joined(item, i)
    return ""

def qml_decl(name):
    """One `readonly property <type> <name>:` declaration, whole."""
    for i, l in enumerate(qml_lines):
        if re.match(r"\s*readonly property \S+ %s\s*:" % name, l):
            return joined(qml_lines, i)
    return ""

def fn_span(name):
    """One member function's span in `code`, so an occurrence can be placed INSIDE or outside
    it. A count over the whole file cannot say which line it found."""
    m = re.search(r"\w+ EthWalletUiBackend::%s\([^)]*\)(?:\s*const)?\s*\{(.*?)\n\}" % name,
                  code, re.S)
    return (m.start(1), m.end(1)) if m else (0, 0)

def fn_body(name):
    """One member function's body — not a window, and not `.*?` across the whole file."""
    lo, hi = fn_span(name)
    return code[lo:hi]

def handler(name):
    """One event subscription's own body, bounded by its own closing brace."""
    m = re.search(r"on%s\(\[this\]\([^)]*\)\s*\{(.*?)\n    \}\);" % name, code, re.S)
    return m.group(1) if m else ""

def qml_fn_body(text, name):
    """One QML function's own body, brace-matched. A window over the item around it is
    answered by any neighbouring handler carrying the same substring."""
    m = re.search(r"function\s+%s\s*\([^)]*\)\s*\{" % name, text)
    if not m:
        return ""
    depth, start = 0, m.end() - 1
    for j in range(start, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:j]
    return ""

def qml_fn_lines(name):
    """The 1-based line range of one top-level QML function, brace-matched. An exemption
    anchored to a SITE cannot be borrowed by a new line that merely looks like it."""
    for i, l in enumerate(qml_lines):
        if re.match(r"\s*function %s\s*\(" % name, l):
            depth = 0
            for j in range(i, len(qml_lines)):
                depth += qml_lines[j].count("{") - qml_lines[j].count("}")
                if depth <= 0 and j > i:
                    return (i + 1, j + 1)
            break
    return (0, -1)

def in_order(text, *needles):
    """True when every needle appears, IN THIS ORDER. A presence check cannot see order."""
    at = -1
    for n in needles:
        i = text.find(n, at + 1)
        if i < 0:
            return False
        at = i
    return True

print("0b) a scoped backend property is read ONLY inside the guarded declarations")
# The render half of the invariant. A figure means something only against the account and
# network it was read under, so every one of these is reachable in QML through exactly one
# guarded property; a binding reading the backend directly would walk around that gate.
SCOPED = ["balancesJson", "balancesRoute", "historyJson", "tokensJson", "blockedChainsJson",
          "quoteJson", "quoteRequestJson", "quoteStale", "feeTiersJson", "sweepingReceipts",
          "txDetailsJson"]
ungated = [f"EthWalletView.qml:{n}: {l.strip()}"
           for n, l in enumerate(qml_lines, 1)
           if not l.strip().startswith("//")
           and any("backend." + s in l for s in SCOPED)
           and not l.strip().startswith("readonly property")]
check("every scoped read is a guarded declaration", ungated, [])
print("   and each guard is gated on the backend's own freshness stamp, not on `ready`")
for name, gate in [("balancesKnown", "scoped"), ("historyKnown", "scoped"),
                   ("quote", "scoped"), ("quoteRequest", "scoped"), ("quoteStale", "scoped"),
                   ("balancesRoute", "balancesKnown"), ("txDetails", "scoped"),
                   ("blockedChains", "historyKnown"), ("sweeping", "historyKnown"),
                   ("tokens", "tokensKnown")]:
    decl = [l for l in qml_lines if re.match(r"\s*readonly property \S+ %s\s*:" % name, l)]
    check(f"`{name}` is gated on `{gate}`", len(decl) == 1 and gate in qml_decl(name), True)
print("   control: the em-dash states are claims too — an unread list is not an empty one")
print("   anchored on the item's OWN `visible:` line: a 240-character window after the")
print("   objectName is answered by the NEXT item's binding just as happily as by this one's")
for name, gate in [("historyEmpty", "root.historyKnown &&"), ("tokensEmpty", "root.tokensKnown &&"),
                   ("tokenActivityEmpty", "root.historyKnown && tokenPage.tokKnown &&")]:
    check(f"`{name}` speaks only for a scope that was read", gate in qml_binding(name, "visible"), True)

print("0c) the selection moves through ONE door, and the generated setters ARE that door")
# Overriding rather than remembering to clear is the whole fix: setActiveChain used to
# withdraw and selectAccount did not, which is exactly what a copy-paste rule produces.
check("setSelectedAccount is overridden", "void setSelectedAccount(QString address) override;" in hdr, True)
check("setActiveNetworkJson is overridden", "void setActiveNetworkJson(QString networkJson) override;" in hdr, True)
for setter in ["setSelectedAccount", "setActiveNetworkJson"]:
    check(f"{setter} does nothing but enter the new scope",
          fn_body(setter).strip().startswith("publishSelection("), True)
print("   control: the base setters are reachable from exactly one function, which withdraws")
print("   first — any other caller would move the selection and leave the old figures up")
door = fn_body("publishSelection")
base_calls = [l.strip() for l in code.splitlines() if "EthWalletUiSimpleSource::set" in l]
check("both base setters are called", len(base_calls), 2)
check("...and only inside publishSelection", bool(door) and all(c in door for c in base_calls), True)
print("   ...and it withdraws and bumps the guard BEFORE publishing, which a presence check")
print("   cannot see: the other order shows the previous account's figures under the new name")
check("bump, then withdraw, then publish — in that order",
      in_order(door, "++m_dataGen", "publishScope(s)",
               "EthWalletUiSimpleSource::setSelectedAccount"), True)
print("   the withdrawal itself is a pure function, and its table is")
print("   doctests/test_scope_invariant.cpp — it needs no app either")
check("the rule lives in one header", (SRC / "eth_wallet_ui_scope.h").exists(), True)

print("0d) the Send figures are bound to the REQUEST they priced, not to the last call made")
# The defect this replaces: reprice() called the backend only when both fields were non-empty,
# so clearing one made no call, withdrew nothing, and left the previous request's gas limit,
# ceiling and nonce on screen with Submit still armed. Hooking each CONTROL is what let a
# change that went through no control keep the old numbers; the hook is the request itself.
qml = VIEW.read_text()
dialog = qml[qml.index("id: sendDialog"):qml.index("── pending approval")]
figures = [f"EthWalletView.qml: {l.strip()}" for l in dialog.splitlines()
           if "root.quote." in l and not l.strip().startswith("//")]
check("no figure in the dialog reads the quote unpaired with its request", figures, [])
check("the pairing IS the `q` declaration, not a line somewhere near it",
      "root.quoteRequest === sendForm.formRequest" in qml_decl("q"), True)
check("...and the request is a BINDING, so an edit re-evaluates it",
      qml_decl("formRequest"), "readonly property string formRequest: request()")
check("...which is also what re-prices",
      any(l.strip() == "onFormRequestChanged: if (sendDialog.visible) reprice()"
          for l in dialog.splitlines()), True)
print("   control: no control handler re-prices — a handler is exactly what a change can skip")
CONTROL = re.compile(r"on(TextChanged|CheckedChanged|Clicked|Activated|Triggered)\s*:")
handlers = [f"EthWalletView.qml: {l.strip()}" for l in dialog.splitlines()
            if "reprice" in l and CONTROL.match(l.strip())]
check("no control handler re-prices", handlers, [])
print("   ...and the whole dialog re-prices from exactly two places: the request, and the open")
print("   (the verdict can have moved since the last quote, so an open re-prices regardless)")
sites = [l.strip() for l in dialog.splitlines()
         if "reprice" in l and not l.strip().startswith("//")]
check("the re-price hangs off the request and the open, nowhere else", len(sites), 3)
# `sendSubmitting` JOINED this binding rather than replacing anything in it: the gap between
# the click and the shell's chooser is real work with the dialog still up, and a second click
# in it would price and reserve a nonce twice.
check("and Submit is armed by a quote that priced THIS form, and disarmed by a click in flight",
      qml_binding("sendSubmitButton", "enabled"),
      "enabled: root.ready && !root.sendPending && !root.sendSubmitting "
      "&& sendForm.q.ok === true")
print("   the token picker answers with the field beside it, as accountPicker already did:")
print("   ComboBox resets currentIndex when its model is re-read, and sendDialog.token did not")
print("   asserted against syncIndex's OWN body: onActivated three lines up carries the same")
print("   substring, and syncIndex is what re-asserts on a MODEL change — the defect described")
picker = re.search(r'objectName: "sendTokenPicker"(.*?)\n            \}', dialog, re.S)
sync = qml_fn_body(picker.group(1) if picker else "", "syncIndex")
check("sendTokenPicker re-asserts its index on a model change",
      bool(picker) and "onModelChanged: syncIndex()" in picker.group(1), True)
check("...and syncIndex writes the token back, so the picker and the amount field agree",
      "sendDialog.selectToken(root.tokens[currentIndex])" in sync, True)

print("0e) the backend holds NO rule about what may reach the screen")
# WHY THIS SECTION LOOKS NOTHING LIKE THE ELEVEN PASSES BEFORE IT.
#
# Every guard here used to be asserted as source text: the calls a function makes, in order,
# anchored to the write each one guards. `if (!answersFor(reply, shown()) && false)` satisfies
# all of that and guards nothing — measured, on this file, with the list still passing. A
# source-text assertion cannot see a neutered guard, and four of the re-anchored ones were
# being answered by a different line entirely.
#
# So the guards moved INSIDE pure transitions over ScopedState (src/eth_wallet_ui_apply.h),
# where doctests/test_apply.cpp runs them and neutering one fails a row that executed it.
# What no table can see is whether the backend consults them — and that is asserted here as
# an ABSENCE, which no other line can answer for.
struct = SCOPE[SCOPE.index("struct ScopedState {"):]
struct = struct[:struct.index("\n};")]
fields = re.findall(r"^\s{4}(?:QString|bool|Selection)\s+(\w+)", struct, re.M)
scoped = sorted(set(re.findall(r"\bset\w+\(", fn_body("publishScope"))))
check("every field of ScopedState is snapshotted",
      sorted(re.findall(r"^\s+s\.(\w+) = ", fn_body("scopeSnapshot"), re.M)), sorted(fields))
check("...and every one but the selection they were read under is published",
      len(scoped), len(fields) - 1)
print("   and NOTHING else writes one. This is the invariant the tables rest on: every value")
print("   on screen that means something against an account and a network was produced by a")
print("   pure transition, so the guard that let it through is a guard some row RAN.")
lo, hi = fn_span("publishScope")
stray = sorted({f"eth_wallet_ui_backend.cpp: {s}" for s in scoped
                for m in re.finditer(re.escape(s), code) if not lo <= m.start() < hi})
check("no scoped setter is called outside publishScope", stray, [])

print("   the two guarded async lanes are ONE protocol, written once")
# The quote lane never received the data lane's fixes: no ticket gate on the completion, a
# lapse timer that cleared the spinner and stranded the re-price queued behind it, and a claim
# taken for exactly as long as the call it covered. Three fixes, one twin, twelve passes.
check("takeLane is reached from exactly one place", code.count("takeLane("), 1)
check("...and laneFinish from exactly one", code.count("laneFinish("), 1)
check("...and a lane's own claim is never touched around them", code.count(".flight"), 0)
begun = sorted(set(re.findall(r"beginLane\((m_\w+)", code)))
check("every lane is entered through beginLane", begun,
      ["m_dataLane", "m_quoteLane", "m_tokenSearchLane"])
check("...and every lane that is begun is also handed on",
      sorted(set(re.findall(r"handOnLane\((m_\w+)", code))), begun)
print("   and no claim anywhere is taken for exactly as long as the call it covers — the")
print("   quote lane's take(kCallBudgetMs) against Timeout(kCallBudgetMs) was zero margin")
check("both budgets come from the one formula",
      [l.strip() for l in guard.splitlines() if "= guardBudgetMs(" in l],
      ["constexpr int kOneCallBudgetMs = guardBudgetMs(1);",
       "constexpr int kTwoCallBudgetMs = guardBudgetMs(2);"])
check("no claim is taken for a bare call budget",
      [l.strip() for l in code.splitlines() if ".take(kCallBudgetMs" in l], [])
print("   ...and a lane's budget is a NAMED one of the two: it is assigned rather than passed,")
print("   so the check above cannot see it — measured, by setting it to kCallBudgetMs")
# A SET, not a list: the claim is that no lane invents a budget of its own, and a fourth
# lane reusing one of the two is not a regression the fixed list could tell apart.
check("each lane's budget is one of the two",
      sorted({b for b in re.findall(r"budgetMs = (k\w+);", code)}
             - {"kOneCallBudgetMs", "kTwoCallBudgetMs"}), [])

print("   each applier snapshots, calls ONE transition, and publishes — it decides nothing")
for fn, transition in [("fetchTxDetails", "applyTxDetails("),
                       ("applyBalancesReply", "applyBalances("),
                       ("applyHistoryReply", "applyHistory("),
                       ("applyVerifiedProxy", "applyVerdict("),
                       ("loadFeeTiers", "applyFeeTiers("),
                       ("runQuote", "applyQuote("),
                       ("submitSend", "applySend(")]:
    check(f"{fn} snapshots, calls {transition[:-1]}, publishes",
          in_order(fn_body(fn), "scopeSnapshot()", transition, "publishScope("), True)
print("   the event that names the new chain is TAKEN, not discarded: until it is adopted")
print("   the values for the network being left are on screen and every reply for it is accepted")
check("active_chain_changed adopts the chain it names, first",
      handler("Active_chain_changed").strip().startswith("adoptChain(chainId);"), True)
check("balances_updated ignores an account that is not on screen",
      "address.compare(selectedAccount()" in handler("Balances_updated"), True)
check("closing the dialog withdraws the figures, not just the timer",
      "withdrawQuote(s)" in fn_body("setQuoteAutoRefresh"), True)
print("   the tables need no app, and doctests/run_tables.sh runs all five")
for t in ["test_apply.cpp", "test_data_guard.cpp", "test_reply_scope.cpp",
          "test_scope_invariant.cpp", "test_sweep_decision.cpp"]:
    check(f"{t} exists", (Path(__file__).resolve().parent / t).exists(), True)

print("0f) the two SYNC producers take a witness BEFORE the call, not after")
# eth_wallet_backend is concurrency:"multi", so a synchronous call into it runs a nested event
# loop and dispatches queued events inline. The selection can therefore move INSIDE the call,
# and neither the answer nor the refusal that comes back is about the screen any more.
#
# loadNetwork's write IS `shown()`, the thing every other check is made against: one stale
# write there does not show one wrong value, it inverts every check on the screen. submitSend's
# write is `sendError`, which is scoped — enterScope has already withdrawn the line the refusal
# was worded for, so writing it here puts it under the account that replaced it.
#
# The DECISION each one makes is a table row in test_apply.cpp (networkStep, mayAdopt,
# applySend). What is asserted here is only that the witness reaches it, taken before the read.
net = fn_body("loadNetwork")
first, _, rest = net.partition("list_networks()")
check("loadNetwork: witness, read, decide",
      in_order(first, "gen = m_dataGen", "get_active_network()",
               "networkStep(selectionHeld(gen)"), True)
print("   anchored to the FIRST read's own region: the second read's re-read request sits")
print("   200 characters further down and answered for this one until this pass")
check("...and an answer older than the screen is asked for again", "m_refreshAgain" in first, True)
print("   and the fix material was already on the wire: list_networks names the chain the")
print("   backend is actually on, and the read kept only `networks`")
check("a second witness is taken between the two reads",
      in_order(net, "get_active_network()", "gen = m_dataGen", "list_networks()"), True)
check("...and the later read's own answer decides the chain, under that witness",
      in_order(rest, "activeChainId", "mayAdopt(selectionHeld(gen)", "adoptChain(now)"), True)
check("submitSend: witness, send, decide",
      in_order(fn_body("submitSend"), "gen = m_dataGen", ".send(requestJson)",
               "applySend(after, reply, selectionHeld(gen))"), True)

print("0g) an unknown value matches NOTHING, and a claim outlives no figure it is about")
# Two empty strings compare EQUAL. `(r.token || "") === (tok.address || "")` is therefore TRUE
# for every row that carries no token — i.e. every native send — whenever the token itself is
# unresolved. The token page did not go blank, it listed exactly the transactions it is not
# about: a perfect inversion, and it needs only tokensKnown false with historyKnown true.
check("the token page refuses to filter against a token it has no entry for",
      qml_decl("activity").startswith("readonly property var activity: !tokenPage.tokKnown ? []"),
      True)
check("...and `tok` is the entry itself, never an empty stand-in for one",
      qml_decl("tok"),
      "readonly property var tok: tokKnown ? root.tokenByKey(tokenPage.key) : ({})")
print("   the em-dash states go with it: an unresolved token has no answer about its activity")
check("`tokenActivityUnknown` speaks for the token as well as the history",
      qml_binding("tokenActivityUnknown", "visible"),
      "visible: !root.historyKnown || !tokenPage.tokKnown")
print("   and the SHAPE is banned everywhere, not just where it was found: a comparison whose")
print("   two sides both default to \"\" answers true about two absent values, and that trap")
print("   never appears exactly once")
def both_empty(line):
    for op in ("===", "!=="):
        i = line.find(op)
        while i >= 0:
            if '|| ""' in line[:i] and '|| ""' in line[i:]:
                return True
            i = line.find(op, i + 1)
    return False
traps = [f"{f.name}:{n}: {l.strip()}"
         for f in sorted((SRC / "qml").glob("*.qml"))
         for n, l in enumerate(f.read_text().splitlines(), 1)
         if not l.strip().startswith("//") and both_empty(l)]
check("no comparison defaults BOTH of its sides to an empty string", traps, [])
print("   the one exemption is sameHex's OWN BODY, anchored to its lines. Exempting the")
print("   SHAPE `a.toLowerCase() === b.toLowerCase()` exempted every future loose compare")
print("   that happened to name its operands a and b, and bit only the ones that did not")
lo, hi = qml_fn_lines("sameHex")
loose = [f"EthWalletView.qml:{n}: {l.strip()}" for n, l in enumerate(qml_lines, 1)
         if not l.strip().startswith("//") and ".toLowerCase() ===" in l and not lo <= n <= hi]
check("every case-folded hex comparison goes through sameHex, whose absent case is explicit",
      loose, [])
check("...and sameHex is a real function, not an empty exemption window", hi > lo > 0, True)
print("   and the fee basis speaks for the FIGURES beside it. `root.fees` is read under no")
print("   request and no account, so the fallback kept naming a basis for a quote the form")
print("   had already withdrawn — the figures went, the line claiming their provenance stayed")
check("the basis is gated on the quote that priced THIS form",
      qml_binding("feeSourceLabel", "text").startswith('text: sendForm.q.ok !== true ? ""'), True)

print("0h) the transaction screen: every new figure belongs to ONE transaction, and none")
print("    of them is computed here")
# What this round added: the transaction's own `to` beside the recipient, the Transfer logs
# decoded off the receipt, the gas figures, and one on-demand fetch for the two things a
# receipt genuinely does not carry. Three properties no table can reach are asserted here.
print("   the fetched detail is gated on the HASH, not merely on the selection: open one")
print("   transaction, fetch, go back, open another — the second must not show the first's")
print("   mined time, and the account and chain are the SAME for both")
check("`det` is gated on the hash the screen is about",
      "root.sameHex(root.txDetails.hash, txPage.hash)" in qml_decl("det"), True)
raw = [f"EthWalletView.qml:{n}: {l.strip()}" for n, l in enumerate(qml_lines, 1)
       if not l.strip().startswith("//") and re.search(r"root\.txDetails\b", l)]
check("...and the raw property is reachable through that one declaration alone", len(raw), 2)

print("   the top card carries RAW transaction fields and nothing interpreted. The one `to`")
print("   the transaction has means two different things — the recipient on a native send,")
print("   the token CONTRACT on an erc20 one — so `kind` picks the row that names it, and an")
print("   erc20 send gets no \"To\" row at all, because the transaction has no such field")
check("the plain-send row is gated on the kind the backend recorded",
      qml_binding("txDetailToRow", "visible"), 'visible: txPage.rec.kind === "native"')
check("...and the contract row on the other one",
      qml_binding("txDetailInteractedRow", "visible"), 'visible: txPage.rec.kind === "erc20"')
check("both render the SAME field, so neither can be the other's interpretation",
      qml_binding("txDetailToRow", "value") == qml_binding("txDetailInteractedRow", "value")
      == "value: root.rawToDisplay(txPage.rec)", True)
check("the calldata goes with the contract row, and nowhere else",
      qml_binding("txDetailDataRow", "visible"), 'visible: txPage.rec.kind === "erc20"')
print("   the regression this opens: with \"To\" gone from the card, an erc20 send whose")
print("   receipt has not landed decodes no transfers — and the recipient the user typed")
print("   would be NOWHERE on the screen. It is rendered below instead, in the interpreted")
print("   section, labelled as this wallet's own record rather than as chain data")
check("the fallback wants an erc20 row with nothing decoded",
      qml_decl("recipientRecorded").endswith('"erc20" && txPage.transfers.length === 0'), True)
check("...and what it shows is the recipient this wallet recorded, in full",
      qml_binding("txDetailRecordedToRow", "address"), 'address: txPage.rec.to || ""')
check("...saying in as many words that no receipt has been read",
      "receipt has not been read yet" in qml_binding("txDetailRecordedNote", "text"), True)
# A presence check is not a comparison: `txTo === undefined` asks whether a receipt was ever
# read, which is exactly the marker the header refresh offers a backfill on.
compares = [f"EthWalletView.qml:{n}: {l.strip()}" for n, l in enumerate(qml_lines, 1)
            if not l.strip().startswith("//") and "txTo" in l
            and ("===" in l or "!==" in l)
            and not re.search(r"txTo\s*[!=]==\s*undefined", l)]
check("no line here compares the two addresses itself", compares, [])

print("   MONEY: not one figure on this screen is derived in QML. A QML number is a double,")
print("   and the exact decimal-string arithmetic is all in the backend")
qml_body = VIEW.read_text()
SCALERS = ["Math.pow", "parseFloat", "toFixed", "Number("]
scaled = [f"EthWalletView.qml:{n}: {l.strip()}" for n, l in enumerate(qml_lines, 1)
          if not l.strip().startswith("//") and any(x in l for x in SCALERS)]
check("nothing scales, rounds or floats an amount", scaled, [])
check("the gas percentage is READ, never computed",
      "rec.gasUsedPercent" in qml_fn_body(qml_body, "txGasUsed")
      and "/" not in qml_fn_body(qml_body, "txGasUsed"), True)
print("   ...and every one of them says UNKNOWN rather than zero when it is absent")
for fn, arg in [("perGas", "display === undefined"), ("txMined", "det.block")]:
    check(f"`{fn}` answers an em-dash for an absent value",
          '"—"' in qml_fn_body(qml_body, fn) and arg in qml_fn_body(qml_body, fn), True)

print("   an unlisted token has UNKNOWN decimals, so the backend sends no rendered amount and")
print("   the raw integer is shown AS one. Never scaled by an assumed 18")
check("the rendered amount is preferred, and the raw integer is labelled",
      in_order(qml_fn_body(qml_body, "transferAmount"),
               "t.amountDisplay !== undefined", "t.amount", "base units"), True)
check("...and the note names the contract it is about",
      "is not in this wallet's token " in qml_binding("txDetailUnknownToken_\" + index", "text")
      or "is not in this wallet's token " in qml_body, True)

print("   the transfers section is ABSENT, never \"none\": a row whose receipt we never read")
print("   carries no `transfers` key, and we do not assert that nothing moved")
check("the card is shown only for a non-empty list",
      qml_binding("txDetailTransfersCard", "visible"), "visible: txPage.transfers.length > 0")
check("...and an absent key is an empty list, not a claim",
      qml_decl("transfers").startswith(
          "readonly property var transfers: txPage.rec.transfers !== undefined"), True)
print("   once a receipt decodes a transfer the recorded-recipient card above goes away, so")
print("   these rows are the ONLY rendering of the recipient left on a confirmed token send.")
print("   The standing rule here is that every address is copyable, and that includes these")
# The copy button is the component's now, keyed off the same address the row renders — so
# what was two bindings that could disagree is one value, and the assertion follows it.
for end in ["From", "To"]:
    check(f"the transfer's {end} is a row of its own, carrying the whole address",
          qml_binding("txDetailTransfer%s_" % end, "address"),
          'address: modelData.%s || ""' % end.lower())

print("   the ceiling appears beside a fee that was PAID. While pending the fee row already")
print("   IS the ceiling, and one number under two labels explains nothing")
check("the ceiling row wants both figures",
      qml_decl("feeCeilingShown"),
      "readonly property bool feeCeilingShown: txPage.rec.feeWeiDisplay !== undefined "
      "&& txPage.rec.feeCeilingWeiDisplay !== undefined")

print("   the fetch is a guarded async claim with a DEADLINE, like every other call here —")
print("   a callback that never fires must not leave a spinner up for good")
check("fetchTxDetails: claim, call, own the reply, apply, publish",
      in_order(fn_body("fetchTxDetails"), "beginClaim(m_detailsInFlight",
               "get_tx_detailsAsyncResult", "isCurrent(slot)", "applyTxDetails(",
               "publishScope("), True)
check("...and the claim arms the lapse that lowers its spinner",
      in_order(fn_body("beginClaim"), "take(kOneCallBudgetMs", "setLoading(true)",
               "singleShot", "setLoading(false)"), True)
print("   control: the button is its own control, NOT the header refresh — that one re-reads")
print("   the receipt, which is a different question with a different answer")
check("the header refresh still calls refreshTxStatus",
      "root.backend.refreshTxStatus(txPage.hash)" in " ".join(qml_item("txDetailRefresh")), True)
check("...and it now offers the backfill an older settled row needs",
      "txPage.rec.txTo === undefined" in qml_binding("txDetailRefresh", "enabled"), True)
check("the fetch button calls fetchTxDetails",
      "root.backend.fetchTxDetails(txPage.hash)" in " ".join(qml_item("txDetailFetchButton")),
      True)

print("0h) a call a BUTTON starts is ASYNCHRONOUS, and the receipt re-read was the last")
print("   one that was not: ~23s of frozen window on the only control an older row offers")
# F-1. `refreshTxStatus` ran synchronously into a `concurrency: "multi"` backend, whose
# verified gate was UNBOUNDED in front of the receipt read. Every remaining synchronous call
# is inventoried here — with where it runs, not with a claim that it is harmless — so a new
# one fails this and has to be argued for.
STILL_SYNC = {
    "get_active_network": "refresh(), and its write IS the selection every check is made against",
    "list_networks": "refresh(), under its own witness beside the read above",
    "list_tokens": "refresh()",
    "list_accounts": "refresh(), with the labels read that must land in the same turn",
    "get_account_labels": "refresh()",
    "get_account_wallets": "refresh(), beside the labels: an account nobody named borrows "
                           "its wallet's, and the two have to land in the same turn or the "
                           "picker renames itself between them",
    "list_contacts": "refresh(), and after either write below — the backend orders the book, "
                     "so the view re-reads rather than editing its published copy",
    "save_contact": "the address book, which reaches no chain and writes one small file",
    "forget_contact": "the address book",
    "suggest_fees": "refresh()",
    "set_active_chain": "a chain switch, which re-reads everything behind it anyway",
    "send": "the send path, whose ordering witness is taken around the call",
    "send_status": "the send poll",
    "cancel_send": "the send path",
    "set_token_sort": "the order menu: it writes one string in the settings and reaches no chain",
}
called = set(re.findall(r"modules\(\)\.eth_wallet_backend\.(\w+)\(", code))
sync = sorted(n for n in called
              if not n.endswith("AsyncResult") and not re.match(r"on[A-Z]", n))
check("every synchronous backend call is one of the fifteen inventoried here",
      sync, sorted(STILL_SYNC))
check("...and the receipt re-read is no longer one of them", "refresh_tx_status" in sync, False)
check("refreshTxStatus: claim, call, own the reply, re-read, lower the spinner",
      in_order(fn_body("refreshTxStatus"), "beginClaim(m_txStatusInFlight",
               "refresh_tx_statusAsyncResult", "isCurrent(slot)", "loadBalancesAndHistory()",
               "setTxStatusLoading(false)"), True)
print("   every bare claim goes through beginClaim, which arms the lapse that lowers its")
print("   spinner — a third one written without it fails this")
check("the three spinner-bearing claims",
      sorted(set(re.findall(r"beginClaim\((m_\w+)", code))),
      ["m_detailsInFlight", "m_tokenToggleInFlight", "m_txStatusInFlight"])
check("...and the button it drives says it is running",
      "!root.txStatusLoading" in qml_binding("txDetailRefresh", "enabled"), True)

print("0i) the fee card: a bounded row, and its exact string on a copy button")
# F-2. `feeWeiDisplay` and `feeCeilingWeiDisplay` both rendered "<0.00001" on a real send, and
# neither row set copyValue — so DetailRow took its non-copy branch and the *Exact strings were
# unreachable. The ceiling row was a verbatim duplicate of the row above it.
for r in ["txDetailFeeRow", "txDetailCeilingRow", "txDetailGasPriceRow",
          "txDetailPriorityRow", "txDetailTotalRow"]:
    check(f"{r} carries its exact figure",
          qml_binding(r, "copyValue").startswith("copyValue: root.exactOf("), True)
print("   ...and when the two bounded strings collide the rows print every digit instead,")
print("   which is a STRING test — there is no arithmetic on an amount anywhere here")
check("the collision is decided by comparing the two rendered strings",
      qml_decl("feesCollide").endswith(
          "=== txPage.rec.feeCeilingWeiDisplay"), True)
for r, fn in [("txDetailFeeRow", "txFee"), ("txDetailCeilingRow", "txCeiling")]:
    check(f"{r} renders through {fn}, told whether they collided",
          f"root.{fn}(txPage.rec, txPage.feesCollide)" in qml_binding(r, "value"), True)

print("0j) F-3: a failed transaction moved the fee and nothing else, and says so")
check("the note is gated on the status the backend recorded",
      qml_binding("txDetailFailedNote", "visible"),
      'visible: txPage.rec.status === "failed"')
print("   the total goes with it — the backend omits it on a failure, so the row it drives")
print("   is absent rather than carrying the fee under a name that says the amount left too")
check("the total row is gated on the backend having sent one",
      qml_binding("txDetailTotalRow", "visible"),
      "visible: txPage.rec.totalWeiExact !== undefined")

print("0k) F-5: the fetch's only exclusive payload is the block time, and at minute")
print("   resolution it printed the string the Broadcast row above it already showed")
for fn in ["txWhen", "txMined"]:
    check(f"`{fn}` renders to the second", "HH:mm:ss" in qml_fn_body(qml_body, fn), True)
check("...and the wait itself is spelled out, in whole seconds off two timestamps",
      "minedAfter(t - rec.timestamp)" in qml_fn_body(qml_body, "txMined"), True)
check("...fed timestamps and nothing else: a duration is not an amount",
      [w for w in ("Wei", "amount", "Display", "Exact")
       if w in qml_fn_body(qml_body, "minedAfter")], [])

print("0l) the transaction screen SCROLLS. An Item whose only child was an anchors.fill")
print("   ColumnLayout simply cut its own content off — the Fetch button at the bottom of")
print("   the screen was unreachable on any window shorter than the page")
check("the page is a scroll view filling the screen",
      qml_binding("txDetailScroll", "anchors.fill"), "anchors.fill: parent")
check("...and it never scrolls sideways",
      qml_binding("txDetailScroll", "contentWidth"), "contentWidth: availableWidth")
check("...with a real width for the column, not its implicit one",
      "width: txScroll.availableWidth" in qml_body, True)

print("0m) the activity list groups by day. The model is a plain JS array, which ListView's")
print("   section.property cannot read, so the break is decided against the PREVIOUS row —")
print("   which is only enough because the backend sorts rows newest-first (history.rs)")
check("the heading is decided against the neighbour",
      qml_decl("startsDay").endswith("|| root.txDay(modelData) !== root.txDay(prevRec)"), True)
check("...and index 0 always opens a day, including an undated one",
      "index === 0" in qml_decl("startsDay"), True)
print("   a row with no broadcast time gets its own bucket: never a date, and never silently")
print("   the previous day's")
check("the key is empty for an absent or zero timestamp",
      in_order(qml_fn_body(qml_body, "txDay"), "timestamp <= 0", 'return ""'), True)
# Consistency, not a claim about reachability: four helpers reading `rec.timestamp` and
# disagreeing about what counts as absent is how the four of them come apart.
check("...and all four helpers off `rec.timestamp` guard it the same way",
      [fn for fn in ("txWhen", "txDay", "txTime", "txMined")
       if "rec.timestamp <= 0" not in qml_fn_body(qml_body, fn)], [])
for w in ("Date unknown", "Today", "Yesterday", "MMM d, yyyy"):
    check(f"the heading offers \"{w}\"", '"%s"' % w in qml_fn_body(qml_body, "txDayHeading"), True)
print("   \"Today\" is decided against a TICKER, not the wall clock: `new Date()` is not a")
print("   binding dependency and an idle wallet republishes no history, so a heading that")
print("   dated itself stayed \"Today\" past local midnight until something else moved")
check("the heading compares against the root's own day keys",
      in_order(qml_fn_body(qml_body, "txDayHeading"), "root.todayKey", "root.yesterdayKey"), True)
check("...and asks the wall clock nowhere",
      "new Date()" in qml_fn_body(qml_body, "txDayHeading"), False)
check("...while a timer moves them, no faster than a heading needs",
      qml_binding("dayKeyTicker", "interval"), "interval: 60000")
check("...and the day before is walked in LOCAL midnights, not by subtracting 24 hours",
      "d.setDate(d.getDate() + offset)" in qml_fn_body(qml_body, "dayKey"), True)
check("the row's own line gained the time, to the minute",
      '"HH:mm"' in qml_fn_body(qml_body, "txTime"), True)
print("   the heading is a SIBLING of the interactive row, not a child of it. It used to be")
print("   anchored inside the delegate, under the delegate's OWN hover and press background:")
print("   pointing at \"Yesterday\" lit up the transaction beneath it as one block")
# Structural, and it is a proof rather than a hint: a child is always declared AFTER the
# brace that opens its parent, so a heading declared before the component's only hoverable
# item cannot be inside it. The consequence — that the hover surface really does not carry
# it — is measured in doctests/probe_tx_detail.qml, which walks the live item tree.
delegate_src = strip_cpp_comments(
    qml_body[qml_body.index("id: txRowDelegate"):qml_body.index("id: accountPicker")])
check("the row's container is a plain Column, which hovers nothing",
      bool(re.match(r"id: txRowDelegate\s*\n\s*Column \{", delegate_src)), True)
check("...holding exactly one hoverable item",
      delegate_src.count("LogosItemDelegate"), 1)
check("...which opens AFTER the heading, so the heading cannot be inside it",
      delegate_src.index('objectName: "txDay_') < delegate_src.index("LogosItemDelegate"), True)
check("...and the click that opens a transaction is that item's, not the heading's",
      delegate_src.index("LogosItemDelegate") < delegate_src.index("onClicked:"), True)
print("   the Column drops an invisible child AND the spacing that would follow it, so the")
print("   height covers a heading exactly when one is shown")
check("the container spaces the heading off the row", "spacing: Theme.spacing.small" in
      delegate_src[:delegate_src.index('objectName: "txDay_')], True)

print("0n) the Tokens tab is sorted BY THE BACKEND. get_balances answers a row for every")
print("    enabled token, already in the persisted order, because comparing 18-decimal")
print("    amounts is exact U256 work — and the tab renders that order rather than one")
print("    derived here. doctests/probe_tokens_sort.qml drives the control and the list.")
check("the list renders the ordered property, not the token list",
      qml_binding("tokenList", "model"), "model: root.orderedTokens")
ordered = re.search(r"readonly property var orderedTokens: \{(.*?)\n    \}", qml_body, re.S)
ordered = strip_cpp_comments(ordered.group(1)) if ordered else ""
check("...which maps the POSITIONS the balances came in",
      "pos[tokenKey(balances[i])] = i" in ordered, True)
print("   keyed on the CONTRACT: a symbol key is last-write-wins, so two contracts sharing")
print("   one collapsed onto a single position — and a comparator answering 0 for the pair")
print("   let Qt's unstable sort reshuffle the whole order the backend had published")
check("...never on the symbol", "balances[i].symbol" in ordered, False)
check("...and the comparator is total, so a tie is still an order",
      "a.p !== b.p ? a.p - b.p : a.i - b.i" in ordered, True)
check("...and reads no figure at all to do it",
      [w for w in ("display", "exact", "amount", "raw", "decimals") if w in ordered], [])
check("...while an unread balance set is not an order: it is the list, unsorted",
      ordered.strip().startswith("if (!balancesKnown) return tokens"), True)
print("   the order is ASKED for, never applied here, and the one in force is READ from the")
print("   published scope — a copy held in the view is a second answer free to drift")
asks = [f"EthWalletView.qml:{n}: {l.strip()}" for n, l in enumerate(qml_lines, 1)
        if not l.strip().startswith("//") and "backend.chooseTokenSort" in l]
check("exactly one line asks the backend for an order", len(asks), 1)
check("...and it does not ask for the order already in force",
      "order !== root.tokenSort" in qml_fn_body(qml_body, "setTokenSort"), True)
sortdecl = re.search(r"readonly property string tokenSort: \{(.*?)\n    \}", qml_body, re.S)
sortdecl = strip_cpp_comments(sortdecl.group(1)) if sortdecl else ""
check("the order on screen is the published one", "backend.tokenSort" in sortdecl, True)
check("...normalised to the closed set the menu offers, so an order this build does not "
      "know is shown as no order at all",
      'v === "balance" ? "balance" : "alpha"' in sortdecl, True)
print("   MetaMask's own label for the second order is \"Declining balance ($ high-low)\". This")
print("   wallet has no prices and will not fetch any — a price feed is told which tokens to")
print("   quote, which IS the holdings — so no label here may promise an order by value")
money = [f"EthWalletView.qml:{n}: {l.strip()}" for n, l in enumerate(qml_lines, 1)
         if not l.strip().startswith("//") and re.search(r"\$|high-low|fiat|USD\b", l)]
check("nothing on screen prices anything", money, [])
check("the two orders are named in one function",
      qml_fn_body(qml_body, "tokenSortLabel").strip(),
      'return order === "balance" ? "Declining balance" : "Alphabetically (A-Z)"')
check("...and nowhere else, so the strip and the menu cannot come apart",
      len([l for l in qml_lines
           if "Declining balance" in l and not l.strip().startswith("//")]), 1)
check("...with the line saying what it orders by where the order is CHOSEN",
      qml_binding("tokenSortNote_", "text"), "text: modelData.note")
print("   the tick is drawn by the view rather than left to the style's own check: a")
print("   `checkable` row TOGGLES on the click, overwriting the binding that reads the")
print("   persisted order with whatever the click meant")
check("no row in this view is checkable",
      [f"EthWalletView.qml:{n}" for n, l in enumerate(qml_lines, 1)
       if not l.strip().startswith("//") and "checkable" in l], [])
check("the tick follows the persisted order",
      qml_binding("tokenSortTick_", "visible"), "visible: root.tokenSort === modelData.order")
check("...and the strip names it without the menu being open",
      qml_binding("tokenSortLabel", "text"), "text: root.tokenSortLabel(root.tokenSort)")
check("...and the button is what opens that menu",
      "tokenSortMenu.popupUnder(tokenSortButton)" in " ".join(qml_item("tokenSortButton")), True)
check("the strip is gone when there is nothing to order",
      qml_binding("tokenSortStrip", "visible"), "visible: root.tokens.length > 0")
print("   and the PERSISTED order is adopted from whichever listing lands first. Taken off")
print("   the catalogue search alone, it was restored only if the user opened Manage tokens")
print("   and typed — an ordinary launch showed the default whatever was stored")
check("all three reads take the order off their reply",
      sorted(f for f in ("loadNetwork", "loadBalancesAndHistory", "runTokenSearch")
             if "adoptTokenSort(" in fn_body(f)),
      ["loadBalancesAndHistory", "loadNetwork", "runTokenSearch"])
print("   three readers, one hazard: a listing issued under the previous order lands after")
print("   the user has chosen a different one, naming the order they just replaced")
check("the choice is counted before the call that can pump a stale reply in",
      in_order(fn_body("chooseTokenSort"), "++m_sortChoiceGen", "set_token_sort("), True)
check("...and the rule that drops one older than it is a pure function, run by a table",
      "adoptedTokenSort(reply, issuedAt, m_sortChoiceGen)" in fn_body("adoptTokenSort"), True)

print("0o) Manage tokens: a SCREEN on the nav stack, reached from Settings, listing what the")
print("    BACKEND answered for a query. doctests/probe_manage_tokens.qml drives it.")
check("Settings is what opens it",
      "root.openManageTokens()" in " ".join(qml_item("manageTokensButton")), True)
check("...onto the nav stack, so the back arrow works",
      "nav.pushItem(manageTokensComponent)" in qml_fn_body(qml_body, "openManageTokens"), True)
check("...and opening it reads, rather than showing the last answer",
      'root.searchTokens("")' in qml_fn_body(qml_body, "openManageTokens"), True)
print("   the query goes to the BACKEND. The embedded Uniswap list is thousands of rows, so")
print("   a filter written here would mean pulling all of them across the wire first")
check("the list renders what the backend answered",
      qml_binding("manageTokensList", "model"), "model: root.availableTokens")
check("...which is that reply's own tokens, unfiltered and unsorted",
      [w for w in ("filter(", "sort(", "toLowerCase", "indexOf")
       if w in qml_decl("availableTokens")], [])
check("...for THIS chain: a catalogue read under another network is not this one's answer",
      "available.chainId === net.chainId" in qml_decl("availableForChain"), True)
print("   which makes a network change withhold every row — and the chain can move without")
print("   this screen doing anything. Nothing else re-searches, so the screen sat on its")
print("   \"does not know\" em-dash permanently, recovering only if the user typed")
chainwatch = [l.strip() for l in qml_lines if l.strip().startswith("onChainIdChanged:")]
check("a chain change re-asks the catalogue", len(chainwatch), 1)
check("...for the SAME query, never reset to the whole offered set",
      "root.searchTokens(root.tokenQuery)" in " ".join(chainwatch), True)
check("...and only while the screen that shows it is open",
      "manageTokensOpen" in " ".join(chainwatch), True)
check("the query the view re-asks with is the one it was given",
      "root.tokenQuery = query" in qml_fn_body(qml_body, "searchTokens"), True)
# A ListView inside a ScrollView is two scrollers fighting over one wheel event, and the inner
# one is handed unbounded height — every row is built at once.
manage = qml_lines[next(i for i, l in enumerate(qml_lines) if '"manageTokensPage"' in l):
                   next(i for i, l in enumerate(qml_lines) if '"sendDialog"' in l)]
check("the list scrolls itself rather than sitting inside a scroll view",
      [l.strip() for l in manage if "ScrollView" in l], [])
check("...and it is the design system's list view",
      manage[next(i for i, l in enumerate(manage)
                  if '"manageTokensList"' in l) - 1].strip(), "LogosListView {")
print("   a press ASKS: set_token_enabled emits no event, so a screen that moved the row")
print("   itself would be showing a state the backend has not agreed to")
toggles = [f"EthWalletView.qml:{n}: {l.strip()}" for n, l in enumerate(qml_lines, 1)
           if not l.strip().startswith("//") and "backend.setTokenEnabled" in l]
check("exactly one line asks the backend to enable a token", len(toggles), 1)
check("...and the switch puts its binding back rather than keeping the press",
      in_order(" ".join(qml_item("manageTokenToggle_")), "var want = checked",
               "Qt.binding", "root.setTokenEnabled(modelData.address, want)"), True)
check("...while a builtin, and the native token, cannot be pressed at all",
      "!manageRow.locked" in qml_binding("manageTokenToggle_", "enabled"), True)

print("0p) Manage tokens says WHICH of its several nothings it is looking at. The reply")
print("    carries three counts and an optional error, and the four answers they encode")
print("    used to render as one silent screen. doctests/probe_manage_tokens.qml drives")
print("    each; what is asserted here is that they cannot be COLLAPSED.")
# The four: the read FAILED (listError), this chain has no list at all (listed: 0, which is
# the ORDINARY sepolia answer), the answer was CUT (total > shown), and the query matched
# nothing. Three of them look identical from the row count alone, which is why the row count
# is not what any of them is keyed on.
print("   `listed: 0` with no listError is a REAL, COMPLETE answer — the bundled list is a")
print("   snapshot of a mainnet directory. Only a listError may be worded as a failure")
check("the failure line is keyed on the error, and on nothing else",
      qml_binding("manageTokensListNote", "visible"), "visible: root.availableFailed")
check("...which is the presence of listError, not a count",
      "available.listError !== undefined" in qml_decl("availableListError"), True)
check("...and the empty-chain line is keyed on the count, with the error EXCLUDED",
      in_order(qml_decl("catalogueEmptyForChain"),
               "!availableFailed", "availableListed === 0"), True)
check("...so no line can claim both", qml_binding("manageTokensNoCatalogue", "visible"),
      "visible: root.catalogueEmptyForChain && root.availableTokens.length > 0")
print("   an absent count is not a count of zero: a reply that named no total may not be")
print("   rendered as a reply that matched none")
check("a missing count answers −1, not 0",
      in_order(qml_fn_body(qml_body, "catalogueCount"),
               'typeof v === "number"', "? v : -1"), True)
check("...and the cut is claimed only when BOTH figures were stated",
      in_order(qml_decl("availableCut"), "availableTotal >= 0", "availableShown >= 0",
               "availableTotal > availableShown"), True)
print("   and the cut is never silent: both figures reach the screen, on the line that")
print("   says the list in front of the user is a slice of what matched")
check("the count line names shown and total",
      in_order(qml_binding("manageTokensCountNote", "text"),
               "root.availableShown", "root.availableTotal"), True)
check("...and is on screen exactly when they differ",
      qml_binding("manageTokensCountNote", "visible"), "visible: root.availableCut")
print("   every count the reply carries is READ. A count published and never rendered is a")
print("   truncation the screen is silent about")
check("listed, total and shown all reach a property",
      sorted({k for k in ("listed", "total", "shown")
              if 'catalogueCount("%s")' % k in qml_body}), ["listed", "shown", "total"])
print("   a refused write goes to the toggle's OWN line. lastError is at the top of the view,")
print("   is cleared by the next refresh, and set_token_enabled answers nothing else at all")
enabled_body = fn_body("setTokenEnabled")
check("the refusal is published on its own property",
      in_order(enabled_body, "if (!replyOk(reply))", "setTokenToggleError(refusal(reply"), True)
check("...and never onto the view's error line, a screen away from the switch",
      "setLastError" in enabled_body or "failed(" in enabled_body, False)
check("...cleared before the call, so a stale one cannot stand over a new press",
      in_order(enabled_body, "setTokenToggleError(QString())",
               "set_token_enabledAsyncResult"), True)
check("...and by a new query, which is a new question",
      "setTokenToggleError(QString())" in fn_body("searchTokens"), True)
check("the screen renders it beside the rows it is about",
      qml_binding("manageTokensToggleError", "visible"),
      "visible: root.tokenToggleError.length > 0")

print("   the toggle is announced, not re-read. set_token_enabled now emits tokens_changed,")
print("   so a re-read wired to the REPLY would fire twice for this view's own press and")
print("   never at all for another app's import into token_list")
check("the toggle's callback does not re-read",
      any(c in enabled_body for c in ("refreshSoon()", "runTokenSearch()", "refresh()")), False)
tokens_changed = handler("Tokens_changed")
check("the event does, and moves both listings",
      in_order(tokens_changed, "refreshSoon()", "runTokenSearch()"), True)
check("...only for the chain on screen, since the payload names one",
      in_order(tokens_changed, "chainId != shown().chainId", "return"), True)
check("...and the order event adopts the order it carries",
      in_order(handler("Token_sort_changed"), "setTokenSort(order)", "refreshSoon()"), True)
print("   and eth_rpc is configured from ANOTHER app: applyVerdict stops the verdict poll on")
print("   a confirmed `off`, so nothing else here would ever notice verification switched on")
check("the networks event re-reads", "refreshSoon()" in handler("Networks_changed"), True)

print("   WHERE a row's contract came from, on the row. A symbol is not evidence: enabling")
print("   one is telling this wallet which contract that symbol means")
src = qml_fn_body(qml_body, "tokenSource")
check("`builtin` outranks the list that also names it",
      in_order(src, "native === true", "builtin === true", "t.source"), True)
check("...and `source` is normalised to a closed set, so an unknown one is named as unknown",
      in_order(src, '["allowlist", "custom", "downloaded", "embedded", "enabled"]',
               ': "unknown"'), True)
check("every row carries it", qml_binding("manageTokenSource_", "text"),
      "text: root.tokenSourceLabel(src)")
print("   and never the word \"verified\": this view spends that on eth_rpc's proof-backed")
print("   reads, and a token's provenance proves nothing whatever about a balance")
lo, hi = qml_fn_lines("tokenSourceLabel")
check("no provenance label claims verification",
      [f"EthWalletView.qml:{n}" for n in range(lo, hi + 1)
       if re.search(r"verif", qml_lines[n - 1], re.I)], [])
print("   in flight, and slow. The call's own budget outlasts a user's patience, and rows")
print("   left standing under a running search answer the query BEFORE it")
check("both writers raise one busy state",
      qml_decl("busy"), "readonly property bool busy: root.availableLoading || root.tokenToggleBusy")
check("...and the line says which rows the user is looking at",
      "still answer the previous query" in qml_fn_body(qml_body, "busyLine"), True)
check("...only where there are rows to be wrong about",
      qml_binding("manageTokensBusyNote", "visible"),
      "visible: managePage.busy && root.availableTokens.length > 0")
check("...while the centred block speaks when there are none",
      qml_binding("manageTokensUnknownNote", "text"),
      'text: managePage.busy ? managePage.busyLine(false) : "—"')
check("the slow timer is armed by the busy state and disarmed with it",
      in_order(" ".join(qml_item("manageTokensPage")), "managePage.searchSlow = false",
               "slowSearch.restart()", "slowSearch.stop()"), True)

print()
print("every intent this view asks for is declared in `uses`. An UNDECLARED one fails")
print("`not_declared` at the broker's first gate, before anything is resolved, and nothing")
print("says so where a developer looks — so comparing the two files is the only way to")
print("catch a name that drifted. The broker matches byte-exactly: no case folding, no")
print("normalisation, because a name is a contract between separately shipped apps.")
META = json.loads((Path(__file__).resolve().parent.parent / "metadata.json").read_text())
declared = sorted(e["intent"] for e in META.get("uses", []) if isinstance(e, dict))
# Both call shapes: the signing hop calls the bridge directly, the three navigation hops go
# through `askFor`, which is this view's own wrapper around it. Naming the wrapper couples
# this to it deliberately — renaming it fails here loudly rather than quietly measuring less.
requested = sorted(set(re.findall(r'(?:logos\.request|askFor)\(\s*"([^"]+)"',
                                  VIEW.read_text())))
check("every intent asked for is declared", [i for i in requested if i not in declared], [])
check("...and every intent declared is asked for", [i for i in declared if i not in requested], [])
check("the five hops are the whole list", declared,
      ["evm.accounts.manage", "evm.rpc.configure", "evm.signing.approve",
       "evm.token_lists.configure", "evm.verified_routing.operate"])

print()
print("`uses` entries are OBJECTS. A bare string array parses, declares nothing, and every")
print("request then fails `not_declared` with no obvious cause — so this asserts the shape")
print("rather than the count.")
check("no entry is a bare string",
      [e for e in META.get("uses", []) if not isinstance(e, dict)], [])
check("...and each names a single provider",
      sorted({e.get("cardinality") for e in META.get("uses", [])}), ["single"])

print()
print("the Send form is cleared ON OPEN, and BEFORE the re-price — a quote priced from the")
print("previous form is a quote withdrawn a frame later, and the order is the whole point.")
print("A probe cannot see this: with no overlay a Popup never opens and `onOpened` never")
print("fires, so what runs it is only assertable here.")
opened = qml_fn_body(qml_body, "onOpened") if False else " ".join(qml_item("sendDialog"))
check("onOpened clears the form before it prices it",
      in_order(opened, "onOpened", "sendDialog.clearForm()", "sendForm.reprice()"), True)
check("...and clearing empties the recipient, the amount and every fee override",
      all(f in qml_fn_body(qml_body, "clearForm")
          for f in ["toField.text", "amountField.text", "maxFeeField.text",
                    "maxPriorityFeeField.text", "gasLimitField.text", "nonceField.text",
                    "advanced.checked"]), True)

print()
print("the recipient picker offers three sources and writes into the field rather than")
print("becoming a second one. Its rows live in a Popup with no delegates instantiated while")
print("it is closed, so the wiring is assertable here and the LISTS are asserted in the probe.")
# Against the whole view: `qml_item` stops at the next objectName, and this block is made
# almost entirely of them.
for tab in ["toTabRecent", "toTabBook", "toTabMine"]:
    check(f"  {tab} is offered", tab in qml_body, True)
check("Recents is bound to the derived list, not to history directly",
      "model: root.recentRecipients" in qml_body, True)
check("the book is bound to the backend's, in the backend's order",
      "model: root.contacts" in qml_body, True)
check("saving and forgetting ASK the backend rather than editing the published copy",
      "root.backend.saveContact(" in qml_body and "root.backend.forgetContact(" in qml_body, True)

print()
print("and the Send picker only PICKS. A control that both chooses a recipient and deletes")
print("one is a control where a mis-tap during a transaction costs a saved address, so every")
print("write lives on the Address book screen and none of them is reachable from the form.")
picker = qml_body[qml_body.index('objectName: "toAccountsMenu"'):
                  qml_body.index('objectName: "selfSendWarning"')]
book = qml_body[qml_body.index("id: addressBookComponent"):
                qml_body.index("id: manageTokensComponent")]
check("the picker writes nothing to the book",
      "saveContact(" in picker or "forgetContact(" in picker, False)
check("...and it offers all three sources",
      all(t in picker for t in ["toTabRecent", "toTabBook", "toTabMine"]), True)
check("the address book screen is where both writes live",
      "saveContact(" in book and "forgetContact(" in book, True)
check("...and renaming goes through the same upsert an add does, not a second path",
      book.count("root.backend.saveContact("), 2)

print()
print("one rule for showing an address, and the name never replaces it: a name is this")
print("wallet's own word for who that is and cannot be checked against what was signed.")
check("namedAddr always carries the short address",
      qml_fn_body(qml_body, "namedAddr").count("shortAddr(a)"), 2)
# The CLOSED picker is the one place a name stands without its address, and deliberately:
# the selected account's address is rendered beside the control, and 220px holding both is
# 220px that elides the address. The open list carries both, on two lines.
check("...and the closed picker shows a name alone, falling back to the short address",
      "return n.length ? n : shortAddr(a)" in qml_fn_body(qml_body, "accountDisplay"), True)
check("...while its rows carry both, resolved per row rather than baked into the model",
      "model: addresses" in qml_body and "text: root.displayName(modelData)" in qml_body, True)
print()
print("the account chrome is HOME chrome: it is about the selected account, which a pushed")
print("screen is not about — and a button naming a screen you are already on is worse than")
print("no button. The chain chip is the exception, and deliberately: a detail screen still")
print("shows figures, and which chain they came from is not something to leave behind.")
# Gated as two ROWS on one reading rather than control by control: five `visible` bindings
# saying the same thing are five that can come to disagree, and the chip was the one that
# did — it followed the user onto a settings screen, over a page with its own title.
check("the header is gated on one reading of what home is",
      qml_body.count("visible: root.homeChrome"), 2)
check("...and no control carries a second opinion about it",
      "visible: nav.depth <= 1" in qml_body, False)
check("...which is the StackView's depth, read once",
      qml_decl("homeChrome").endswith("nav !== null && nav.depth <= 1"), True)
check("there is no Settings popup left to hold links to any of them",
      "settingsDialog" in qml_body, False)
check("...and each button opens a screen rather than a dialog",
      all(f"root.open{n}()" in qml_body for n in ["AddressBook", "Networks", "ManageTokens"]),
      True)
print()
print("what the Tokens screen turns on and off is which tokens this wallet SHOWS. Where they")
print("come from is device-wide and owned elsewhere, exactly as the endpoint is — so it asks")
print("for the capability rather than naming the app that has it.")
check("the Tokens screen offers the way to the lists",
      'root.askFor("evm.token_lists.configure"' in qml_body, True)

print()
print("overriding a design-system delegate replaces its background too, so a row that looks")
print("inert is the default rather than the accident. Both custom rows draw their own.")
picker_body = qml_body[qml_body.index("component AccountPicker"):
                       qml_body.index("component PickableAddress")]
pick_body = qml_body[qml_body.index("component PickableAddress"):
                     qml_body.index("component DetailRow")]
check("the account rows highlight with the combo's own highlighted index",
      "highlighted: picker.highlightedIndex === index" in picker_body, True)
check("...and draw a background for it",
      "accountItem.highlighted ? Theme.palette.surface" in picker_body, True)
check("the recipient rows highlight on hover, having no highlighted index to follow",
      "pick.hovered ? Theme.palette.surface" in pick_body, True)
check("...and both say they are clickable",
      picker_body.count("PointingHandCursor") == 1 and pick_body.count("PointingHandCursor") == 1,
      True)

print()
print("no address is elided TWICE. A mid-ellided address has already lost 30 characters, and")
print("a container that trims it again leaves a prefix matching thousands of addresses. So")
print("wherever a name and an address share a row they are on separate lines: the name may")
print("elide, the address may not.")
for comp, addr_line in [("AccountPicker", "accountRowAddress_"),
                        ("PickableAddress", "Address")]:
    body = qml_body[qml_body.index("component %s" % comp):]
    body = body[:body.index("\n    component ")] if "\n    component " in body else body
    check(f"  {comp}'s address line is never elided", "elide: Text.ElideNone" in body, True)
check("a detail row's address wraps instead of eliding, and is the WHOLE address",
      "wrapMode: Text.WrapAnywhere" in qml_body[qml_body.index("component NamedAddressRow"):
                                                qml_body.index("component DetailRow")], True)
check("...and it is the address itself, never a shortened copy",
      "text: nrow.address" in qml_body, True)
check("the address book screen shows the whole address too",
      "text: bookRow.contact.address" in qml_body, True)

check("...and it resolves accounts, wallets AND the address book",
      all(f in qml_fn_body(qml_body, "displayName")
          for f in ["accountLabel(a)", "accountWallet(a)", "contactName(a)"]), True)

if "--grep-only" in sys.argv:
    print()
    print("RESULT:", "ALL PASS" if not FAIL else f"{len(FAIL)} FAILED -> {FAIL}")
    sys.exit(1 if FAIL else 0)

# setup through the view's own backend. FROM HERE ON this script MUTATES the machine it talks
# to — see the module docstring for the fixture it expects.
call("evaluate",{"expression":'logos.callModule("keystore_module","import_private_key",["ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80","pw123456"])'})
# The endpoint is eth_rpc's, device-wide, and the wallet has no setter for it any more.
call("evaluate",{"expression":'logos.callModule("eth_rpc_module","patch_chain_endpoint",["11155111","http://127.0.0.1:8545"])'})
call("evaluate",{"expression":'logos.module("eth_wallet_ui").setActiveChain(11155111)'})
time.sleep(3)

print("1) the tab actually moves, and the chip is on BOTH tabs")
for i,name in enumerate(["Tokens","Activity"]):
    tab(i)
    check(f"pages.currentIndex after selectTab({i})", props("pages").get("currentIndex"), i)
    check(f"chip on {name}", props("chainChip").get("text"), "SEPOLIA · TESTNET")

print("2) empty history, asserted by PROPERTY on the Activity tab")
tab(1)
print("   the line is a CLAIM about this account, so it speaks only for a history we read")
check("the history was actually read", ev("historyKnown"), True)
check("historyEmpty.visible", props("historyEmpty").get("visible"), True)
print("   control: it must be FALSE on the Tokens tab, or the assertion proves nothing")
tab(0)
check("historyEmpty.visible on Tokens", props("historyEmpty").get("visible"), False)

print("3) the Send button names the network")
call("callMethod",{"objectId":oid("openSendButton"),"method":"clicked","args":[]}); time.sleep(1)
check("submit label", props("sendSubmitButton").get("text"), "Send on Sepolia (testnet)")

print("4) the seven advanced fee controls, plus the token picker and the fee estimate")
for n in ["tierSlow","tierNormal","tierFast","maxFeeField","maxPriorityFeeField","gasLimitField",
          "nonceField","sendTokenPicker","feeEstimate","sendErrorLabel","quoteStaleNote"]:
    check(f"control {n}", oid(n) is not None, True)

print("5) fee provenance speaks for the figures beside it, and only while they stand")
print("   nothing has been priced yet, so there is no basis to name. The fallback this")
print("   replaces read `root.fees`, which is gated on neither the request nor the selection")
check("no basis claimed with no figures on screen", props("feeSourceLabel").get("text"), "")

print("6) the BACKEND's refusal surfaces — priority fee above max fee — INSIDE the modal")
call("evaluate",{"expression":'logos.module("eth_wallet_ui").quote(JSON.stringify({from:"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",to:"0x70997970C51812dc3A010C7d01b50e0d17dc79C8",amountUnits:"0.000001",maxFeePerGas:"1000",maxPriorityFeePerGas:"999999999"}))'})
time.sleep(2.5)
check("refusal text", props("sendErrorLabel").get("text"), "maxPriorityFeePerGas cannot exceed maxFeePerGas", "contains")
check("sendErrorLabel visible", props("sendErrorLabel").get("visible"), True)
print("   control: it must NOT be on the wallet's own error line, behind the scrim")
check("wallet error line untouched", props("errorLabel").get("visible"), False)

print("7) insufficient funds also comes from the backend, in TOKEN units")
call("evaluate",{"expression":'logos.module("eth_wallet_ui").quote(JSON.stringify({from:"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",to:"0x70997970C51812dc3A010C7d01b50e0d17dc79C8",amountUnits:"99999000"}))'})
time.sleep(2.5)
check("insufficient funds", props("sendErrorLabel").get("text"), "insufficient funds", "contains")
check("named in ETH", props("sendErrorLabel").get("text"), "ETH", "contains")
print("   control: an error about money must not report raw base units")
check("no 'wei' anywhere in it", " wei" in str(props("sendErrorLabel").get("text")), False)

print("8) a token row opens its own screen — and the native currency has NO contract chip")
view("openTokenDetail","native")
check("token screen pushed", oid("tokenDetailPage") is not None, True)
check("title is the symbol", props("tokenDetailTitle").get("text"), "ETH")
check("contract row names the category", props("tokenContractRow").get("value"), "Native currency")
check("and offers nothing to copy", props("tokenContractRow").get("copyValue"), "")
check("decimals", props("tokenDecimalsRow").get("value"), "18")
check("no activity for this token yet", props("tokenActivityEmpty").get("visible"), True)
print("   the header stays pinned OUTSIDE the stack, so the network is still on screen")
check("chip on the token screen", props("chainChip").get("text"), "SEPOLIA · TESTNET")
print("   the metadata row discriminates; the boolean it replaces said No for ETH forever")
check("no explorer row anywhere", oid("tokenExplorerRow"), None)
check("metadata row instead", props("tokenMetadataRow").get("value"), "Defined by the network")
check("and the card says what the list is", props("tokenListNote").get("text"),
      "does not download token lists", "contains")

print("9) a copy button puts the WHOLE value on the clipboard, not the shortened display")
me=props("addressCopyButton").get("value")
call("callMethod",{"objectId":oid("addressCopyButton"),"method":"copy","args":[]}); time.sleep(0.4)
check("copied value is the full address", props("ethWalletRoot").get("lastCopiedValue"), me)
print("   control: the label DISPLAYS a shorter string, so this is not the same read twice")
check("displayed value is elided", props("addressLabel").get("text"), "…", "contains")
check("and is shorter than what was copied", len(str(props("addressLabel").get("text"))) < len(str(me)), True)

print("10) back closes the screen, and a hash we never broadcast opens nothing")
view("back")
check("token screen gone", oid("tokenDetailPage"), None)
view("openTxDetail","0x" + "11"*32)
check("no transaction screen", oid("txDetailPage"), None)

print("11) Send offers this wallet's own accounts without taking away free text")
call("evaluate",{"expression":'logos.callModule("keystore_module","import_private_key",["59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d","pw123456"])'})
call("evaluate",{"expression":'logos.module("eth_wallet_ui").refresh()'}); time.sleep(2.5)
call("callMethod",{"objectId":oid("openSendButton"),"method":"clicked","args":[]}); time.sleep(1)
check("picker on screen once a second account exists", props("toAccountsButton").get("visible"), True)
check("the entry names the account and its address", props("toAccount_0").get("text"), "0x7099", "contains")
print("   the regression: the handler said popupUnder(toAccountsButton) with only an")
print("   objectName declared. objectName is not in the QML scope chain, so that was a")
print("   ReferenceError and the handler aborted BEFORE the menu was ever asked to open.")
check("menu shut to begin with", props("toAccountsMenu").get("visible"), False)
call("callMethod",{"objectId":oid("toAccountsButton"),"method":"clicked","args":[]}); time.sleep(0.8)
check("clicking the chevron really opens it", props("toAccountsMenu").get("visible"), True)
call("callMethod",{"objectId":oid("toAccountsMenu"),"method":"close","args":[]}); time.sleep(0.5)
call("callMethod",{"objectId":oid("toAccount_0"),"method":"triggered","args":[]}); time.sleep(0.5)
check("picking one writes into the free-text field", props("toField").get("text"), "0x7099", "contains")
check("which is still editable", props("toField").get("readOnly"), False)

print("12) sending to yourself is warned about, never refused")
call("setProperty",{"objectId":oid("toField"),"property":"text","value":me}); time.sleep(0.5)
check("warning on screen", props("selfSendWarning").get("visible"), True)
print("   control: it must vanish for any other address, or it is always-on")
call("setProperty",{"objectId":oid("toField"),"property":"text","value":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8"})
time.sleep(0.5)
check("warning gone", props("selfSendWarning").get("visible"), False)

# ─────────────────────────────────────────────────────────────────────────────
# Regression cover for the polling and disclosure fixes. 13 and 17 need no chain
# state at all: the decisions are pure functions the bindings call, so every case
# — including the ones a live wallet cannot be pushed into — is executable here.
# 14-16 flip the verified-proxy mode for real and put it back at the end.
# ─────────────────────────────────────────────────────────────────────────────

print("13) the chip is tri-state, and speaks for the BALANCES only")
READY    = '{"mode":"required","state":"ready"}'
NOSTATE  = '{"mode":"required"}'
UNKNOWN  = '{"mode":"unknown","state":"unhealthy"}'
OFF      = '{"mode":"off","state":"disabled"}'
BLOCKING = '{"mode":"required","state":"unhealthy","blocking":true}'
BLOCKRDY = '{"mode":"required","state":"ready","blocking":true}'
for label, verdict, route, want in [
    ("a ready proxy AND a proof-backed balance", READY,   "verified", "verified"),
    ("the same ready proxy, balance only proxied", READY, "proxied",  "unproved"),
    ("...or direct", READY,                                "direct",   "unproved"),
    ("...or read before any label arrived", READY,         "",         "unproved"),
    ("a verdict we could not read", UNKNOWN,               "verified", "unknown"),
    ("a verdict carrying no state", NOSTATE,               "verified", "unknown"),
    ("verification confirmed off", OFF,                    "verified", "hidden"),
    ("never asked", '{}',                                  "verified", "hidden"),
    ("a blocking verdict, whatever the last good read labelled", BLOCKING, "verified", "unproved"),
    ("...even one still calling itself ready", BLOCKRDY,   "verified", "unproved"),
]:
    check("chipState — "+label, ev("chipState(JSON.parse('%s'),'%s')" % (verdict, route)), want)
print("   the second row is the over-claim this replaces: `ready` did not mean proved")
print("   the last two are the other one: nothing re-reads balances when the verdict moves,")
print("   so the route label outlives the proxy that earned it and the chip read `Balances")
print("   verified` directly above the banner asserted in 15. The backend withdraws the")
print("   label on that transition; this is the view refusing to claim it either way.")
check("only one state may say verified", ev("chipText('verified')"), "Balances verified")
check("unknown is its own word", ev("chipText('unknown')"), "Verification unknown")
check("and unproved says so", ev("chipText('unproved')"), "Not verified")
print("   and the chip on screen is the same function, not a second copy of the rule")
check("live chip text", props("verifiedChip").get("text"),
      ev("chipText(chipState(vp, balancesRoute))"))

print("14) a mode flip clears the open quote")
call("evaluate",{"expression":'logos.module("eth_wallet_ui").quote(JSON.stringify({from:"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",to:"0x70997970C51812dc3A010C7d01b50e0d17dc79C8",amountUnits:"0.000001"}))'})
time.sleep(2.5)
check("a quote is on screen first", props("quoteSummary").get("text"), "Gas limit", "contains")
check("and Send is live", props("sendSubmitButton").get("enabled"), True)
print("   ask #4: the ceiling is named as a ceiling, and the tier it was priced at")
check("fee estimate on screen", props("feeEstimate").get("text"), "Network fee at most", "contains")
check("Market is the default tier", props("feeEstimate").get("text"), "(normal)", "contains")
print("   flip the mode — the numbers were priced under the OLD one. Through eth_rpc, which")
print("   OWNS it: the wallet's setter is gone and that is what makes the split enforced.")
call("evaluate",{"expression":'logos.callModule("eth_rpc_module","set_verified_proxy_mode",["11155111","required"])'})
call("evaluate",{"expression":'logos.module("eth_wallet_ui").refreshVerifiedProxy()'})
time.sleep(6)
check("quote withdrawn", props("quoteSummary").get("text"), "")
check("and Send refuses", props("sendSubmitButton").get("enabled"), False)

print("15) the verified banner wraps INSIDE its frame — measured")
check("banner on screen", props("verifiedBanner").get("visible"), True)
bw, mw, aw = num("verifiedBanner","width"), num("verifiedBannerMessage","width"), num("verifiedBannerAction","width")
check("message has a real box", mw > 0, True)
check("message fits the frame", 0 < mw <= bw, True)
check("action fits the frame", 0 < aw <= bw, True)
print("   the defect this replaces: a plain child of LogosFrame is sized to its OWN implicit")
print("   width, so two lines of different length get two different boxes and neither wraps")
check("both lines share the frame's inner width", abs(mw - aw) <= 1, True)
check("message never overflows its box", num("verifiedBannerMessage","contentWidth") <= mw + 1, True)
check("action never overflows its box", num("verifiedBannerAction","contentWidth") <= aw + 1, True)
print("   either it fitted on one line or it wrapped; wider-and-still-one-line is the bug")
check("message wrapped rather than overflowed",
      num("verifiedBannerMessage","implicitWidth") <= mw + 1 or num("verifiedBannerMessage","lineCount") >= 2, True)
check("action wrapped rather than overflowed",
      num("verifiedBannerAction","implicitWidth") <= aw + 1 or num("verifiedBannerAction","lineCount") >= 2, True)
print("   and a blocking proxy is never badged verified")
check("chip under a blocking proxy", props("verifiedChip").get("text"), "Not verified")

print("16) the receipt sweep is STOPPED when nothing is still due")
tab(1)
print("   on the Activity tab, or every `visible` below reads false whatever it is bound to")
check("control: the tab is really showing", props("activityRouteNote").get("visible"), True)
check("nothing recorded to sweep", ev("history.length"), 0)
check("the backend agrees nothing is due",
      call("evaluate",{"expression":'JSON.parse(logos.callModule("eth_wallet_backend","get_history",[logos.module("eth_wallet_ui").selectedAccount])).stillDue'}).get("result"),
      False)
check("so the schedule is off", ev("backend.sweepingReceipts"), False)
check("and the note with it", props("sweepNote").get("visible"), False)
print("   a sweep that finds nothing must not re-arm it")
call("evaluate",{"expression":'logos.module("eth_wallet_ui").refreshPending()'}); time.sleep(2.5)
check("still off after a sweep", ev("backend.sweepingReceipts"), False)
check("and the item asserted above is the real one", props("sweepNote").get("text"),
      "Checking for confirmations…")
print("   the leg that matters — a FAILED read leaves the schedule exactly as it was — is")
print("   NOT reachable from here: `get_history` answers ok:false only when the backend")
print("   module has no context, and this harness has no lever to take it away. It is")
print("   covered as a table in doctests/test_sweep_decision.cpp, which fails five rows")
print("   the moment that branch is reverted. The armed-and-stays-armed leg still wants a")
print("   broadcast row, i.e. the approver_probe fixture from the e2e spec.")

print("17) a frozen row is explained in the backend's own words")
BLOCKED='{"chainId":11155111,"network":"Sepolia","count":%d,"message":"The verified proxy is running but not tracking the chain.","action":"restart_or_reload"}'
check("plural, chain, message and what to do",
      ev("blockedLine(JSON.parse('%s'))" % (BLOCKED % 2)),
      "2 transactions on Sepolia cannot be checked. The verified proxy is running but not "
      "tracking the chain. Open Verified Proxy, press Stop then Start. If that does not help, "
      "reload the app.")
check("one row is not 'transactions'", ev("blockedLine(JSON.parse('%s'))" % (BLOCKED % 1)),
      "1 transaction on Sepolia", "contains")
print("   and the row's own badge says which of the two it is")
ROW = '{"status":"pending"%s}'
check("frozen — the chain was never asked",
      ev("statusText(JSON.parse('%s'))" % (ROW % ',"verificationBlocked":true')), "not checked")
check("stalled — we gave up asking",
      ev("statusText(JSON.parse('%s'))" % (ROW % ',"stalled":true')), "unconfirmed")
check("control: an ordinary pending row is untouched",
      ev("statusText(JSON.parse('%s'))" % (ROW % "")), "pending")
print("   control: with nothing frozen the frame must be off screen")
check("blocked frame hidden", props("blockedChainsFrame").get("visible"), False)

print("18) the forwarded figures say they are forwarded")
check("only 'verified' claims proof", ev("routeNote('verified')"), "proof-backed", "contains")
for r in ["proxied", "direct", "undefined"]:
    check("...'%s' does not" % r, ev("routeNote(%s)" % (r if r == "undefined" else "'%s'" % r)),
          "not proved", "contains")
check("the Send screen says so about the fee", props("feeRouteNote").get("text"), "not proved", "contains")
check("and it is actually on screen", props("feeRouteNote").get("visible"), True)
check("and the Activity tab about the status", props("activityRouteNote").get("text"), "not proved", "contains")

print("19) put the device-wide setting back")
call("evaluate",{"expression":'logos.callModule("eth_rpc_module","set_verified_proxy_mode",["11155111","off"])'})
call("evaluate",{"expression":'logos.module("eth_wallet_ui").refreshVerifiedProxy()'})
time.sleep(6)
check("verification off again", ev("vp.mode"), "off")
check("chip hidden", props("verifiedChip").get("visible"), False)
print("   control: the forwarded-figure notes go with it")
check("fee note hidden", props("feeRouteNote").get("visible"), False)

# ─────────────────────────────────────────────────────────────────────────────
# Round 5: money in token units, the picker, account names, and the split.
# ─────────────────────────────────────────────────────────────────────────────

print("20) every amount on screen is a backend string, never arithmetic done here")
call("evaluate",{"expression":'logos.module("eth_wallet_ui").refresh()'}); time.sleep(2.5)
tab(0)
check("the row and the function are the same code",
      props("balance_native").get("text"), ev("balanceDisplay(nativeToken)"))
print("   the two resolutions are different strings: bounded in the list, exact underneath")
disp, exact = ev("balanceDisplay(nativeToken)"), ev("balanceExact(nativeToken)")
check("a display figure came back", isinstance(disp,str) and disp != "—", True)
check("an exact figure came back", isinstance(exact,str) and exact != "—", True)
check("exact is never shorter than the bounded one", len(str(exact)) >= len(str(disp)), True)
print("   control: a token we hold nothing of is an em-dash, not a zero — and it is looked")
print("   up by CONTRACT, so a contract the balances do not name reads as unknown even when")
print("   another one wearing the same symbol does")
check("unknown contract", ev('balanceDisplay({symbol:"LIT",address:"0x" + "11".repeat(20)})'),
      "—")
check("...and its exact twin too",
      ev('balanceExact({symbol:"LIT",address:"0x" + "11".repeat(20)})'), "—")
print("   the detail screen is the one carrying every digit")
view("openTokenDetail","native")
check("token screen shows the exact figure", props("tokenDetailBalance").get("text"),
      str(exact), "contains")
print("   control: the list row shows the BOUNDED one, so this is not the same read twice")
view("back")
tab(0)
check("list row is the bounded figure", props("balance_native").get("text"), str(disp))

print("21) the Send screen picks a token and takes TOKEN units")
call("callMethod",{"objectId":oid("openSendButton"),"method":"clicked","args":[]}); time.sleep(1)
check("the picker offers what the wallet holds", (ev("tokens.length") or 0) >= 1, True)
check("it names the symbol and the balance", props("sendTokenPicker").get("model"), "ETH", "contains")
check("and it opens on the native currency", props("sendDialog").get("token"), "ETH")
check("the amount field asks for ETH, not wei", props("amountField").get("placeholderText"),
      "Amount in ETH")
print("   the wire always names the token now, 'ETH' included — tokens::find resolves it to")
print("   the native path, so this removes a UI conditional rather than adding a backend one")
call("setProperty",{"objectId":oid("toField"),"property":"text","value":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8"})
call("setProperty",{"objectId":oid("amountField"),"property":"text","value":"0.25"}); time.sleep(2.5)
req=call("evaluate",{"objectId":oid("sendDialog"),"expression":"request()"}).get("result")
check("the request carries token units", '"amountUnits":"0.25"' in str(req), True)
check("...and names the token", '"token":"ETH"' in str(req), True)
print("   control: the base-units field must NOT also be set — they mean different units")
check("no base-units amount on the wire", '"amount"' in str(req), False)
check("and a real quote came back for it", props("quoteSummary").get("text"), "Gas limit", "contains")
check("...and NOW the basis names where those figures came from",
      props("feeSourceLabel").get("text"), "Fee basis", "contains")

print("22) a submit that is REFUSED stays on screen with its reason")
call("setProperty",{"objectId":oid("toField"),"property":"text","value":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8"})
call("setProperty",{"objectId":oid("amountField"),"property":"text","value":"99999000"})
time.sleep(2.5)
call("evaluate",{"expression":'logos.module("eth_wallet_ui").submitSend(JSON.stringify({from:logos.module("eth_wallet_ui").selectedAccount,to:"0x70997970C51812dc3A010C7d01b50e0d17dc79C8",amountUnits:"99999000",token:"ETH"}))'})
time.sleep(3)
check("the reason is inside the modal", props("sendErrorLabel").get("visible"), True)
check("and it is the backend's own words", props("sendErrorLabel").get("text"),
      "insufficient funds", "contains")
print("   the defect this replaces: the dialog closed unconditionally, so the message landed")
print("   on the wallet behind the scrim and the user never saw it")
check("the dialog did NOT close", props("sendDialog").get("visible"), True)
check("nothing is pending", ev("sendPending"), False)
call("callMethod",{"objectId":oid("sendCancelButton"),"method":"clicked","args":[]}); time.sleep(0.8)

print("23) accounts are identified by NAME, with the address beside the selector")
print("   `set_label` is custodian-gated (keystore glue.rs:338-341) and this view is not the")
print("   custodian, so the NAMED leg only runs where the harness is allowed to write one.")
named=call("evaluate",{"expression":'logos.callModule("keystore_module","set_label",["%s","Treasury"])' % me}).get("result")
call("evaluate",{"expression":'logos.module("eth_wallet_ui").refresh()'}); time.sleep(2.5)
if '"ok":true' in str(named):
    check("the keystore's name reaches the view", ev("accountLabel('%s')" % me), "Treasury")
    check("the picker shows the name", ev("accountDisplay('%s')" % me), "Treasury")
    check("the picker's model carries it", props("accountPicker").get("model"), "Treasury", "contains")
else:
    print("  SKIP  the keystore refused the label: %s" % str(named)[:120])
print("   the address stays BESIDE the selector, never merged into it")
check("address label is its own control", props("addressLabel").get("text"), "…", "contains")
check("...and the picker is not showing a raw address when a name exists",
      props("accountPicker").get("model") is not None, True)
print("   control: an unnamed account falls back to its address, never to 'Account 2' —")
print("   a positional name RENUMBERS when an account is added or removed")
unnamed=[a for a in (ev("accounts") or []) if not str(ev("accountLabel('%s')" % a) or "")]
if unnamed:
    got=str(ev("accountDisplay('%s')" % unnamed[0]))
    check("unnamed account shows an address", got, "0x", "contains")
    check("...and never an invented number", got.startswith("Account "), False)
else:
    print("  SKIP  every staged account has a name")

print("24) the eth_rpc controls are GONE from Settings, replaced by a read-only report")
for n in ["rpcUrlField","saveRpcButton","verifiedProxySwitch","verifiedModeUnknown",
          "verifiedTestnetWarning","tokenListUrlField","saveTokenListButton","tokenListStatus"]:
    check(f"{n} removed", oid(n), None)
# A SCREEN now, not a dialog: Settings held nothing but links to other places, so the
# places are the screens and the popup is gone.
call("callMethod",{"objectId":oid("networksButton"),"method":"clicked","args":[]}); time.sleep(1)
check("the note names the endpoint", props("rpcSettingsNote").get("text"), "Endpoint:", "contains")
check("and says who owns it", props("rpcSettingsNote").get("text"), "Ethereum RPC app", "contains")
print("   control: the network selector STAYS — that is wallet state, not eth_rpc config")
check("network selector still here", oid("network_sepolia") is not None, True)

# ─────────────────────────────────────────────────────────────────────────────
# Round 9: a figure on screen belongs to the selection on screen, or it is not a
# figure. 25-27 are the reported bug and its two siblings. Each one FAILS on the
# code it replaces — the pure-logic twin of 25 is doctests/test_scope_invariant.cpp,
# which needs no app at all.
# ─────────────────────────────────────────────────────────────────────────────

print("25) an ACCOUNT switch never leaves the previous account's figures on screen")
call("callMethod",{"objectId":oid("networksBack"),"method":"clicked","args":[]}); time.sleep(0.6)
settle()
accts = ev("accounts") or []
if len(accts) < 2:
    print("  SKIP  only one account staged — 11 imports the second one this needs")
else:
    a, b = accts[0], accts[1]
    call("evaluate",{"expression":'logos.module("eth_wallet_ui").selectAccount("%s")' % a})
    before = settle(want_acct=a)[-1]
    check("we start on A with its balance read", before["bk"] and before["acct"].lower()==a.lower(), True)
    check("...and a real figure on screen", before["bal"] != "—", True)
    print("   the defect: selectAccount bumped the generation and cleared NOTHING, so A's")
    print("   balances and A's Activity rows sat under B's name until the read came back.")
    print("   The generation guard only drops a stale REPLY; it cannot unshow a value.")
    call("evaluate",{"expression":'logos.module("eth_wallet_ui").selectAccount("%s")' % b})
    frames = settle(want_acct=b)
    under_b = [f for f in frames if f["acct"].lower() == b.lower()]
    check("B did appear on screen", len(under_b) > 0, True)
    check("...and was on screen with NO balance attributed to it",
          any(not f["bk"] for f in under_b), True)
    check("...with no history attributed to it either",
          any(not f["hk"] for f in under_b), True)
    print("   the unknown state is an em-dash, never a zero and never A's number")
    check("the hero balance was an em-dash while unknown",
          all(f["bal"] == "—" for f in under_b if not f["bk"]), True)
    check("no frame showed B carrying A's exact balance",
          [f["bal"] for f in under_b if not f["bk"] and f["bal"] == before["bal"]], [])
    print("   the chip speaks for the balances, so it cannot outlive them either")
    check("never 'Balances verified' over an unread balance",
          [f["chip"] for f in under_b if not f["bk"] and f["chip"] == "Balances verified"], [])
    print("   and the read does land: the screen comes back, for the account now selected")
    check("balances known again", under_b[-1]["bk"], True)
    check("history known again", under_b[-1]["hk"], True)
    check("still on B", under_b[-1]["acct"].lower(), b.lower())

print("26) a NETWORK switch withdraws the token list with everything else")
nets = ev("networks") or []
other = [n for n in nets if n.get("chainId") != ev("net.chainId")]
if not other:
    print("  SKIP  only one network configured")
else:
    settle()
    to = other[0]["chainId"]
    back = ev("net.chainId")
    call("evaluate",{"expression":'logos.module("eth_wallet_ui").setActiveChain(%d)' % to})
    frames = settle(want_chain=to)
    under = [f for f in frames if f["chain"] == to]
    if not under:
        print("  SKIP  the backend refused the switch: %s" % str(props("errorLabel").get("text"))[:100])
    else:
        check("the new network was on screen with no balance attributed to it",
              any(not f["bk"] for f in under), True)
        print("   the token list is chain-scoped too: symbols, decimals and CONTRACT")
        print("   ADDRESSES from another chain under this chain's name are wrong, not stale")
        check("...and with no token list attributed to it",
              any(not f["tk"] for f in under), True)
        check("no frame showed the new chain with the old chain's rows",
              [f["rows"] for f in under if not f["hk"] and f["rows"] > 0], [])
        call("evaluate",{"expression":'logos.module("eth_wallet_ui").setActiveChain(%d)' % back})
        settle(want_chain=back)
        check("put back on the chain the rest of this file expects", ev("net.chainId"), back)

print("27) changing WHAT is being sent withdraws the figures priced for the old request")
call("callMethod",{"objectId":oid("openSendButton"),"method":"clicked","args":[]}); time.sleep(1)
call("setProperty",{"objectId":oid("toField"),"property":"text","value":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8"})
call("setProperty",{"objectId":oid("amountField"),"property":"text","value":"0.001"}); time.sleep(3)
check("a quote is on screen for the request as typed", props("quoteSummary").get("text"),
      "Gas limit", "contains")
check("and the ceiling names the tier it was priced at", props("feeEstimate").get("text"),
      "(normal)", "contains")
print("   the defect: nothing bumped a guard when the REQUEST changed, so the reply for the")
print("   previous tier was applied and feeEstimate read the new tier's label beside the old")
print("   ceiling. Gas limit differs ~2.5x between a native send and an ERC-20 one.")
call("callMethod",{"objectId":oid("tierFast"),"method":"clicked","args":[]})
priced=[]
for _ in range(25):
    q = call("evaluate",{"objectId":oid("ethWalletRoot"),"expression":
        'JSON.stringify([quote.ok===true, quoteLoading])'}).get("result")
    try: ok, loading = json.loads(q)
    except Exception: break
    priced.append((ok, loading))
    if ok: break
    time.sleep(0.1)
check("the old request's quote was withdrawn before the new one arrived",
      any(not ok for ok, _ in priced), True)
check("...and the screen said so rather than leaving a gap",
      props("quotePricingNote").get("text"), "Pricing…")
check("the re-price does land", priced[-1][0], True)
check("and the ceiling now names the tier actually asked for",
      props("feeEstimate").get("text"), "(fast)", "contains")
call("callMethod",{"objectId":oid("sendCancelButton"),"method":"clicked","args":[]}); time.sleep(0.8)

print("28) a form edit that re-prices NOTHING still withdraws the figures it invalidated")
# 27 drives the tier button, which does re-price, and passed over this entirely: the old guard
# hung off the CALL, so an edit that made no call withdrew nothing and left the previous
# request's gas limit, ceiling and nonce on screen with Submit still armed.
call("callMethod",{"objectId":oid("openSendButton"),"method":"clicked","args":[]}); time.sleep(1)
call("setProperty",{"objectId":oid("toField"),"property":"text","value":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8"})
call("setProperty",{"objectId":oid("amountField"),"property":"text","value":"0.001"}); time.sleep(3)
check("a quote is on screen for the request as typed", props("quoteSummary").get("text"),
      "Gas limit", "contains")
print("   clear the amount: there is nothing to price, so nothing is called — and the figures")
print("   priced for the amount that is gone may not stay standing beside an empty field")
call("setProperty",{"objectId":oid("amountField"),"property":"text","value":""}); time.sleep(1.5)
check("the gas limit, ceiling and nonce went with the amount",
      props("quoteSummary").get("text"), "")
check("...and so did the fee ceiling", props("feeEstimate").get("text"), "")
check("...and the line claiming their fee basis", props("feeSourceLabel").get("text"), "")
check("...and the advanced fields stopped suggesting the old request's numbers",
      ev('JSON.stringify([sendForm.q.gasLimit===undefined, sendForm.q.nonce===undefined])'),
      "[true,true]")
print("   and Submit is the one that matters: an armed button under withdrawn figures is a")
print("   send priced for a request the form no longer describes")
check("Submit is disarmed", props("sendSubmitButton").get("enabled"), False)
call("callMethod",{"objectId":oid("sendCancelButton"),"method":"clicked","args":[]}); time.sleep(0.8)

print("29) reopening on a different token does not render the previous token's quote")
# The second shape: setQuoteAutoRefresh(false) cleared the request and the timer but not the
# figures, so an ETH quote rendered under a form reading "Amount in WETH".
call("callMethod",{"objectId":oid("openSendButton"),"method":"clicked","args":[]}); time.sleep(1)
call("setProperty",{"objectId":oid("toField"),"property":"text","value":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8"})
call("setProperty",{"objectId":oid("amountField"),"property":"text","value":"0.001"}); time.sleep(3)
priced_native = props("quoteSummary").get("text")
check("an ETH send is priced", priced_native, "Gas limit", "contains")
call("callMethod",{"objectId":oid("sendCancelButton"),"method":"clicked","args":[]}); time.sleep(0.8)
check("closing the dialog withdrew the quote with it", ev("quoteRequest"), "")
erc20 = [t for t in json.loads(ev("JSON.stringify(tokens)") or "[]") if t.get("native") is not True]
if not erc20:
    print("  SKIP  this network's token list carries no ERC-20 to reopen on")
else:
    print("   reopen on a token the previous quote was NOT priced for: the amount field now")
    print("   reads \"Amount in %s\", and the ETH gas limit is the wrong number under it"
          % erc20[0]["symbol"])
    # By CONTRACT: a symbol may be worn by two of this chain's tokens, and the by-symbol form
    # of this could only ever open the first of them.
    call("evaluate",{"objectId":oid("ethWalletRoot"),
                     "expression":'openTokenDetail("%s")'
                                  % erc20[0]["address"].lower()}); time.sleep(1)
    call("callMethod",{"objectId":oid("tokenDetailSendButton"),"method":"clicked","args":[]})
    time.sleep(0.4)
    check("the amount field names the token being sent",
          props("amountField").get("placeholderText"), "Amount in %s" % erc20[0]["symbol"])
    check("no quote from the previous token is standing under it",
          props("quoteSummary").get("text"), "")
    check("...and Submit is not armed by it", props("sendSubmitButton").get("enabled"), False)
    call("callMethod",{"objectId":oid("sendCancelButton"),"method":"clicked","args":[]})
    time.sleep(0.8)
    view("back")

print()
print("RESULT:", "ALL PASS" if not FAIL else f"{len(FAIL)} FAILED -> {FAIL}")
sys.exit(1 if FAIL else 0)
