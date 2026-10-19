// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library AAMUtils {
    function getSelector(string calldata _fnSig) public pure returns (bytes4) {
        return bytes4(abi.encodeWithSignature(_fnSig));
    }
}
