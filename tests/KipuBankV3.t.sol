// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";

contract KipuBankV3Test is Test {
    KipuBankV3 kipu;

    address owner = address(0xABCD);
    address usdc = address(0x1111);
    address feed = address(0x2222);
    address router = address(0x3333);

    function setUp() public {
        kipu = new KipuBankV3(owner, usdc, feed, router, 1000000e6, 10000e6);
    }

    function testInitialSetup() public view {
        assertEq(address(kipu.i_usdc()), usdc);
        assertEq(address(kipu.i_uniswapRouter()), router);
    }
}
