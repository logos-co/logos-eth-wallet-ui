#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QList>
#include <QStringList>

#include "eth_wallet_ui_scope.h"

// Another app's request to send transactions from this wallet — `evm.transactions.send` —
// checked and reshaped here, as pure functions doctests/test_intent_send.cpp runs. The app
// hands over calls and a purpose; it never sees a key, and it is answered only once the send
// has settled, with every hash or with why not.

/// The most calls one request may carry: the sender's own bundle limit.
constexpr int kMaxIntentCalls = 8;
constexpr int kMaxIntentPurposeChars = 256;

struct IntentSendChecked {
    bool ok = false;
    /// `bad_request` for a payload that cannot be fixed by retrying it unchanged; `busy` for
    /// a wallet already sending; empty on success.
    QString error;
    /// Why, in words the app's author can act on. Empty on success.
    QString detail;
    /// What the review dialog shows: `{ requestId, requester, chainId, from, purpose, calls }`.
    QJsonObject review;
    /// What tx_sender_module is handed on acceptance: `{ chainId, from, purpose, calls, tier }`.
    QJsonObject senderRequest;
};

inline bool looksLikeAddress(const QString &s)
{
    if (s.size() != 42 || !s.startsWith(QLatin1String("0x"), Qt::CaseInsensitive))
        return false;
    for (int i = 2; i < s.size(); ++i) {
        const QChar c = s.at(i);
        if (!((c >= QLatin1Char('0') && c <= QLatin1Char('9')) || (c >= QLatin1Char('a') && c <= QLatin1Char('f'))
              || (c >= QLatin1Char('A') && c <= QLatin1Char('F'))))
            return false;
    }
    return true;
}

/// Check a request against the wallet as it stands. `shown` supplies the default account and
/// UI-local chain cursor, `allowedChains` is eth_rpc's enabled in-scope set, `accounts` the
/// keystore roster, and `sending` whether a send is already awaiting a human.
inline IntentSendChecked checkIntentSend(const QString &requestJson, const Selection &shown,
                                         const QStringList &accounts,
                                         const QList<int> &allowedChains, bool sending)
{
    IntentSendChecked out;
    const QJsonObject r = parseObject(requestJson);
    const QString requestId = r.value(QStringLiteral("requestId")).toString();
    const QString requester = r.value(QStringLiteral("requester")).toString();
    const QJsonObject p = r.value(QStringLiteral("params")).toObject();
    auto refuse = [&](const QString &code, const QString &why) {
        out.error = code;
        out.detail = why;
        return out;
    };
    if (requestId.isEmpty())
        return refuse(QStringLiteral("bad_request"), QStringLiteral("no request id"));
    if (sending)
        return refuse(QStringLiteral("busy"), QStringLiteral("the wallet is already waiting on a send"));
    if (shown.chainId == 0 || shown.account.isEmpty())
        return refuse(QStringLiteral("busy"), QStringLiteral("the wallet has no account or network selected"));

    const QJsonValue chainV = p.value(QStringLiteral("chainId"));
    int chainId = shown.chainId;
    if (!chainV.isUndefined() && !chainV.isNull()) {
        if (!chainV.isDouble() || chainV.toDouble() != chainV.toInt())
            return refuse(QStringLiteral("bad_request"), QStringLiteral("chainId must be an integer"));
        chainId = chainV.toInt();
    }
    if (chainId <= 0 || !allowedChains.contains(chainId))
        return refuse(QStringLiteral("bad_request"),
                      QStringLiteral("chain %1 is not enabled and in scope").arg(chainId));
    QString from = p.value(QStringLiteral("from")).toString().trimmed();
    if (from.isEmpty()) {
        from = shown.account;
    } else {
        const bool held = std::any_of(accounts.begin(), accounts.end(), [&](const QString &a) {
            return a.compare(from, Qt::CaseInsensitive) == 0;
        });
        if (!held)
            return refuse(QStringLiteral("bad_request"), QStringLiteral("this wallet holds no account %1").arg(from));
    }
    const QString purpose = p.value(QStringLiteral("purpose")).toString().trimmed();
    if (purpose.isEmpty())
        return refuse(QStringLiteral("bad_request"), QStringLiteral("a purpose is required: the human reads it"));
    if (purpose.size() > kMaxIntentPurposeChars)
        return refuse(QStringLiteral("bad_request"), QStringLiteral("the purpose is longer than %1 characters").arg(kMaxIntentPurposeChars));
    const QJsonArray calls = p.value(QStringLiteral("calls")).toArray();
    if (calls.isEmpty())
        return refuse(QStringLiteral("bad_request"), QStringLiteral("no calls"));
    if (calls.size() > kMaxIntentCalls)
        return refuse(QStringLiteral("bad_request"), QStringLiteral("more than %1 calls").arg(kMaxIntentCalls));
    QJsonArray cleaned;
    for (int i = 0; i < calls.size(); ++i) {
        const QJsonObject c = calls.at(i).toObject();
        const QString to = c.value(QStringLiteral("to")).toString().trimmed();
        if (!looksLikeAddress(to))
            return refuse(QStringLiteral("bad_request"), QStringLiteral("call %1 has no `to` address").arg(i + 1));
        const QString data = c.value(QStringLiteral("data")).toString().trimmed();
        if (!data.isEmpty() && (!data.startsWith(QLatin1String("0x")) || data.size() % 2 != 0))
            return refuse(QStringLiteral("bad_request"), QStringLiteral("call %1 has calldata that is not 0x-hex").arg(i + 1));
        QJsonObject k{{QStringLiteral("to"), to}};
        const QString value = c.value(QStringLiteral("value")).toVariant().toString().trimmed();
        if (!value.isEmpty())
            k.insert(QStringLiteral("value"), value);
        if (!data.isEmpty())
            k.insert(QStringLiteral("data"), data);
        const QString gas = c.value(QStringLiteral("gasLimit")).toVariant().toString().trimmed();
        if (!gas.isEmpty())
            k.insert(QStringLiteral("gasLimit"), gas);
        const QString label = c.value(QStringLiteral("label")).toString().trimmed();
        k.insert(QStringLiteral("label"), label.isEmpty() ? QStringLiteral("Call %1").arg(i + 1) : label.left(120));
        // The requester's own metadata rides along, stamped with who asked so the row can be
        // told apart from the wallet's own later — the sender's `origin` attests the same.
        QJsonObject meta = c.value(QStringLiteral("meta")).toObject();
        meta.insert(QStringLiteral("app"), requester);
        meta.insert(QStringLiteral("intent"), QStringLiteral("evm.transactions.send"));
        k.insert(QStringLiteral("meta"), meta);
        cleaned.append(k);
    }
    QString tier = p.value(QStringLiteral("tier")).toString().trimmed();
    if (tier.isEmpty())
        tier = QStringLiteral("normal");
    if (tier != QLatin1String("slow") && tier != QLatin1String("normal") && tier != QLatin1String("fast"))
        return refuse(QStringLiteral("bad_request"), QStringLiteral("tier must be slow, normal or fast"));

    out.ok = true;
    out.review = QJsonObject{
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("requester"), requester},
        {QStringLiteral("chainId"), chainId},
        {QStringLiteral("from"), from},
        {QStringLiteral("purpose"), purpose},
        {QStringLiteral("tier"), tier},
        {QStringLiteral("calls"), cleaned},
    };
    out.senderRequest = QJsonObject{
        {QStringLiteral("chainId"), chainId},
        {QStringLiteral("from"), from},
        {QStringLiteral("purpose"), purpose},
        {QStringLiteral("calls"), cleaned},
        {QStringLiteral("tier"), tier},
    };
    return out;
}

// Compatibility overload for focused callers that model only the cursor chain. Production
// passes eth_rpc's complete in-scope set through the overload above.
inline IntentSendChecked checkIntentSend(const QString &requestJson, const Selection &shown,
                                         const QStringList &accounts, bool sending)
{
    return checkIntentSend(requestJson, shown, accounts, QList<int>{shown.chainId}, sending);
}

/// The answer to the requester once the send has settled, from the wallet's own outcome
/// record. `ok` only for a broadcast; every other status is the error, in the sender's word.
struct IntentAnswer {
    bool ok = false;
    QJsonObject result;
    QString error;
};

inline IntentAnswer answerFromOutcome(const QString &lastSendOutcomeJson, const QString &sendRequestId)
{
    IntentAnswer a;
    const QJsonObject o = parseObject(lastSendOutcomeJson);
    const QString status = o.value(QStringLiteral("status")).toString();
    if (status.isEmpty())
        return a;
    a.result = QJsonObject{{QStringLiteral("status"), status}, {QStringLiteral("requestId"), sendRequestId}};
    if (o.contains(QStringLiteral("hash")))
        a.result.insert(QStringLiteral("hash"), o.value(QStringLiteral("hash")));
    if (o.contains(QStringLiteral("hashes")))
        a.result.insert(QStringLiteral("hashes"), o.value(QStringLiteral("hashes")));
    if (status == QLatin1String("broadcast")) {
        a.ok = true;
        return a;
    }
    a.error = status;
    const QString reason = o.value(QStringLiteral("reason")).toString();
    if (!reason.isEmpty())
        a.result.insert(QStringLiteral("reason"), reason);
    return a;
}
