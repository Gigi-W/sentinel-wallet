// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { Test } from "forge-std/Test.sol";
import "../src/wallet/SentinelWallet.sol";
import "../src/wallet/modules/DailyLimitModule.sol";
import "../src/interfaces/IModule.sol";
import "../src/utils/Errors.sol";

contract TestDailyLimitModule is Test {
    SentinelWallet wallet;
    DailyLimitModule daily;

    uint256 ownerKey;
    address owner;

    // 事件声明
    event SetWalletLimit(address indexed wallet, uint256 indexed limit);

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
        vm.expectRevert(Errors.ExceedingDailyLimit.selector);
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

    // 测试正好达到限额
    function testExecAtLimit() public {
        vm.deal(address(wallet), 1 ether);
        TargetContract t = new TargetContract();
        
        vm.prank(address(0xAAAD));
        daily.exec(address(wallet), address(t), 1 ether, abi.encodeWithSignature("setX(uint256)", 99));
        
        assertEq(t.x(), 99);
        uint256 day = block.timestamp / 1 days;
        assertEq(daily.spent(address(wallet), day), 1 ether);
    }

    // 测试设置钱包限额
    function testSetWalletLimit() public {
        address wallet2 = address(0x5678);
        uint256 customLimit = 5 ether;
        
        vm.prank(address(0xAAAB)); // module owner
        daily.setWalletLimit(wallet2, customLimit);
        
        assertEq(daily.walletLimit(wallet2), customLimit);
        assertEq(daily.dailyLimitFor(wallet2), customLimit);
    }

    // 测试设置零限额应该失败
    function testSetWalletLimitZero() public {
        address wallet2 = address(0x5678);
        
        vm.prank(address(0xAAAB));
        vm.expectRevert(Errors.LimitMustBeGreaterThanZero.selector);
        daily.setWalletLimit(wallet2, 0);
    }

    // 测试非所有者设置限额
    function testSetWalletLimitByNonOwner() public {
        address wallet2 = address(0x5678);
        
        vm.prank(address(0xAAAD)); // 非所有者
        vm.expectRevert(Errors.NotOwner.selector);
        daily.setWalletLimit(wallet2, 5 ether);
    }

    // 测试 dailyLimitFor 返回默认限额
    function testDailyLimitForDefault() public {
        address wallet2 = address(0x5678);
        assertEq(daily.dailyLimitFor(wallet2), 1 ether); // 默认限额
    }

    // 测试 dailyLimitFor 返回自定义限额
    function testDailyLimitForCustom() public {
        address wallet2 = address(0x5678);
        uint256 customLimit = 3 ether;
        
        vm.prank(address(0xAAAB));
        daily.setWalletLimit(wallet2, customLimit);
        
        assertEq(daily.dailyLimitFor(wallet2), customLimit);
    }

    // 测试模块接口方法
    function testModuleInterface() public {
        assertEq(uint256(daily.moduleType()), 0); // Executor
        assertEq(keccak256(bytes(daily.moduleName())), keccak256(bytes("DailyLimitModule")));
        assertEq(keccak256(bytes(daily.moduleVersion())), keccak256(bytes("1.0.0")));
    }

    // 测试构造函数错误情况
    function testConstructorWithZeroOwner() public {
        vm.expectRevert(Errors.OwnerCannotBeZero.selector);
        new DailyLimitModule(address(0), 1 ether);
    }

    function testConstructorWithZeroLimit() public {
        vm.expectRevert(Errors.DefaultLimitMustBeGreaterThanZero.selector);
        new DailyLimitModule(address(0xAAAB), 0);
    }

    // 测试跨天限额重置
    function testDailyLimitResets() public {
        vm.deal(address(wallet), 2 ether);
        TargetContract t = new TargetContract();
        
        // 第一天：使用1 ether
        vm.prank(address(0xAAAD));
        daily.exec(address(wallet), address(t), 1 ether, abi.encodeWithSignature("setX(uint256)", 11));
        
        uint256 day1 = block.timestamp / 1 days;
        assertEq(daily.spent(address(wallet), day1), 1 ether);
        
        // 第二天：应该可以再次使用1 ether
        vm.warp(block.timestamp + 1 days);
        uint256 day2 = block.timestamp / 1 days;
        assertEq(daily.spent(address(wallet), day2), 0); // 新的一天，支出为0
        
        vm.prank(address(0xAAAD));
        daily.exec(address(wallet), address(t), 1 ether, abi.encodeWithSignature("setX(uint256)", 22));
        
        assertEq(daily.spent(address(wallet), day2), 1 ether);
    }

    // 测试事件
    function testSetWalletLimitEmitsEvent() public {
        address wallet2 = address(0x5678);
        uint256 customLimit = 5 ether;
        
        vm.prank(address(0xAAAB));
        vm.expectEmit(true, true, false, false);
        emit SetWalletLimit(wallet2, customLimit);
        daily.setWalletLimit(wallet2, customLimit);
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

    receive() external payable {}

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

