// SPDX-License-Identifier: MIT
//Handler is going to narrow down the way we call functions

/** @notice To recreate possible alternative code, remove the comments and commented on other scenario.
*/

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizeStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract Handler is Test { 
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;

    // /** [[[1]]] */
    // ERC20Mock weth;
    // ERC20Mock wbtc;

     /** [[[2]]] */
    address weth;
    address wbtc;

    uint256 public timesMintIsCalled;
    uint256 public timesRedeemIsCalled;
    uint256 public timesLiquidateIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc, HelperConfig _config) {
        dsce = _dscEngine;
        dsc = _dsc;
        config = _config;

        // /** [[[1]]] */
        // address[] memory collateralTokens = dsce.getCollateralAddress();
        // weth = ERC20Mock(collateralTokens[0]);
        // wbtc = ERC20Mock(collateralTokens[1]);

        /** [[[2]]] */
        weth = dsce.getCollateralTokensAddresses(0);
        wbtc = dsce.getCollateralTokensAddresses(1);

        ethUsdPriceFeed = MockV3Aggregator(dsce.geTokenPriceFeed(weth));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);

        // /** [[[1]]] */
        // ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // collateral.mint(msg.sender, amountCollateral);
        // collateral.approve(address(dsce), amountCollateral);
        // dsce.depositCollateral(address(collateral), amountCollateral);

        /** [[[2]]] */
        address collateral = _getCollateralFromSeed(collateralSeed);
        ERC20Mock(collateral).mint(msg.sender, amountCollateral);
        ERC20Mock(collateral).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(collateral, amountCollateral);

        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    /**
     * @notice The deposited amount cannot be 0 unless the invariant called the redeemCollateral first
     * @notice If the deposited amount is 0, then the maxCollateralToRedeem = 0, and since it assume it != 0, then it just let it passed
     * @notice But, if the invariant test called depositCollateral first, now it can properly redeem it
     */
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral/*, uint256 addressSeed*/) public {
        // // /** [[[1]]] */
        // // if(usersWithCollateralDeposited.length == 0) {
        // //     return;
        // // }
        // // address redeemer = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        // address collateral = _getCollateralFromSeed(collateralSeed);
        // // uint256 maxCollateralToRedeem = dsce.getCollateralDeposited(collateral, redeemer);
        // uint256 maxCollateralToRedeem = dsce.getCollateralDeposited(collateral, msg.sender);
        // amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        // if(amountCollateral == 0){
        //     return;
        // }
        // // vm.startPrank(redeemer);
        // dsce.redeemCollateral(collateral, amountCollateral);
        // // vm.stopPrank();


        // /** [[[2]]] */
        amountCollateral = bound(amountCollateral, 0, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = ERC20Mock(_getCollateralFromSeed(collateralSeed));
        dsce.redeemCollateral(address(collateral), amountCollateral);

        timesRedeemIsCalled++;

        
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if(usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        vm.assume(maxDscToMint > 0);
        amount = bound(amount, 1, uint256(maxDscToMint));
        
        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();

        timesMintIsCalled++;
    }

    function liquidate(uint256 addressSeed, uint256 addressLiquidatorSeed, uint256 collateralSeed, uint256 debtToCover) public {
        if(usersWithCollateralDeposited.length == 0) {
            return;
        }
        address liquidator = usersWithCollateralDeposited[addressLiquidatorSeed % usersWithCollateralDeposited.length];
        address badHealthFactorUser = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        vm.assume(liquidator != badHealthFactorUser);
        vm.assume(dsce.getHealthFactor(badHealthFactorUser) <= 1e18);
        address collateral = _getCollateralFromSeed(collateralSeed);
        debtToCover = bound(debtToCover, 1, dsce.getCollateralDeposited(badHealthFactorUser, collateral));
        vm.prank(liquidator);
        dsce.liquidate(collateral, badHealthFactorUser, debtToCover);
        vm.stopPrank();
        timesLiquidateIsCalled++;
    }
    // This breaks out invariant test
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 oldPrice = config.ETH_USD_PRICE();
    //     vm.assume(((int256(int96(newPrice))*1e16) / oldPrice) > 1e16*90/100);
    //     int256 newPriceInt = int256(int96(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper functions

    /** [[[1]]] */
    // function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock) {
    //     if(collateralSeed % 2 == 0) {
    //         return weth;
    //     }
    //     return wbtc;
    // }

    /** [[[2]]] */
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(address) {
        if(collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}