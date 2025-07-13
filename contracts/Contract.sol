// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract CrowdfundingImproved {
    struct Donator {
        address donator;
        uint256 amount;
        string comment;
        string date;
        string paymentMethod; // "crypto" or "evc"

    }

    struct Campaign {
        uint256 id;           // Unique ID for the campaign
        address owner;
        string title;
        string story;
        uint256 target;
        uint256 deadline;
        uint256 amountCollected;
        string image;
        Donator[] donators;
        bool isActive;
        bool approved;
    }

    // Main storage: mapping from campaignId to Campaign
    mapping(uint256 => Campaign) public campaigns;
    uint256 public numberOfCampaigns = 0;

    // EVC Payment Oracle System
    address public oracle; // Your backend wallet address
    uint256 public escrowBalance; // Track escrow funds
    
    
    // Keep track of all campaign IDs for iteration
    uint256[] public allCampaignIds;
    
    // Owner's campaigns
    mapping(address => uint256[]) public ownerToCampaignIds;

    // Events
    event CampaignStateChanged(uint256 campaignId, bool isActive);
    event CampaignCreated(uint256 campaignId, address owner);
    event DonationReceived(uint256 campaignId, address donor, uint256 amount, string paymentMethod);
    event EvcDonationProcessed(uint256 campaignId, address donor, uint256 amount, string evcTransactionId);
    event EscrowFunded(uint256 amount);
    event EscrowWithdrawn(uint256 amount);
    event CampaignApproved(uint256 campaignId);

    modifier onlyOwner(uint256 _campaignId) {
        require(campaigns[_campaignId].owner == msg.sender, "Only campaign owner can perform this action");
        _;
    }

        modifier onlyOracle() {
        require(msg.sender == oracle, "Only oracle can perform this action");
        _;
    }

    modifier campaignExists(uint256 _campaignId) {
        require(_campaignId < numberOfCampaigns, "Campaign does not exist");
        _;
    }

    
    constructor() {
        oracle = msg.sender; // Initially set deployer as oracle
    }

    // Function to change oracle address (important for security)
    function setOracle(address _newOracle) public onlyOracle {
        oracle = _newOracle;
    }

    // Fund the escrow with MATIC for EVC payments
    function fundEscrow() public payable onlyOracle {
        escrowBalance += msg.value;
        emit EscrowFunded(msg.value);
    }

    // Withdraw from escrow (only oracle/admin)
    function withdrawFromEscrow(uint256 _amount) public onlyOracle {
        require(_amount <= escrowBalance, "Insufficient escrow balance");
        require(_amount <= address(this).balance, "Insufficient contract balance");
        
        escrowBalance -= _amount;
        (bool sent, ) = payable(oracle).call{value: _amount}("");
        require(sent, "Failed to withdraw from escrow");
        
        emit EscrowWithdrawn(_amount);
    }


     function donateWithEvc(
        uint256 _campaignId,
        address _donor,
        uint256 _amountInWei, // Convert EVC amount to Wei equivalent
        string memory _comment,
        string memory _date,
        string memory _evcTransactionId
    ) public onlyOracle campaignExists(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];

        require(campaign.isActive, "Campaign is paused");
        require(campaign.approved, "Campaign is not approved");
        require(campaign.deadline > block.timestamp, "Campaign expired");
        require(_amountInWei <= escrowBalance, "Insufficient escrow balance");
        require(_amountInWei <= address(this).balance, "Insufficient contract balance");

        // Mark transaction as processed to prevent double spending

        // Add donator to campaign
        campaign.donators.push(Donator({
            donator: _donor,
            amount: _amountInWei,
            comment: _comment,
            date: _date,
            paymentMethod: "evc"
        }));

        // Transfer from escrow to campaign owner
        escrowBalance -= _amountInWei;
        (bool sent, ) = payable(campaign.owner).call{value: _amountInWei}("");
        require(sent, "Failed to send Ether to campaign owner");

        // Update campaign collected amount
        campaign.amountCollected += _amountInWei;
        
        emit DonationReceived(_campaignId, _donor, _amountInWei, "evc");
        emit EvcDonationProcessed(_campaignId, _donor, _amountInWei, _evcTransactionId);
    }


    // Get escrow balance
    function getEscrowBalance() public view returns (uint256) {
        return escrowBalance;
    }

    // Get contract balance
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }



    function createCampaign(
        address _owner,
        string memory _title,
        string memory _story,
        uint256 _target,
        uint256 _deadline,
        string memory _image
    ) public returns (uint256) {
        require(_deadline > block.timestamp, "The deadline should be a date in the future.");

        uint256 campaignId = numberOfCampaigns;
        
        // Initialize campaign in storage first, then set values individually
        Campaign storage campaign = campaigns[campaignId];
        campaign.id = campaignId;
        campaign.owner = _owner;
        campaign.title = _title;
        campaign.story = _story;
        campaign.target = _target;
        campaign.deadline = _deadline;
        campaign.image = _image;
        campaign.amountCollected = 0;
        campaign.isActive = true;
        campaign.approved = false;
        // donators array is automatically initialized as an empty array

        // Track this campaign in our arrays
        allCampaignIds.push(campaignId);
        ownerToCampaignIds[_owner].push(campaignId);
        
        emit CampaignCreated(campaignId, _owner);
        
        numberOfCampaigns++;
        return campaignId;
    }

    function approveCampaign(uint256 _campaignId) public onlyOracle campaignExists(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];
        require(!campaign.approved, "Campaign is already approved");
        campaign.approved = true;
        emit CampaignApproved(_campaignId);
    }

    // Toggle function to switch between active and paused states
    function toggleCampaignState(uint256 _campaignId) public onlyOwner(_campaignId) campaignExists(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];
        
        // If trying to activate an expired campaign, prevent it
        if (!campaign.isActive && campaign.deadline <= block.timestamp) {
            revert("Cannot activate expired campaign");
        }
        
        // Toggle the state
        campaign.isActive = !campaign.isActive;
        
        // Emit event with the new state
        emit CampaignStateChanged(_campaignId, campaign.isActive);
    }

    function donate(uint256 _campaignId, string memory _comment, string memory _date) public payable campaignExists(_campaignId) {
        uint256 amount = msg.value;
        Campaign storage campaign = campaigns[_campaignId];

        require(campaign.isActive, "Campaign is paused");
        require(campaign.approved, "Campaign is not approved");
        require(campaign.deadline > block.timestamp, "Campaign expired");

        campaign.donators.push(Donator({
            donator: msg.sender,
            amount: amount,
            comment: _comment,
            date: _date,
            paymentMethod: "crypto"
            
        }));

        (bool sent, ) = payable(campaign.owner).call{value: amount}("");
        require(sent, "Failed to send Ether");

        campaign.amountCollected += amount;
        emit DonationReceived(_campaignId, msg.sender, amount,"crypto");
    }

    // Get a specific campaign by ID
    function getCampaign(uint256 _campaignId) public view campaignExists(_campaignId) returns (Campaign memory) {
        return campaigns[_campaignId];
    }

    // Get all ongoing campaigns (returns full campaign objects with their IDs)
    function getOngoingCampaigns() public view returns (Campaign[] memory) {
        uint256 activeCount = 0;
        
        // First count active campaigns
        for(uint256 i = 0; i < allCampaignIds.length; i++) {
            uint256 campaignId = allCampaignIds[i];
            if(campaigns[campaignId].deadline > block.timestamp && campaigns[campaignId].isActive && campaigns[campaignId].approved) {
                activeCount++;
            }
        }
        
        // Then populate the array
        Campaign[] memory activeCampaigns = new Campaign[](activeCount);
        uint256 currentIndex = 0;
        
        for(uint256 i = 0; i < allCampaignIds.length; i++) {
            uint256 campaignId = allCampaignIds[i];
            if(campaigns[campaignId].deadline > block.timestamp && campaigns[campaignId].isActive && campaigns[campaignId].approved) {
                activeCampaigns[currentIndex] = campaigns[campaignId];
                currentIndex++;
            }
        }
        
        return activeCampaigns;
    }

    function getPendingCampaigns() public view returns (Campaign[] memory) {
        uint256 pendingCount = 0;
        for (uint256 i = 0; i < numberOfCampaigns; i++) {
            if (!campaigns[i].approved) {
                pendingCount++;
            }
        }

        Campaign[] memory pendingCampaigns = new Campaign[](pendingCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < numberOfCampaigns; i++) {
            if (!campaigns[i].approved) {
                pendingCampaigns[currentIndex] = campaigns[i];
                currentIndex++;
            }
        }

        return pendingCampaigns;
    }

    // Get all expired campaigns
    function getExpiredCampaigns() public view returns (Campaign[] memory) {
        uint256 expiredCount = 0;
        
        for(uint256 i = 0; i < allCampaignIds.length; i++) {
            uint256 campaignId = allCampaignIds[i];
            if(campaigns[campaignId].deadline <= block.timestamp) {
                expiredCount++;
            }
        }
        
        Campaign[] memory expiredCampaigns = new Campaign[](expiredCount);
        uint256 currentIndex = 0;
        
        for(uint256 i = 0; i < allCampaignIds.length; i++) {
            uint256 campaignId = allCampaignIds[i];
            if(campaigns[campaignId].deadline <= block.timestamp) {
                expiredCampaigns[currentIndex] = campaigns[campaignId];
                currentIndex++;
            }
        }
        
        return expiredCampaigns;
    }

    // Get a user's ongoing campaigns
    function getUserOngoingCampaigns(address _user) public view returns (Campaign[] memory) {
        uint256[] memory userCampaignIds = ownerToCampaignIds[_user];
        uint256 activeCount = 0;
        
        // Count user's active campaigns
        for(uint256 i = 0; i < userCampaignIds.length; i++) {
            uint256 campaignId = userCampaignIds[i];
            if(campaigns[campaignId].deadline > block.timestamp && campaigns[campaignId].isActive && campaigns[campaignId].approved) {
                activeCount++;
            }
        }
        
        // Populate array with user's active campaigns
        Campaign[] memory activeCampaigns = new Campaign[](activeCount);
        uint256 currentIndex = 0;
        
        for(uint256 i = 0; i < userCampaignIds.length; i++) {
            uint256 campaignId = userCampaignIds[i];
            if(campaigns[campaignId].deadline > block.timestamp && campaigns[campaignId].isActive && campaigns[campaignId].approved) {
                activeCampaigns[currentIndex] = campaigns[campaignId];
                currentIndex++;
            }
        }
        
        return activeCampaigns;
    }


    

    
    
    // Get a user's in active or puased campaigns
    function getUsersInActiveCampaign(address _user) public view returns (Campaign[] memory) {
        uint256[] memory userCampaignIds = ownerToCampaignIds[_user];
        uint256 inActiveCount = 0;
        
        // Count user's active campaigns
        for(uint256 i = 0; i < userCampaignIds.length; i++) {
            uint256 campaignId = userCampaignIds[i];
            if(!campaigns[campaignId].isActive) {
                inActiveCount++;
            }
        }
        
        // Populate array with user's active campaigns
        Campaign[] memory inActiveCampaigns = new Campaign[](inActiveCount);
        uint256 currentIndex = 0;
        
        for(uint256 i = 0; i < userCampaignIds.length; i++) {
            uint256 campaignId = userCampaignIds[i];
            if(!campaigns[campaignId].isActive) {
                inActiveCampaigns[currentIndex] = campaigns[campaignId];
                currentIndex++;
            }
        }
        
        return inActiveCampaigns;
    }

    // Get a user's expired campaigns
    function getUserExpiredCampaigns(address _user) public view returns (Campaign[] memory) {
        uint256[] memory userCampaignIds = ownerToCampaignIds[_user];
        uint256 expiredCount = 0;

        // Count user's expired campaigns
        for (uint256 i = 0; i < userCampaignIds.length; i++) {
            uint256 campaignId = userCampaignIds[i];
            if (campaigns[campaignId].deadline <= block.timestamp) {
                expiredCount++;
            }
        }

        // Populate array with user's expired campaigns
        Campaign[] memory expiredCampaigns = new Campaign[](expiredCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < userCampaignIds.length; i++) {
            uint256 campaignId = userCampaignIds[i];
            if (campaigns[campaignId].deadline <= block.timestamp) {
                expiredCampaigns[currentIndex] = campaigns[campaignId];
                currentIndex++;
            }
        }

        return expiredCampaigns;
    }

    
    // Get all campaigns created by a specific user
    function getUserCampaigns(address _user) public view returns (Campaign[] memory) {
        uint256[] memory userCampaignIds = ownerToCampaignIds[_user];
        Campaign[] memory userCampaigns = new Campaign[](userCampaignIds.length);
        
        for(uint256 i = 0; i < userCampaignIds.length; i++) {
            userCampaigns[i] = campaigns[userCampaignIds[i]];
        }
        
        return userCampaigns;
    }

    function getUserLatestOngoingCampaign(address _user) public view returns (Campaign memory) {
        uint256[] memory userCampaignIds = ownerToCampaignIds[_user];
        Campaign memory latestCampaign;
        bool found = false;
        uint256 latestDeadline = 0;

        for (uint256 i = 0; i < userCampaignIds.length; i++) {
            uint256 campaignId = userCampaignIds[i];
            Campaign memory campaign = campaigns[campaignId];

            if (campaign.deadline > block.timestamp && campaign.deadline > latestDeadline && campaign.approved) {
                latestDeadline = campaign.deadline;
                latestCampaign = campaign;
                found = true;
            }
        }

        require(found, "No ongoing campaign found");
        return latestCampaign;
    }

    function updateCampaignTitle(uint256 _campaignId, string memory _newTitle)  public onlyOwner(_campaignId) campaignExists(_campaignId){
        campaigns[_campaignId].title = _newTitle;
    }

    function updateCampaignStory(uint256 _campaignId, string memory _newStory)
        public
        onlyOwner(_campaignId)
        campaignExists(_campaignId)
    {
        campaigns[_campaignId].story = _newStory;
    }

    // Get campaign state
    // function getCampaignState(uint256 _campaignId) public view campaignExists(_campaignId) returns (bool) {
    //     return campaigns[_campaignId].isActive;
    // }

    // Get donators for a campaign
    // function getDonators(uint256 _campaignId) public view campaignExists(_campaignId) returns (Donator[] memory) {
    //     return campaigns[_campaignId].donators;
    // }

    // Get all campaigns
    // function getCampaigns() public view returns (Campaign[] memory) {
    //     Campaign[] memory allCampaigns = new Campaign[](allCampaignIds.length);

    //     for (uint256 i = 0; i < allCampaignIds.length; i++) {
    //         allCampaigns[i] = campaigns[allCampaignIds[i]];
    //     }

    //     return allCampaigns;
    // }
    
    // Get total number of campaigns
    // function getTotalCampaigns() public view returns (uint256) {
    //     return numberOfCampaigns;
    // }
}