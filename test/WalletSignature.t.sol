// SPDX-License-Identifier:MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/wallet/SentinelWallet.sol";
import "../src/utils/Errors.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract WalletSignatureTest is Test{
    using ECDSA for bytes32;

    SentinelWallet wallet;
    uint256 ownerKey; // 私钥使用vm.sign
    address owner;

    function setUp() public {
        ownerKey = 0xBEEF; // 任意私钥（测试专用）
        owner = vm.addr(ownerKey);
        wallet = new SentinelWallet(owner);
        vm.deal(address(wallet), 10 ether); // 钱包初始余额10 ETH
    }

    function _buildHashForSigning(
        address _to, uint256 _value, bytes memory _data, uint256 _nonce
    ) internal view returns (bytes32){
        bytes32 h = keccak256(abi.encodePacked(address(wallet), _to, _value, keccak256(_data), _nonce, block.chainid));
        // 计算以太坊签名消息格式
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
        return ethSignedHash;
    }

    /// 准备操作数据 → 生成唯一签名哈希 → 模拟所有者签名 → 模拟第三方提交签名执行 → 验证操作结果和 nonce 递增
    function testExecuteWithSignatureSucceeds() public{
        address target = address(new TargetContract());
        bytes memory data = abi.encodeWithSignature("setX(uint256)", 123);

        uint256 transferValue = 1 ether;
        uint256 walletBeforeBalance = address(wallet).balance;
        uint256 targetBeforeBalance = target.balance;
        uint256 currentNonce = wallet.nonce();

        /// 生成签名所需的唯一哈希
        bytes32 h = _buildHashForSigning(target, transferValue, data, currentNonce);

        /// 模拟所有者签名生成签名数据
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, h); // 用所有者私钥对哈希h签名
        bytes memory signature = abi.encodePacked(r,s,v);

        vm.prank(address(0xDEAD)); // 模拟以任意第三方地址（0xDEAD）发起调用
        wallet.executeWithSignature(target, transferValue, data, signature); // 调用钱包的签名执行函数

        assertEq(TargetContract(target).x(), 123);
        assertEq(address(wallet).balance, walletBeforeBalance - transferValue);
        assertEq(target.balance, targetBeforeBalance + transferValue);
        assertEq(wallet.nonce(), currentNonce + 1);

        console2.log("Target Final Balance:", address(target).balance / 1 ether, "ETH");
        console2.log("Wallet Final Balance:", address(wallet).balance / 1 ether, "ETH");
    }

    // 使用其他私钥对消息hash签名
    function testExecuteWithInvalidSignatureReverts() public{
        address target = address(new TargetContract());
        bytes memory data = abi.encodeWithSignature("setX(uint256)", 999);

        uint256 currentNonce = wallet.nonce();
        bytes32 h = _buildHashForSigning(target, 0, data, currentNonce);

        uint256 otherKey = 0xCAFE;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherKey, h);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(address(0xDEAD));
        vm.expectRevert(Errors.InvalidSignature.selector);
        wallet.executeWithSignature(target, 0, data, signature);

        assertEq(wallet.nonce(), currentNonce);
    }

    /// 同签名二次调用，重放攻击
    function testExecuteWithDoubleSignature() public{
        address target = address(new TargetContract());
        bytes memory data = abi.encodeWithSignature("setX(uint256)", 123);
        uint256 currentNonce = wallet.nonce();

        /// 生成签名所需的唯一哈希
        bytes32 h = _buildHashForSigning(target, 0, data, currentNonce);

        /// 模拟所有者签名生成签名数据
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, h); // 用所有者私钥对哈希h签名
        bytes memory signature = abi.encodePacked(r,s,v);

        vm.prank(address(0xDEAD)); // 模拟以任意第三方地址（0xDEAD）发起调用
        wallet.executeWithSignature(target,0,data,signature); // 调用钱包的签名执行函数

        assertEq(TargetContract(target).x(), 123);
        assertEq(wallet.nonce(), currentNonce + 1);

        /// 模拟同签名第二次调用
        vm.prank(address(0xAAA));
        vm.expectRevert(Errors.InvalidSignature.selector);
        wallet.executeWithSignature(target,0,data,signature);

        assertEq(TargetContract(target).x(), 123);
    }

    /// 跨合约签名重放，在另一个钱包地址复用签名
    function testExecuteCrossContract() public {
        address target = address(new TargetContract());
        bytes memory data = abi.encodeWithSignature("setX(uint256)", 999);
        uint256 currentNonce = wallet.nonce();

        // 钱包2
        SentinelWallet wallet2 = new SentinelWallet(owner);
        vm.deal(address(wallet2), 10 ether);

        bytes32 h = _buildHashForSigning(target, 0, data, currentNonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, h);
        bytes memory signature = abi.encodePacked(r,s,v);

        vm.prank(address(0xAEDA));
        wallet.executeWithSignature(target, 0, data, signature);

        assertEq(wallet.nonce(), currentNonce + 1);
        assertEq(TargetContract(target).x(), 999);

        vm.prank(address(0xAAAB));
        vm.expectRevert(Errors.InvalidSignature.selector);
        wallet2.executeWithSignature(target, 0, data, signature);
    }

    /// 跨链攻击
    function testExecuteCrossChain() public {
        address target = address(new TargetContract());
        bytes memory data = abi.encodeWithSignature("setX(uint256)", 222);
        uint256 currentNonce = wallet.nonce();

        bytes32 h = _buildHashForSigning(target, 0, data, currentNonce);

        bytes32 h2 = keccak256(abi.encodePacked(address(wallet), target, uint256(0), keccak256(data), currentNonce, block.chainid+1));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, h);
        bytes memory signature = abi.encodePacked(r,s,v);
        
        // 用正确的签名恢复消息哈希2的公钥，匹配失败
        address recover2 = MessageHashUtils.toEthSignedMessageHash(h2).recover(signature);
        assertTrue(recover2 != owner);

        vm.prank(address(0xAAAC));
        wallet.executeWithSignature(target, 0, data, signature);
        assertEq(wallet.nonce(), currentNonce + 1);
        assertEq(TargetContract(target).x(), 222);
    }
}

contract TargetContract {
    uint256 public x;
    function setX(uint256 _x) external payable{
        x = _x;
    }
}