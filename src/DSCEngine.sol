// SPDX-License-Identifier: MIT

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

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// Chainlink data feeds for prices
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Richard Ikenna
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 * We should always have more collateral than DSC in the system at all times
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    /*******************Errors************************/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine_MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();
    error DSCEngine__InsufficientCollateral();

    /*******************Type************************/
    // replace 'latestRoundData' calls with 'staleCheckLatestRoundData' from OracleLib
    using OracleLib for AggregatorV3Interface;

    /*******************State Variables************************/
    // map of allowed deposit tokens to their price feed ( token <-> price feed )
    // We're using solidity's new named mapping
    // Set when we deploy the contract (i.e in constructor)
    mapping(address token => address priceFeed) private s_priceFeeds;
    /**
     * map of user to collateral token and amount of collateral deposited
     * */
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    /*
     * map of user to amount of DSC minted
     */
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    // We need to be 200% overcollateralized to mint DSC
    // This means that for every 1 DSC minted, we need to have $2 worth
    // of collateral deposited in the system.
    // LIQUIDATION_THRESHOLD means collateral value should back 50% of DSC value minted i.e -> $100 ETH backs max $50 DSC
    // If collateral value goes below threshold, user is liquidated
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means 10% bonus

    // array of collateral tokens
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    /************************************Events*************************************/
    // Emit (console.log) data to the blockchain
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    /************************************Modifiers**********************************/
    // ensure amount passed is more than zero
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    // check that this token is allowd to be deposited
    // If 'token' is not in the s_priceFeeds mapping, the call reverts with DSCEngine__NotAllowedToken
    modifier isAllowedToken(address token) {
        // check if there's no price feed set for the given token
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        // Run the rest of the function
        _;
    }

    /************************************Functions**********************************/
    // initialize values
    constructor(
        // tokenAddresses are the addresses of the tokens we allow to be deposited as collateral
        // We'll map the token address to its price feed address
        address[] memory tokenAddresses,
        // priceFeedAddresses are the addresses of the price feeds for those tokens
        address[] memory priceFeedAddresses,
        // dscAddress is the address of the DecentralizedStableCoin contract
        address dscAddress
    ) {
        // check that tokenAddresses list and priceFeedAddresses list are same length
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // We're using USD backed price feeds e.g ETH/USD, BTC/USD
        // Loop through tokenAddresses and set the corresponding price feed address
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            //  adds the address at tokenAddresses[i] to the s_collateralTokens array
            s_collateralTokens.push(tokenAddresses[i]);
        }
        // Set the DecentralizedStableCoin contract address
        // This is immutable so it can't be changed after deployment
        // Type cast dscAddress to DecentralizedStableCoin
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /****************External Functions****************/
    // Deposit eth/btc and mint Dsc
    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI (Checks Effects Interaction) pattern
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @notice This function allows users to deposit collateral (e.g. ETH, BTC)
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        // modifier to check that amount is more than zero
        moreThanZero(amountCollateral)
        // modifier to check that the token deposited is allowed
        isAllowedToken(tokenCollateralAddress)
        // ReentrancyGuard to prevent reentrancy attacks
        nonReentrant
    {
        // Deposit collateral and update state
        // This line adds amountCollateral to the deposit for the user(msg.sender) and token(tokenCollateralAddress) combination
        // s_collateralDeposited maps user address to token address to amount deposited
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        // emitting event cause we're updating state
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        // Wrap collateral address as ERC20 token so we can interact with it
        // perform 'transferFrom' from user to this contract
        // IERC20 is the interface for ERC20 tokens
        // store result as boolean
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        // If transfer fails, revert the transaction
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    // function getUsdValue(
    //     address token,
    //     uint256 amount // in WEI
    // ) external view returns (uint256) {
    //     return _getUsdValue(token, amount);
    // }

    // function getAccountCollateralValue(
    //     address user
    // ) public view returns (uint256 totalCollateralValueInUsd) {
    //     for (uint256 index = 0; index < s_collateralTokens.length; index++) {
    //         address token = s_collateralTokens[index];
    //         uint256 amount = s_collateralDeposited[user][token];
    //         totalCollateralValueInUsd += _getUsdValue(token, amount);
    //     }
    //     return totalCollateralValueInUsd;
    // }

    /**
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral amount of collateral to redeem
     * @param amountDscToBurn amount of DSC to burn
     * This function burns DSC and redeems underlying collateral in one transaction
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        // We need to burn dsc minted before redeeming collateral (else health factor will break and this will revert)
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeem collateral checks health factor
    }

    // in order to redeem collateral
    // 1. health factor must be above 1 after collateral pulled
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        // only enter if amountCollateral is more than zero
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        // revert function if it breaks health factor
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Quick way to get more collateral against dsc
    // Calling this burns a users dsc on behalf of themselves
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of Decentralized stablecoin to mint
     * @notice they must have more collateral value than minimum threshold
     * */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) {
        // Keep track oh how much anyone that calls this, mints
        // add 'amountDscToMint' to 'amountDscMinted' (in 's_DSCMinted' map) for address who calls this
        s_DSCMinted[msg.sender] += amountDscToMint;

        // if adding dsc breaks health factor, revert
        _revertIfHealthFactorIsBroken(msg.sender);

        // Mint the DSC to the user calling
        // Call the mint function in DecentralizedStableCoin contract
        // Actual mint function is in DecentralizedStableCoin contract
        // This executes it and checks that it worked
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        // If mint fails, revert the transaction
        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    // liquidate people if price of collateral deposited goes below dsc minted
    // People get paid for liquidating people who are almost undercollaterized
    // liquidator takes remaining collateral and pays/burns DSC minted
    // We put in a higher collateral against what we mint e.g $100 ETH to mint $50 DSC
    // However, If ETH value drops to $40, We're now undercollateralized (less ETH than DSC)
    // This function kicks out users (using a threshold) who are too close to being undercollateralized
    // Threshold will be 150% (i.e whatever DSC amount you have * 150% = ETH/BTC $ collateral equivalent required to not get liquidated)
    // If someone pays minted DSC of users that fall below threshold (hence user has 0 debt), they can have all their collateral for a discount (i.e 'liquidate' them)
    // This is like punishment for allowing collateral value go too low
    /**
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The user who broke health factor. i.e _healthFactor is below MIN_HEALTH_FACTOR
     * @param debtToCover Amount of DSC to burn to improve user health factor
     * @notice You can partially liauidate a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollaterized in order for this to work
     * @notice A known bug would be if the protocol were %100 or less collaterized, then we wouldnt be able to incentivize liquidators
     * @notice Example would be if the price of the collateral plummeted before anyone could liquidate
     *
     * Follows CEI: Checks, Effects, Interactions
     * */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        // check health factor of user at beginning
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            // revert if health factor is good
            revert DSCEngine__HealthFactorOk();
        }
        // Burn their DSC "debt"
        // Take their collateral

        // Bad user: $140 ETH, $100 DSC
        // debtToCover = $100
        // $100 of DSC = ??? ETH?           or BTC
        // i.e get collateral value of dsc(debt) to burn
        uint tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );

        // Give liquidator 10% discount
        // For $100 DSC debt, give liquidator $110
        // In percentage
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint totalCollateralToRedeem = bonusCollateral +
            tokenAmountFromDebtCovered;

        // from will be user getting liquidated
        // to will be whoever is calling this liquidate function
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        // Burn Dsc
        // Whoever calls this function (msg.sender) is paying the DSC debt when burning "dscFrom"
        // onBehalfOf -> User getting liquidated
        _burnDsc(debtToCover, user, msg.sender);

        // revert if health factor wasn't improved
        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine_HealthFactorNotImproved();
        }
        // revert if liquidators health factor breaks
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Check how healthy people are
    function getHealthFactor() external view {}

    /***************Private and Internal View Functions****************/

    /**
     * Returns minted DSC and collateral value for each user
     */
    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        // Use global map to get total DSC minted
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     * Returns ratio of collateral to DSC minted users can have
     */
    function _healthFactor(address user) private view returns (uint256) {
        // get user total dsc minted
        // get collateral value
        // ensure collateral value is greater than dsc minted
        // get both values from _getAccountInformation fn
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);

        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    // Check Health factor (Does user have enough collateral)
    // Revert if false
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            // If health factor is less than 1, revert with error
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    // Internal redeem collateral function to redeem collateral from anybody to anybody
    // from is the address of user whose collateral is being removed
    // to is the address collateral will be sent to
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        // chatgpt
        // uint256 balance = s_collateralDeposited[from][tokenCollateralAddress];
        // if (amountCollateral > balance) {
        //     revert DSCEngine__InsufficientCollateral(); // define this error
        // }
        // We need to burn dsc minted before redeeming collateral (else health factor will break and this will revert)

        // Subtract amountCollateral from callers address based on s_collateralDeposited compound map
        // Solidity compiler has an inbuild error if user tries to pull out more than they have (safe math)
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        // emit event since we're updating state
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        // Send collateral token to the address
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev Low-level internal function, do not call unless the function calling it is checking
     * for health factors being broken
     * Allows us to burn dsc from anybody
     * @param onBehalfOf -> Whose DSC are we burning
     * @param dscFrom -> Address dsc is coming from
     * */
    function _burnDsc(
        uint amountToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        // Remove amount from total DSC minted
        s_DSCMinted[onBehalfOf] -= amountToBurn;
        // transfer 'amountToBurn' from 'dscFrom' to this contract (DecentralizedStableCoin contract)
        // So we can call IERC20Burnable inbuilt burn function
        // NB: 'transferFrom' is from 'ERC20' being inherited by DecentralizedStableCoin
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountToBurn);
    }

    // function _getUsdValue(
    //     address token,
    //     uint256 amount
    // ) private view returns (uint256) {
    //     AggregatorV3Interface priceFeed = AggregatorV3Interface(
    //         s_priceFeeds[token]
    //     );
    //     (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
    //     // 1 ETH = 1000 USD
    //     // The returned value from Chainlink will be 1000 * 1e8
    //     // Most USD pairs have 8 decimals, so we will just pretend they all do
    //     // We want to have everything in terms of WEI, so we add 10 zeros at the end
    //     return
    //         ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    // }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        // check if total dsc minted is zero
        // If no dsc minted by user, then health factor is max (i.e 1e18)
        // This means that if no dsc is minted, then health factor is always healthy
        // This is because if no dsc is minted, then there is no debt to cover
        // Hence, no need to check collateral value
        if (totalDscMinted == 0) return type(uint256).max;

        // Check maximum DSC to mint based on collateral value
        // We need to be 200% overcollateralized to mint DSC
        // This means that for every 1 DSC minted, we need to have $2 worth of collateral deposited in the system. (Need 2x collateral to DSC minted)
        // collateralValueInUsd * 50/100 or 1/2
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // e.g for $1000 worth eth
        // $1000 ETH * 50 = 50,000 / 100 = 500 (We can mint $500 worth of DSC max)
        // For 100 DSC minted, that would be 500/100 = 5 i.e > 1 hence healthy

        // e.g $150 worth of ETH
        // 150 * 50 = 7500 / 100 = 75
        // For 100 DSC minted, that would be 75/100 = 0.75 i.e < 1 hence unhealthy

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
        // Liquidate users if this value is less than 1
        // multiply by PRECISION to get 18 decimals cause totalDscMinted is in 18 decimals
    }

    /****************** Public & External View Functions ******************/
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token
        // get amount deposited
        // map it to the price to get the usd value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            // get each token
            address token = s_collateralTokens[i];
            // get deposited amount of collateral based on user address and collateral token address (using 's_collateralDeposited' compound map)
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * Get USD value of token based on contract address and token amount
     * */
    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        // Get the price feed for the token we're looking to get the value of (and wrap it with AggregatorV3Interface so we can call its functions)
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        // extract the price value using Chainlink's price feed
        // (, int256 price, , , ) = priceFeed.latestRoundData();
        // check if data is stale before calling
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // BTC and ETH both have 8 decimals, so we need to convert the price to 18 decimals (standard for)
        // If 1 ETH = $1000
        // Returned price value from chainlink will be 1000 * 1e8 ("8" is gotten from the decimals of the price feed (docs.chain.link/data-feeds/price-feeds/addresses))

        // ADDITIONAL_FEED_PRECISION is used to scale the chainlink price from 8 to 18 decimals (1e8 * 1e10 = 1e18)
        // Convert the Chainlink 8-decimal price to 18-decimal format, multiply it by the token amount, and return the USD value (also in 1e18 format)
        // NB: 'amount' is in wei (18 decimals) format, hence 1 ETH = 1 * 1e18
        // PRECISION is used to normalize final result back to 18 decimal format
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    // Get collateral value of dsc(debt) to burn in liquidate fn
    // usdAmountInWei is debt to cover
    // Converts a USD-denominated debt amount into the equivalent amount of a token (like ETH, WBTC, etc.), based on the token's price feed
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        // tokenAmount = Debt(DSC) Amount/ Token Price in USD

        // if price is $2000/ETH & we have $1000 DSC = 1000/2000 = 0.5 ETH
        // usdAmountInWei/price

        // Get price feed contract for the token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        // save only second antry from function call
        // price is in 8 decimals ($2000 = 200000000000 = 2000*1e8)
        // (, int256 price, , , ) = priceFeed.latestRoundData();
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        // NB: usdAmount is in wei hence 18 decimals ($1000 = 1000*1e18)
        // Scale price(1e8) to 18 decimals(1e18) by multiplying with ADDITIONAL_FEED_PRECISION(1e10)
        // We multiply (scale up) numerator by PRECISION in order to keep output at 1e18
        // If we dont do this, usdAmountInWei(1e18) will cancel all zeros in denominator(1e18) and return plain values (not 18 decimals)
        // To scale up answer to 1e18, multiply it
        // e.g 1000e36/2000e18 = 0.5e18 ETH
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    // get account info externally
    function getAccountInformation(
        address user
    ) external view returns (uint totalDscMinted, uint collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    // returns array of collateral tokens
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
