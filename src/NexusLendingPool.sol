// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NexusLendingPool is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant COLLATERAL_RATIO = 150;
    uint256 public constant LIQUIDATION_THRESHOLD = 120;
    uint256 public constant INTEREST_RATE = 5;
    uint256 public constant PRECISION = 100;

    struct Position {
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 lastInterestUpdate;
        bool isActive;
    }

    IERC20 public immutable borrowToken;
    mapping(address => Position) public positions;
    uint256 public totalDeposits;
    uint256 public totalBorrowed;

    event CollateralDeposited(address indexed user, uint256 amount);
    event TokensBorrowed(address indexed user, uint256 amount);
    event LoanRepaid(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event PositionLiquidated(address indexed user, address indexed liquidator);

    error InsufficientCollateral();
    error ExceedsBorrowLimit();
    error NoActivePosition();
    error PositionHealthy();
    error ZeroAmount();

    constructor(address _borrowToken) Ownable(msg.sender) {
        borrowToken = IERC20(_borrowToken);
    }

    function depositCollateral() external payable nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        Position storage pos = positions[msg.sender];
        pos.collateralAmount += msg.value;
        pos.isActive = true;
        pos.lastInterestUpdate = block.timestamp;
        totalDeposits += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Position storage pos = positions[msg.sender];
        if (!pos.isActive) revert NoActivePosition();
        uint256 maxBorrow = getMaxBorrow(msg.sender);
        if (pos.borrowedAmount + amount > maxBorrow) revert ExceedsBorrowLimit();
        pos.borrowedAmount += amount;
        totalBorrowed += amount;
        borrowToken.safeTransfer(msg.sender, amount);
        emit TokensBorrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Position storage pos = positions[msg.sender];
        if (!pos.isActive) revert NoActivePosition();
        uint256 repayAmount = amount > pos.borrowedAmount ? pos.borrowedAmount : amount;
        pos.borrowedAmount -= repayAmount;
        totalBorrowed -= repayAmount;
        borrowToken.safeTransferFrom(msg.sender, address(this), repayAmount);
        emit LoanRepaid(msg.sender, repayAmount);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Position storage pos = positions[msg.sender];
        if (!pos.isActive) revert NoActivePosition();
        if (pos.borrowedAmount > 0) revert InsufficientCollateral();
        pos.collateralAmount -= amount;
        totalDeposits -= amount;
        if (pos.collateralAmount == 0) pos.isActive = false;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
        emit CollateralWithdrawn(msg.sender, amount);
    }

    function liquidate(address user) external nonReentrant {
        Position storage pos = positions[user];
        if (!pos.isActive) revert NoActivePosition();
        if (!isLiquidatable(user)) revert PositionHealthy();
        uint256 collateral = pos.collateralAmount;
        uint256 debt = pos.borrowedAmount;
        pos.collateralAmount = 0;
        pos.borrowedAmount = 0;
        pos.isActive = false;
        totalDeposits -= collateral;
        totalBorrowed -= debt;
        borrowToken.safeTransferFrom(msg.sender, address(this), debt);
        (bool success, ) = msg.sender.call{value: collateral}("");
        require(success, "ETH transfer failed");
        emit PositionLiquidated(user, msg.sender);
    }

    function getMaxBorrow(address user) public view returns (uint256) {
        Position memory pos = positions[user];
        return (pos.collateralAmount * PRECISION) / COLLATERAL_RATIO;
    }

    function isLiquidatable(address user) public view returns (bool) {
        Position memory pos = positions[user];
        if (!pos.isActive || pos.borrowedAmount == 0) return false;
        uint256 collateralValue = pos.collateralAmount * PRECISION;
        uint256 requiredCollateral = pos.borrowedAmount * LIQUIDATION_THRESHOLD;
        return collateralValue < requiredCollateral;
    }

    function getPosition(address user) external view returns (
        uint256 collateral,
        uint256 borrowed,
        uint256 maxBorrow,
        bool liquidatable
    ) {
        Position memory pos = positions[user];
        return (
            pos.collateralAmount,
            pos.borrowedAmount,
            getMaxBorrow(user),
            isLiquidatable(user)
        );
    }

    receive() external payable {}
}