// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/wallet/SentinelWallet.sol";
import "../src/wallet/modules/DailyLimitModule.sol";
import "../src/wallet/modules/MockModule.sol";
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

    // ============ 集成测试：签名执行 ============

    function testExecWithSignatureReplay() public {
        Target target = new Target();
        // 确保钱包有足够余额
        vm.deal(address(wallet), 10 ether);
        payable(address(wallet)).transfer(1 ether);

        // 要调用的参数
        address to = address(target);
        uint256 value = 0.1 ether;
        bytes memory data = abi.encodeWithSignature("setX(uint256)", 123);
        uint256 nonceBefore = wallet.nonce();

        // 计算消息hash
        bytes32 innerHash = keccak256(abi.encodePacked(address(wallet), to, value, keccak256(data), nonceBefore, block.chainid));

        // 计算以太坊签名消息格式
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", innerHash));

        // 用私钥签名消息
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 用签名调用合约
        vm.prank(address(0xAAAE));
        wallet.executeWithSignature(to, value, data, signature);

        // nonce应该+1
        assertEq(wallet.nonce(), nonceBefore + 1);
        assertEq(target.x(), 123);

        // 同签名重放
        vm.prank(address(0xAAAE));
        vm.expectRevert(Errors.InvalidSignature.selector);
        wallet.executeWithSignature(to, value, data, signature);
    }

    // ============ 集成测试：多模块并存 ============

    function testExecFromModuleMultipleModules() public {
        DailyLimitModule daily = new DailyLimitModule(owner, 10 ether);
        MockModule mock = new MockModule();
        
        vm.prank(owner);
        wallet.enableModule(address(daily));
        vm.prank(owner);
        wallet.enableModule(address(mock));
        
        // 确保钱包有足够余额
        vm.deal(address(wallet), 10 ether);
        payable(address(wallet)).transfer(5 ether);

        Target t1 = new Target();
        Target t2 = new Target();

        // 使用mock module 发起调用
        vm.prank(address(0xAAAF));
        mock.exec(address(wallet), address(t1), 0.5 ether, abi.encodeWithSignature("setX(uint256)", 111));
        assertEq(t1.x(), 111);

        // 使用daily module的exec调用
        vm.prank(address(0xAABA));
        daily.exec(address(wallet), address(t2), 1 ether, abi.encodeWithSignature("setX(uint256)", 222));
        assertEq(t2.x(), 222);

        assertTrue(wallet.nonce() >= 2);
    }

    // ============ 集成测试：并发调用 ============

    function testConcurrentExecSameBlock() public {
        MockModule mock = new MockModule();

        vm.prank(owner);
        wallet.enableModule(address(mock));
        
        // 确保钱包有足够余额
        vm.deal(address(wallet), 10 ether);
        payable(address(wallet)).transfer(3 ether);

        Target tA = new Target();
        Target tB = new Target();

        // 保证同一个区块
        uint256 startBlock = block.number;

        // 第一次调用
        vm.prank(address(0xAAAF));
        mock.exec(address(wallet), address(tA), 0.5 ether, abi.encodeWithSignature("setX(uint256)", 111));
        // 紧接着第二次调用
        vm.prank(address(0xAABA));
        mock.exec(address(wallet), address(tB), 0.4 ether, abi.encodeWithSignature("setX(uint256)", 222));
    
        // 断言两个都会被调用
        assertEq(tA.x(), 111);
        assertEq(tB.x(), 222);

        // 确认block 还在同一区块
        assertEq(block.number, startBlock);
        // 确认nonce正确处理
        assertTrue(wallet.nonce() >= 2);
    }

    // ============ 集成测试：模块执行 nonce 递增 ============

    function testWalletNonceIncrementOnExecFromModule() public {
        MockModule mock = new MockModule();
        vm.prank(owner);
        wallet.enableModule(address(mock));
        
        // 确保钱包有足够余额（即使value为0，也需要一些余额用于gas）
        vm.deal(address(wallet), 10 ether);
        payable(address(wallet)).transfer(1 ether);

        uint256 nonceBefore = wallet.nonce();

        vm.prank(address(0xAAAA));
        mock.exec(address(wallet), address(0xBBBB), 0, abi.encodeWithSignature(""));
        assertEq(wallet.nonce(), nonceBefore + 1);
    }
}

contract Target {
    uint256 public x;
    
    function setX(uint256 _x) external payable {
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
