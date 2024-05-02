// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

contract FunctionsPlayground is FunctionsClient, ConfirmedOwner {
  using FunctionsRequest for FunctionsRequest.Request;

  bytes32 public s_lastRequestId;
  bytes public s_lastResponse;
  bytes public s_lastError;

  error UnexpectedRequestID(bytes32 requestId);

  event Response(bytes32 indexed requestId, string character, bytes response, bytes err);

  bytes32 immutable donID;

  string public character;
  uint64 public subscriptionId;

  constructor(address _router, bytes32 _donId, uint64 _subscriptionId) FunctionsClient(_router) ConfirmedOwner(msg.sender) {
    donID = _donId;
    subscriptionId = _subscriptionId;
  }

  function setSubscriptionId(uint64 _subscriptionId) external onlyOwner {
    subscriptionId = _subscriptionId;
  }

  function sendRequest(string calldata sourceCode, string[] calldata args) external onlyOwner returns (bytes32 requestId) {
    FunctionsRequest.Request memory req;
    req.initializeRequestForInlineJavaScript(sourceCode);
    if (args.length > 0) req.setArgs(args);

    s_lastRequestId = _sendRequest(req.encodeCBOR(), subscriptionId, 300000, donID);

    return s_lastRequestId;
  }

  function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
    if (s_lastRequestId != requestId) {
      revert UnexpectedRequestID(requestId);
    }
    s_lastResponse = response;
    character = string(response);
    s_lastError = err;

    emit Response(requestId, character, s_lastResponse, s_lastError);
  }
}