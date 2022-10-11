// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICEth {
    function mint() external payable;

    function borrow(uint256) external returns (uint256);

    function repayBorrow() external payable;

    function borrowBalanceCurrent(address) external returns (uint256);
}