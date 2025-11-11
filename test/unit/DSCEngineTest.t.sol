// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);
}

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
    uint256 amountToMint = 100 ether;

    // return dsc and engine cause thats what our deploy contract returns
    function setUp() public {
        deployer = new DeployDSC();
        // return dsc and engine cause thats what our DeployDSC contract returns
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, , weth, , ) = config.activeNetworkconfig();

        // Mint mock weth to USER
        // ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);

        vm.deal(USER, STARTING_ERC20_BALANCE); // give USER ETH
        vm.startPrank(USER);
        IWETH(weth).deposit{value: STARTING_ERC20_BALANCE}(); // wrap ETH into WETH

        // Approve DSCEngine to spend WETH
        IWETH(weth).approve(address(engine), STARTING_ERC20_BALANCE);
        vm.stopPrank();
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
        uint256 ethAmount = 1e18;
        // 15e18 * 3421.69/ETH = 30000e18
        uint256 expectedUsd = 3426.03e18; // current price
        // weth is set to default eth 0 address i.e address(0)
        // And if mock price feed is set to address(0), our helperconfig defaults to address(0)
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
        console2.log(actualUsd);
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
        // ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        // fund USER with ETH to wrap into WETH
        vm.deal(USER, AMOUNT_COLLATERAL);

        // wrap ETH → WETH
        IWETH(weth).deposit{value: AMOUNT_COLLATERAL}();

        // approve DSCEngine to spend WETH
        IWETH(weth).approve(address(engine), AMOUNT_COLLATERAL);

        // deposit AMOUNT_COLLATERAL of weth by USER
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        // fund USER with ETH to wrap into WETH
        vm.deal(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        // ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        // engine.depositCollateralAndMintDsc(
        //     weth,
        //     AMOUNT_COLLATERAL,
        //     amountToMint
        // );

        // 1️⃣ Wrap some ETH into WETH (real WETH on Sepolia)
        IWETH(weth).deposit{value: AMOUNT_COLLATERAL}();

        // 2️⃣ Approve DSCEngine to spend the WETH
        IERC20(weth).approve(address(engine), AMOUNT_COLLATERAL);

        // 3️⃣ Deposit WETH and mint DSC
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );

        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral()
        public
        depositedCollateralAndMintedDsc
    {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    function testUserCanMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintDsc(amountToMint);

        vm.stopPrank();
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    function testUserCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        // todo
        vm.stopPrank();
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
