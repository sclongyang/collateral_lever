// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error CollateralLever__tokenBaseEqTokenQuote();
error CollateralLever__investmentAmountIsZero();

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract CollateralLever {
    address private immutable i_uniswapV2RouterAddress;
    uint256 private constant SWAP_DEADLINE = 18000;

    constructor(address uniswapV2Router) {
        i_uniswapV2RouterAddress = uniswapV2Router;
    }

    function deposit() external payable {}

    function openPosition(
        address tokenBase,
        address tokenQuote,
        uint256 investmentAmount,
        bool investmentIsQuote,
        uint256 lever,
        bool isShort
    ) external {
        if (tokenBase == tokenQuote) {
            revert CollateralLever__tokenBaseEqTokenQuote();
        }
        if (investmentAmount == 0) {
            revert CollateralLever__investmentAmountIsZero();
        }

        address tokenForFlashSwap;
        bool investmentNeedSwap;

        //calculate originalCollateralAmount初始抵押量
        uint256 originalCollateralAmount = investmentAmount;
        if (isShort) {
            tokenForFlashSwap = tokenQuote;
            investmentNeedSwap = investmentIsQuote ? false : true;
        } else {
            tokenForFlashSwap = tokenBase;
            investmentNeedSwap = investmentIsQuote ? true : false;
        }
        if (investmentNeedSwap) {
            address[] memory path = new address[](2);
            if (tokenForFlashSwap == tokenBase) {
                path[0] = tokenQuote;
                path[1] = tokenBase;
            } else {
                path[0] = tokenBase;
                path[1] = tokenQuote;
            }
            originalCollateralAmount = _swapToCollateral(
                investmentAmount,
                path,
                msg.sender, /*swap给用户*/
                _getDeadline()
            );
        }

        //calculate flashswap amount


        // uint256 flashAmount =
    }

    function _swapToCollateral(
        uint256 amountIn,
        address[] memory path,
        address to,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        _safeDelegateApprove(path[0], i_uniswapV2RouterAddress, amountIn);
        uint256[] memory amounts = IUniswapV2Router(i_uniswapV2RouterAddress)
            .swapExactTokensForTokens(amountIn, 0, path, to, deadline);
        return amounts[1];
    }

    function _getDeadline() internal view returns (uint256) {
        return block.timestamp + 600; //10 minutes
    }

    function _safeDelegateApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.delegatecall(
            abi.encodeWithSelector(0x095ea7b3, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: APPROVE_FAILED"
        );
    }

    // getter function--------------------------------------
    function getUniswapV2RouterAddress() external view returns (address) {
        return i_uniswapV2RouterAddress;
    }
}
