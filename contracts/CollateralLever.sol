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
// import "./interfaces/IComptroller.sol";

error CollateralLever__tokenBaseEqTokenQuote();
error CollateralLever__investmentAmountIsZero();
error CollateralLever__leverIsTooLow();
error CollateralLever__leverIsTooHigh();
error CollateralLever__approveFailed();
error CollateralLever__transferFailed();
error CollateralLever__CErc20MintFailed();
error CollateralLever__cErc20RedeemUnderlyingFailed();
error CollateralLever__cErc20BorrowFailed();
error CollateralLever__cErc20RepayBorrowFailed();
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

    // address private immutable i_comptrollerAddress;
    address[] private s_cTokenAddresses;

    address[] private s_flashSwapPath;
    mapping(address => PositionInfo[]) public s_userAddress2PositionInfos;

    constructor(
        address uniswapV2Router,
        address uniswapV2Factory,
        address[] memory cTokenAddresses
        // address comptroller
    ) {
        i_uniswapV2RouterAddress = uniswapV2Router;
        i_uniswapV2FactoryAddress = uniswapV2Factory;
        s_cTokenAddresses = cTokenAddresses;
        // i_comptrollerAddress = comptroller;
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
            true, //开仓:true, 平仓: false
            uint256(0) //没有positionId
        );
        (address token0, ) = UniswapV2Library.sortTokens(tokenBase, tokenQuote);
        uint256 amount0;
        uint256 amount1;
        if (token0 == collateralToken) {
            amount0 = flashSwapAmountOfCollateralToken;
        } else {
            amount1 = flashSwapAmountOfCollateralToken;
        }
        address[] memory flashSwapPath = new address[](2);
        flashSwapPath[0] = borrowingToken;
        flashSwapPath[1] = collateralToken;
        s_flashSwapPath = flashSwapPath;
        IUniswapV2Pair(pair).swap(amount0, amount1, address(this), data);
    }

    function closePosition(uint256 positionId)
        external
    // uint256 repayAmountOfBorrowingToken //平仓数量    第一版暂不使用该参数, 只实现全量平仓
    {
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

        // uint256 flashSwapAmountOfBorrowingToken = repayAmountOfBorrowingToken >
        //     positionInfo.borrowedAmountOfBorrowingToken
        //     ? positionInfo.borrowedAmountOfBorrowingToken
        //     : repayAmountOfBorrowingToken;
        uint256 flashSwapAmountOfBorrowingToken = positionInfo.borrowedAmountOfBorrowingToken; //第一版只实现 全量平仓

        //是否平仓全量
        bool isCloseAllAmount = flashSwapAmountOfBorrowingToken ==
            positionInfo.borrowedAmountOfBorrowingToken;

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
            positionInfo.collateralAmountOfCollateralToken,
            msg.sender,
            isCloseAllAmount,
            false, //开仓:true, 平仓: false
            positionId
        );
        (address token0, ) = UniswapV2Library.sortTokens(
            collateralTokenAddress,
            borrowingTokenAddress
        );
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

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 flashSwapAmount,
        bytes calldata data
    ) external override {
        (
            address collateralTokenOrCToken, //开仓对应于token, 平仓对应于cToken
            address borrowingTokenOrCToken, //开仓对应于token, 平仓对应于cToken
            uint256 originalOrTotalCollateralAmount, //开仓对应于origin, 平仓对应于total
            address user,
            bool flag,
            bool isOpenPosition,
            uint256 positionId //仅用于_callbackForClosePosition
        ) = abi.decode(data, (address, address, uint256, address, bool, bool, uint256));
        isOpenPosition
            ? _callbackForOpenPosition(
                flashSwapAmount, //对应的token是collateralToken
                collateralTokenOrCToken,
                borrowingTokenOrCToken,
                originalOrTotalCollateralAmount,
                user,
                flag //代表 isShort
            )
            : _callbackForClosePosition(
                flashSwapAmount, //对应的token是borrowingToken
                collateralTokenOrCToken,
                borrowingTokenOrCToken,
                originalOrTotalCollateralAmount,
                user,
                flag, //代表 isCloseAllAmount 是否平仓全量
                positionId
            );
    }

    function _callbackForClosePosition(
        uint256 flashSwapAmountOfBorrowingToken,
        address collateralCTokenAddress,
        address borrowingCTokenAddress,
        uint256 totalCollateralAmountOfCollateralToken,
        address user,
        bool isCloseAllAmount,
        uint256 positionId
    ) internal {
        ICErc20 borrowingCToken = ICErc20(borrowingCTokenAddress);
        ICErc20 collateralCToken = ICErc20(collateralCTokenAddress);
        address borrowingTokenAddress = borrowingCToken.underlying();
        address collateralTokenAddress = collateralCToken.underlying();

        _safeApprove(
            borrowingTokenAddress,
            borrowingCTokenAddress,
            flashSwapAmountOfBorrowingToken
        );
        // -1 表示全额还款，包括所有利息
        uint256 error = borrowingCToken.repayBorrow(
            isCloseAllAmount ? type(uint256).max : flashSwapAmountOfBorrowingToken
        );
        if (error != 0) {
            revert CollateralLever__cErc20RepayBorrowFailed();
        }

        //闪电贷还款金额
        uint256 repayAmountOfCollateralTokenForFlash = IUniswapV2Router(i_uniswapV2RouterAddress)
            .getAmountsIn(flashSwapAmountOfBorrowingToken, s_flashSwapPath)[0];

        uint256 transferAmountToUser;
        // 赎回:cToken=>token
        if (isCloseAllAmount) {
            error = collateralCToken.redeemUnderlying(totalCollateralAmountOfCollateralToken);
            if (error != 0) {
                revert CollateralLever__cErc20RedeemUnderlyingFailed();
            }

            transferAmountToUser =
                totalCollateralAmountOfCollateralToken -
                repayAmountOfCollateralTokenForFlash;
        } else {
            //todo: 第一版不会到这里, 后续版本考虑此情况
            require(false, "cannot be here");
        }

        //还闪电贷
        address pair = UniswapV2Library.pairFor(
            i_uniswapV2FactoryAddress,
            collateralTokenAddress,
            borrowingTokenAddress
        );
        _safeTransfer(s_flashSwapPath[0], pair, repayAmountOfCollateralTokenForFlash);

        //transfer to user
        _safeTransfer(collateralTokenAddress, user, transferAmountToUser);

        //第一版直接删除仓位信息
        PositionInfo[] memory positions = s_userAddress2PositionInfos[user];//saving gas
        uint256 len = positions.length;
        uint256 idx = type(uint256).max;
        for (uint256 i = 0; i < len; i++) {
            if (positions[i].positionId == positionId) {
                idx = i;
                break;
            }
        }
        if(idx != type(uint256).max){
            delete s_userAddress2PositionInfos[user][idx]; //会产生gap, 可考虑优化
        }        
    }

    function _callbackForOpenPosition(
        uint256 flashSwapAmountOfCallateralToken,
        address collateralToken,
        address borrowingToken,
        uint256 originalCollateralAmountOfCollateralToken,
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
        uint256 borrowAmountOfBorrowingToken = IUniswapV2Router(i_uniswapV2RouterAddress)
            .getAmountsIn(flashSwapAmountOfCallateralToken, s_flashSwapPath)[0];
        uint256 totalCollateralAmount = flashSwapAmountOfCallateralToken +
            originalCollateralAmountOfCollateralToken;
        _borrow(
            cTokenCollateral,
            cTokenBorrowing,
            totalCollateralAmount,
            borrowAmountOfBorrowingToken
        );

        //还闪电贷
        address pair = UniswapV2Library.pairFor(
            i_uniswapV2FactoryAddress,
            collateralToken,
            borrowingToken
        );
        _safeTransfer(s_flashSwapPath[0], pair, borrowAmountOfBorrowingToken);

        //保存仓位信息
        PositionInfo[] memory positions = s_userAddress2PositionInfos[user];
        uint256 positionId = positions.length > 0
            ? positions[positions.length - 1].positionId + 1
            : 1;
        s_userAddress2PositionInfos[user].push(
            PositionInfo(
                cTokenCollateral,
                cTokenBorrowing,
                totalCollateralAmount,
                borrowAmountOfBorrowingToken,
                isShort,
                positionId
            ));
    }

    // 参考 https://github.com/compound-developers/compound-borrow-examples/blob/master/contracts/MyContracts.sol
    function _borrow(
        address collateralCTokenAddress,
        address borrowingCTokenAddress,
        uint256 collateralAmountOfCallateralToken,
        uint256 borrowAmount
    ) internal {
        // IComptroller comptroller = IComptroller(i_comptrollerAddress);
        ICErc20 collateralCToken = ICErc20(collateralCTokenAddress);
        ICErc20 borrowingCToken = ICErc20(borrowingCTokenAddress);

        // Approve transfer of underlying
        _safeApprove(
            collateralCToken.underlying(),
            collateralCTokenAddress,
            collateralAmountOfCallateralToken
        );

        // Supply underlying as collateral, get cToken in return
        uint256 error = collateralCToken.mint(collateralAmountOfCallateralToken);
        if (error != 0) {
            revert CollateralLever__CErc20MintFailed();
        }

        // // Enter the market so you can borrow another type of asset
        // address[] memory cTokens = new address[](1);
        // cTokens[0] = collateralCTokenAddress;
        // uint256[] memory errors = comptroller.enterMarkets(cTokens);
        // if (errors[0] != 0) {
        //     revert("Comptroller.enterMarkets failed.");
        // }
        error = borrowingCToken.borrow(borrowAmount);
        if (error != 0) {
            revert CollateralLever__cErc20BorrowFailed();
        }

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
        if (!IERC20(token).approve(to, value)) {
            revert CollateralLever__approveFailed();
        }
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        if (!IERC20(token).transfer(to, value)) {
            revert CollateralLever__transferFailed();
        }
    }

    // getter function--------------------------------------
    function getUniswapV2RouterAddress() external view returns (address) {
        return i_uniswapV2RouterAddress;
    }

    function getUniswapV2FactoryAddress() external view returns (address) {
        return i_uniswapV2FactoryAddress;
    }
}
