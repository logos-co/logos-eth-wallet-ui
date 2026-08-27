#include "eth_wallet_ui_backend.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

// The generated umbrella carrying `struct LogosModules` — without it `modules()` is an
// incomplete type and every dependency call fails to compile.
#include "logos_sdk.h"

namespace {

constexpr int kSendPollMs = 1500;

QJsonObject parseObject(const QString &reply)
{
    return QJsonDocument::fromJson(reply.toUtf8()).object();
}

bool replyOk(const QString &reply)
{
    return parseObject(reply).value(QStringLiteral("ok")).toBool();
}

QString replyError(const QString &reply)
{
    const QString e = parseObject(reply).value(QStringLiteral("error")).toString();
    return e.isEmpty() ? QStringLiteral("the wallet backend refused the request") : e;
}

/// Re-serialize one member of a reply, so the view receives just the payload.
QString member(const QString &reply, const char *key)
{
    const QJsonValue v = parseObject(reply).value(QLatin1String(key));
    if (v.isArray())
        return QString::fromUtf8(QJsonDocument(v.toArray()).toJson(QJsonDocument::Compact));
    if (v.isObject())
        return QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact));
    return {};
}

} // namespace

bool EthWalletUiBackend::failed(const QString &reply, const QString &context)
{
    if (replyOk(reply))
        return false;
    setLastError(context.isEmpty() ? replyError(reply)
                                   : QStringLiteral("%1: %2").arg(context, replyError(reply)));
    return true;
}

void EthWalletUiBackend::refreshSoon()
{
    QTimer::singleShot(0, [this] { refresh(); });
}

void EthWalletUiBackend::onContextReady()
{
    m_sendPoll.setInterval(kSendPollMs);
    QObject::connect(&m_sendPoll, &QTimer::timeout, [this] { pollSend(); });

    // Balances move without us asking — a send from elsewhere, a block landing. Subscribing
    // makes that a push; the send poll below is the only thing that needs a timer.
    modules().eth_wallet_backend.onBalances_updated([this](QString) { refreshSoon(); });
    modules().eth_wallet_backend.onActive_chain_changed([this](int) { refreshSoon(); });
    modules().eth_wallet_backend.onSend_status_changed([this](QString) {
        QTimer::singleShot(0, [this] { pollSend(); });
    });

    refresh();
}

void EthWalletUiBackend::loadNetwork()
{
    const QString active = modules().eth_wallet_backend.get_active_network();
    if (!failed(active, QStringLiteral("network")))
        setActiveNetworkJson(member(active, "network"));

    const QString all = modules().eth_wallet_backend.list_networks();
    if (!failed(all, QStringLiteral("networks")))
        setNetworksJson(member(all, "networks"));

    const QString tokens = modules().eth_wallet_backend.list_tokens();
    if (!failed(tokens, QStringLiteral("tokens")))
        setTokensJson(member(tokens, "tokens"));
}

void EthWalletUiBackend::loadAccounts()
{
    const QString reply = modules().eth_wallet_backend.list_accounts();
    if (failed(reply, QStringLiteral("accounts")))
        return;
    setAccountsJson(member(reply, "accounts"));

    const QJsonArray list = QJsonDocument::fromJson(accountsJson().toUtf8()).array();
    const bool stillThere = std::any_of(list.begin(), list.end(), [this](const QJsonValue &v) {
        return v.toString().compare(selectedAccount(), Qt::CaseInsensitive) == 0;
    });
    if (!stillThere)
        setSelectedAccount(list.isEmpty() ? QString() : list.first().toString());
}

void EthWalletUiBackend::loadBalancesAndHistory()
{
    if (selectedAccount().isEmpty()) {
        setBalancesJson(QString());
        setHistoryJson(QStringLiteral("[]"));
        return;
    }

    const QString bal = modules().eth_wallet_backend.get_balances(selectedAccount());
    // On failure the balances stay EMPTY rather than keeping the previous network's numbers.
    // A stale figure attached to the wrong chain is worse than no figure at all.
    setBalancesJson(replyOk(bal) ? member(bal, "balances") : QString());
    if (!replyOk(bal))
        setLastError(QStringLiteral("balances: %1").arg(replyError(bal)));

    const QString hist = modules().eth_wallet_backend.get_history(selectedAccount());
    setHistoryJson(replyOk(hist) ? member(hist, "transactions") : QStringLiteral("[]"));
}

void EthWalletUiBackend::loadFeeTiers()
{
    const QString reply = modules().eth_wallet_backend.suggest_fees();
    if (!replyOk(reply)) {
        setFeeTiersJson(QStringLiteral("{}"));
        return;
    }
    // Pass the whole reply through: the view shows `source`, so the user can see when the
    // wallet is pricing off legacy gasPrice rather than a real EIP-1559 suggestion.
    setFeeTiersJson(reply);
}

void EthWalletUiBackend::refresh()
{
    if (m_inFlight)
        return;
    m_inFlight = true;
    setBusy(true);
    setLastError(QString());

    loadNetwork();
    loadAccounts();
    loadBalancesAndHistory();
    loadFeeTiers();

    setStatusText(QStringLiteral("Ready"));
    setBusy(false);
    m_inFlight = false;
}

void EthWalletUiBackend::selectAccount(QString address)
{
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

    // Drop everything chain-scoped before re-reading, so nothing from the previous network
    // can be shown against the new one even briefly.
    setBalancesJson(QString());
    setHistoryJson(QStringLiteral("[]"));
    setQuoteJson(QStringLiteral("{}"));
    refresh();
}

void EthWalletUiBackend::setRpcUrl(int chainId, QString url)
{
    setLastError(QString());
    if (!failed(modules().eth_wallet_backend.set_rpc_url(chainId, url), QStringLiteral("endpoint")))
        refresh();
}

void EthWalletUiBackend::setVerifiedProxyMode(int chainId, QString mode)
{
    setLastError(QString());
    if (!failed(modules().eth_wallet_backend.set_verified_proxy_mode(chainId, mode),
                QStringLiteral("verified proxy")))
        refresh();
}

void EthWalletUiBackend::quote(QString requestJson)
{
    setLastError(QString());
    const QString reply = modules().eth_wallet_backend.prepare_send(requestJson);
    if (!replyOk(reply)) {
        setQuoteJson(QStringLiteral("{}"));
        // Insufficient funds and a priority fee above the max fee both land here, worded by
        // the backend. The view renders this string and adds no rule of its own.
        setLastError(replyError(reply));
        return;
    }
    setQuoteJson(reply);
}

void EthWalletUiBackend::submitSend(QString requestJson)
{
    setLastError(QString());
    setBusy(true);
    const QString reply = modules().eth_wallet_backend.send(requestJson);
    setBusy(false);
    if (failed(reply, QString()))
        return;

    setPendingRequestId(parseObject(reply).value(QStringLiteral("requestId")).toString());
    setSendStatusJson(QStringLiteral(R"({"status":"awaitingApproval"})"));
    setStatusText(QStringLiteral("Waiting for approval"));
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
        setPendingRequestId(QString());
        return;
    }
    setSendStatusJson(reply);

    const QString status = parseObject(reply).value(QStringLiteral("status")).toString();
    if (status == QLatin1String("awaitingApproval"))
        return;

    m_sendPoll.stop();
    setPendingRequestId(QString());
    setStatusText(status == QLatin1String("broadcast") ? QStringLiteral("Sent")
                                                       : QStringLiteral("Not sent"));
    refresh();
}

void EthWalletUiBackend::cancelSend()
{
    if (pendingRequestId().isEmpty())
        return;
    const QString reply = modules().eth_wallet_backend.cancel_send(pendingRequestId());
    m_sendPoll.stop();
    setSendStatusJson(reply);
    setPendingRequestId(QString());
    setStatusText(QStringLiteral("Cancelled"));
}

void EthWalletUiBackend::refreshTxStatus(QString hashHex)
{
    if (!failed(modules().eth_wallet_backend.refresh_tx_status(hashHex), QStringLiteral("receipt")))
        loadBalancesAndHistory();
}
