// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;
import "hardhat/console.sol";

interface Erc20 {
    function approve(address, uint256) external returns (bool);

    function transfer(address, uint256) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

interface CErc20 {
    function mint(uint256) external returns (uint256);

    function borrow(uint256) external returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function repayBorrow(uint256) external returns (uint256);

    function underlying() external view returns (address);
}

interface CEth {
    function mint() external payable;

    function borrow(uint256) external returns (uint256);

    function repayBorrow() external payable;

    function borrowBalanceCurrent(address) external returns (uint256);
}

interface Comptroller {
    function markets(address) external returns (bool, uint256);

    function enterMarkets(address[] calldata) external returns (uint256[] memory);

    function getAccountLiquidity(address)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}

interface PriceFeed {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}

contract MyTest {
    event MyLog(string, uint256);

    // Seed the contract with a supported underyling asset before running this
    function borrowErc20Example(
        address payable _cEtherAddress,
        address _comptrollerAddress,
        address _priceFeedAddress,
        address _cTokenAddress,
        uint256 _underlyingDecimals
    ) public payable returns (uint256) {
        CEth cEth = CEth(_cEtherAddress);
        Comptroller comptroller = Comptroller(_comptrollerAddress);
        PriceFeed priceFeed = PriceFeed(_priceFeedAddress);
        CErc20 cToken = CErc20(_cTokenAddress);

        // Supply ETH as collateral, get cETH in return
        cEth.mint{value: msg.value, gas: 250000}();

        // Enter the ETH market so you can borrow another type of asset
        address[] memory cTokens = new address[](1);
        cTokens[0] = _cEtherAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        if (errors[0] != 0) {
            revert("Comptroller.enterMarkets failed.");
        }

        // Get my account's total liquidity value in Compound
        (uint256 error, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(
            address(this)
        );
        if (error != 0) {
            revert("Comptroller.getAccountLiquidity failed.");
        }
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        // Get the collateral factor for our collateral
        // (
        //   bool isListed,
        //   uint collateralFactorMantissa
        // ) = comptroller.markets(_cEthAddress);
        // emit MyLog('ETH Collateral Factor', collateralFactorMantissa);

        // Get the amount of underlying added to your borrow each block
        // uint borrowRateMantissa = cToken.borrowRatePerBlock();
        // emit MyLog('Current Borrow Rate', borrowRateMantissa);

        // Get the underlying price in USD from the Price Feed,
        // so we can find out the maximum amount of underlying we can borrow.
        uint256 underlyingPrice = priceFeed.getUnderlyingPrice(_cTokenAddress);
        uint256 maxBorrowUnderlying = liquidity / underlyingPrice;

        // Borrowing near the max amount will result
        // in your account being liquidated instantly
        emit MyLog("Maximum underlying Borrow (borrow far less!)", maxBorrowUnderlying);

        // Borrow underlying
        uint256 numUnderlyingToBorrow = 10;

        // Borrow, check the underlying balance for this contract's address
        cToken.borrow(numUnderlyingToBorrow * 10**_underlyingDecimals);

        // Get the borrow balance
        uint256 borrows = cToken.borrowBalanceCurrent(address(this));
        emit MyLog("Current underlying borrow amount", borrows);

        return borrows;
    }

    function myErc20RepayBorrow(
        address _erc20Address,
        address _cErc20Address,
        uint256 amount
    ) public returns (bool) {
        Erc20 underlying = Erc20(_erc20Address);
        CErc20 cToken = CErc20(_cErc20Address);

        underlying.approve(_cErc20Address, amount);
        uint256 error = cToken.repayBorrow(amount);

        require(error == 0, "CErc20.repayBorrow Error");
        return true;
    }

    struct Param {
        address payable _cEtherAddress;
        address _comptrollerAddress;
        address _cTokenAddress;
        address _underlyingAddress;
        uint256 _underlyingToSupplyAsCollateral;
    }

    function borrowEthExample(Param calldata param) public returns (uint256) {
        CEth cEth = CEth(param._cEtherAddress);
        Comptroller comptroller = Comptroller(param._comptrollerAddress);
        CErc20 cToken = CErc20(param._cTokenAddress);
        Erc20 underlying = Erc20(param._underlyingAddress);

        // Approve transfer of underlying
        underlying.approve(param._cTokenAddress, param._underlyingToSupplyAsCollateral);
        console.log(
            "ctoken.underlying == param._underlyingAddress? %s, %s",
            cToken.underlying(),
            param._underlyingAddress
        );
        console.log(
            "before compound mint, collateralCToken amount of this:%s",
            _ERC20BalanceOf(param._cTokenAddress, address(this))
        );
        console.log(
            "before compound mint, collateralToken amount of this:%s",
            _ERC20BalanceOf(cToken.underlying(), address(this))
        );

        (uint256 error22, uint256 liquidity22, uint256 shortfall22) = comptroller
            .getAccountLiquidity(address(this));

        console.log(
            "before compound mint, getAccountLiquidity of this:%s, %s, %s",
            error22,
            liquidity22,
            shortfall22
        );

        // Supply underlying as collateral, get cToken in return
        uint256 error = cToken.mint(param._underlyingToSupplyAsCollateral);
        require(error == 0, "CErc20.mint Error");

        console.log(
            "after compound mint, collateralCToken amount of this:%s",
            _ERC20BalanceOf(param._cTokenAddress, address(this))
        );
        console.log(
            "after compound mint, collateralToken amount of this:%s",
            _ERC20BalanceOf(cToken.underlying(), address(this))
        );

        (error22, liquidity22, shortfall22) = comptroller.getAccountLiquidity(address(this));

        console.log(
            "after compound mint, getAccountLiquidity of this:%s, %s, %s",
            error22,
            liquidity22,
            shortfall22
        );

        // Enter the market so you can borrow another type of asset
        address[] memory cTokens = new address[](1);
        cTokens[0] = param._cTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        if (errors[0] != 0) {
            revert("Comptroller.enterMarkets failed.");
        }

        // // Get my account's total liquidity value in Compound
        // (uint256 error2, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(
        //     address(this)
        // );
        // if (error2 != 0) {
        //     revert("Comptroller.getAccountLiquidity failed.");
        // }
        // require(shortfall == 0, "account underwater");
        // require(liquidity > 0, "account has excess collateral");

        // // Borrowing near the max amount will result
        // // in your account being liquidated instantly
        // emit MyLog("Maximum ETH Borrow (borrow far less!)", liquidity);

        // // Get the collateral factor for our collateral
        // (
        //   bool isListed,
        //   uint collateralFactorMantissa
        // ) = comptroller.markets(param._cTokenAddress);
        // emit MyLog('Collateral Factor', collateralFactorMantissa);

        // // Get the amount of ETH added to your borrow each block
        // uint borrowRateMantissa = cEth.borrowRatePerBlock();
        // emit MyLog('Current ETH Borrow Rate', borrowRateMantissa);

        // Borrow a fixed amount of ETH below our maximum borrow amount
        uint256 numWeiToBorrow = 300;

        console.log(
            "before compound borrow, borrowingCToken amount of this:%s",
            _ERC20BalanceOf(param._cEtherAddress, address(this))
        );
        console.log(
            "before compound borrow, borrowingToken amount of this:%s",
            address(this).balance
        );

        // Borrow, then check the underlying balance for this contract's address
        error = cEth.borrow(numWeiToBorrow);
        console.log("cEth.borrow error:$s", error);

        console.log(
            "after compound borrow, borrowingCToken amount of this:%s ",
            _ERC20BalanceOf(param._cEtherAddress, address(this))
        );
        console.log(
            "after compound borrow, borrowingToken amount of this:%s",
            address(this).balance
        );
        console.log(
            "is eq to borrowingCToken.borrowBalanceCurrent(address(this))?: %s ",
            cEth.borrowBalanceCurrent(address(this))
        );

        uint256 borrows = cEth.borrowBalanceCurrent(address(this));
        emit MyLog("Current ETH borrow amount", borrows);

        return borrows;
    }

    function erc20BorrowErc20Example(Param calldata param) public returns (uint256) {
        CErc20 cTokenBorrow = CErc20(param._cEtherAddress);
        Comptroller comptroller = Comptroller(param._comptrollerAddress);
        CErc20 cTokenCollateral = CErc20(param._cTokenAddress);
        Erc20 underlyingCollateral = Erc20(param._underlyingAddress);

        // Approve transfer of underlying
        underlyingCollateral.approve(param._cTokenAddress, param._underlyingToSupplyAsCollateral);

        console.log(
            "ctoken.underlying == param._underlyingAddress? %s, %s",
            cTokenCollateral.underlying(),
            param._underlyingAddress
        );
        console.log(
            "before compound mint, collateralCToken amount of this:%s",
            _ERC20BalanceOf(param._cTokenAddress, address(this))
        );
        console.log(
            "before compound mint, collateralToken amount of this:%s",
            _ERC20BalanceOf(cTokenCollateral.underlying(), address(this))
        );

        // (uint256 error22, uint256 liquidity22, uint256 shortfall22) = comptroller
        //     .getAccountLiquidity(address(this));

        // console.log(
        //     "before compound mint, getAccountLiquidity of this:%s, %s, %s",
        //     error22,
        //     liquidity22,
        //     shortfall22
        // );

        // Supply underlying as collateral, get cToken in return
        uint256 error = cTokenCollateral.mint(param._underlyingToSupplyAsCollateral);
        require(error == 0, "CErc20.mint Error");

        console.log(
            "after compound mint, collateralCToken amount of this:%s",
            _ERC20BalanceOf(param._cTokenAddress, address(this))
        );
        console.log(
            "after compound mint, collateralToken amount of this:%s",
            _ERC20BalanceOf(cTokenCollateral.underlying(), address(this))
        );

        // (error22, liquidity22, shortfall22) = comptroller.getAccountLiquidity(address(this));

        // console.log(
        //     "after compound mint, getAccountLiquidity of this:%s, %s, %s",
        //     error22,
        //     liquidity22,
        //     shortfall22
        // );

        // Enter the market so you can borrow another type of asset
        address[] memory cTokens = new address[](1);
        cTokens[0] = param._cTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        if (errors[0] != 0) {
            revert("Comptroller.enterMarkets failed.");
        }

        // Get my account's total liquidity value in Compound
        (uint256 error2, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(
            address(this)
        );
        if (error2 != 0) {
            revert("Comptroller.getAccountLiquidity failed.");
        }
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        // Borrowing near the max amount will result
        // in your account being liquidated instantly
        emit MyLog("Maximum ETH Borrow (borrow far less!)", liquidity);

        // // Get the collateral factor for our collateral
        // (
        //   bool isListed,
        //   uint collateralFactorMantissa
        // ) = comptroller.markets(_cTokenAddress);
        // emit MyLog('Collateral Factor', collateralFactorMantissa);

        // // Get the amount of ETH added to your borrow each block
        // uint borrowRateMantissa = cEth.borrowRatePerBlock();
        // emit MyLog('Current ETH Borrow Rate', borrowRateMantissa);

        // Borrow a fixed amount of ETH below our maximum borrow amount
        uint256 numWeiToBorrow = 200;

        console.log(
            "before compound borrow, borrowingCToken amount of this:%s",
            _ERC20BalanceOf(param._cEtherAddress, address(this))
        );
        console.log(
            "before compound borrow, borrowingToken amount of this:%s",
            _ERC20BalanceOf(cTokenBorrow.underlying(), address(this))
        );

        // Borrow, then check the underlying balance for this contract's address

        error = cTokenBorrow.borrow(numWeiToBorrow);
        console.log("borrow error:$s", error);

        console.log(
            "after compound borrow, borrowingCToken amount of this:%s ",
            _ERC20BalanceOf(param._cEtherAddress, address(this))
        );
        console.log(
            "after compound borrow, borrowingToken amount of this:%s",
            _ERC20BalanceOf(cTokenBorrow.underlying(), address(this))
        );
        console.log(
            "is eq to borrowingCToken.borrowBalanceCurrent(address(this))?: %s ",
            cTokenBorrow.borrowBalanceCurrent(address(this))
        );

        uint256 borrows = cTokenBorrow.borrowBalanceCurrent(address(this));
        emit MyLog("Current ETH borrow amount", borrows);

        return borrows;
    }

    function myEthRepayBorrow(
        address _cEtherAddress,
        uint256 amount,
        uint256 gas
    ) public returns (bool) {
        CEth cEth = CEth(_cEtherAddress);
        cEth.repayBorrow{value: amount, gas: gas}();
        return true;
    }

    // Need this to receive ETH when `borrowEthExample` executes
    receive() external payable {}

    function _ERC20BalanceOf(address token, address user) internal view returns (uint256) {
        return Erc20(token).balanceOf(user);
    }

    function _borrow(
        address comptrollerAddress,
        address collateralCTokenAddress,
        address borrowingCTokenAddress,
        uint256 collateralAmountOfCallateralToken,
        uint256 borrowAmountOfBorrowingToken
    ) public returns (uint256 borrowBalanceCurrent) {
        Comptroller comptroller = Comptroller(comptrollerAddress);
        CErc20 collateralCToken = CErc20(collateralCTokenAddress);
        CErc20 borrowingCToken = CErc20(borrowingCTokenAddress);

        // Approve transfer of underlying
        _safeApprove(
            collateralCToken.underlying(),
            collateralCTokenAddress,
            collateralAmountOfCallateralToken
        );

        uint256 error;

        // Supply underlying as collateral, get cToken in return
        error = collateralCToken.mint(collateralAmountOfCallateralToken);
        if (error != 0) {
            revert("CollateralLever__CErc20MintFailed(error)");
        }

        // (error2, liquidity, shortfall) = comptroller.getAccountLiquidity(address(this));

        address[] memory cTokens = new address[](1);
        cTokens[0] = collateralCTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        if (errors[0] != 0) {
            revert("Comptroller.enterMarkets failed.");
        }

        error = borrowingCToken.borrow(borrowAmountOfBorrowingToken);
        if (error != 0) {
            revert("CollateralLever__cErc20BorrowFailed(error)");
        }

        return borrowingCToken.borrowBalanceCurrent(address(this)); //利息原因, 此值可能大于_ERC20BalanceOf(borrowingCToken.underlying(), address(this))
    }

    function _safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        if (!Erc20(token).approve(to, value)) {
            revert("_safeApprove failed");
        }
    }
}
