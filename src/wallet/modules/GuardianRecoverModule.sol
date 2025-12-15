/// 典型守护者机制，处理私钥丢失/恢复资产等情况，用户可以授权可信地址更改所有者
/// Guardian(监护人)提出owner恢复请求 -> 延时 -> 执行换owner

// SPDX-License-Identifier:MIT
pragma solidity ^0.8.21;

import "../../interfaces/ISentinelWallet.sol";
import "../../interfaces/IModule.sol";
import "../../utils/Errors.sol";

contract GuardianRecoverModule is IModule {
    address owner;
    uint256 delay;

    mapping(address => address) public guardianOf;
    struct Proposal{
        address proposed;
        uint256 at;
    }

    mapping(address => Proposal) public proposals;

    event GuardianSet(address indexed wallet, address indexed guardian);
    event RecoveryProposed(address indexed wallet, address indexed guardian, address indexed proposed, uint256 at);
    event RecoveryFinalized(address indexed wallet, address indexed newOwner);

    constructor(address _owner, uint256 _delay){
        owner = _owner;
        delay = _delay;
    }

    /// @inheritdoc IModule
    function moduleType() external pure returns (ModuleType) {
        return ModuleType.Recovery;
    }

    /// @inheritdoc IModule
    function moduleName() external pure returns (string memory) {
        return "GuardianRecoverModule";
    }

    /// @inheritdoc IModule
    function moduleVersion() external pure returns (string memory) {
        return "1.0.0";
    }

    modifier onlyOwner(){
        if (owner != msg.sender) {
            revert Errors.NotOwner();
        }
        _;
    }

    // 设置守护者，onlyOwner
    function setGuardian(address wallet, address guardian) external onlyOwner {
        if (guardian == address(0)) {
            revert Errors.GuardianCannotBeZero();
        }
        guardianOf[wallet] = guardian;
        emit GuardianSet(wallet, guardian);
    }

    // guardian发起提议
    function proposeRecovery(address wallet, address proposed) external {
        if (proposed == address(0)) {
            revert Errors.ProposedCannotBeZero();
        }
        address guardian = guardianOf[wallet];
        if (guardian != msg.sender) {
            revert Errors.NotGuardian();
        }

        proposals[wallet] = Proposal({
            proposed: proposed,
            at: block.timestamp
        });

        emit RecoveryProposed(wallet, guardian, proposed, block.timestamp);
    }

    // 让提议生效，任何人可执行
    function finalizeRecovery(address wallet) external {
        Proposal memory proposal = proposals[wallet];
        address proposed = proposal.proposed;

        if (block.timestamp < proposal.at + delay) {
            revert Errors.DelayNotPassed();
        }

        delete proposals[wallet];
        ISentinelWallet(wallet).changeOwnerByModule(proposed);
        emit RecoveryFinalized(wallet, proposed);
    }
}

