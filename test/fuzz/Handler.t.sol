// SPDX-License-Identifier: MIT

// Handler will narrow down the way we call functions

// Invariants contract target contract will be this handler

// This handler will also check external contracts called like price feed

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    // contracts handler will handle making calls to
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    // Ghost variable to track how often mint is called
    uint public timesMintIsCalled;
    // array of addresses that have called depositCollateral
    address[] public usersWithCollateralDeposited;

    MockV3Aggregator public ethUsdPriceFeed;

    uint96 MAX_DEPOSIT_SIZE = type(uint96).max; //the max uint 96 value

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;

        // get array of collateral tokens
        address[] memory collateralTokens = engine.getCollateralTokens();
        // get each collateral token from array
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        // for price feeds fuzz
        // get weth price feed
        ethUsdPriceFeed = MockV3Aggregator(
            engine.getCollateralTokenPriceFeed(address(weth))
        );
    }

    function mintDsc(uint amount, uint addressSeed) public {
        // we need to set this function so only addressed that have deposited collateral
        // can call it else it'll anlost never get called. However, there might be a case of a user minting dsc without depositing collateral
        // we dont know about (reason we have both continue on revert and fail on revert tests)
        // for fail on revert, we'll only pick a message .sender that has deposited collateral

        // skip run if usersWithCollateralDeposited array is empty
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }

        // set caller of function from random user with deposited collateral
        // modulo maps randomly fuzzed addressSeed stays within bounds of usersWithCollateralDeposited array
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];

        // only mint dsc if amount is less than collateral
        // we'll use "getAccountInformation" function which gets collateralValueInUsd for each user
        // and ensure we're always minting < collateralValueInUsd
        (uint totalDscMinted, uint collateralValueInUsd) = engine
            .getAccountInformation(sender);

        // collateral to dsc is on 2:1 basis
        // collateralValueInUsd / 2 = maximum DSC they are allowed to mint based on your 2:1 ratio
        // minus any previously minted dsc (will be redundant if user hasn't minted dsc)
        // maxDscToMint = how much more DSC they can mint safely.
        // replicates checking user health factor
        // nb: we typecast both values to int256 to perform subtraction safely
        // as uint cant represent negative numbers and will revert with underflow
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) -
            int256(totalDscMinted);
        // skip if maxDscToMint is negative
        if (maxDscToMint < 0) {
            return;
        }

        // amount shouldn't be less than 0
        // cast masDscToMint back to uint256 cause we sure it isn't negative
        // we're not using 1 cause ideally, a user can pass 0 but our mintDsc function checks this and reverts
        // 'bound' is used to constrain the input values within a specific valid range
        // for the function being called
        amount = bound(amount, 0, uint256(maxDscToMint));
        // revert if mount is 0 (in order not to waste runs)
        if (amount == 0) {
            return;
        }
        // mint dsc to sender
        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();

        // track how often mint is called
        timesMintIsCalled++;
    }

    // Dont call redeem collateral except theres collateral to redeem

    // deposit random collaterals that are valid collaterals
    // In handlers, whatever parameters we have are going to be randomized
    // i.e, random (valid (weth, wbtc)) collateral & random amountCollateral
    // collateralSeed will pick from our two valid collateral addresses
    function depositCollateral(
        uint collateralSeed,
        uint amountCollateral
    ) public {
        // get valid collaterals
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // console.log("collateral ", collateral);
        // get valid amountCollateral (i.e collateral more than 0)
        // bound amountCollateral between 1 & MAX_DEPOSIT_SIZE
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        // approve protocol to deposit collateral
        // msg.sender here is theaddress of test framework i.e address from
        // which invariant runner (Invariants.t.sol) called Handler
        vm.startPrank(msg.sender);
        // mint collateral to msg.sender(calling depositCollateral) so they can deposit it
        collateral.mint(msg.sender, amountCollateral);
        // approve engine to spend amountCollateral of collateral on behalf of msg.sender
        collateral.approve(address(engine), amountCollateral);
        // deposit valid collateral addresses
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        // add all addresses that call this function to this list
        usersWithCollateralDeposited.push(msg.sender);
    }

    // only allow people redeem the maximum amount they have in the system
    function redeemCollateral(
        uint collateralSeed,
        uint amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // only allow people redeem the maximum amount they have in the system
        uint maxCollateralToRedeem = engine.getCollateralBalanceOfUser(
            msg.sender,
            address(collateral)
        );
        // chatGpt
        // vm.assume(maxCollateralToRedeem > 0);

        // bound amountCollateral to maxCollateralToRedeem
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        // dont execute next function if user hasnt deposited anything
        if (amountCollateral == 0) {
            return;
        }
        // call the next function using msg.sender rather than address(Handler)
        // this way we get the same user that called depositCollateral above and we simulate a real user calling redeemCollateral (inside DSCEngine)
        vm.prank(msg.sender);
        // call redeemCollateral function
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    // Price feed test
    // Test what happens when collateral price changes
    // results from this test showed that if price plummets too quickly,
    // our system gets destroyed cause we become undercollaterized and invatiants wont hold anymore
    // function updateCollateralPrice(uint96 newPrice) public {
    //     // newPrice is new eth/usd price we want to set with 8 decimals
    //     // convert to int cause price feeds use int
    //     // this converts uint96 -> uint256 -> int256
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     // updateAnswer function manually updates the latest price data in a way that
    //     // mimics how a real Chainlink price feed works
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    /************************Helper Functions************************/

    // gets valid deposit collateral (weth, wbtc)
    // collateralSeed is a random fuzz-generated number
    // weth or wbtc is returned based on if this value is odd or even (i.e modulo)
    function _getCollateralFromSeed(
        uint collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function callSummary() external view {
        console.log("Weth total deposited", weth.balanceOf(address(engine)));
        console.log("Wbtc total deposited", wbtc.balanceOf(address(engine)));
        console.log("Total supply of DSC", dsc.totalSupply());
    }
}
