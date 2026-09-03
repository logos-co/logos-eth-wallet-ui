// A reply is rendered only against the scope it NAMES, as a table.
//
// The generation counter this replaces is authoritative for moves the view made and blind to
// moves it has not observed. The measured failure: a balances read is in flight, the user
// picks another network, `set_active_chain` is a SYNC call into a `concurrency:"multi"` module
// and so runs a nested event loop, and the reply for the NEW chain is dispatched inside it
// while the counter still matches — putting Sepolia's number under "ETHEREUM", with
// scopedDataFresh true so no dash and no spinner stood in its place.
//
// The wire already carries the answer: get_balances and get_history name `chainId` and
// `address`, list_tokens and suggest_fees name `chainId`, the verified-proxy verdict names
// `chainId`, and a quote names `chainId` and `from`. `answersFor` is the check the counter
// cannot make, and it is a pure function so its table needs no app, no backend and no GUI.
//
// Run it from this directory, with PKG_CONFIG_PATH pointing at the qtbase this module builds
// against (`<qtbase>/lib/pkgconfig`):
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) \
//       test_reply_scope.cpp -o /tmp/test_reply_scope && /tmp/test_reply_scope

#include <cstdio>

// Qt 6.9's qyieldcpu.h calls __yield() without declaring it, which is an error for a plain
// clang invocation on aarch64. Qt's own CMake build never sees it.
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif

#include "eth_wallet_ui_scope.h"

namespace {

int failures = 0;

const char *ALICE = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

/// Sepolia, account A: the selection on screen throughout.
Selection screen()
{
    Selection s;
    s.account = QString::fromUtf8(ALICE);
    s.chainId = 11155111;
    return s;
}

void expectTrue(const char *label, const char *claim, bool got)
{
    if (!got)
        ++failures;
    std::printf("  %s  %-52s %s\n", got ? "PASS" : "FAIL", label, claim);
}

void check(const char *label, const char *reply, bool want)
{
    const bool got = answersFor(QString::fromUtf8(reply), screen());
    if (got != want)
        ++failures;
    std::printf("  %s  %-52s got=%-8s want=%s\n", got == want ? "PASS" : "FAIL", label,
                got ? "acted" : "dropped", want ? "acted" : "dropped");
}

void checkSend(const char *label, const char *request, bool want)
{
    const bool got = describesASend(QString::fromUtf8(request));
    if (got != want)
        ++failures;
    std::printf("  %s  %-52s got=%-8s want=%s\n", got == want ? "PASS" : "FAIL", label,
                got ? "price" : "nothing", want ? "price" : "nothing");
}

} // namespace

int main()
{
    std::printf("a reply for the selection on screen is the one that may be rendered\n");
    check("get_balances for this account on this chain",
          R"({"ok":true,"chainId":11155111,"address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
              "balances":[],"route":"verified"})", true);
    std::printf("   list_accounts hands back EIP-55 hex and the backend echoes what it was\n");
    std::printf("   given, so a case-only difference is the same account\n");
    check("...answered in another casing",
          R"({"ok":true,"chainId":11155111,"address":"0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
              "balances":[]})", true);

    std::printf("\nthe reported defect: a reply for a chain the view has NOT been told about\n");
    check("balances answered for the chain just switched TO",
          R"({"ok":true,"chainId":1,"address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
              "balances":[{"symbol":"ETH","display":"1.5"}]})", false);
    check("get_history for another chain",
          R"({"ok":true,"chainId":1,"address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
              "transactions":[],"stillDue":false})", false);
    check("get_balances for the account just switched AWAY from",
          R"({"ok":true,"chainId":11155111,"address":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
              "balances":[]})", false);
    check("list_tokens for another chain",
          R"({"ok":true,"chainId":1,"tokens":[{"symbol":"USDC"}]})", false);
    check("suggest_fees for another chain",
          R"({"ok":true,"chainId":1,"baseFeePerGas":"7","tiers":{}})", false);
    check("a verdict for another chain",
          R"({"ok":true,"chainId":1,"mode":"required","state":"ready","blocking":false})", false);
    check("a quote priced on another chain",
          R"({"ok":true,"chainId":1,"from":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
              "gasLimit":21000})", false);
    check("a quote priced for another account",
          R"({"ok":true,"chainId":11155111,"from":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
              "gasLimit":21000})", false);

    std::printf("\nan `ok` payload naming NEITHER cannot be attributed, so it is not evidence\n");
    std::printf("   about the selection on screen. Every scoped read this view makes names its\n");
    std::printf("   scope; one that stops is a backend regression, and this shows a dash\n");
    check("a balances reply carrying no scope at all",
          R"({"ok":true,"balances":[{"symbol":"ETH","display":"1.5"}]})", false);

    std::printf("\na REFUSAL names nothing by design and is the answer to the call we made:\n");
    std::printf("   dropping it would leave the previous figures standing with no error\n");
    check("the backend refused", R"({"ok":false,"error":"module context not ready"})", true);
    check("the verified gate blocked the read",
          R"({"ok":false,"error":"the verified proxy is not usable",
              "verifiedProxy":{"state":"unhealthy"}})", true);
    check("a transport failure arrives empty", "", true);
    check("or not as JSON at all", "<html>502</html>", true);
    std::printf("   the control: a refusal that DOES name another chain is still about\n");
    std::printf("   something else, and its message must not land under this network\n");
    check("a refusal naming another chain",
          R"({"ok":false,"error":"no endpoint","chainId":1})", false);

    std::printf("\na network we could not read is chainId 0: nothing may be attributed to it\n");
    {
        Selection unknown;
        unknown.account = QString::fromUtf8(ALICE);
        expectTrue("balances for a real chain", "are dropped while the network is unknown",
                   !answersFor(QString::fromUtf8(
                       R"({"ok":true,"chainId":11155111,"address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"})"),
                       unknown));
        expectTrue("the synthesised unknown verdict", "names chainId 0 and is published",
                   answersFor(QString::fromUtf8(R"({"ok":false,"chainId":0,"mode":"unknown"})"),
                              unknown));
    }

    std::printf("\nthe quote is scoped by REQUEST too, and the wire echoes no request:\n");
    std::printf("   the view stamps the one it priced, and a form describing another\n");
    std::printf("   withdraws the figures whether or not anything re-priced\n");
    {
        const QString first = QStringLiteral(R"({"to":"0xBob","amountUnits":"0.1"})");
        ScopedState s;
        s.quote = QStringLiteral(R"({"ok":true,"gasLimit":21000})");
        s.quoteRequest = first;
        s.quoteStale = true;
        expectTrue("re-pricing the same request", "keeps the figures it priced",
                   !enterQuoteRequest(s, first) && s.quoteRequest == first);
        expectTrue("clearing the amount", "withdraws them though nothing was called",
                   enterQuoteRequest(s, QStringLiteral(R"({"to":"0xBob","amountUnits":""})"))
                       && s.quote == QLatin1String("{}") && s.quoteRequest.isEmpty()
                       && !s.quoteStale);
    }

    std::printf("\nand a form that describes no send is nothing to price, not an error\n");
    checkSend("a complete request", R"({"to":"0xBob","amountUnits":"0.1"})", true);
    checkSend("base units instead of token units", R"({"to":"0xBob","amount":"100000"})", true);
    checkSend("the amount cleared", R"({"to":"0xBob","amountUnits":""})", false);
    checkSend("...or blanked to spaces", R"({"to":"0xBob","amountUnits":"   "})", false);
    checkSend("the recipient cleared", R"({"to":"","amountUnits":"0.1"})", false);
    checkSend("a form with neither", R"({"tier":"normal"})", false);
    checkSend("nothing at all", "", false);

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
