import QtQuick
import QtQuick.Controls
import QtTest
Item {
 id: probe
 width: 1040; height: 740
 property var logos: ({ module: function(n) { return fake }, isViewModuleReady: function(n) { return true } })
 readonly property string software: "0x1111111111111111111111111111111111111111"
 readonly property string card: "0x2222222222222222222222222222222222222222"
 readonly property string other: "0x3333333333333333333333333333333333333333"
 TestCase { id: input; name: "SelectorCopy"; when: false }
 property int failures: 0
 function check(label, condition) { if (!condition) failures++; console.log((condition ? "PASS " : "FAIL ")+label) }
 function find(o,n) { if (!o) return null; if(o.objectName===n) return o; var children=o.data||[]; for(var i=0;i<children.length;i++){var f=find(children[i],n);if(f)return f;} return null }
 function origins(name) { var o={}; o[software]={signer:"keystore_module",origin:{devices:[{kind:"keystore",id:"local"}],phrase:{id:"seed-local-123",name:"Family"}}};o[card]={signer:"keycard_module",available:false,origin:{devices:[{kind:"keycard",id:"instance:abc12345678",name:name}],phrase:{id:"seed-card-123"}}};o[other]={signer:"keystore_module",origin:{devices:[{kind:"keystore",id:"local"}],phrase:{id:"another-wallet",name:"Work"}}};return JSON.stringify(o) }
 QtObject { id: fake
property string lastError: ""
property bool scopedDataFresh: false
property bool dataLoading: false
property bool balancesLoading: false
property bool quoteLoading: false
property bool feeTiersLoading: false
property string activeNetworkJson: "{}"
property string networksJson: "[]"
property string networkScope: "mainnets"
property string verifiedProxyJson: "{}"
property string accountsJson: "[]"
property string selectedAccount: ""
property string accountLabelsJson: "{}"
property string accountWalletsJson: "{}"
property string contactsJson: "[]"
property string contactsError: ""
property string balancesJson: ""
property string balancesRoute: ""
property string tokensJson: ""
property string tokenSort: "alpha"
property string historyJson: ""
property string blockedChainsJson: ""
property bool sweepingReceipts: false
property string blockedNoncesJson: ""
property bool resendLoading: false
property string resendReviewJson: ""
property string txDetailsJson: ""
property bool txDetailsLoading: false
property bool txStatusLoading: false
property string feeTiersJson: "{}"
property string quoteJson: "{}"
property string quoteRequestJson: ""
property string sendError: ""
property bool quoteStale: false
property string pendingRequestId: ""
property string pendingApprovalHandle: ""
property string lastSendOutcomeJson: ""
property string intentSendJson: ""
property bool intentSendPricing: false
function refreshVerifiedProxy(a) {}
function acceptIntentSend(a) {}
function selectAccount(a) {selectedAccount = a}
function resendBlockedNonce(a) {}
function dismissResend(a) {}
function setQuoteAutoRefresh(a) {}
function fetchTxDetails(a) {}
function submitSend(a) {}
function selectChain(a) {}
function reviewIntentSend(a) {}
function saveContact(a) {}
function refreshPending(a) {}
function declineIntentSend(a) {}
function refresh(a) {}
property int accountRefreshes: 0
function refreshAccounts() { accountRefreshes++ }
function chooseTokenSort(a) {}
function refreshTxStatus(a) {}
function quote(a) {}
function cancelSend(a) {}
function forgetContact(a) {}
function pollSend(a) {}
 }
 Loader { id:view; anchors.fill:parent; onLoaded: settle.start(); onStatusChanged: if(status===Loader.Error) Qt.exit(1) }
 Timer { id:settle; interval:300; onTriggered: {
  check("both accounts loaded",view.item.accounts.length===3)
  check("named phrase and device",view.item.accountDisplay(software).indexOf("This device (Keystore) — Wallet “Family”")===0)
  check("disconnected card name and ID",view.item.accountDisplay(card).indexOf("Keycard “Travel” · abc12345")===0)
  check("account name and address retained",view.item.accountDisplay(card).indexOf("Savings — 0x")>0)
  var picker=find(view.item,"accountPicker");
  check("selected value has three lines for multiple wallets",find(view.item,"accountPickerSelectedWallet").visible)
  check("selection height is fixed",picker.height===88)
  check("model stays addresses",picker.model[1]===card)
  picker.currentIndex=1;picker.activated(1)
  check("selection uses address",fake.selectedAccount===card)
  fake.accountWalletsJson=origins("Renamed")
  check("rename updates label",view.item.accountDisplay(card).indexOf("Renamed")>=0)
  check("rename keeps selected account",fake.selectedAccount===card)
  check("single-wallet device omits middle line",!find(view.item,"accountPickerSelectedWallet").visible)
  check("device rename stays visible",find(view.item,"accountPickerSelectedDevice").text.indexOf("Renamed")>=0)
  check("two-line selection keeps same height",picker.height===88)
  var copy=find(view.item,"accountPickerSelectedCopy")
  input.mouseClick(copy.mouseAreaItem)
  check("selector copies full address without opening popup",view.item.lastCopiedValue===card && !picker.popup.visible)
  check("duplicate address row removed",!find(view.item,"addressLabel"))
  picker.popup.open(); screenshot.start()
 } }
 Timer { id:screenshot;interval:300;onTriggered:{
  var picker=find(view.item,"accountPicker");
  check("opening selector refreshes signer accounts",fake.accountRefreshes===1)
  var list=picker.popupListView;
  check("dropdown entries share height",list.itemAtIndex(0).height===88 && list.itemAtIndex(1).height===88)
  var copy=find(list.itemAtIndex(0).contentItem,"accountRow_0Copy")
  input.mouseClick(copy.mouseAreaItem)
  check("dropdown copy preserves selected account and popup",view.item.lastCopiedValue===software && fake.selectedAccount===card && picker.popup.visible)
  picker.popup.contentItem.grabToImage(function(image){image.saveToFile("/tmp/account-origins-build/EthWalletView-popup.png")})
  probe.grabToImage(function(image){image.saveToFile("/tmp/account-origins-build/EthWalletView.png");Qt.exit(probe.failures ? 1 : 0)})
 } }
 Component.onCompleted: {
  fake.accountsJson=JSON.stringify([software,card,other]);fake.selectedAccount=software
  var names={};names[card.slice(2)]="Savings";fake.accountLabelsJson=JSON.stringify(names)
  fake.accountWalletsJson=origins("Travel")
  view.source=Qt.resolvedUrl("../src/qml/EthWalletView.qml")
 }
}
