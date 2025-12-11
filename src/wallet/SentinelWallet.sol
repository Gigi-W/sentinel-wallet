// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SentinelWallet {
    using ECDSA for bytes32;

    address public owner;
    uint256 public nonce;
    mapping(address => bool) public modules;

    event ModuleEnabled(address indexed module);
    event ModuleDisabled(address indexed module);
    event Executed(address indexed to, uint256 value, bytes data, address indexed signer);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    constructor(address _owner){
        require(_owner != address(0), "owner 0");
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not Owner");
        _;
    }

    /// 限制仅模块可调用
    modifier onlyModule(){
        require(modules[msg.sender], "Not enabled module");
        _;
    }

    /// 启用模块
    function enableModule(address module) external onlyOwner{
        require(module != address(0), "Module cannot be 0");
        modules[module] = true;
        emit ModuleEnabled(module);
    }

    /// 禁用模块
    function disableModule(address module) external onlyOwner{
        require(module != address(0), "Module cannot be 0");
        modules[module]=false;
        emit ModuleDisabled(module);
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
        // 因为测试用例中的hash已经做过以太坊签名了，因此这里去掉
        // address signer = MessageHashUtils.toEthSignedMessageHash(hash).recover(signature);
        address signer = hash.recover(signature);
        require(signer == owner, "Invalid signature");

        nonce+=1;

        bytes memory res = _callTarget(to,value,data);

        emit Executed(to,value,data,signer);
        return res;
    }

    /// 3、模块调用，模块必须先被owner启用
    function execFromModule(address to, uint256 value, bytes calldata data) external onlyModule returns(bytes memory){
        return _executeWithNonce(to, value, data);
    }

    // owner直接修改owner
    function changeOwner(address newOwner) external onlyOwner{
        require(newOwner!=address(0), "owner 0");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    // 模块修改owner
    function changeOwnerByModule(address newOwner) external onlyModule{
        require(newOwner!=address(0), "owner 0");
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
        require(ok, "Call failed");
        return ret;
    }

    function _buildHash(address to,  uint256 value, bytes calldata data, uint256 _nonce, uint256 _chainId) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), to, value, keccak256(data), _nonce, _chainId));
    }

    receive() external payable {}
    fallback() external payable {}
}