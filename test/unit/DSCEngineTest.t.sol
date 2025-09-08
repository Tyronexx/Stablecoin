// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    // From Helperconfig
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;

    address public USER = makeAddr("user");
    uint public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    // return dsc and engine cause thats what our deploy contract returns
    function setUp() public {
        deployer = new DeployDSC();
        // return dsc and engine cause thats what our DeployDSC contract returns
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, , weth, , ) = config.activeNetworkconfig();

        // Mint mock weth to USER
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /**********************Constructor Tests***********************/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        // one token address
        tokenAddresses.push(weth);
        // two price feed addresses
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        // should revert with this error when constructor of DSCEngine contract initializes
        vm.expectRevert(
            DSCEngine
                .DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*************************Price Tests**************************/
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        // weth is set to default eth 0 address i.e address(0)
        // And if mock price feed is set to address(0), our helperconfig defaults to address(0)
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint usdAmount = 100 ether;
        // $2000 / ETH, $100
        uint expectedWeth = 0.05 ether;
        uint actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /***********************depositCollateral Tests********************/
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    // test that only allowed tokens are deposited as collateral
    function testRevertsWithUnapprovedCollateral() public {
        // mock fake token (not allowed to be deposited)
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        // expect this error (from deposit collateral function)
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // deposit collateral by USER
    modifier depositedCollateral() {
        vm.startPrank(USER);
        // Allow (address(engine)) to spend up to AMOUNT_COLLATERAL worth of 'weth' from USER
        // weth was given to USER in constructor
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        // deposit AMOUNT_COLLATERAL of weth by USER
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        //get USER account info
        (uint totalDscMinted, uint collateralValueInUsd) = engine
            .getAccountInformation(USER);

        // USER hasnt minted any dsc
        uint expectedTotalDscMinted = 0;
        uint expectedDepositAmount = engine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // Write more tests
}
