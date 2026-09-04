#pragma once

#include "eth_wallet_ui_scope.h"
#include "eth_wallet_ui_sweep.h"

// Every guard deciding whether a reply reaches the screen lives here, INSIDE the transition it
// guards, as a pure function over ScopedState. The backend snapshots, calls one of these, and
// publishes: it holds no rule of its own, so a guard cannot be neutered at a call site that no
// longer has one. doctests/test_apply.cpp is the table that runs them.

/// What a reply did, and what the user must be told. `error` is the backend's own wording and
/// is empty unless the read failed.
struct Applied {
    bool acted = false;
    QString error;
};

/// The verdict to publish once the backend has stopped answering. It mirrors the shape
/// eth_wallet_backend emits for an unreadable verdict, and cannot be sourced from there for
/// the obvious reason. Unknown is not "off": it blocks.
inline QString unknownVerdict(int chainId, const QString &why)
{
    const QJsonObject v{
        {QStringLiteral("ok"), false},
        {QStringLiteral("error"), why},
        {QStringLiteral("chainId"), chainId},
        {QStringLiteral("mode"), QStringLiteral("unknown")},
        {QStringLiteral("state"), QStringLiteral("unhealthy")},
        {QStringLiteral("usable"), false},
        {QStringLiteral("blocking"), true},
        {QStringLiteral("message"), QStringLiteral("The verified-proxy state could not be read.")},
        {QStringLiteral("action"), QStringLiteral("restart_or_reload")},
        {QStringLiteral("detail"), why},
    };
    return QString::fromUtf8(QJsonDocument(v).toJson(QJsonDocument::Compact));
}

/// Balances. The reply names the account and chain it read, so one naming another selection is
/// not late — it is about something else. Dropped whole: it may not stamp freshness either.
inline Applied applyBalances(ScopedState &s, const QString &reply)
{
    if (!answersFor(reply, s.at))
        return {};
    const bool ok = replyOk(reply);
    // On failure the figures stay EMPTY rather than keeping the previous network's numbers, and
    // the route label says nothing, which the chip must not render as verified.
    s.balances = ok ? member(reply, "balances") : QString();
    s.balancesRoute = ok ? parseObject(reply).value(QStringLiteral("route")).toString() : QString();
    // What is on screen was read under `at`. Stamping that is what lets the view render at all.
    s.fresh = true;
    return {true, ok ? QString() : refusal(reply, QStringLiteral("balances"))};
}

/// History, and the sweep schedule the same reply carries.
struct HistoryApplied {
    bool acted = false;
    SweepVerdict sweep = SweepVerdict::Unchanged;
};

inline HistoryApplied applyHistory(ScopedState &s, const QString &reply)
{
    // As applyBalances: a reply answering for another selection says nothing here — not about
    // the rows, and not about the sweep schedule.
    if (!answersFor(reply, s.at))
        return {};
    HistoryApplied out{true, sweepVerdict(reply)};
    if (!replyOk(reply)) {
        // UNKNOWN, not "[]": an empty list renders as "No transactions yet", which is an answer
        // a read that FAILED may not give.
        s.history.clear();
        return out;
    }
    s.history = member(reply, "transactions");
    const QString blocked = member(reply, "blockedChains");
    s.blockedChains = blocked.isEmpty() ? QStringLiteral("[]") : blocked;
    return out;
}

/// Fee tiers. fee_module names the chain it priced, and fees read for another network are wrong
/// under this one's name rather than stale. The whole reply is published: the view shows
/// `source`, so the user can see a legacy gasPrice fallback.
inline void applyFeeTiers(ScopedState &s, const QString &reply)
{
    s.feeTiers = (replyOk(reply) && answersFor(reply, s.at)) ? reply : QStringLiteral("{}");
}

/// The token list. One we could not read is UNKNOWN, not the previous network's: keeping it
/// would show another chain's symbols and contract addresses under this one's name.
inline Applied applyTokens(ScopedState &s, const QString &reply)
{
    const bool ok = replyOk(reply);
    s.tokens = (ok && answersFor(reply, s.at)) ? member(reply, "tokens") : QString();
    return {ok, ok ? QString() : refusal(reply, QStringLiteral("tokens"))};
}

/// The persisted token order a reply carries. `get_balances`, `list_tokens` and the catalogue
/// search all echo it, so the order the user chose is restored by whichever lands first rather
/// than only by a search on a screen they may never open.
///
/// `issuedAt` is the choice counter the read went out under, `chosenAt` the current one. A
/// reply in flight ACROSS a choice carries the order the user just replaced, and publishing it
/// would put the menu back under their hand. Empty leaves the published order alone.
inline QString adoptedTokenSort(const QString &reply, quint64 issuedAt, quint64 chosenAt)
{
    if (issuedAt != chosenAt)
        return {};
    const QString order = parseObject(reply).value(QStringLiteral("tokenSort")).toString();
    // Only the two orders this build knows. An order it does not is left unpublished rather
    // than shown as a label nothing in the menu can match.
    return (order == QLatin1String("alpha") || order == QLatin1String("balance")) ? order
                                                                                  : QString();
}

/// Nothing to read: what is on screen — nothing — does describe this selection, so it is
/// stamped fresh. Without that the view spins forever on a wallet with no account.
inline void applyNoAccount(ScopedState &s)
{
    s.balances.clear();
    s.balancesRoute.clear();
    s.history = QStringLiteral("[]");
    s.blockedChains = QStringLiteral("[]");
    s.fresh = true;
}

/// One quote reply, against the request it priced. `interactive` is a user edit, whose failure
/// is the user's to read; a timer tick's failure only marks the figure stale, because
/// withdrawing a figure under a dialog nobody touched reads as the wallet breaking.
inline void applyQuote(ScopedState &s, const QString &reply, const QString &priced,
                       bool interactive)
{
    // The quote names its chain and account; the request it priced is stamped beside it,
    // because the wire echoes no request of its own.
    if (replyOk(reply) && answersFor(reply, s.at)) {
        s.quote = reply;
        s.quoteRequest = priced;
        s.quoteStale = false;
    } else if (replyOk(reply)) {
        withdrawQuote(s);
    } else if (interactive) {
        // Insufficient funds and a priority fee above the max fee both land here, worded by the
        // backend. The view adds no rule of its own.
        withdrawQuote(s);
        s.sendError = replyError(reply);
    } else {
        // A timer tick. `send` re-quotes internally before requesting approval, so a briefly
        // stale DISPLAYED figure cannot mis-price a signature.
        s.quoteStale = true;
    }
}

/// A transport failure arrives EMPTY, and the backend cannot word a refusal it never sent. So
/// this one is authored here — the same reason unknownVerdict above exists — and it names the
/// transaction, because the message renders beside that transaction's own rows.
inline QString detailsUnavailable(const QString &hash)
{
    const QJsonObject v{
        {QStringLiteral("ok"), false},
        {QStringLiteral("hash"), hash},
        {QStringLiteral("error"), QStringLiteral("the wallet backend did not answer")},
    };
    return QString::fromUtf8(QJsonDocument(v).toJson(QJsonDocument::Compact));
}

/// One transaction's extra detail, against the hash the fetch was made for.
///
/// THE DEFECT THIS EXISTS FOR: open transaction A, fetch, go back, open B — and B must not show
/// A's mined time. The reply carries the hash it is about, so a late one is not stale, it is
/// about something else, exactly as a reply for another account is. A partial answer is still
/// an answer and is published whole; so is a refusal, which is what the fee card renders.
inline bool applyTxDetails(ScopedState &s, const QString &reply, const QString &forHash)
{
    const QString r = parseObject(reply).contains(QStringLiteral("hash"))
        ? reply
        : detailsUnavailable(forHash);
    if (!sameHexValue(parseObject(r).value(QStringLiteral("hash")).toString(), forHash))
        return false;
    if (!answersFor(r, s.at))
        return false;
    s.txDetails = r;
    return true;
}

/// What a verified-proxy reply leaves behind: the new silence count, and whether the verdict
/// poll keeps running.
struct VerdictApplied {
    int silent = 0;
    bool poll = true;
};

/// A transport failure arrives empty, and a verdict naming a chain we are not showing has told
/// us nothing about the one we are: both are silence. One blip keeps the last verdict, but a
/// backend answering nothing must not hold "ready" up while nothing is being verified.
inline VerdictApplied applyVerdict(ScopedState &s, const QString &reply, int silent,
                                   int maxSilent)
{
    QString publish = reply;
    if (!parseObject(publish).contains(QStringLiteral("mode")) || !answersFor(publish, s.at)) {
        if (++silent < maxSilent)
            return {silent, true};
        publish = unknownVerdict(s.at.chainId,
                                 QStringLiteral("the wallet backend stopped answering"));
    } else {
        silent = 0;
    }

    const QJsonObject prev = parseObject(s.verifiedProxy);
    const QJsonObject next = parseObject(publish);
    s.verifiedProxy = publish;

    // A quote priced under the previous verdict is not the one the user would be signing, and
    // the route label behind the balances was read under it too. Nothing re-reads balances on a
    // verdict change, so the label has to be withdrawn here or it outlives it.
    if (prev.value(QStringLiteral("mode")) != next.value(QStringLiteral("mode"))
        || prev.value(QStringLiteral("state")) != next.value(QStringLiteral("state"))) {
        withdrawQuote(s);
        s.balancesRoute.clear();
    }

    // Only a CONFIRMED `off` stops the poll; `unknown` is the ordinary startup race.
    return {silent, next.value(QStringLiteral("mode")).toString() != QLatin1String("off")};
}

/// What `send` left behind. The request id is deliberately NOT scoped — it is a request sitting
/// in the signer, and forgetting it would orphan an approval the user still has to answer.
struct SendApplied {
    /// The backend took the request; a poll for its approval starts.
    bool accepted = false;
    QString requestId;
    /// The keystore's name for the approval record, for pointing a signer at this request.
    QString handle;
    /// Whether the refusal reached the modal the user is standing in front of.
    bool surfaced = false;
};

/// `send` is a SYNC call into a `concurrency:"multi"` module, so it dispatches queued events
/// inline and the selection can move inside it. sendError is scoped: a refusal worded for the
/// account being left has already been withdrawn by enterScope, and republishing it here would
/// put it under the account that replaced it.
inline SendApplied applySend(ScopedState &s, const QString &reply, bool selectionHeld)
{
    if (replyOk(reply)) {
        const QJsonObject o = parseObject(reply);
        return {true, o.value(QStringLiteral("requestId")).toString(),
                o.value(QStringLiteral("handle")).toString(), false};
    }
    if (!selectionHeld)
        return {};
    s.sendError = replyError(reply);
    return {false, QString(), QString(), true};
}

/// What the network read may do. Its write IS `shown()`, the selection every other check is
/// made against, so an answer older than the screen is DROPPED and asked for again: putting the
/// chain back turns every correct reply for the network the wallet is really on into a refusal.
enum class NetworkStep { AskAgain, Publish, Unknown };

inline NetworkStep networkStep(bool selectionHeld, const QString &reply)
{
    if (!selectionHeld)
        return NetworkStep::AskAgain;
    return replyOk(reply) ? NetworkStep::Publish : NetworkStep::Unknown;
}

/// Whether the chain named by the later read may be adopted. It is a selection write like any
/// other, and zero means the reply did not say.
inline bool mayAdopt(bool selectionHeld, int reportedChainId)
{
    return selectionHeld && reportedChainId != 0;
}
