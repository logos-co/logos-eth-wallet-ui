// The account picker over the signer manager's roster: each account once, by its name and
// address, with its wallet and every signer holding it. One account the keystore and a Shell
// both hold, one on a card whose reader is empty, and one the roster hasn't listed yet.
import QtQuick
import QtQuick.Controls
import QtTest
Item {
 id: probe
 width: 1040; height: 740
 property var requests: []
 property var logos: ({ module: function(n) { return fake }, isViewModuleReady: function(n) { return true },
                        request: function(intent, params, done) { probe.requests.push({ intent: intent, params: params }) } })
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
property string signerWalletsJson: "[]"
property bool contactsLocked: false
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
  // Signers are short tags now ("Keystore", "Keycard", "Keycard Shell", "QR wallet"); the long
  // form with its transport stays in each tag's accessible name and in the summary.
  check("...the keystore first",text("accountPickerSelectedChip_0")==="Keystore")
  check("...then the Shell holding it too",text("accountPickerSelectedChip_1")==="Keycard Shell")
  check("...each tag's accessible name keeps the transport",find(view.item,"accountPickerSelectedChip_1").Accessible.name==="Keycard Shell · USB, connected")
  var summary=view.item.accountDisplay(software)
  check("the summary names the account before its signers",summary.indexOf("Ethereum 0 0x1111…1111 — Wallet “Family”")===0 && summary.indexOf("This device (Keystore), Keycard Shell · USB")>summary.indexOf("Wallet"))
  check("an account the roster hasn't listed yet keeps its wallet name",view.item.accountDisplay(other).indexOf("Wallet “Work”")>0)
  picker.currentIndex=1;picker.activated(1)
  check("selection uses address",fake.selectedAccount===card)
  check("the card's account by name",text("accountPickerSelectedName")==="Savings")
  // Its only holder is not connected, and it still shows: the row must say which device to connect.
  check("...on a card whose reader is empty",text("accountPickerSelectedChip_0")==="Keycard")
  check("...said in grey, not as a signer that can sign now",find(view.item,"accountPickerSelectedChip_0").Accessible.name==="Keycard · reader, not connected")
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
  probe.grabToImage(function(image){image.saveToFile("/tmp/account-origins-build/EthWalletView.png");locked.start()})
 } }
 // Every wallet locked: no account is usable, so the picker and the tabs are gone and the view
 // must say WHICH device to unlock. One notice per device app, as the picker's footer groups
 // them (a Shell folds into Keycard: both unlock in the Keycard app), each with its own Unlock.
 Timer { id:locked;interval:300;onTriggered:{
  var picker=find(view.item,"accountPicker"); picker.popup.close()
  console.log("every wallet locked")
  fake.signerWalletsJson=JSON.stringify([{seed:"s-card",name:"Family",locked:true,kinds:["keycard"]},
                                         {seed:"s-file",name:"Work",locked:true,kinds:["keystore"]},
                                         {seed:"s-shell",name:"Travel",locked:true,kinds:["keycard_shell"]},
                                         {seed:"s-open",name:"Open",locked:false,kinds:["keystore"]}])
  check("mixed state: no locked notice while an account is usable (the picker's footer has them)",!find(view.item,"accountsLocked_Keycard"))
  fake.accountsJson="[]"
  check("the picker is hidden",!picker.visible)
  check("...and the tabs",!find(view.item,"tabs").visible)
  var card=find(view.item,"accountsLocked_Keycard"), file=find(view.item,"accountsLocked_Keystore")
  check("a notice for the Keycard wallets, the Shell's among them",card!==null && card.title==="2 Keycard wallets are locked")
  check("...naming the app that unlocks them",card!==null && card.message==="Unlock them in the Keycard app to use their accounts.")
  check("a notice for the Keystore wallet",file!==null && file.title==="1 Keystore wallet is locked")
  check("...naming its app",file!==null && file.message==="Unlock them in the Keystore app to use their accounts.")
  check("no notice for a wallet that is open",!find(view.item,"accountsLocked_Signer"))
  check("no generic Signer-app banner",!find(view.item,"accountsLockedBanner"))
  var unlock=card ? (find(card,"accountsUnlock_Keycard") || card.actions[0]) : null
  check("each notice has its own Unlock",unlock!==null && unlock.objectName==="accountsUnlock_Keycard" && unlock.text==="Unlock")
  if (unlock) unlock.clicked()
  var last=probe.requests[probe.requests.length-1]
  check("...which asks for that device's wallets only",last!==undefined && last.intent==="wallets.unlock" && JSON.stringify(last.params.seeds)==='["s-card","s-shell"]')
  fake.signerWalletsJson="[]"
  check("no wallet at all: where accounts come from instead",find(view.item,"noWalletsState").visible && !find(view.item,"accountsLocked_Keycard"))
  Qt.exit(probe.failures ? 1 : 0)
 } }
 Component.onCompleted: {
  fake.accountsJson=JSON.stringify([software,card,other]);fake.selectedAccount=software
  fake.accountWalletsJson=wallets()
  fake.accountRosterJson=roster("Savings")
  view.source=Qt.resolvedUrl("../src/qml/EthWalletView.qml")
 }
}
