// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ICErc20.sol";

contract MyTest{
    function getUnderlying(address cToken)external view returns (address){        
        // return cToken;
        return ICErc20(cToken).underlying();
    }
}
