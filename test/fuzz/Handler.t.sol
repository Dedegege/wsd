// SPDX-License-Identifier: MIT
// handler is going to narrow down the way we call functiom

pragma solidity 0.8.20;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Test } from "forge-std/Test.sol";
// import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol"; Updated mock location
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { DSCEngine, AggregatorV3Interface } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
// import {Randomish, EnumerableSet} from "../Randomish.sol"; // Randomish is not found in the codebase, EnumerableSet
// is imported from openzeppelin
import { console } from "forge-std/console.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
      dsce = _dscEngine;
      dsc = _dsc;
      address[] memory collateralTokens = dsce.getCollateralTokens();
      weth = ERC20Mock(collateralTokens[0]);
      wbtc = ERC20Mock(collateralTokens[1]);

      ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
      btcUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
      amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
      ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

      vm.startPrank(msg.sender);
      collateral.mint(msg.sender, amountCollateral);
      collateral.approve(address(dsce), amountCollateral);
      dsce.depositCollateral(address(collateral), amountCollateral);
      vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
      amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
      ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
      vm.startPrank(msg.sender);
      uint256 maxCollateralToRedeem = dsce.getCollateralAmount(address(collateral));
      if (maxCollateralToRedeem == 0) {
        return;
      }
      amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);
      dsce.redeemCollateral(address(collateral), amountCollateral);
      vm.stopPrank();
    }

    function updateCollateralPrice(uint96 newPrice) public {
      int256 newPriceInt = int256(uint256(newPrice));
      ethUsdPriceFeed.updateAnswer(newPriceInt);
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
      return collateralSeed % 2 == 0 ? weth : wbtc;
    }
}

