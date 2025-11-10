// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

contract DeployKipuBankV3 is Script {
    function run() external {
        //  Cargar tu clave privada
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //  Direcciones reales de testnet Sepolia
        address USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // USDC (testnet)
        address ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // Chainlink ETH/USD feed
        address UNISWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45; // Uniswap V2 Router

        //  Deploy del contrato
        KipuBankV3 kipu = new KipuBankV3(
            msg.sender,         // Propietario
            USDC,               // Token USDC
            ETH_USD_FEED,       // Oráculo Chainlink
            UNISWAP_ROUTER,     // Router Uniswap
            1_000_000e6,        // Límite global (en USD6)
            10_000e6            // Límite de retiro (en USD6)
        );

        console.log("KipuBankV3 desplegado en:", address(kipu));

        vm.stopBroadcast();
    }
}
