// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*///////////////////////
        Imports
///////////////////////*/
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// Usamos la interfaz local de Chainlink (ubicada en src/AggregatorV3Interface.sol)
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/*//////////////////////////////////////////////////////////////
        Interfaz mínima del router de Uniswap V2
//////////////////////////////////////////////////////////////*/
interface IUniswapV2Router02 {
    /**
     * @notice Devuelve la dirección del token WETH (Wrapped Ether) utilizada por el Router.
     */
    function WETH() external pure returns (address);

    /**
     * @notice Swap de tokens ERC20 -> ERC20 con cantidad exacta de entrada.
     * @param amountIn Cantidad exacta del token de entrada.
     * @param amountOutMin Mínimo aceptable del token de salida (protección de slippage).
     * @param path Ruta de intercambio: [tokenIn, ..., tokenOut].
     * @param to Dirección que recibirá el token de salida.
     * @param deadline Timestamp máximo de validez de la operación.
     * @return amounts Vector con los montos utilizados/recibidos en cada salto del path.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Swap de ETH nativo -> ERC20 usando WETH como token intermedio.
     * @param amountOutMin Mínimo aceptable del token de salida (protección de slippage).
     * @param path Ruta de intercambio: [WETH, ..., tokenOut].
     * @param to Dirección que recibirá el token de salida.
     * @param deadline Timestamp máximo de validez de la operación.
     * @return amounts Vector con los montos utilizados/recibidos en cada salto del path.
     */
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

/*//////////////////////////////////////////////////////////////
                           KipuBankV3
//////////////////////////////////////////////////////////////*/
/**
 * @title KipuBankV3
 * @notice Bóveda DeFi educativa con:
 *         - Depósitos y retiros en ETH y USDC.
 *         - Depósitos en cualquier token ERC20 con par directo a USDC en Uniswap V2.
 *         - Depósitos de ETH convertidos directamente a USDC vía Uniswap V2 usando WETH.
 *         - Límites globales (cap del banco) y por transacción (withdraw limit) expresados en USD(6).
 * @dev Contrato diseñado para prácticas con Foundry + Sepolia.
 *      NO usar en producción sin auditoría externa.
 */
contract KipuBankV3 is Ownable {
    /*///////////////////////
          Declaraciones
    ///////////////////////*/

    using SafeERC20 for IERC20;

    /// @notice Heartbeat máximo tolerado del oráculo (segundos). Si el precio es más viejo → precio obsoleto.
    uint16 public constant ORACLE_HEARTBEAT = 3600; // 1 hora

    /// @notice Factor de decimales: 10^20 (= 10^(18 ETH + 8 price - 6 USD)), normaliza ETH(18) * price(8) → USD(6)
    uint256 public constant DECIMAL_FACTOR = 1e20;

    /// @notice Decimales objetivo para USD estilo USDC (6)
    uint8 public constant DECIMALS_USDC = 6;

    /*///////////////////////
           Variables
    ///////////////////////*/

    /// @notice Referencia al token USDC (decimales nativos = 6)
    IERC20 public immutable i_usdc;

    /// @notice Feed Chainlink ETH/USD usado para convertir ETH→USD(6)
    AggregatorV3Interface public immutable i_ethUsdFeed;

    /// @notice Router de Uniswap V2 usado para los swaps token→USDC y ETH→USDC (vía WETH)
    IUniswapV2Router02 public immutable i_uniswapRouter;

    /// @notice Límite global del banco en USD(6). Si se excede al depositar, se revierte.
    uint256 public immutable i_bankCapUSD6;

    /// @notice Límite máximo por retiro en USD(6). Aplica tanto a ETH (valuado en USD) como a USDC.
    uint256 public immutable i_withdrawLimitUSD6;

    /// @notice Balance interno de ETH por usuario (en wei)
    mapping(address usuario => uint256 balanceWei) public s_ethBalances;

    /// @notice Balance interno de USDC por usuario (en unidades de 6 decimales)
    mapping(address usuario => uint256 balanceUSDC) public s_usdcBalances;

    /// @notice Cantidad de depósitos realizados por usuario (conteo)
    mapping(address usuario => uint256 count) public s_depositCount;

    /// @notice Cantidad de retiros realizados por usuario (conteo)
    mapping(address usuario => uint256 count) public s_withdrawCount;

    /// @notice Conteo global de depósitos (no USD)
    uint256 public s_totalDeposits;

    /// @notice Conteo global de retiros (no USD)
    uint256 public s_totalWithdrawals;

    /// @notice Valor total del banco en USD(6). Suma de ETH valuado en USD(6) + USDC.
    uint256 public s_totalUSD6;

    /// @notice Flag de reentrancia: true si una función protegida está en ejecución
    bool private s_locked;

    /// @notice Flag de pausa: true detiene depósitos y retiros
    bool public s_paused;

    /*///////////////////////
            Eventos
    ///////////////////////*/

    /// @notice Evento emitido al depositar ETH contabilizado con Chainlink
    event KipuBankV3_DepositoETH(address indexed usuario, uint256 amountETH, uint256 usd6);

    /// @notice Evento emitido al depositar USDC
    event KipuBankV3_DepositoUSDC(address indexed usuario, uint256 amountUSDC);

    /// @notice Evento emitido al depositar un token ERC20 vía swap en Uniswap V2 → USDC
    event KipuBankV3_DepositoToken(
        address indexed usuario,
        address indexed token,
        uint256 amountIn,
        uint256 usdcOut
    );

    /// @notice Evento emitido al depositar ETH que se convierte a USDC vía Uniswap V2 (WETH → USDC)
    event KipuBankV3_DepositoETHviaSwap(
        address indexed usuario,
        uint256 amountETH,
        uint256 usdcOut
    );

    /// @notice Evento emitido al retirar ETH
    event KipuBankV3_ExtraccionETH(address indexed usuario, uint256 amountETH, uint256 usd6);

    /// @notice Evento emitido al retirar USDC
    event KipuBankV3_ExtraccionUSDC(address indexed usuario, uint256 amountUSDC);

    /// @notice Evento emitido al pausar o reanudar el contrato
    event KipuBankV3_PausaCambiada(bool estado);

    /*///////////////////////
            Errores
    ///////////////////////*/

    /// @notice Error: reentrada detectada al usar funciones protegidas
    error KipuBankV3_Reentrancia();

    /// @notice Error: el contrato está en pausa
    error KipuBankV3_Pausado();

    /// @notice Error: el monto provisto es cero
    error KipuBankV3_MontoCero();

    /// @notice Error: el precio del oráculo no es válido (<= 0)
    error KipuBankV3_OracleComprometido();

    /// @notice Error: el precio del oráculo está obsoleto respecto al heartbeat configurado
    error KipuBankV3_StalePrice();

    /// @notice Error: se excede el límite global del banco en USD(6)
    error KipuBankV3_LimiteGlobalSuperado(uint256 total, uint256 limite);

    /// @notice Error: se excede el límite por transacción en USD(6)
    error KipuBankV3_LimiteExtraccion(uint256 solicitado, uint256 maximo);

    /// @notice Error: el balance del usuario es insuficiente
    error KipuBankV3_SaldoInsuficiente(uint256 solicitado, uint256 disponible);

    /// @notice Error: transferencia nativa fallida
    error KipuBankV3_TransferenciaFallida(bytes razon);

    /// @notice Error: parámetros/direcciones no válidos (por ejemplo address(0))
    error KipuBankV3_DireccionInvalida();

    /// @notice Error: llamada inválida a receive/fallback o a función inexistente
    error KipuBankV3_LlamadaInvalida();

    /*///////////////////////
          Modificadores
    ///////////////////////*/

    /// @notice Protege contra ataques de reentrancia
    modifier nonReentrant() {
        if (s_locked) revert KipuBankV3_Reentrancia();
        s_locked = true;
        _;
        s_locked = false;
    }

    /// @notice Permite ejecutar solo cuando el contrato no está en pausa
    modifier whenNotPaused() {
        if (s_paused) revert KipuBankV3_Pausado();
        _;
    }

    /// @notice Verifica que el monto sea > 0
    modifier montoValido(uint256 amount) {
        if (amount == 0) revert KipuBankV3_MontoCero();
        _;
    }

    /*///////////////////////
          Constructor
    ///////////////////////*/

    /**
     * @notice Inicializa la bóveda con sus dependencias y límites.
     * @dev Valida que las direcciones de dependencias no sean cero.
     */
    constructor(
        address _owner,
        address _usdc,
        address _ethUsdFeed,
        address _uniswapRouter,
        uint256 _bankCapUSD6,
        uint256 _withdrawLimitUSD6
    ) Ownable(_owner) {
        if (_usdc == address(0) || _ethUsdFeed == address(0) || _uniswapRouter == address(0)) {
            revert KipuBankV3_DireccionInvalida();
        }

        i_usdc = IERC20(_usdc);
        i_ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        i_uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        i_bankCapUSD6 = _bankCapUSD6;
        i_withdrawLimitUSD6 = _withdrawLimitUSD6;

        s_locked = false;
    }

    /*///////////////////////
        Funciones admin
    ///////////////////////*/

    /**
     * @notice Pausa o reanuda depósitos y retiros.
     * @dev Solo ejecutable por el propietario.
     */
    function setPaused(bool _status) external onlyOwner {
        s_paused = _status;
        emit KipuBankV3_PausaCambiada(_status);
    }

    /*///////////////////////
           Depósitos
    ///////////////////////*/

    /**
     * @notice Deposita ETH en la bóveda y lo contabiliza en USD(6) con Chainlink.
     * @dev Aplica validaciones de pausa, monto > 0, límite global y reentrancia.
     *      Sigue CEI: primero CHECKS, luego EFFECTS, finalmente INTERACTIONS.
     */
    function depositETH()
        external
        payable
        whenNotPaused
        nonReentrant
        montoValido(msg.value)
    {
        /*//////////////////////////////////////////////////////////////
                                CHECKS
        //////////////////////////////////////////////////////////////*/

        // Convertir a USD(6) usando el feed de Chainlink
        uint256 usd6 = _ethToUSD6(msg.value);

        // Verificar límite global del banco (bank cap)
        uint256 nuevoTotal = s_totalUSD6 + usd6;
        if (nuevoTotal > i_bankCapUSD6) {
            revert KipuBankV3_LimiteGlobalSuperado(nuevoTotal, i_bankCapUSD6);
        }

        /*//////////////////////////////////////////////////////////////
                                EFFECTS
        //////////////////////////////////////////////////////////////*/

        s_totalUSD6 = nuevoTotal;
        s_ethBalances[msg.sender] += msg.value;
        s_depositCount[msg.sender] += 1;
        s_totalDeposits += 1;

        /*//////////////////////////////////////////////////////////////
                             INTERACTIONS
        //////////////////////////////////////////////////////////////*/

        // No hay interacción externa (ETH ya se recibió en msg.value)
        emit KipuBankV3_DepositoETH(msg.sender, msg.value, usd6);
    }

    /**
     * @notice Deposita ETH en la bóveda convirtiéndolo directamente a USDC vía Uniswap V2 (ETH -> WETH -> USDC).
     * @dev
     * - El usuario envía ETH nativo (msg.value).
     * - El contrato llama a `swapExactETHForTokens` del router usando WETH y USDC como path.
     * - Los USDC resultantes quedan en custodia del contrato y se acreditan al balance interno del usuario.
     * - Se verifica el límite global del banco en USD(6) usando el resultado efectivo del swap (usdcOut).
     * - Sigue CEI.
     * @param amountOutMin Mínimo aceptable de USDC a recibir (protección de slippage).
     * @param deadline Timestamp máximo de validez de la operación (suele ser block.timestamp + N).
     */
    function depositETHviaUniswap(
        uint256 amountOutMin,
        uint256 deadline
    )
        external
        payable
        whenNotPaused
        nonReentrant
        montoValido(msg.value)
    {
        /*//////////////////////////////////////////////////////////////
                                CHECKS
        //////////////////////////////////////////////////////////////*/

        // Obtener la dirección de WETH desde el router (dinámicamente, como en el módulo del profesor)
        address weth = i_uniswapRouter.WETH();

        // Construir el path: WETH -> USDC
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = address(i_usdc);

        /*//////////////////////////////////////////////////////////////
                        INTERACTIONS (swap en Uniswap V2)
        //////////////////////////////////////////////////////////////*/

        // El ETH enviado en msg.value se envía al router, se envuelve en WETH, se intercambia por USDC
        // y los USDC quedan en este contrato (to = address(this)).
        uint256[] memory amounts = i_uniswapRouter.swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            address(this),
            deadline
        );

        uint256 usdcOut = amounts[amounts.length - 1];

        /*//////////////////////////////////////////////////////////////
                                CHECKS (post-swap)
        //////////////////////////////////////////////////////////////*/

        // Verificar límite global del banco con el resultado en USDC
        uint256 nuevoTotal = s_totalUSD6 + usdcOut;
        if (nuevoTotal > i_bankCapUSD6) {
            revert KipuBankV3_LimiteGlobalSuperado(nuevoTotal, i_bankCapUSD6);
        }

        /*//////////////////////////////////////////////////////////////
                                EFFECTS
        //////////////////////////////////////////////////////////////*/

        s_totalUSD6 = nuevoTotal;
        s_usdcBalances[msg.sender] += usdcOut;
        s_depositCount[msg.sender] += 1;
        s_totalDeposits += 1;

        /*//////////////////////////////////////////////////////////////
                             INTERACTIONS
        //////////////////////////////////////////////////////////////*/

        emit KipuBankV3_DepositoETHviaSwap(msg.sender, msg.value, usdcOut);
    }

    /**
     * @notice Deposita USDC en la bóveda (USDC ya está en USD(6)).
     * @dev Requiere aprobación previa (approve) al contrato.
     */
    function depositUSDC(uint256 amount)
        external
        whenNotPaused
        nonReentrant
        montoValido(amount)
    {
        /*//////////////////////////////////////////////////////////////
                                CHECKS
        //////////////////////////////////////////////////////////////*/

        // Verificar límite global con el nuevo monto
        uint256 nuevoTotal = s_totalUSD6 + amount;
        if (nuevoTotal > i_bankCapUSD6) {
            revert KipuBankV3_LimiteGlobalSuperado(nuevoTotal, i_bankCapUSD6);
        }

        /*//////////////////////////////////////////////////////////////
                                EFFECTS
        //////////////////////////////////////////////////////////////*/

        s_totalUSD6 = nuevoTotal;
        s_usdcBalances[msg.sender] += amount;
        s_depositCount[msg.sender] += 1;
        s_totalDeposits += 1;

        /*//////////////////////////////////////////////////////////////
                             INTERACTIONS
        //////////////////////////////////////////////////////////////*/

        // Transferir USDC desde el usuario al contrato (pull)
        i_usdc.safeTransferFrom(msg.sender, address(this), amount);

        emit KipuBankV3_DepositoUSDC(msg.sender, amount);
    }

    /**
     * @notice Deposita un token ERC20 cualquiera con par directo a USDC en Uniswap V2.
     * @dev
     * - El usuario debe aprobar previamente al contrato para gastar `amount` del token.
     * - El contrato hace `safeTransferFrom` hacia sí mismo.
     * - Luego da allowance al router y ejecuta `swapExactTokensForTokens` (token -> USDC).
     * - Los USDC resultantes quedan en custodia del contrato y se registran en el balance interno del usuario.
     * - Se verifica el límite global del banco usando el resultado efectivo del swap.
     * - Sigue el estilo del módulo `SwapModuleV2` provisto por el profesor, integrado al flujo de la bóveda.
     * @param token Dirección del token de entrada (no puede ser address(0) ni USDC).
     * @param amount Cantidad exacta de token de entrada a depositar.
     * @param amountOutMin Mínimo aceptable de USDC a recibir (protección de slippage).
     * @param deadline Timestamp máximo de validez de la operación.
     */
    function depositToken(
        address token,
        uint256 amount,
        uint256 amountOutMin,
        uint256 deadline
    )
        external
        whenNotPaused
        nonReentrant
        montoValido(amount)
    {
        /*//////////////////////////////////////////////////////////////
                                CHECKS
        //////////////////////////////////////////////////////////////*/

        if (token == address(0) || token == address(i_usdc)) {
            revert KipuBankV3_DireccionInvalida();
        }

        IERC20 erc = IERC20(token);

        /*//////////////////////////////////////////////////////////////
                        INTERACTIONS (parcialmente CHECKS)
        //////////////////////////////////////////////////////////////*/

        // 1) Traemos los tokens al contrato (el usuario debe tener approve)
        erc.safeTransferFrom(msg.sender, address(this), amount);

        // 2) Preparar path para Uniswap: token -> USDC
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(i_usdc);

        // 3) Dar allowance al router para ejecutar el swap
        erc.safeIncreaseAllowance(address(i_uniswapRouter), amount);

        // 4) Interacción externa: ejecutar el swap.
        //    Los USDC resultantes quedan en este contrato (to = address(this)).
        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens(
            amount,
            amountOutMin,
            path,
            address(this),
            deadline
        );

        uint256 usdcOut = amounts[amounts.length - 1];

        /*//////////////////////////////////////////////////////////////
                                CHECKS (post-swap)
        //////////////////////////////////////////////////////////////*/

        // Verificamos bankCap con el resultado en USDC
        uint256 nuevoTotal = s_totalUSD6 + usdcOut;
        if (nuevoTotal > i_bankCapUSD6) {
            revert KipuBankV3_LimiteGlobalSuperado(nuevoTotal, i_bankCapUSD6);
        }

        /*//////////////////////////////////////////////////////////////
                                EFFECTS
        //////////////////////////////////////////////////////////////*/

        s_totalUSD6 = nuevoTotal;
        s_usdcBalances[msg.sender] += usdcOut;
        s_depositCount[msg.sender] += 1;
        s_totalDeposits += 1;

        /*//////////////////////////////////////////////////////////////
                             INTERACTIONS
        //////////////////////////////////////////////////////////////*/

        emit KipuBankV3_DepositoToken(msg.sender, token, amount, usdcOut);
    }

    /*///////////////////////
            Retiros
    ///////////////////////*/

    /**
     * @notice Retira ETH de la bóveda valorado en USD(6), respetando límite por transacción.
     */
    function withdrawETH(uint256 amount)
        external
        whenNotPaused
        nonReentrant
        montoValido(amount)
    {
        /*//////////////////////////////////////////////////////////////
                                CHECKS
        //////////////////////////////////////////////////////////////*/

        // Saldo suficiente
        uint256 balance = s_ethBalances[msg.sender];
        if (amount > balance) {
            revert KipuBankV3_SaldoInsuficiente(amount, balance);
        }

        // Límite por transacción, expresado en USD(6)
        uint256 usd6 = _ethToUSD6(amount);
        if (usd6 > i_withdrawLimitUSD6) {
            revert KipuBankV3_LimiteExtraccion(usd6, i_withdrawLimitUSD6);
        }

        /*//////////////////////////////////////////////////////////////
                                EFFECTS
        //////////////////////////////////////////////////////////////*/

        unchecked {
            s_ethBalances[msg.sender] = balance - amount;
            s_totalUSD6 -= usd6;
        }
        s_withdrawCount[msg.sender] += 1;
        s_totalWithdrawals += 1;

        /*//////////////////////////////////////////////////////////////
                             INTERACTIONS
        //////////////////////////////////////////////////////////////*/

        // Envío de ETH nativo al usuario
        (bool success, bytes memory reason) = payable(msg.sender).call{value: amount}("");
        if (!success) revert KipuBankV3_TransferenciaFallida(reason);

        emit KipuBankV3_ExtraccionETH(msg.sender, amount, usd6);
    }

    /**
     * @notice Retira USDC de la bóveda respetando límite por transacción.
     */
    function withdrawUSDC(uint256 amount)
        external
        whenNotPaused
        nonReentrant
        montoValido(amount)
    {
        /*//////////////////////////////////////////////////////////////
                                CHECKS
        //////////////////////////////////////////////////////////////*/

        uint256 balance = s_usdcBalances[msg.sender];
        if (amount > balance) {
            revert KipuBankV3_SaldoInsuficiente(amount, balance);
        }

        if (amount > i_withdrawLimitUSD6) {
            revert KipuBankV3_LimiteExtraccion(amount, i_withdrawLimitUSD6);
        }

        /*//////////////////////////////////////////////////////////////
                                EFFECTS
        //////////////////////////////////////////////////////////////*/

        unchecked {
            s_usdcBalances[msg.sender] = balance - amount;
            s_totalUSD6 -= amount;
        }
        s_withdrawCount[msg.sender] += 1;
        s_totalWithdrawals += 1;

        /*//////////////////////////////////////////////////////////////
                             INTERACTIONS
        //////////////////////////////////////////////////////////////*/

        i_usdc.safeTransfer(msg.sender, amount);

        emit KipuBankV3_ExtraccionUSDC(msg.sender, amount);
    }

    /*///////////////////////
       Conversión ETH→USD6
    ///////////////////////*/

    /**
     * @notice Convierte un monto en ETH (wei) a USD(6) usando Chainlink ETH/USD.
     * @dev Valida que el precio sea positivo, que no esté obsoleto, y que la ronda sea fresca.
     *      amountETH(1e18) * price(1e8) / 1e20 = USD(1e6).
     */
    function _ethToUSD6(uint256 amountETH) internal view returns (uint256 usd6) {
        (uint80 roundID, int256 price, , uint256 updatedAt, uint80 answeredInRound) =
            i_ethUsdFeed.latestRoundData();

        if (price <= 0) revert KipuBankV3_OracleComprometido();
        if (block.timestamp - updatedAt > ORACLE_HEARTBEAT) revert KipuBankV3_StalePrice();
        if (answeredInRound < roundID) revert KipuBankV3_StalePrice();

        // El cast a uint256 es seguro porque Chainlink garantiza precio positivo
        usd6 = (amountETH * uint256(price)) / DECIMAL_FACTOR;
    }

    /*///////////////////////
        Funciones de vista
    ///////////////////////*/

    /**
     * @notice Devuelve el balance interno de ETH para un usuario (en wei).
     */
    function getEthBalance(address user) external view returns (uint256 balanceWei) {
        return s_ethBalances[user];
    }

    /**
     * @notice Devuelve el balance interno de USDC para un usuario (6 decimales).
     */
    function getUsdcBalance(address user) external view returns (uint256 balanceUSDC) {
        return s_usdcBalances[user];
    }

    /**
     * @notice Devuelve el balance de ETH nativo que posee el contrato (en wei).
     */
    function contractBalanceETH() external view returns (uint256 balanceETH) {
        return address(this).balance;
    }

    /**
     * @notice Devuelve el balance de USDC que posee el contrato (6 decimales).
     */
    function contractBalanceUSDC() external view returns (uint256 balanceUSDC) {
        return i_usdc.balanceOf(address(this));
    }

    /*///////////////////////
         Receive/Fallback
    ///////////////////////*/

    /// @notice Rechaza recibir ETH fuera de depositETH() / depositETHviaUniswap() para no saltar validaciones
    receive() external payable {
        revert KipuBankV3_LlamadaInvalida();
    }

    /// @notice Rechaza llamadas a funciones inexistentes o con datos no compatibles
    fallback() external payable {
        revert KipuBankV3_LlamadaInvalida();
    }
}
