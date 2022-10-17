// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "hardhat/console.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/ICErc20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ICEth.sol";
import "./interfaces/IComptroller.sol";
// import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
// import "./interfaces/IUniswapV2Pair.sol";
// import "./interfaces/IUniswapV2Callee.sol";

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
error CollateralLever__CErc20MintFailed(uint256 error);
error CollateralLever__cErc20RedeemUnderlyingFailed(uint256 error);
error CollateralLever__cErc20BorrowFailed(uint256 error);
error CollateralLever__cErc20RepayBorrowFailed(uint256 error);

// error CollateralLever__borrowedAmountLessThanRepayAmount();

contract CollateralLever is IUniswapV2Callee, Ownable, ReentrancyGuard {
    using UQ112x112 for uint224;

    struct PositionInfo {
        address cTokenCollateralAddress;
        address cTokenBorrowingAddress;
        uint256 collateralAmountOfCollateralToken;
        uint256 collateralAmountOfCollateralCToken;
        uint256 borrowedAmountOfBorrowingToken;
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

    address private immutable i_unitrollerAddress;
    address[] private s_flashSwapPath;
    uint256 private s_lastPositionId;
    mapping(address => uint256) private s_totalBorrowedTokenAmount; //tokenAddress, totalBorrowedTokenAmount
    mapping(address => address) public s_token2CToken; //underlying token address to ctoken address
    mapping(address => mapping(uint256 => PositionInfo)) public s_userAddress2PositionInfos;

    //是否持有仓位
    modifier OwnerOfPosition(address user, uint256 positionId) {
        PositionInfo memory positionInfo = s_userAddress2PositionInfos[user][positionId];
        if (positionInfo.positionId == 0) {
            revert CollateralLever__notOwnerOfPosition();
        }
        _;
    }

    constructor(
        address uniswapV2Router,
        address uniswapV2Factory,
        address unitroller
    ) {
        i_uniswapV2RouterAddress = uniswapV2Router;
        i_uniswapV2FactoryAddress = uniswapV2Factory;
        i_unitrollerAddress = unitroller;
    }

    // receive() external payable {
    //     //todo 第一版仅支持ERC20
    // }

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

        _safeTransferFrom(investmentToken, msg.sender, address(this), investmentAmount);

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

        IUniswapV2Pair(pair).swap(amount0, amount1, address(this), data);
    }

    function closePosition(
        uint256 positionId // uint256 repayAmountOfBorrowingToken //平仓数量    第一版暂不使用该参数, 只实现全量平仓
    ) external OwnerOfPosition(msg.sender, positionId) {
        PositionInfo memory positionInfo = s_userAddress2PositionInfos[msg.sender][positionId];

        ICErc20 borrowingCToken = ICErc20(positionInfo.cTokenBorrowingAddress);

        

        address collateralTokenAddress = ICErc20(positionInfo.cTokenCollateralAddress)
            .underlying();
        address borrowingTokenAddress = borrowingCToken.underlying();

        bool isCloseAllAmount = true; //第一版只实现 全量平仓
        //todo:待研究如何计算每个仓位的borrowingCToken利息, 第一版暂用简单粗暴的算法:按比例, 第一版只实现 全量平仓
        //第一版:flashSwapAmountOfBorrowingToken = 利息+positionInfo.borrowedAmountOfBorrowingToken
        //其中: 利息/总利息(borrowBalanceCurrent- s_totalBorrowedTokenAmount[borrowingTokenAddress]) == positionInfo.borrowedAmountOfBorrowingToken/s_totalBorrowedTokenAmount[borrowingTokenAddress]
        // uint256 flashSwapAmountOfBorrowingToken = (positionInfo.borrowedAmountOfBorrowingToken *
        //     borrowingCToken.borrowBalanceCurrent(address(this))) /
        //     s_totalBorrowedTokenAmount[borrowingTokenAddress];
        uint256 flashSwapAmountOfBorrowingToken = positionInfo.borrowedAmountOfBorrowingToken;
        

        address pair = UniswapV2Library.pairFor(
            i_uniswapV2FactoryAddress,
            collateralTokenAddress,
            borrowingTokenAddress
        );

        bytes memory data = abi.encode(
            positionInfo.cTokenCollateralAddress,
            positionInfo.cTokenBorrowingAddress,
            positionInfo.collateralAmountOfCollateralCToken,
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

        IUniswapV2Pair(pair).swap(amount0, amount1, address(this), data);
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {

        (
            address collateralTokenOrCToken, //开仓对应于token, 平仓对应于cToken
            address borrowingTokenOrCToken, //开仓对应于token, 平仓对应于cToken
            uint256 collateralAmount, //开仓对应于original collateralAmountOfCollateralToken, 平仓对应于total collateralAmountOfCollateralCToken
            address user,
            bool flag,
            bool isOpenPosition, //开仓or平仓
            uint256 positionId //仅用于平仓
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

        (address token0, ) = UniswapV2Library.sortTokens(
            collateralTokenAddress,
            borrowingTokenAddress
        );

        isOpenPosition
            ? _callbackForOpenPosition(
                token0 == borrowingTokenAddress ? amount1 : amount0, //flashSwapAmount对应的token是collateralToken
                collateralTokenOrCToken,
                borrowingTokenOrCToken,
                collateralAmount,
                user,
                flag //代表 isShort
            )
            : _callbackForClosePosition(
                token0 == borrowingTokenAddress ? amount0 : amount1, //flashSwapAmount对应的token是borrowingToken
                collateralTokenOrCToken,
                borrowingTokenOrCToken,
                collateralAmount,
                user,
                flag, //代表 isCloseAllAmount 是否平仓全量
                positionId
            );
    }

    function _callbackForClosePosition(
        uint256 flashSwapAmountOfBorrowingToken,
        address collateralCTokenAddress,
        address borrowingCTokenAddress,
        uint256 totalCollateralAmountOfCollateralCToken,
        address user,
        bool isCloseAllAmount,
        uint256 positionId
    ) internal nonReentrant {
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
        uint256 error = borrowingCToken.repayBorrow(flashSwapAmountOfBorrowingToken);

        if (error != 0) {
            revert CollateralLever__cErc20RepayBorrowFailed(error);
        }
        s_totalBorrowedTokenAmount[borrowingTokenAddress] -= flashSwapAmountOfBorrowingToken;
        
        //闪电贷还款金额
        uint256 repayAmountOfCollateralTokenForFlash = IUniswapV2Router(i_uniswapV2RouterAddress)
            .getAmountsIn(flashSwapAmountOfBorrowingToken, s_flashSwapPath)[0];

        
        // 赎回:cToken=>token
        if (isCloseAllAmount) {
            error = collateralCToken.redeem(totalCollateralAmountOfCollateralCToken);
            if (error != 0) {
                revert CollateralLever__cErc20RedeemUnderlyingFailed(error);
            }
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
        uint256 transferAmountToUser = _ERC20BalanceOf(collateralTokenAddress, address(this));
        if (transferAmountToUser > 0) {
            _safeTransfer(collateralTokenAddress, user, transferAmountToUser);
        }
        
        //第一版直接删除仓位信息
        PositionInfo memory positionInfo = s_userAddress2PositionInfos[user][positionId];
        if (positionInfo.positionId == 0) {
            revert CollateralLever__notFindPosition(user, positionId);
        } else {
            delete s_userAddress2PositionInfos[user][positionId]; //会产生gap, 可考虑优化
            emit ClosePositionSucc(user, positionId);
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

        uint256 collateralAmountOfCollateralCToken = _borrow(
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
        uint256 positionId = ++s_lastPositionId;
        PositionInfo memory newPosition = PositionInfo(
            cTokenCollateral,
            cTokenBorrowing,
            totalCollateralAmount,
            collateralAmountOfCollateralCToken,
            borrowAmountOfBorrowingToken,
            isShort,
            positionId
        );
        s_userAddress2PositionInfos[user][positionId] = newPosition;
        s_totalBorrowedTokenAmount[borrowingToken] += borrowAmountOfBorrowingToken;
        emit OpenPositionSucc(user, newPosition);
    }

    // 参考 https://github.com/compound-developers/compound-borrow-examples/blob/master/contracts/MyContracts.sol
    function _borrow(
        address collateralCTokenAddress,
        address borrowingCTokenAddress,
        uint256 collateralAmountOfCallateralToken,
        uint256 borrowAmountOfBorrowingToken
    ) internal returns (uint256 collateralAmountOfCollateralCToken) {
        IComptroller comptroller = IComptroller(i_unitrollerAddress);
        ICErc20 collateralCToken = ICErc20(collateralCTokenAddress);
        ICErc20 borrowingCToken = ICErc20(borrowingCTokenAddress);

        // Approve transfer of underlying
        _safeApprove(
            collateralCToken.underlying(),
            collateralCTokenAddress,
            collateralAmountOfCallateralToken
        );

        

        uint256 error;
        uint256 oldAmount = collateralCToken.balanceOf(address(this));
        // Supply underlying as collateral, get cToken in return
        error = collateralCToken.mint(collateralAmountOfCallateralToken);
        if (error != 0) {
            revert CollateralLever__CErc20MintFailed(error);
        }
        
        collateralAmountOfCollateralCToken = collateralCToken.balanceOf(address(this)) - oldAmount;
        // (error2, liquidity, shortfall) = comptroller.getAccountLiquidity(address(this));
        address[] memory cTokens = new address[](1);
        cTokens[0] = collateralCTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        if (errors[0] != 0) {
            revert("Comptroller.enterMarkets failed.");
        }

        error = borrowingCToken.borrow(borrowAmountOfBorrowingToken);
        if (error != 0) {
            revert CollateralLever__cErc20BorrowFailed(error);
        }
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
        return i_unitrollerAddress;
    }

    function getNextPostionId() external view returns (uint256) {
        return s_lastPositionId;
    }
}
