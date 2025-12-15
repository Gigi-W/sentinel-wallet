// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/wallet/SentinelWallet.sol";
import "../src/wallet/modules/DailyLimitModule.sol";
import "../src/wallet/modules/GuardianRecoverModule.sol";
import "../src/wallet/modules/MockModule.sol";
import "../src/utils/Errors.sol";

contract DeployExtended is Script {
    uint256 constant DEFAULT_WALLET_FUND = 2 ether;
    uint256 constant DEFAULT_DAILY_LIMIT = 1 ether;
    uint256 constant DEFAULT_TIMELOCK = 1 days;

    function run() external {
        // 读取环境变量
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 fundAmount = vm.envOr("WALLET_FUND", DEFAULT_WALLET_FUND);
        uint256 dailyLimit = vm.envOr("DAILY_LIMIT", DEFAULT_DAILY_LIMIT);
        uint256 timelock = vm.envOr("GUARDIAN_DELAY", DEFAULT_TIMELOCK);
        address guardianAddr = vm.envOr("GUARDIAN_ADDRESS", address(0));

        // 验证配置
        if (dailyLimit == 0) {
            revert Errors.DefaultLimitMustBeGreaterThanZero();
        }
        if (timelock == 0) {
            revert("Timelock must be greater than 0");
        }

        // 开始广播
        vm.startBroadcast(deployerKey);

        // 部署钱包
        address owner = msg.sender;
        SentinelWallet wallet = new SentinelWallet(owner);
        if (address(wallet) == address(0)) {
            revert Errors.DeploymentFailed();
        }
        console.log("Deployed SentinelWallet at:", address(wallet));

        // 部署模块
        DailyLimitModule daily = new DailyLimitModule(owner, dailyLimit);
        if (address(daily) == address(0)) {
            revert Errors.DeploymentFailed();
        }
        console.log("Deployed DailyLimitModule at:", address(daily));

        GuardianRecoverModule guardian = new GuardianRecoverModule(owner, timelock);
        if (address(guardian) == address(0)) {
            revert Errors.DeploymentFailed();
        }
        console.log("Deployed GuardianRecoverModule at:", address(guardian));

        MockModule mock = new MockModule();
        if (address(mock) == address(0)) {
            revert Errors.DeploymentFailed();
        }
        console.log("Deployed MockModule at:", address(mock));

        // 设置guardian（如果提供）
        if (guardianAddr != address(0)) {
            guardian.setGuardian(address(wallet), guardianAddr);
            console.log("Guardian set for wallet:", guardianAddr);
        }

        // 给wallet充值（如果金额大于0）
        if (fundAmount > 0) {
            (bool ok, ) = payable(address(wallet)).call{value: fundAmount}("");
            if (!ok) {
                revert Errors.DeploymentFailed();
            }
            console.log("Funded wallet with:", fundAmount, "wei");
        }

        // 打印部署摘要
        console.log("=== DEPLOY SUMMARY ===");
        console.log("Wallet:", address(wallet));
        console.log("Wallet balance (wei):", address(wallet).balance);
        console.log("Owner:", owner);
        console.log("DailyLimitModule:", address(daily));
        console.log("GuardianRecoverModule:", address(guardian));
        console.log("MockModule:", address(mock));
        if (guardianAddr != address(0)) {
            console.log("Guardian:", guardianAddr);
        }

        vm.stopBroadcast();
    }
}