import {simulateScript} from "@chainlink/functions-toolkit"
import fs from "fs";
import dotenv from "dotenv";

dotenv.config({path: "./.env"});

//const [fromChainSelector, toChainSelector, token, amount, txHash, sender, receiver, blockHash] = args;
const fromChainSelector = "12532609583862916517";
const toChainSelector = "14767482510784806043";
const token = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB";
const amount = "1000000000000000000";
const txHash = "0x5d2b4f7b1b6e5d3b4f6c";
const sender = "0x5d2b4f7b1b6e5d3b4f6c";
const receiver = "0x5d2b4f7b1b6e5d3b4f6c";
const blockHash = "0x5d2b4f7b1b6e5d3b4f6c";

const PROVIDER_API_KEY = "8acf47c71165427f8cee3a92fea12da2";

const args = [
    fromChainSelector,
    toChainSelector,
    token,
    amount,
    txHash,
    sender,
    receiver,
    blockHash,
];

const secrets = {
    PROVIDER_API_KEY: PROVIDER_API_KEY,
    WALLET_PRIVATE_KEY: process.env.SECOND_TEST_WALLET_PRIVATE_KEY,
    INFURA_API_KEY: PROVIDER_API_KEY,
};

// async function simulateDST() {
//   const result = await simulateScript({
//     source: fs.readFileSync("./CLFunctionsDST.js", "utf8"),
//     args, // Array of string arguments accessible from the source code via the global variable `args`
//     // bytesArgs? : string[] // Array of bytes arguments, represented as hex strings, accessible from the source code via the global variable `bytesArgs`
//     secrets, // Secret values represented as key-value pairs
//     // maxOnChainResponseBytes // ? : number // Maximum size of the returned value in bytes (defaults to 256)
//     // maxExecutionTimeMs // ? : number // Maximum execution duration (defaults to 10_000ms)
//     // maxMemoryUsageMb // ? : number // Maximum RAM usage (defaults to 128mb)
//     // numAllowedQueries // ? : number // Maximum number of HTTP requests (defaults to 5)
//     // maxQueryDurationMs // ? : number // Maximum duration of each HTTP request (defaults to 9_000ms)
//     // maxQueryUrlLength // ? : number // Maximum HTTP request URL length (defaults to 2048)
//     // maxQueryRequestBytes // ? : number // Maximum size of outgoing HTTP request payload (defaults to 2048 == 2 KB)
//     // maxQueryResponseBytes // ? : number // Maximum size of incoming HTTP response payload (defaults to 2_097_152 == 2 MB)
//   });
//   console.log(result);
//   return result;
// }

async function simulateSRC() {
    const {responseBytesHexstring, errorString, capturedTerminalOutput} =
        await simulateScript({
            source: fs.readFileSync("./LOCAL-CLFunctionsSRC.mjs", "utf8"),
            args,
            secrets,
            maxOnChainResponseBytes: 256,
            maxExecutionTimeMs: 100000,
            maxMemoryUsageMb: 128,
            numAllowedQueries: 5,
            maxQueryDurationMs: 10000,
            maxQueryUrlLength: 2048,
            maxQueryRequestBytes: 2048,
            maxQueryResponseBytes: 2097152,
        });

    if (errorString) {
        console.error(errorString);
    }

    console.log(capturedTerminalOutput);
}

// simulateDstFunctions()
simulateSRC();
