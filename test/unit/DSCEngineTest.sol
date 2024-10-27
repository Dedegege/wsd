// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { MockMoreDebtDSC } from "../mocks/MockMoreDebtDSC.sol";
import { MockFailedMintDSC } from "../mocks/MockFailedMintDSC.sol";
import { MockFailedTransferFrom } from "../mocks/MockFailedTransferFrom.sol";
import { MockFailedTransfer } from "../mocks/MockFailedTransfer.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract DSCEngineTest is StdCheats, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public config;
    

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;
    address[] public tokenAddressses;
    address[] public priceFeedAddresses;
    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public  {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddressses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine.DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector
        );
        new DSCEngine(tokenAddressses,priceFeedAddresses,address(dsc));
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(
            DSCEngine.DSCEngine_NeedsMoreThanZero.selector
        );
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock random = new ERC20Mock("RAN", "RAN", user, 100e18);
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine_TokenNotAllowed.selector,address(random))
        );
        dsce.depositCollateral(address(random), amountCollateral);
        vm.stopPrank();
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30_000e18;
        uint256 usdValue = dsce.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

    // this test needs it's own setup
    function testRevertsIfTransferFromFails() public {
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom(address(this));
        tokenAddressses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockDsce = new DSCEngine(tokenAddressses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(user, amountCollateral);
        mockDsc.transferOwnership(address(mockDsce));

        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce),amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine_TransferFailed.selector);
        mockDsce.depositCollateral(address(mockDsc), amountCollateral);
        vm.stopPrank();
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 balance = dsc.balanceOf(user);
        assertEq(balance, 0);
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInfo(user);
        uint expectedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectedAmount, amountCollateral);
        assertEq(totalDscMinted, 0);
    }

    function testGetCollateralAmount() public depositedCollateral {
        vm.startPrank(user);
        uint amount = dsce.getCollateralAmount(weth);       
        assertEq(amount, amountCollateral);
        vm.stopPrank();
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public depositedCollateral {
        (, int256 price, , , ) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = (amountCollateral * (uint256(price) * 1e10)) / 1e18;
        vm.startPrank(user);
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.mintDsc(amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        
    }

    ///////////////////////////////////
    // mintDsc Tests //
    ///////////////////////////////////
    // This test needs it's own custom setup
    function testRevertsIfMintFails() public {
       
    }

    function testRevertsIfMintAmountIsZero() public {
        
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        // 0xe580cc6100000000000000000000000000000000000000000000000006f05b59d3b20000
        // 0xe580cc6100000000000000000000000000000000000000000000003635c9adc5dea00000
        
    }

    function testCanMintDsc() public depositedCollateral {
        
    }

    ///////////////////////////////////
    // burnDsc Tests //
    ///////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public {
        
    }

    function testCantBurnMoreThanUserHas() public {
        
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        
    }

    ///////////////////////////////////
    // redeemCollateral Tests //
    //////////////////////////////////

    // this test needs it's own setup
    function testRevertsIfTransferFails() public {
       
       
    }

    function testRevertsIfRedeemAmountIsZero() public {
       
    }

    function testCanRedeemCollateral() public depositedCollateral {
        
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        
    }
    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        
    }

    function testCanRedeemDepositedCollateral() public {
        
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test needs it's own setup
    function testMustImproveHealthFactorOnLiquidation() public {
        
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        
    }

    modifier liquidated() {
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        
    }

    function testUserHasNoMoreDebt() public liquidated {
       
    }

    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////
    function testGetCollateralTokenPriceFeed() public {
        
    }

    function testGetCollateralTokens() public {
       
    }

    function testGetMinHealthFactor() public {
        
    }

    function testGetLiquidationThreshold() public {
        
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        
    }

    function testGetCollateralBalanceOfUser() public {
        
    }

    function testGetAccountCollateralValue() public {
        
    }

    function testGetDsc() public {
        
    }

    function testLiquidationPrecision() public {
        
    }

    // How do we adjust our invariant tests for this?
    // function testInvariantBreaks() public depositedCollateralAndMintedDsc {
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(0);

    //     uint256 totalSupply = dsc.totalSupply();
    //     uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(dsce));
    //     uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

    //     uint256 wethValue = dsce.getUsdValue(weth, wethDeposted);
    //     uint256 wbtcValue = dsce.getUsdValue(wbtc, wbtcDeposited);

    //     console.log("wethValue: %s", wethValue);
    //     console.log("wbtcValue: %s", wbtcValue);
    //     console.log("totalSupply: %s", totalSupply);

    //     assert(wethValue + wbtcValue >= totalSupply);
    // }
}

