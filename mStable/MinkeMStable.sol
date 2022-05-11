// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC2771Context } from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

import { IMasset } from "./interfaces/IMasset.sol";
import { ISavingsContractV3 } from "./interfaces/ISavingsContract.sol";
import { IBoostedVaultWithLockup } from "./interfaces/IBoostedVaultWithLockup.sol";

contract MinkeMStable is ERC2771Context {
    using SafeERC20 for IERC20;
    // Creator of this contract.
    address public owner;

    bool public stopped = false;

    constructor(address _trustedForwarder) ERC2771Context(_trustedForwarder) {
        owner = msg.sender;
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
        if (_stake && _referrer != address(0)) {
            uint256 credits = ISavingsContractV3(_save).depositSavings(
                _amount,
                address(this),
                _referrer
            );
            IBoostedVaultWithLockup(_vault).stake(_msgSender(), credits);
        } else if (_stake && _referrer == address(0)) {
            uint256 credits = ISavingsContractV3(_save).depositSavings(_amount, address(this));
            IBoostedVaultWithLockup(_vault).stake(_msgSender(), credits);
        } else if (!_stake && _referrer != address(0)) {
            ISavingsContractV3(_save).depositSavings(_amount, _msgSender(), _referrer);
        } else {
            ISavingsContractV3(_save).depositSavings(_amount, _msgSender());
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
}