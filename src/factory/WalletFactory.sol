// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import "../wallet/SentinelWallet.sol";
import "../utils/Errors.sol";

contract WalletFactory{
    event WalletCreated(address indexed wallet, address indexed owner, bytes32 salt);

    function getAddress(address owner, bytes32 salt) public view returns (address predicted){
        // 合约的 CreationCode + 构造函数参数 ABI 编码
        bytes memory bytecode = abi.encodePacked(
            type(SentinelWallet).creationCode,
            abi.encode(owner)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );

        predicted = address(uint160(uint256(hash)));
    }

    function deploy(address owner, bytes32 salt) external returns (address wallet){
        if (owner == address(0)) {
            revert Errors.OwnerCannotBeZero();
        }

        wallet = address(new SentinelWallet{salt: salt}(owner));

        if (wallet == address(0)) {
            revert Errors.DeploymentFailed();
        }

        emit WalletCreated(wallet, owner, salt);
    }
}