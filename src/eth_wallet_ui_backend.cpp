#include "eth_wallet_ui_backend.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

// The generated umbrella carrying `struct LogosModules` — without it `modules()` is an
// incomplete type and every dependency call fails to compile.
#include "logos_sdk.h"

namespace {

constexpr int kSendPollMs = 1500;
constexpr int kPendingPollMs = 5000;
// eth_rpc's verdict TTL is also 5s, so a tick typically MISSES that cache and pays a real
// probe. Every poll below is asynchronous for exactly that reason.
constexpr int kVerifiedPollMs = 5000;
// Verdict polls that learned nothing tolerated (~15s) before the published verdict is
// withdrawn. One transport blip must not repaint the chip; a backend that has stopped
// answering must not leave a stale "ready" on screen while nothing is being verified.
constexpr int kMaxSilentPolls = 3;
// Ask #4's refresh. Twelve seconds is one mainnet block: the base fee moves at most 12.5% per
// block, so a faster poll cannot learn anything new. It also clears eth_rpc's 5s verdict TTL
// above, so a tick does not collide with the verified-proxy probe.
constexpr int kQuotePollMs = 12000;
// The cut on one catalogue search. The embedded list runs to thousands of rows and no screen
// can be scrolled through that; the reply says how many matched BEFORE the cut, so the count
// on screen is the honest one either way.
constexpr int kTokenSearchLimit = 200;

} // namespace

// Wired here rather than in onContextReady: a lane entered before its spinner and its re-run
// were attached would raise a spinner nothing lowers.
EthWalletUiBackend::EthWalletUiBackend()
{
    m_dataLane.budgetMs = kTwoCallBudgetMs;
    m_dataLane.setLoading = [this](bool on) { setDataLoading(on); };
    m_dataLane.rerun = [this] { loadBalancesAndHistory(); };

    m_quoteLane.budgetMs = kOneCallBudgetMs;
    m_quoteLane.setLoading = [this](bool on) { setQuoteLoading(on); };
    m_quoteLane.rerun = [this] {
        const bool wasEdit = m_quoteAgainInteractive;
        m_quoteAgainInteractive = false;
        runQuote(m_quoteRequest, wasEdit);
    };

    m_tokenSearchLane.budgetMs = kOneCallBudgetMs;
    m_tokenSearchLane.setLoading = [this](bool on) { setAvailableTokensLoading(on); };
    // Reads m_tokenQuery rather than a captured one: a keystroke queued behind a live call
    // must search for what was typed LAST, not for what started the call it is waiting on.
    m_tokenSearchLane.rerun = [this] { runTokenSearch(); };
}

bool EthWalletUiBackend::failed(const QString &reply, const QString &context)
{
    if (replyOk(reply))
        return false;
    setLastError(refusal(reply, context));
    return true;
}

Selection EthWalletUiBackend::shown() const
{
    return selectionOf(selectedAccount(), activeNetworkJson());
}

// Assigned by name, not positionally: every field here is a QString or a bool, so a snapshot
// that fell out of step with the struct would compile and publish the wrong value.
ScopedState EthWalletUiBackend::scopeSnapshot() const
{
    ScopedState s;
    s.at = shown();
    s.fresh = scopedDataFresh();
    s.balances = balancesJson();
    s.balancesRoute = balancesRoute();
    s.history = historyJson();
    s.blockedChains = blockedChainsJson();
    s.quote = quoteJson();
    s.quoteRequest = quoteRequestJson();
    s.quoteStale = quoteStale();
    s.sendError = sendError();
    s.txDetails = txDetailsJson();
    s.tokens = tokensJson();
    s.feeTiers = feeTiersJson();
    s.verifiedProxy = verifiedProxyJson();
    return s;
}

// The generated setters are change-guarded, so publishing a whole snapshot moves only what a
// transition actually touched.
void EthWalletUiBackend::publishScope(const ScopedState &s)
{
    setScopedDataFresh(s.fresh);
    setBalancesJson(s.balances);
    setBalancesRoute(s.balancesRoute);
    setHistoryJson(s.history);
    setBlockedChainsJson(s.blockedChains);
    setQuoteJson(s.quote);
    setQuoteRequestJson(s.quoteRequest);
    setQuoteStale(s.quoteStale);
    setSendError(s.sendError);
    setTxDetailsJson(s.txDetails);
    setTokensJson(s.tokens);
    setFeeTiersJson(s.feeTiers);
    setVerifiedProxyJson(s.verifiedProxy);
}

void EthWalletUiBackend::publishSelection(const QString &account, const QString &networkJson)
{
    ScopedState s = scopeSnapshot();
    const Selection to = selectionOf(account, networkJson);
    const bool chainMoved = s.at.chainId != to.chainId;
    if (enterScope(s, to)) {
        // Withdraw BEFORE publishing the selection below: the two reach the view as separate
        // updates, and the other order puts the previous account's figures under the new name.
        ++m_dataGen;
        ++m_quoteGen;
        publishScope(s);
    }
    // The staleness bound counts silence about the chain on screen, so a new chain starts it
    // again rather than inheriting the last one's unanswered ticks.
    if (chainMoved)
        m_vpSilent = 0;
    EthWalletUiSimpleSource::setSelectedAccount(account);
    EthWalletUiSimpleSource::setActiveNetworkJson(networkJson);
}

bool EthWalletUiBackend::adoptChain(int chainId)
{
    if (chainId == shown().chainId)
        return false;
    // list_networks is not chain-scoped, so the new network's own object is already in hand.
    // Without it the chip would read "—" for the frames before the refresh below lands.
    const QJsonArray all = QJsonDocument::fromJson(networksJson().toUtf8()).array();
    for (const QJsonValue &v : all) {
        const QJsonObject n = v.toObject();
        if (n.value(QStringLiteral("chainId")).toInt() == chainId) {
            setActiveNetworkJson(
                QString::fromUtf8(QJsonDocument(n).toJson(QJsonDocument::Compact)));
            return true;
        }
    }
    setActiveNetworkJson(QStringLiteral("{\"chainId\":%1}").arg(chainId));
    return true;
}

bool EthWalletUiBackend::beginLane(AsyncLane &lane, quint64 *slot)
{
    if (!takeLane(lane, slot))
        return false;
    lane.setLoading(true);
    // The claim is a DEADLINE and a callback can simply never fire. Without this the re-run
    // queued behind a lost call is stranded and the spinner never comes down.
    QTimer::singleShot(lane.budgetMs + 1, this, [this, &lane] {
        if (!lane.busy())
            handOnLane(lane);
    });
    return true;
}

void EthWalletUiBackend::handOnLane(AsyncLane &lane)
{
    if (laneFinish(lane) == LaneStep::Rerun)
        lane.rerun();
    else
        lane.setLoading(false);
}

bool EthWalletUiBackend::beginClaim(InFlight &claim, quint64 *slot, const SetLoading &setLoading)
{
    if (!claim.take(kOneCallBudgetMs, slot))
        return false;
    setLoading(true);
    // The claim is a DEADLINE and a callback can simply never fire. Without this the spinner
    // outlives the call it is about and the button never comes back.
    QTimer::singleShot(kOneCallBudgetMs + 1, this, [this, &claim, setLoading] {
        if (!claim.busy())
            setLoading(false);
    });
    return true;
}

void EthWalletUiBackend::setSelectedAccount(QString address)
{
    publishSelection(address, activeNetworkJson());
}

void EthWalletUiBackend::setActiveNetworkJson(QString networkJson)
{
    publishSelection(selectedAccount(), networkJson);
}

void EthWalletUiBackend::refreshSoon()
{
    QTimer::singleShot(0, [this] { refresh(); });
}

void EthWalletUiBackend::applyVerifiedProxy(const QString &verdictJson)
{
    ScopedState s = scopeSnapshot();
    const VerdictApplied v = applyVerdict(s, verdictJson, m_vpSilent, kMaxSilentPolls);
    m_vpSilent = v.silent;
    publishScope(s);
    if (!v.poll)
        m_vpPoll.stop();
    else if (!m_vpPoll.isActive())
        m_vpPoll.start();
}

void EthWalletUiBackend::onContextReady()
{
    m_sendPoll.setInterval(kSendPollMs);
    QObject::connect(&m_sendPoll, &QTimer::timeout, [this] { pollSend(); });
    m_pendingPoll.setInterval(kPendingPollMs);
    QObject::connect(&m_pendingPoll, &QTimer::timeout, [this] { refreshPending(); });
    m_vpPoll.setInterval(kVerifiedPollMs);
    QObject::connect(&m_vpPoll, &QTimer::timeout, [this] { pollVerifiedProxy(); });
    m_quotePoll.setInterval(kQuotePollMs);
    QObject::connect(&m_quotePoll, &QTimer::timeout, [this] {
        // A send awaiting a human is settled, not being priced: re-quoting it would move the
        // figures out from under the transaction already sitting in the signer.
        if (m_quoteRequest.isEmpty() || !pendingRequestId().isEmpty())
            return;
        runQuote(m_quoteRequest, false);
    });

    // Balances move without us asking — a send from elsewhere, a block landing. Subscribing
    // makes that a push; the send poll below is the only thing that needs a timer.
    //
    // The event names the account. It does NOT name a chain, so this is half a scope check:
    // a move on a chain we are not showing still costs one re-read.
    modules().eth_wallet_backend.onBalances_updated([this](QString address) {
        if (address.isEmpty() || address.compare(selectedAccount(), Qt::CaseInsensitive) == 0)
            refreshSoon();
    });
    // Taken, not discarded: until the move is adopted, the values for the network being left
    // are on screen and every reply for it is one this view would still have accepted.
    modules().eth_wallet_backend.onActive_chain_changed([this](int chainId) {
        adoptChain(chainId);
        refreshSoon();
    });
    modules().eth_wallet_backend.onSend_status_changed([this](QString) {
        QTimer::singleShot(0, [this] { pollSend(); });
    });
    // A settled receipt moves balances and one history row, not the network or the accounts.
    // The event names a HASH and no scope, so it cannot be filtered — the re-read it triggers
    // is checked against the selection on screen by the appliers instead.
    modules().eth_wallet_backend.onTx_status_changed([this](QString) {
        QTimer::singleShot(0, [this] { loadBalancesAndHistory(); });
    });
    // The keystore is mutated from another app entirely, so the roster and the NAMES on it
    // move without this view doing anything. The count in the payload is advisory — a rename
    // does not move it — so it is discarded and the whole selection is re-read.
    modules().eth_wallet_backend.onAccounts_changed([this](int) { refreshSoon(); });
    // The set of tokens OFFERED on a chain moves without this view asking — a toggle it made
    // itself, and a custom token another app imported into token_list. Chain-scoped, so a
    // move on a network we are not showing costs nothing.
    modules().eth_wallet_backend.onTokens_changed([this](int chainId) {
        if (chainId != shown().chainId)
            return;
        refreshSoon();
        runTokenSearch();
    });
    // Device-wide and chainless. The rows are BUILT in this order, so adopting it is what
    // makes an order chosen in another wallet instance visible here.
    modules().eth_wallet_backend.onToken_sort_changed([this](QString order) {
        setTokenSort(order);
        refreshSoon();
    });
    // eth_rpc's record for a chain moved, and eth_rpc is configured from ANOTHER app. This is
    // what restores the verdict: `applyVerdict` stops the poll on a confirmed `off`, so
    // without this, verification switched on elsewhere would never reach this screen. The
    // refresh carries the verdict inline and restarts the poll, so nothing else is needed.
    modules().eth_wallet_backend.onNetworks_changed([this](int) { refreshSoon(); });

    refresh();
}

void EthWalletUiBackend::loadNetwork()
{
    // This write IS `shown()`, the selection every reply is checked against, so it takes a
    // witness like a reply. The read spins the event loop: an answer older than a chain change
    // landing inside it puts the chain BACK, and every consumer then refuses the real one.
    quint64 gen = m_dataGen;
    const QString active = modules().eth_wallet_backend.get_active_network();
    switch (networkStep(selectionHeld(gen), active)) {
    case NetworkStep::AskAgain:
        // Nothing else guarantees a re-read: selectAccount() moves the selection without one.
        m_refreshAgain = true;
        break;
    case NetworkStep::Publish:
        setActiveNetworkJson(member(active, "network"));
        // The verdict rides along inside the network object, so one refresh feeds the chip.
        applyVerifiedProxy(member(activeNetworkJson(), "verifiedProxy"));
        break;
    case NetworkStep::Unknown:
        setLastError(refusal(active, QStringLiteral("network")));
        // A network we could not read is a selection we do not know: publishing an empty one
        // withdraws the chain-scoped values rather than leaving them under a stale name.
        setActiveNetworkJson(QStringLiteral("{}"));
        // Nothing else re-reads the network, and the view is now showing dashes: ask again
        // rather than leaving the wallet blank until the user happens to do something.
        if (!m_networkRetry) {
            m_networkRetry = true;
            QTimer::singleShot(kVerifiedPollMs, this, [this] {
                m_networkRetry = false;
                refresh();
            });
        }
        // The FIRST read is the one that loses a startup race, and this is the only branch
        // that reaches it. Without a poll here the chip stays hidden forever.
        if (!m_vpPoll.isActive())
            m_vpPoll.start();
        break;
    }

    gen = m_dataGen;
    const QString all = modules().eth_wallet_backend.list_networks();
    if (!failed(all, QStringLiteral("networks"))) {
        setNetworksJson(member(all, "networks"));
        // The later of the two reads, and it names the chain the backend is actually on: a move
        // this view was never told about is adopted here.
        const int now = parseObject(all).value(QStringLiteral("activeChainId")).toInt();
        if (mayAdopt(selectionHeld(gen), now) && adoptChain(now))
            m_refreshAgain = true;
    }

    // Snapshotted AFTER the read, not before: a sync read into the multi backend pumps the
    // event loop, so the selection this reply is checked against is the one it left behind.
    const quint64 sortGen = m_sortChoiceGen;
    const QString tokens = modules().eth_wallet_backend.list_tokens();
    ScopedState s = scopeSnapshot();
    const Applied t = applyTokens(s, tokens);
    publishScope(s);
    // The order rides on this reply, and every refresh reads it: without this the persisted
    // order was restored only by a catalogue search, on a screen the user need never open.
    adoptTokenSort(tokens, sortGen);
    if (!t.error.isEmpty())
        setLastError(t.error);
}

void EthWalletUiBackend::loadAccounts()
{
    // BOTH reads before EITHER write: each is a synchronous call that spins the event loop, so
    // a roster published between them is on screen under the names it had before — and an
    // account that just left the keystore is on screen with nothing selected beside it.
    const QString reply = modules().eth_wallet_backend.list_accounts();
    const QString labels = modules().eth_wallet_backend.get_account_labels();
    const QString wallets = modules().eth_wallet_backend.get_account_wallets();
    if (failed(reply, QStringLiteral("accounts")))
        return;
    setAccountsJson(member(reply, "accounts"));

    // A failed read KEEPS the previous names rather than blanking the picker: a missing name
    // is cosmetic, and flickering an account's identity is worse than showing a stale one.
    if (replyOk(labels))
        setAccountLabelsJson(member(labels, "labels"));
    // Same rule as the names above: a failed read keeps what was on screen. A picker that
    // drops back to bare addresses for one refresh is a picker whose rows change identity.
    if (replyOk(wallets))
        setAccountWalletsJson(member(wallets, "wallets"));
    // The address book is neither scoped to an account nor to a chain, so it is read here
    // with the roster rather than in loadBalancesAndHistory: it does not change when either
    // moves, and re-reading it there would cost a call per selection.
    loadContacts();

    const QJsonArray list = QJsonDocument::fromJson(accountsJson().toUtf8()).array();
    const bool stillThere = std::any_of(list.begin(), list.end(), [this](const QJsonValue &v) {
        return v.toString().compare(selectedAccount(), Qt::CaseInsensitive) == 0;
    });
    // setSelectedAccount IS the withdrawal: an account that disappeared from the keystore
    // moves the scope exactly as a click on the picker does.
    if (!stillThere)
        setSelectedAccount(list.isEmpty() ? QString() : list.first().toString());
}

void EthWalletUiBackend::loadBalancesAndHistory()
{
    if (selectedAccount().isEmpty()) {
        ScopedState s = scopeSnapshot();
        applyNoAccount(s);
        publishScope(s);
        setSweep(false);
        setDataLoading(false);
        return;
    }
    quint64 slot = 0;
    if (!beginLane(m_dataLane, &slot))
        return;

    const quint64 gen = m_dataGen;
    const quint64 sortGen = m_sortChoiceGen;
    const QString who = selectedAccount();
    // AsyncResult, not Async: the plain variant hands back a bare QString, so a failed call
    // is indistinguishable from a reply, and a call refused synchronously never calls back.
    modules().eth_wallet_backend.get_balancesAsyncResult(who,
        [this, gen, sortGen, who, slot](logos::AsyncResult<QString> bal) {
            if (!m_dataLane.owns(slot))
                return;
            if (gen == m_dataGen) {
                const QString reply = bal.ok() ? bal.value : QString();
                // Not scope-gated: the order is one persisted setting, not a chain-scoped one,
                // so a reply for another selection still names the order that was chosen.
                adoptTokenSort(reply, sortGen);
                applyBalancesReply(reply);
            }
            modules().eth_wallet_backend.get_historyAsyncResult(who,
                [this, gen, slot](logos::AsyncResult<QString> hist) {
                    m_dataLane.release(slot);
                    if (!m_dataLane.owns(slot))
                        return;
                    if (gen == m_dataGen)
                        applyHistoryReply(hist.ok() ? hist.value : QString());
                    handOnLane(m_dataLane);
                },
                Timeout(kCallBudgetMs));
        },
        Timeout(kCallBudgetMs));
}

void EthWalletUiBackend::applyBalancesReply(const QString &reply)
{
    ScopedState s = scopeSnapshot();
    const Applied a = applyBalances(s, reply);
    publishScope(s);
    if (!a.error.isEmpty())
        setLastError(a.error);
}

void EthWalletUiBackend::applyHistoryReply(const QString &reply)
{
    ScopedState s = scopeSnapshot();
    const HistoryApplied h = applyHistory(s, reply);
    if (h.sweep != SweepVerdict::Unchanged)
        setSweep(h.sweep == SweepVerdict::Run);
    publishScope(s);
}

void EthWalletUiBackend::setSweep(bool due)
{
    if (!due)
        m_pendingPoll.stop();
    else if (!m_pendingPoll.isActive())
        m_pendingPoll.start();
    setSweepingReceipts(due);
}

void EthWalletUiBackend::loadFeeTiers()
{
    const QString reply = modules().eth_wallet_backend.suggest_fees();
    ScopedState s = scopeSnapshot();
    applyFeeTiers(s, reply);
    publishScope(s);
}

void EthWalletUiBackend::refresh()
{
    // Queued, not dropped: the synchronous reads below spin the event loop, so a chain change
    // arriving mid-refresh would otherwise never be read and the view would keep the previous
    // network's data with the backend already on the new one.
    if (m_inFlight) {
        m_refreshAgain = true;
        return;
    }
    m_inFlight = true;
    setLastError(QString());

    loadNetwork();
    loadAccounts();
    loadBalancesAndHistory();
    loadFeeTiers();

    m_inFlight = false;
    if (m_refreshAgain) {
        m_refreshAgain = false;
        refreshSoon();
    }
}

void EthWalletUiBackend::selectAccount(QString address)
{
    // The setter IS the withdrawal — see publishSelection().
    setSelectedAccount(address);
    loadBalancesAndHistory();
}

void EthWalletUiBackend::setActiveChain(int chainId)
{
    setLastError(QString());
    const QString reply = modules().eth_wallet_backend.set_active_chain(chainId);
    // The backend refuses while a send is awaiting approval, and its message names the
    // network that send was built for. Surface it verbatim.
    if (failed(reply, QString()))
        return;
    // refresh() re-reads the network through setActiveNetworkJson, which is what withdraws
    // everything scoped to the network being left — an in-flight reply included.
    refresh();
}

void EthWalletUiBackend::quote(QString requestJson)
{
    runQuote(requestJson, true);
}

void EthWalletUiBackend::runQuote(const QString &requestJson, bool interactive)
{
    if (requestJson != m_quoteRequest)
        ++m_quoteGen;
    m_quoteRequest = requestJson;
    // Hooked on the REQUEST, not on whether anything below calls: what is published priced the
    // previous token, tier or amount, which makes it the WRONG number under this form rather
    // than a stale one. A form that describes no send withdraws exactly like any other change.
    ScopedState s = scopeSnapshot();
    enterQuoteRequest(s, requestJson);
    // Before the return below, not after: the refusal was worded for the request the user has
    // just edited away, and a form that describes no send cannot be the one it is about.
    if (interactive)
        s.sendError.clear();
    publishScope(s);
    if (!describesASend(requestJson)) {
        setQuoteLoading(false);
        return;
    }

    // ASYNC deliberately: prepare_send reaches eth_rpc's verified gate, fee_module, a balance
    // read and a nonce read, and QML calls this on every keystroke. Synchronously that is a
    // freeze.
    quint64 slot = 0;
    if (!beginLane(m_quoteLane, &slot)) {
        m_quoteAgainInteractive = m_quoteAgainInteractive || interactive;
        return;
    }
    const quint64 gen = m_dataGen;
    const quint64 qgen = m_quoteGen;
    const QString priced = requestJson;
    modules().eth_wallet_backend.prepare_sendAsyncResult(requestJson,
        [this, gen, qgen, slot, priced, interactive](logos::AsyncResult<QString> res) {
            m_quoteLane.release(slot);
            if (!m_quoteLane.owns(slot))
                return;
            if (gen == m_dataGen && qgen == m_quoteGen) {
                ScopedState st = scopeSnapshot();
                applyQuote(st, res.ok() ? res.value : QString(), priced, interactive);
                publishScope(st);
            }
            handOnLane(m_quoteLane);
        },
        Timeout(kCallBudgetMs));
}

void EthWalletUiBackend::setQuoteAutoRefresh(bool on)
{
    ScopedState s = scopeSnapshot();
    if (!on) {
        m_quotePoll.stop();
        // Forget the request AND the figures it priced: with the dialog closed the quote
        // describes nothing on screen, and a reply still in flight must not repopulate it.
        ++m_quoteGen;
        m_quoteRequest.clear();
        withdrawQuote(s);
        publishScope(s);
        return;
    }
    s.sendError.clear();
    publishScope(s);
    if (!m_quotePoll.isActive())
        m_quotePoll.start();
}

void EthWalletUiBackend::submitSend(QString requestJson)
{
    ScopedState s = scopeSnapshot();
    s.sendError.clear();
    publishScope(s);
    // The witness is taken before the call, exactly as loadNetwork's is: `send` is SYNC into a
    // multi module, so it dispatches queued events inline and the selection can move inside it.
    const quint64 gen = m_dataGen;
    const QString reply = modules().eth_wallet_backend.send(requestJson);
    ScopedState after = scopeSnapshot();
    const SendApplied sent = applySend(after, reply, selectionHeld(gen));
    publishScope(after);
    if (!sent.accepted)
        return;

    // The outcome of the LAST send goes as this one starts: leaving it up would put a
    // receipt beside a request that has not been answered yet.
    setLastSendOutcomeJson(QString());
    setPendingApprovalHandle(sent.handle);
    setPendingRequestId(sent.requestId);
    m_sendPoll.start();
}

void EthWalletUiBackend::pollSend()
{
    if (pendingRequestId().isEmpty()) {
        m_sendPoll.stop();
        return;
    }
    const QString reply = modules().eth_wallet_backend.send_status(pendingRequestId());
    if (failed(reply, QStringLiteral("send"))) {
        m_sendPoll.stop();
        setPendingApprovalHandle(QString());
        setPendingRequestId(QString());
        return;
    }
    const QJsonObject settled = parseObject(reply);
    const QString status = settled.value(QStringLiteral("status")).toString();
    if (status == QLatin1String("awaitingApproval"))
        return;

    m_sendPoll.stop();
    // Published BEFORE the pending id clears, so the waiting dialog is never replaced by
    // nothing. The shell returns the user here the moment the signer answers, and a screen
    // that goes blank on arrival makes the trip look like it happened for no reason.
    QJsonObject outcome{{QStringLiteral("status"), status}};
    for (const auto &key : {QStringLiteral("hash"), QStringLiteral("reason")}) {
        const QString v = settled.value(key).toString();
        if (!v.isEmpty())
            outcome.insert(key, v);
    }
    setLastSendOutcomeJson(QString::fromUtf8(QJsonDocument(outcome).toJson(QJsonDocument::Compact)));
    setPendingApprovalHandle(QString());
    setPendingRequestId(QString());
    refresh();
    // AFTER refresh, which clears lastError on entry. Onto the wallet's own error line rather
    // than sendError: clearing pendingRequestId above closes both dialogs in the same turn, so
    // this is the only surface left standing to explain a send that did not go out.
    const QString reason = settled.value(QStringLiteral("reason")).toString();
    if (status != QLatin1String("broadcast") && !reason.isEmpty())
        setLastError(QStringLiteral("send %1: %2").arg(status, reason));
}

void EthWalletUiBackend::cancelSend()
{
    if (pendingRequestId().isEmpty())
        return;
    modules().eth_wallet_backend.cancel_send(pendingRequestId());
    m_sendPoll.stop();
    setLastSendOutcomeJson(QStringLiteral("{\"status\":\"cancelled\"}"));
    setPendingApprovalHandle(QString());
    setPendingRequestId(QString());
}

void EthWalletUiBackend::refreshTxStatus(QString hashHex)
{
    quint64 slot = 0;
    if (selectedAccount().isEmpty() || hashHex.isEmpty())
        return;
    if (!beginClaim(m_txStatusInFlight, &slot, [this](bool on) { setTxStatusLoading(on); }))
        return;
    const quint64 gen = m_dataGen;
    // ASYNC deliberately, and this was the last synchronous one: the call runs eth_rpc's
    // verified gate and then a receipt poll, started by a click on the GUI thread. The record's
    // own chain decides which node is asked, so the account goes with the hash.
    modules().eth_wallet_backend.refresh_tx_statusAsyncResult(selectedAccount(), hashHex,
        [this, gen, slot](logos::AsyncResult<QString> res) {
            m_txStatusInFlight.release(slot);
            if (!m_txStatusInFlight.isCurrent(slot))
                return;
            if (gen == m_dataGen
                && !failed(res.ok() ? res.value : QString(), QStringLiteral("receipt")))
                loadBalancesAndHistory();
            setTxStatusLoading(false);
        },
        Timeout(kCallBudgetMs));
}

void EthWalletUiBackend::fetchTxDetails(QString hashHex)
{
    quint64 slot = 0;
    if (selectedAccount().isEmpty() || hashHex.isEmpty())
        return;
    if (!beginClaim(m_detailsInFlight, &slot, [this](bool on) { setTxDetailsLoading(on); }))
        return;
    const quint64 gen = m_dataGen;
    // ASYNC deliberately: two JSON-RPC round trips on the row's own chain, behind eth_rpc's
    // verified gate, started by a click on the GUI thread. The hash the call was made FOR
    // travels with it — the reply is published only for that transaction.
    modules().eth_wallet_backend.get_tx_detailsAsyncResult(selectedAccount(), hashHex,
        [this, gen, slot, hashHex](logos::AsyncResult<QString> res) {
            m_detailsInFlight.release(slot);
            if (!m_detailsInFlight.isCurrent(slot))
                return;
            if (gen == m_dataGen) {
                ScopedState s = scopeSnapshot();
                applyTxDetails(s, res.ok() ? res.value : QString(), hashHex);
                publishScope(s);
            }
            setTxDetailsLoading(false);
        },
        Timeout(kCallBudgetMs));
}

void EthWalletUiBackend::pollVerifiedProxy()
{
    // A tick that could not even ask has still learned nothing, and silence is what the
    // staleness bound counts — one unanswered probe would otherwise hold "ready" on screen
    // forever. Counted here, not in the slot below, which anything may call for free.
    if (m_vpInFlight.busy())
        applyVerifiedProxy(QString());
    else
        refreshVerifiedProxy();
}

void EthWalletUiBackend::refreshVerifiedProxy()
{
    // ASYNC deliberately: this runs on the GUI thread, and eth_rpc spends its probe and
    // modules-state budgets before answering when the proxy is not installed. The guard is
    // a DEADLINE: a callback that never fires must not wedge the probe shut for good.
    quint64 slot = 0;
    if (!m_vpInFlight.take(kOneCallBudgetMs, &slot))
        return;
    modules().eth_wallet_backend.verified_proxy_stateAsyncResult(
        [this, slot](logos::AsyncResult<QString> verdict) {
            m_vpInFlight.release(slot);
            // A failed call is silence, never a verdict — the plain Async twin cannot say.
            applyVerifiedProxy(verdict.ok() ? verdict.value : QString());
        },
        Timeout(kCallBudgetMs));
}

void EthWalletUiBackend::refreshPending()
{
    quint64 slot = 0;
    if (selectedAccount().isEmpty() || !m_pendingInFlight.take(kOneCallBudgetMs, &slot))
        return;
    const quint64 gen = m_dataGen;
    // ASYNC deliberately: a sweep spends eth_rpc's probe budget plus one receipt RPC per due
    // row, and this fires every 5s on the GUI thread — the one moment the user is watching.
    // A failed sweep leaves the row pending and the schedule retries, so it is not an error
    // the user has to read — only one the guard has to survive.
    modules().eth_wallet_backend.refresh_pendingAsyncResult(selectedAccount(),
        [this, gen, slot](logos::AsyncResult<QString>) {
            m_pendingInFlight.release(slot);
            if (gen == m_dataGen)
                loadBalancesAndHistory();
        },
        Timeout(kCallBudgetMs));
}

void EthWalletUiBackend::adoptTokenSort(const QString &reply, quint64 issuedAt)
{
    const QString order = adoptedTokenSort(reply, issuedAt, m_sortChoiceGen);
    if (!order.isEmpty())
        setTokenSort(order);
}

void EthWalletUiBackend::chooseTokenSort(QString order)
{
    // Counted BEFORE the call: set_token_sort is synchronous into a `multi` backend, so it
    // pumps the event loop, and a listing issued under the previous order can land inside it
    // carrying that order back over the one just chosen.
    ++m_sortChoiceGen;
    // Synchronous like set_active_chain: it writes one string in the backend's settings and
    // reaches no chain. The rows are BUILT in that order, so both listings are re-read.
    const QString reply = modules().eth_wallet_backend.set_token_sort(order);
    if (failed(reply, QStringLiteral("token order")))
        return;
    setTokenSort(order);
}

// Both writers re-read the book rather than editing the published copy: the backend orders
// it, and a view that inserted a row itself would show an order the next read undoes.
void EthWalletUiBackend::saveContact(QString address, QString name)
{
    const QString reply = modules().eth_wallet_backend.save_contact(address, name);
    if (!replyOk(reply)) {
        setContactsError(replyError(reply));
        return;
    }
    setContactsError(QString());
    loadContacts();
}

void EthWalletUiBackend::forgetContact(QString address)
{
    const QString reply = modules().eth_wallet_backend.forget_contact(address);
    if (!replyOk(reply)) {
        setContactsError(replyError(reply));
        return;
    }
    setContactsError(QString());
    loadContacts();
}

void EthWalletUiBackend::loadContacts()
{
    const QString reply = modules().eth_wallet_backend.list_contacts();
    // A failed read KEEPS the book that is on screen, exactly as the account names do: an
    // empty picker tab is indistinguishable from "you have no contacts", and it is not that.
    if (replyOk(reply))
        setContactsJson(member(reply, "contacts"));
}

void EthWalletUiBackend::searchTokens(QString query)
{
    // A new query is a new question; the refusal belonged to the previous one.
    setTokenToggleError(QString());
    m_tokenQuery = query;
    // The chain the query is FOR, taken now: the reply is checked against the chain on screen
    // when it lands, and a search issued for one chain may not answer for another.
    m_tokenQueryChain = shown().chainId;
    runTokenSearch();
}

void EthWalletUiBackend::runTokenSearch()
{
    quint64 slot = 0;
    if (!beginLane(m_tokenSearchLane, &slot))
        return;
    const quint64 gen = m_dataGen;
    const quint64 sortGen = m_sortChoiceGen;
    // ASYNC deliberately, and the query goes to the BACKEND: the embedded Uniswap list is
    // thousands of rows, so matching it here would mean pulling all of them across the wire.
    modules().eth_wallet_backend.list_available_tokensAsyncResult(
        m_tokenQueryChain, m_tokenQuery, kTokenSearchLimit,
        [this, gen, sortGen, slot](logos::AsyncResult<QString> res) {
            m_tokenSearchLane.release(slot);
            if (!m_tokenSearchLane.owns(slot))
                return;
            const QString reply = res.ok() ? res.value : QString();
            if (gen == m_dataGen && answersFor(reply, shown())) {
                adoptTokenSort(reply, sortGen);
                // The reply VERBATIM, so the screen can tell an empty catalogue from a
                // catalogue that could not be read — it carries `listed` and `listError`.
                setAvailableTokensJson(replyOk(reply) ? reply : QString());
                failed(reply, QStringLiteral("token list"));
            }
            handOnLane(m_tokenSearchLane);
        },
        Timeout(kCallBudgetMs));
}

void EthWalletUiBackend::setTokenEnabled(QString address, bool enabled)
{
    quint64 slot = 0;
    if (address.isEmpty())
        return;
    if (!beginClaim(m_tokenToggleInFlight, &slot, [this](bool on) { setTokenToggleBusy(on); }))
        return;
    setTokenToggleError(QString());
    const quint64 gen = m_dataGen;
    modules().eth_wallet_backend.set_token_enabledAsyncResult(shown().chainId, address, enabled,
        [this, gen, slot](logos::AsyncResult<QString> res) {
            m_tokenToggleInFlight.release(slot);
            if (!m_tokenToggleInFlight.isCurrent(slot))
                return;
            const QString reply = res.ok() ? res.value : QString();
            if (gen == m_dataGen) {
                // Onto the toggle's OWN line rather than lastError: the switch springs back to
                // whatever the backend still says, and the refusal is the only account of why.
                // Disabling a builtin is refused, and this is where that has to be readable.
                if (!replyOk(reply)) {
                    setTokenToggleError(refusal(reply, QStringLiteral("token")));
                }
            }
            setTokenToggleBusy(false);
        },
        Timeout(kCallBudgetMs));
}
