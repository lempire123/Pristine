// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISatoshi} from "./interfaces/ISatoshiInterface.sol";
import {AggregatorV3Interface} from "./interfaces/IOracle.sol";
import {IAaveOracle} from "./interfaces/IAaveOracle.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

/**
   _____  _____  _____  _____ _______ _____ _   _ ______ 
 |  __ \|  __ \|_   _|/ ____|__   __|_   _| \ | |  ____|
 | |__) | |__) | | | | (___    | |    | | |  \| | |__   
 |  ___/|  _  /  | |  \___ \   | |    | | | . ` |  __|  
 | |    | | \ \ _| |_ ____) |  | |   _| |_| |\  | |____ 
 |_|    |_|  \_\_____|_____/   |_|  |_____|_| \_|______|

    @author Lempire
 */
contract Pristine {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Position {
        address owner;
        uint256 id;
        uint256 collatAmount;
        uint256 borrowedAmount;
    }

    /*//////////////////////////////////////////////////////////////
                            NUMERIC CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant WBTC_DECIMALS = 10 ** 8;
    uint256 public constant SATOSHI_DECIMALS = 10 ** 18;
    uint256 public constant MIN_COLLAT_RATIO = 110; // 110%
    uint256 public constant RISKY_COLLAT_RATIO = 140; // 140%
    uint256 public constant MEDIUM_COLLAT_RATIO = 180; // 180%
    uint256 public constant REDEMPTION_RATE_RISKY = 100; // 1.00$
    uint256 public constant REDEMPTION_RATE_MEDIUM = 97; // 0.97$
    uint256 public constant REDEMPTION_RATE_SAFE = 95; // 0.95$
    uint256 public constant CHAINLINK_UPDATE_MAX_DELAY = 1 hours;

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL CONTRACTS
    //////////////////////////////////////////////////////////////*/

    address public constant PRICE_FEED_ADDRESS =
        0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // Chainlink Price Feed address on Ethereum Mainnet
    address public constant AAVE_ORACLE =
        0xAC4A2aC76D639E10f2C05a41274c1aF85B772598;
    IERC20 public constant WBTC =
        IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable deployer;
    uint256 public positionCounter; // Supports 2^256 positions (more than enough)
    ISatoshi public Satoshi;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => Position) public Positions;
    mapping(address => uint256) public UserPosition;

    /*//////////////////////////////////////////////////////////////
                                EVENTS 
    //////////////////////////////////////////////////////////////*/

    event Opened(
        uint256 indexed id,
        address indexed owner,
        uint256 collatAmount
    );
    event Deposited(uint256 indexed id, uint256 collatAmount);
    event Borrowed(uint256 indexed id, uint256 borrowedAmount);
    event Repayed(uint256 indexed id, uint256 repaidAmount);
    event Withdrew(uint256 indexed id, uint256 collatAmount);
    event Liquidated(uint256 indexed id, uint256 collatAmount);
    event Redeemed(
        uint256 indexed id,
        address indexed redeemer,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PositionNotHealthy(uint256 id);
    error PositionHealthy(uint256 id);
    error PositionNotFound(uint256 id);
    error NotOwner();
    error NotDeployer();
    error CannotCreateMultiplePositions();
    error AlreadyInitialized();
    error FaultyOracle();
    error NotEnoughCollateral();
    error NotEnoughDebt();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier PositionExists(uint256 _id) {
        if (Positions[_id].owner == address(0)) revert PositionNotFound(_id);
        _;
    }

    modifier onlyDeployer() {
        if (msg.sender != deployer) revert NotDeployer();
        _;
    }

    modifier onlyOwner(uint256 _id) {
        if (msg.sender != Positions[_id].owner) revert NotOwner();
        _;
    }

    modifier notInitialized() {
        if (address(Satoshi) != address(0)) revert AlreadyInitialized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    // @notice - Sets the owner of the contract to the deployer
    // @dev - Owner's power is limited to setting the address of the Satoshi contract
    constructor() {
        deployer = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                       EXTERNAL MUTABLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @notice - Sets the address of the Satoshi contract
    // @dev - Only the owner can call this function
    // @param _Satoshi - The address of the Satoshi contract
    function initSatoshi(address _Satoshi) public onlyDeployer notInitialized {
        Satoshi = ISatoshi(_Satoshi);
    }

    // @notice - Opens a new position
    // @dev - Transfers the amount of WBTC from the caller to the contract
    // @param _amount - The amount of WBTC to be deposited as collateral
    function open(uint256 _amount) public returns (uint256) {
        if (UserPosition[msg.sender] != 0)
            revert CannotCreateMultiplePositions();
        WBTC.transferFrom(msg.sender, address(this), _amount);
        positionCounter++;
        Positions[positionCounter] = Position(
            msg.sender,
            positionCounter,
            _amount,
            0
        );
        UserPosition[msg.sender] = positionCounter;
        emit Opened(positionCounter, msg.sender, _amount);

        return positionCounter;
    }

    // @notice - Deposits WBTC into an existing position
    // @dev - Transfers the amount of WBTC from the caller to the contract
    // @param _amount - The amount of WBTC to be deposited as collateral
    function deposit(uint256 _amount, uint256 _id) public PositionExists(_id) {
        WBTC.transferFrom(msg.sender, address(this), _amount);
        Positions[_id].collatAmount += _amount;

        emit Deposited(_id, _amount);
    }

    // @notice - Borrows Satoshi from an existing position
    // @dev - Mints the amount of Satoshi to the caller
    // @param _amount - The amount of Satoshi to be borrowed
    function borrow(
        uint256 _amount,
        uint256 _id
    ) public PositionExists(_id) onlyOwner(_id) {
        Satoshi.mint(msg.sender, _amount);
        Positions[_id].borrowedAmount += _amount;
        if (!checkPositionHealth(_id)) revert PositionNotHealthy(_id);

        emit Borrowed(_id, _amount);
    }

    // @notice - Repays Satoshi to an existing position
    // @dev - Burns the amount of Satoshi from the caller
    // @param _amount - The amount of Satoshi to be repaid
    function repay(uint256 _amount, uint256 _id) public PositionExists(_id) {
        Satoshi.burn(msg.sender, _amount);
        Positions[_id].borrowedAmount -= _amount;

        emit Repayed(_id, _amount);
    }

    // @notice - Withdraws WBTC from an existing position
    // @dev - Transfers the amount of WBTC to the caller
    // @param _amount - The amount of WBTC to be withdrawn
    function withdraw(
        uint256 _amount,
        uint256 _id
    ) public PositionExists(_id) onlyOwner(_id) {
        WBTC.transfer(msg.sender, _amount);
        Positions[_id].collatAmount -= _amount;
        if (!checkPositionHealth(_id)) revert PositionNotHealthy(_id);

        emit Withdrew(_id, _amount);
    }

    // @notice - liquidates an unhealthy position
    // @dev - Transfers the amount of WBTC to the caller
    // @param _id - The id of the position to be liquidates
    function liquidatePosition(uint256 _id) public PositionExists(_id) {
        if (checkPositionHealth(_id)) revert PositionHealthy(_id);
        Position memory position = Positions[_id];
        Satoshi.burn(msg.sender, position.borrowedAmount);
        WBTC.transfer(msg.sender, position.collatAmount);

        //Update Positions
        delete Positions[_id];
        delete UserPosition[position.owner];

        emit Liquidated(_id, position.collatAmount);
    }

    // @notice - Redeems Satoshi for WBTC from a specified position
    // @param _id - The id of the position to be redeemed from
    // @param _amount - The amount of Satoshi to be redeemed
    function redeem(uint256 _id, uint256 _amount) public PositionExists(_id) {
        Satoshi.burn(msg.sender, _amount);

        uint256 btcPrice = getCollatPrice();
        uint256 redemptionRate = getRedemptionRate(_id); // Get the redemption rate based on the collateral ratio

        uint256 redeemableBTC = (((_amount * redemptionRate) / 10 ** 12) /
            btcPrice);

        // Ensure the position has enough collateral for the redemption
        Position memory position = Positions[_id];
        if (position.collatAmount < redeemableBTC) revert NotEnoughCollateral();
        if (position.borrowedAmount < _amount) revert NotEnoughDebt();

        position.collatAmount -= redeemableBTC;
        position.borrowedAmount -= _amount;
        Positions[_id] = position;

        WBTC.transfer(msg.sender, redeemableBTC);

        emit Redeemed(_id, msg.sender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @notice - Checks if a position is healthy
    // @dev - Returns true if the position is healthy, false otherwise
    // @param _id - The id of the position to be checked
    function checkPositionHealth(uint256 _id) public view returns (bool) {
        Position memory position = Positions[_id];
        uint256 collateralValue = (position.collatAmount * getCollatPrice()) /
            WBTC_DECIMALS;
        uint256 borrowedValue = position.borrowedAmount / SATOSHI_DECIMALS;
        if (borrowedValue == 0) return true;

        return (collateralValue * 100) / borrowedValue >= MIN_COLLAT_RATIO;
    }

    // @notice - Gets the price of WBTC in USD
    // @dev - Uses chainlink as primary oracle, Aave as secondary
    // Importantly, returns the price normalized to WBTC_DECIMALS
    function getCollatPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            PRICE_FEED_ADDRESS
        );
        (, int price, , uint timestamp, ) = priceFeed.latestRoundData();
        uint256 chainlinkPrice = uint256(price);

        if (
            chainlinkPrice > 0 &&
            block.timestamp - timestamp <= CHAINLINK_UPDATE_MAX_DELAY
        ) {
            return chainlinkPrice / WBTC_DECIMALS;
        } else {
            uint256 aavePrice = IAaveOracle(AAVE_ORACLE).getAssetPrice(
                address(WBTC)
            );

            if (aavePrice == 0) revert FaultyOracle();

            return aavePrice / WBTC_DECIMALS;
        }
    }

    // Helper function to determine the redemption rate based on the collateral ratio
    function getRedemptionRate(uint256 _id) public view returns (uint256) {
        uint256 collatValue = (Positions[_id].collatAmount * getCollatPrice()) /
            WBTC_DECIMALS;
        uint256 borrowedValue = Positions[_id].borrowedAmount /
            SATOSHI_DECIMALS;
        uint256 collatRatio = (borrowedValue == 0)
            ? 0
            : (collatValue * 100) / borrowedValue;

        if (collatRatio >= MEDIUM_COLLAT_RATIO) {
            return REDEMPTION_RATE_SAFE;
        } else if (collatRatio >= RISKY_COLLAT_RATIO) {
            return REDEMPTION_RATE_MEDIUM;
        } else {
            return REDEMPTION_RATE_RISKY;
        }
    }
}
