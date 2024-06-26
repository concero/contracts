// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {Storage} from "./Libraries/Storage.sol";
import {IParentPool} from "./Interfaces/IParentPool.sol";
import {IDexSwap} from "./Interfaces/IDexSwap.sol";

////////////////////////////////////////////////////////
//////////////////////// ERRORS ////////////////////////
////////////////////////////////////////////////////////
///@notice error emitted when a TX was already added
error TXAlreadyExists(bytes32 txHash, bool isConfirmed);
///@notice error emitted when a unexpected ID is added
error UnexpectedRequestID(bytes32);
///@notice error emitted when a transaction does not exist
error TxDoesNotExist();
///@notice error emitted when a transaction was already confirmed
error TxAlreadyConfirmed();
///@notice error emitted when function receive a call from a not allowed address
error AddressNotSet();
///@notice error emitted when an arbitrary address calls fulfillRequestWrapper
error ConceroFunctions_ItsNotOrchestrator(address caller);
error ConceroFunctions_NotMessenger(address caller);
error TXReleasedFailed(bytes error); // todo: TXReleasE

contract ConceroFunctions is FunctionsClient, Storage {
  ///////////////////////
  ///TYPE DECLARATIONS///
  ///////////////////////
  using SafeERC20 for IERC20;
  using FunctionsRequest for FunctionsRequest.Request;

  ///////////////////////////////////////////////////////////
  //////////////////////// VARIABLES ////////////////////////
  ///////////////////////////////////////////////////////////
  ///////////////
  ///CONSTANTS///
  ///////////////
  ///@notice
  uint32 public constant CL_FUNCTIONS_CALLBACK_GAS_LIMIT = 300_000;
  ///@notice
  uint256 public constant CL_FUNCTIONS_GAS_OVERHEAD = 185_000;
  ///@notice
  uint8 internal constant CL_SRC_RESPONSE_LENGTH = 192;
  ///@notice JS Code for Chainlink Functions
  string internal constant CL_JS_CODE =
    "try { const u = 'https://raw.githubusercontent.com/ethers-io/ethers.js/v6.10.0/dist/ethers.umd.min.js'; const [t, p] = await Promise.all([ fetch(u), fetch( `https://raw.githubusercontent.com/concero/contracts-ccip/new-delpoy-infra-script/packages/hardhat/tasks/CLFScripts/dist/${BigInt(bytesArgs[2]) === 1n ? 'DST' : 'SRC'}.min.js`, ), ]); const [e, c] = await Promise.all([t.text(), p.text()]); const g = async s => { return ( '0x' + Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))) .map(v => ('0' + v.toString(16)).slice(-2).toLowerCase()) .join('') ); }; const r = await g(c); const x = await g(e); const b = bytesArgs[0].toLowerCase(); const o = bytesArgs[1].toLowerCase(); if (r === b && x === o) { const ethers = new Function(e + '; return ethers;')(); return await eval(c); } throw new Error(`${r}!=${b}||${x}!=${o}`); } catch (e) { throw new Error(e.message.slice(0, 255));}";

  ////////////////
  ///IMMUTABLES///
  ////////////////
  ///@notice Chainlink Function Don ID
  bytes32 private immutable i_donId;
  ///@notice Chainlink Functions Protocol Subscription ID
  uint64 private immutable i_subscriptionId;
  //@notice CCIP chainSelector
  uint64 immutable CHAIN_SELECTOR;
  ///@notice variable to store the DexSwap address
  address immutable i_dexSwap;
  ///@notice variable to store the ConceroPool address
  address immutable i_poolProxy;
  ///@notice Immutable variable to hold proxy address
  address immutable i_proxy;
  ///@notice ID of the deployed chain on getChain() function
  Chain immutable i_chainIndex;

  ////////////////////////////////////////////////////////
  //////////////////////// EVENTS ////////////////////////
  ////////////////////////////////////////////////////////
  ///@notice emitted on source when a Unconfirmed TX is sent
  event UnconfirmedTXSent(bytes32 indexed ccipMessageId, address sender, address recipient, uint256 amount, CCIPToken token, uint64 dstChainSelector);
  ///@notice emitted when a Unconfirmed TX is added by a cross-chain TX
  event UnconfirmedTXAdded(bytes32 indexed ccipMessageId, address sender, address recipient, uint256 amount, CCIPToken token, uint64 srcChainSelector);
  event TXReleased(bytes32 indexed ccipMessageId, address indexed sender, address indexed recipient, address token, uint256 amount);
  ///@notice emitted when on destination when a TX is validated.
  event TXConfirmed(bytes32 indexed ccipMessageId, address indexed sender, address indexed recipient, uint256 amount, CCIPToken token);
  ///@notice emitted when a Function Request returns an error
  event FunctionsRequestError(bytes32 indexed ccipMessageId, bytes32 requestId, uint8 requestType);
  ///@notice emitted when the concero pool address is updated
  event ConceroPoolAddressUpdated(address previousAddress, address pool);

  ///////////////
  ///MODIFIERS///
  ///////////////

  /**
   * @notice modifier to check if the caller is the an approved messenger
   */
  modifier onlyMessenger() {
    if (isMessenger(msg.sender) == false) revert ConceroFunctions_NotMessenger(msg.sender);
    _;
  }

  constructor(
    FunctionsVariables memory _variables,
    uint64 _chainSelector,
    uint _chainIndex,
    address _dexSwap,
    address _pool,
    address _proxy
  ) FunctionsClient(_variables.functionsRouter) Storage(msg.sender) {
    i_donId = _variables.donId;
    i_subscriptionId = _variables.subscriptionId;
    CHAIN_SELECTOR = _chainSelector;
    i_chainIndex = Chain(_chainIndex);
    i_dexSwap = _dexSwap;
    i_poolProxy = _pool;
    i_proxy = _proxy;
  }

  ///////////////////////////////////////////////////////////////
  ///////////////////////////Functions///////////////////////////
  ///////////////////////////////////////////////////////////////

  function getDstTotalFeeInUsdc(uint256 amount) public pure returns (uint256) {
    return amount / 1000;
    //@audit we can have loss of precision here?
  }

  function addUnconfirmedTX(
    bytes32 ccipMessageId,
    address sender,
    address recipient,
    uint256 amount,
    uint64 srcChainSelector,
    CCIPToken token,
    uint256 blockNumber,
    bytes calldata dstSwapData
  ) external onlyMessenger {
    Transaction memory transaction = s_transactions[ccipMessageId];
    if (transaction.sender != address(0)) revert TXAlreadyExists(ccipMessageId, transaction.isConfirmed);

    s_transactions[ccipMessageId] = Transaction(ccipMessageId, sender, recipient, amount, token, srcChainSelector, false, dstSwapData);

    bytes[] memory args = new bytes[](12);
    args[0] = abi.encode(s_dstJsHashSum);
    args[1] = abi.encode(s_ethersHashSum);
    args[2] = abi.encode(RequestType.checkTxSrc);
    args[3] = abi.encode(s_conceroContracts[srcChainSelector]);
    args[4] = abi.encode(srcChainSelector);
    args[5] = abi.encode(blockNumber);
    args[6] = abi.encode(ccipMessageId);
    args[7] = abi.encode(sender);
    args[8] = abi.encode(recipient);
    args[9] = abi.encode(uint8(token));
    args[10] = abi.encode(amount);
    args[11] = abi.encode(CHAIN_SELECTOR);

    bytes32 reqId = sendRequest(args, CL_JS_CODE);

    s_requests[reqId].requestType = RequestType.checkTxSrc;
    s_requests[reqId].isPending = true;
    s_requests[reqId].ccipMessageId = ccipMessageId;

    emit UnconfirmedTXAdded(ccipMessageId, sender, recipient, amount, token, srcChainSelector);
  }

  /**
   * @notice Function to send a Request to Chainlink Functions
   * @param args the arguments for the request as bytes array
   * @param jsCode the JScode that will be executed.
   */
  function sendRequest(bytes[] memory args, string memory jsCode) internal returns (bytes32) {
    FunctionsRequest.Request memory req;
    req.initializeRequestForInlineJavaScript(jsCode);
    req.addDONHostedSecrets(s_donHostedSecretsSlotId, s_donHostedSecretsVersion);
    req.setBytesArgs(args);
    return _sendRequest(req.encodeCBOR(), i_subscriptionId, CL_FUNCTIONS_CALLBACK_GAS_LIMIT, i_donId);
  }

  function fulfillRequestWrapper(bytes32 requestId, bytes memory response, bytes memory err) external {
    if (address(this) != i_proxy) revert ConceroFunctions_ItsNotOrchestrator(msg.sender);

    fulfillRequest(requestId, response, err);
  }

  ////////////////////////
  ///INTERNAL FUNCTIONS///
  ////////////////////////

  function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
    Request storage request = s_requests[requestId];

    if (!request.isPending) {
      revert UnexpectedRequestID(requestId);
    }

    request.isPending = false;

    if (err.length > 0) {
      emit FunctionsRequestError(request.ccipMessageId, requestId, uint8(request.requestType));
      return;
    }

    if (request.requestType == RequestType.checkTxSrc) {
      _handleDstFunctionsResponse(request);
    } else if (request.requestType == RequestType.addUnconfirmedTxDst) {
      _handleSrcFunctionsResponse(response);
    }
  }

  function _confirmTX(bytes32 ccipMessageId, Transaction storage transaction) internal {
    if (transaction.sender == address(0)) revert TxDoesNotExist();
    if (transaction.isConfirmed == true) revert TxAlreadyConfirmed();

    transaction.isConfirmed = true;

    emit TXConfirmed(ccipMessageId, transaction.sender, transaction.recipient, transaction.amount, transaction.token);
  }

  function sendUnconfirmedTX(
    bytes32 ccipMessageId,
    address sender,
    address recipient,
    uint256 amount,
    uint64 dstChainSelector,
    CCIPToken token,
    IDexSwap.SwapData[] calldata dstSwapData
  ) internal {
    if (s_conceroContracts[dstChainSelector] == address(0)) revert AddressNotSet();

    bytes[] memory args = new bytes[](13);
    args[0] = abi.encode(s_srcJsHashSum);
    args[1] = abi.encode(s_ethersHashSum);
    args[2] = abi.encode(RequestType.addUnconfirmedTxDst);
    args[3] = abi.encode(s_conceroContracts[dstChainSelector]);
    args[4] = abi.encode(ccipMessageId);
    args[5] = abi.encode(sender);
    args[6] = abi.encode(recipient);
    args[7] = abi.encode(amount);
    args[8] = abi.encode(CHAIN_SELECTOR);
    args[9] = abi.encode(dstChainSelector);
    args[10] = abi.encode(uint8(token));
    args[11] = abi.encode(block.number);
    args[12] = _swapDataToBytes(dstSwapData);

    bytes32 reqId = sendRequest(args, CL_JS_CODE);
    s_requests[reqId].requestType = RequestType.addUnconfirmedTxDst;
    s_requests[reqId].isPending = true;
    s_requests[reqId].ccipMessageId = ccipMessageId;

    emit UnconfirmedTXSent(ccipMessageId, sender, recipient, amount, token, dstChainSelector);
  }

  function _swapDataToBytes(IDexSwap.SwapData[] calldata _swapData) private pure returns (bytes memory _encodedData) {
    uint256 numberOfSwaps = _swapData.length;
    if (numberOfSwaps == 0) return abi.encode(uint(0));

    for (uint256 i; i < numberOfSwaps; i++) {
      _encodedData = abi.encode(
        _swapData[i].dexType,
        _swapData[i].fromToken,
        _swapData[i].fromAmount,
        _swapData[i].toToken,
        _swapData[i].toAmount,
        _swapData[i].toAmountMin,
        _swapData[i].dexData
      );
    }
  }

  function _handleDstFunctionsResponse(Request storage request) internal {
    Transaction storage transaction = s_transactions[request.ccipMessageId];

    _confirmTX(request.ccipMessageId, transaction);

    address tokenReceived = getToken(transaction.token, i_chainIndex);
    uint256 amount = transaction.amount - getDstTotalFeeInUsdc(transaction.amount);

    if (transaction.dstSwapData.length > 0) {
      IParentPool(i_poolProxy).orchestratorLoan(tokenReceived, amount, address(this));
      IDexSwap.SwapData[] memory swapData = abi.decode(transaction.dstSwapData, (IDexSwap.SwapData[]));
      (bool swapSuccess, bytes memory swapError) = i_dexSwap.delegatecall(abi.encodeWithSelector(IDexSwap.conceroEntry.selector, swapData, 0));
      if (swapSuccess == false) revert TXReleasedFailed(swapError);
    } else {
      IParentPool(i_poolProxy).orchestratorLoan(tokenReceived, amount, transaction.recipient);
    }

    emit TXReleased(request.ccipMessageId, transaction.sender, transaction.recipient, tokenReceived, amount);
  }

  function _handleSrcFunctionsResponse(bytes memory response) internal {
    if (response.length != CL_SRC_RESPONSE_LENGTH) {
      return;
    }

    (uint256 dstGasPrice, uint256 srcGasPrice, uint256 dstChainSelector, uint256 linkUsdcRate, uint256 nativeUsdcRate, uint256 linkNativeRate) = abi.decode(
      response,
      (uint256, uint256, uint256, uint256, uint256, uint256)
    );

    s_lastGasPrices[CHAIN_SELECTOR] = srcGasPrice;
    s_lastGasPrices[uint64(dstChainSelector)] = dstGasPrice;
    s_latestLinkUsdcRate = linkUsdcRate;
    s_latestNativeUsdcRate = nativeUsdcRate;
    s_latestLinkNativeRate = linkNativeRate;
  }

  /**
   * @notice Function to check if a caller address is an allowed messenger
   * @param _messenger the address of the caller
   */
  function isMessenger(address _messenger) internal pure returns (bool _isMessenger) {
    address[] memory messengers = new address[](4); //Number of messengers. To define.
    messengers[0] = 0x05CF0be5cAE993b4d7B70D691e063f1E0abeD267; //fake messenger from foundry environment
    messengers[1] = address(0);
    messengers[2] = address(0);
    messengers[3] = address(0);

    for (uint256 i; i < messengers.length; ) {
      if (_messenger == messengers[i]) {
        return true;
      }
      unchecked {
        ++i;
      }
    }
    return false;
  }
}
