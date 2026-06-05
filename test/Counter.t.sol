// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/NexusLendingPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {
        _mint(msg.sender, 1_000_000e18);
    }
}

contract NexusLendingPoolTest is Test {
    NexusLendingPool pool;
    MockToken token;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new MockToken();
        pool = new NexusLendingPool(address(token));
        token.transfer(address(pool), 100_000e18);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_DepositCollateral() public {
        vm.prank(alice);
        pool.depositCollateral{value: 1 ether}();
        (uint256 collateral,,,) = pool.getPosition(alice);
        assertEq(collateral, 1 ether);
    }

    function test_Borrow() public {
        vm.startPrank(alice);
        pool.depositCollateral{value: 1 ether}();
        uint256 maxBorrow = pool.getMaxBorrow(alice);
        pool.borrow(maxBorrow);
        (, uint256 borrowed,,) = pool.getPosition(alice);
        assertEq(borrowed, maxBorrow);
        vm.stopPrank();
    }

    function test_RevertWhen_BorrowExceedsLimit() public {
        vm.startPrank(alice);
        pool.depositCollateral{value: 1 ether}();
        uint256 maxBorrow = pool.getMaxBorrow(alice);
        vm.expectRevert(NexusLendingPool.ExceedsBorrowLimit.selector);
        pool.borrow(maxBorrow + 1);
        vm.stopPrank();
    }

    function test_Repay() public {
        vm.startPrank(alice);
        pool.depositCollateral{value: 1 ether}();
        uint256 maxBorrow = pool.getMaxBorrow(alice);
        pool.borrow(maxBorrow);
        token.approve(address(pool), maxBorrow);
        pool.repay(maxBorrow);
        (, uint256 borrowed,,) = pool.getPosition(alice);
        assertEq(borrowed, 0);
        vm.stopPrank();
    }

    function testFuzz_DepositCollateral(uint256 amount) public {
        amount = bound(amount, 0.01 ether, 5 ether);
        vm.deal(alice, amount);
        vm.prank(alice);
        pool.depositCollateral{value: amount}();
        (uint256 collateral,,,) = pool.getPosition(alice);
        assertEq(collateral, amount);
    }

    function testFuzz_BorrowNeverExceedsMax(uint256 depositAmount, uint256 borrowAmount) public {
        depositAmount = bound(depositAmount, 0.01 ether, 5 ether);
        vm.deal(alice, depositAmount);
        vm.prank(alice);
        pool.depositCollateral{value: depositAmount}();
        uint256 maxBorrow = pool.getMaxBorrow(alice);
        borrowAmount = bound(borrowAmount, maxBorrow + 1, maxBorrow + 1000e18);
        vm.prank(alice);
        vm.expectRevert(NexusLendingPool.ExceedsBorrowLimit.selector);
        pool.borrow(borrowAmount);
    }
}