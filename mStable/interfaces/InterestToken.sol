// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface InterestToken {
    function deposit(address _beneficiary, uint256 _amount) external;
    function withdraw(address _account, uint256 _amount) external;
}