#pragma once

#include <QObject>
#include <QString>
#include <QTimer>

#include "eth_wallet_ui_apply.h"
#include "eth_wallet_ui_guard.h"
#include "eth_wallet_ui_scope.h"
#include "rep_eth_wallet_ui_source.h"
#include "logos_ui_plugin_context.h"

// The Ethereum wallet UI backend.
//
// Every backend call is made here over the generated typed client; the QML half renders and
// makes no module calls of its own. Nothing on this class takes or returns key material: it
// requests signatures and reads which accounts exist, and that is the whole of its reach.
//
// It holds no rule about what may reach the screen. Every scoped value is produced by a pure
// transition in eth_wallet_ui_apply.h and published through publishScope() below, so the guard
// deciding whether a reply is rendered is executed by doctests/test_apply.cpp rather than
// described by a grep over this file.
class EthWalletUiBackend : public EthWalletUiSimpleSource,
                           public LogosUiPluginContext
{
public:
    EthWalletUiBackend();

    void refresh() override;
    void selectAccount(QString address) override;
    void setActiveChain(int chainId) override;
    void quote(QString requestJson) override;
    void setQuoteAutoRefresh(bool on) override;
    void submitSend(QString requestJson) override;
    void pollSend() override;
    void cancelSend() override;
    void refreshTxStatus(QString hashHex) override;
    void fetchTxDetails(QString hashHex) override;
    void refreshVerifiedProxy() override;
    void refreshPending() override;
    void chooseTokenSort(QString order) override;
    void searchTokens(QString query) override;
    void setTokenEnabled(QString address, bool enabled) override;

    /// The two halves of the selection, overridden onto publishSelection() below. Overriding
    /// rather than shadowing is what makes the withdrawal unavoidable: a handler that
    /// publishes an account or a network gets it whether it asked for it or not.
    void setSelectedAccount(QString address) override;
    void setActiveNetworkJson(QString networkJson) override;

protected:
    void onContextReady() override;

private:
    /// The ONE place the selection moves. Withdraws every value the new selection does not
    /// describe, bumps the generation so an in-flight reply for the old one is dropped, and
    /// only then publishes the selection — the other order shows the previous account's
    /// figures under the new name.
    void publishSelection(const QString &account, const QString &networkJson);
    ScopedState scopeSnapshot() const;
    /// The ONLY writer of a scoped property. Everything on screen that means something against
    /// a particular account and network reaches the view through here.
    void publishScope(const ScopedState &s);

    /// The account and network on screen right now: what every reply is checked against.
    Selection shown() const;

    /// Whether the selection has stood still since `gen` was taken. Every synchronous read
    /// spins the event loop, so an answer in hand can already be older than the screen.
    bool selectionHeld(quint64 gen) const { return gen == m_dataGen; }

    /// Take the chain named by an active_chain_changed event. The counter only knows about
    /// moves this view made, so without this the values for the network being left stand —
    /// and every reply for it is accepted — until refresh() reads the move back. Answers
    /// whether the chain actually moved.
    bool adoptChain(int chainId);

    /// Enter a guarded async lane: raise its spinner and arm the lapse timer that hands the
    /// guard on when a callback never fires. Both lanes go through here, so neither can be
    /// written with a spinner nobody lowers or a re-run nobody drains.
    bool beginLane(AsyncLane &lane, quint64 *slot);
    /// Hand the guard on: run the re-run queued behind this claim, or take the spinner down.
    void handOnLane(AsyncLane &lane);
    /// Take a bare claim and raise the spinner it drives, arming the lapse that lowers it when
    /// the callback never fires. `InFlight` expires by itself; a published spinner does not, so
    /// one without the other is a spinner nobody takes down. No queue: this covers a claim a
    /// BUTTON takes, and the button is disabled while it is held.
    bool beginClaim(InFlight &claim, quint64 *slot, const SetLoading &setLoading);

    void loadNetwork();
    void loadAccounts();
    /// Read balances then history, asynchronously. Both legs reach eth_rpc's verified gate,
    /// which spends a probe budget before answering — on the GUI thread that is a freeze.
    void loadBalancesAndHistory();
    void loadFeeTiers();

    /// One quote, priced asynchronously.
    void runQuote(const QString &requestJson, bool interactive);

    /// One catalogue search, for `m_tokenQuery` on `m_tokenQueryChain`. Asynchronous: the
    /// embedded list is thousands of rows and the match runs in the backend, not here.
    void runTokenSearch();
    /// Take the order a listing reply rode back on. list_tokens, get_balances and the
    /// catalogue search ALL carry it, so the persisted order reaches the view on whichever
    /// lands first — never only on a search the user has to go and make. `issuedAt` is the
    /// choice counter the read went out under; see m_sortChoiceGen.
    void adoptTokenSort(const QString &reply, quint64 issuedAt);

    void applyBalancesReply(const QString &reply);
    void applyHistoryReply(const QString &reply);

    /// Start or stop the receipt sweep, and publish which it is. `start()` on a running
    /// timer restarts its interval, so re-arming is deliberately a no-op.
    void setSweep(bool due);

    /// Publish the verified-proxy verdict, and poll it unless verification is confirmed off.
    void applyVerifiedProxy(const QString &verdictJson);

    /// One tick of the verdict poll: probe, or count the tick that could not ask.
    void pollVerifiedProxy();

    /// Surface a backend refusal verbatim on the wallet's own error line.
    bool failed(const QString &reply, const QString &context);

    /// Re-enter on a clean event-loop stack. Required from event callbacks: calling out
    /// synchronously from an IPC callback blocks the thread that would deliver the reply.
    void refreshSoon();

    bool m_inFlight = false;
    /// One outstanding re-read of a network that could not be read. Withdrawing the chain
    /// leaves the wallet showing dashes, so something has to ask again — but only ever one.
    bool m_networkRetry = false;
    /// A refresh asked for while one was running. Queued rather than dropped: the reads spin
    /// the event loop, so a chain change landing mid-refresh would never be read at all.
    bool m_refreshAgain = false;
    /// Polls a pending send until it settles. Stopped once nothing is in flight.
    QTimer m_sendPoll;
    /// Sweeps broadcast transactions for receipts. Runs only while a row is pending.
    QTimer m_pendingPoll;
    /// Re-reads the verified-proxy verdict. Stopped only on a confirmed "off" mode.
    QTimer m_vpPoll;
    /// One probe at a time: the async read can outlast the poll interval. No queue and no
    /// spinner, so it is a bare claim rather than a lane.
    InFlight m_vpInFlight;
    /// Verdict polls in a row that learned nothing. Bounded, so a backend that has gone
    /// quiet cannot leave its last "ready" verdict on screen indefinitely.
    int m_vpSilent = 0;

    /// One balances+history read at a time, with exactly one re-read queued behind it.
    AsyncLane m_dataLane;
    /// One sweep at a time — it costs a probe plus a receipt RPC per due row.
    InFlight m_pendingInFlight;
    /// One transaction-details fetch at a time. A bare claim rather than a lane: a second press
    /// of the button should be ignored, not queued behind the first.
    InFlight m_detailsInFlight;
    /// One receipt re-read at a time, on the same terms as the fetch above.
    InFlight m_txStatusInFlight;
    /// One quote at a time, with exactly one re-price coalesced behind it: a keystroke
    /// arriving mid-call must still be priced, but every keystroke must not be a round-trip.
    AsyncLane m_quoteLane;
    /// One catalogue search at a time, one re-search coalesced behind it. Same shape as the
    /// quote lane and for the same reason: a keystroke landing mid-call must still be searched.
    AsyncLane m_tokenSearchLane;
    /// The newest query, and the chain it is meant for. The queued re-search reads them, so a
    /// keystroke arriving behind a live call searches for what was typed LAST, not first.
    QString m_tokenQuery;
    int m_tokenQueryChain = 0;
    /// One enable/disable at a time. A bare claim: a second toggle should be ignored while the
    /// first is in flight, not queued behind it and applied to a row that has since moved.
    InFlight m_tokenToggleInFlight;
    /// Whether anything queued behind the live quote was a user edit. Carried separately, or a
    /// keystroke arriving behind a timer tick replays as a tick and its refusal is swallowed.
    bool m_quoteAgainInteractive = false;
    /// The newest request seen; what the timer re-sends. Cleared when the dialog closes, so
    /// a tick can never re-price a request the user has walked away from.
    QString m_quoteRequest;
    /// Ask #4's periodic re-price. Runs only while the Send dialog is open.
    QTimer m_quotePoll;
    /// Bumped whenever the account or chain changes, so a reply for the previous one is
    /// dropped. Half the guard only: it knows about moves this view MADE, and is blind to a
    /// move it has not observed — `answersFor` checks the scope the reply itself names.
    quint64 m_dataGen = 0;
    /// The same, one dimension narrower: bumped when the REQUEST changes, so a reply priced
    /// for the previous token, tier or amount cannot land under the new one.
    quint64 m_quoteGen = 0;
    /// Bumped by every token-order CHOICE. Three different reads echo the persisted order, and
    /// one of them may already be in flight when the user picks a different one: its reply
    /// names the order it was replaced by. Compared against the counter each read captured.
    quint64 m_sortChoiceGen = 0;
};
