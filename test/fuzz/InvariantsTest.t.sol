// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Have our invariant aka properties

// what are our invariants

// 1. The total supply of DSC should always be less than total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant 
import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { console } from "forge-std/console.sol";
import { Handler } from "./Handler.t.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    Handler public handler;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThatTotalSupplyUsd() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposited = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));
        
     

        assert(dsce.getUsdValue(weth, wethDeposited) + dsce.getUsdValue(wbtc, wbtcDeposited)
         >= totalSupply);
    }
}