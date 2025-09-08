// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// Holds invariants (i.e values that should always hold)

// 1. Total supply of dsc should be less than total value of collateral

// 2. Getter view functions should never revert  <- evergreen invariant

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    // DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        // get balance of both collateral tokens
        (, , weth, wbtc, ) = config.activeNetworkconfig();
        // for open fuzzing
        // targetContract(address(engine));

        handler = new Handler(engine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all collateral in the protocol
        // compare it to all the debt (dsc)

        // total supply of all dsc
        uint256 totalSupply = dsc.totalSupply();
        // get total amount of weth & wbtc in dsc contract
        uint totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        // get $ value of weth & wbtc
        uint wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply: ", totalSupply);
        console.log("times mint is called", handler.timesMintIsCalled());

        // main invariant
        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_summary() public view {
        handler.callSummary();
    }

    // ensure no function combination breaks any of our getters
    // layup invariant
    // A failure in a basic getter function often signals an underlying invalid or unexpected system state reached during the fuzzing process.
    function invariant_gettersShouldNotRevert() public view {
        engine.getLiquidationBonus();
        engine.getPrecision();
    }
}

// Handler handles how we make calls to engine
// e.g don't call redeemCollateral unless there is collateral to redeem
// Invariants contract target contract will be the handler
