// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    // We'll pass these arrays to dsc engine
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    // Deploy both contracts
    function run()
        external
        returns (DecentralizedStableCoin, DSCEngine, HelperConfig)
    {
        HelperConfig config = new HelperConfig();

        // Get values of HelperConfig struct and save them
        // Deploy based on Network config
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = config.activeNetworkconfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );

        // transfer ownership of DecentralizedStableCoin contract to DSCEngine (using Ownable library)
        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();

        // Return contracts
        return (dsc, engine, config);
        // Return Helper config for testing purposes
    }
}
