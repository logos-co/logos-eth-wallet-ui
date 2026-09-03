// The persisted token order: which replies may speak for it, and which one may not.
//
// THE DEFECT THIS EXISTS FOR: adoptTokenSort had exactly ONE call site — the catalogue search —
// so the order the user chose was restored only if they happened to open Manage tokens and
// type into it. On an ordinary launch the Tokens tab showed the default order whatever was
// persisted. Three replies carry `tokenSort`; the rule below says what each may do with it.
//
// The second half is the hazard the first half creates. Adopting from three reads means a read
// issued under the OLD order can land after the user has picked a new one, naming the order
// they just replaced — and the menu moves back under their hand. The counter is what stops it.
//
// Run it from this directory — see doctests/run_tables.sh, or by hand:
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) \
//       test_token_sort.cpp -o /tmp/test_token_sort && /tmp/test_token_sort

#include <cstdio>

// Qt 6.9's qyieldcpu.h calls __yield() without declaring it, which is an error for a plain
// clang invocation on aarch64. Qt's own CMake build never sees it.
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif

#include <QFile>
#include <QRegularExpression>

#include "eth_wallet_ui_apply.h"

namespace {

int failures = 0;

void same(const char *label, const QString &got, const QString &want)
{
    const bool ok = got == want;
    if (!ok)
        ++failures;
    std::printf("  %s  %-56s got=%s\n", ok ? "PASS" : "FAIL", label,
                got.isEmpty() ? "<unpublished>" : got.toUtf8().constData());
}

QString q(const char *s) { return QString::fromUtf8(s); }

/// `list_tokens`: read synchronously by refresh(), which runs at startup.
const char *TOKENS = R"({"ok":true,"chainId":1,"tokenSort":"balance","tokens":[]})";
/// `get_balances`: the reply the Tokens tab is actually built from.
const char *BALANCES =
    R"({"ok":true,"chainId":1,"address":"0xf39F","tokenSort":"balance","balances":[]})";
/// `list_available_tokens`: the only one that used to be read.
const char *CATALOGUE =
    R"({"ok":true,"chainId":1,"tokenSort":"alpha","listed":40,"total":0,"shown":0,"tokens":[]})";

} // namespace

int main()
{
    std::printf("EVERY listing carries the persisted order, so it is restored by whichever\n");
    std::printf("reply lands first — never only by a search on a screen nobody opened\n");
    same("the token list, read at startup", adoptedTokenSort(q(TOKENS), 0, 0), q("balance"));
    same("...the balances the tab is built from", adoptedTokenSort(q(BALANCES), 0, 0),
         q("balance"));
    same("...and the catalogue search, as before", adoptedTokenSort(q(CATALOGUE), 0, 0),
         q("alpha"));

    std::printf("\na reply that does not name an order says nothing about it: the published\n");
    std::printf("order is LEFT ALONE rather than reset to a default nobody chose\n");
    same("a reply carrying no order", adoptedTokenSort(q(R"({"ok":true,"chainId":1})"), 0, 0),
         QString());
    same("...a refusal", adoptedTokenSort(q(R"({"ok":false,"error":"no endpoint"})"), 0, 0),
         QString());
    same("...and a transport failure, which arrives empty", adoptedTokenSort(QString(), 0, 0),
         QString());
    same("an order this build does not know",
         adoptedTokenSort(q(R"({"ok":true,"tokenSort":"marketcap"})"), 0, 0), QString());
    same("...nor an empty one", adoptedTokenSort(q(R"({"ok":true,"tokenSort":""})"), 0, 0),
         QString());

    std::printf("\nTHE HAZARD ADOPTING FROM THREE READS CREATES: one issued under the previous\n");
    std::printf("order lands after the user picked a different one, and names what they just\n");
    std::printf("replaced. A reply older than the choice may not speak for the order at all\n");
    same("a listing that crossed the choice", adoptedTokenSort(q(CATALOGUE), 0, 1), QString());
    same("...the balances too — same reply, same rule", adoptedTokenSort(q(BALANCES), 2, 3),
         QString());
    same("...and the startup token list", adoptedTokenSort(q(TOKENS), 7, 9), QString());
    std::printf("   while a read the choice stood still for is the persisted answer, and is\n");
    std::printf("   exactly how the menu confirms what the backend actually stored\n");
    same("a read issued after the choice", adoptedTokenSort(q(CATALOGUE), 4, 4), q("alpha"));
    same("...and one issued after several", adoptedTokenSort(q(BALANCES), 12, 12), q("balance"));

    // The rule above is only ever reached from a call site, and the defect WAS the call
    // sites: one of three. A table that ran the rule and nothing else would have been green
    // throughout the bug.
    QFile f(QStringLiteral("../src/eth_wallet_ui_backend.cpp"));
    if (!f.open(QIODevice::ReadOnly)) {
        std::printf("  FAIL  the backend source could not be read\n");
        return 1;
    }
    const QString src = QString::fromUtf8(f.readAll());
    std::printf("\nand the rule is reached from all three reads. This half is the defect: one\n");
    std::printf("call site, on the one screen the user need never open\n");
    for (const char *fn : {"loadNetwork", "loadBalancesAndHistory", "runTokenSearch"}) {
        const int at = src.indexOf(QStringLiteral("EthWalletUiBackend::%1(")
                                       .arg(QString::fromLatin1(fn)));
        const int end = at < 0 ? -1 : src.indexOf(QStringLiteral("\n}\n"), at);
        const bool ok = at >= 0 && end > at
            && src.mid(at, end - at).contains(QStringLiteral("adoptTokenSort("));
        if (!ok)
            ++failures;
        std::printf("  %s  %-56s %s\n", ok ? "PASS" : "FAIL", fn,
                    ok ? "takes the order off its reply" : "READS AN ORDER AND DROPS IT");
    }
    {
        const int at = src.indexOf(QStringLiteral("EthWalletUiBackend::chooseTokenSort("));
        const int call = src.indexOf(QStringLiteral("set_token_sort("), at);
        const int bump = src.indexOf(QStringLiteral("++m_sortChoiceGen"), at);
        const bool ok = at >= 0 && bump > at && call > bump;
        if (!ok)
            ++failures;
        std::printf("  %s  %-56s %s\n", ok ? "PASS" : "FAIL", "chooseTokenSort",
                    ok ? "counts the choice BEFORE the call that can pump a reply in"
                       : "the choice is not counted ahead of the call");
    }

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
