// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";

//====== Master Pool
import {ParentPoolDeploy} from "../../../script/ParentPoolDeploy.s.sol";
import {ParentPoolProxyDeploy} from "../../../script/ParentPoolProxyDeploy.s.sol";
import {ParentPool} from "contracts/ParentPool.sol";
import {ParentPoolProxy} from "contracts/Proxy/ParentPoolProxy.sol";

//====== Child Pool
import {ChildPoolDeploy} from "../../../script/ChildPoolDeploy.s.sol";
import {ChildPoolProxyDeploy} from "../../../script/ChildPoolProxyDeploy.s.sol";
import {ConceroChildPool} from "contracts/ConceroChildPool.sol";
import {ChildPoolProxy} from "contracts/Proxy/ChildPoolProxy.sol";

//====== Automation
import {AutomationDeploy} from "../../../script/AutomationDeploy.s.sol";
import {ConceroAutomation} from "contracts/ConceroAutomation.sol";

//====== LPToken
import {LPTokenDeploy} from "../../../script/LPTokenDeploy.s.sol";
import {LPToken} from "contracts/LPToken.sol";

//====== OpenZeppelin
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

//====== Chainlink Solutions
import {CCIPLocalSimulator, IRouterClient, WETH9, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

//===== Mocks
import {USDC} from "../../Mocks/USDC.sol";

contract PoolsTesting is Test{
    //====== Instantiate Master Pool
    ParentPoolDeploy masterDeploy;
    ParentPoolProxyDeploy masterProxyDeploy;
    ParentPool master;
    ParentPoolProxy masterProxy;
    ParentPool wMaster;

    //====== Instantiate Child Pool
    ChildPoolDeploy childDeploy;
    ChildPoolProxyDeploy childProxyDeploy;
    ConceroChildPool child;
    ChildPoolProxy childProxy;
    ConceroChildPool wChild;

    //====== Instantiate Automation
    AutomationDeploy autoDeploy;
    ConceroAutomation automation;

    //====== Instantiate LPToken
    LPTokenDeploy lpDeploy;
    LPToken lp;

    //====== Instantiate Transparent Proxy Interfaces
    ITransparentUpgradeableProxy masterInterface;
    ITransparentUpgradeableProxy childInterface;

    //====== Instantiate Chainlink Solutions
    CCIPLocalSimulator public ccipLocalSimulator;    
    uint64 chainSelector;
    IRouterClient sourceRouter;
    IRouterClient destinationRouter;
    WETH9 wrappedNative;
    LinkToken linkToken;

    //====== Instantiate Mocks
    USDC usdc;
    uint256 private constant USDC_INITIAL_BALANCE = 500 * 10**6;
    uint256 private constant USDC_WHALE_BALANCE = 1000 * 10**6;

    address proxyOwner = makeAddr("owner");
    address Tester = makeAddr("Tester");
    address LiquidityProvider = makeAddr("LiquidityProvider");
    address LiquidityProviderTwo = makeAddr("LiquidityProviderTwo");
    address LiquidityProviderThree = makeAddr("LiquidityProviderThree");
    address LiquidityProviderWhale = makeAddr("Whale");
    address Athena = makeAddr("Athena");
    address Concero = makeAddr("Concero");
    address ConceroDst = makeAddr("ConceroDst");
    address Orchestrator = makeAddr("Orchestrator");
    address Messenger = makeAddr("Messenger");
    address Forwarder = makeAddr("Forwarder");
    
    address mockFunctionsRouter = makeAddr("0x08");

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();
        (
            chainSelector,
            sourceRouter,
            destinationRouter,
            wrappedNative,
            linkToken,
            ,
            
        ) = ccipLocalSimulator.configuration();

        usdc = new USDC("USDC", "USDC", Tester, USDC_INITIAL_BALANCE);
        usdc.mint(LiquidityProviderWhale, USDC_WHALE_BALANCE);

        //////////////////////////////////////////////
        /////////////// DEPLOY SCRIPTS ///////////////
        //////////////////////////////////////////////
        //====== Deploy Master Pool scripts
        masterDeploy = new ParentPoolDeploy();
        masterProxyDeploy = new ParentPoolProxyDeploy();

        //====== Deploy Child Pool scripts
        childDeploy = new ChildPoolDeploy();
        childProxyDeploy = new ChildPoolProxyDeploy();

        //====== Deploy Automation scripts
        autoDeploy = new AutomationDeploy();

        //====== Deploy LPToken scripts
        lpDeploy = new LPTokenDeploy();

        ////////////////////////////////////////////////
        /////////////// DEPLOY CONTRACTS ///////////////
        ////////////////////////////////////////////////

        //Dummy address initially
        masterProxy = masterProxyDeploy.run(address(usdc), proxyOwner, Tester, "");
        masterInterface = ITransparentUpgradeableProxy(address(masterProxy));

        lp = lpDeploy.run(Tester, address(masterProxy));

        //====== Deploy Automation contract
        automation = autoDeploy.run(
            0x66756e2d626173652d6d61696e6e65742d310000000000000000000000000000, //_donId
            15, //_subscriptionId
            2, //_slotId
            0, //_secretsVersion
            0x46d3cb1bb1c87442ef5d35a58248785346864a681125ac50b38aae6001ceb124, //_srcJsHashSum
            0x46d3cb1bb1c87442ef5d35a58248785346864a681125ac50b38aae6001ceb124, //_ethersHashSum
            0xf9B8fc078197181C841c296C876945aaa425B278, //_router,
            address(masterProxy),
            Tester //_owner
        );

        master = masterDeploy.run(
            address(masterProxy),
            address(linkToken),
            0,
            0,
            mockFunctionsRouter,
            address(sourceRouter),
            address(usdc),
            address(lp),
            address(automation),
            Orchestrator,
            Tester
        );

        //Dummy address initially
        childProxy = childProxyDeploy.run(address(usdc), proxyOwner, Tester, "");
        childInterface = ITransparentUpgradeableProxy(address(childProxy));
        child = childDeploy.run(
            Orchestrator, //infra
            address(masterProxy),
            address(childProxy),
            address(linkToken),
            address(destinationRouter),
            chainSelector,
            address(usdc),
            Tester
        );

        ///////////////////////////////////////////////
        /////////////// UPGRADE PROXIES ///////////////
        ///////////////////////////////////////////////
        vm.startPrank(proxyOwner);
        masterInterface.upgradeToAndCall(address(master), "");
        childInterface.upgradeToAndCall(address(child), "");
        vm.stopPrank();

        /////////////////////////////////////////////
        /////////////// LPToken ROLES ///////////////
        /////////////////////////////////////////////
        vm.startPrank(Tester);
        lp.grantRole(keccak256("CONTRACT_MANAGER"), Athena);
        lp.grantRole(keccak256("MINTER_ROLE"), address(masterProxy));
        vm.stopPrank();

        //////////////////////////////////////////////////////
        /////////////// WRAP PROXY & CONTRACTS ///////////////
        //////////////////////////////////////////////////////
        wMaster = ParentPool(payable(address(masterProxy)));
        wChild = ConceroChildPool(payable(address(childProxy)));

        /// FAUCET
        ccipLocalSimulator.requestLinkFromFaucet(address(wMaster), 10 * 10**18);
        ccipLocalSimulator.requestLinkFromFaucet(address(wChild), 10 * 10**18);
        ccipLocalSimulator.supportNewToken(address(usdc));
        usdc.mint(LiquidityProvider, USDC_INITIAL_BALANCE);
        usdc.mint(LiquidityProviderTwo, USDC_INITIAL_BALANCE);
        usdc.mint(LiquidityProviderThree, USDC_INITIAL_BALANCE);
    }

    modifier setters {
        //====== Master Setters
        vm.startPrank(Tester);
        wMaster.setPoolsToSend(chainSelector, address(wChild));
        assertEq(wMaster.s_poolToSendTo(chainSelector), address(wChild));

        wMaster.setConceroContractSender(chainSelector, address(wChild), 1);
        assertEq(wMaster.s_contractsToReceiveFrom(chainSelector, address(wChild)), 1);

        wMaster.setConceroContractSender(chainSelector, address(ConceroDst), 1);
        assertEq(wMaster.s_contractsToReceiveFrom(chainSelector, address(ConceroDst)), 1);

        wMaster.setPoolCap(USDC_INITIAL_BALANCE);

        //====== Child Setters

        wChild.setConceroContractSender(chainSelector, address(wMaster), 1);
        assertEq(wChild.s_contractsToReceiveFrom(chainSelector, address(wMaster)), 1);

        wChild.setConceroContractSender(chainSelector, address(Concero), 1);
        assertEq(wChild.s_contractsToReceiveFrom(chainSelector, address(Concero)), 1);

        //====== Automation Setters

        automation.setForwarderAddress(Forwarder);
        // automation.setDonHostedSecretsVersion()

        vm.stopPrank();
        _;
    }

    error ConceroChildPool_InsufficientBalance();
    //Deposits, start withdraw, take loans, complete withdraw.
    //One liquidity provider -> partial withdraw
    function test_localDepositLiquidity() public setters{
        uint256 amountToDeposit = 150 * 10**6;
        uint256 amountLpShouldBeEmitted = 150 * 10**18;
        uint256 mockedFeeAccrued = 3*10**6;
        uint256 loanAmount = 1 * 10**6;
        uint256 biggerLoanAmount = 20 * 10**6;

        //====== Initiate the Deposit + Cross-chain transfer
        assertEq(usdc.balanceOf(address(wMaster)), 0);
        assertEq(usdc.balanceOf(address(wChild)), 0);

        vm.startPrank(LiquidityProvider);
        usdc.approve(address(wMaster), amountToDeposit);
        wMaster.depositLiquidity(amountToDeposit); //150
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(wMaster)), amountToDeposit/2); //75
        assertEq(usdc.balanceOf(address(wChild)), amountToDeposit/2);

        //===== Check User LP balance
        assertEq(lp.balanceOf(LiquidityProvider), 0);

        //===== Adjust manually the LP emission
        wMaster.updateUSDCAmountManually(LiquidityProvider, lp.totalSupply(), amountToDeposit, amountToDeposit);//150

        //===== Check User LP balance
        assertEq(lp.balanceOf(LiquidityProvider), amountLpShouldBeEmitted);
        
        //===== Mocking some fees
        usdc.mint(address(wMaster), mockedFeeAccrued);
        usdc.mint(address(wChild), mockedFeeAccrued);
        assertEq(usdc.balanceOf(address(wMaster)), (amountToDeposit/2) + mockedFeeAccrued);//75+3
        assertEq(usdc.balanceOf(address(wChild)), (amountToDeposit/2) + mockedFeeAccrued);

        //===== User initiate an withdrawRequest
        //Withdraw only 1/3 of deposited == 150*10**18 / 3;
        vm.prank(LiquidityProvider);
        wMaster.startWithdrawal(50 * 10**18);

        //===== Adjust manually the USDC cross-chain total
        wMaster.updateUSDCAmountEarned(LiquidityProvider, lp.totalSupply(), 50 * 10**18, usdc.balanceOf(address(wChild)));

        //===== Take a loan on child pool
        assertEq(usdc.balanceOf(Athena), 0);

        vm.prank(Orchestrator);
        wChild.orchestratorLoan(address(usdc), loanAmount, Athena);

        assertEq(usdc.balanceOf(Athena), loanAmount);

        //===== Advance in time
        vm.warp(7 days);

        //==== Mock the Automation call to ChildPool
        vm.prank(Messenger);
        wChild.ccipSendToPool(LiquidityProvider, 26_000_000);

        //==== Mock complete withdraw
        vm.startPrank(LiquidityProvider);
        lp.approve(address(wMaster), 50 *10**18);
        wMaster.completeWithdrawal();
        vm.stopPrank();

        assertEq(usdc.balanceOf(LiquidityProvider), USDC_INITIAL_BALANCE - amountToDeposit + 52*10**6);
        assertEq(lp.balanceOf(LiquidityProvider), 100*10**18);

        //===== Take a loan on child pool
        assertEq(usdc.balanceOf(Athena), loanAmount);

        vm.prank(Orchestrator);
        wChild.orchestratorLoan(address(usdc), biggerLoanAmount, Athena);

        assertEq(usdc.balanceOf(Athena), loanAmount + biggerLoanAmount);

        //==== Mock the Automation call to ChildPool
        vm.prank(Messenger);
        vm.expectRevert(abi.encodeWithSelector(ConceroChildPool_InsufficientBalance.selector));
        wChild.ccipSendToPool(LiquidityProvider, (amountToDeposit/2) - ((amountToDeposit/2))/2);
    }

    function test_localMultipleDepositLiquidity() public setters{
        uint256 amountToDeposit = 100 * 10**6;
        uint256 secondAmountToDeposit = 200 * 10**6;
        uint256 thirdAmountToDeposit = 500 * 10**6;
        uint256 mockedFeeAccrued = 5*10**6;
        uint256 loanAmount = 10 * 10**6;
        uint256 biggerLoanAmount = 100 * 10**6;

        vm.prank(Tester);
        wMaster.setPoolCap(USDC_INITIAL_BALANCE * 3); //500*3

        ////////////////////////////////////////////////////////////////
        //====== Initiate First Deposit + Cross-chain transfer ======//
        //////////////////////////////////////////////////////////////
        assertEq(usdc.balanceOf(address(wMaster)), 0);
        assertEq(usdc.balanceOf(address(wChild)), 0);

        vm.startPrank(LiquidityProvider);
        usdc.approve(address(wMaster), amountToDeposit);
        wMaster.depositLiquidity(amountToDeposit);
        vm.stopPrank();

        assertEq(usdc.balanceOf(LiquidityProvider), 400*10**6);
        assertEq(usdc.balanceOf(address(wMaster)), 50*10**6);
        assertEq(usdc.balanceOf(address(wChild)), 50*10**6);
        
        //===== Adjust manually the LP emission
        wMaster.updateUSDCAmountManually(LiquidityProvider, lp.totalSupply(), amountToDeposit, 0); //Not taking the user deposit in account

        //===== Check User LP balance
        uint256 liquidityProviderFirstLpBalance = lp.balanceOf(LiquidityProvider);

        assertEq(liquidityProviderFirstLpBalance, 100*10**18);

        //===== Mocking some fees
        usdc.mint(address(wMaster), mockedFeeAccrued);
        usdc.mint(address(wChild), mockedFeeAccrued);

        /////////////////////////////////////////////////////////////////
        //====== Initiate Second Deposit + Cross-chain transfer ======//
        ///////////////////////////////////////////////////////////////
        vm.startPrank(LiquidityProviderTwo);
        usdc.approve(address(wMaster), secondAmountToDeposit);
        wMaster.depositLiquidity(secondAmountToDeposit);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(LiquidityProviderTwo)), 300*10**6);
        assertEq(usdc.balanceOf(address(wMaster)), 155*10**6);
        assertEq(usdc.balanceOf(address(wChild)), 155*10**6);
        
        //===== Adjust manually the LP emission
        wMaster.updateUSDCAmountManually(LiquidityProviderTwo, lp.totalSupply(), secondAmountToDeposit, 110*10**6); //Not taking the user deposit in account

        //===== Check User LP balance
        uint256 liquidityProviderTwoFirstLpBalance = lp.balanceOf(LiquidityProviderTwo);
        assertEq(liquidityProviderTwoFirstLpBalance, 181818181818181818181);

        //===== Mocking some fees
        usdc.mint(address(wMaster), mockedFeeAccrued);
        usdc.mint(address(wChild), mockedFeeAccrued);

        ////////////////////////////////////////////////////////////////
        //====== Initiate third Deposit + Cross-chain transfer ======//
        //////////////////////////////////////////////////////////////
        vm.startPrank(LiquidityProviderThree);
        usdc.approve(address(wMaster), thirdAmountToDeposit);
        wMaster.depositLiquidity(thirdAmountToDeposit);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(LiquidityProviderThree)), 0);
        assertEq(usdc.balanceOf(address(wMaster)), 410*10**6);
        assertEq(usdc.balanceOf(address(wChild)), 410*10**6);
        
        //===== Adjust manually the LP emission
        wMaster.updateUSDCAmountManually(LiquidityProviderThree, lp.totalSupply(), thirdAmountToDeposit, 320*10**6); //Not taking the user deposit in account

        //===== Check User LP balance
        uint256 liquidityProviderThreeLpBalance = lp.balanceOf(LiquidityProviderThree);
        assertEq(liquidityProviderThreeLpBalance, 440_340_909_090_909_090_907);

        //===== Mocking some fees
        usdc.mint(address(wMaster), mockedFeeAccrued);
        usdc.mint(address(wChild), mockedFeeAccrued);

        /////////////////////////////////////////////////////////////////
        //====== Initiate fourth Deposit + Cross-chain transfer ======//
        ///////////////////////////////////////////////////////////////
        uint256 fourthDepositAmount = USDC_INITIAL_BALANCE - amountToDeposit;

        vm.startPrank(LiquidityProvider);
        usdc.approve(address(wMaster), fourthDepositAmount);
        wMaster.depositLiquidity(fourthDepositAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(LiquidityProvider)), 0);
        assertEq(usdc.balanceOf(address(wMaster)), 615*10**6);
        assertEq(usdc.balanceOf(address(wChild)), 615*10**6);
        
        //===== Adjust manually the LP emission
        wMaster.updateUSDCAmountManually(LiquidityProvider, lp.totalSupply(), fourthDepositAmount, 830*10**6); //Not taking the user deposit in account

        //===== Check User LP balance
        uint256 liquidityProviderSecondBalanceLpBalance = lp.balanceOf(LiquidityProvider);
        assertEq(liquidityProviderSecondBalanceLpBalance, liquidityProviderFirstLpBalance + 348028477546549835705);

        //===== Mocking some fees
        usdc.mint(address(wMaster), mockedFeeAccrued);
        usdc.mint(address(wChild), mockedFeeAccrued);

        ////////////////////////////////////////////////////////////////
        //====== Initiate fifth Deposit + Cross-chain transfer ======//
        //////////////////////////////////////////////////////////////
        uint256 fifthDepositAmount = USDC_INITIAL_BALANCE - secondAmountToDeposit; //500-200

        vm.startPrank(LiquidityProviderTwo);
        usdc.approve(address(wMaster), fifthDepositAmount);
        wMaster.depositLiquidity(fifthDepositAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(LiquidityProviderTwo)), 0);
        assertEq(usdc.balanceOf(address(wMaster)), 770*10**6);
        assertEq(usdc.balanceOf(address(wChild)), 770*10**6);

        //===== Adjust manually the LP emission
        wMaster.updateUSDCAmountManually(LiquidityProviderTwo, lp.totalSupply(), fifthDepositAmount, 1240*10**6); //Something is breaking here.

        //===== Check User LP balance
        assertEq(lp.balanceOf(LiquidityProviderTwo), liquidityProviderTwoFirstLpBalance + 258916347207009857611);

        //===== Mocking some fees
        usdc.mint(address(wMaster), mockedFeeAccrued);
        usdc.mint(address(wChild), mockedFeeAccrued);

        //===== Total USDC balance
        console2.log("Master + Child", usdc.balanceOf(address(wMaster)) + usdc.balanceOf(address(wChild)));

        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        ////////////////////////////////////////////////////////////// WITHDRAW //////////////////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        //==== LiquidityProvider
        uint256 liquidityProviderBalanceBeforeWithdraw = lp.balanceOf(LiquidityProvider);

        vm.prank(LiquidityProvider);
        wMaster.startWithdrawal(liquidityProviderBalanceBeforeWithdraw);

        vm.warp(7 days);
        uint256 poolBalanceBeforeFirstWithdraw = usdc.balanceOf(address(wMaster)) + usdc.balanceOf(address(wChild));
        wMaster.updateUSDCAmountEarned(LiquidityProvider, lp.totalSupply(), liquidityProviderBalanceBeforeWithdraw, usdc.balanceOf(address(wChild)));

        uint256 liquidityProviderUSDCAmountEarned = 522490477;

        vm.prank(Messenger);
        wChild.ccipSendToPool(LiquidityProvider, 261245238);

        vm.startPrank(LiquidityProvider);
        lp.approve(address(wMaster), liquidityProviderBalanceBeforeWithdraw);
        wMaster.completeWithdrawal();
        vm.stopPrank();

        assertEq(wMaster.s_withdrawRequests(), 0);

        assertEq(lp.balanceOf(LiquidityProvider), 0);
        assertEq(usdc.balanceOf(LiquidityProvider), liquidityProviderUSDCAmountEarned);
        
        //===== Total USDC balance
        console2.log("Master + Child", usdc.balanceOf(address(wMaster)) + usdc.balanceOf(address(wChild)));

        //==== LiquidityProviderTwo
        uint256 liquidityProviderTwoBalanceBeforeWithdraw = lp.balanceOf(LiquidityProviderTwo);

        vm.prank(LiquidityProviderTwo);
        wMaster.startWithdrawal(liquidityProviderTwoBalanceBeforeWithdraw);

        vm.warp(7 days);
        uint256 poolBalanceBeforeSecondWithdraw = usdc.balanceOf(address(wMaster));
        wMaster.updateUSDCAmountEarned(LiquidityProviderTwo, lp.totalSupply(), liquidityProviderTwoBalanceBeforeWithdraw,  usdc.balanceOf(address(wChild)));

        uint256 liquidityProviderTwoUSDCAmountEarned = 513984281;

        vm.prank(Messenger);
        wChild.ccipSendToPool(LiquidityProviderTwo, 256992140);

        vm.startPrank(LiquidityProviderTwo);
        lp.approve(address(wMaster), liquidityProviderTwoBalanceBeforeWithdraw);
        wMaster.completeWithdrawal();
        vm.stopPrank();

        assertEq(wMaster.s_withdrawRequests(), 0);

        assertEq(lp.balanceOf(LiquidityProviderTwo), 0);
        assertEq(usdc.balanceOf(LiquidityProviderTwo), liquidityProviderTwoUSDCAmountEarned);
        
        //===== Total USDC balance
        console2.log("Master + Child", usdc.balanceOf(address(wMaster)) + usdc.balanceOf(address(wChild)));
        
        //==== LiquidityProviderThree
        uint256 liquidityProviderThreeBalanceBeforeWithdraw = lp.balanceOf(LiquidityProviderThree);

        vm.prank(LiquidityProviderThree);
        wMaster.startWithdrawal(liquidityProviderThreeBalanceBeforeWithdraw);

        vm.warp(7 days);
        uint256 poolBalanceBeforeThirdWithdraw = usdc.balanceOf(address(wMaster));
        wMaster.updateUSDCAmountEarned(LiquidityProviderThree, lp.totalSupply(), liquidityProviderThreeBalanceBeforeWithdraw, usdc.balanceOf(address(wChild)));

        uint256 liquidityProviderThreeUSDCAmountEarned = 513525242;

        vm.prank(Messenger);
        wChild.ccipSendToPool(LiquidityProviderThree, 256762622);

        assertEq(usdc.balanceOf(address(wMaster)), 513_525_242);
        assertEq(usdc.balanceOf(address(wChild)), 0);        

        vm.startPrank(LiquidityProviderThree);
        lp.approve(address(wMaster), liquidityProviderThreeBalanceBeforeWithdraw);
        wMaster.completeWithdrawal();
        vm.stopPrank();

        assertEq(lp.balanceOf(LiquidityProviderThree), 0);
        assertEq(usdc.balanceOf(LiquidityProviderThree), liquidityProviderThreeUSDCAmountEarned);
        
        //===== Total USDC balance
        console2.log("Master + Child", usdc.balanceOf(address(wMaster)) + usdc.balanceOf(address(wChild)));
    }

}