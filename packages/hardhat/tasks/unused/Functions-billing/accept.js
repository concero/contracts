"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const { SubscriptionManager } = require("@chainlink/functions-toolkit");
const CLFnetworks_1 = __importDefault(require("../../../constants/CLFnetworks"));
task("clf-sub-accept", "Accepts ownership of an Functions subscription after a transfer is requested")
    .addParam("subid", "Subscription ID")
    .setAction(async (taskArgs) => {
    const accounts = await ethers.getSigners();
    if (accounts.length < 2) {
        throw Error("This command requires a second wallet's private key to be made available in networks.js");
    }
    const accepter = accounts[1]; // Second wallet.
    const subscriptionId = parseInt(taskArgs.subid);
    const confirmations = CLFnetworks_1.default[network.name].confirmations;
    const txOptions = { confirmations };
    const functionsRouterAddress = CLFnetworks_1.default[network.name]["functionsRouter"];
    const linkTokenAddress = CLFnetworks_1.default[network.name]["linkToken"];
    const sm = new SubscriptionManager({ signer: accepter, linkTokenAddress, functionsRouterAddress });
    await sm.initialize();
    const currentOwner = (await sm.getSubscriptionInfo(subscriptionId)).owner;
    console.log(`\nAccepting ownership of subscription ${subscriptionId} from ${currentOwner}...`);
    const acceptTx = await sm.acceptSubTransfer({ subscriptionId, txOptions });
    console.log(`Acceptance request completed in Tx: ${acceptTx.transactionHash}. \n${accepter.address} is now the owner of subscription ${subscriptionId}.`);
    const subInfo = await sm.getSubscriptionInfo(subscriptionId);
    // parse balances into LINK for readability
    subInfo.balance = ethers.utils.formatEther(subInfo.balance) + " LINK";
    subInfo.blockedBalance = ethers.utils.formatEther(subInfo.blockedBalance) + " LINK";
    console.log("\nUpdated Subscription Info: ", subInfo);
});
exports.default = {};
