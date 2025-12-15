// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { Test } from "forge-std/Test.sol";
import { WalletFactory } from "../src/factory/WalletFactory.sol";
import "../src/wallet/SentinelWallet.sol";
import "../src/utils/Errors.sol";

contract WalletFactoryTest is Test {
    WalletFactory factory;
    address user = address(0x1234);

    // 事件声明
    event WalletCreated(address indexed wallet, address indexed owner, bytes32 salt);

    function setUp() public {
        factory = new WalletFactory();
    }

    function testDeployAndPredict() public {
        bytes32 salt = keccak256("sentinel");

        address predicted = factory.getAddress(user, salt);
        address deployed = factory.deploy(user, salt);

        assertEq(predicted, deployed, "address mismatch");
    }

    // 测试部署零地址应该失败
    function testDeployZeroAddress() public {
        bytes32 salt = keccak256("test");
        
        vm.expectRevert(Errors.OwnerCannotBeZero.selector);
        factory.deploy(address(0), salt);
    }

    // 测试部署事件
    function testDeployEmitsEvent() public {
        bytes32 salt = keccak256("test");
        address predicted = factory.getAddress(user, salt);
        
        vm.expectEmit(true, true, false, false);
        emit WalletCreated(predicted, user, salt);
        factory.deploy(user, salt);
    }

    // 测试相同 salt 和 owner 应该得到相同地址
    function testSameSaltSameAddress() public {
        bytes32 salt = keccak256("same");
        
        address predicted1 = factory.getAddress(user, salt);
        address predicted2 = factory.getAddress(user, salt);
        
        assertEq(predicted1, predicted2);
    }

    // 测试不同 salt 得到不同地址
    function testDifferentSaltDifferentAddress() public {
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        
        address addr1 = factory.getAddress(user, salt1);
        address addr2 = factory.getAddress(user, salt2);
        
        assertNotEq(addr1, addr2);
    }

    // 测试不同 owner 得到不同地址
    function testDifferentOwnerDifferentAddress() public {
        bytes32 salt = keccak256("test");
        address user2 = address(0x5678);
        
        address addr1 = factory.getAddress(user, salt);
        address addr2 = factory.getAddress(user2, salt);
        
        assertNotEq(addr1, addr2);
    }

    // 测试部署后钱包所有者正确
    function testDeployedWalletOwner() public {
        bytes32 salt = keccak256("test");
        
        address walletAddr = factory.deploy(user, salt);
        SentinelWallet wallet = SentinelWallet(payable(walletAddr));
        
        assertEq(wallet.owner(), user);
    }

    // 测试部署后钱包 nonce 为 0
    function testDeployedWalletNonce() public {
        bytes32 salt = keccak256("test");
        
        address walletAddr = factory.deploy(user, salt);
        SentinelWallet wallet = SentinelWallet(payable(walletAddr));
        
        assertEq(wallet.nonce(), 0);
    }

    // 测试多次部署相同参数应该失败（地址已存在）
    function testDeployTwiceSameParams() public {
        bytes32 salt = keccak256("test");
        
        factory.deploy(user, salt);
        
        // 第二次部署应该失败，因为地址已存在
        // 注意：这取决于 CREATE2 的行为，如果地址已存在，部署会失败
        // 但这里主要测试工厂合约的逻辑
        vm.expectRevert();
        factory.deploy(user, salt);
    }

    // 测试 getAddress 是纯函数，不改变状态
    function testGetAddressIsView() public {
        bytes32 salt = keccak256("test");
        
        // 多次调用应该返回相同结果
        address addr1 = factory.getAddress(user, salt);
        address addr2 = factory.getAddress(user, salt);
        address addr3 = factory.getAddress(user, salt);
        
        assertEq(addr1, addr2);
        assertEq(addr2, addr3);
    }

    // 测试空 salt
    function testDeployWithEmptySalt() public {
        bytes32 salt = bytes32(0);
        
        address predicted = factory.getAddress(user, salt);
        address deployed = factory.deploy(user, salt);
        
        assertEq(predicted, deployed);
    }

    // 测试最大 salt 值
    function testDeployWithMaxSalt() public {
        bytes32 salt = bytes32(uint256(type(uint256).max));
        
        address predicted = factory.getAddress(user, salt);
        address deployed = factory.deploy(user, salt);
        
        assertEq(predicted, deployed);
    }
}