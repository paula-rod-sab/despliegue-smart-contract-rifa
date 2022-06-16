// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
pragma experimental ABIEncoderV2;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @dev Implementacion de las funciones de la rifa
 */
contract rifa is VRFConsumerBaseV2, KeeperCompatibleInterface {

    /**
     * @dev Declaraciones de variables
     */
    uint256 private rondaId;                    // @dev Indica el número de ronda.
    address private dir_owner_rifa;             // @dev Direccion de quien despliega el contrato. 
    address private dir_contrato;               // @dev Esta direccion se encarga de guardar el dinero que hay en el bote.
    address private asociacion;                 // @dev Direccion asociacion a la que se destinara parte del premio.
    address [] private participantes;           // @dev Array que recoge a todos los participantes de la rifa.

    // ---------- Chainlink Price feeds ----------
    AggregatorV3Interface internal priceFeedETHUSD;
    AggregatorV3Interface internal priceFeedEURUSD;
    uint256 private precioPorBoletoEnEur; 

    // ---------- Chainlink Keepers --------------
    bool private estadoRifa;    // @dev True indica que está abierta, False indica que se está calculando el ganador (cerrada).
    uint256 private tiempo;     // @dev Tiempo que tiene que pasar para elegir ganador y que se reinicie la rifa.
    uint256 private lastTimeStamp;

    // ---------- Chainlink VRF ------------------
    VRFCoordinatorV2Interface private VRFCOORDINADOR;
    bytes32 private keyHash;
    uint64 private subId;
    uint16 private minimumRequestConfirmations = 3;
    uint32 private callbackGasLimit;
    uint32 private numWords = 1;


    /**
     * @dev Mappings
     */
    mapping(uint256 => mapping(address => uint)) boletosPorPersona; // @dev Relaciona la persona con los boletos que tiene en cada ronda.
    mapping(uint => address) historialGanadores;                    // @dev Relaciona la ronda con la persona ganadora.

    /**
     * @dev Eventos
     */
    event ComprandoBoletos(uint cantidadBoletos, address who);
    event PersonaGanadora(address personaGanadora);
    event transferido_ganador(uint cantidad);
    event transferido_asociacion(uint cantidad);
    event Comienzo_ronda(uint rondaId);
    event ErrorTransferAsociacion();

    /**
     * @dev Errores
     */
    error Rifa__NoHasEnviadoSuficientesFondos();
    error Rifa__SeNecesitanMasBoletosEnElBote();
    error Rifa__ErrorTransferGanador();
    error Rifa__ErrorTransferAsociacion();
    error Rifa__ErrorTransferDevolucion();
    error Rifa__ErrorNoSeHaRealizadoElCheckUpKeep();

    constructor (
        uint256 _precioPorBoletoEnEur, 
        uint256 _intervaloTiempo, 
        address _dirAsociacion, 
        address _Agg_eth_usd, 
        address _Agg_eur_usd, 
        address _vrfCoordinador,
        bytes32 _keyHash,
        uint64 _subId,
        uint32 _callbackGasLimit
        ) VRFConsumerBaseV2(_vrfCoordinador){
        precioPorBoletoEnEur = _precioPorBoletoEnEur; // euros por boleto 
        rondaId = 1;
        tiempo = _intervaloTiempo; // segundos para que se reinicie
        lastTimeStamp = block.timestamp; // momento en el que se ha minado el bloque
        estadoRifa = true;
        dir_owner_rifa = msg.sender;
        dir_contrato = address(this);
        asociacion = _dirAsociacion;
        priceFeedETHUSD = AggregatorV3Interface(_Agg_eth_usd);
        priceFeedEURUSD = AggregatorV3Interface(_Agg_eur_usd);
        VRFCOORDINADOR = VRFCoordinatorV2Interface(_vrfCoordinador);
        keyHash = _keyHash;
        subId = _subId;
        callbackGasLimit = _callbackGasLimit;
    }


    // ---------------------- GESTION DE BOLETOS -----------------------

    /**
     * @dev Compra de boletos.
     */ 
    function compraBoleto(uint _numBoletos) public payable {
        uint costeBoletos = getPrecioBoletos(_numBoletos);
        if(msg.value < costeBoletos) {
            revert Rifa__NoHasEnviadoSuficientesFondos();
        }
        if(msg.value > costeBoletos) {
            uint devuelve = msg.value - costeBoletos;
            (bool successDevolucion, ) = payable(msg.sender).call{value: devuelve}(""); // payable(msg.sender).transfer(devuelve); // @dev Envia la diferencia de Ethers que no necesita para comprar los boletos requeridos.
            if (!successDevolucion) {
                revert Rifa__ErrorTransferDevolucion();
            }
        }        
        emit ComprandoBoletos(_numBoletos, msg.sender);
        /**
        * @dev Asignacion de boletos.
        */
        boletosPorPersona[rondaId][msg.sender] += _numBoletos;
        for(uint i = 0; i < _numBoletos; i++) {
            participantes.push(msg.sender);           
        }
    }

    /**
     * @dev Funcion para obtener ganador.
     */
    function obtenerGanador(uint numeroAleatorio) private {
        // Calcula el numero aleatorio del sorteo y elige a la persona.
        uint posArray = numeroAleatorio % participantes.length;
        address personaGanadora = participantes[posArray];
        historialGanadores[rondaId] = personaGanadora;
        emit PersonaGanadora(personaGanadora);
        // Divide el bote entre el ganador y la asociacion. Un cuarto para el ganador y 3/4 para la asociacion
        uint ethers_premio = dir_contrato.balance / 4;
        uint ethers_asociacion = dir_contrato.balance - ethers_premio;
        // Se transfiere el dinero al ganador y a la asociación
        (bool successGanador, ) = payable(personaGanadora).call{value: ethers_premio}("");
        if (!successGanador) {
            revert Rifa__ErrorTransferGanador();
        }
        emit transferido_ganador(ethers_premio);
        (bool successAsociacion, ) = payable(asociacion).call{value: ethers_asociacion}("");
        if (!successAsociacion) {
            revert Rifa__ErrorTransferAsociacion();
        }
        emit transferido_asociacion(ethers_asociacion);
        // Reseteo de la ronda.
        rondaId++;
        estadoRifa = true; // Vuelve a abrirse el sorteo
        lastTimeStamp = block.timestamp; // Se reinicia el valor al bloque actual
        participantes = new address [](0);
        emit Comienzo_ronda(rondaId);
    } 

    // ---------------------- FUNCIONES PRICE FEEDS -----------------------

    /**
     * Devuelve el valor del eth en dolars y el valor del eur en dolars, multiplicado por 10**8.
     */
    function getLatestPrice() public view returns (uint256, uint256) {
        (,int priceETHUSDInt,,,) = priceFeedETHUSD.latestRoundData();
        uint256 priceETHUSD = uint256(priceETHUSDInt);
        (,int priceEURUSDInt,,,) = priceFeedEURUSD.latestRoundData();
        uint256 priceEURUSD = uint256(priceEURUSDInt);
        return (priceETHUSD, priceEURUSD);
    }

    /**
     * Devuelve el precio de la entrada en Wei.
     */
    function getPrecioBoletoEth() public view returns (uint256) {
        (uint256 eth_Usd,uint256 eur_Usd) = getLatestPrice();
        uint256 precioUnBoleto_Eth = (eur_Usd*precioPorBoletoEnEur*(10**18)) / (eth_Usd);
        return precioUnBoleto_Eth;
    }


    // ---------------------- FUNCIONES KEEPERS -----------------------

    /**
     * @dev Especifica qué tiene que ocurrir para que se ejecute la función performUpkeep().
     */
    function checkUpkeep(bytes memory /* checkData */) public view override returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool estaAbierta = (estadoRifa == true);
        bool tiempoCumplido = (block.timestamp - lastTimeStamp > tiempo);
        bool boteConFondos = (bote() > 0);
        upkeepNeeded = (estaAbierta && tiempoCumplido && boteConFondos);
        return (upkeepNeeded, "0x0");  
    }

    /**
     * @dev Se realiza el sorteo y se reinicia la ronda.
     */
    function performUpkeep(bytes memory /* performData */) external override {
        (bool checkUpkeepRealizado, ) = checkUpkeep("");
        if (!checkUpkeepRealizado) {
            revert Rifa__ErrorNoSeHaRealizadoElCheckUpKeep();
        }
        estadoRifa = false; // se cierra el sorteo
        VRFCOORDINADOR.requestRandomWords(keyHash, subId, minimumRequestConfirmations, callbackGasLimit, numWords);
    }

    // ---------------------- FUNCIONES VRF -----------------------

    function fulfillRandomWords(uint256 /**/, uint256[] memory randomWords) internal override {
        obtenerGanador(randomWords[0]);
    }


    // ---------------------- FUNCIONES AUXILIARES -----------------------

    /**
     * @dev Calcula el precio de los boletos en ethers.
     */
    function getPrecioBoletos(uint _numBoletos) public view returns (uint) {
        return _numBoletos*(getPrecioBoletoEth());
    }

    /**
     * @dev Balance de boletos en el bote.
     */
    function bote() public view returns (uint) {
        return participantes.length;
    }

    /**
     * @dev Balance de fondos en el bote. En wei
     */
    function boteEnWei() public view returns (uint) {
        return dir_contrato.balance;
    }

    /**
     * @dev Balance de fondos en el bote. En eur con 8 decimales
     */
    function boteEnEur() public view returns (uint) {
        (uint256 eth_Usd,uint256 eur_Usd) = getLatestPrice();
        uint256 precioBote_Eur = (eth_Usd*boteEnWei()*(10**8)) / (eur_Usd*(10**18));
        return precioBote_Eur;
    }

    /**
     * @dev Balance de boletos de cada persona.
     */
    function misBoletos() public view returns (uint) {
        return (boletosPorPersona[rondaId][msg.sender]);
    }

    // ---------------------- FUNCIONES GETTER -----------------------

    function getPrecioUnBoletoEur() public view returns (uint256) {
        return precioPorBoletoEnEur;
    }

    function getRondaId() public view returns (uint256) {
        return rondaId;
    }

    function getUltimoGanador() public view returns (address) {
        uint256 rondaAnterior = getRondaId() - 1;
        return historialGanadores[rondaAnterior];
    }

    function getDir_owner_rifa() public view returns (address) {
        return dir_owner_rifa;
    }

    function getDir_contrato() public view returns (address) {
        return dir_contrato;
    }

    function getDir_asociacion() public view returns (address) {
        return asociacion;
    }

    function getListaParticipantes() public view returns (address [] memory) {
        return participantes;
    }
}