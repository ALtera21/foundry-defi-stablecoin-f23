// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizeStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_DSC_TO_MINT_HEALTHY = 10000 ether; // <==10k dollar, since we have 20k collateral in USD

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce,) = deployer.run();
    }

    function testMintFromDsc() public {
        vm.startPrank(address(dsce));
        dsc.mint(USER, AMOUNT_DSC_TO_MINT_HEALTHY);
        assertEq(ERC20Burnable(dsc).balanceOf(USER), AMOUNT_DSC_TO_MINT_HEALTHY);
    }

    function testBurnFromDsc() public {
        vm.startPrank(address(dsce));
        dsc.mint(address(dsce), AMOUNT_DSC_TO_MINT_HEALTHY);
        dsc.burn(AMOUNT_DSC_TO_MINT_HEALTHY);
        assertEq(ERC20Burnable(dsc).balanceOf(address(dsce)), 0);
        vm.stopPrank();
    }

    function testMintNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.mint(USER, AMOUNT_DSC_TO_MINT_HEALTHY);
        assertEq(ERC20Burnable(dsc).balanceOf(USER), 0);
    }

    function testBurnNotOwner() public {
        vm.startPrank(address(dsce));
        dsc.mint(address(dsce), AMOUNT_DSC_TO_MINT_HEALTHY);
        vm.stopPrank();
        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(USER);
        dsc.burn(AMOUNT_DSC_TO_MINT_HEALTHY);
        vm.stopPrank();
    }
}