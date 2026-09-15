// Another app's request to send, checked as a table. `checkIntentSend` is the whole rule for
// what this wallet accepts from an app, and `answerFromOutcome` is the whole rule for what it
// tells the app back; both are pure over their arguments and run here.
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) test_intent_send.cpp -o /tmp/t && /tmp/t
#include <cstdio>
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif
#include "eth_wallet_ui_intent.h"

namespace {
int failures = 0;
const char *ALICE = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const char *BOB = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
const char *ROUTER = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";

void expect(const char *label, const char *claim, bool got)
{
    if (!got) ++failures;
    std::printf("  %s  %-52s %s\n", got ? "PASS" : "FAIL", label, claim);
}
void same(const char *label, const QString &got, const QString &want)
{
    const bool ok = got == want;
    if (!ok) ++failures;
    std::printf("  %s  %-52s got=%s\n", ok ? "PASS" : "FAIL", label, got.isNull() ? "<null>" : got.toUtf8().constData());
}
QString q(const char *s) { return QString::fromUtf8(s); }

Selection sepolia() { return selectionOf(q(ALICE), QStringLiteral(R"({"chainId":11155111})")); }
QStringList roster() { return {q(ALICE), q(BOB)}; }

QString req(const char *params, const char *id = "req_1", const char *who = "uniswap_ui")
{
    return QStringLiteral(R"({"requestId":"%1","requester":"%2","params":%3})").arg(q(id), q(who), q(params));
}
} // namespace

int main()
{
    std::printf("a well-formed request: checked, cleaned, and reshaped for the sender\n");
    {
        const IntentSendChecked c = checkIntentSend(
            req(R"({"purpose":"Swap 1 ETH for USDC","calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45","value":"1000000000000000000","data":"0x5ae401dc","gasLimitHint":1,"label":"Swap ETH for USDC","meta":{"kind":"swap"}}],"tier":"fast"})"),
            sepolia(), roster(), false);
        expect("it is accepted", "ok", c.ok);
        same("...for the selected account when none was named", c.review.value(QStringLiteral("from")).toString(), q(ALICE));
        same("...on the chain on screen", QString::number(c.review.value(QStringLiteral("chainId")).toInt()), QStringLiteral("11155111"));
        same("...keeping the tier", c.senderRequest.value(QStringLiteral("tier")).toString(), QStringLiteral("fast"));
        const QJsonObject call = c.senderRequest.value(QStringLiteral("calls")).toArray().at(0).toObject();
        same("the call keeps its address", call.value(QStringLiteral("to")).toString(), q(ROUTER));
        same("...its value", call.value(QStringLiteral("value")).toString(), QStringLiteral("1000000000000000000"));
        same("...its calldata", call.value(QStringLiteral("data")).toString(), QStringLiteral("0x5ae401dc"));
        same("...its label", call.value(QStringLiteral("label")).toString(), QStringLiteral("Swap ETH for USDC"));
        expect("a stray field is dropped", "no gasLimitHint", !call.contains(QStringLiteral("gasLimitHint")));
        const QJsonObject meta = call.value(QStringLiteral("meta")).toObject();
        same("the requester's meta rides along", meta.value(QStringLiteral("kind")).toString(), QStringLiteral("swap"));
        same("...stamped with who asked", meta.value(QStringLiteral("app")).toString(), QStringLiteral("uniswap_ui"));
        same("...and by which door", meta.value(QStringLiteral("intent")).toString(), QStringLiteral("evm.transactions.send"));
        same("the purpose is the requester's, verbatim", c.senderRequest.value(QStringLiteral("purpose")).toString(), QStringLiteral("Swap 1 ETH for USDC"));
    }
    std::printf("\ndefaults and normalisation\n");
    {
        const IntentSendChecked c = checkIntentSend(req(R"({"purpose":"p","calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"}]})"), sepolia(), roster(), false);
        expect("a bare call", "is accepted", c.ok);
        same("...with the default tier", c.senderRequest.value(QStringLiteral("tier")).toString(), QStringLiteral("normal"));
        same("...and a label of its own", c.senderRequest.value(QStringLiteral("calls")).toArray().at(0).toObject().value(QStringLiteral("label")).toString(), QStringLiteral("Call 1"));
        const IntentSendChecked n = checkIntentSend(req(R"({"purpose":"p","chainId":11155111,"from":"0x70997970c51812dc3a010c7d01b50e0d17dc79c8","calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45","value":5}]})"), sepolia(), roster(), false);
        expect("a named account this wallet holds, recased", "is accepted", n.ok);
        same("...and used", n.review.value(QStringLiteral("from")).toString(), QStringLiteral("0x70997970c51812dc3a010c7d01b50e0d17dc79c8"));
        same("a numeric value is carried as a string", n.senderRequest.value(QStringLiteral("calls")).toArray().at(0).toObject().value(QStringLiteral("value")).toString(), QStringLiteral("5"));
    }
    std::printf("\nrefusals: bad_request is a payload no retry fixes; busy is the wallet's state\n");
    {
        auto code = [&](const char *params, const Selection &s = sepolia(), bool sending = false) {
            return checkIntentSend(req(params), s, roster(), sending).error;
        };
        same("no calls", code(R"({"purpose":"p","calls":[]})"), QStringLiteral("bad_request"));
        same("no purpose", code(R"({"purpose":"  ","calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"}]})"), QStringLiteral("bad_request"));
        same("a call without an address", code(R"({"purpose":"p","calls":[{"data":"0x00"}]})"), QStringLiteral("bad_request"));
        same("calldata that is not hex", code(R"({"purpose":"p","calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45","data":"hello"}]})"), QStringLiteral("bad_request"));
        same("another chain than the one on screen", code(R"({"purpose":"p","chainId":1,"calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"}]})"), QStringLiteral("bad_request"));
        same("an account this wallet does not hold", code(R"({"purpose":"p","from":"0x1234567890123456789012345678901234567890","calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"}]})"), QStringLiteral("bad_request"));
        same("a tier that is not one of the three", code(R"({"purpose":"p","tier":"turbo","calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"}]})"), QStringLiteral("bad_request"));
        QString nine = QStringLiteral(R"({"purpose":"p","calls":[)");
        for (int i = 0; i < 9; ++i) nine += QStringLiteral(R"(%1{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"})").arg(i ? "," : "");
        nine += QStringLiteral("]}");
        same("more calls than the sender takes", code(nine.toUtf8().constData()), QStringLiteral("bad_request"));
        same("a wallet already waiting on a send", code(R"({"purpose":"p","calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"}]})", sepolia(), true), QStringLiteral("busy"));
        same("a wallet with no account", code(R"({"purpose":"p","calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"}]})", selectionOf(QString(), QStringLiteral(R"({"chainId":11155111})"))), QStringLiteral("busy"));
        const IntentSendChecked why = checkIntentSend(req(R"({"purpose":"p","chainId":1,"calls":[{"to":"0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"}]})"), sepolia(), roster(), false);
        expect("every refusal says why, for the app's author", "detail", why.detail.contains(QStringLiteral("11155111")));
    }
    std::printf("\nthe answer, from the wallet's own outcome record\n");
    {
        IntentAnswer a = answerFromOutcome(q(R"({"status":"broadcast","hash":"0xb","hashes":["0xa","0xb"]})"), QStringLiteral("snd_1"));
        expect("a broadcast", "answers ok", a.ok);
        same("...with every hash", QString::number(a.result.value(QStringLiteral("hashes")).toArray().size()), QStringLiteral("2"));
        same("...the last one", a.result.value(QStringLiteral("hash")).toString(), QStringLiteral("0xb"));
        same("...and the sender's request id", a.result.value(QStringLiteral("requestId")).toString(), QStringLiteral("snd_1"));
        a = answerFromOutcome(q(R"({"status":"rejected"})"), QStringLiteral("snd_2"));
        expect("a rejection", "is not ok", !a.ok);
        same("...with the status as the error", a.error, QStringLiteral("rejected"));
        a = answerFromOutcome(q(R"({"status":"failed","reason":"leg 2 of 2: reverted"})"), QStringLiteral("snd_3"));
        same("a failure carries the sender's reason", a.result.value(QStringLiteral("reason")).toString(), QStringLiteral("leg 2 of 2: reverted"));
        a = answerFromOutcome(QString(), QStringLiteral("snd_4"));
        expect("no outcome yet", "answers nothing", !a.ok && a.error.isEmpty() && a.result.isEmpty());
    }
    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
