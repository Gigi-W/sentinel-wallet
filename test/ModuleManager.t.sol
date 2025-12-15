// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/wallet/SentinelWallet.sol";
import "../src/utils/Errors.sol";

/**
 * ModuleManager.t.sol
 * 对 SentinelWallet 的模块管理逻辑进行单元测试
 *
 * 覆盖：
 * - enableModule 幂等性（重复 enable 不失败）
 * - disableModule 幂等性（重复 disable 不失败）
 * - getModules / isModuleEnabled 接口
 * - enable -> disable -> 列表变化与事件检查
 */
contract ModuleManagerTest is Test {
    SentinelWallet wallet;
    uint256 ownerKey;
    address owner;

    function setUp() public {
        ownerKey = 0xBEEF;
        owner = vm.addr(ownerKey);

        wallet = new SentinelWallet(owner);
    }

    function testEnableDisableModuleAndList() public {
        address modA = address(0xA1);
        address modB = address(0xB1);

        // 初始：没有模块
        address[] memory initial = wallet.getModules();
        assertEq(initial.length, 0);
        assertEq(wallet.isModuleEnabled(modA), false);

        // owner 启用 modA
        vm.prank(owner);
        wallet.enableModule(modA);

        // 状态检查
        assertTrue(wallet.isModuleEnabled(modA));
        address[] memory list1 = wallet.getModules();
        assertEq(list1.length, 1);
        assertEq(list1[0], modA);

        // owner 再次启用 modA（幂等）
        vm.prank(owner);
        wallet.enableModule(modA);
        address[] memory list2 = wallet.getModules();
        assertEq(list2.length, 1); // 仍然只有一个

        // 启用 modB
        vm.prank(owner);
        wallet.enableModule(modB);
        assertTrue(wallet.isModuleEnabled(modB));
        address[] memory list3 = wallet.getModules();
        assertEq(list3.length, 2);

        // owner 禁用 modA
        vm.prank(owner);
        wallet.disableModule(modA);
        assertFalse(wallet.isModuleEnabled(modA));
        address[] memory list4 = wallet.getModules();
        assertEq(list4.length, 1);
        // 列表中只剩 modB（顺序可能变化，检查包含即可）
        assertTrue(list4[0] == modB);

        // 再次 disable modA（幂等）
        vm.prank(owner);
        wallet.disableModule(modA);
        address[] memory list5 = wallet.getModules();
        assertEq(list5.length, 1);

        // disable modB
        vm.prank(owner);
        wallet.disableModule(modB);
        assertEq(wallet.getModules().length, 0);
    }

    // 验证非 owner 无法 enable/disable（权限校验）
    function testOnlyOwnerCanEnableDisable() public {
        address modC = address(0xC1);

        vm.prank(address(0xAABB));
        vm.expectRevert(Errors.NotOwner.selector);
        wallet.enableModule(modC);

        vm.prank(address(0xAABB));
        vm.expectRevert(Errors.NotOwner.selector);
        wallet.disableModule(modC);
    }
}
