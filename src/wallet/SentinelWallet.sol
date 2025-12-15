// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../utils/Errors.sol";

contract SentinelWallet {
    using ECDSA for bytes32;

    address public owner;
    uint256 public nonce;
    
    // 标记模块是否启用
    mapping(address => bool) private modulesEnabled;
    // 存储所有已启用模块的模块地址
    address[] private modulesList;
    // 记录「模块地址」在modulesList中的「索引+1」，为了和索引0（不存在）做区分
    mapping(address => uint256) public modulesIndexPlusOne;

    event ModuleEnabled(address indexed module);
    event ModuleDisabled(address indexed module);
    event ExecFromModule(address module, address to, uint256 value, bytes data);
    event Executed(address indexed to, uint256 value, bytes data, address indexed signer);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    constructor(address _owner){
        if (_owner == address(0)) {
            revert Errors.OwnerCannotBeZero();
        }
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert Errors.NotOwner();
        }
        _;
    }

    /// 限制仅模块可调用
    modifier onlyModule(){
        if (!modulesEnabled[msg.sender]) {
            revert Errors.NotEnabledModule();
        }
        _;
    }

    /// 模块是否启用
    function isModuleEnabled(address module) external view returns (bool) {
        return modulesEnabled[module];
    } 

    /// 返回模块列表
    function getModules() external view returns(address[] memory) {
        return modulesList;
    }

    /// 启用模块
    function enableModule(address module) external onlyOwner{
        if (module == address(0)) {
            revert Errors.ModuleCannotBeZero();
        }
        if(modulesEnabled[module]){
            return;
        }
        modulesEnabled[module] = true;
        modulesList.push(module);
        modulesIndexPlusOne[module] = modulesList.length;
        emit ModuleEnabled(module);
    }

    /// 禁用模块
    function disableModule(address module) external onlyOwner{
        if (module == address(0)) {
            revert Errors.ModuleCannotBeZero();
        }
        if(!modulesEnabled[module]){
            return;
        }
        modulesEnabled[module]=false;
        // 从模块列表中删除
        uint256 idxPlusOne = modulesIndexPlusOne[module];
        if(idxPlusOne!=0){
            uint256 idx = idxPlusOne - 1;
            uint256 lastIdx = modulesList.length - 1;
            if(idx!=lastIdx){
                address last = modulesList[lastIdx];
                modulesList[idx] = last;
                modulesIndexPlusOne[last] = idx + 1;
            }
            modulesList.pop();
            // 标记不在列表中
            modulesIndexPlusOne[module] = 0;
            emit ModuleDisabled(module);
        }
    }

    /// 1、所有者调用executed → 校验权限 → 递增 nonce → 调用目标地址
    function executed(address to, uint256 value, bytes calldata data) external onlyOwner returns(bytes memory result){
        return _executeWithNonce(to, value, data);
    }


    // 2、第三方签名调用 → 验证签名 → 递增 nonce → 调用目标地址
    function executeWithSignature(
        address to, uint256 value, bytes calldata data, bytes calldata signature
    ) external returns (bytes memory){
        bytes32 hash = _buildHash(to,value,data,nonce, block.chainid);
        address signer = MessageHashUtils.toEthSignedMessageHash(hash).recover(signature);
        if (signer != owner) {
            revert Errors.InvalidSignature();
        }

        nonce+=1;

        bytes memory res = _callTarget(to,value,data);

        emit Executed(to,value,data,signer);
        return res;
    }

    /// 3、模块调用，模块必须先被owner启用
    function execFromModule(address to, uint256 value, bytes calldata data) external onlyModule returns(bytes memory){
        nonce += 1;
        bytes memory res = _callTarget(to,value,data);
        emit ExecFromModule(msg.sender, to, value, data);
        return res;
    }

    // owner直接修改owner
    function changeOwner(address newOwner) external onlyOwner{
        if (newOwner == address(0)) {
            revert Errors.OwnerCannotBeZero();
        }
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    // 模块修改owner
    function changeOwnerByModule(address newOwner) external onlyModule{
        if (newOwner == address(0)) {
            revert Errors.OwnerCannotBeZero();
        }
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function _executeWithNonce(address to, uint256 value, bytes calldata data) internal returns(bytes memory){
        nonce += 1;
        bytes memory res = _callTarget(to,value,data);
        emit Executed(to, value, data, msg.sender);
        return res;
    }

    function _callTarget(address to, uint256 value, bytes calldata data) internal returns (bytes memory){
        (bool ok, bytes memory ret) = to.call{value: value}(data);
        if (!ok) {
            revert Errors.CallFailed();
        }
        return ret;
    }

    function _buildHash(address to,  uint256 value, bytes calldata data, uint256 _nonce, uint256 _chainId) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), to, value, keccak256(data), _nonce, _chainId));
    }

    receive() external payable {}
    fallback() external payable {}
}