// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
/*
 * @title: DECEngine
 * @author: nate
 *
 * This system is designed to be as minimal as possible, and have the tokens maintain
 * a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard{
    error DSCEngine_NeedsMoreThanZero();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine_TokenNotAllowed(address token);
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine_MintFailed();
    error DSCEngine_HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    // @dev Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    /// @dev Amount of DSC minted by user
    mapping(address user => uint256 amount) private s_DSCMinted;
    /// @dev If we know exactly how many tokens we have, we could make this immutable!
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount); 

    modifier moreThanZero(uint256 amount) {
        if(amount == 0) revert DSCEngine_NeedsMoreThanZero(); 
        _;
    }

    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)) revert DSCEngine_TokenNotAllowed(token);
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if(tokenAddresses.length != priceFeedAddresses.length) revert DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        // USD Price Feeds
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(priceFeedAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }


    function depositCollateralAndMintDsc() external {}
    
    /* 
     * @notice follows CEI(check effects interactions)
     * @param token The address of the token to deposit as collateral
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(
        address token, 
        uint256 amount) 
        external 
        moreThanZero(amount) 
        isAllowedToken(token) 
        nonReentrant
    {
        s_collateralDeposited[msg.sender][token] += amount;
        emit CollateralDeposited(msg.sender, token, amount);
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert DSCEngine_TransferFailed();
    }

    function redeemCollateralForDsc() external {}
    
    function redeemCollateral() external {}

    function mintDsc(uint256 amount) external moreThanZero(amount) nonReentrant {
        s_DSCMinted[msg.sender] += amount;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amount);
        if(!minted) revert DSCEngine_MintFailed();
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////

    function _getAccountInfo(address user) private view 
        returns(uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }
    /*
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns(uint256) {
       // total DSC minted
       // total collateral VALUE
       (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInfo(user);
       uint256 collateralAdjustedForthreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
       return (collateralAdjustedForthreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
       uint256 userHealthFactor = _healthFactor(user);
       if (userHealthFactor < MIN_HEALTH_FACTOR) {
        revert DSCEngine_BreaksHealthFactor(userHealthFactor);
       }
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // If 1 ETH = 1000 USD
        // Then the returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }


    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited,
        // and map it to the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    )
        external
        view
        returns (uint256)
    {
        return _getUsdValue(token, amount);
    }




}