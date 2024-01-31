// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {UniswapPaymasterSwap} from "src/swap/UniswapPaymasterSwap.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Minimal} from "v3-core/contracts/interfaces/IERC20Minimal.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

contract UniswapPaymasterSwapTest is Test {
    UniswapPaymasterSwap public paymasterSwap;
    address public owner;
    address public router;

    function setUp() public {
        string memory rpcId = vm.envString("POLYGON_RPC_URL");
        uint256 forkId = vm.createFork(rpcId);
        vm.selectFork(forkId);
        owner = makeAddr("owner");

        // Uniswap SwapRouter
        router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        // WMATIC
        address token0 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        // USDC
        address token1 = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        uint24 fee = 100;

        paymasterSwap = new UniswapPaymasterSwap(router, token0, fee);
        paymasterSwap.initialize(abi.encodePacked(token1));

        deal(token1, owner, 1 ether);
        deal(token1, address(paymasterSwap), 1 ether);
    }

    function testCanSwap() public {
        // WMATIC/USDC 1% pool
        address pool = 0x0a6c4588b7D8Bd22cF120283B1FFf953420c45F3;

        uint128 amount = 10;
        vm.expectCall(router, abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector));
        vm.expectCall(pool, abi.encodeWithSelector(bytes4(keccak256("swap(address,bool,int256,uint160,bytes)"))));
        uint256 amountOut = paymasterSwap.swap(amount);
        assertNotEq(amountOut, 0);
    }
}
