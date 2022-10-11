// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
// import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
// import "./interfaces/IUniswapV2Pair.sol";
// import "./interfaces/IUniswapV2Callee.sol";
import "./libraries/UniswapV2Library.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/ICErc20.sol";
import "./interfaces/ICEth.sol";
import "./interfaces/IComptroller.sol";

error CollateralLever__tokenBaseEqTokenQuote();
error CollateralLever__investmentAmountIsZero();
error CollateralLever__leverIsTooLow();
error CollateralLever__leverIsTooHigh();
error CollateralLever__notSupportToken(address tokenAddress);
// error CollateralLever__borrowedAmountLessThanRepayAmount();
error CollateralLever__PositionInfoNotExsit(uint256 positionId);

contract CollateralLever is IUniswapV2Callee {
    struct PositionInfo {
        address cTokenCollateralAddress;
        address cTokenBorrowingAddress;
        uint256 collateralAmountOfCollateralToken; //抵押数量        
        uint256 borrowedAmountOfBorrowingToken; //贷出数量        
        bool isShort; //是否做空
        uint256 positionId;
    }
    uint256 private constant SWAP_DEADLINE = 18000;
    address private immutable i_uniswapV2RouterAddress;
    address private immutable i_uniswapV2FactoryAddress;

    address private immutable i_comptrollerAddress;
    address[] private s_cTokenAddresses;

    address[] private s_flashSwapPath;
    mapping(address => PositionInfo[]) public s_userAddress2PositionInfos;

    constructor(
        address uniswapV2Router,
        address uniswapV2Factory,
        address[] memory cTokenAddresses,
        address comptroller
    ) {
        i_uniswapV2RouterAddress = uniswapV2Router;
        i_uniswapV2FactoryAddress = uniswapV2Factory;
        s_cTokenAddresses = cTokenAddresses;
        i_comptrollerAddress = comptroller;
    }

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
        if (lever < 2) {
            revert CollateralLever__leverIsTooLow();
        }
        if (lever > 3) {
            // compound最多能贷出75%, 对应最大杠杆为4
            revert CollateralLever__leverIsTooHigh();
        }

        //资金转移到本合约
        address investmentToken = investmentIsQuote ? tokenQuote : tokenBase;
        _safeApprove(investmentToken, address(this), investmentAmount);
        IERC20(investmentToken).transferFrom(msg.sender, address(this), investmentAmount);

        address collateralToken;
        address borrowingToken;

        //calculate originalCollateralAmount初始抵押量
        uint256 originalCollateralAmount = investmentAmount;
        if (isShort) {
            collateralToken = tokenQuote;
            borrowingToken = tokenBase;
        } else {
            collateralToken = tokenBase;
            borrowingToken = tokenQuote;
        }

        //投入的token不是抵押物token, 则需swap
        if (investmentToken != collateralToken) {
            address[] memory path = new address[](2);
            if (collateralToken == tokenBase) {
                path[0] = tokenQuote;
                path[1] = tokenBase;
            } else {
                path[0] = tokenBase;
                path[1] = tokenQuote;
            }
            originalCollateralAmount = _swapToCollateral(
                investmentAmount,
                path,
                address(this),
                _getDeadline()
            );
        }

        //flashswap
        uint256 flashSwapAmountOfCollateralToken = originalCollateralAmount * (lever - 1);
        address pair = UniswapV2Library.pairFor(i_uniswapV2FactoryAddress, tokenBase, tokenQuote);
        bytes memory data = abi.encodePacked(
            collateralToken,
            borrowingToken,
            originalCollateralAmount,
            msg.sender,
            isShort,
            true //开仓:true, 平仓: false
        );
        (address token0, address token1) = UniswapV2Library.sortTokens(tokenBase, tokenQuote);
        uint256 amount0;
        uint256 amount1;
        if (token0 == collateralToken) {
            amount0 = flashSwapAmountOfCollateralToken;
        } else {
            amount1 = flashSwapAmountOfCollateralToken;
        }
        address[] memory path = new address[](2);
        path[0] = borrowingToken;
        path[1] = collateralToken;
        s_flashSwapPath = path;
        IUniswapV2Pair(pair).swap(amount0, amount1, address(this), data);
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 flashSwapAmount,
        bytes calldata data
    ) external {
        (
            address collateralTokenOrCToken, //开仓对应于token, 平仓对应于cToken
            address borrowingTokenOrCToken, //开仓对应于token, 平仓对应于cToken
            uint256 originalCollateralAmount,//仅用于_callbackForOpenPosition
            address user,
            bool isShort,
            bool isOpenPosition
        ) = abi.decode(data, (address, address, uint256, address, bool, bool));
        isOpenPosition
            ? _callbackForOpenPosition(
                flashSwapAmount,//对应的token是collateralToken
                collateralTokenOrCToken,
                borrowingTokenOrCToken,
                originalCollateralAmount,
                user,
                isShort
            )
            : _callbackForClosePosition(
                flashSwapAmount, //对应的token是borrowingToken
                collateralTokenOrCToken,
                borrowingTokenOrCToken,
                user,
                isShort
            );
    }

    function _callbackForClosePosition(
        uint256 flashSwapAmount,
        address collateralCTokenAddress,
        address borrowingCTokenAddress,
        address user,
        bool isShort
    ) internal {
       
    }

    function _callbackForOpenPosition(
        uint256 flashSwapAmountOfCallateralToken,
        address collateralToken,
        address borrowingToken,
        uint256 originalCollateralAmount,
        address user,
        bool isShort
    ) internal {
        //获得对应的cTokenAddress
        address cTokenCollateral;
        address cTokenBorrowing;
        address tempAddress;
        address[] memory ctokenAddresses = s_cTokenAddresses;
        uint256 len = ctokenAddresses.length;
        for (uint256 i = 0; i < len; ++i) {
            tempAddress = ctokenAddresses[i];
            if (ICErc20(tempAddress).underlying() == collateralToken) {
                cTokenCollateral = tempAddress;
            } else if (ICErc20(tempAddress).underlying() == borrowingToken) {
                cTokenBorrowing = tempAddress;
            }
            if (cTokenCollateral != address(0) && cTokenBorrowing != address(0)) {
                break;
            }
        }
        if (cTokenCollateral == address(0)) {
            revert CollateralLever__notSupportToken(collateralToken);
        }
        if (cTokenBorrowing == address(0)) {
            revert CollateralLever__notSupportToken(borrowingToken);
        }

        // compound borrow
        uint256 borrowAmountOfBorrowingToken = IUniswapV2Router(i_uniswapV2RouterAddress).getAmountsIn(
            flashSwapAmountOfCallateralToken,
            s_flashSwapPath
        )[0];
        uint256 totalCollateralAmount = flashSwapAmountOfCallateralToken + originalCollateralAmount;
        _borrow(
            cTokenCollateral,
            cTokenBorrowing,
            totalCollateralAmount,
            borrowAmountOfBorrowingToken
        );        

        //还闪电贷
        address pair = UniswapV2Library.pairFor(i_uniswapV2FactoryAddress, collateralToken, borrowingToken);
        IERC20(s_flashSwapPath[0]).transfer(pair, borrowAmountOfBorrowingToken);

        //保存仓位信息
        PositionInfo[] memory positions = s_userAddress2PositionInfos[user];
        uint256 positionId = positions.length > 0 ? positions[positions.length - 1].positionId : 1;
        positions.push(
            PositionInfo(
                cTokenCollateral,
                cTokenBorrowing,
                totalCollateralAmount,     
                borrowAmountOfBorrowingToken,           
                isShort,
                positionId
            )
        );
        s_userAddress2PositionInfos[user] = positions;
    }

    function closePosition(
        uint256 positionId,
        uint256 repayAmountOfBorrowingToken //平仓数量
    ) external {
        PositionInfo memory positionInfo;
        PositionInfo[] memory positions = s_userAddress2PositionInfos[msg.sender];
        for (uint256 i = 0; i < positions.length; ++i) {
            if (positions[i].positionId == positionId) {
                positionInfo = positions[i];
                break;
            }
        }
        if (positionInfo.positionId == 0) {
            revert CollateralLever__PositionInfoNotExsit(positionId);
        }

        uint256 flashSwapAmountOfBorrowingToken = repayAmountOfBorrowingToken >
            positionInfo.borrowedAmountOfBorrowingToken
            ? positionInfo.borrowedAmountOfBorrowingToken
            : repayAmountOfBorrowingToken;

        address collateralTokenAddress = ICErc20(positionInfo.cTokenCollateralAddress)
            .underlying();
        address borrowingTokenAddress = ICErc20(positionInfo.cTokenBorrowingAddress).underlying();

        address pair = UniswapV2Library.pairFor(
            i_uniswapV2FactoryAddress,
            collateralTokenAddress,
            borrowingTokenAddress
        );

        bytes memory data = abi.encodePacked(
            positionInfo.cTokenCollateralAddress,
            positionInfo.cTokenBorrowingAddress,
            0,
            msg.sender,
            positionInfo.isShort,
            false //开仓:true, 平仓: false
        );
        (address token0, address token1) = UniswapV2Library.sortTokens(collateralTokenAddress, borrowingTokenAddress);
        uint256 amount0;
        uint256 amount1;
        if (token0 == borrowingTokenAddress) {
            amount0 = flashSwapAmountOfBorrowingToken;
        } else {
            amount1 = flashSwapAmountOfBorrowingToken;
        }
        address[] memory path = new address[](2);
        path[0] = collateralTokenAddress;
        path[1] = borrowingTokenAddress;
        s_flashSwapPath = path;
        IUniswapV2Pair(pair).swap(amount0, amount1, address(this), data);
    }

    // 参考 https://github.com/compound-developers/compound-borrow-examples/blob/master/contracts/MyContracts.sol
    function _borrow(
        address collateralCTokenAddress,
        address borrowingCTokenAddress,
        uint256 collateralAmountOfCallateralToken,
        uint256 borrowAmount
    ) internal  {
        IComptroller comptroller = IComptroller(i_comptrollerAddress);
        ICErc20 collateralCToken = ICErc20(collateralCTokenAddress);
        IERC20 underlying = IERC20(collateralCToken.underlying());
        ICErc20 borrowingCToken = ICErc20(borrowingCTokenAddress);

        // Approve transfer of underlying
        underlying.approve(collateralCTokenAddress, collateralAmountOfCallateralToken);

        // Supply underlying as collateral, get cToken in return
        uint256 error = collateralCToken.mint(collateralAmountOfCallateralToken);
        require(error == 0, "CErc20.mint Error");

        // // Enter the market so you can borrow another type of asset
        // address[] memory cTokens = new address[](1);
        // cTokens[0] = collateralCTokenAddress;
        // uint256[] memory errors = comptroller.enterMarkets(cTokens);
        // if (errors[0] != 0) {
        //     revert("Comptroller.enterMarkets failed.");
        // }
        borrowingCToken.borrow(borrowAmount);

        // uint256 borrows = borrowingCToken.borrowBalanceCurrent(address(this));
    }

    function _swapToCollateral(
        uint256 amountIn,
        address[] memory path,
        address to,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        uint256[] memory amounts = IUniswapV2Router(i_uniswapV2RouterAddress)
            .swapExactTokensForTokens(amountIn, 0, path, to, deadline);
        return amounts[1];
    }

    function _getDeadline() internal view returns (uint256) {
        return block.timestamp + 600; //10 minutes
    }

    function _safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        require(IERC20(token).approve(to, value), "APPROVE_FAILED");
    }

    // getter function--------------------------------------
    function getUniswapV2RouterAddress() external view returns (address) {
        return i_uniswapV2RouterAddress;
    }

    function getUniswapV2FactoryAddress() external view returns (address) {
        return i_uniswapV2FactoryAddress;
    }
}
