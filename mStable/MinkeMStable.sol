// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC2771Context } from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

import { IMasset } from "./interfaces/IMasset.sol";
import { ISavingsContractV3 } from "./interfaces/ISavingsContract.sol";
import { IBoostedVaultWithLockup } from "./interfaces/IBoostedVaultWithLockup.sol";
import { InterestToken } from "./interfaces/InterestToken.sol";
import { IVault } from "./interfaces/IVault.sol";

contract MinkeMStable is ERC2771Context {
    using SafeERC20 for IERC20;
    // Creator of this contract.
    address public owner;

    bool public stopped = false;
    bool internal locked;

    address public interestToken;
    address public vault;

    constructor(
        address _trustedForwarder,
        address _vault,
        address _interestToken
    ) ERC2771Context(_trustedForwarder) {
        owner = msg.sender;
        vault = _vault;
        interestToken = _interestToken;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }

    // circuit breaker modifiers
    modifier stopInEmergency {
        if (stopped) {
            revert("Paused");
        } else {
            _;
        }
    }

    modifier nonReentrant() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }

    function versionRecipient() external pure returns (string memory) {
        return "1.0";
    }

    // - to Pause the contract
    function toggleContractActive() public onlyOwner {
        stopped = !stopped;
    }

    /**
     * @dev Approve mAsset and bAssets, Feeder Pools and fAssets, and Save/vault
     */
    function approve(
        address _mAsset,
        address[] calldata _bAssets,
        address[] calldata _fPools,
        address[] calldata _fAssets,
        address _save,
        address _vault
    ) external onlyOwner {
        _approve(_mAsset, _save);
        _approve(_save, _vault);
        _approve(_bAssets, _mAsset);

        require(_fPools.length == _fAssets.length, "Mismatching fPools/fAssets");
        for (uint256 i = 0; i < _fPools.length; i++) {
            _approve(_fAssets[i], _fPools[i]);
        }
    }

    /**
     * @dev Approve one token/spender
     */
    function approve(address _token, address _spender) external onlyOwner {
        _approve(_token, _spender);
    }

    /**
     * @dev Approve multiple tokens/one spender
     */
    function approve(address[] calldata _tokens, address _spender) external onlyOwner {
        _approve(_tokens, _spender);
    }

    function _approve(address _token, address _spender) internal {
        require(_spender != address(0), "Invalid spender");
        require(_token != address(0), "Invalid token");
        IERC20(_token).safeApprove(_spender, 2**256 - 1);
    }

    function _approve(address[] calldata _tokens, address _spender) internal {
        require(_spender != address(0), "Invalid spender");
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), "Invalid token");
            IERC20(_tokens[i]).safeApprove(_spender, 2**256 - 1);
        }
    }

    function claimRewards() external onlyOwner {
        IVault(vault).claimReward();
        IERC20 wmatic = IVault(vault).getRewardToken();
        IERC20 mta = IVault(vault).getPlatformToken();
        uint256 rewardsAmount = wmatic.balanceOf(address(this));
        uint256 platformAmount = mta.balanceOf(address(this));
        if (rewardsAmount > 0) {
            require(wmatic.transfer(msg.sender, rewardsAmount));
        }
        if (platformAmount > 0) {
            require(mta.transfer(msg.sender, platformAmount));
        }
    }

    /**
    * @dev 1. Mints an mAsset and then deposits to Save/Savings Vault
    * @param _mAsset       mAsset address
    * @param _bAsset       bAsset address
    * @param _save         Save address
    * @param _vault        Boosted Savings Vault address
    * @param _amount       Amount of bAsset to mint with
    * @param _minOut       Min amount of mAsset to get back
    * @param _stake        Add the imAsset to the Boosted Savings Vault?
    * @param _referrer     Referrer address for this deposit.
    */
    function _saveViaMint(
        address _mAsset,
        address _save,
        address _vault,
        address _bAsset,
        uint256 _amount,
        uint256 _minOut,
        bool _stake,
        address _referrer
    ) internal {
        require(_mAsset != address(0), "Invalid mAsset");
        require(_save != address(0), "Invalid save");
        require(_vault != address(0), "Invalid vault");
        require(_bAsset != address(0), "Invalid bAsset");

        // 1. Get the input bAsset
        IERC20(_bAsset).safeTransferFrom(_msgSender(), address(this), _amount);

        // 2. Mint
        uint256 massetsMinted = IMasset(_mAsset).mint(_bAsset, _amount, _minOut, address(this));

        // 3. Mint imAsset and optionally stake in vault
        _depositAndStake(_save, _vault, massetsMinted, _stake, _referrer);
    }

    /** @dev Internal func to deposit into Save and optionally stake in the vault
    * @param _save       Save address
    * @param _vault      Boosted vault address
    * @param _amount     Amount of mAsset to deposit
    * @param _stake      Add the imAsset to the Savings Vault?
    * @param _referrer   Referrer address for this deposit, if any.
    */
    function _depositAndStake(
        address _save,
        address _vault,
        uint256 _amount,
        bool _stake,
        address _referrer
    ) internal {
        uint256 credits;
        if (_stake && _referrer != address(0)) {
            credits = ISavingsContractV3(_save).depositSavings(
                _amount,
                address(this),
                _referrer
            );
            IBoostedVaultWithLockup(_vault).stake(address(this), credits);
        } else if (_stake && _referrer == address(0)) {
            credits = ISavingsContractV3(_save).depositSavings(_amount, address(this));
            IBoostedVaultWithLockup(_vault).stake(address(this), credits);
        } else if (!_stake && _referrer != address(0)) {
            credits = ISavingsContractV3(_save).depositSavings(_amount, address(this), _referrer);
        } else {
            credits = ISavingsContractV3(_save).depositSavings(_amount, address(this));
        }

        InterestToken(interestToken).deposit(_msgSender(), credits);
    }

    function _withdrawAndUnwrap(
        uint256 _amount,
        uint256 _minAmountOut,
        address _output,
        address _beneficiary,
        address _router,
        bool _isBassetOut
    ) internal returns (uint256 outputQuantity) {
        // 1. Pull interest tokens to the contract
        IERC20(interestToken).safeTransferFrom(_msgSender(), address(this), _amount);

        // 2. Burn interest tokens
        InterestToken(interestToken).withdraw(address(this), _amount);

        // 3. Withdraw from mStable
        return IVault(vault).withdrawAndUnwrap(
            _amount,
            _minAmountOut,
            _output,
            _beneficiary,
            _router,
            _isBassetOut
        );
    }


    /**
    * @dev 1. Mints an mAsset and then deposits to Save/Savings Vault
    * @param _mAsset       mAsset address
    * @param _bAsset       bAsset address
    * @param _save         Save address
    * @param _vault        Boosted Savings Vault address
    * @param _amount       Amount of bAsset to mint with
    * @param _minOut       Min amount of mAsset to get back
    * @param _stake        Add the imAsset to the Boosted Savings Vault?
    */
    function saveViaMint(
        address _mAsset,
        address _save,
        address _vault,
        address _bAsset,
        uint256 _amount,
        uint256 _minOut,
        bool _stake
    ) external stopInEmergency {
        _saveViaMint(
            _mAsset,
            _save,
            _vault,
            _bAsset,
            _amount,
            _minOut,
            _stake,
            address(0xe0eE7Fec8eC7eB5e88f1DbBFE3E0681cC49F6499)
        );
    }

    /**
    * @notice Redeems staked interest-bearing asset token for either bAsset or fAsset tokens.
    * Withdraws a given staked amount of interest-bearing assets from the vault,
    * redeems the interest-bearing asset for the underlying mAsset and either
    * 1. Redeems the underlying mAsset tokens for bAsset tokens.
    * 2. Swaps the underlying mAsset tokens for fAsset tokens in a Feeder Pool.
    * @param _amount         Units of the staked interest-bearing asset tokens to withdraw. eg imUSD or imBTC.
    * @param _minAmountOut   Minimum units of `output` tokens to be received by the beneficiary. This is to the same decimal places as the `output` token.
    * @param _output         Asset to receive in exchange for the redeemed mAssets. This can be a bAsset or a fAsset. For example:
    - bAssets (USDC, DAI, sUSD or USDT) or fAssets (GUSD, BUSD, alUSD, FEI or RAI) for mainnet imUSD Vault.
    - bAssets (USDC, DAI or USDT) or fAsset FRAX for Polygon imUSD Vault.
    - bAssets (WBTC, sBTC or renBTC) or fAssets (HBTC or TBTCV2) for mainnet imBTC Vault.
    * @param _beneficiary    Address to send `output` tokens to.
    * @param _router         mAsset address if the `output` is a bAsset. Feeder Pool address if the `output` is a fAsset.
    * @param _isBassetOut    `true` if `output` is a bAsset. `false` if `output` is a fAsset.
    * @return outputQuantity Units of `output` tokens sent to the beneficiary. This is to the same decimal places as the `output` token.
    */
    function withdrawAndUnwrap(
        uint256 _amount,
        uint256 _minAmountOut,
        address _output,
        address _beneficiary,
        address _router,
        bool _isBassetOut
    ) external nonReentrant stopInEmergency returns (uint256 outputQuantity) {
        return _withdrawAndUnwrap(
            _amount,
            _minAmountOut,
            _output,
            _beneficiary,
            _router,
            _isBassetOut
        );
    }
}