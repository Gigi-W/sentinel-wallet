// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

contract MockModule {
    function exec(address walletAddr, address to, uint256 value, bytes calldata data) external returns (bytes memory) {
        (bool ok, bytes memory ret) = address(walletAddr).call(
            abi.encodeWithSignature("execFromModule(address,uint256,bytes)", to, value ,data)
        );

        require(ok, "MockModule: wallet.execFromModule failed");
        return ret;
    }
}