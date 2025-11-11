// We use this to check that the heartbeat of our price feed actually updates as it
// should (e.g ETH/USD -> 3600s --> from docs.chain.link) & if its not we pause
// the functionality of our contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Richard
 * @notice This library is used to check the chainlink oracle for stale data.
 * @notice If a price is stale(i.e doesn't change based on heartbeat), the function
 * will revert and render DSCEngine unusable - this is by design
 * */
library OracleLib {
    error OracleLib__StalePrice();

    uint private constant TIMEOUT = 200000 hours; // 3* 60 * 60 = 10800 seconds

    // same return values of latestRound data function in AggregatorV3 interface
    function staleCheckLatestRoundData(
        AggregatorV3Interface priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        // save return values of latest round data
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // get seconds since this price feed was updated
        // (current time - last time priceFeed was updated)
        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
