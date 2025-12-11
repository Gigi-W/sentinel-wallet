/// 为每个钱包提供每日限额

// SPDX-License-Identifier:MIT
pragma solidity ^0.8.21;

interface ISentinelWallet{
    function execFromModule(address to, uint256 value, bytes calldata data) 
    external returns(bytes memory);
}
contract DailyLimitModule {
    address public owner;
    uint256 public deafultDailyLimit;

    mapping(address => mapping(uint256 => uint256)) public spent; // 某天已经支出的金额
    mapping(address => uint256) public walletLimit;

    event SetWalletLimit(address indexed wallet, uint256 indexed limit);
    event Exec(address indexed wallet, address indexed to, uint256 value, uint256 dayIndex);

    constructor(address _owner, uint256 _defaultDailyLimit){
        require(_owner != address(0), "Owner cannot be 0");
        require(_defaultDailyLimit > 0, "Default limit must greater than 0");
        owner = _owner;
        deafultDailyLimit = _defaultDailyLimit;
    }

    modifier onlyOnwer(){
        require(owner == msg.sender, "Not owner");
        _;
    }

    function setWalletLimit(address wallet, uint256 limit) external onlyOnwer {
        require(limit > 0, "Limit must greater than 0");
        walletLimit[wallet] = limit;
        emit SetWalletLimit(wallet, limit);
    }

    function _dayIndex() internal view returns(uint256){
        return block.timestamp / 1 days;
    }

    /// 查询钱包每日限额
    function dailyLimitFor(address wallet) public view returns (uint256) {
        uint256 l = walletLimit[wallet];
        return l == 0 ? deafultDailyLimit : l;
    }

    /// 模块执行: 计算转账金额有没有超过限额，执行操作，更新spent
    function exec(address wallet, address to, uint256 value, bytes calldata data) external returns(bytes memory){
        uint256 limit = dailyLimitFor(wallet);
        uint256 dayIndex = _dayIndex();
        uint256 dailySpent = spent[wallet][dayIndex];
        require(dailySpent + value <= limit, "Exceeding the limit");

        spent[wallet][dayIndex] += value; // 先写状态，防止重放
        bytes memory res = ISentinelWallet(wallet).execFromModule(to, value, data);
        emit Exec(wallet, to, value, dayIndex);
        return res;
    }
}