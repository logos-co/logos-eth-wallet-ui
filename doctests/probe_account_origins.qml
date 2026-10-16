// The account picker over the signer manager's roster: each account once, by its name and
// address, with its wallet and every signer holding it. One account the keystore and a Shell
// both hold, one on a card whose reader is empty, and one the roster hasn't listed yet.
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
 function text(n) { var o=find(view.item,n); return o ? o.text : "<absent>" }
 function holder(signer, transport, presence, kind, model) { return {signer:signer,accountId:"",kind:kind,model:model,transport:transport,presence:presence,available:presence!=="absent"} }
 function roster(cardLabel) { return JSON.stringify([
  {key:software,family:"evm",address:software,path:"m/44'/60'/0'/0/0",label:null,wallet:{fingerprint:"73c5da0a",name:"Family"},
   holders:[holder("keystore_module","keystore","local","keystore",""),holder("keycard_shell_module","usb","connected","keycard_shell","Keycard Shell")]},
  {key:card,family:"evm",address:card,path:"m/44'/60'/0'/0/0",label:cardLabel,wallet:{fingerprint:"9a3c11f0"},
   holders:[holder("keycard_module","reader","absent","keycard","")]}]) }
 function wallets() { var o={}; o[other]={signer:"keystore_module",origin:{devices:[{kind:"keystore",id:"local"}],phrase:{id:"another-wallet",name:"Work"}}}; return JSON.stringify(o) }
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
property string accountRosterJson: "[]"
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
  var picker=find(view.item,"accountPicker");
  check("one row per account, never one per signer",picker.model.length===3)
  check("selected: the account's address",text("accountPickerSelectedAddress")==="0x1111…1111")
  check("...its wallet, by name and fingerprint",text("accountPickerSelectedWallet")==="Wallet “Family” · 73c5da0a · account 0")
  check("...the keystore first",text("accountPickerSelectedChip_0")==="● This device (Keystore)")
  check("...then the Shell holding it too",text("accountPickerSelectedChip_1")==="● Keycard Shell · USB")
  check("the summary names the account before its signers",view.item.accountDisplay(software).indexOf("0x1111…1111 — Wallet “Family”")===0)
  check("an account the roster hasn't listed yet keeps its wallet name",view.item.accountDisplay(other).indexOf("Wallet “Work”")>0)
  picker.currentIndex=1;picker.activated(1)
  check("selection uses address",fake.selectedAccount===card)
  check("the card's account by name",text("accountPickerSelectedName")==="Savings")
  check("...on a card whose reader is empty",text("accountPickerSelectedChip_0")==="○ Keycard · reader")
  fake.accountRosterJson=roster("Travel")
  check("a rename shows",text("accountPickerSelectedName")==="Travel")
  check("rename keeps selected account",fake.selectedAccount===card && picker.currentIndex===1)
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
  check("dropdown entries share height",list.itemAtIndex(0).height===list.itemAtIndex(1).height)
  var copy=find(list.itemAtIndex(0).contentItem,"accountPickerRow_0Copy")
  input.mouseClick(copy.mouseAreaItem)
  check("dropdown copy preserves selected account and popup",view.item.lastCopiedValue===software && fake.selectedAccount===card && picker.popup.visible)
  picker.popup.contentItem.grabToImage(function(image){image.saveToFile("/tmp/account-origins-build/EthWalletView-popup.png")})
  probe.grabToImage(function(image){image.saveToFile("/tmp/account-origins-build/EthWalletView.png");Qt.exit(probe.failures ? 1 : 0)})
 } }
 Component.onCompleted: {
  fake.accountsJson=JSON.stringify([software,card,other]);fake.selectedAccount=software
  fake.accountWalletsJson=wallets()
  fake.accountRosterJson=roster("Savings")
  view.source=Qt.resolvedUrl("../src/qml/EthWalletView.qml")
 }
}
