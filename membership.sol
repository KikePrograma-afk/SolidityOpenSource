// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

// Interface para comunicarse con ShelterDatabase
interface IShelterDatabase {
    enum ShelterStatus { Incomplete, Pending, Approved, UnderReview, Rejected }
    
    function shelterCount() external view returns (uint256);
    function updateShelterStatus(uint256 _shelterId, ShelterStatus _status) external;
    function updateShelterVotes(uint256 _shelterId, uint256 _approvalVotes, uint256 _reviewVotes) external;
    function getShelterVotes(uint256 _shelterId) external view returns (uint256 approvalVotes, uint256 reviewVotes);
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
}

contract MembershipAndVoting is ReentrancyGuard, Pausable {
    IShelterDatabase public shelterDatabase;
    address public owner;
    address public treasuryWallet;
    
    // Configuración de membresía
    uint256 public membershipFee = 0.01 ether; // Fee mínimo para ser miembro
    uint256 public approvalThreshold = 3; // Votos necesarios para aprobar
    uint256 public reviewThreshold = 2; // Votos necesarios para marcar como "bajo revisión"
    uint256 public rejectionThreshold = 3; // Votos necesarios para rechazar
    
    // Estados de membresía
    mapping(address => bool) public isMember;
    mapping(address => uint256) public memberSince;
    mapping(address => uint256) public memberDonationTotal;
    mapping(address => uint256) public memberVotingPower; // Poder de voto basado en donaciones
    
    // Control de votos por refugio
    mapping(uint256 => mapping(address => bool)) public hasVotedApproval;
    mapping(uint256 => mapping(address => bool)) public hasVotedReview;
    mapping(uint256 => mapping(address => bool)) public hasVotedRejection;
    
    // Listas de votantes por refugio
    mapping(uint256 => address[]) public approvalVoters;
    mapping(uint256 => address[]) public reviewVoters;
    mapping(uint256 => address[]) public rejectionVoters;
    
    // Estadísticas de miembros
    struct MemberStats {
        uint256 totalVotes;
        uint256 approvalsVoted;
        uint256 reviewsVoted;
        uint256 rejectionsVoted;
        uint256 lastVoteTime;
    }
    mapping(address => MemberStats) public memberStats;
    
    // Estadísticas globales
    uint256 public totalMembers;
    uint256 public totalMembershipFees;
    uint256 public totalVotesCast;
    uint256 public totalSheltersApproved;
    uint256 public totalSheltersRejected;
    
    // Eventos
    event MembershipAcquired(address indexed member, uint256 amount, uint256 timestamp);
    event MembershipUpgraded(address indexed member, uint256 additionalAmount, uint256 newTotal);
    event VoteCast(uint256 indexed shelterId, address indexed voter, string voteType, uint256 timestamp);
    event ShelterApproved(uint256 indexed shelterId, uint256 totalApprovalVotes, uint256 timestamp);
    event ShelterMarkedForReview(uint256 indexed shelterId, uint256 totalReviewVotes, uint256 timestamp);
    event ShelterRejected(uint256 indexed shelterId, uint256 totalRejectionVotes, uint256 timestamp);
    event ThresholdUpdated(string thresholdType, uint256 newValue);
    event MembershipFeeUpdated(uint256 newFee);
    
    // --- CONSTRUCTOR CORREGIDO ---
    constructor(address _shelterDatabase, address _treasuryWallet) ReentrancyGuard() Pausable() {
        owner = msg.sender;
        shelterDatabase = IShelterDatabase(_shelterDatabase);
        treasuryWallet = _treasuryWallet;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el propietario");
        _;
    }
    
    modifier onlyMember() {
        require(isMember[msg.sender], "Solo miembros pueden votar");
        _;
    }
    
    modifier validShelterId(uint256 _shelterId) {
        require(_shelterId > 0 && _shelterId <= shelterDatabase.shelterCount(), "ID de refugio invalido");
        _;
    }
    
    modifier shelterInPendingState(uint256 _shelterId) {
        (,,,,,, IShelterDatabase.ShelterStatus status,) = shelterDatabase.getShelter(_shelterId);
        require(status == IShelterDatabase.ShelterStatus.Pending, "Refugio no esta en estado pendiente");
        _;
    }
    
    // --- RESTO DEL CÓDIGO (SIN CAMBIOS) ---

    function becomeMember() external payable nonReentrant whenNotPaused {
        require(msg.value >= membershipFee, "Donacion minima no alcanzada");
        require(!isMember[msg.sender], "Ya eres miembro");
        
        isMember[msg.sender] = true;
        memberSince[msg.sender] = block.timestamp;
        memberDonationTotal[msg.sender] = msg.value;
        memberVotingPower[msg.sender] = calculateVotingPower(msg.value);
        
        totalMembers++;
        totalMembershipFees += msg.value;
        
        payable(treasuryWallet).transfer(msg.value);
        
        emit MembershipAcquired(msg.sender, msg.value, block.timestamp);
    }
    
    function upgradeMembership() external payable nonReentrant whenNotPaused {
        require(isMember[msg.sender], "No eres miembro");
        require(msg.value > 0, "Debe enviar una cantidad mayor a 0");
        
        memberDonationTotal[msg.sender] += msg.value;
        memberVotingPower[msg.sender] = calculateVotingPower(memberDonationTotal[msg.sender]);
        
        totalMembershipFees += msg.value;
        
        payable(treasuryWallet).transfer(msg.value);
        
        emit MembershipUpgraded(msg.sender, msg.value, memberDonationTotal[msg.sender]);
    }
    
    function voteForApproval(uint256 _shelterId) 
        external 
        onlyMember 
        validShelterId(_shelterId) 
        shelterInPendingState(_shelterId) 
        whenNotPaused 
    {
        require(!hasVotedApproval[_shelterId][msg.sender], "Ya has votado para aprobar este refugio");
        require(!hasVotedReview[_shelterId][msg.sender], "Ya has votado para revisar este refugio");
        require(!hasVotedRejection[_shelterId][msg.sender], "Ya has votado para rechazar este refugio");
        
        hasVotedApproval[_shelterId][msg.sender] = true;
        approvalVoters[_shelterId].push(msg.sender);
        
        memberStats[msg.sender].totalVotes++;
        memberStats[msg.sender].approvalsVoted++;
        memberStats[msg.sender].lastVoteTime = block.timestamp;
        
        (uint256 currentApprovalVotes, uint256 currentReviewVotes) = shelterDatabase.getShelterVotes(_shelterId);
        uint256 newApprovalVotes = currentApprovalVotes + memberVotingPower[msg.sender];
        
        shelterDatabase.updateShelterVotes(_shelterId, newApprovalVotes, currentReviewVotes);
        
        totalVotesCast++;
        
        emit VoteCast(_shelterId, msg.sender, "approval", block.timestamp);
        
        if (newApprovalVotes >= approvalThreshold) {
            shelterDatabase.updateShelterStatus(_shelterId, IShelterDatabase.ShelterStatus.Approved);
            totalSheltersApproved++;
            emit ShelterApproved(_shelterId, newApprovalVotes, block.timestamp);
        }
    }
    
    function voteForReview(uint256 _shelterId) 
        external 
        onlyMember 
        validShelterId(_shelterId) 
        shelterInPendingState(_shelterId) 
        whenNotPaused 
    {
        require(!hasVotedApproval[_shelterId][msg.sender], "Ya has votado para aprobar este refugio");
        require(!hasVotedReview[_shelterId][msg.sender], "Ya has votado para revisar este refugio");
        require(!hasVotedRejection[_shelterId][msg.sender], "Ya has votado para rechazar este refugio");
        
        hasVotedReview[_shelterId][msg.sender] = true;
        reviewVoters[_shelterId].push(msg.sender);
        
        memberStats[msg.sender].totalVotes++;
        memberStats[msg.sender].reviewsVoted++;
        memberStats[msg.sender].lastVoteTime = block.timestamp;
        
        (uint256 currentApprovalVotes, uint256 currentReviewVotes) = shelterDatabase.getShelterVotes(_shelterId);
        uint256 newReviewVotes = currentReviewVotes + memberVotingPower[msg.sender];
        
        shelterDatabase.updateShelterVotes(_shelterId, currentApprovalVotes, newReviewVotes);
        
        totalVotesCast++;
        
        emit VoteCast(_shelterId, msg.sender, "review", block.timestamp);
        
        if (newReviewVotes >= reviewThreshold) {
            shelterDatabase.updateShelterStatus(_shelterId, IShelterDatabase.ShelterStatus.UnderReview);
            emit ShelterMarkedForReview(_shelterId, newReviewVotes, block.timestamp);
        }
    }
    
    function voteForRejection(uint256 _shelterId) 
        external 
        onlyMember 
        validShelterId(_shelterId) 
        shelterInPendingState(_shelterId) 
        whenNotPaused 
    {
        require(!hasVotedApproval[_shelterId][msg.sender], "Ya has votado para aprobar este refugio");
        require(!hasVotedReview[_shelterId][msg.sender], "Ya has votado para revisar este refugio");
        require(!hasVotedRejection[_shelterId][msg.sender], "Ya has votado para rechazar este refugio");
        
        hasVotedRejection[_shelterId][msg.sender] = true;
        rejectionVoters[_shelterId].push(msg.sender);
        
        memberStats[msg.sender].totalVotes++;
        memberStats[msg.sender].rejectionsVoted++;
        memberStats[msg.sender].lastVoteTime = block.timestamp;
        
        uint256 totalRejectionVotes = 0;
        for (uint256 i = 0; i < rejectionVoters[_shelterId].length; i++) {
            totalRejectionVotes += memberVotingPower[rejectionVoters[_shelterId][i]];
        }
        
        totalVotesCast++;
        
        emit VoteCast(_shelterId, msg.sender, "rejection", block.timestamp);
        
        if (totalRejectionVotes >= rejectionThreshold) {
            shelterDatabase.updateShelterStatus(_shelterId, IShelterDatabase.ShelterStatus.Rejected);
            totalSheltersRejected++;
            emit ShelterRejected(_shelterId, totalRejectionVotes, block.timestamp);
        }
    }
    
    function calculateVotingPower(uint256 _donationAmount) public pure returns (uint256) {
        // Esta función ahora es 'pure' porque no lee el estado del contrato (membershipFee)
        // Lo pasamos como un valor fijo por ahora, o podrías leerlo desde una constante.
        uint256 fee = 0.01 ether;
        uint256 basePower = 1;
        if (_donationAmount < fee) return 0; // No debería pasar por el require, pero por seguridad.
        uint256 additionalPower = (_donationAmount - fee) / fee;
        uint256 maxPower = 5;
        
        uint256 finalPower = basePower + additionalPower;
        return finalPower > maxPower ? maxPower : finalPower;
    }
    
    function updateMembershipFee(uint256 _newFee) external onlyOwner {
        require(_newFee > 0, "Fee debe ser mayor a 0");
        membershipFee = _newFee;
        emit MembershipFeeUpdated(_newFee);
    }
    
    function updateApprovalThreshold(uint256 _newThreshold) external onlyOwner {
        require(_newThreshold > 0, "Threshold debe ser mayor a 0");
        approvalThreshold = _newThreshold;
        emit ThresholdUpdated("approval", _newThreshold);
    }
    
    function updateReviewThreshold(uint256 _newThreshold) external onlyOwner {
        require(_newThreshold > 0, "Threshold debe ser mayor a 0");
        reviewThreshold = _newThreshold;
        emit ThresholdUpdated("review", _newThreshold);
    }
    
    function updateRejectionThreshold(uint256 _newThreshold) external onlyOwner {
        require(_newThreshold > 0, "Threshold debe ser mayor a 0");
        rejectionThreshold = _newThreshold;
        emit ThresholdUpdated("rejection", _newThreshold);
    }
    
    function updateTreasuryWallet(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Direccion invalida");
        treasuryWallet = _newTreasury;
    }
    
    function updateShelterDatabase(address _newShelterDatabase) external onlyOwner {
        require(_newShelterDatabase != address(0), "Direccion invalida");
        shelterDatabase = IShelterDatabase(_newShelterDatabase);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw() external onlyOwner {
        payable(treasuryWallet).transfer(address(this).balance);
    }
    
    function getMemberInfo(address _member) external view returns (
        bool isActiveMember,
        uint256 membershipDate,
        uint256 totalDonated,
        uint256 votingPower,
        MemberStats memory stats
    ) {
        return (
            isMember[_member],
            memberSince[_member],
            memberDonationTotal[_member],
            memberVotingPower[_member],
            memberStats[_member]
        );
    }
    
    function getShelterVotingInfo(uint256 _shelterId) external view validShelterId(_shelterId) returns (
        uint256 approvalVotes,
        uint256 reviewVotes,
        uint256 rejectionVotes,
        address[] memory approvalVotersList,
        address[] memory reviewVotersList,
        address[] memory rejectionVotersList,
        bool canVote
    ) {
        (approvalVotes, reviewVotes) = shelterDatabase.getShelterVotes(_shelterId);
        
        uint256 totalRejectionVotes = 0;
        for (uint256 i = 0; i < rejectionVoters[_shelterId].length; i++) {
            totalRejectionVotes += memberVotingPower[rejectionVoters[_shelterId][i]];
        }
        
        bool canVoteForShelter = isMember[msg.sender] && 
                                !hasVotedApproval[_shelterId][msg.sender] && 
                                !hasVotedReview[_shelterId][msg.sender] && 
                                !hasVotedRejection[_shelterId][msg.sender];
        
        return (
            approvalVotes,
            reviewVotes,
            totalRejectionVotes,
            approvalVoters[_shelterId],
            reviewVoters[_shelterId],
            rejectionVoters[_shelterId],
            canVoteForShelter
        );
    }
    
    function getPendingShelters() external view returns (uint256[] memory) {
        uint256 count = shelterDatabase.shelterCount();
        if (count == 0) {
            return new uint256[](0);
        }
        uint256[] memory pendingShelters = new uint256[](count);
        uint256 pendingCount = 0;
        
        for (uint256 i = 1; i <= count; i++) {
            (,,,,,, IShelterDatabase.ShelterStatus status,) = shelterDatabase.getShelter(i);
            if (status == IShelterDatabase.ShelterStatus.Pending) {
                pendingShelters[pendingCount] = i;
                pendingCount++;
            }
        }
        
        uint256[] memory result = new uint256[](pendingCount);
        for (uint256 i = 0; i < pendingCount; i++) {
            result[i] = pendingShelters[i];
        }
        
        return result;
    }
    
    function getDAOStats() external view returns (
        uint256 totalMembersCount,
        uint256 totalFees,
        uint256 totalVotes,
        uint256 approvedShelters,
        uint256 rejectedShelters,
        uint256 averageDonationPerMember
    ) {
        uint256 avgDonation = totalMembers > 0 ? totalMembershipFees / totalMembers : 0;
        
        return (
            totalMembers,
            totalMembershipFees,
            totalVotesCast,
            totalSheltersApproved,
            totalSheltersRejected,
            avgDonation
        );
    }
    
    receive() external payable {
        if (isMember[msg.sender]) {
            memberDonationTotal[msg.sender] += msg.value;
            memberVotingPower[msg.sender] = calculateVotingPower(memberDonationTotal[msg.sender]);
            totalMembershipFees += msg.value;
            payable(treasuryWallet).transfer(msg.value);
            emit MembershipUpgraded(msg.sender, msg.value, memberDonationTotal[msg.sender]);
        } else {
            revert("Use becomeMember() para unirte a la DAO");
        }
    }
    
    fallback() external payable {
        revert("Funcion no encontrada");
    }
}