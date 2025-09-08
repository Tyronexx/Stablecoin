// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.18;

// // 1. Total supply of dsc should be less than total value of collateral

// // 2. Getter view functions should never revert  <- evergreen invariant

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDSC deployer;
//     DSCEngine engine;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, engine, config) = deployer.run();
//         // get balance of both collateral tokens
//         (, , weth, wbtc, ) = config.activeNetworkconfig();
//         // for open fuzzing
//         targetContract(address(engine));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         // get the value of all collateral in the protocol
//         // compare it to all the debt (dsc)

//         // total supply of all dsc
//         uint totalSupply = dsc.totalSupply();
//         // get total amount of weth & wbtc in dsc contract
//         uint totalWethDeposited = IERC20(weth).balanceOf(address(dsc));
//         uint totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsc));

//         // get $ value of weth & wbtc
//         uint wethValue = engine.getUsdValue(weth, totalWethDeposited);
//         uint wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

//         console.log("weth value: ", wethValue);
//         console.log("wbtc value: ", wbtcValue);
//         console.log("total supply: ", totalSupply);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }




// // open invariants make some 'silly' calls cause it calls functions in our contract
// // randomly with random data. In reality, we want to call functons in an order and maybe with specific random data
// // e.g depositCollateral() before redeemColletarel()

// // We want to point our fuzz or random runs in a direction that makes alot more sense
// // A handler will narrow down function calls