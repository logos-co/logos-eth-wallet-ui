// tx_sender_module's `send_status`, as this wallet reads it: which replies keep pollSend polling,
// which end the send and with what outcome, and what an app that asked through
// `evm.transactions.send` is then told. The sender's `final` decides, refusals included: a
// refusal that may yet pass must be asked again, or an approved send is never broadcast.
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) test_send_status.cpp -o /tmp/t && /tmp/t
#include <cstdio>
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif
#include "eth_wallet_ui_intent.h"

namespace {
int failures = 0;

const char *STUCK_REASON =
    "the broadcast has not answered; this send may already be on chain and must not be sent again";

void expect(const char *label, const char *claim, bool got)
{
    if (!got) ++failures;
    std::printf("  %s  %-58s %s\n", got ? "PASS" : "FAIL", label, claim);
}
QString q(const char *s) { return QString::fromUtf8(s); }

// The shape tx_sender's `job_reply` answers and eth_wallet_backend relays, `extra` merged in.
QString reply(const char *status, const QString &extra = QString())
{
    return QStringLiteral(
               R"({"ok":true,"requestId":"snd_1","handle":"h","chainId":11155111,"from":"0xaaaa",)"
               R"("status":"%1","origin":"eth_wallet_backend","purpose":"p","legs":[],"hashes":[]%2})")
        .arg(q(status), extra);
}

QString refusal(const char *error, const QString &extra = QString())
{
    return QStringLiteral(R"({"ok":false,"error":"%1"%2})").arg(q(error), extra);
}

const QString NOT_FINAL = QStringLiteral(R"(,"final":false)");
const QString FINAL = QStringLiteral(R"(,"final":true)");

QString stuck()
{
    return reply("stuck", QStringLiteral(R"(,"reason":"%1","final":true)").arg(q(STUCK_REASON)));
}

QString broadcast()
{
    return reply("broadcast", QStringLiteral(R"(,"hashes":["0xa","0xb"],"hash":"0xb","final":true)"));
}

// What pollSend publishes, and so the only thing an app can be answered from.
QString published(const SendPolled &p)
{
    return p.settled ? toJsonCompact(p.outcome) : QString();
}

QString statusOf(const SendPolled &p)
{
    return p.outcome.value(QStringLiteral("status")).toString();
}
} // namespace

int main()
{
    std::printf("still moving: the poll keeps coming\n");
    expect("awaitingApproval", "asked again", !sendPolled(reply("awaitingApproval", NOT_FINAL)).settled);
    expect("awaitingApproval held by the verified gate", "asked again",
           !sendPolled(reply("awaitingApproval", QStringLiteral(R"(,"blocked":true,)"
                                                                R"("reason":"The verified proxy is not usable.","final":false)")))
                .settled);
    expect("broadcasting, first leg out, second still to go", "asked again",
           !sendPolled(reply("broadcasting", QStringLiteral(R"(,"hashes":["0xa"],"hash":"0xa","final":false)")))
                .settled);

    std::printf("\na refusal that may yet pass is asked again, never taken as the end\n");
    for (const char *error : {"no time left to read the approval", "tx_sender_module: Timeout",
                              "unknown approval state 'expired'"}) {
        const SendPolled p = sendPolled(refusal(error, NOT_FINAL));
        expect(error, "asked again, nothing published", !p.settled && p.outcome.isEmpty());
    }
    expect("a reply that never arrived", "asked again", !sendPolled(QString()).settled);

    std::printf("\nfinal: the poll stops, with the outcome in the sender's word\n");
    for (const char *s : {"broadcast", "rejected", "cancelled", "failed", "stuck"}) {
        const SendPolled p = sendPolled(reply(s, FINAL));
        expect(s, "settled as itself", p.settled && statusOf(p) == q(s));
    }
    {
        const SendPolled b = sendPolled(broadcast());
        expect("a broadcast keeps its last hash", "hash",
               b.outcome.value(QStringLiteral("hash")).toString() == q("0xb"));
        expect("...and every hash of the bundle", "hashes",
               b.outcome.value(QStringLiteral("hashes")).toArray().size() == 2);
        expect("stuck carries the sender's warning", "reason",
               sendPolled(stuck()).outcome.value(QStringLiteral("reason")).toString() == q(STUCK_REASON));
    }

    std::printf("\na final refusal is a send the sender no longer holds\n");
    {
        const SendPolled p = sendPolled(refusal("no send with id 'snd_1'", FINAL));
        expect("it ends the poll", "settled", p.settled);
        expect("...as failed", "status", statusOf(p) == q("failed"));
        expect("...in the sender's words", "reason",
               p.outcome.value(QStringLiteral("reason")).toString() == q("no send with id 'snd_1'"));
    }

    std::printf("\na backend that predates `final` is read the way it behaves\n");
    expect("awaitingApproval", "asked again", !sendPolled(reply("awaitingApproval")).settled);
    expect("broadcasting", "asked again", !sendPolled(reply("broadcasting")).settled);
    expect("stuck", "settled", sendPolled(reply("stuck")).settled);
    expect("broadcast", "settled", sendPolled(reply("broadcast")).settled);
    for (const char *error : {"no time left to read the approval", "no send with id 'snd_1'"})
        expect(error, "no refusal is final", !sendPolled(refusal(error)).settled);

    std::printf("\na cancel reads the same: refused, the send is still going\n");
    {
        const SendPolled claimed =
            sendPolled(refusal("this send is being broadcast and can no longer be cancelled"));
        expect("the broadcast is already claimed", "nothing settles",
               !claimed.settled && claimed.outcome.isEmpty());
        expect("...or the send already settled", "the poll says how",
               !sendPolled(refusal("this send is already rejected and cannot be cancelled")).settled);
        const SendPolled taken = sendPolled(reply("cancelled", FINAL));
        expect("taken, it is the cancelled send", "cancelled",
               taken.settled && statusOf(taken) == q("cancelled"));
    }

    std::printf("\nthe app is answered from what the poll settled, never from a send still moving\n");
    {
        const struct {
            const char *label;
            QString reply;
        } moving[] = {
            {"awaitingApproval", reply("awaitingApproval", NOT_FINAL)},
            {"broadcasting", reply("broadcasting", QStringLiteral(R"(,"hashes":["0xa"],"final":false)"))},
            {"a refusal that may yet pass", refusal("no time left to read the approval", NOT_FINAL)},
        };
        for (const auto &m : moving) {
            const IntentAnswer a = answerFromOutcome(published(sendPolled(m.reply)), QStringLiteral("snd_1"));
            expect(m.label, "answers nothing yet", !a.ok && a.error.isEmpty() && a.result.isEmpty());
        }
        const IntentAnswer s = answerFromOutcome(published(sendPolled(stuck())), QStringLiteral("snd_1"));
        expect("stuck", "is not ok, in the sender's word", !s.ok && s.error == QLatin1String("stuck"));
        expect("...carrying the warning not to send it again", "reason",
               s.result.value(QStringLiteral("reason")).toString() == q(STUCK_REASON));
        const IntentAnswer gone = answerFromOutcome(
            published(sendPolled(refusal("no send with id 'snd_1'", FINAL))), QStringLiteral("snd_1"));
        expect("a send the sender no longer holds", "is answered failed",
               !gone.ok && gone.error == QLatin1String("failed"));
        const IntentAnswer b = answerFromOutcome(published(sendPolled(broadcast())), QStringLiteral("snd_1"));
        expect("a broadcast", "answers ok, with every hash",
               b.ok && b.result.value(QStringLiteral("hashes")).toArray().size() == 2);
    }

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
