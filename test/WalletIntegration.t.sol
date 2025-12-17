// SPDX-License-Identifier:MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/wallet/SentinelWallet.sol";
import "../src/wallet/modules/DailyLimitModule.sol";
import "../src/wallet/modules/MockModule.sol";
import "../src/utils/Errors.sol";

contract WalletIntegrationTest is Test {
    SentinelWallet wallet;
    DailyLimitModule daily;

    uint256 ownerKey;
    address owner;

    function setUp() public {
        ownerKey = 0xDEEF;
        owner = vm.addr(ownerKey);

        wallet = new SentinelWallet(owner);

        daily = new DailyLimitModule(owner, 10 ether);

        vm.prank(owner);
        wallet.enableModule(address(daily));
    }

    // 1、测试签名重放
    function testExecWithSignatureReplay() public {
        Target target = new Target();
        payable(address(wallet)).transfer(1 ether);

        // 要调用的参数
        address to = address(target);
        uint256 value = 0.1 ether;
        bytes memory data = abi.encodeWithSignature("setX(uint256)", 123);
        uint256 nonceBefore = wallet.nonce();

        // 计算消息hash
        bytes32 innerHash = keccak256(abi.encodePacked(address(wallet),to,value,keccak256(data),nonceBefore,block.chainid));

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

        // 同签名重放
        vm.prank(address(0xAAAE));
        vm.expectRevert(Errors.InvalidSignature.selector);
        wallet.executeWithSignature(to, value, data, signature);
    }

    // 2、多module并存测试
    function testExecFromModule_mutipleModules() public {
        MockModule mock = new MockModule();
        vm.prank(owner);
        wallet.enableModule(address(mock));
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

    // 3、同一区块内"并发"调用一致性
    function testConcurrentExecSameBlock() public {
        MockModule mock = new MockModule();

        vm.prank(owner);
        wallet.enableModule(address(mock));
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

    // 4、单独测试 nonce 会被正确增加
    function testWalletNonceIncrementOnExecFromModule() public {
        MockModule mock = new MockModule();
        vm.prank(owner);
        wallet.enableModule(address(mock));
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
}
