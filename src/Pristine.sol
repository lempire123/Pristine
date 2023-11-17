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
        0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address public constant AAVE_ORACLE =
        0x54586bE62E3c3580375aE3723C145253060Ca0C2;
    IERC20 public constant WBTC =
        IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable deployer;
    uint256 public positionCounter;
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
    event PositionTransferred(
        uint256 indexed id,
        address indexed from,
        address indexed to
    );
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
    error SameOwner();
    error InvalidAddress();

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
        if (_amount > Positions[_id].collatAmount) revert NotEnoughCollateral();
        WBTC.transfer(msg.sender, _amount);
        Positions[_id].collatAmount -= _amount;
        if (!checkPositionHealth(_id)) revert PositionNotHealthy(_id);

        emit Withdrew(_id, _amount);
    }

    // @notice - Transfers ownership of a position to a new address
    // @dev - Only the owner of the position can call this function
    // @param _id - The id of the position to be transferred
    // @param _newOwner - The address of the new owner
    function transferPosition(
        uint256 _id,
        address _newOwner
    ) public PositionExists(_id) onlyOwner(_id) {
        if (_newOwner == address(0)) revert InvalidAddress();
        if (_newOwner == address(0)) revert SameOwner();

        Positions[_id].owner = _newOwner;

        // If you keep the UserPosition mapping, update that as well
        UserPosition[_newOwner] = _id;
        UserPosition[msg.sender] = 0;

        emit PositionTransferred(_id, msg.sender, _newOwner);
    }

    // @notice - liquidates a part or all of an unhealthy position
    // @dev - Transfers the proportional amount of WBTC to the caller
    // @param _id - The id of the position to be liquidated
    // @param _debtAmount - The amount of debt to be repaid
    function liquidatePosition(
        uint256 _id,
        uint256 _debtAmount
    ) public PositionExists(_id) {
        if (checkPositionHealth(_id)) revert PositionHealthy(_id);

        Position memory position = Positions[_id];

        if (_debtAmount > position.borrowedAmount) revert NotEnoughDebt();

        // uint256 collatToTransfer = (_debtAmount * collatRatio) / 100;
        uint256 collatToTransfer = (_debtAmount * position.collatAmount) /
            position.borrowedAmount;

        if (collatToTransfer > position.collatAmount) {
            collatToTransfer = position.collatAmount;
        }

        position.borrowedAmount -= _debtAmount;
        position.collatAmount -= collatToTransfer;

        // Transfer the funds
        Satoshi.burn(msg.sender, _debtAmount);
        WBTC.transfer(msg.sender, collatToTransfer);

        Positions[_id] = position;

        emit Liquidated(_id, collatToTransfer);
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
        if (Positions[_id].borrowedAmount == 0) return true; // If there is no collateral, the position is unhealthy
        return getCollatRatio(_id) >= MIN_COLLAT_RATIO;
    }

    function getCollatRatio(uint256 _id) public view returns (uint256) {
        Position memory position = Positions[_id];
        uint256 collatValue = (position.collatAmount *
            getCollatPrice() *
            SATOSHI_DECIMALS) / WBTC_DECIMALS;
        uint256 borrowedValue = position.borrowedAmount;
        return (borrowedValue == 0) ? 0 : (collatValue * 100) / borrowedValue;
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
    // @notice Returns the redemption rate based on the health of the position
    // @dev The rates are based on hardcoded values
    // @param _id Position id
    function getRedemptionRate(uint256 _id) public view returns (uint256) {
        uint256 collatRatio = getCollatRatio(_id);

        if (collatRatio >= MEDIUM_COLLAT_RATIO) {
            return REDEMPTION_RATE_SAFE;
        } else if (collatRatio >= RISKY_COLLAT_RATIO) {
            return REDEMPTION_RATE_MEDIUM;
        } else {
            return REDEMPTION_RATE_RISKY;
        }
    }
}
