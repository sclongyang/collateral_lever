// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
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

error CollateralLever__notOwnerOfPosition();
error CollateralLever__notFindPosition(address user, uint256 positionId);
error CollateralLever__callerIsNotUniswapPair();
error CollateralLever__tokenNotSupport(address token);
error CollateralLever__tokenBaseEqTokenQuote();
error CollateralLever__investmentAmountIsZero();
error CollateralLever__leverIsWrong();
error CollateralLever__approveFailed();
error CollateralLever__transferFailed();
error CollateralLever__transferFromFailed();
error CollateralLever__CErc20MintFailed();
error CollateralLever__cErc20RedeemUnderlyingFailed();
error CollateralLever__cErc20BorrowFailed();
error CollateralLever__cErc20RepayBorrowFailed();

// error CollateralLever__borrowedAmountLessThanRepayAmount();

contract CollateralLever is IUniswapV2Callee, Ownable, ReentrancyGuard {
    struct PositionInfo {
        address cTokenCollateralAddress;
        address cTokenBorrowingAddress;
        uint256 collateralAmountOfCollateralToken; //抵押数量
        uint256 borrowedAmountOfBorrowingToken; //贷出数量
        bool isShort; //是否做空
        uint256 positionId;
    }

    event AddSupportedCToken(address cTokenAddress);
    event OpenPositionSucc(address user, PositionInfo positionInfo);
    event ClosePositionSucc(address user, uint256 positionId);

    uint256 private constant SWAP_DEADLINE = 600;
    uint256 private constant UINT256_MAX = type(uint256).max;

    //Patrick Collins recommend naming style
    address private immutable i_uniswapV2RouterAddress;
    address private immutable i_uniswapV2FactoryAddress;

    address private immutable i_comptrollerAddress;
    address[] private s_flashSwapPath;
    mapping(address => address) public s_token2CToken; //underlying token address to ctoken address
    mapping(address => PositionInfo[]) public s_userAddress2PositionInfos;

    //是否持有仓位
    modifier OwnerOfPosition(address user, uint256 positionId) {
        (uint256 idx, ) = _findPosition(user, positionId);
        if (idx == UINT256_MAX) {
            revert CollateralLever__notOwnerOfPosition();
        }
        _;
    }

    constructor(
        address uniswapV2Router,
        address uniswapV2Factory,
        address comptroller,
        address[] memory cTokenAddresses
    ) {
        i_uniswapV2RouterAddress = uniswapV2Router;
        i_uniswapV2FactoryAddress = uniswapV2Factory;
        i_comptrollerAddress = comptroller;

        for (uint256 i = 0; i < cTokenAddresses.length; ++i) {
            s_token2CToken[ICErc20(cTokenAddresses[i]).underlying()] = cTokenAddresses[i];
        }
    }

    receive() external payable {
        //todo 第一版仅支持ERC20
    }

    function addSupportedCToken(address cTokenAddress) external onlyOwner {
        s_token2CToken[ICErc20(cTokenAddress).underlying()] = cTokenAddress;
        emit AddSupportedCToken(cTokenAddress);
    }

    function openPosition(
        address tokenBase,
        address tokenQuote,
        uint256 investmentAmount,
        bool investmentIsQuote,
        uint256 lever,
        bool isShort
    ) external {
        console.log("start open position");
        if (tokenBase == tokenQuote) {
            revert CollateralLever__tokenBaseEqTokenQuote();
        }
        if (investmentAmount == 0) {
            revert CollateralLever__investmentAmountIsZero();
        }
        if (lever > 3 || lever < 2) {
            // compound eth最多能贷出75%, 对应极限杠杆为4
            revert CollateralLever__leverIsWrong();
        }
        _checkTokenSupported(tokenBase);
        _checkTokenSupported(tokenQuote);

        //资金转移到本合约
        address investmentToken = investmentIsQuote ? tokenQuote : tokenBase;
        // _safeApprove(investmentToken, address(this), investmentAmount);

        console.log(
            "before transfer to this: %s",
            _ERC20BalanceOf(investmentToken, address(this))
        );

        _safeTransferFrom(investmentToken, msg.sender, address(this), investmentAmount);

        console.log("after transfer to this: %s", _ERC20BalanceOf(investmentToken, address(this)));

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
                block.timestamp + SWAP_DEADLINE
            );
        }

        //flashswap
        uint256 flashSwapAmountOfCollateralToken = originalCollateralAmount * (lever - 1);
        address pair = UniswapV2Library.pairFor(i_uniswapV2FactoryAddress, tokenBase, tokenQuote);
        bytes memory data = abi.encode(
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

        console.log("originalCollateralAmount: %s", originalCollateralAmount);
        console.log("flashSwapAmountOfCollateralToken: %s", flashSwapAmountOfCollateralToken);
        console.log("start flash swap");

        IUniswapV2Pair(pair).swap(amount0, amount1, address(this), data);
    }

    function closePosition(
        uint256 positionId // uint256 repayAmountOfBorrowingToken //平仓数量    第一版暂不使用该参数, 只实现全量平仓
    ) external OwnerOfPosition(msg.sender, positionId) {
        console.log("start close postion");

        (, PositionInfo memory positionInfo) = _findPosition(msg.sender, positionId);

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

        bytes memory data = abi.encode(
            positionInfo.cTokenCollateralAddress,
            positionInfo.cTokenBorrowingAddress,
            positionInfo.collateralAmountOfCollateralToken,
            msg.sender,
            isCloseAllAmount,
            false, //开仓:true, 平仓: false
            positionInfo.positionId
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
        console.log("flashSwapAmountOfBorrowingToken: %s", flashSwapAmountOfBorrowingToken);
        console.log("start flash swap of close postion");

        IUniswapV2Pair(pair).swap(amount0, amount1, address(this), data);
    }    

     function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 flashSwapAmount,
        bytes calldata data
    ) external override  {
        console.log("uniswap pair call uniswapV2Call");
        (
            address collateralTokenOrCToken, //开仓对应于token, 平仓对应于cToken
            address borrowingTokenOrCToken, //开仓对应于token, 平仓对应于cToken
            uint256 originalOrTotalCollateralAmount, //开仓对应于origin, 平仓对应于total
            address user,
            bool flag,
            bool isOpenPosition, //开仓or平仓
            uint256 positionId //仅用于_callbackForClosePosition
        ) = abi.decode(data, (address, address, uint256, address, bool, bool, uint256));

        //安全性:只允许uniswap pair调用
        //check token is supported
        address collateralTokenAddress = isOpenPosition
            ? collateralTokenOrCToken
            : ICErc20(collateralTokenOrCToken).underlying();
        address borrowingTokenAddress = isOpenPosition
            ? borrowingTokenOrCToken
            : ICErc20(borrowingTokenOrCToken).underlying();
        _checkTokenSupported(collateralTokenAddress);
        _checkTokenSupported(borrowingTokenAddress);

        //check invoker is uniswap pair
        address pair = UniswapV2Library.pairFor(
            i_uniswapV2FactoryAddress,
            collateralTokenAddress,
            borrowingTokenAddress
        );
        if (pair != msg.sender) {
            revert CollateralLever__callerIsNotUniswapPair();
        }

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
    ) internal nonReentrant {
        console.log("start _callbackForClosePosition");

        ICErc20 borrowingCToken = ICErc20(borrowingCTokenAddress);
        ICErc20 collateralCToken = ICErc20(collateralCTokenAddress);
        address borrowingTokenAddress = borrowingCToken.underlying();
        address collateralTokenAddress = collateralCToken.underlying();

        _safeApprove(
            borrowingTokenAddress,
            borrowingCTokenAddress,
            flashSwapAmountOfBorrowingToken
        );

        console.log("call borrowingCToken.repayBorrow(-1)");

        // -1 表示全额还款，包括所有利息
        uint256 error = borrowingCToken.repayBorrow(
            isCloseAllAmount ? UINT256_MAX : flashSwapAmountOfBorrowingToken
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
            console.log(
                "before redeemUnderlying, this balanceof collateralToken:%s",
                _ERC20BalanceOf(collateralTokenAddress, address(this))
            );

            error = collateralCToken.redeemUnderlying(totalCollateralAmountOfCollateralToken);
            if (error != 0) {
                revert CollateralLever__cErc20RedeemUnderlyingFailed();
            }
            console.log(
                "after redeemUnderlying(%s), this balanceof collateralToken:%s",
                totalCollateralAmountOfCollateralToken,
                _ERC20BalanceOf(collateralTokenAddress, address(this))
            );

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
        console.log(
            "s_flashSwapPath[0] == collateralTokenAddress true? %s",
            s_flashSwapPath[0] == collateralTokenAddress
        );

        _safeTransfer(s_flashSwapPath[0], pair, repayAmountOfCollateralTokenForFlash);

        console.log("transferAmountToUser should be 0:  %s", transferAmountToUser);

        //transfer to user
        if (transferAmountToUser > 0) {
            console.log(
                "before transfer to user:%s",
                _ERC20BalanceOf(collateralTokenAddress, user)
            );
            _safeTransfer(collateralTokenAddress, user, transferAmountToUser);
            console.log(
                "after transfer to user:%s",
                _ERC20BalanceOf(collateralTokenAddress, user)
            );
        }

        //第一版直接删除仓位信息
        (uint256 idx, ) = _findPosition(user, positionId);
        if (idx != UINT256_MAX) {
            delete s_userAddress2PositionInfos[user][idx]; //会产生gap, 可考虑优化
            emit ClosePositionSucc(user, positionId);
        } else {
            revert CollateralLever__notFindPosition(user, positionId);
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
        console.log("start _callbackForOpenPosition()");

        //获得对应的cTokenAddress
        address cTokenCollateral = s_token2CToken[collateralToken];
        address cTokenBorrowing = s_token2CToken[borrowingToken];

        if (cTokenCollateral == address(0)) {
            revert CollateralLever__tokenNotSupport(collateralToken);
        }
        if (cTokenBorrowing == address(0)) {
            revert CollateralLever__tokenNotSupport(borrowingToken);
        }

        // compound borrow
        uint256 borrowAmountOfBorrowingToken = IUniswapV2Router(i_uniswapV2RouterAddress)
            .getAmountsIn(flashSwapAmountOfCallateralToken, s_flashSwapPath)[0];
        uint256 totalCollateralAmount = flashSwapAmountOfCallateralToken +
            originalCollateralAmountOfCollateralToken;

        console.log(
            "before borrow compound, this balance:%s",
            _ERC20BalanceOf(borrowingToken, address(this))
        );

        console.log(
            "start _borrow (totalcollateralAmount:%s, borrowAmount:%s)",
            totalCollateralAmount,
            borrowAmountOfBorrowingToken
        );

        _borrow(
            cTokenCollateral,
            cTokenBorrowing,
            totalCollateralAmount,
            borrowAmountOfBorrowingToken
        );
        console.log(
            "after borrow compound, this balance:%s",
            _ERC20BalanceOf(borrowingToken, address(this))
        );

        //还闪电贷
        address pair = UniswapV2Library.pairFor(
            i_uniswapV2FactoryAddress,
            collateralToken,
            borrowingToken
        );
        _safeTransfer(s_flashSwapPath[0], pair, borrowAmountOfBorrowingToken);

        //保存仓位信息
        PositionInfo[] memory positions = s_userAddress2PositionInfos[user]; //saving gas
        uint256 positionId = positions.length > 0
            ? positions[positions.length - 1].positionId + 1
            : 1;

        PositionInfo memory newPosition = PositionInfo(
            cTokenCollateral,
            cTokenBorrowing,
            totalCollateralAmount,
            borrowAmountOfBorrowingToken,
            isShort,
            positionId
        );
        s_userAddress2PositionInfos[user].push(newPosition);

        console.log(
            "save position, user:%s, positionId:%s,totalCollateralAmount:%s",
            user,
            positionId,
            totalCollateralAmount
        );
        console.log(
            "borrowAmountOfBorrowingToken:%s, isShort:%s",
            borrowAmountOfBorrowingToken,
            isShort
        );
        // console.log(
        //     "save position, user:%s, positionId:%s,totalCollateralAmount:%s, borrowAmountOfBorrowingToken:%s, isShort:%s",
        //     user,
        //     positionId,
        //     totalCollateralAmount,
        //     borrowAmountOfBorrowingToken,
        //     isShort
        // );
        emit OpenPositionSucc(user, newPosition);
    }

    // 参考 https://github.com/compound-developers/compound-borrow-examples/blob/master/contracts/MyContracts.sol
    function _borrow(
        address collateralCTokenAddress,
        address borrowingCTokenAddress,
        uint256 collateralAmountOfCallateralToken,
        uint256 borrowAmountOfBorrowingToken
    ) internal {
        IComptroller comptroller = IComptroller(i_comptrollerAddress);
        ICErc20 collateralCToken = ICErc20(collateralCTokenAddress);
        ICErc20 borrowingCToken = ICErc20(borrowingCTokenAddress);

        // Approve transfer of underlying
        _safeApprove(
            collateralCToken.underlying(),
            collateralCTokenAddress,
            collateralAmountOfCallateralToken
        );

        console.log(
            "before compound mint, collateralCToken amount of this:%s",
            _ERC20BalanceOf(collateralCTokenAddress, address(this))
        );

        // Supply underlying as collateral, get cToken in return
        uint256 error = collateralCToken.mint(collateralAmountOfCallateralToken);
        if (error != 0) {
            revert CollateralLever__CErc20MintFailed();
        }
        console.log(
            "after compound mint, collateralCToken amount of this:%s",
            _ERC20BalanceOf(collateralCTokenAddress, address(this))
        );

        address[] memory cTokens = new address[](1);
        cTokens[0] = collateralCTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        if (errors[0] != 0) {
            revert("Comptroller.enterMarkets failed.");
        }

        console.log(
            "before compound borrow, borrowingCToken amount of this:%s",
            _ERC20BalanceOf(borrowingCTokenAddress, address(this))
        );

        error = borrowingCToken.borrow(borrowAmountOfBorrowingToken);
        if (error != 0) {
            revert CollateralLever__cErc20BorrowFailed();
        }
        console.log(
            "after compound borrow, borrowingCToken amount of this:%s ",
            _ERC20BalanceOf(borrowingCTokenAddress, address(this))
        );
        console.log(
            "is eq to borrowingCToken.borrowBalanceCurrent(address(this))?: %s ",
            borrowingCToken.borrowBalanceCurrent(address(this))
        );

        // uint256 borrows = borrowingCToken.borrowBalanceCurrent(address(this));
    }

    function _swapToCollateral(
        uint256 amountIn,
        address[] memory path,
        address to,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        console.log(
            "before uniswap swap, balance of this: %s, %s",
            _ERC20BalanceOf(path[0], to),
            _ERC20BalanceOf(path[1], to)
        );
        console.log("begin uniswap swap, amountIn: %s", amountIn);

        uint256[] memory amounts = IUniswapV2Router(i_uniswapV2RouterAddress)
            .swapExactTokensForTokens(amountIn, 0, path, to, deadline);

        console.log("after uniswap swap, amountout: %s", amounts[1]);
        console.log(
            "after uniswap swap, balance of this: %s, %s",
            _ERC20BalanceOf(path[0], to),
            _ERC20BalanceOf(path[1], to)
        );

        return amounts[1];
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

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        if (!IERC20(token).transferFrom(from, to, value)) {
            revert CollateralLever__transferFromFailed();
        }
    }

    function _ERC20BalanceOf(address token, address user) internal view returns (uint256) {
        return IERC20(token).balanceOf(user);
    }

    function _findPosition(address user, uint256 positionId)
        internal
        view
        returns (uint256 idx, PositionInfo memory positionInfo)
    {
        PositionInfo[] memory positions = s_userAddress2PositionInfos[user]; //saving gas
        uint256 len = positions.length;
        idx = UINT256_MAX;
        for (uint256 i = 0; i < len; ++i) {
            if (positions[i].positionId == positionId) {
                positionInfo = positions[i];
                idx = i;
                break;
            }
        }
    }

    function _checkTokenSupported(address tokenAddress) internal view {
        if (s_token2CToken[tokenAddress] == address(0)) {
            revert CollateralLever__tokenNotSupport(tokenAddress);
        }
    }

    // getter function--------------------------------------
    function getUniswapV2RouterAddress() external view returns (address) {
        return i_uniswapV2RouterAddress;
    }

    function getUniswapV2FactoryAddress() external view returns (address) {
        return i_uniswapV2FactoryAddress;
    }

    function getComptrollerAddress() external view returns (address) {
        return i_comptrollerAddress;
    }
}
