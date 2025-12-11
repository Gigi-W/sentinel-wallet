// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { Test } from "forge-std/Test.sol";
import "../src/wallet/SentinelWallet.sol";
import "../src/wallet/modules/DailyLimitModule.sol";

contract TestDailyLimitModule is Test {
    SentinelWallet wallet;
    DailyLimitModule daily;

    uint256 ownerKey;
    address owner;

    function setUp() public {
        ownerKey = 0xBEEF;
        owner = vm.addr(ownerKey);

        wallet = new SentinelWallet(owner);

        daily = new DailyLimitModule(address(0xAAAB), 1 ether);

        // 启用Daily module
        vm.prank(owner);
        wallet.enableModule(address(daily));
    }



    // 限额内正常转账
    function testExecWithInLimit() public {
        vm.deal(address(wallet), 1 ether);
        TargetContract t = new TargetContract();
        vm.prank(address(0xAAAD));
        daily.exec(address(wallet), address(t), 0.5 ether, abi.encodeWithSignature("setX(uint256)", 11));

        assertEq(t.x(),11);
        uint256 day = block.timestamp / 1 days;
        assertEq(daily.spent(address(wallet), day), 0.5 ether);
    }

    // 超限额 revert
    function testExceed() public {
        vm.deal(address(wallet), 2 ether);
        TargetContract t = new TargetContract();
        vm.prank(address(0xAAAD));
        daily.exec(address(wallet), address(t), 1 ether, abi.encodeWithSignature("setX(uint256)", 22));

        assertEq(t.x(), 22);
        uint256 day = block.timestamp / 1 days;
        assertEq(daily.spent(address(wallet), day), 1 ether);

        vm.prank(address(0xAAAD));
        vm.expectRevert("Exceeding the limit");
        daily.exec(address(wallet), address(t), 1 ether, abi.encodeWithSignature("setX(uint256)", 22));
    }

    // 重入攻击尝试
    function testReentrycy() public {
        vm.deal(address(wallet), 2 ether);
        TargetContract victim = new TargetContract();

        // 部署恶意合约
        MaliciousTarget malicious = (new MaliciousTarget{value: 0}(address(daily), address(wallet), address(victim), 0.6 ether));
        vm.prank(address(0xAAAD));
        daily.exec(address(wallet), address(malicious), 0.6 ether, abi.encodeWithSignature("setX(uint256)", 33));

        // victim 不应被二次更新（若发生双花 victim.x==999）
        assertEq(victim.x(), 0, "victim should not have been updated");

        uint256 day = block.timestamp / 1 days;
        assertEq(daily.spent(address(wallet), day), 0.6 ether);
    }
}

contract MaliciousTarget {
    address public module;
    address public walletAddr;
    address public victim; // 想让Module双花
    uint256 public attackValue;

    constructor(address _module, address _walletAddr, address _victim, uint256 _attackValue) payable{
        module = _module;
        walletAddr = _walletAddr;
        victim = _victim;
        attackValue = _attackValue;
    }

    fallback() external payable{
        (bool ok,) = module.call(
            abi.encodeWithSignature(
                "exec(address,address,uint256,bytes)", 
                walletAddr,
                victim,
                attackValue,
                abi.encodeWithSignature("setX(uint256)", 999)
            )
        );
        ok;
    }
}

contract TargetContract {
    uint256 public x;
    function setX(uint256 _x) external payable {
        x = _x;
    }
}

