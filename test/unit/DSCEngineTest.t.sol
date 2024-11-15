// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizeStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public USER_2 = makeAddr("user_2");
    address public USER_WITH_BAD_HEALTH_FACTOR = makeAddr("user_with_bad_health_factor");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT_HEALTHY = 10000 ether; // <==10k dollar, since we have 20k collateral in USD
    uint256 public constant AMOUNT_DSC_TO_MINT_UNHEALTHY = 12000 ether;
    uint256 public constant COLLATERAL_REDEEMED = 6 ether;
    uint256 public constant LIQUIDATION_AMOUNT_IN_USD = 8000 ether;
    uint256 public constant LIQUIDATION_AMOUNT_IN_USD_NOT_IMPROVED = 1;
    uint256 public constant AMOUNT_TO_APPROVE_DSC = 20000 ether; // <== This one needs to be big, since we only count with DSC value in USD and not in the amount

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE_NEW = 500e8;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(USER_2, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(USER_WITH_BAD_HEALTH_FACTOR, STARTING_ERC20_BALANCE);
    }

    //----------------------------------------//
    // CONSTRUCTOR TEST
    //----------------------------------------//

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLenght.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testPriceFeedOfTokenAddressesIsCorrect() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        DSCEngine testDsc = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        assertEq(testDsc.getPriceFeedAddresses(tokenAddresses, 0), priceFeedAddresses[0]);
        console.log(testDsc.getPriceFeedAddresses(tokenAddresses, 0));
        console.log(priceFeedAddresses[0]);
    }

    function testTokenAddressesArrayBeingPushed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        DSCEngine testDsc = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        assertEq(testDsc.getCollateralTokensAddresses(0), weth);
        console.log(testDsc.getCollateralTokensAddresses(0));
        console.log(weth);
    }

    //----------------------------------------//
    // PRICE TEST
    //----------------------------------------//

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000 = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    //----------------------------------------//
    // DEPOSIT COLLATERAL TEST
    //----------------------------------------//

    function testRevertsIfCollateraZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    function testDepositCollateralRevertedTransactionFailed() public {
        vm.startPrank(USER);

    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier mintDsc() {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT_HEALTHY);
        vm.stopPrank();
        _;
    }

    modifier unhealthyUserDepositAndMintDsc {

        vm.startPrank(USER_WITH_BAD_HEALTH_FACTOR); 
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL); 
        // ^== 2.] then, we need USER_WITH_BAD_HEALTH_FACTOR to deposit collateral, now we have unhealthy user
        vm.stopPrank();

        dsce.simulaterDscMinted(USER_WITH_BAD_HEALTH_FACTOR, AMOUNT_DSC_TO_MINT_UNHEALTHY); 
        // ^== 3.] now we simulate USER_WITH_BAD_HEALTH_FACTOR to 'ever' mint unhealthy amount of dsc
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(AMOUNT_COLLATERAL, dsce.getTokenAmountFromUsd(weth, collateralValueInUsd));
    }

    function testCanDepositCollateralAndChecksStorageCollateralDeposited() public depositedCollateral {
        assertEq(dsce.getCollateralDeposited(USER, weth), AMOUNT_COLLATERAL);
    }

    function testDepositCollateralAndMintDsc() public depositedCollateral mintDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        console.log(totalDscMinted);
        console.log(collateralValueInUsd);
        console.log(dsce.getHealthFactor(USER));
        // 10000e18        000000000000000000
        // 20000e18        000000000000000000
        // 1e18            000000000000000000
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT_HEALTHY);
        assertEq(AMOUNT_COLLATERAL, dsce.getTokenAmountFromUsd(weth, collateralValueInUsd));
    }

    function testDepositCollateralAndMintDscMainFunctionIsWorking() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.despositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT_HEALTHY);
    }

    function testDepositCollateralAndMintDscFailedIfDepositCollateralAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.despositCollateralAndMintDsc(weth, 0, AMOUNT_DSC_TO_MINT_HEALTHY);
    }

    function testDepositCollateralAndMintDscFailedIfDepositCollateralWithNotAllowedToken() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.despositCollateralAndMintDsc(address(123), AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT_HEALTHY);
    }

    function testRevertsIdDepositCollateralAndMintDscBreaksHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                dsce.calculateHealthFactor(AMOUNT_DSC_TO_MINT_UNHEALTHY, dsce.getUsdValue(weth, AMOUNT_COLLATERAL))
            )
        );
        dsce.despositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT_UNHEALTHY);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        assertEq(totalDscMinted, 0);
        assertEq(dsce.getTokenAmountFromUsd(weth, collateralValueInUsd), 0);
    }

    //----------------------------------------//
    // REDEEM COLLATERAL TEST
    //----------------------------------------//

    function testRedeemCollateral() public depositedCollateral {
        vm.prank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
    }

    function testRedeemCollateralFailedIfCollateralToRedeemIsZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralFailedIfBreaksHealthFactor() public depositedCollateral mintDsc {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                dsce.calculateHealthFactor(AMOUNT_DSC_TO_MINT_HEALTHY, dsce.getUsdValue(weth, (AMOUNT_COLLATERAL - COLLATERAL_REDEEMED)))
            )
        );
        dsce.redeemCollateral(weth, COLLATERAL_REDEEMED);
    }

    function testRedeemCollateralAndChecksCollateralDepositedShouldBe4AfterRedeemed6() public depositedCollateral {
        vm.startPrank(USER);
        assertEq(dsce.getCollateralDeposited(USER, weth), AMOUNT_COLLATERAL);
        dsce.redeemCollateral(weth, COLLATERAL_REDEEMED);
        assertEq(dsce.getCollateralDeposited(USER, weth), 4 ether);
    } 

    //----------------------------------------//
    // MINT DSC TEST
    //----------------------------------------//

    function testMintDsc() public depositedCollateral mintDsc {}

    function testRevertsIfMintDscBreaksHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                dsce.calculateHealthFactor(AMOUNT_DSC_TO_MINT_UNHEALTHY, dsce.getUsdValue(weth, AMOUNT_COLLATERAL))
            )
        );
        dsce.mintDsc(AMOUNT_DSC_TO_MINT_UNHEALTHY);
    }

    //----------------------------------------//
    // BURN DSC TEST
    //----------------------------------------//

    function testBurnDscOnly() public depositedCollateral mintDsc {
        vm.startPrank(USER);
        ERC20Mock(address(dsc)).approve(address(dsce), AMOUNT_TO_APPROVE_DSC);
        dsce.burnDsc(1);
        vm.stopPrank();
    }

    function testBurnDscFailsIfAmounttoBurnIsZero() public depositedCollateral mintDsc {
        vm.startPrank(USER);
        ERC20Mock(address(dsc)).approve(address(dsce), AMOUNT_TO_APPROVE_DSC);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnDscFailesIfUserNeverMintingDsc() public depositedCollateral {
        vm.startPrank(USER);
        ERC20Mock(address(dsc)).approve(address(dsce), AMOUNT_TO_APPROVE_DSC);
        vm.expectRevert();
        dsce.burnDsc(1);
        vm.stopPrank();
    }

    function testBurnDscFailesIfUsersDscBalanceIsZeroAfterMintingDsc() public depositedCollateral mintDsc {
        console.log(ERC20Mock(address(dsc)).balanceOf(USER));
        console.log(ERC20Mock(address(dsc)).balanceOf(USER_2));
        vm.startPrank(USER);
        ERC20Mock(address(dsc)).approve(address(dsce), AMOUNT_TO_APPROVE_DSC);
        ERC20Mock(address(dsc)).transfer(USER_2, AMOUNT_DSC_TO_MINT_HEALTHY);
        console.log(ERC20Mock(address(dsc)).balanceOf(USER));
        console.log(ERC20Mock(address(dsc)).balanceOf(USER_2));
        vm.expectRevert();
        dsce.burnDsc(1);
        vm.stopPrank();
    }

    //----------------------------------------//
    // GET ACCOUNT INFO TEST
    //----------------------------------------//

    function testGetAccountInfoWithNoInfo() public {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        vm.stopPrank();
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
    }

    function testGetAccountInfoWithInfo() public depositedCollateral mintDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        console.log(totalDscMinted);
        console.log(collateralValueInUsd);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT_HEALTHY);
        assertEq(collateralValueInUsd, dsce.getUsdValue(weth, AMOUNT_COLLATERAL));
        //  1e18       000000000000000000
        //  20000e18   000000000000000000
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 actualCollateralValue = dsce.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = 20000e18;
        assertEq(actualCollateralValue, expectedCollateralValue);
    }

    //----------------------------------------//
    // GET HEALTH FACTOR TEST
    //----------------------------------------//

    function testGetHealthFactorWithDepositAndMint() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.despositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT_HEALTHY);
        uint256 expectedHealthFactor = 1 ether;
        assertEq(dsce.getHealthFactor(USER), expectedHealthFactor);
    }

    function testGetHealthFactorWhenDepositOnly() public depositedCollateral {
        // ^=== The error that patrick mentined was found here
        vm.startPrank(USER);
        console.log(dsce.getHealthFactor(USER));
        uint256 expectedHealthFactor = 1 ether;
        assertEq(dsce.getHealthFactor(USER), expectedHealthFactor);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorISBroken() public unhealthyUserDepositAndMintDsc {
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                dsce.calculateHealthFactor(AMOUNT_DSC_TO_MINT_UNHEALTHY, dsce.getUsdValue(weth, AMOUNT_COLLATERAL))
            )
        );
        dsce.getRevertIfHealthFactorIsBroken(USER_WITH_BAD_HEALTH_FACTOR);
    }

    function testCalculateHealthFactor() public {
        uint256 expectedHealthFactor = 1 ether;
        assertEq(dsce.calculateHealthFactor(0, AMOUNT_COLLATERAL), expectedHealthFactor);
    }

    //----------------------------------------//
    // LIQUIDATION TEST
    //----------------------------------------//

    function testLiquidationOnly() public depositedCollateral mintDsc unhealthyUserDepositAndMintDsc{ 
        // ^== 1.] first, we need USER to have DSC to burn when liquidating, (step 2 & 3 on modifier unhealthyUserDepositAndMintDsc)

        vm.startPrank(USER); // <== 5.] Now, we let USER to execute the function liquidate()
        uint256 UserDSBalance = ERC20Mock(address(dsc)).balanceOf(USER);
        uint256 UserEthBalance = ERC20Mock(weth).balanceOf(USER);


        console.log(ERC20Mock(weth).balanceOf(address(dsce)));
        // 20e18       000000000000000000
        console.log(UserEthBalance);
        // 0
        console.log(UserDSBalance);
        // 10000e18    000000000000000000


        ERC20Mock(address(dsc)).approve(address(dsce), AMOUNT_TO_APPROVE_DSC);
        dsce.liquidate(weth, USER_WITH_BAD_HEALTH_FACTOR, LIQUIDATION_AMOUNT_IN_USD);
        // ^== 6.] approval of weth for _redeemCollateral() alreade being set in modifier depositCollateral
        // Now we only need to approve dsc token for _burnDsc() and voala, it took 2 days and i am tired

        uint256 UserEthBalanceAfter = ERC20Mock(weth).balanceOf(USER);
        uint256 UserDSBalanceAfter = ERC20Mock(address(dsc)).balanceOf(USER);


        console.log(ERC20Mock(weth).balanceOf(address(dsce)));
        // 15.6e18          00000000000000000
        console.log(UserEthBalanceAfter);
        // 4.4e18           00000000000000000
        console.log(UserDSBalanceAfter);
        // 2000e18          000000000000000000
        vm.stopPrank();
    }

    function testLiquidationRevertIfHealthFactorNotImproved() public depositedCollateral mintDsc unhealthyUserDepositAndMintDsc {
        vm.startPrank(USER);
        ERC20Mock(address(dsc)).approve(address(dsce), AMOUNT_TO_APPROVE_DSC);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dsce.liquidate(weth, USER_WITH_BAD_HEALTH_FACTOR, LIQUIDATION_AMOUNT_IN_USD_NOT_IMPROVED);
        vm.stopPrank();
    } 

    function testLiquidationRevertIfHealthFactorOk() public depositedCollateral mintDsc {
        vm.startPrank(USER_2);
        console.log(dsce.getHealthFactor(USER));
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, COLLATERAL_REDEEMED);
    }

    function testLiquidationRevertIfCollateralToLiquidateIsZero() public depositedCollateral mintDsc {
        vm.startPrank(USER_2);
        console.log(dsce.getHealthFactor(USER));
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, 0);
    }
}
