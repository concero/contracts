//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

////////////////////////////////////////////////////////
//////////////////////// ERRORS ////////////////////////
////////////////////////////////////////////////////////
///@notice error emitted when the caller is not the owner of the contract
error ChildStorage_NotContractOwner();
///@notice error emitted when the receiver is the address(0)
error ChildStorage_InvalidAddress();
///@notice error emitted when the caller is not the messenger
error ChildStorage_NotMessenger(address caller);
///@notice error emitted when the CCIP message sender is not allowed.
error ChildStorage_SenderNotAllowed(address sender);

contract ChildStorage {
  ///////////////////////////////////////////////////////////
  //////////////////////// VARIABLES ////////////////////////
  ///////////////////////////////////////////////////////////

  ///////////
  ///STATE///
  ///////////
  ///@notice variable to store the value that will be temporary used by Chainlink Functions
  uint256 public s_loansInUse;
  ///@notice gap to reserve storage in the contract for future variable additions
  uint256[50] __gap;

  ////////////////
  ///IMMUTABLES///
  ////////////////
  ///@notice Contract Owner
  address immutable i_owner;

  ///////////////
  ///CONSTANTS///
  ///////////////
  ///@notice Magic Number Removal
  uint256 private constant ALLOWED = 1;

  /////////////
  ///STORAGE///
  /////////////
  ///@notice Mapping to keep track of allowed pool senders
  mapping(uint64 chainSelector => mapping(address conceroContract => uint256)) public s_contractsToReceiveFrom;

  ////////////////////////////////////////////////////////
  //////////////////////// EVENTS ////////////////////////
  ////////////////////////////////////////////////////////
  ///@notice event emitted when a allowed Cross-chain contract is updated
  event ChildStorage_ConceroSendersUpdated(uint64 chainSelector, address conceroContract, uint256 isAllowed);

  ///////////////
  ///MODIFIERS///
  ///////////////
  modifier onlyOwner() {
    if (msg.sender != i_owner) revert ChildStorage_NotContractOwner();
    _;
  }

  /**
   * @notice CCIP Modifier to check Chains And senders
   * @param _chainSelector Id of the source chain of the message
   * @param _sender address of the sender contract
   */
  modifier onlyAllowlistedSenderAndChainSelector(uint64 _chainSelector, address _sender) {
    if (s_contractsToReceiveFrom[_chainSelector][_sender] != ALLOWED) revert ChildStorage_SenderNotAllowed(_sender);
    _;
  }

  /**
   * @notice modifier to check if the caller is the an approved messenger
   */
  modifier onlyMessenger() {
    if (isMessengers(msg.sender) == false) revert ChildStorage_NotMessenger(msg.sender);
    _;
  }

  /////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////FUNCTIONS//////////////////////////////////
  /////////////////////////////////////////////////////////////////////////////
  constructor(address _owner) {
    i_owner = _owner;
  }

  ///////////////////////
  ///SETTERS FUNCTIONS///
  ///////////////////////
  /**
   * @notice function to manage the Cross-chains Concero contracts
   * @param _chainSelector chain identifications
   * @param _contractAddress address of the Cross-chains Concero contracts
   * @param _isAllowed 1 == allowed | Any other value == not allowed
   * @dev only owner can call it
   * @dev it's payable to save some gas.
   * @dev this functions is used on ConceroPool.sol
   */
  function setConceroContractSender(uint64 _chainSelector, address _contractAddress, uint256 _isAllowed) external payable onlyOwner {
    if (_contractAddress == address(0)) revert ChildStorage_InvalidAddress();
    s_contractsToReceiveFrom[_chainSelector][_contractAddress] = _isAllowed;

    emit ChildStorage_ConceroSendersUpdated(_chainSelector, _contractAddress, _isAllowed);
  }

  ///////////////////////////
  ///VIEW & PURE FUNCTIONS///
  ///////////////////////////

  /**
   * @notice Function to check if a caller address is an allowed messenger
   * @param _messenger the address of the caller
   */
  function isMessengers(address _messenger) internal pure returns (bool isMessenger) {
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
