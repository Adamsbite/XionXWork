// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract JobBoard is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Structs
    struct Job {
        address poster;
        string title;
        string description;
        uint256 budget;
        JobStatus status;
        address assignedFreelancer;
        uint256 createdAt;
    }

    struct Proposal {
        address freelancer;
        uint256 bidAmount;
        string coverLetter;
        ProposalStatus status;
    }

    // Enums
    enum JobStatus {
        OPEN,
        IN_PROGRESS,
        COMPLETED,
        CANCELLED
    }

    enum ProposalStatus {
        PENDING,
        ACCEPTED,
        REJECTED
    }

    // State Variables
    uint256 public jobCounter;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5; // 5% platform fee
    uint256 public constant MAX_PROPOSAL_PER_JOB = 10;

    // Mappings
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => Proposal[]) public jobProposals;
    mapping(address => uint256[]) public userJobs;
    mapping(address => uint256) public freelancerEscrow;

    // Events
    event JobPosted(
        uint256 indexed jobId,
        address indexed poster,
        string title,
        uint256 budget
    );
    event ProposalSubmitted(
        uint256 indexed jobId,
        address indexed freelancer,
        uint256 bidAmount
    );
    event ProposalAccepted(uint256 indexed jobId, address indexed freelancer);
    event JobCompleted(uint256 indexed jobId);
    event FundReleased(
        uint256 indexed jobId,
        address indexed freelancer,
        uint256 amount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        jobCounter = 0;
    }

    // Job Posting Function
    function postJob(
        string memory _title,
        string memory _description,
        uint256 _budget
    ) external payable nonReentrant {
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(_budget > 0, "Budget must be greater than 0");
        require(msg.value == _budget, "Sent value must match budget");

        uint256 jobId = jobCounter++;
        jobs[jobId] = Job({
            poster: msg.sender,
            title: _title,
            description: _description,
            budget: _budget,
            status: JobStatus.OPEN,
            assignedFreelancer: address(0),
            createdAt: block.timestamp
        });

        userJobs[msg.sender].push(jobId);
        emit JobPosted(jobId, msg.sender, _title, _budget);
    }

    // Proposal Submission Function
    function submitProposal(
        uint256 _jobId,
        uint256 _bidAmount,
        string memory _coverLetter
    ) external nonReentrant {
        Job storage job = jobs[_jobId];
        require(job.status == JobStatus.OPEN, "Job is not open");
        require(
            jobProposals[_jobId].length < MAX_PROPOSAL_PER_JOB,
            "Max proposals reached"
        );
        require(_bidAmount <= job.budget, "Bid amount exceeds job budget");

        jobProposals[_jobId].push(
            Proposal({
                freelancer: msg.sender,
                bidAmount: _bidAmount,
                coverLetter: _coverLetter,
                status: ProposalStatus.PENDING
            })
        );

        emit ProposalSubmitted(_jobId, msg.sender, _bidAmount);
    }

    // Accept Proposal Function
    function acceptProposal(
        uint256 _jobId,
        address _freelancer
    ) external nonReentrant {
        Job storage job = jobs[_jobId];
        require(job.poster == msg.sender, "Only job poster can accept");
        require(job.status == JobStatus.OPEN, "Job is not open");

        Proposal[] storage proposals = jobProposals[_jobId];
        bool proposalFound = false;
        uint256 acceptedProposalIndex;

        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i].freelancer == _freelancer) {
                require(
                    proposals[i].status == ProposalStatus.PENDING,
                    "Proposal not pending"
                );
                proposals[i].status = ProposalStatus.ACCEPTED;
                proposalFound = true;
                acceptedProposalIndex = i;
                break;
            }
        }

        require(proposalFound, "Proposal not found");

        job.status = JobStatus.IN_PROGRESS;
        job.assignedFreelancer = _freelancer;

        emit ProposalAccepted(_jobId, _freelancer);
    }

    // Complete Job Function
    function completeJob(uint256 _jobId) external nonReentrant {
        Job storage job = jobs[_jobId];
        require(job.poster == msg.sender, "Only job poster can complete");
        require(job.status == JobStatus.IN_PROGRESS, "Job not in progress");

        job.status = JobStatus.COMPLETED;

        // Calculate platform fee
        uint256 platformFee = (job.budget * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 freelancerAmount = job.budget - platformFee;

        // Release funds to freelancer
        (bool success, ) = job.assignedFreelancer.call{value: freelancerAmount}(
            ""
        );
        require(success, "Transfer to freelancer failed");

        emit JobCompleted(_jobId);
        emit FundReleased(_jobId, job.assignedFreelancer, freelancerAmount);
    }

    // Withdraw Function
    function withdrawEscrow() external nonReentrant {
        uint256 amount = freelancerEscrow[msg.sender];
        require(amount > 0, "No funds to withdraw");

        freelancerEscrow[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    // View Functions
    function getJobDetails(uint256 _jobId) external view returns (Job memory) {
        return jobs[_jobId];
    }

    function getJobProposals(
        uint256 _jobId
    ) external view returns (Proposal[] memory) {
        return jobProposals[_jobId];
    }

    function getUserJobs(
        address _user
    ) external view returns (uint256[] memory) {
        return userJobs[_user];
    }

    // Fallback and Receive functions to handle direct transfers
    receive() external payable {}
    fallback() external payable {}
}
