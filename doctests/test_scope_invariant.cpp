// The selection-change withdrawal, as a table.
//
// The rule under test is the one the user hit: a value on screen must describe the account and
// network CURRENTLY selected, or be shown as unknown. `enterScope` in src/eth_wallet_ui_scope.h
// is the single place that enforces it, and EthWalletUiBackend reaches it only through the two
// generated selection setters — so a handler cannot move the selection around it.
//
// This is a pure function over a plain struct precisely so the rule is testable with no view,
// no backend and no GUI. doctests/assert_ui.py needs a live inspector; a regression test that
// can only run against an app is not a regression test.
//
// Run it from this directory, with PKG_CONFIG_PATH pointing at the qtbase this module builds
// against (`<qtbase>/lib/pkgconfig`):
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) \
//       test_scope_invariant.cpp -o /tmp/test_scope_invariant && /tmp/test_scope_invariant

#include <cstdio>

// Qt 6.9's qyieldcpu.h calls __yield() without declaring it, which is an error for a plain
// clang invocation on aarch64. Qt's own CMake build never sees it.
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif

#include "eth_wallet_ui_scope.h"

namespace {

int failures = 0;

const char *SEPOLIA = R"({"chainId":11155111,"name":"Sepolia"})";
const char *MAINNET = R"({"chainId":1,"name":"Ethereum"})";
const char *ALICE = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const char *BOB = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

void expect(const char *label, const char *field, bool got, bool want)
{
    const bool ok = got == want;
    if (!ok)
        ++failures;
    std::printf("  %s  %-46s %-30s got=%-9s want=%s\n", ok ? "PASS" : "FAIL", label, field,
                got ? "kept" : "withdrawn", want ? "kept" : "withdrawn");
}

void expectTrue(const char *label, const char *claim, bool got)
{
    if (!got)
        ++failures;
    std::printf("  %s  %-46s %s\n", got ? "PASS" : "FAIL", label, claim);
}

/// A screen with everything read: the state the user was looking at when they changed account.
ScopedState readScreen()
{
    ScopedState s;
    s.at = selectionOf(QString::fromUtf8(ALICE), QString::fromUtf8(SEPOLIA));
    s.fresh = true;
    s.balances = R"([{"symbol":"ETH","display":"1.5","exact":"1.5"}])";
    s.balancesRoute = "verified";
    s.history = R"([{"hash":"0xdead","status":"confirmed"}])";
    s.blockedChains = R"([{"chainId":11155111,"count":2}])";
    s.quote = R"({"ok":true,"gasLimit":21000})";
    s.quoteRequest = R"({"to":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8","amountUnits":"0.1"})";
    s.quoteStale = true;
    s.sendError = "insufficient funds";
    s.txDetails = R"({"ok":true,"hash":"0xdead","block":{"timestamp":1756612345}})";
    s.tokens = R"([{"symbol":"ETH","native":true}])";
    s.feeTiers = R"({"source":"eip1559"})";
    s.verifiedProxy = R"({"ok":true,"chainId":11155111,"mode":"required","state":"ready"})";
    return s;
}

/// What a move to `account` on `network` may leave standing.
struct Want {
    bool moved;
    bool keepsAccountData;
    bool keepsChainData;
};

void check(const char *label, const char *account, const char *network, Want w)
{
    ScopedState s = readScreen();
    const bool moved = enterScope(s, selectionOf(QString::fromUtf8(account),
                                                 QString::fromUtf8(network)));
    expectTrue(label, w.moved ? "the selection moved" : "the selection did NOT move",
               moved == w.moved);
    expect(label, "scopedDataFresh", s.fresh, w.keepsAccountData);
    expect(label, "balancesJson", !s.balances.isEmpty(), w.keepsAccountData);
    expect(label, "balancesRoute", !s.balancesRoute.isEmpty(), w.keepsAccountData);
    expect(label, "historyJson", !s.history.isEmpty(), w.keepsAccountData);
    expect(label, "blockedChainsJson", !s.blockedChains.isEmpty(), w.keepsAccountData);
    expect(label, "quoteJson", s.quote != QLatin1String("{}"), w.keepsAccountData);
    expect(label, "quoteRequestJson", !s.quoteRequest.isEmpty(), w.keepsAccountData);
    expect(label, "quoteStale", s.quoteStale, w.keepsAccountData);
    expect(label, "sendError", !s.sendError.isEmpty(), w.keepsAccountData);
    // Detail about one transaction of THIS account. Left standing, it renders a mined time
    // under a transaction the new account never made.
    expect(label, "txDetailsJson", !s.txDetails.isEmpty(), w.keepsAccountData);
    expect(label, "tokensJson", !s.tokens.isEmpty(), w.keepsChainData);
    expect(label, "feeTiersJson", s.feeTiers != QLatin1String("{}"), w.keepsChainData);
    // The verdict names a chain and drives a BLOCKING banner: one for the network being left
    // would claim the wallet is showing proved figures for a chain it is no longer on.
    expect(label, "verifiedProxyJson", s.verifiedProxy != QLatin1String("{}"), w.keepsChainData);

    // Withdrawn means UNKNOWN, never an empty answer: "[]" renders as "No transactions yet"
    // and as a network with no tokens on it, which are claims about a scope nothing has read.
    if (!w.keepsAccountData)
        expectTrue(label, "history reads as UNKNOWN, not as \"[]\"", s.history == QString());
    if (!w.keepsChainData)
        expectTrue(label, "tokens read as UNKNOWN, not as \"[]\"", s.tokens == QString());
}

} // namespace

int main()
{
    std::printf("a change of ACCOUNT withdraws everything read for the account being left\n");
    std::printf("   (this is the reported bug: three lines that cleared nothing, so account\n");
    std::printf("    A's balances and A's Activity rows sat under account B's name)\n");
    check("pick another account", BOB, SEPOLIA, {true, false, true});
    std::printf("   the network is unchanged, so the token list and the fee tiers stand: an\n");
    std::printf("   account switch does not run refresh(), and nothing would re-read them\n");

    std::printf("\na change of NETWORK withdraws the chain-scoped values as well\n");
    check("pick another network", ALICE, MAINNET, {true, false, false});
    check("...and another account with it", BOB, MAINNET, {true, false, false});

    std::printf("\na network we could not READ is a selection we do not know\n");
    check("get_active_network failed", ALICE, "{}", {true, false, false});
    check("...or answered with something that is not JSON", ALICE, "<html>502</html>",
          {true, false, false});
    check("...or with a network carrying no chainId", ALICE, R"({"name":"Sepolia"})",
          {true, false, false});

    std::printf("\nthe account disappearing from the keystore is a move like any other\n");
    check("no account left to select", "", SEPOLIA, {true, false, true});

    std::printf("\nthe control: a re-read of the SAME selection must not blank the screen\n");
    check("the same account and network", ALICE, SEPOLIA, {false, true, true});
    std::printf("   list_accounts returns EIP-55 checksummed hex and callers hand back any\n");
    std::printf("   casing, so a case-only difference is the same account, not a move\n");
    check("the same account, lowercased", "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", SEPOLIA,
          {false, true, true});
    std::printf("   and the network object carries rpcUrl and the verdict, which move on\n");
    std::printf("   their own — only the chainId decides whether the network changed\n");
    check("the same chain, a re-read network object",
          ALICE, R"({"chainId":11155111,"name":"Sepolia","rpcUrl":"http://127.0.0.1:8545"})",
          {false, true, true});

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
