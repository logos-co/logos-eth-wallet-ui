// Every guard that decides whether a reply reaches the screen, as a table.
//
// This file exists because of what a source-text assertion cannot see. `if (!answersFor(reply,
// shown()) && false)` leaves the call present, in order, and anchored to the write it guards —
// so a grep over the backend passes while the guard does nothing. The way out is not a cleverer
// grep: it is to put the guard inside a pure transition and RUN it. Neutering any guard below
// fails a row that executed it.
//
// The transitions live in src/eth_wallet_ui_apply.h and are the only things that write a scoped
// value; EthWalletUiBackend snapshots, calls one, and publishes. It holds no rule of its own.
//
// Run it from this directory — see doctests/run_tables.sh, or by hand:
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) \
//       test_apply.cpp -o /tmp/test_apply && /tmp/test_apply

#include <cstdio>

// Qt 6.9's qyieldcpu.h calls __yield() without declaring it, which is an error for a plain
// clang invocation on aarch64. Qt's own CMake build never sees it.
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif

#include "eth_wallet_ui_apply.h"

namespace {

int failures = 0;

const char *ALICE = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const char *BOB = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

void expect(const char *label, const char *claim, bool got)
{
    if (!got)
        ++failures;
    std::printf("  %s  %-50s %s\n", got ? "PASS" : "FAIL", label, claim);
}

void same(const char *label, const QString &got, const QString &want)
{
    const bool ok = got == want;
    if (!ok)
        ++failures;
    std::printf("  %s  %-50s got=%s\n", ok ? "PASS" : "FAIL", label,
                got.isNull() ? "<unknown>" : got.toUtf8().constData());
}

/// Sepolia, Alice, everything read: the screen every reply below is checked against.
ScopedState screen()
{
    ScopedState s;
    s.at = selectionOf(QString::fromUtf8(ALICE),
                       QStringLiteral(R"({"chainId":11155111})"));
    s.fresh = true;
    s.balances = QStringLiteral(R"([{"symbol":"ETH","display":"1.5"}])");
    s.balancesRoute = QStringLiteral("verified");
    s.history = QStringLiteral(R"([{"hash":"0xdead"}])");
    s.blockedChains = QStringLiteral("[]");
    s.tokens = QStringLiteral(R"([{"symbol":"ETH"}])");
    s.feeTiers = QStringLiteral(R"({"source":"eip1559"})");
    s.verifiedProxy = QStringLiteral(
        R"({"ok":true,"chainId":11155111,"mode":"required","state":"ready"})");
    return s;
}

QString q(const char *s) { return QString::fromUtf8(s); }

} // namespace

int main()
{
    std::printf("balances: a reply naming another selection is not late, it is about\n");
    std::printf("something else — and it may not stamp freshness either\n");
    {
        ScopedState s = screen();
        s.fresh = false;
        s.balances.clear();
        const Applied a = applyBalances(s, q(R"({"ok":true,"chainId":1,"address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","balances":[{"symbol":"ETH"}],"route":"verified"})"));
        expect("a reply for another chain", "is not acted on", !a.acted);
        expect("...and the freshness stamp", "stays down, so the view shows a dash", !s.fresh);
        same("...and the figures", s.balances, QString());
    }
    {
        ScopedState s = screen();
        s.fresh = false;
        const Applied a = applyBalances(s, q(R"({"ok":true,"chainId":11155111,"address":"0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266","balances":[{"symbol":"ETH"}],"route":"proxied"})"));
        expect("a reply for THIS selection, case-folded", "is acted on", a.acted);
        expect("...and stamps freshness", "so the view may render a figure", s.fresh);
        same("...the route label", s.balancesRoute, q("proxied"));
        expect("...and says nothing to the user", "a read that worked is not an error",
               a.error.isEmpty());
    }
    {
        ScopedState s = screen();
        const Applied a = applyBalances(s, q(R"({"ok":false,"error":"no endpoint"})"));
        std::printf("   a refusal names nothing by design and IS this call's own answer\n");
        expect("the backend refused", "is acted on", a.acted);
        same("...the figures go", s.balances, QString());
        same("...and the route label with them", s.balancesRoute, QString());
        same("...worded by the backend", a.error, q("balances: no endpoint"));
    }

    std::printf("\nhistory: the rows AND the sweep schedule the same reply carries\n");
    {
        ScopedState s = screen();
        const HistoryApplied h = applyHistory(s, q(R"({"ok":true,"chainId":1,"address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","transactions":[],"stillDue":false})"));
        expect("a reply for another chain", "is not acted on", !h.acted);
        expect("...and says nothing about the sweep", "on an idle wallet nothing restarts it",
               h.sweep == SweepVerdict::Unchanged);
        same("...the rows stand", s.history, q(R"([{"hash":"0xdead"}])"));
    }
    {
        ScopedState s = screen();
        const HistoryApplied h = applyHistory(s, q(R"({"ok":false,"error":"module context not ready"})"));
        expect("a read that FAILED", "leaves the schedule alone",
               h.acted && h.sweep == SweepVerdict::Unchanged);
        std::printf("   UNKNOWN, not \"[]\": an empty list renders as \"No transactions yet\"\n");
        same("...and the rows read as unknown", s.history, QString());
    }
    {
        ScopedState s = screen();
        const HistoryApplied h = applyHistory(s, q(R"({"ok":true,"chainId":11155111,"address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","transactions":[{"status":"pending"}]})"));
        expect("a pending row", "schedules the sweep", h.sweep == SweepVerdict::Run);
        same("...and the blocked list defaults to none", s.blockedChains, q("[]"));
    }

    std::printf("\nfee tiers and the token list: read for another network they are WRONG under\n");
    std::printf("this one's name, not stale\n");
    {
        ScopedState s = screen();
        applyFeeTiers(s, q(R"({"ok":true,"chainId":1,"tiers":{}})"));
        same("fees priced on another chain", s.feeTiers, q("{}"));
    }
    {
        ScopedState s = screen();
        applyFeeTiers(s, q(R"({"ok":true,"chainId":11155111,"source":"gasPrice"})"));
        same("fees for this chain", s.feeTiers, q(R"({"ok":true,"chainId":11155111,"source":"gasPrice"})"));
    }
    {
        ScopedState s = screen();
        const Applied a = applyTokens(s, q(R"({"ok":true,"chainId":1,"tokens":[{"symbol":"USDC"}]})"));
        same("a list for another chain", s.tokens, QString());
        expect("...and it is not an error", "the read worked, it just answered elsewhere",
               a.error.isEmpty());
    }
    {
        ScopedState s = screen();
        const Applied a = applyTokens(s, q(R"({"ok":false,"error":"no endpoint"})"));
        same("a list we could not read", s.tokens, QString());
        same("...worded by the backend", a.error, q("tokens: no endpoint"));
    }

    std::printf("\nno account: what is on screen — nothing — DOES describe this selection\n");
    {
        ScopedState s = screen();
        s.fresh = false;
        applyNoAccount(s);
        expect("an empty wallet", "is stamped fresh, or the view spins forever", s.fresh);
        same("...its history is an ANSWER", s.history, q("[]"));
        same("...and its balances are not", s.balances, QString());
    }

    std::printf("\nthe quote is scoped by account, chain and REQUEST, and the wire echoes no\n");
    std::printf("request: the view stamps the one it priced\n");
    {
        ScopedState s = screen();
        applyQuote(s, q(R"({"ok":true,"chainId":11155111,"from":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","gasLimit":21000})"),
                   q("REQ"), true);
        same("a quote for this selection", s.quoteRequest, q("REQ"));
        expect("...and it is not stale", "it was just priced", !s.quoteStale);
    }
    {
        ScopedState s = screen();
        s.quote = q(R"({"ok":true,"gasLimit":21000})");
        s.quoteRequest = q("OLD");
        applyQuote(s, q(R"({"ok":true,"chainId":1,"from":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","gasLimit":21000})"),
                   q("REQ"), true);
        std::printf("   a quote priced on another chain is not late, and the figures it would\n");
        std::printf("   replace are not this form's either\n");
        same("a quote for another chain withdraws", s.quote, q("{}"));
        same("...and the request stamp with it", s.quoteRequest, QString());
    }
    {
        ScopedState s = screen();
        s.quote = q(R"({"ok":true,"gasLimit":21000})");
        s.quoteRequest = q("OLD");
        applyQuote(s, q(R"({"ok":false,"error":"insufficient funds"})"), q("REQ"), true);
        same("a user edit's refusal reaches the modal", s.sendError, q("insufficient funds"));
        same("...and the figures go with it", s.quote, q("{}"));
    }
    {
        ScopedState s = screen();
        s.quote = q(R"({"ok":true,"gasLimit":21000})");
        s.quoteRequest = q("OLD");
        applyQuote(s, q(R"({"ok":false,"error":"insufficient funds"})"), q("REQ"), false);
        std::printf("   a TIMER tick's failure only marks the figure stale: withdrawing one\n");
        std::printf("   under a dialog nobody touched reads as the wallet breaking\n");
        expect("a tick's refusal", "marks the quote stale", s.quoteStale);
        same("...and leaves the figures standing", s.quote, q(R"({"ok":true,"gasLimit":21000})"));
        expect("...and says nothing in the modal", "nobody asked", s.sendError.isEmpty());
    }

    std::printf("\nthe verdict drives a BLOCKING banner, so silence is COUNTED rather than\n");
    std::printf("rendered: one blip keeps the last verdict, three withdraw it\n");
    {
        ScopedState s = screen();
        const QString ready = s.verifiedProxy;
        VerdictApplied v = applyVerdict(s, QString(), 0, 3);
        expect("one transport failure", "counts, and changes nothing on screen",
               v.silent == 1 && s.verifiedProxy == ready);
        v = applyVerdict(s, QString(), v.silent, 3);
        expect("two", "still count", v.silent == 2 && s.verifiedProxy == ready);
        v = applyVerdict(s, QString(), v.silent, 3);
        expect("three", "withdraw the verdict", v.silent == 3 && s.verifiedProxy != ready);
        expect("...and what replaces it BLOCKS", "unknown is not off",
               parseObject(s.verifiedProxy).value(QStringLiteral("blocking")).toBool());
        expect("...naming the chain on screen", "so the view may attribute it",
               parseObject(s.verifiedProxy).value(QStringLiteral("chainId")).toInt() == 11155111);
        expect("...and the poll keeps running", "nothing is verified while it is unknown", v.poll);
    }
    {
        ScopedState s = screen();
        const QString ready = s.verifiedProxy;
        const VerdictApplied v = applyVerdict(
            s, q(R"({"ok":true,"chainId":1,"mode":"off","state":"ready"})"), 0, 3);
        expect("a verdict for a chain we are not showing", "is silence, not an answer",
               v.silent == 1 && s.verifiedProxy == ready);
        expect("...and does NOT stop the poll", "an off verdict for another chain says nothing",
               v.poll);
    }
    {
        ScopedState s = screen();
        s.quote = q(R"({"ok":true,"gasLimit":21000})");
        s.quoteRequest = q("REQ");
        const VerdictApplied v = applyVerdict(
            s, q(R"({"ok":true,"chainId":11155111,"mode":"required","state":"unhealthy"})"), 2, 3);
        std::printf("   a quote priced under the PREVIOUS verdict is not the one the user\n");
        std::printf("   would be signing, and the route label was read under it too\n");
        same("the state moved: the figures go", s.quote, q("{}"));
        same("...and the route label with them", s.balancesRoute, QString());
        expect("...and the silence count resets", "the backend answered", v.silent == 0);
    }
    {
        ScopedState s = screen();
        const VerdictApplied v = applyVerdict(
            s, q(R"({"ok":true,"chainId":11155111,"mode":"off","state":"ready"})"), 0, 3);
        expect("a CONFIRMED off", "stops the poll", !v.poll);
    }

    std::printf("\nsubmitSend: `send` is SYNC into a multi module, so it dispatches queued\n");
    std::printf("events inline and the selection can move inside it\n");
    {
        ScopedState s = screen();
        const SendApplied a = applySend(s, q(R"({"ok":true,"requestId":"r-1"})"), true);
        expect("the backend took the request", "and a poll for its approval starts",
               a.accepted && a.requestId == QLatin1String("r-1"));
        expect("...and says nothing in the modal", "nothing was refused", s.sendError.isEmpty());
    }
    {
        ScopedState s = screen();
        const SendApplied a = applySend(s, q(R"({"ok":true,"requestId":"r-1"})"), false);
        std::printf("   the request id is deliberately NOT scoped: it is sitting in the signer,\n");
        std::printf("   and forgetting it would orphan an approval the user still has to answer\n");
        expect("the selection moved under an ACCEPTED send", "the request id is still taken",
               a.accepted && a.requestId == QLatin1String("r-1"));
    }
    {
        ScopedState s = screen();
        const SendApplied a = applySend(s, q(R"({"ok":false,"error":"insufficient funds"})"), true);
        same("a refusal under the selection it was submitted for", s.sendError,
             q("insufficient funds"));
        expect("...reaches the modal", "which is the only surface visible from inside it",
               a.surfaced && !a.accepted);
    }
    {
        ScopedState s = screen();
        s.sendError.clear();
        const SendApplied a = applySend(s, q(R"({"ok":false,"error":"insufficient funds"})"), false);
        std::printf("   THE REPORTED DEFECT: sendError is scoped, so a refusal worded for the\n");
        std::printf("   account being left has already been withdrawn by enterScope — writing\n");
        std::printf("   it here puts it under the account that replaced it\n");
        expect("a refusal the selection moved out from under", "is not surfaced",
               !a.surfaced && s.sendError.isEmpty());
    }
    {
        ScopedState s = screen();
        const SendApplied a = applySend(s, QString(), true);
        expect("a transport failure arrives empty", "and is still a refusal to read",
               a.surfaced && s.sendError == QLatin1String("the wallet backend refused the request"));
    }

    std::printf("\ntx details: the extra fields are about ONE transaction, and the reply says\n");
    std::printf("which. Open A, fetch, go back, open B — and B must not show A's mined time\n");
    {
        const char *A = "0xaaa1000000000000000000000000000000000000000000000000000000000001";
        const char *B = "0xbbb2000000000000000000000000000000000000000000000000000000000002";
        {
            ScopedState s = screen();
            const QString reply = q(R"({"ok":true,"hash":"0xaaa1000000000000000000000000000000000000000000000000000000000001","chainId":11155111,"block":{"timestamp":1756612345}})");
            expect("a reply for the transaction it was asked about", "is published",
                   applyTxDetails(s, reply, q(A)) && s.txDetails == reply);
        }
        {
            ScopedState s = screen();
            const QString forA = q(R"({"ok":true,"hash":"0xaaa1000000000000000000000000000000000000000000000000000000000001","chainId":11155111,"block":{"timestamp":1756612345}})");
            std::printf("   THE REPORTED DEFECT: a lapsed fetch for the PREVIOUS transaction\n");
            std::printf("   landing while another is open would fill this one's rows\n");
            expect("a reply naming another transaction", "is not late, it is about something else",
                   !applyTxDetails(s, forA, q(B)) && s.txDetails.isEmpty());
        }
        {
            // Case-folded: a node answers lowercase hex and a stored hash may be either.
            ScopedState s = screen();
            const QString shouty = q(R"({"ok":true,"hash":"0xAAA1000000000000000000000000000000000000000000000000000000000001","chainId":11155111,"block":{"timestamp":1}})");
            expect("the same hash in another casing", "is the same transaction",
                   applyTxDetails(s, shouty, q(A)));
        }
        {
            ScopedState s = screen();
            const QString elsewhere = q(R"({"ok":true,"hash":"0xaaa1000000000000000000000000000000000000000000000000000000000001","chainId":1,"block":{"timestamp":1}})");
            expect("a reply for another chain", "is refused like every other scoped reply",
                   !applyTxDetails(s, elsewhere, q(A)) && s.txDetails.isEmpty());
        }
        {
            // Partial failure is NORMAL: the two legs are independent, so one landing alone is
            // still an answer and is published whole, error line and all.
            ScopedState s = screen();
            const QString partial = q(R"({"ok":true,"hash":"0xaaa1000000000000000000000000000000000000000000000000000000000001","chainId":11155111,"transaction":{"gasLimit":51000},"blockError":"timed out"})");
            expect("a half answer", "is an answer, and carries the half that failed",
                   applyTxDetails(s, partial, q(A)) && s.txDetails == partial);
        }
        {
            // A refusal names nothing but its hash, and is this call's own answer — the fee
            // card renders it beside the rows it could not fill.
            ScopedState s = screen();
            const QString no = q(R"({"ok":false,"hash":"0xaaa1000000000000000000000000000000000000000000000000000000000001","error":"the verified proxy is not tracking this chain"})");
            expect("a refusal that names its transaction", "is published for it",
                   applyTxDetails(s, no, q(A)) && s.txDetails == no);
        }
        {
            ScopedState s = screen();
            std::printf("   a transport failure arrives EMPTY and the backend cannot word what\n");
            std::printf("   it never answered, so the refusal is authored here — and it still\n");
            std::printf("   names the transaction, or it would land under whichever is open\n");
            expect("a transport failure", "is a refusal about THIS transaction",
                   applyTxDetails(s, QString(), q(A))
                       && parseObject(s.txDetails).value(QStringLiteral("hash")).toString() == q(A)
                       && !replyOk(s.txDetails));
        }
        {
            // Two empty strings compare equal, which would answer "the same transaction" about
            // two we do not have. sameHexValue makes an absent value match nothing.
            ScopedState s = screen();
            expect("a fetch with no hash at all", "matches nothing",
                   !applyTxDetails(s, QString(), QString()) && s.txDetails.isEmpty());
        }
        {
            ScopedState s = screen();
            s.txDetails = q(R"({"ok":true,"hash":"0xaaa"})");
            Selection to = s.at;
            to.chainId = 1;
            enterScope(s, to);
            expect("...and the selection moving withdraws it", "with every other scoped figure",
                   s.txDetails.isEmpty());
        }
    }

    std::printf("\nthe PRODUCER of the selection: its write IS the thing every check above is\n");
    std::printf("made against, so an answer older than the screen is dropped AND asked again\n");
    expect("a read that outlived the screen", "is not published, whatever it says",
           networkStep(false, q(R"({"ok":true,"network":{"chainId":1}})")) == NetworkStep::AskAgain);
    expect("...nor is a refusal that did", "the retry is what re-reads it",
           networkStep(false, q(R"({"ok":false})")) == NetworkStep::AskAgain);
    expect("a read the selection stood still for", "is published",
           networkStep(true, q(R"({"ok":true,"network":{"chainId":1}})")) == NetworkStep::Publish);
    expect("a network we could not read", "is a selection we do not know",
           networkStep(true, q(R"({"ok":false,"error":"no endpoint"})")) == NetworkStep::Unknown);
    expect("the later read's chain, under a held selection", "is adopted", mayAdopt(true, 1));
    expect("...under one that moved", "is not — adopting is a selection write too",
           !mayAdopt(false, 1));
    expect("...and zero", "means the reply did not say", !mayAdopt(true, 0));

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
