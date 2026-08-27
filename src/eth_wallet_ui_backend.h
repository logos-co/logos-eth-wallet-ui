#pragma once

#include <QObject>
#include <QString>
#include <QTimer>

#include "rep_eth_wallet_ui_source.h"
#include "logos_ui_plugin_context.h"

// The Ethereum wallet UI backend.
//
// Every backend call is made here over the generated typed client; the QML half renders and
// makes no module calls of its own. Nothing on this class takes or returns key material: it
// requests signatures and reads which accounts exist, and that is the whole of its reach.
class EthWalletUiBackend : public EthWalletUiSimpleSource,
                           public LogosUiPluginContext
{
public:
    void refresh() override;
    void selectAccount(QString address) override;
    void setActiveChain(int chainId) override;
    void setRpcUrl(int chainId, QString url) override;
    void setVerifiedProxyMode(int chainId, QString mode) override;
    void quote(QString requestJson) override;
    void submitSend(QString requestJson) override;
    void pollSend() override;
    void cancelSend() override;
    void refreshTxStatus(QString hashHex) override;

protected:
    void onContextReady() override;

private:
    void loadNetwork();
    void loadAccounts();
    void loadBalancesAndHistory();
    void loadFeeTiers();

    /// Surface a backend refusal verbatim. The rule that produced it lives in the backend,
    /// so restating it here would be a second copy free to drift.
    bool failed(const QString &reply, const QString &context);

    /// Re-enter on a clean event-loop stack. Required from event callbacks: calling out
    /// synchronously from an IPC callback blocks the thread that would deliver the reply.
    void refreshSoon();

    bool m_inFlight = false;
    /// Polls a pending send until it settles. Stopped once nothing is in flight.
    QTimer m_sendPoll;
};
