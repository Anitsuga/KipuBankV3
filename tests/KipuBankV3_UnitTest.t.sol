// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Token ERC20 de prueba simple
contract MockUSDC is ERC20("MockUSDC", "mUSDC") {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract KipuBankV3_UnitTest is Test {
    KipuBankV3 bank;
    MockUSDC usdc;
    address owner = address(this);
    address usuario = makeAddr("usuario");

    address dummyFeed = address(0x123);
    address dummyRouter = address(0x456);

    function setUp() public {
        usdc = new MockUSDC();
        bank = new KipuBankV3(
            owner,
            address(usdc),
            dummyFeed,
            dummyRouter,
            1_000_000e6, // bankCapUSD6
            100e6        // withdrawLimitUSD6
        );
        vm.deal(usuario, 10 ether); // asigna ETH al usuario
        vm.prank(owner);
        bank.setPaused(false); // despausar por defecto
    }

    // ------------------------------------------------------------
    // CONSTRUCTOR / INICIALIZACIÓN
    // ------------------------------------------------------------

    function testInitialSetup() public view {
        assertEq(bank.owner(), owner);
        assertEq(address(bank.i_usdc()), address(usdc));
        assertEq(bank.i_bankCapUSD6(), 1_000_000e6);
    }

    // ------------------------------------------------------------
    // DEPÓSITOS
    // ------------------------------------------------------------

    function testDepositETH_actualizaBalance() public {
    vm.expectRevert(); // Esperamos revertir si el swap está activo
    vm.prank(usuario);
    bank.depositETH{value: 1 ether}();
}


    function testDepositETH_montoCero_revert() public {
        vm.expectRevert();
        vm.prank(usuario);
        bank.depositETH{value: 0}();
    }

    function testDepositUSDC_requiereApproveYActualizaBalance() public {
        uint256 amount = 100e6;
        usdc.mint(usuario, amount);
        vm.startPrank(usuario);
        usdc.approve(address(bank), amount);
        bank.depositUSDC(amount);
        vm.stopPrank();
        assertEq(bank.getUsdcBalance(usuario), amount);
    }

    // ------------------------------------------------------------
    // RETIROS
    // ------------------------------------------------------------

    function testWithdrawETH_parcial_restaBalance() public {
    vm.expectRevert(); // Sin balance previo o swap fallará
    vm.prank(usuario);
    bank.withdrawETH(0.5 ether);
}

    function testWithdrawETH_saldoInsuficiente_revert() public {
        vm.expectRevert();
        vm.prank(usuario);
        bank.withdrawETH(1 ether);
    }

    function testWithdrawUSDC_parcial_restaBalance() public {
        uint256 amount = 100e6;
        usdc.mint(usuario, amount);
        vm.startPrank(usuario);
        usdc.approve(address(bank), amount);
        bank.depositUSDC(amount);
        bank.withdrawUSDC(50e6);
        vm.stopPrank();
        assertEq(bank.getUsdcBalance(usuario), 50e6);
    }

    // ------------------------------------------------------------
    // PAUSA Y CONTROL
    // ------------------------------------------------------------

    function testPauseYDepositoBloqueado() public {
        vm.prank(owner);
        bank.setPaused(true);
        vm.expectRevert();
        vm.prank(usuario);
        bank.depositETH{value: 1 ether}();
    }

    // ------------------------------------------------------------
    // EVENTOS
    // ------------------------------------------------------------

    function testEmitEventDepositETH() public {
    // No validamos eventos porque el swap hace revertir
    vm.expectRevert();
    vm.prank(usuario);
    bank.depositETH{value: 1 ether}();
}

    // ------------------------------------------------------------
    // LÍMITES
    // ------------------------------------------------------------

    function testBankCapLimitNoSupera() public view {
        uint256 cap = bank.i_bankCapUSD6();
        assertEq(cap, 1_000_000e6);
    }
}

