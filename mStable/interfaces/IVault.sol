// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault {
    function withdrawAndUnwrap(
        uint256 _amount,
        uint256 _minAmountOut,
        address _output,
        address _beneficiary,
        address _router,
        bool _isBassetOut
    ) external returns (uint256 outputQuantity);
    function claimReward() external;
    function getRewardToken() external returns (IERC20);
    function getPlatformToken() external returns (IERC20);
}