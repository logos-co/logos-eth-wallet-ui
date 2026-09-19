// Which nonce holds up an account's later sends, and the resend that releases it: rows another
// transaction at their nonce has mined read `replaced`, and a resend is priced past what a node
// demands of a replacement. The first rows are the ones a zero-tip send left on mainnet.
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) test_blocked_nonce.cpp -o /tmp/t && /tmp/t
#include <cstdio>
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif
#include <QJsonDocument>

#include "eth_wallet_ui_nonce.h"

namespace {
int failures = 0;

void expect(const char *label, const char *claim, bool got)
{
    if (!got) ++failures;
    std::printf("  %s  %-58s %s\n", got ? "PASS" : "FAIL", label, claim);
}

const char *ME = "0xa1e277ea6b97effc5b61b3bf5de03f438981247e";
const char *PAYEE = "0x0ADB6CaA256A5375C638C00e2fF80A9Ac1b2d3A7";
const char *USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const qint64 NOW = 1789825000;

QJsonObject row(int chain, qint64 nonce, const char *status, qint64 ts, const char *fee = "1000",
                const char *tip = "100", const char *hash = "0xh")
{
    return QJsonObject{{"chainId", chain}, {"nonce", nonce}, {"status", status}, {"timestamp", ts},
                       {"from", ME}, {"hash", hash}, {"label", "Send ETH"}, {"origin", "eth_wallet_backend"},
                       {"maxFeePerGas", fee}, {"maxPriorityFeePerGas", tip},
                       {"meta", QJsonObject{{"kind", "native"}, {"recipient", PAYEE}, {"amount", "100000000000"}}}};
}

QJsonObject with(QJsonObject o, const char *key, const QJsonValue &v)
{
    o.insert(QLatin1String(key), v);
    return o;
}

QJsonArray gap(int chain, qint64 nonce) { return {QJsonObject{{"chainId", chain}, {"nonce", nonce}}}; }

QJsonObject only(const QJsonArray &a) { return a.size() == 1 ? a.at(0).toObject() : QJsonObject{}; }

QString s(const QJsonValue &v) { return v.isString() ? v.toString() : QString::number(v.toDouble(), 'f', 0); }

// The replacement rule geth, reth, nethermind and erigon share at their default 10% bump.
bool nodeTakesIt(quint64 oldFee, quint64 oldTip, const ReplacementFees &f)
{
    const quint64 fee = f.maxFeePerGas.toULongLong(), tip = f.maxPriorityFeePerGas.toULongLong();
    return fee > oldFee && tip > oldTip && fee >= oldFee * 110 / 100 && tip >= oldTip * 110 / 100
           && tip <= fee;
}

QJsonObject tier(const char *fee, const char *tip)
{
    return QJsonObject{{"maxFeePerGas", fee}, {"maxPriorityFeePerGas", tip}};
}

// Mainnet, 2026-09: nonce 40 went out with a zero tip, 41 queued behind it for two days.
const QJsonObject ZERO_TIP = with(row(1, 40, "pending", 1789669762, "338658463", "0",
                                      "0x2659f4eaf0c6913674c16f1c7453daef9a44b74722aac59f45da62890340b9cc"),
                                  "stalled", true);
const QJsonObject QUEUED = row(1, 41, "pending", 1789824627, "486624394", "50000000",
                               "0x6ad122dd58f825738853bc345bae340e21b0ab005e0dc8b1370d34126ae2102e");
const QJsonObject CONFIRMED_39 = row(1, 39, "confirmed", 1789669648, "336108902", "1000000");
}

int main()
{
    std::printf("\nthe zero-tip send that held up the next one\n");
    {
        const QJsonObject b = only(blockedNonces({CONFIRMED_39, ZERO_TIP, QUEUED}, {}, NOW));
        expect("blocker", "nonce 40 on chain 1 is named", b.value("nonce").toInt() == 40 && b.value("chainId").toInt() == 1);
        expect("behind", "with the one send waiting behind it", b.value("behind").toInt() == 1);
        expect("why", "it stalled: the sender stopped asking", b.value("why").toString() == "stalled");
        expect("since", "since it was broadcast", s(b.value("since")) == "1789669762");
        const QJsonObject r = b.value("resend").toObject();
        expect("resend", "the same transfer, at the same nonce",
               r.value("to").toString() == PAYEE && r.value("amount").toString() == "100000000000"
                   && r.value("nonce").toInt() == 40 && r.value("chainId").toInt() == 1
                   && r.value("from").toString() == ME && !r.contains("tokenAddress"));
        expect("floor", "the fee floor is what nonce 40 carried",
               b.value("floorMaxFeePerGas").toString() == "338658463"
                   && b.value("floorMaxPriorityFeePerGas").toString() == "0");

        // The user's own resend carried 336953631 / 37979581: a lower max fee than the original.
        const ReplacementFees f = replacementFees(tier("336953631", "37979581"), "338658463", "0");
        expect("priced", "the max fee rises past the original's by 10%",
               f.error.isEmpty() && f.maxFeePerGas == "372524310" && f.maxPriorityFeePerGas == "37979581");
        expect("accepted", "a node still holding nonce 40 takes the replacement", nodeTakesIt(338658463, 0, f));
        const QJsonObject req = resendRequest(b, f);
        expect("request", "the request carries both fees and the pinned nonce",
               req.value("maxFeePerGas").toString() == "372524310"
                   && req.value("maxPriorityFeePerGas").toString() == "37979581" && req.value("nonce").toInt() == 40);
    }

    std::printf("\nonce another transaction at that nonce has mined\n");
    {
        const QJsonObject resent = row(1, 40, "confirmed", 1789825816, "336953631", "37979581", "0x2148");
        const QJsonArray rows = markReplaced({CONFIRMED_39, ZERO_TIP, resent, with(QUEUED, "status", "confirmed")});
        expect("replaced", "the zero-tip row reads replaced", rows.at(1).toObject().value("replaced").toBool());
        expect("kept", "the mined rows are untouched",
               !rows.at(0).toObject().contains("replaced") && !rows.at(2).toObject().contains("replaced")
                   && !rows.at(3).toObject().contains("replaced"));
        expect("released", "nothing is blocked any more", blockedNonces(rows, {}, NOW + 60).isEmpty());
        const QJsonArray other = markReplaced({ZERO_TIP, with(resent, "chainId", 10)});
        expect("per chain", "a nonce mined on another chain replaces nothing",
               !other.at(0).toObject().contains("replaced"));
        const QJsonArray lost = markReplaced({with(ZERO_TIP, "status", "unknown"), resent});
        expect("unknown", "an unresolved row at a mined nonce is replaced too",
               lost.at(0).toObject().value("replaced").toBool());
        // What the sender settles itself, including a nonce another wallet's transaction took.
        const QJsonArray sender = markReplaced({with(ZERO_TIP, "status", "replaced")});
        expect("sender", "a row the sender settled replaced reads replaced with no sibling in view",
               sender.at(0).toObject().value("replaced").toBool());
        expect("sender", "...and holds nothing up",
               blockedNonces(sender, {}, NOW + 60).isEmpty() && !rowWaiting(sender.at(0).toObject()));
    }

    std::printf("\nwhat is not called stuck\n");
    {
        expect("young", "40 waiting for 60 s is just slow",
               blockedNonces({row(1, 40, "pending", NOW - 60), row(1, 41, "pending", NOW - 30)}, {}, NOW).isEmpty());
        expect("alone", "a lone pending row that has not stalled holds up nothing",
               blockedNonces({row(1, 40, "pending", NOW - 1200)}, {}, NOW).isEmpty());
        expect("below mined", "a row below a mined nonce has been used, one way or another",
               blockedNonces({with(row(1, 38, "pending", NOW - 7200), "stalled", true), CONFIRMED_39}, {}, NOW).isEmpty());
        expect("empty", "no rows, nothing blocked", blockedNonces({}, {}, NOW).isEmpty());
    }

    std::printf("\nwhat is\n");
    {
        const QJsonObject p = only(blockedNonces({row(1, 40, "pending", NOW - 200), row(1, 41, "pending", NOW - 100),
                                                  row(1, 42, "pending", NOW - 90)}, {}, NOW));
        expect("pending", "40 pending 200 s with two later sends behind it",
               p.value("why").toString() == "pending" && p.value("behind").toInt() == 2);
        const QJsonObject lone = only(blockedNonces({ZERO_TIP}, {}, NOW));
        expect("stalled", "a lone stalled row is named, with nothing behind it",
               lone.value("why").toString() == "stalled" && lone.value("behind").toInt() == 0);
        const QJsonObject u = only(blockedNonces({with(row(1, 40, "unknown", NOW - 300), "unresolved", true),
                                                  row(1, 41, "pending", NOW - 250)}, {}, NOW));
        expect("unresolved", "an outcome that never came back, with a send behind it",
               u.value("why").toString() == "unresolved" && u.contains("resend"));
    }

    std::printf("\na number reserved and never sent\n");
    {
        const QJsonObject g = only(blockedNonces({row(1, 41, "pending", NOW - 200)}, gap(1, 40), NOW));
        expect("stranded", "the gap at 40 is named", g.value("nonce").toInt() == 40 && g.value("why").toString() == "stranded");
        expect("since", "since the first send that waited on it", s(g.value("since")) == QString::number(NOW - 200));
        expect("no resend", "there is nothing to resend", !g.contains("resend"));
        expect("young gap", "a gap only counts once a send has waited 3 minutes on it",
               blockedNonces({row(1, 41, "pending", NOW - 100)}, gap(1, 40), NOW).isEmpty());
        expect("used gap", "a stranded number the chain has used is no gap",
               blockedNonces({row(1, 40, "confirmed", NOW - 900), row(1, 41, "pending", NOW - 200)}, gap(1, 40), NOW)
                   .isEmpty());
        expect("lone gap", "a gap with nothing behind it is not evidence", blockedNonces({}, gap(1, 40), NOW).isEmpty());
    }

    std::printf("\nwhat can be resent\n");
    {
        QJsonObject swap = row(1, 40, "pending", NOW - 400);
        // A recipient and an amount of its own: only the kind keeps it from being resent as a transfer.
        swap.insert("meta", QJsonObject{{"kind", "swap"}, {"recipient", PAYEE}, {"amount", "5"}});
        swap.insert("label", "Swap");
        swap.insert("origin", "uniswap_backend");
        const QJsonObject c = only(blockedNonces({swap, row(1, 41, "pending", NOW - 300)}, {}, NOW));
        expect("call", "another app's call is named, and not resent",
               c.value("nonce").toInt() == 40 && !c.contains("resend") && c.value("origin").toString() == "uniswap_backend");
        QJsonObject usdc = row(1, 40, "pending", NOW - 400);
        usdc.insert("meta", QJsonObject{{"kind", "erc20"}, {"recipient", PAYEE}, {"amount", "2500000"},
                                        {"token", USDC}, {"tokenDecimals", 6}});
        const QJsonObject e = only(blockedNonces({usdc, row(1, 41, "pending", NOW - 300)}, {}, NOW))
                                  .value("resend").toObject();
        expect("erc20", "a token transfer resends the token amount to the recipient",
               e.value("tokenAddress").toString() == USDC && e.value("to").toString() == PAYEE
                   && e.value("amount").toString() == "2500000");
        QJsonObject blind = row(1, 40, "pending", NOW - 400);
        blind.remove("maxFeePerGas");
        expect("unpriced", "a row whose fees are unreadable is not resent: its floor is unknown",
               !only(blockedNonces({blind, row(1, 41, "pending", NOW - 300)}, {}, NOW)).contains("resend"));
    }

    std::printf("\na second attempt at the same nonce\n");
    {
        const QJsonObject first = with(row(1, 40, "pending", NOW - 7200, "900", "0"), "stalled", true);
        const QJsonObject second = row(1, 40, "pending", NOW - 400, "700", "50");
        const QJsonObject b = only(blockedNonces({first, second, row(1, 41, "pending", NOW - 300)}, {}, NOW));
        expect("newest", "the latest attempt decides: pending, not stalled", b.value("why").toString() == "pending");
        expect("floor", "the floor takes the higher of each field across attempts",
               b.value("floorMaxFeePerGas").toString() == "900" && b.value("floorMaxPriorityFeePerGas").toString() == "50");
    }

    std::printf("\nper chain\n");
    {
        const QJsonArray a = blockedNonces({ZERO_TIP, QUEUED, row(11155111, 7, "pending", NOW - 20),
                                            row(11155111, 8, "pending", NOW - 10)}, {}, NOW);
        expect("chains", "only the chain that is stuck is named",
               a.size() == 1 && a.at(0).toObject().value("chainId").toInt() == 1);
        const QJsonArray both = blockedNonces({ZERO_TIP, QUEUED, row(11155111, 7, "pending", NOW - 900),
                                               row(11155111, 8, "pending", NOW - 800)}, {}, NOW);
        expect("ordered", "two stuck chains, in chain order",
               both.size() == 2 && both.at(0).toObject().value("chainId").toInt() == 1
                   && both.at(1).toObject().value("chainId").toInt() == 11155111);
    }

    std::printf("\nreplacement fees\n");
    {
        const ReplacementFees high = replacementFees(tier("1000", "100"), "500", "50");
        expect("market", "a market above the floor is used as it is",
               high.maxFeePerGas == "1000" && high.maxPriorityFeePerGas == "100");
        const ReplacementFees tipFloor = replacementFees(tier("1000", "10"), "100", "2000");
        expect("tip floor", "a tip floor above the market fee lifts the fee with it",
               tipFloor.maxPriorityFeePerGas == "2201" && tipFloor.maxFeePerGas == "2201");
        const ReplacementFees tiny = replacementFees(tier("0", "0"), "0", "0");
        expect("zero", "nothing to beat still means strictly more", tiny.maxFeePerGas == "1" && tiny.maxPriorityFeePerGas == "1");
        bool all = true;
        const quint64 olds[] = {0, 1, 9, 10, 11, 99, 100, 101, 999999, 338658463, 50000000000ULL};
        const char *tiers[][2] = {{"0", "0"}, {"1", "1"}, {"372524309", "0"}, {"100000000000", "2000000000"}};
        for (quint64 of : olds)
            for (quint64 ot : olds)
                for (const auto &t : tiers) {
                    const ReplacementFees f = replacementFees(tier(t[0], t[1]), QString::number(of), QString::number(ot));
                    all = all && f.error.isEmpty() && nodeTakesIt(of, ot, f)
                          && f.maxFeePerGas.toULongLong() >= QString(t[0]).toULongLong()
                          && f.maxPriorityFeePerGas.toULongLong() >= QString(t[1]).toULongLong();
                }
        expect("rule", "every floor x market pair clears the node's rule, never below market", all);
        expect("no market", "no current fee refuses", !replacementFees({}, "1", "1").error.isEmpty());
        expect("bad floor", "an unreadable floor refuses", !replacementFees(tier("1", "1"), "x", "1").error.isEmpty());
        expect("huge floor", "a floor past any real fee refuses",
               !replacementFees(tier("1", "1"), "2000000000000000000", "1").error.isEmpty());
        expect("unresendable", "an entry with nothing to resend builds no request",
               resendRequest(QJsonObject{{"nonce", 40}}, high).isEmpty());
        expect("unpriced", "a refused price builds no request",
               resendRequest(only(blockedNonces({ZERO_TIP, QUEUED}, {}, NOW)), replacementFees({}, "1", "1")).isEmpty());
    }

    std::printf("\nRESULT: %s\n", failures ? "FAILURES" : "ALL PASS");
    return failures ? 1 : 0;
}
