// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NSDERC20 is IERC20 {
  string public constant name = "NSD Token";
  string public constant symbol = "NSD";

  uint8 public constant decimals = 18;
  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor() {}

  function _mint(address to, uint256 value) internal {
    balanceOf[to] += value;
    totalSupply += value;
    emit Transfer(address(0), to, value);
  }

  function _burn(address from, uint256 value) internal {
    balanceOf[from] -= value;
    totalSupply -= value;
    emit Transfer(from, address(0), value);
  }

  function _approve(address owner, address spender, uint256 value) internal {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");
    allowance[owner][spender] = value;
    emit Approval(owner, spender, value);
  }

  function _transfer(address from, address to, uint256 value) internal {
    balanceOf[from] -= value;
    balanceOf[to] += value;
    emit Transfer(from, to, value);
  }

  function transfer(address to, uint value) external override returns (bool) {
    _transfer(msg.sender, to, value);
    return true;
  }

  function transferFrom(address from, address to, uint value) external override returns (bool) {
    require(value <= allowance[from][msg.sender], "ERC20: transfer amount exceeds allowance");
    _transfer(from, to, value);
    allowance[from][msg.sender] -= value;
    return true;
  }

  function approve(address spender, uint value) external override returns (bool) {
    _approve(msg.sender, spender, value);
    return true;
  }
}