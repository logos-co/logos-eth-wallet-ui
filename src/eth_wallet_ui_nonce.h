#pragma once

#include <algorithm>

#include <QJsonArray>
#include <QJsonObject>
#include <QMap>
#include <QSet>
#include <QString>

#include "eth_wallet_ui_scope.h"

/// How long the lowest waiting nonce may sit before the view calls it stuck.
constexpr qint64 kStuckNonceSecs = 180;

inline bool nonceOf(const QJsonObject &row, qint64 *out)
{
    const QJsonValue v = row.value(QStringLiteral("nonce"));
    bool ok = v.isDouble() && v.toDouble() >= 0;
    if (ok)
        *out = static_cast<qint64>(v.toDouble());
    return ok;
}

inline bool rowMined(const QJsonObject &row)
{
    const QString s = row.value(QStringLiteral("status")).toString();
    return s == QLatin1String("confirmed") || s == QLatin1String("failed");
}

inline bool rowWaiting(const QJsonObject &row)
{
    const QString s = row.value(QStringLiteral("status")).toString();
    return (s == QLatin1String("pending") || s == QLatin1String("unknown"))
           && row.value(QStringLiteral("replaced")).toBool() == false;
}

/// Flags each row the sender settled `replaced`, and each waiting row whose nonce another row on
/// the same chain has mined, for a sender that predates the status: it never will be mined.
inline QJsonArray markReplaced(QJsonArray rows)
{
    QSet<QPair<int, qint64>> mined;
    for (const QJsonValue &v : rows) {
        const QJsonObject r = v.toObject();
        qint64 n = 0;
        if (rowMined(r) && nonceOf(r, &n))
            mined.insert({r.value(QStringLiteral("chainId")).toInt(), n});
    }
    for (int i = 0; i < rows.size(); ++i) {
        QJsonObject r = rows.at(i).toObject();
        qint64 n = 0;
        const bool settled = r.value(QStringLiteral("status")).toString() == QLatin1String("replaced");
        if (settled || (rowWaiting(r) && nonceOf(r, &n)
                        && mined.contains({r.value(QStringLiteral("chainId")).toInt(), n}))) {
            r.insert(QStringLiteral("replaced"), true);
            rows.replace(i, r);
        }
    }
    return rows;
}

/// The same transfer again, from the row's own `meta`; empty for anything but a transfer.
inline QJsonObject transferOf(const QJsonObject &row)
{
    const QJsonObject meta = row.value(QStringLiteral("meta")).toObject();
    const QString kind = meta.value(QStringLiteral("kind")).toString();
    const QString to = meta.value(QStringLiteral("recipient")).toString();
    const QString amount = meta.value(QStringLiteral("amount")).toString();
    const QString token = meta.value(QStringLiteral("token")).toString();
    const bool erc20 = kind == QLatin1String("erc20");
    if ((kind != QLatin1String("native") && !erc20) || to.isEmpty() || amount.isEmpty()
        || (erc20 && token.isEmpty()))
        return {};
    QJsonObject r{{QStringLiteral("to"), to}, {QStringLiteral("amount"), amount}};
    if (erc20)
        r.insert(QStringLiteral("tokenAddress"), token);
    return r;
}

inline bool weiOf(const QJsonValue &v, quint64 *out)
{
    bool ok = false;
    *out = v.toString().toULongLong(&ok, 10);
    return ok;
}

/// The lowest waiting nonce on each chain, when later sends queue behind it or it has stalled.
/// `stranded` is the sender's `strandedNonces`: numbers reserved and never sent.
inline QJsonArray blockedNonces(const QJsonArray &rows, const QJsonArray &stranded, qint64 now)
{
    // Nonces are used in order: at or below the highest mined one, nothing still waits.
    QMap<int, qint64> minedUpTo;
    for (const QJsonValue &v : rows) {
        const QJsonObject r = v.toObject();
        qint64 n = 0;
        if (rowMined(r) && nonceOf(r, &n)) {
            const int c = r.value(QStringLiteral("chainId")).toInt();
            minedUpTo[c] = qMax(minedUpTo.value(c, -1), n);
        }
    }
    QMap<int, QList<QJsonObject>> waiting;
    QMap<int, QSet<qint64>> gaps;
    for (const QJsonValue &v : rows) {
        const QJsonObject r = v.toObject();
        const int c = r.value(QStringLiteral("chainId")).toInt();
        qint64 n = 0;
        if (rowWaiting(r) && nonceOf(r, &n) && n > minedUpTo.value(c, -1))
            waiting[c].append(r);
    }
    for (const QJsonValue &v : stranded) {
        const QJsonObject g = v.toObject();
        const int c = g.value(QStringLiteral("chainId")).toInt();
        qint64 n = 0;
        if (nonceOf(g, &n) && n > minedUpTo.value(c, -1))
            gaps[c].insert(n);
    }

    QSet<int> chains;
    for (auto it = waiting.cbegin(); it != waiting.cend(); ++it)
        chains.insert(it.key());
    for (auto it = gaps.cbegin(); it != gaps.cend(); ++it)
        chains.insert(it.key());
    QList<int> ordered(chains.cbegin(), chains.cend());
    std::sort(ordered.begin(), ordered.end());

    QJsonArray out;
    for (int c : ordered) {
        QSet<qint64> candidates = gaps.value(c);
        for (const QJsonObject &r : waiting.value(c)) {
            qint64 n = 0;
            nonceOf(r, &n);
            candidates.insert(n);
        }
        if (candidates.isEmpty())
            continue;
        const qint64 n0 = *std::min_element(candidates.cbegin(), candidates.cend());

        QList<QJsonObject> at;
        QSet<qint64> later;
        qint64 laterSince = 0;
        for (const QJsonObject &r : waiting.value(c)) {
            qint64 n = 0;
            nonceOf(r, &n);
            const qint64 t = r.value(QStringLiteral("timestamp")).toVariant().toLongLong();
            if (n == n0) {
                at.append(r);
            } else if (n > n0) {
                later.insert(n);
                laterSince = laterSince == 0 ? t : qMin(laterSince, t);
            }
        }
        QJsonObject e{{QStringLiteral("chainId"), c}, {QStringLiteral("nonce"), n0},
                      {QStringLiteral("behind"), later.size()}};

        // A gap is only evidence once a later send has waited on it.
        if (at.isEmpty()) {
            if (later.isEmpty() || now - laterSince < kStuckNonceSecs)
                continue;
            e.insert(QStringLiteral("why"), QStringLiteral("stranded"));
            e.insert(QStringLiteral("since"), laterSince);
            out.append(e);
            continue;
        }

        // The latest attempt at n0 decides; every attempt sets the fee floor.
        QJsonObject newest = at.first();
        quint64 floorFee = 0, floorTip = 0;
        bool feesKnown = true;
        for (const QJsonObject &r : at) {
            if (r.value(QStringLiteral("timestamp")).toVariant().toLongLong()
                > newest.value(QStringLiteral("timestamp")).toVariant().toLongLong())
                newest = r;
            quint64 fee = 0, tip = 0;
            feesKnown = feesKnown && weiOf(r.value(QStringLiteral("maxFeePerGas")), &fee)
                        && weiOf(r.value(QStringLiteral("maxPriorityFeePerGas")), &tip);
            floorFee = qMax(floorFee, fee);
            floorTip = qMax(floorTip, tip);
        }
        const qint64 since = newest.value(QStringLiteral("timestamp")).toVariant().toLongLong();
        const bool stalled = newest.value(QStringLiteral("stalled")).toBool();
        if (now - since < kStuckNonceSecs || (later.isEmpty() && !stalled))
            continue;
        const bool unknown = newest.value(QStringLiteral("status")).toString() == QLatin1String("unknown");
        e.insert(QStringLiteral("why"), unknown ? QStringLiteral("unresolved")
                                        : stalled ? QStringLiteral("stalled") : QStringLiteral("pending"));
        e.insert(QStringLiteral("since"), since);
        for (const char *k : {"hash", "label", "origin"}) {
            const QString s = newest.value(QLatin1String(k)).toString();
            if (!s.isEmpty())
                e.insert(QLatin1String(k), s);
        }
        QJsonObject resend = transferOf(newest);
        if (!resend.isEmpty() && feesKnown) {
            resend.insert(QStringLiteral("chainId"), c);
            resend.insert(QStringLiteral("from"), newest.value(QStringLiteral("from")).toString());
            resend.insert(QStringLiteral("nonce"), n0);
            e.insert(QStringLiteral("resend"), resend);
            e.insert(QStringLiteral("floorMaxFeePerGas"), QString::number(floorFee));
            e.insert(QStringLiteral("floorMaxPriorityFeePerGas"), QString::number(floorTip));
        }
        out.append(e);
    }
    return out;
}

struct ReplacementFees {
    QString maxFeePerGas;
    QString maxPriorityFeePerGas;
    QString error;
};

/// The tier's fees, raised where needed past what nodes demand of a replacement: more than
/// the transaction it replaces, and at least 10% more, on both fields.
inline ReplacementFees replacementFees(const QJsonObject &tier, const QString &floorFee,
                                       const QString &floorTip)
{
    quint64 fee = 0, tip = 0, oldFee = 0, oldTip = 0;
    if (!weiOf(tier.value(QStringLiteral("maxFeePerGas")), &fee)
        || !weiOf(tier.value(QStringLiteral("maxPriorityFeePerGas")), &tip))
        return {{}, {}, QStringLiteral("no current fee to price it with")};
    if (!weiOf(floorFee, &oldFee) || !weiOf(floorTip, &oldTip))
        return {{}, {}, QStringLiteral("the fees of the transaction it replaces are unreadable")};
    constexpr quint64 kMaxBumpable = 1000000000000000000ULL;  // 10^9 gwei per gas
    if (oldFee > kMaxBumpable || oldTip > kMaxBumpable)
        return {{}, {}, QStringLiteral("the fees of the transaction it replaces are out of range")};
    const auto bump = [](quint64 x) { return x + x / 10 + 1; };
    tip = qMax(tip, bump(oldTip));
    fee = qMax(qMax(fee, bump(oldFee)), tip);
    return {QString::number(fee), QString::number(tip), {}};
}

/// The send request for a blocked entry, priced; empty when the entry has nothing to resend.
inline QJsonObject resendRequest(const QJsonObject &blocked, const ReplacementFees &fees)
{
    QJsonObject r = blocked.value(QStringLiteral("resend")).toObject();
    if (r.isEmpty() || !fees.error.isEmpty())
        return {};
    r.insert(QStringLiteral("maxFeePerGas"), fees.maxFeePerGas);
    r.insert(QStringLiteral("maxPriorityFeePerGas"), fees.maxPriorityFeePerGas);
    return r;
}
