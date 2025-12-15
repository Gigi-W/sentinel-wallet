// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { Test } from "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/wallet/SentinelWallet.sol";
import "../src/wallet/modules/GuardianRecoverModule.sol";
import "../src/interfaces/IModule.sol";
import "../src/utils/Errors.sol";

contract GuardianRecoveryModuleTest is Test {
    SentinelWallet wallet;
    GuardianRecoverModule guardianMod;

    uint256 ownerKey;
    address owner;

    // 事件声明
    event GuardianSet(address indexed wallet, address indexed guardian);
    event RecoveryProposed(address indexed wallet, address indexed guardian, address indexed proposed, uint256 at);
    event RecoveryFinalized(address indexed wallet, address indexed newOwner);

    function setUp() public {
        ownerKey = 0xBEEF;
        owner = vm.addr(ownerKey);

        wallet = new SentinelWallet(owner);

        guardianMod = new GuardianRecoverModule(owner, 1 days);

        vm.prank(owner);
        wallet.enableModule(address(guardianMod));
    }

    // 正常恢复流程
    function testRecovery() public {
        address guardian = address(0xAAAA);
        address newOwner = address(0xAAAB);

        vm.prank(owner);
        guardianMod.setGuardian(address(wallet), guardian); // owner 改为 guardian

        vm.prank(guardian);
        guardianMod.proposeRecovery(address(wallet), newOwner);

        vm.expectRevert(Errors.DelayNotPassed.selector);
        guardianMod.finalizeRecovery(address(wallet));

        vm.warp(block.timestamp + 1 days + 1); // 1天后再执行
        guardianMod.finalizeRecovery(address(wallet));

        assertEq(wallet.owner(), newOwner);
    }

    /// 二次调用
    function testDoubleFinalizeRejected() public {
        address guardian = address(0xAAAA);
        address newOwner = address(0xAAAB);

        vm.prank(owner);
        guardianMod.setGuardian(address(wallet), guardian);
        vm.prank(guardian);
        guardianMod.proposeRecovery(address(wallet), newOwner);

        vm.warp(block.timestamp + 1 days + 1);

        // 第一次 finalize 应成功
        guardianMod.finalizeRecovery(address(wallet));
        assertEq(wallet.owner(), newOwner);

        // 第二次调用失败，因为proposal被删除，proposed为0地址
        vm.expectRevert();
        guardianMod.finalizeRecovery(address(wallet));
    }

    // 在timelock未到之前，guardian再次propose，应该覆盖之前的proposal
    function testProposeOverwriteAndFinalize() public {
        address guardian = address(0xAABB);
        address ownerA = address(0xAAAA);
        address ownerB = address(0xAAAB);

        vm.prank(owner);
        guardianMod.setGuardian(address(wallet), guardian);
        vm.prank(guardian);
        guardianMod.proposeRecovery(address(wallet), ownerA);

        // 在timelock未到之前，guardian再次propose
        vm.prank(guardian);
        guardianMod.proposeRecovery(address(wallet), ownerB);

        vm.warp(block.timestamp + 1 days + 1);
        guardianMod.finalizeRecovery(address(wallet));
        assertEq(wallet.owner(), ownerB);
    }

    // 测试模块接口方法
    function testModuleInterface() public {
        assertEq(uint256(guardianMod.moduleType()), 3); // Recovery
        assertEq(keccak256(bytes(guardianMod.moduleName())), keccak256(bytes("GuardianRecoverModule")));
        assertEq(keccak256(bytes(guardianMod.moduleVersion())), keccak256(bytes("1.0.0")));
    }

    // 测试设置守护者为零地址
    function testSetGuardianZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Errors.GuardianCannotBeZero.selector);
        guardianMod.setGuardian(address(wallet), address(0));
    }

    // 测试非所有者设置守护者
    function testSetGuardianByNonOwner() public {
        address guardian = address(0xAAAA);
        
        vm.prank(address(0x1234)); // 非所有者
        vm.expectRevert(Errors.NotOwner.selector);
        guardianMod.setGuardian(address(wallet), guardian);
    }

    // 测试设置守护者事件
    function testSetGuardianEmitsEvent() public {
        address guardian = address(0xAAAA);
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit GuardianSet(address(wallet), guardian);
        guardianMod.setGuardian(address(wallet), guardian);
    }

    // 测试非守护者发起提议
    function testProposeRecoveryByNonGuardian() public {
        address guardian = address(0xAAAA);
        address newOwner = address(0xAAAB);
        
        vm.prank(owner);
        guardianMod.setGuardian(address(wallet), guardian);
        
        vm.prank(address(0x1234)); // 非守护者
        vm.expectRevert(Errors.NotGuardian.selector);
        guardianMod.proposeRecovery(address(wallet), newOwner);
    }

    // 测试提议零地址
    function testProposeRecoveryZeroAddress() public {
        address guardian = address(0xAAAA);
        
        vm.prank(owner);
        guardianMod.setGuardian(address(wallet), guardian);
        
        vm.prank(guardian);
        vm.expectRevert(Errors.ProposedCannotBeZero.selector);
        guardianMod.proposeRecovery(address(wallet), address(0));
    }

    // 测试提议事件
    function testProposeRecoveryEmitsEvent() public {
        address guardian = address(0xAAAA);
        address newOwner = address(0xAAAB);
        
        vm.prank(owner);
        guardianMod.setGuardian(address(wallet), guardian);
        
        vm.prank(guardian);
        vm.expectEmit(true, true, true, true);
        emit RecoveryProposed(address(wallet), guardian, newOwner, block.timestamp);
        guardianMod.proposeRecovery(address(wallet), newOwner);
    }

    // 测试最终化事件
    function testFinalizeRecoveryEmitsEvent() public {
        address guardian = address(0xAAAA);
        address newOwner = address(0xAAAB);
        
        vm.prank(owner);
        guardianMod.setGuardian(address(wallet), guardian);
        
        vm.prank(guardian);
        guardianMod.proposeRecovery(address(wallet), newOwner);
        
        vm.warp(block.timestamp + 1 days + 1);
        
        vm.expectEmit(true, true, false, false);
        emit RecoveryFinalized(address(wallet), newOwner);
        guardianMod.finalizeRecovery(address(wallet));
    }

    // 测试没有守护者时发起提议
    function testProposeRecoveryWithoutGuardian() public {
        address newOwner = address(0xAAAB);
        
        vm.prank(address(0xAAAA)); // 尝试作为守护者，但未设置
        vm.expectRevert(Errors.NotGuardian.selector);
        guardianMod.proposeRecovery(address(wallet), newOwner);
    }

    // 测试没有提议时最终化
    function testFinalizeRecoveryWithoutProposal() public {
        // 没有提议时，proposal.at 为 0，proposal.proposed 为 0
        // 检查 block.timestamp < 0 + delay，如果当前时间小于 delay，会触发 DelayNotPassed
        // 如果当前时间大于 delay，会通过时间检查，然后触发 OwnerCannotBeZero
        // 在测试环境中，通常当前时间小于 delay，所以会触发 DelayNotPassed
        vm.expectRevert(Errors.DelayNotPassed.selector);
        guardianMod.finalizeRecovery(address(wallet));
    }

    // 测试精确延迟时间
    function testFinalizeRecoveryAtExactDelay() public {
        address guardian = address(0xAAAA);
        address newOwner = address(0xAAAB);
        
        vm.prank(owner);
        guardianMod.setGuardian(address(wallet), guardian);
        
        vm.prank(guardian);
        uint256 proposalTime = block.timestamp;
        guardianMod.proposeRecovery(address(wallet), newOwner);
        
        // 正好在延迟时间（block.timestamp == proposalTime + delay）
        // 代码检查是 block.timestamp < proposal.at + delay
        // 如果相等，条件为 false，会通过检查
        vm.warp(proposalTime + 1 days);
        
        // 在精确延迟时间，应该可以通过（因为条件是 <，不是 <=）
        guardianMod.finalizeRecovery(address(wallet));
        assertEq(wallet.owner(), newOwner);
    }

    // 测试多个钱包的守护者恢复
    function testMultipleWallets() public {
        SentinelWallet wallet2 = new SentinelWallet(owner);
        address guardian = address(0xAAAA);
        address newOwner1 = address(0xAAAB);
        address newOwner2 = address(0xAACC);
        
        vm.prank(owner);
        wallet2.enableModule(address(guardianMod));
        
        // 为两个钱包设置守护者
        vm.prank(owner);
        guardianMod.setGuardian(address(wallet), guardian);
        vm.prank(owner);
        guardianMod.setGuardian(address(wallet2), guardian);
        
        // 为两个钱包发起提议
        vm.prank(guardian);
        guardianMod.proposeRecovery(address(wallet), newOwner1);
        vm.prank(guardian);
        guardianMod.proposeRecovery(address(wallet2), newOwner2);
        
        vm.warp(block.timestamp + 1 days + 1);
        
        // 最终化两个钱包
        guardianMod.finalizeRecovery(address(wallet));
        guardianMod.finalizeRecovery(address(wallet2));
        
        assertEq(wallet.owner(), newOwner1);
        assertEq(wallet2.owner(), newOwner2);
    }
}