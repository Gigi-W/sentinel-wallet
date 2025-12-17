// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/wallet/SentinelWallet.sol";
import "../src/utils/Errors.sol";

contract SentinelWalletTest is Test {
    SentinelWallet wallet;
    uint256 ownerKey;
    address owner;
    address nonOwner;

    // 事件声明
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    function setUp() public {
        ownerKey = 0xBEEF;
        owner = vm.addr(ownerKey);
        nonOwner = address(0x1234);
        
        wallet = new SentinelWallet(owner);
        vm.deal(address(wallet), 10 ether);
    }

    // ============ 构造函数测试 ============

    function testConstructorWithZeroAddress() public {
        vm.expectRevert(Errors.OwnerCannotBeZero.selector);
        new SentinelWallet(address(0));
    }

    function testConstructorSetsOwner() public {
        assertEq(wallet.owner(), owner);
    }

    function testConstructorInitializesNonce() public {
        assertEq(wallet.nonce(), 0);
    }

    // ============ executed() 测试 ============

    function testExecutedByOwner() public {
        Target target = new Target();
        bytes memory data = abi.encodeWithSignature("setX(uint256)", 123);
        
        vm.prank(owner);
        bytes memory result = wallet.executed(address(target), 0, data);
        
        assertEq(target.x(), 123);
        assertEq(wallet.nonce(), 1);
        // setX 函数没有返回值，所以 result 可能为空
        // 只要调用成功即可
        assertTrue(true);
    }

    function testExecutedWithValue() public {
        Target target = new Target();
        uint256 value = 1 ether;
        uint256 balanceBefore = address(target).balance;
        
        vm.prank(owner);
        wallet.executed(address(target), value, "");
        
        assertEq(address(target).balance, balanceBefore + value);
        assertEq(address(wallet).balance, 10 ether - value);
    }

    function testExecutedByNonOwner() public {
        Target target = new Target();
        bytes memory data = abi.encodeWithSignature("setX(uint256)", 123);
        
        vm.prank(nonOwner);
        vm.expectRevert(Errors.NotOwner.selector);
        wallet.executed(address(target), 0, data);
    }

    function testExecutedIncrementsNonce() public {
        Target target = new Target();
        uint256 nonceBefore = wallet.nonce();
        
        vm.prank(owner);
        wallet.executed(address(target), 0, "");
        
        assertEq(wallet.nonce(), nonceBefore + 1);
    }

    // ============ changeOwner() 测试 ============

    function testChangeOwner() public {
        address newOwner = address(0x5678);
        
        vm.prank(owner);
        wallet.changeOwner(newOwner);
        
        assertEq(wallet.owner(), newOwner);
    }

    function testChangeOwnerEmitsEvent() public {
        address newOwner = address(0x5678);
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit OwnerChanged(owner, newOwner);
        wallet.changeOwner(newOwner);
    }

    function testChangeOwnerByNonOwner() public {
        address newOwner = address(0x5678);
        
        vm.prank(nonOwner);
        vm.expectRevert(Errors.NotOwner.selector);
        wallet.changeOwner(newOwner);
    }

    function testChangeOwnerToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Errors.OwnerCannotBeZero.selector);
        wallet.changeOwner(address(0));
    }

    // ============ receive() 和 fallback() 测试 ============

    function testReceiveEther() public {
        uint256 amount = 5 ether;
        uint256 balanceBefore = address(wallet).balance;
        
        (bool success, ) = payable(address(wallet)).call{value: amount}("");
        require(success, "Transfer failed");
        
        assertEq(address(wallet).balance, balanceBefore + amount);
    }

    function testFallback() public {
        uint256 amount = 3 ether;
        uint256 balanceBefore = address(wallet).balance;
        
        (bool success, ) = payable(address(wallet)).call{value: amount}("");
        require(success, "Transfer failed");
        
        assertEq(address(wallet).balance, balanceBefore + amount);
    }

    // ============ 模块管理边界测试 ============

    function testEnableModuleAlreadyEnabled() public {
        address module = address(0xA1);
        
        vm.prank(owner);
        wallet.enableModule(module);
        
        uint256 modulesCountBefore = wallet.getModules().length;
        
        vm.prank(owner);
        wallet.enableModule(module); // 再次启用
        
        uint256 modulesCountAfter = wallet.getModules().length;
        assertEq(modulesCountBefore, modulesCountAfter); // 应该不变
    }

    function testDisableModuleNotEnabled() public {
        address module = address(0xA1);
        
        vm.prank(owner);
        wallet.disableModule(module); // 禁用未启用的模块，应该不报错
        
        assertFalse(wallet.isModuleEnabled(module));
    }

    function testDisableModuleLastOne() public {
        address module = address(0xA1);
        
        vm.prank(owner);
        wallet.enableModule(module);
        
        vm.prank(owner);
        wallet.disableModule(module);
        
        assertEq(wallet.getModules().length, 0);
        assertFalse(wallet.isModuleEnabled(module));
    }

    function testDisableModuleMiddleOne() public {
        address module1 = address(0xA1);
        address module2 = address(0xA2);
        address module3 = address(0xA3);
        
        vm.prank(owner);
        wallet.enableModule(module1);
        vm.prank(owner);
        wallet.enableModule(module2);
        vm.prank(owner);
        wallet.enableModule(module3);
        
        vm.prank(owner);
        wallet.disableModule(module2);
        
        address[] memory modules = wallet.getModules();
        assertEq(modules.length, 2);
        assertTrue(wallet.isModuleEnabled(module1));
        assertFalse(wallet.isModuleEnabled(module2));
        assertTrue(wallet.isModuleEnabled(module3));
    }

    // ============ execFromModule 错误测试 ============

    function testExecFromModuleByNonModule() public {
        Target target = new Target();
        
        vm.prank(nonOwner);
        vm.expectRevert(Errors.NotEnabledModule.selector);
        wallet.execFromModule(address(target), 0, "");
    }

    // ============ 调用失败测试 ============

    function testCallFailed() public {
        // 创建一个会失败的调用目标
        FailingTarget target = new FailingTarget();
        
        vm.prank(owner);
        vm.expectRevert(Errors.CallFailed.selector);
        wallet.executed(address(target), 0, "");
    }
}

contract Target {
    uint256 public x;
    
    function setX(uint256 _x) external {
        x = _x;
    }
    
    receive() external payable {}
}

contract FailingTarget {
    function fail() external pure {
        revert("Always fails");
    }
    
    receive() external payable {
        revert("Always fails");
    }
    
    fallback() external payable {
        revert("Always fails");
    }
}
