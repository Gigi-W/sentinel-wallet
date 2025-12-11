// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { Test } from "forge-std/Test.sol";
import { WalletFactory } from "../src/factory/WalletFactory.sol";

contract WalletFactoryTest is Test {
    WalletFactory factory;
    address user = address(0x1234);

    function setUp() public {
        factory = new WalletFactory();
    }

    function testDeployAndPredict() public {
        bytes32 salt = keccak256("sentinel");

        address predicted = factory.getAddress(user, salt);
        address deployed = factory.deploy(user,salt);

        assertEq(predicted, deployed, "address mismatch");
    }
}