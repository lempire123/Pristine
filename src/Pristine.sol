// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISatoshi} from "./interfaces/ISatoshiInterface.sol";
import {AggregatorV3Interface} from "./interfaces/IOracle.sol";
import {IAaveOracle} from "./interfaces/IAaveOracle.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract Pristine {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public constant PRICE_FEED_ADDRESS =
        0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // Chainlink Price Feed address on Ethereum Mainnet
    address public constant AAVE_ORACLE =
        0xAC4A2aC76D639E10f2C05a41274c1aF85B772598;
    IERC20 public constant WBTC =
        IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    uint256 public constant COLLAT_RATIO = 110; // 110%
    ISatoshi public Satoshi;
    address public immutable deployer;
    uint256 public positionCounter; // Support 2^256 positions (more than enough)

    mapping(uint256 => Position) public Positions;
    mapping(address => uint256) public UserPosition;

    /*//////////////////////////////////////////////////////////////
                                EVENTS 
    //////////////////////////////////////////////////////////////*/

    event Open(uint256 indexed id, address indexed owner, uint256 collatAmount);
    event Deposit(uint256 indexed id, uint256 collatAmount);
    event Borrow(uint256 indexed id, uint256 borrowedAmount);
    event Repay(uint256 indexed id, uint256 repaidAmount);
    event Withdraw(uint256 indexed id, uint256 collatAmount);
    event Liquidate(uint256 indexed id, uint256 collatAmount);

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
        emit Open(positionCounter, msg.sender, _amount);

        return positionCounter;
    }

    // @notice - Deposits WBTC into an existing position
    // @dev - Transfers the amount of WBTC from the caller to the contract
    // @param _amount - The amount of WBTC to be deposited as collateral
    function deposit(uint256 _amount, uint256 _id) public PositionExists(_id) {
        WBTC.transferFrom(msg.sender, address(this), _amount);
        Positions[_id].collatAmount += _amount;

        emit Deposit(_id, _amount);
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

        emit Borrow(_id, _amount);
    }

    // @notice - Repays Satoshi to an existing position
    // @dev - Burns the amount of Satoshi from the caller
    // @param _amount - The amount of Satoshi to be repaid
    function repay(uint256 _amount, uint256 _id) public PositionExists(_id) {
        Satoshi.burn(msg.sender, _amount);
        Positions[_id].borrowedAmount -= _amount;

        emit Repay(_id, _amount);
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

        emit Withdraw(_id, _amount);
    }

    // @notice - Liquidates an unhealthy position
    // @dev - Transfers the amount of WBTC to the caller
    // @param _id - The id of the position to be liquidated
    function liquidatePosition(uint256 _id) public PositionExists(_id) {
        if (checkPositionHealth(_id)) revert PositionHealthy(_id);
        Position memory position = Positions[_id];
        Satoshi.burn(msg.sender, position.borrowedAmount);
        WBTC.transfer(msg.sender, position.collatAmount);

        //Update Positions
        delete Positions[_id];

        emit Liquidate(_id, position.collatAmount);
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
            10 ** 8;
        uint256 borrowedValue = position.borrowedAmount / 10 ** 18;
        if (borrowedValue == 0) return true;

        return (collateralValue * 100) / borrowedValue >= COLLAT_RATIO;
    }

    // @notice - Gets the price of WBTC in USD
    // @dev - Uses chainlink as primary oracle, Aave as secondary
    function getCollatPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            PRICE_FEED_ADDRESS
        );
        (, int price, , uint timestamp, ) = priceFeed.latestRoundData();
        uint256 chainlinkPrice = uint256(price);

        if (chainlinkPrice > 0 && block.timestamp - timestamp <= 1 hours) {
            return chainlinkPrice / 10 ** 8;
        } else {
            uint256 aavePrice = IAaveOracle(AAVE_ORACLE).getAssetPrice(
                address(WBTC)
            );

            if (aavePrice == 0) revert FaultyOracle();

            return aavePrice / 10 ** 8;
        }
    }

    // @notice - Gets the position details
    // @dev - Returns the owner, id, collateral amount, and borrowed amount of the position
    // @param _id - The id of the position to be checked
    function getPosition(
        uint256 _id
    ) public view returns (address, uint256, uint256, uint256) {
        Position memory position = Positions[_id];
        return (
            position.owner,
            position.id,
            position.collatAmount,
            position.borrowedAmount
        );
    }
}
