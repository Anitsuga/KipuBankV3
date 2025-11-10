# 🏦 KipuBankV3

💡 **Bóveda inteligente multi-activo (ETH + USDC + tokens Uniswap)** con conversión automática a USDC mediante integración con Uniswap V2 y Chainlink.  
Este proyecto corresponde al **examen final del curso Ethereum Developer Pack**, demostrando integración de protocolos DeFi, buenas prácticas de seguridad y testing en Foundry.

---

## ✨ Funcionalidad

✅ Depósitos y retiros en ETH, USDC y tokens ERC20 compatibles con Uniswap V2.  
✅ Conversión automática de tokens a USDC mediante Uniswap Router.  
✅ Control de límite global (bankCap) expresado en USD (6 decimales).  
✅ Modo pausa administrable y control de acceso mediante Ownable.  
✅ Eventos y registro contable de operaciones.

---

## 🚀 Despliegue en Remix o Foundry

### **Remix IDE**
1. Crear archivo `/src/KipuBankV3.sol`.
2. Compilar con Solidity 0.8.26 y optimizer (200 runs).
3. Deploy con Injected Provider – MetaMask (red Sepolia).

### **Foundry**
1. Configurar `.env` con:
   ```bash
   SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/tu_api_key
   PRIVATE_KEY=0xTUCLAVEPRIVADA
   ETHERSCAN_API_KEY=tu_api_key_etherscan
   ```
2. Ejecutar:
   ```bash
   forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
   ```

---

## 🧠 Interacción con el contrato

- `depositETH()` — deposita ETH.  
- `depositUSDC(uint256 amount)` — deposita USDC.  
- `depositToken(address token, uint256 amount)` — deposita cualquier token soportado (convertido a USDC).  
- `withdrawETH(uint256 amount)` / `withdrawUSDC(uint256 amount)` — retira fondos.  
- `setPaused(bool)` — pausa operaciones (solo owner).  
- `getBalanceETH(address)` / `getBalanceUSDC(address)` — consulta balances.

---

## 🛡️ Seguridad y Buenas Prácticas

- Errores personalizados en lugar de `require` con texto.  
- Patrón **Checks-Effects-Interactions**.  
- Protección `ReentrancyGuard` y `SafeERC20`.  
- Control de acceso `Ownable`.  
- Variables `immutable` y `constant` para optimizar gas.  
- Validación de oráculos **Chainlink (ETH/USD)**.

---

## 🧪 Metodología de Testing y Cobertura

El proyecto incluye un conjunto de pruebas unitarias e integraciones desarrolladas con **Foundry**.

| Categoría | Funciones verificadas | Resultado |
|------------|----------------------|------------|
| 💰 Depósitos | `depositETH`, `depositUSDC` | ✅ Balance actualizado |
| 💸 Retiros | `withdrawETH`, `withdrawUSDC` | ✅ Control de saldo insuficiente |
| 🔒 Control | `setPaused`, `onlyOwner` | ✅ Operaciones bloqueadas en pausa |
| 📊 Límite global | `i_bankCapUSD6` | ✅ Validación correcta |
| 📢 Eventos | Emisión en depósito | ✅ Evento detectado |
| ⚙️ Inicialización | Constructor, `immutable` | ✅ Configuración correcta |

### Cobertura de pruebas

La suite actual incluye pruebas unitarias e integraciones desarrolladas en Foundry,  
verificando los flujos principales de depósito, retiro, control de pausado y límite global.  

> La cobertura obtenida supera el 50 % requerido por el examen,  
> con todos los tests pasando exitosamente (`forge test`).

### Herramientas utilizadas

- Framework: Foundry / Forge  
- Librerías: `forge-std/Test.sol`, `OpenZeppelin ERC20`  
- Red local: Anvil  
- Mock: `MockUSDC`  
- Reporte: `forge coverage`

---

## 💡 Mejoras respecto a KipuBankV2

| Área | V2 | V3 |
|------|----|----|
| Activos soportados | ETH + USDC | ETH + USDC + ERC20 |
| Límite global | En USD | USD con swaps previos |
| Oráculo | Chainlink ETH/USD | Chainlink + Uniswap Router |
| Seguridad | Reentrancy + Ownable | + SafeERC20 + Pausable |
| Testing | Básico | Cobertura completa |
| Arquitectura | Modular | Integración DeFi real |

---

## 🔗 Contrato desplegado

- Dirección: `0x522f590b272AF0778110871484EEb14C310932ef`  
- Red: **Ethereum Sepolia**  
- ✅ Verificado en [Etherscan](https://sepolia.etherscan.io/address/0x522f590b272AF0778110871484EEb14C310932ef)

---

