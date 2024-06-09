// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

////////////////////////////////////////////////////////
//////////////////////// ERRORS ////////////////////////
////////////////////////////////////////////////////////
///@notice error emitted when the caller is not authorized
error ConceroPool_Unauthorized();
///@notice error emitted when the balance is not sufficient
error ConceroPool_InsufficientBalance();
///@notice error emitted when the transfer revert
error ConceroPool_TransferFailed();
///@notice error emitted when the user input an unsupported token
error ConceroPool_TokenNotSupported();
///@notice error emitted when the caller is not an Orchestrator
error ConceroPool_ItsNotAnOrchestrator(address caller);
///@notice error emitted when the receiver is the address(0)
error ConceroPool_InvalidAddress();
///@notice error emitted when the CCIP message sender is not allowed.
error ConceroPool_SenderNotAllowed(address _sender);
///@notice error emitted when an attempt to create a new request is made while other is still active.
error ConceroPool_PendingRequestNotFulfilledYet();
///@notice error emitted when an attempt to send value to a not allowed receiver is made
error ConceroPool_DestinationNotAllowed();
///@notice error emitted when the contract doesn't have enought link balance
error ConceroPool_NotEnoughLinkBalance(uint256 linkBalance, uint256 fees);

contract ConceroPool is CCIPReceiver, Ownable {
  using SafeERC20 for IERC20;

  struct WithdrawRequests {
    uint256 condition;
    uint256 amount;
    bool isPending;
  }

  ///@notice removing magic-numbers
  uint256 private constant APPROVED = 1;
  ///@notice the maximum percentage a direct withdraw can take.
  uint256 private constant WITHDRAW_THRESHOLD = 10;
  ///@notice Chainlink Link Token interface
  LinkTokenInterface private immutable i_linkToken;
  ///@notice Chainlink CCIP Router
  IRouterClient private immutable i_router;
  address public immutable i_conceroOrchestrator;

  ///@notice Mapping to keep track of allowed tokens ~ 1 == True
  mapping(address token => uint256 isApproved) public s_isTokenSupported;
  ///@notice Mapping to keep track of allowed senders on a given token
  mapping(address token => address senderAllowed) public s_approvedSenders;
  ///@notice Mapping to keep track of balances of user on a given token
  mapping(address token => mapping(address user => uint256 balance)) public s_userBalances;
  ///@notice Mapping to keep track of allowed pool senders ~ 1 == True
  mapping(uint64 chainId => mapping(address poolAddress => uint256)) public s_allowedPool;
  ///@notice Mapping to keep track of allowed pool receiver
  mapping(uint64 chainId => address pool) public s_poolReceiver;
  ///@notice Mapping to keep track of withdraw requests
  mapping(address token => WithdrawRequests) private s_withdrawWaitlist;
  ///@notice address of the messenger addresses
  mapping(address => uint256) private s_messengerAddresses;

  ////////////////////////////////////////////////////////
  //////////////////////// EVENTS ////////////////////////
  ////////////////////////////////////////////////////////

  ///@notice event emitted when an Orchestrator is updated
  event ConceroPool_OrchestratorUpdated(address previousOrchestrator, address orchestrator);
  ///@notice event emitted when a Messenger is added
  event ConceroPool_MessengerAddressAdded(address messengerAddress);
  ///@notice event emitted when a Messenger is removed
  event ConceroPool_MessengerAddressRemoved(address messengerAddress);
  ///@notice event emitted when a supported token is added
  event ConceroPool_TokenSupportedUpdated(address token, uint256 isSupported);
  ///@notice event emitted when an approved sender is updated
  event ConceroPool_ApprovedSenderUpdated(address token, address indexed newSender);
  ///@notice event emitted when a Concero contract is added
  event ConceroPool_ConceroContractUpdated(uint64 chainSelector, address conceroContract, uint256 isAllowed);
  ///@notice event emitted when a Concero pool is added
  event ConceroPool_PoolReceiverUpdated(uint64 chainSelector, address pool);
  ///@notice event emitted when value is deposited into the contract
  event ConceroPool_Deposited(address indexed token, address indexed from, uint256 amount);
  ///@notice event emitted when a new withdraw request is made
  event ConceroPool_WithdrawRequest(address caller, address token, uint256 condition, uint256 amount);
  ///@notice event emitted when a value is withdraw from the contract
  event ConceroPool_Withdrawn(address to, address token, uint256 amount);
  ///@notice event emitted when a Cross-chain tx is received.
  event ConceroPool_CCIPReceived(bytes32 indexed ccipMessageId, uint64 srcChainSelector, address sender, address token, uint256 amount);
  ///@notice event emitted when a Cross-chain message is sent.
  event ConceroPool_MessageSent(bytes32 messageId, uint64 destinationChainSelector, address receiver, address linkToken, uint256 fees);

  ///////////////
  ///MODIFIERS///
  ///////////////
  /**
   * @notice Modifier to check if the msg.sender is allowed to manage the specific token
   * @param _token the address of the token to check.
   */
  modifier onlyApprovedSender(address _token) {
    if (s_approvedSenders[_token] != msg.sender) revert ConceroPool_Unauthorized();
    _;
  }

  /**
   * @notice CCIP Modifier to check Chains And senders
   * @param _chainSelector Id of the source chain of the message
   * @param _sender address of the sender contract
   */
  modifier onlyAllowlistedSenderAndChainSelector(uint64 _chainSelector, address _sender) {
    if (s_allowedPool[_chainSelector][_sender] != APPROVED) revert ConceroPool_SenderNotAllowed(_sender);
    _;
  }

  constructor(address _link, address _ccipRouter, address _conceroOrchestrator) CCIPReceiver(_ccipRouter) {
    i_linkToken = LinkTokenInterface(_link);
    i_router = IRouterClient(_ccipRouter);
    i_conceroOrchestrator = _conceroOrchestrator;
  }

  /////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////FUNCTIONS//////////////////////////////////
  /////////////////////////////////////////////////////////////////////////////
  receive() external payable {}

  //////////////////////////////////
  ///onlyOwner EXTERNAL FUNCTIONS///
  //////////////////////////////////

  /**
   * @notice Function to update the messenger address
   * @param _messenger the address that will call some restrict functions
   * @param _isAllowed 1 == True | Any other value == False
   * @dev only owner can call it
   * @dev it's payable to save some gas.
   */
  function setMessenger(address _messenger, uint256 _isAllowed) external payable onlyOwner {
    s_messengerAddresses[_messenger] = _isAllowed;

    if (_isAllowed == APPROVED) {
      emit ConceroPool_MessengerAddressAdded(_messenger);
    } else {
      emit ConceroPool_MessengerAddressRemoved(_messenger);
    }
  }

  /**
   * @notice function to manage the Cross-chains Concero contracts
   * @param _chainSelector chain identifications
   * @param _contractAddress address of the Cross-chains Concero contracts
   * @param _isAllowed 1 == allowed | Any other value == not allowed
   * @dev only owner can call it
   * @dev it's payable to save some gas.
   */
  function setConceroContractSender(uint64 _chainSelector, address _contractAddress, uint256 _isAllowed) external payable onlyOwner {
    s_allowedPool[_chainSelector][_contractAddress] = _isAllowed;

    emit ConceroPool_ConceroContractUpdated(_chainSelector, _contractAddress, _isAllowed);
  }

  /**
   * @notice function to manage the Cross-chains Concero contracts
   * @param _chainSelector chain identifications
   * @param _pool address of the Cross-chains Concero contracts
   * @dev only owner can call it
   * @dev it's payable to save some gas.
   */
  function setConceroPoolReceiver(uint64 _chainSelector, address _pool) external payable onlyOwner {
    s_poolReceiver[_chainSelector] = _pool;

    emit ConceroPool_PoolReceiverUpdated(_chainSelector, _pool);
  }

  /**
   * @notice function to manage supported tokens
   * @param _token address of the token
   * @param _isApproved 1 == True | Any other value == False
   * @dev only owner can call it
   * @dev it's payable to save some gas.
   */
  function setSupportedToken(address _token, uint256 _isApproved) external payable onlyOwner {
    s_isTokenSupported[_token] = _isApproved;

    emit ConceroPool_TokenSupportedUpdated(_token, _isApproved);
  }

  /**
   * @notice function to manage token depositors
   * @param _token address of the token
   * @param _approvedSender address of the depositor
   * @dev only owner can call it
   * @dev it's payable to save some gas.
   */
  function setApprovedSender(address _token, address _approvedSender) external payable onlyOwner {
    if (s_isTokenSupported[_token] != APPROVED) revert ConceroPool_TokenNotSupported();

    s_approvedSenders[_token] = _approvedSender;

    emit ConceroPool_ApprovedSenderUpdated(_token, _approvedSender);
  }

  ////////////////////////
  ///EXTERNAL FUNCTIONS///
  ////////////////////////
  /**
   * @notice function to deposit Ether
   * @dev The address(0) is hardcode as ether
   * @dev only approved address can call this function
   */
  function depositEther() external payable onlyApprovedSender(address(0)) {
    uint256 valueToBeTransfered = msg.value;

    s_userBalances[address(0)][msg.sender] = s_userBalances[address(0)][msg.sender] + valueToBeTransfered;

    emit ConceroPool_Deposited(address(0), msg.sender, valueToBeTransfered);
  }

  /**
   * @notice function to deposit ERC20 tokens
   * @param _token the address of the token to be deposited
   * @param _amount the amount to be deposited
   * @dev only approved address can call this function
   */
  function depositToken(address _token, uint256 _amount) external onlyApprovedSender(_token) {
    s_userBalances[_token][msg.sender] = s_userBalances[_token][msg.sender] + _amount;

    emit ConceroPool_Deposited(_token, msg.sender, _amount);

    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
  }

  /**
   * @notice this function will manage LP's withdraw requests
   * @param _token the address of the token being withdraw
   * @param _amount the amount to be withdraw
   * @dev if the value is bigger than the threshold, a request will be created
   * @dev if the value is less than the threshold, the withdraw will procced right away.
   */
  function withdrawLiquidityRequest(address _token, uint256 _amount) external onlyApprovedSender(_token) {
    if (_amount > s_userBalances[_token][msg.sender]) revert ConceroPool_InsufficientBalance();

    WithdrawRequests memory request = s_withdrawWaitlist[_token];

    uint256 tokenAmount;
    if (_token == address(0)) {
      tokenAmount = address(this).balance;
    } else {
      tokenAmount = IERC20(_token).balanceOf(address(this));
    }

    if (request.isPending) {
      if (tokenAmount < request.condition) revert ConceroPool_PendingRequestNotFulfilledYet();

      s_withdrawWaitlist[_token].isPending = false;
      _withdraw(_token, _amount);
    } else {
      if (_amount > (tokenAmount * WITHDRAW_THRESHOLD) / 100) {
        uint256 condition = (tokenAmount - ((tokenAmount * WITHDRAW_THRESHOLD) / 100)) + _amount;
        s_withdrawWaitlist[_token] = WithdrawRequests({condition: condition, amount: _amount, isPending: true});
        emit ConceroPool_WithdrawRequest(msg.sender, _token, condition, _amount); //CLF will listen to this.
      } else {
        _withdraw(_token, _amount);
      }
    }
  }

  /**
   * @notice Function to Distribute Liquidity across Concero Pools
   * @param _destinationChainSelector Chain Id of the chain that will receive the amount
   * @param _token  address of the token to be sent
   * @param _amount amount of the token to be sent
   */
  function ccipSendToPool(uint64 _destinationChainSelector, address _token, uint256 _amount) external returns (bytes32 messageId) {
    if (s_messengerAddresses[msg.sender] != APPROVED) revert ConceroPool_Unauthorized();

    if (s_poolReceiver[_destinationChainSelector] == address(0)) revert ConceroPool_DestinationNotAllowed();

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);

    Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({token: _token, amount: _amount});

    tokenAmounts[0] = tokenAmount;

    Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(s_poolReceiver[_destinationChainSelector]),
      data: "",
      tokenAmounts: tokenAmounts,
      extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 300_000})),
      feeToken: address(i_linkToken)
    });

    uint256 fees = i_router.getFee(_destinationChainSelector, evm2AnyMessage);

    emit ConceroPool_MessageSent(messageId, _destinationChainSelector, s_poolReceiver[_destinationChainSelector], address(i_linkToken), fees);

    if (fees > i_linkToken.balanceOf(address(this))) revert ConceroPool_NotEnoughLinkBalance(i_linkToken.balanceOf(address(this)), fees);

    IERC20(_token).safeApprove(address(i_router), _amount);
    i_linkToken.approve(address(i_router), fees);

    messageId = i_router.ccipSend(_destinationChainSelector, evm2AnyMessage);
  }

  /**
   * @notice function to the Concero Orchestrator contract take loans
   * @param _token address of the token being loaned
   * @param _amount being loaned
   * @param _receiver address of the user that will receive the amount
   * @dev only the Orchestrator contract should be able to call this function
   * @dev for ether transfer, the _receiver need to be known and trusted
   */
  function orchestratorLoan(address _token, uint256 _amount, address _receiver) external {
    if (msg.sender != i_conceroOrchestrator) revert ConceroPool_ItsNotAnOrchestrator(msg.sender);
    if (_receiver == address(0)) revert ConceroPool_InvalidAddress();

    if (_token == address(0)) {
      if (_amount > address(this).balance) revert ConceroPool_InsufficientBalance();

      (bool sent, ) = _receiver.call{value: _amount}("");
      if (!sent) revert ConceroPool_TransferFailed();
    } else {
      if (_amount > IERC20(_token).balanceOf(address(this))) revert ConceroPool_InsufficientBalance();

      IERC20(_token).safeTransfer(_receiver, _amount);
    }
  }

  ////////////////
  /// INTERNAL ///
  ////////////////
  /**
   * @notice CCIP function to receive bridged values
   * @param any2EvmMessage the CCIP message
   * @dev only allowed chains and sender must be able to deliver a message in this function.
   */
  function _ccipReceive(
    Client.Any2EVMMessage memory any2EvmMessage
  ) internal override onlyAllowlistedSenderAndChainSelector(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address))) {
    address receivedToken = any2EvmMessage.destTokenAmounts[0].token;
    address allowedSenderToCompoundLpFee = s_approvedSenders[receivedToken];

    if (any2EvmMessage.data.length > 0) {
      uint256 receivedAmount = abi.decode(any2EvmMessage.data, (uint256));

      s_userBalances[receivedToken][allowedSenderToCompoundLpFee] = s_userBalances[receivedToken][allowedSenderToCompoundLpFee] + receivedAmount;
    } else {
      s_userBalances[receivedToken][s_messengerAddress] = s_userBalances[receivedToken][s_messengerAddress] + any2EvmMessage.destTokenAmounts[0].amount;
    }

    emit ConceroPool_CCIPReceived(
      any2EvmMessage.messageId,
      any2EvmMessage.sourceChainSelector,
      abi.decode(any2EvmMessage.sender, (address)),
      any2EvmMessage.destTokenAmounts[0].token,
      any2EvmMessage.destTokenAmounts[0].amount
    );
  }

  ///////////////
  /// PRIVATE ///
  ///////////////

  /**
   * @notice function to withdraw ERC20 or native tokens from the pool
   * @param _token address of the token to be withdraw
   * @param _amount the total amount to be withdraw
   * @dev this is a private function that can only be called throught `withdrawLiquidityRequest`
   */
  function _withdraw(address _token, uint256 _amount) private onlyApprovedSender(_token) {
    bool isNativeToken = _token == address(0);
    if (isNativeToken) {
      if (_amount > s_userBalances[address(0)][msg.sender] || _amount > address(this).balance) revert ConceroPool_InsufficientBalance();
    } else {
      if (_amount > IERC20(_token).balanceOf(address(this))) revert ConceroPool_InsufficientBalance();
    }

    s_userBalances[_token][msg.sender] = s_userBalances[_token][msg.sender] - _amount;
    emit ConceroPool_Withdrawn(msg.sender, _token, _amount);

    if (isNativeToken) {
      (bool sent, ) = msg.sender.call{value: _amount}("");
      if (!sent) revert ConceroPool_TransferFailed();
    } else {
      IERC20(_token).safeTransfer(msg.sender, _amount);
    }
  }

  ///////////////////////////
  ///VIEW & PURE FUNCTIONS///
  ///////////////////////////
  /**
   * @notice getter function to keep track of the contract balances
   * @param _token the address of the token
   * @return _contractBalance in the momento of the call.
   * @dev to access ether, _token must be address(0).
   */
  function availableBalanceNow(address _token) external view returns (uint256 _contractBalance) {
    if (_token == address(0)) {
      _contractBalance = address(this).balance;
    } else {
      _contractBalance = IERC20(_token).balanceOf(address(this));
    }
  }

  //@audit can remove this later
  function getRequestInfo(address _token) external view returns (WithdrawRequests memory request) {
    request = s_withdrawWaitlist[_token];
  }
}
