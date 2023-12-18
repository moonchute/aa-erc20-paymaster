// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/console.sol";

contract AAERC20 is IERC20 {
    address public immutable token;
    uint256 public immutable tokenDecimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    string public name;
    string public symbol;

    constructor(IERC20Metadata _token) {
        token = address(_token);
        name = string.concat("AA-", _token.name());
        symbol = string.concat("AA-" , _token.symbol());
        tokenDecimals = 10 ** _token.decimals();
    }

    function mint(address to, uint256 amount) external {
        IERC20(token).transferFrom(to, address(this), amount);
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        _burn(msg.sender, amount);
        IERC20(token).transfer(to, amount);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        require(value <= allowance[from][msg.sender], "AA-ERC20: transfer amount exceeds allowance");
        _transfer(from, to, value);
        allowance[from][msg.sender] -= value;
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

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
        require(owner != address(0), "AA-ERC20: approve from the zero address");
        require(spender != address(0), "AA-ERC20: approve to the zero address");
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
