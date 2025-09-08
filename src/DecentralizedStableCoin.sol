// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// DecentralizedStableCoin is Ownable so it's 100% controlled by our logic (DCSEngine)
// i.e, We'll have onlyOwner modifiers where the owner will be the immutable logic (DSCEngine)

/*
 * @title DecentralizedStableCoin
 * @author Richard Ikenna
 * Collateral: Exogenous (ETH & BTC)
 * Minting/Stability Mechanism: Algorithmic
 * This is governed by DSCEngine (Logic)
 * This is the ERC20 implementation of our stablecoing system
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    // ERC20Burnable cause we're gonna be buring tokens to maintain the pegged price
    constructor()
        // Name & Symbol
        ERC20("DecentralizedStableCoin", "DSC")
        // Initial owner
        Ownable()
    {}

    // Only engine can call this
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        // Check that amount being burned isn't 0 or less
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        // check that account balance is higher than value to be burned
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        // Super keyword means use the 'burn' function from the parent class (i.e ERC20Burnable) since we're overriding the burn function in it
        super.burn(_amount);
    }

    // Only engine can call this
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        // Dont allow people mint to the zero address
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        // Can't mint 0 or less tokens
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
