// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract ShelterDatabase {
    address public owner;
    address public governanceContract;
    
    enum ShelterStatus { Incomplete, Pending, Approved, UnderReview, Rejected }
    
    // Struct súper simple - solo 8 campos
    struct Shelter {
        string name;
        string email;
        string location;
        string contact;
        bool hasOfficialId;
        string officialId;
        ShelterStatus status;
        address submittedBy;
    }
    
    // Datos adicionales en mappings separados
    mapping(uint256 => string) public shelterDetails;    // Descripción, website, etc.
    mapping(uint256 => string) public shelterAddress;    // Dirección completa
    mapping(uint256 => string) public shelterCoords;     // Latitud,Longitud
    mapping(uint256 => string) public shelterOperations; // Horarios, capacidad, etc.
    mapping(uint256 => string) public shelterResponsible; // Datos del responsable
    mapping(uint256 => uint256) public shelterVotes;     // approval_votes * 1000000 + review_votes
    
    mapping(uint256 => Shelter) public shelters;
    mapping(string => bool) public officialIdUsed;
    uint256 public shelterCount;
    
    event ShelterRegistered(uint256 indexed shelterId, string name, address submittedBy);
    event ShelterUpdated(uint256 indexed shelterId, string section);
    event ShelterStatusChanged(uint256 indexed shelterId, ShelterStatus status);
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el propietario");
        _;
    }
    
    modifier onlyGovernance() {
        require(msg.sender == governanceContract, "Solo gobernanza");
        _;
    }
    
    function setGovernanceContract(address _governance) external onlyOwner {
        governanceContract = _governance;
    }
    
    // Registro básico - solo 6 parámetros
    function registerShelter(
        string memory _name,
        string memory _email,
        string memory _location,
        string memory _contact,
        bool _hasOfficialId,
        string memory _officialId
    ) external returns (uint256) {
        require(bytes(_name).length > 0, "Nombre requerido");
        require(bytes(_email).length > 0, "Email requerido");
        
        if (_hasOfficialId) {
            require(bytes(_officialId).length > 0, "ID oficial requerido");
            require(!officialIdUsed[_officialId], "ID ya usado");
            officialIdUsed[_officialId] = true;
        }
        
        shelterCount++;
        
        shelters[shelterCount] = Shelter({
            name: _name,
            email: _email,
            location: _location,
            contact: _contact,
            hasOfficialId: _hasOfficialId,
            officialId: _officialId,
            status: ShelterStatus.Incomplete,
            submittedBy: msg.sender
        });
        
        emit ShelterRegistered(shelterCount, _name, msg.sender);
        return shelterCount;
    }
    
    // Actualizar detalles por separado
    function updateShelterDetails(uint256 _shelterId, string memory _details) external {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        require(shelters[_shelterId].submittedBy == msg.sender, "No autorizado");
        
        shelterDetails[_shelterId] = _details;
        emit ShelterUpdated(_shelterId, "details");
    }
    
    function updateShelterAddress(uint256 _shelterId, string memory _address) external {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        require(shelters[_shelterId].submittedBy == msg.sender, "No autorizado");
        
        shelterAddress[_shelterId] = _address;
        emit ShelterUpdated(_shelterId, "address");
    }
    
    function updateShelterCoords(uint256 _shelterId, string memory _coords) external {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        require(shelters[_shelterId].submittedBy == msg.sender, "No autorizado");
        
        shelterCoords[_shelterId] = _coords;
        emit ShelterUpdated(_shelterId, "coords");
    }
    
    function updateShelterOperations(uint256 _shelterId, string memory _operations) external {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        require(shelters[_shelterId].submittedBy == msg.sender, "No autorizado");
        
        shelterOperations[_shelterId] = _operations;
        emit ShelterUpdated(_shelterId, "operations");
    }
    
    function updateShelterResponsible(uint256 _shelterId, string memory _responsible) external {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        require(shelters[_shelterId].submittedBy == msg.sender, "No autorizado");
        
        shelterResponsible[_shelterId] = _responsible;
        emit ShelterUpdated(_shelterId, "responsible");
    }
    
    function finalizeShelter(uint256 _shelterId) external {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        require(shelters[_shelterId].submittedBy == msg.sender, "No autorizado");
        require(shelters[_shelterId].status == ShelterStatus.Incomplete, "Ya finalizado");
        
        shelters[_shelterId].status = ShelterStatus.Pending;
        emit ShelterStatusChanged(_shelterId, ShelterStatus.Pending);
    }
    
    // Funciones para gobernanza
    function updateShelterStatus(uint256 _shelterId, ShelterStatus _status) external onlyGovernance {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        shelters[_shelterId].status = _status;
        emit ShelterStatusChanged(_shelterId, _status);
    }
    
    function updateShelterVotes(uint256 _shelterId, uint256 _approvalVotes, uint256 _reviewVotes) external onlyGovernance {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        // Combinar votos en un solo número: approval_votes * 1000000 + review_votes
        shelterVotes[_shelterId] = _approvalVotes * 1000000 + _reviewVotes;
    }
    
    function getShelterVotes(uint256 _shelterId) external view returns (uint256 approvalVotes, uint256 reviewVotes) {
        uint256 combined = shelterVotes[_shelterId];
        approvalVotes = combined / 1000000;
        reviewVotes = combined % 1000000;
    }
    
    // Funciones de consulta
    function getShelter(uint256 _shelterId) external view returns (
        string memory name,
        string memory email,
        string memory location,
        string memory contact,
        bool hasOfficialId,
        string memory officialId,
        ShelterStatus status,
        address submittedBy
    ) {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        
        Shelter memory shelter = shelters[_shelterId];
        return (
            shelter.name,
            shelter.email,
            shelter.location,
            shelter.contact,
            shelter.hasOfficialId,
            shelter.officialId,
            shelter.status,
            shelter.submittedBy
        );
    }
    
    function getShelterExtendedInfo(uint256 _shelterId) external view returns (
        string memory details,
        string memory fullAddress,
        string memory coords,
        string memory operations,
        string memory responsible
    ) {
        require(_shelterId > 0 && _shelterId <= shelterCount, "ID invalido");
        
        return (
            shelterDetails[_shelterId],
            shelterAddress[_shelterId],
            shelterCoords[_shelterId],
            shelterOperations[_shelterId],
            shelterResponsible[_shelterId]
        );
    }
}