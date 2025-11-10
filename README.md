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

## 📐 Decisiones de diseño y trade-offs

- **Swaps siempre hacia USDC como “moneda contable”:**  
  El protocolo normaliza el valor de todos los depósitos a USDC. Esto simplifica el cálculo del `bankCap` y la contabilidad interna, a costa de perder exposición al token depositado (el usuario ya no tiene ese token, sino USDC).

- **Uso de Chainlink solo para ETH→USD:**  
  Solo se usa oráculo para valorar ETH, ya que USDC ya está en USD(6) y el resto de tokens se convierten a USDC vía Uniswap V2. Es un trade-off entre simplicidad y completitud: se evita manejar múltiples oráculos para cada token ERC20.

- **Límite global (`bankCap`) en USD(6):**  
  El límite se expresa en formato USDC (6 decimales) para tener una métrica homogénea del riesgo total del banco. Esto simplifica la lógica de chequeo de límites, aunque implica hacer conversiones previas (ETH→USD, tokens→USDC) antes de actualizar el estado.

- **Owner centralizado con capacidad de pausa:**  
  El uso de `Ownable` y `setPaused(bool)` permite reaccionar rápidamente ante incidentes (por ejemplo, un problema de oráculo o un bug en el router). El trade-off es que el sistema no es totalmente descentralizado: el owner concentra poder. En producción se podría reemplazar por multisig o gobernanza.

- **Uso de errores personalizados vs `require` con string:**  
  Se eligieron errores personalizados (`error KipuBankV3_...`) para ahorrar gas y mejorar la claridad semántica. Esto hace que el bytecode sea más eficiente y los revert reasons sean más fáciles de identificar en una auditoría.

- **Uso de `immutable` y `constant` para dependencias y parámetros globales:**  
  Direcciones como USDC, router de Uniswap y feed de Chainlink se declaran `immutable`, mientras que parámetros como `DECIMAL_FACTOR` y `ORACLE_HEARTBEAT` son `constant`. Esto reduce el costo de gas en lectura y hace explícito que no cambiarán en tiempo de ejecución.


## 🔍 Análisis de amenazas y pasos faltantes para madurez

A continuación se listan algunos riesgos del protocolo y posibles líneas de mejora para llevar KipuBankV3 hacia un nivel de madurez más cercano a producción:

### 1. Reentrancy y llamadas externas

- **Estado actual:**  
  - El contrato usa un flag de reentrancia (`nonReentrant`) y sigue el patrón **Checks-Effects-Interactions**.  
  - Los swaps se realizan a través del router de Uniswap V2, un contrato ampliamente auditado.

- **Riesgo:**  
  - Cualquier llamada externa (router, tokens no estándar) podría ser un vector de reentrancy si no se sigue CEI y no se protege el flujo.

- **Mejoras futuras:**  
  - Añadir pruebas específicas de reentrancy (por ejemplo, con tokens maliciosos en entorno local).  
  - Considerar el uso de `ReentrancyGuard` de OpenZeppelin como alternativa al flag manual.


### 2. Riesgo de oráculo (Chainlink ETH/USD)

- **Estado actual:**  
  - Se valida que el precio sea > 0.  
  - Se verifica `updatedAt` contra un `ORACLE_HEARTBEAT` (stale check).  
  - Se compara `answeredInRound` con `roundID`.

- **Riesgo:**  
  - Si el feed es manipulado, o la fuente deja de actualizar en tiempo y forma, los depósitos y retiros en ETH podrían valorarse incorrectamente.

- **Mejoras futuras:**  
  - Usar oráculos de respaldo (multi-oráculo) o check cruzado con otra fuente.  
  - Añadir alertas fuera de cadena (monitoring) cuando el oráculo quede stale.


### 3. Liquidez y slippage en Uniswap V2

- **Estado actual:**  
  - El usuario define `amountOutMin` y `deadline` al llamar a `depositToken`, lo que protege contra slippage excesivo.  
  - El contrato no fuerza un mínimo global ni verifica calidad de pool o liquidez.

- **Riesgo:**  
  - Pools con liquidez baja pueden producir un `usdcOut` muy bajo o incluso revertir.  
  - Riesgo de MEV / front-running en redes públicas.

- **Mejoras futuras:**  
  - Implementar estrategias de slippage predeterminadas o límites máximos de desviación para ciertos tokens.  
  - Integrar agregadores de precios o routers más sofisticados en lugar de un único AMM.


### 4. BankCap y riesgos de concentración

- **Estado actual:**  
  - `bankCap` limita el valor total del banco expresado en USD(6).  
  - El owner fija estos parámetros en el despliegue.

- **Riesgo:**  
  - Si el `bankCap` se configura demasiado alto, el valor en riesgo aumenta.  
  - No hay segmentación de riesgo por tipo de activo o por usuario.

- **Mejoras futuras:**  
  - Añadir límites por usuario (user caps).  
  - Añadir límites por token (por ejemplo, no permitir que un solo token supere cierto porcentaje del TVL).


### 5. Centralización del owner

- **Estado actual:**  
  - El owner puede pausar el contrato.  
  - No se usa multisig ni gobernanza on-chain.

- **Riesgo:**  
  - Centralización del poder: si la clave del owner se ve comprometida, el atacante podría pausar el protocolo o interferir con su operación.

- **Mejoras futuras:**  
  - Migrar el rol de owner a una billetera multisig.  
  - Añadir `timelocks` para cambios críticos.  
  - Integrar un módulo de gobernanza descentralizada en una versión futura.


### 6. Scope de pruebas

- **Estado actual:**  
  - Pruebas unitarias sobre depósitos, retiros, pausado, límites y eventos.  
  - Cobertura medida con `forge coverage`, superando el 50 % requerido.

- **Riesgo:**  
  - No todas las ramas de error relacionadas con oráculos y Uniswap están cubiertas (por ejemplo, swaps que fallan, oráculos stale en runtime real).

- **Mejoras futuras:**  
  - Añadir tests específicos para escenarios de fallo de oráculo y fallo de swap.  
  - Integrar pruebas de integración completas con un fork de Sepolia o Mainnet para simular Uniswap real.



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

