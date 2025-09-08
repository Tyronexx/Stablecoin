// Helper config to get priceFeedAddresses and tokenAddresses needed to deploy DSCEngine
// Also used to determine network configuration for deployment

// AF/S3/V11
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    // WETH is ERC20 version of ETH
    // WBTC is ERC20 version of BTC

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    // Mocks for anvil deployment
    uint8 public constant DECIMALS = 8;
    // get eth usd price feed mock based on this price (in USD)
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkconfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkconfig = getSepoliaEthConfig();
        } else {
            activeNetworkconfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                wbtcUsdPriceFeed: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    // docs.chain.link/data-feeds/price-feeds/addresses    for price feeds
    // 0x694AA1769357215DE4FAC081bf1f309aDC325306   ethusd
    // 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43   btcusd

    // cyfrin deployed weth(sepolia)  0xdd13E55209Fd76AfE204dBda4007C227904f0a81
    // cyfrin deployed wbtc(sepolia)  0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // If activeNetworkconfig has already been initialized (i.e. wethUsdPriceFeed is set),
        // then just return it. Otherwise, continue executing to set or fetch a new config.
        // When a struct is declared but not explicitly initialized, all of its fields are automatically set to their default values i.e address(0) or 0 for uint.
        // This checks "Has this struct been initialized yet? If not, we need to set it up. else return activeNetworkconfig"
        if (activeNetworkconfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkconfig;
        }

        vm.startBroadcast();
        // Get eth/usd price using mock Data feed based on decimals and price
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        // Mock Eth
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

        // Get btc/usd price using mock Data feed based on decimals and price
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        // Mock Eth
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        return
            NetworkConfig({
                wethUsdPriceFeed: address(ethUsdPriceFeed),
                wbtcUsdPriceFeed: address(btcUsdPriceFeed),
                weth: address(wethMock),
                wbtc: address(wbtcMock),
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }
}
