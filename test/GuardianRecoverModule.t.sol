// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { Test } from "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/wallet/SentinelWallet.sol";
import "../src/wallet/modules/GuardianRecoverModule.sol";

contract GuardianRecoveryModuleTest is Test {
    SentinelWallet wallet;
    GuardianRecoverModule guardianMod;

    uint256 ownerKey;
    address owner;

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

        vm.expectRevert("Delay not passed");
        guardianMod.finalizeRecovery(address(wallet));

        vm.warp(block.timestamp + 1 days + 1); // 1天后再执行
        guardianMod.finalizeRecovery(address(wallet));

        console2.log(wallet.owner());
        console2.log(newOwner);

        assertEq(wallet.owner(), newOwner);
    }
}