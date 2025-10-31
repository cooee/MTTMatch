// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MTTToken {
    string public name = "MTT Token";
    string public symbol = "MTT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(uint256 _totalSupply) {
        totalSupply = _totalSupply * 10**decimals;  // 转换为最小单位
        balanceOf[msg.sender] = totalSupply;        // 部署者获得所有代币
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    
    function transfer(address to, uint256 value) public returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function approve(address spender, uint256 value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        
        emit Transfer(from, to, value);
        return true;
    }
    
    // 方便测试：任何人都可以铸造代币给自己
    function mint(uint256 amount) public {
        uint256 mintAmount = amount * 10**decimals;
        balanceOf[msg.sender] += mintAmount;
        totalSupply += mintAmount;
        emit Transfer(address(0), msg.sender, mintAmount);
    }
}