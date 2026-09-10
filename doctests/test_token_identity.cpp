// A TOKEN IS ITS CONTRACT, as a shape over the view's own source.
//
// The probe beside this one measures the behaviour with two real same-symbol contracts on
// screen. This measures the thing a probe cannot: that no NEW call site resolves a token by
// symbol. The defect was never one lookup — it was eight, spread over the list, the order map,
// the detail screen, the objectNames, the picker and the Manage row, and every one of them
// looked locally reasonable. A rendering path that matches on a symbol is the bug, wherever
// it is added next.
//
// Run it from this directory — see doctests/run_tables.sh, or by hand:
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) \
//       test_token_identity.cpp -o /tmp/test_token_identity && /tmp/test_token_identity

#include <cstdio>

#if defined(__aarch64__)
#  include <arm_acle.h>
#endif

#include <QFile>
#include <QRegularExpression>
#include <QString>
#include <QStringList>

namespace {

int failures = 0;

void expect(const char *label, const char *claim, bool got)
{
    if (!got)
        ++failures;
    std::printf("  %s  %-52s %s\n", got ? "PASS" : "FAIL", label, claim);
}

QString view;

bool has(const char *needle) { return view.contains(QLatin1String(needle)); }

/// Every `objectName: "<prefix>" + <expr>` in the file, as the expression it builds from.
QStringList keyedBy(const char *prefix)
{
    QRegularExpression re(QStringLiteral("objectName: \"%1\" \\+ ([^\\n]+)")
                              .arg(QString::fromLatin1(prefix)));
    QStringList out;
    auto it = re.globalMatch(view);
    while (it.hasNext())
        out << it.next().captured(1).trimmed();
    return out;
}

/// A row's objectName must be built from the identity function and nothing else — two rows
/// named tokenRow_LIT are one row said twice, to a reader and to the harness alike.
void expectKeyed(const char *prefix)
{
    const QStringList sites = keyedBy(prefix);
    bool ok = !sites.isEmpty();
    for (const QString &s : sites)
        ok = ok && s.startsWith(QLatin1String("root.tokenKey("));
    std::printf("  %s  %-52s %s\n", ok ? "PASS" : "FAIL", prefix,
                sites.isEmpty() ? "NO SUCH objectName IN THE VIEW"
                                : "built from root.tokenKey(), never a symbol");
    if (!ok)
        ++failures;
}

} // namespace

int main()
{
    QFile f(QStringLiteral("../src/qml/EthWalletView.qml"));
    if (!f.open(QIODevice::ReadOnly)) {
        std::printf("  FAIL  cannot read ../src/qml/EthWalletView.qml\n");
        return 1;
    }
    view = QString::fromUtf8(f.readAll());

    std::printf("there is ONE identity function, and it is the contract\n");
    expect("tokenKey keys on the address", "case-folded, so two spellings are one token",
           has("if (typeof t.address === \"string\" && t.address.length > 0) "
               "return t.address.toLowerCase()"));
    expect("...and the native currency has its own key",
           "an address cannot spell it", has("if (t.native === true) return \"native\""));

    std::printf("\nand no rendering path resolves a token by the symbol it wears\n");
    expect("no by-symbol lookup survives", "tokenBySymbol is gone", !has("tokenBySymbol"));
    expect("the balances match on identity", "never balances[i].symbol ===",
           !has("balances[i].symbol ===") && has("if (tokenKey(balances[i]) === k)"));
    expect("...the token list too", "never tokens[i].symbol ===",
           !has("tokens[i].symbol ===") && has("if (tokenKey(tokens[i]) === key)"));
    expect("the published order is keyed", "pos[tokenKey(...)], not pos[symbol]",
           has("pos[tokenKey(balances[i])] = i") && !has("pos[String(balances[i].symbol)]"));
    expect("...and its comparator is total", "a tie falls back to the list's own index",
           has("return a.p !== b.p ? a.p - b.p : a.i - b.i"));
    expect("the detail screen opens on a key", "not on a name two contracts share",
           has("function openTokenDetail(key)") && has("if (tokenByKey(key) === null) return"));

    std::printf("\nevery row that can appear beside its namesake is named for its contract\n");
    expectKeyed("tokenRow_");
    expectKeyed("balance_");
    expectKeyed("tokenName_");
    expectKeyed("tokenContract_");
    expectKeyed("manageTokenRow_");
    expectKeyed("manageTokenBalance_");
    expectKeyed("manageTokenName_");
    expectKeyed("manageTokenSource_");
    expectKeyed("manageTokenContract_");
    expectKeyed("manageTokenToggle_");

    std::printf("\nand the send names the CONTRACT to the backend, not a bare symbol\n");
    expect("the request carries the address", "SendRequest.tokenAddress",
           has("r.tokenAddress = sendPage.tokenAddress"));
    expect("...written in one place", "selectToken() sets both fields together",
           has("function selectToken(t)")
               && !has("sendPage.token = root.tokens[currentIndex].symbol"));
    expect("...and the picker chooses a ROW", "never a symbol off the model",
           has("onActivated: sendPage.selectToken(root.tokens[currentIndex])"));
    expect("the section finds its row by identity", "tokenIndex matches tokenKey",
           has("if (root.tokenKey(root.tokens[i]) === k) return i"));

    std::printf("\ntwo rows sharing a symbol are tellable apart by a human, too\n");
    expect("the contract is shown where it settles a question",
           "disambiguator(), on the row", has("function disambiguator(t, dup)")
               && has("dup[String(t.symbol)] === true ? shortAddr(t.address)"));
    expect("...in the picker as well", "name and contract on the line that spends it",
           has("function tokenPickerLabel(t)"));
    expect("a bundled logo goes only to a row this build vouches for",
           "a mark by symbol lends its authority away",
           has("if (!t || (t.native !== true && t.builtin !== true)) return \"\""));

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
