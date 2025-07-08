// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Interface para comunicarse con ShelterDatabase
interface IShelterDatabase {
    enum ShelterStatus { Incomplete, Pending, Approved, UnderReview, Rejected }
    
    function shelterCount() external view returns (uint256);
    function getShelter(uint256 _shelterId) external view returns (
        string memory name,
        string memory email,
        string memory location,
        string memory contact,
        bool hasOfficialId,
        string memory officialId,
        ShelterStatus status,
        address submittedBy
    );
    function getShelterExtendedInfo(uint256 _shelterId) external view returns (
        string memory details,
        string memory fullAddress,
        string memory coords,
        string memory operations,
        string memory responsible
    );
}

contract DonationManager is ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    
    IShelterDatabase public shelterDatabase;
    address public owner;
    address public treasuryWallet; // Wallet para comisiones de la plataforma
    
    // Configuración de comisiones
    uint256 public platformFeePercentage = 250; // 2.5% (250 basis points)
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public minimumDonation = 0.001 ether; // Donación mínima
    
    // Estructuras de datos
    struct Donation {
        address donor;
        uint256 shelterId;
        uint256 amount;
        uint256 platformFee;
        uint256 netAmount;
        uint256 timestamp;
        string message;
        bool isAnonymous;
    }
    
    struct ShelterFinancials {
        uint256 totalReceived;
        uint256 totalWithdrawn;
        uint256 availableBalance;
        uint256 totalDonations;
        uint256 lastWithdrawal;
        bool isActive;
    }
    
    struct DonorProfile {
        uint256 totalDonated;
        uint256 donationCount;
        uint256 sheltersSupported;
        uint256 firstDonation;
        uint256 lastDonation;
    }
    
    // Almacenamiento de datos
    mapping(uint256 => ShelterFinancials) public shelterFinancials;
    mapping(address => DonorProfile) public donorProfiles;
    mapping(uint256 => Donation[]) public shelterDonations;
    mapping(address => uint256[]) public donorDonationIds;
    
    // Arrays para tracking
    Donation[] public allDonations;
    uint256[] public activeShelters;
    mapping(uint256 => bool) public isShelterActive;
    
    // Estadísticas globales
    uint256 public totalDonationsAmount;
    uint256 public totalPlatformFees;
    uint256 public totalWithdrawnByOwner;
    uint256 public totalActiveShelters;
    uint256 public totalDonors;
    
    // Control de retiros
    uint256 public withdrawalCooldown = 86400; // 24 horas
    mapping(uint256 => uint256) public lastWithdrawalTime;
    
    // Eventos
    event DonationReceived(
        uint256 indexed donationId,
        address indexed donor,
        uint256 indexed shelterId,
        uint256 amount,
        uint256 platformFee,
        uint256 netAmount,
        string message,
        bool isAnonymous
    );
    
    event ShelterWithdrawal(
        uint256 indexed shelterId,
        address indexed shelterOwner,
        uint256 amount,
        uint256 timestamp
    );
    
    event PlatformFeeWithdrawal(
        address indexed owner,
        uint256 amount,
        uint256 timestamp
    );
    
    event ShelterActivated(uint256 indexed shelterId);
    event ShelterDeactivated(uint256 indexed shelterId);
    event PlatformFeeUpdated(uint256 newFeePercentage);
    event MinimumDonationUpdated(uint256 newMinimum);
    
    constructor(
        address _shelterDatabase,
        address _treasuryWallet
    ) {
        owner = msg.sender;
        shelterDatabase = IShelterDatabase(_shelterDatabase);
        treasuryWallet = _treasuryWallet;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el propietario");
        _;
    }
    
    modifier onlyApprovedShelter(uint256 _shelterId) {
        require(_shelterId > 0 && _shelterId <= shelterDatabase.shelterCount(), "ID invalido");
        (,,,,,, IShelterDatabase.ShelterStatus status,) = shelterDatabase.getShelter(_shelterId);
        require(status == IShelterDatabase.ShelterStatus.Approved, "Refugio no aprobado");
        _;
    }
    
    modifier onlyShelterOwner(uint256 _shelterId) {
        (,,,,,, , address submittedBy) = shelterDatabase.getShelter(_shelterId);
        require(msg.sender == submittedBy, "No eres el propietario del refugio");
        _;
    }
    
    // Función principal para donar
    function donate(
        uint256 _shelterId,
        string memory _message,
        bool _isAnonymous
    ) external payable nonReentrant whenNotPaused onlyApprovedShelter(_shelterId) {
        require(msg.value >= minimumDonation, "Donacion menor al minimo");
        
        // Calcular comisión de plataforma
        uint256 platformFee = msg.value.mul(platformFeePercentage).div(BASIS_POINTS);
        uint256 netAmount = msg.value.sub(platformFee);
        
        // Crear registro de donación
        Donation memory newDonation = Donation({
            donor: msg.sender,
            shelterId: _shelterId,
            amount: msg.value,
            platformFee: platformFee,
            netAmount: netAmount,
            timestamp: block.timestamp,
            message: _message,
            isAnonymous: _isAnonymous
        });
        
        // Almacenar donación
        uint256 donationId = allDonations.length;
        allDonations.push(newDonation);
        shelterDonations[_shelterId].push(newDonation);
        donorDonationIds[msg.sender].push(donationId);
        
        // Actualizar finanzas del refugio
        ShelterFinancials storage shelter = shelterFinancials[_shelterId];
        shelter.totalReceived = shelter.totalReceived.add(netAmount);
        shelter.availableBalance = shelter.availableBalance.add(netAmount);
        shelter.totalDonations = shelter.totalDonations.add(1);
        
        // Activar refugio si es la primera donación
        if (!shelter.isActive) {
            shelter.isActive = true;
            activeShelters.push(_shelterId);
            isShelterActive[_shelterId] = true;
            totalActiveShelters = totalActiveShelters.add(1);
            emit ShelterActivated(_shelterId);
        }
        
        // Actualizar perfil del donante
        DonorProfile storage donor = donorProfiles[msg.sender];
        if (donor.totalDonated == 0) {
            donor.firstDonation = block.timestamp;
            totalDonors = totalDonors.add(1);
        }
        
        donor.totalDonated = donor.totalDonated.add(msg.value);
        donor.donationCount = donor.donationCount.add(1);
        donor.lastDonation = block.timestamp;
        
        // Contar refugios únicos apoyados
        bool isNewShelterForDonor = true;
        for (uint256 i = 0; i < donorDonationIds[msg.sender].length - 1; i++) {
            if (allDonations[donorDonationIds[msg.sender][i]].shelterId == _shelterId) {
                isNewShelterForDonor = false;
                break;
            }
        }
        if (isNewShelterForDonor) {
            donor.sheltersSupported = donor.sheltersSupported.add(1);
        }
        
        // Actualizar estadísticas globales
        totalDonationsAmount = totalDonationsAmount.add(msg.value);
        totalPlatformFees = totalPlatformFees.add(platformFee);
        
        emit DonationReceived(
            donationId,
            msg.sender,
            _shelterId,
            msg.value,
            platformFee,
            netAmount,
            _message,
            _isAnonymous
        );
    }
    
    // Función para que los refugios retiren fondos
    function withdrawFunds(uint256 _shelterId) 
        external 
        nonReentrant 
        onlyShelterOwner(_shelterId) 
        onlyApprovedShelter(_shelterId) 
    {
        ShelterFinancials storage shelter = shelterFinancials[_shelterId];
        require(shelter.availableBalance > 0, "No hay fondos disponibles");
        require(
            block.timestamp >= lastWithdrawalTime[_shelterId].add(withdrawalCooldown), 
            "Periodo de espera activo"
        );
        
        uint256 amount = shelter.availableBalance;
        shelter.availableBalance = 0;
        shelter.totalWithdrawn = shelter.totalWithdrawn.add(amount);
        shelter.lastWithdrawal = block.timestamp;
        lastWithdrawalTime[_shelterId] = block.timestamp;
        
        // Transferir fondos
        payable(msg.sender).transfer(amount);
        
        emit ShelterWithdrawal(_shelterId, msg.sender, amount, block.timestamp);
    }
    
    // Función para retirar comisiones de plataforma
    function withdrawPlatformFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No hay comisiones para retirar");
        
        totalWithdrawnByOwner = totalWithdrawnByOwner.add(balance);
        payable(treasuryWallet).transfer(balance);
        
        emit PlatformFeeWithdrawal(treasuryWallet, balance, block.timestamp);
    }
    
    // Función para donaciones recurrentes (programadas)
    function scheduleRecurringDonation(
        uint256 _shelterId,
        uint256 _amount,
        uint256 _intervalDays,
        string memory _message
    ) external onlyApprovedShelter(_shelterId) {
        // Esta función almacenaría la configuración para donaciones recurrentes
        // En una implementación completa, necesitarías un sistema off-chain
        // o integración con Chainlink Automation para ejecutar automáticamente
        
        // Por ahora, emitimos un evento para tracking
        emit RecurringDonationScheduled(
            msg.sender,
            _shelterId,
            _amount,
            _intervalDays,
            _message
        );
    }
    
    // Funciones administrativas
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 500, "Comision muy alta"); // Max 5%
        platformFeePercentage = _newFeePercentage;
        emit PlatformFeeUpdated(_newFeePercentage);
    }
    
    function updateMinimumDonation(uint256 _newMinimum) external onlyOwner {
        minimumDonation = _newMinimum;
        emit MinimumDonationUpdated(_newMinimum);
    }
    
    function updateWithdrawalCooldown(uint256 _newCooldown) external onlyOwner {
        withdrawalCooldown = _newCooldown;
    }
    
    function updateTreasuryWallet(address _newTreasury) external onlyOwner {
        treasuryWallet = _newTreasury;
    }
    
    // Funciones de emergencia
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw(uint256 _shelterId) external onlyOwner {
        // Solo para emergencias - permite al owner retirar fondos
        ShelterFinancials storage shelter = shelterFinancials[_shelterId];
        uint256 amount = shelter.availableBalance;
        shelter.availableBalance = 0;
        payable(treasuryWallet).transfer(amount);
    }
    
    // Funciones de consulta
    function getShelterFinancials(uint256 _shelterId) external view returns (
        uint256 totalReceived,
        uint256 totalWithdrawn,
        uint256 availableBalance,
        uint256 totalDonations,
        uint256 lastWithdrawal,
        bool isActive
    ) {
        ShelterFinancials memory shelter = shelterFinancials[_shelterId];
        return (
            shelter.totalReceived,
            shelter.totalWithdrawn,
            shelter.availableBalance,
            shelter.totalDonations,
            shelter.lastWithdrawal,
            shelter.isActive
        );
    }
    
    function getDonorProfile(address _donor) external view returns (
        uint256 totalDonated,
        uint256 donationCount,
        uint256 sheltersSupported,
        uint256 firstDonation,
        uint256 lastDonation
    ) {
        DonorProfile memory donor = donorProfiles[_donor];
        return (
            donor.totalDonated,
            donor.donationCount,
            donor.sheltersSupported,
            donor.firstDonation,
            donor.lastDonation
        );
    }
    
    function getShelterDonations(uint256 _shelterId) external view returns (
        Donation[] memory
    ) {
        return shelterDonations[_shelterId];
    }
    
    function getDonorDonations(address _donor) external view returns (
        Donation[] memory
    ) {
        uint256[] memory donationIds = donorDonationIds[_donor];
        Donation[] memory donations = new Donation[](donationIds.length);
        
        for (uint256 i = 0; i < donationIds.length; i++) {
            donations[i] = allDonations[donationIds[i]];
        }
        
        return donations;
    }
    
    function getActiveShelters() external view returns (uint256[] memory) {
        return activeShelters;
    }
    
    function getRecentDonations(uint256 _limit) external view returns (
        Donation[] memory
    ) {
        require(_limit > 0, "Limite debe ser mayor a 0");
        
        uint256 totalDonations = allDonations.length;
        uint256 limit = _limit > totalDonations ? totalDonations : _limit;
        
        Donation[] memory recent = new Donation[](limit);
        
        for (uint256 i = 0; i < limit; i++) {
            recent[i] = allDonations[totalDonations - 1 - i];
        }
        
        return recent;
    }
    
    function getShelterStats(uint256 _shelterId) external view returns (
        uint256 totalReceived,
        uint256 donationCount,
        uint256 averageDonation,
        uint256 lastDonationTime
    ) {
        ShelterFinancials memory shelter = shelterFinancials[_shelterId];
        Donation[] memory donations = shelterDonations[_shelterId];
        
        totalReceived = shelter.totalReceived;
        donationCount = shelter.totalDonations;
        
        if (donationCount > 0) {
            averageDonation = totalReceived.div(donationCount);
            lastDonationTime = donations[donations.length - 1].timestamp;
        }
    }
    
    function getPlatformStats() external view returns (
        uint256 totalDonations,
        uint256 totalFees,
        uint256 activeSheltersCount,
        uint256 totalDonorsCount,
        uint256 averageDonation
    ) {
        totalDonations = totalDonationsAmount;
        totalFees = totalPlatformFees;
        activeSheltersCount = totalActiveShelters;
        totalDonorsCount = totalDonors;
        
        if (allDonations.length > 0) {
            averageDonation = totalDonationsAmount.div(allDonations.length);
        }
    }
    
    // Función para verificar si un refugio puede recibir donaciones
    function canReceiveDonations(uint256 _shelterId) external view returns (bool) {
        if (_shelterId == 0 || _shelterId > shelterDatabase.shelterCount()) {
            return false;
        }
        
        (,,,,,, IShelterDatabase.ShelterStatus status,) = shelterDatabase.getShelter(_shelterId);
        return status == IShelterDatabase.ShelterStatus.Approved;
    }
    
    // Eventos adicionales
    event RecurringDonationScheduled(
        address indexed donor,
        uint256 indexed shelterId,
        uint256 amount,
        uint256 intervalDays,
        string message
    );
    
    // Función para recibir pagos directos
    receive() external payable {
        revert("Use la funcion donate()");
    }
    
    fallback() external payable {
        revert("Funcion no encontrada");
    }
}