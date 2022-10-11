// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library UniswapV2Library {
    using SafeMath for uint;

    function pairFor(
        address factory,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        //排序token地址
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        //根据排序的token地址计算create2的pair地址
        pair = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                        // pair合约bytecode的keccak256
                        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
                    )
                )
            )
        );
    }

    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        //确认tokenA不等于tokenB
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        //排序token地址
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        //确认token地址不等于0地址
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        //确认路径数组长度大于2
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
        //初始化数额数组
        amounts = new uint256[](path.length);
        //数额数组最后一个元素 = 输出数额
        amounts[amounts.length - 1] = amountOut;
        //从倒数第二个元素倒叙遍历路径数组
        for (uint256 i = path.length - 1; i > 0; i--) {
            //(储备量In,储备量Out) = 获取储备(上一个路径地址,当前路径地址)
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            //上一个数额 = 获取输入数额(当前数额,储备量In,储备量Out)
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB))
            .getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        //确认输出数额大于0
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        //确认储备量In和储备量Out大于0
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        //分子 = 储备量In * 储备量Out * 1000
        uint256 numerator = reserveIn.mul(amountOut).mul(1000);
        //分母 = 储备量Out - 输出数额 * 997
        uint256 denominator = reserveOut.sub(amountOut).mul(997);
        //输入数额 = (分子 / 分母) + 1
        amountIn = (numerator / denominator).add(1);
    }
}
