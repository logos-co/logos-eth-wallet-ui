#pragma once

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

inline QJsonObject parseObject(const QString &reply)
{
    return QJsonDocument::fromJson(reply.toUtf8()).object();
}

inline bool replyOk(const QString &reply)
{
    return parseObject(reply).value(QStringLiteral("ok")).toBool();
}

/// A refusal, worded by the backend. The rule that produced it lives there, so restating it
/// here would be a second copy free to drift.
inline QString replyError(const QString &reply)
{
    const QString e = parseObject(reply).value(QStringLiteral("error")).toString();
    return e.isEmpty() ? QStringLiteral("the wallet backend refused the request") : e;
}

/// A refusal under the heading of the read that produced it.
inline QString refusal(const QString &reply, const QString &context)
{
    return context.isEmpty() ? replyError(reply)
                             : QStringLiteral("%1: %2").arg(context, replyError(reply));
}

/// Re-serialize one member of a reply, so the view receives just the payload.
inline QString member(const QString &reply, const char *key)
{
    const QJsonValue v = parseObject(reply).value(QLatin1String(key));
    if (v.isArray())
        return QString::fromUtf8(QJsonDocument(v.toArray()).toJson(QJsonDocument::Compact));
    if (v.isObject())
        return QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact));
    return {};
}

/// The account and network every scoped value on screen was read under. chainId 0 means the
/// active network could not be read — a selection we do not know, never one we keep answering
/// for out of the previous network's data.
struct Selection {
    QString account;
    int chainId = 0;

    /// Case-folded: the keystore returns EIP-55 checksummed hex, so a re-read differing only
    /// in casing is the same account and must not blank the screen.
    bool operator==(const Selection &o) const
    {
        return chainId == o.chainId && account.compare(o.account, Qt::CaseInsensitive) == 0;
    }
};

inline Selection selectionOf(const QString &account, const QString &networkJson)
{
    Selection s;
    s.account = account;
    s.chainId = parseObject(networkJson).value(QStringLiteral("chainId")).toInt();
    return s;
}

/// The scope a REPLY says it answered for. This is the half a generation counter cannot know:
/// a counter only drops replies for a move the view itself made, while the reply knows what it
/// actually answered — including a move the view has not observed yet.
struct ReplyScope {
    bool namesChain = false;
    bool namesAccount = false;
    int chainId = 0;
    QString account;

    bool names() const { return namesChain || namesAccount; }
    bool agreesWith(const Selection &s) const
    {
        return (!namesChain || chainId == s.chainId)
            && (!namesAccount || account.compare(s.account, Qt::CaseInsensitive) == 0);
    }
};

/// Every scoped read names its account `address`; a quote calls the same thing `from`.
inline ReplyScope replyScope(const QJsonObject &o)
{
    ReplyScope r;
    const QJsonValue chain = o.value(QStringLiteral("chainId"));
    if (chain.isDouble()) {
        r.namesChain = true;
        r.chainId = chain.toInt();
    }
    QJsonValue who = o.value(QStringLiteral("address"));
    if (!who.isString())
        who = o.value(QStringLiteral("from"));
    if (who.isString()) {
        r.namesAccount = true;
        r.account = who.toString();
    }
    return r;
}

/// May this reply be acted on for the selection on screen? One naming another account or chain
/// is not late, it is about something else. A SUCCESSFUL payload naming neither cannot be
/// attributed at all, so it is refused too; a refusal names nothing by design and is this
/// call's own answer.
inline bool answersFor(const QString &reply, const Selection &shown)
{
    const QJsonObject o = parseObject(reply);
    const ReplyScope r = replyScope(o);
    if (!r.agreesWith(shown))
        return false;
    return r.names() || !o.value(QStringLiteral("ok")).toBool();
}

/// Case-folded equality for a hash or an address, with an absent value on EITHER side matching
/// NOTHING. Two empty strings compare equal, which would answer "yes, the same transaction"
/// about two we do not have.
inline bool sameHexValue(const QString &a, const QString &b)
{
    return !a.isEmpty() && !b.isEmpty() && a.compare(b, Qt::CaseInsensitive) == 0;
}

/// Whether a request describes a send at all. An incomplete form is nothing to price rather
/// than an error, and the figures for the previous request are withdrawn by the change of
/// request itself — never by whether this returned true.
inline bool describesASend(const QString &requestJson)
{
    const QJsonObject r = parseObject(requestJson);
    const bool amount = !r.value(QStringLiteral("amountUnits")).toString().trimmed().isEmpty()
        || !r.value(QStringLiteral("amount")).toString().trimmed().isEmpty();
    return amount && !r.value(QStringLiteral("to")).toString().trimmed().isEmpty();
}

/// Every published value that means something only against a particular selection, and the
/// selection it was read under. This list IS the rule: a property that belongs here and is
/// not listed is one free to outlive the account or network it describes.
struct ScopedState {
    Selection at;
    /// Whether the account-scoped values below were read under `at`. The view renders a figure
    /// only while this is true, so nothing stale reaches the screen even in the window before
    /// the re-read lands.
    bool fresh = false;

    // account × chain
    QString balances;
    QString balancesRoute;
    QString history;
    QString blockedChains;
    QString quote = QStringLiteral("{}");
    /// The request the published quote priced. The Send screen renders a figure only while
    /// this still describes the form on screen.
    QString quoteRequest;
    bool quoteStale = false;
    QString sendError;
    /// Extra detail for ONE transaction, and it belongs in this list for the reason the list
    /// exists: the screen it fills is about a transaction of THIS account, on THIS network.
    QString txDetails;

    // chain only — re-read by refresh(), which every chain change runs
    QString tokens;
    QString feeTiers = QStringLiteral("{}");
    /// The verified-proxy verdict names the chain it is about, and drives a blocking banner.
    QString verifiedProxy = QStringLiteral("{}");
};

/// Withdraw the quote and the request it priced, which only ever move together.
inline void withdrawQuote(ScopedState &s)
{
    s.quote = QStringLiteral("{}");
    s.quoteRequest.clear();
    s.quoteStale = false;
}

/// Move the quote to a new request, withdrawing figures priced for the one it replaces: a
/// quote for a request the form no longer describes is not stale, it is about something else.
inline bool enterQuoteRequest(ScopedState &s, const QString &request)
{
    if (s.quoteRequest == request)
        return false;
    withdrawQuote(s);
    return true;
}

/// Move the selection, withdrawing everything that no longer describes it. Empty is UNKNOWN
/// throughout and never "[]", which renders as "none" — an answer about an account nothing has
/// read yet. Returns true when the selection actually moved.
inline bool enterScope(ScopedState &s, const Selection &to)
{
    if (s.at == to)
        return false;
    const bool chainMoved = s.at.chainId != to.chainId;
    s.at = to;
    s.fresh = false;
    s.balances.clear();
    s.balancesRoute.clear();
    s.history.clear();
    s.blockedChains.clear();
    s.txDetails.clear();
    withdrawQuote(s);
    s.sendError.clear();
    if (chainMoved) {
        s.tokens.clear();
        s.feeTiers = QStringLiteral("{}");
        s.verifiedProxy = QStringLiteral("{}");
    }
    return true;
}
