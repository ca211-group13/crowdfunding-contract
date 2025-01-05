// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract CrowdfundingC {
    struct Donator {
        address donator;
        uint256 amount;
        string comment;
        string date;
    }

    struct Campaign {
        address owner;
        string title;
        string story;
        uint256 target;
        uint256 deadline;
        uint256 amountCollected;
        string image;
        Donator[] donators;
        bool isActive; // New field to track campaign state
    }

    mapping(uint256 => Campaign) public campaigns;
    uint256 public numberOfCampaigns = 0;

    // Event to log campaign state changes
    event CampaignStateChanged(uint256 campaignId, bool isActive);

    modifier onlyOwner(uint256 _id) {
        require(campaigns[_id].owner == msg.sender, "Only campaign owner can perform this action");
        _;
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

        Campaign storage campaign = campaigns[numberOfCampaigns];
        campaign.owner = _owner;
        campaign.title = _title;
        campaign.story = _story;
        campaign.target = _target;
        campaign.deadline = _deadline;
        campaign.image = _image;
        campaign.amountCollected = 0;
        campaign.isActive = true; // Set as active by default

        numberOfCampaigns++;
        return numberOfCampaigns - 1;
    }

    // New function to pause campaign
    function pauseCampaign(uint256 _id) public onlyOwner(_id) {
        require(campaigns[_id].isActive, "Campaign is already paused");
        campaigns[_id].isActive = false;
        emit CampaignStateChanged(_id, false);
    }

    // New function to resume campaign
    function resumeCampaign(uint256 _id) public onlyOwner(_id) {
        require(!campaigns[_id].isActive, "Campaign is already active");
        require(campaigns[_id].deadline > block.timestamp, "Cannot resume expired campaign");
        campaigns[_id].isActive = true;
        emit CampaignStateChanged(_id, true);
    }

    function donate(uint256 _id, string memory _comment, string memory _date) public payable {
        uint256 amount = msg.value;
        Campaign storage campaign = campaigns[_id];

        require(campaign.isActive, "Campaign is paused");
        require(campaign.deadline > block.timestamp, "Campaign expired");

        campaign.donators.push(Donator({
            donator: msg.sender,
            amount: amount,
            comment: _comment,
            date: _date
        }));

        (bool sent, ) = payable(campaign.owner).call{value: amount}("");
        require(sent, "Failed to send Ether");

        campaign.amountCollected += amount;
    }

    // Modified to only return active ongoing campaigns
    function getOngoingCampaigns() public view returns (Campaign[] memory) {
        uint256 activeCount = 0;
        
        for(uint256 i = 0; i < numberOfCampaigns; i++) {
            if(campaigns[i].deadline > block.timestamp && campaigns[i].isActive) {
                activeCount++;
            }
        }
        
        Campaign[] memory activeCampaigns = new Campaign[](activeCount);
        uint256 currentIndex = 0;
        
        for(uint256 i = 0; i < numberOfCampaigns; i++) {
            if(campaigns[i].deadline > block.timestamp && campaigns[i].isActive) {
                activeCampaigns[currentIndex] = campaigns[i];
                currentIndex++;
            }
        }
        
        return activeCampaigns;
    }

    // Modified to include all expired campaigns regardless of active state
    function getExpiredCampaigns() public view returns (Campaign[] memory) {
        uint256 expiredCount = 0;
        
        for(uint256 i = 0; i < numberOfCampaigns; i++) {
            if(campaigns[i].deadline <= block.timestamp) {
                expiredCount++;
            }
        }
        
        Campaign[] memory expiredCampaigns = new Campaign[](expiredCount);
        uint256 currentIndex = 0;
        
        for(uint256 i = 0; i < numberOfCampaigns; i++) {
            if(campaigns[i].deadline <= block.timestamp) {
                expiredCampaigns[currentIndex] = campaigns[i];
                currentIndex++;
            }
        }
        
        return expiredCampaigns;
    }

    // Modified to only return active ongoing campaigns for user
    function getUserOngoingCampaigns(address _user) public view returns (Campaign[] memory) {
        uint256 activeCount = 0;
        
        for(uint256 i = 0; i < numberOfCampaigns; i++) {
            if(campaigns[i].owner == _user && 
               campaigns[i].deadline > block.timestamp && 
               campaigns[i].isActive) {
                activeCount++;
            }
        }
        
        Campaign[] memory activeCampaigns = new Campaign[](activeCount);
        uint256 currentIndex = 0;
        
        for(uint256 i = 0; i < numberOfCampaigns; i++) {
            if(campaigns[i].owner == _user && 
               campaigns[i].deadline > block.timestamp && 
               campaigns[i].isActive) {
                activeCampaigns[currentIndex] = campaigns[i];
                currentIndex++;
            }
        }
        
        return activeCampaigns;
    }

    // Get campaign state
    function getCampaignState(uint256 _id) public view returns (bool) {
        return campaigns[_id].isActive;
    }

    function getDonators(uint256 _id) public view returns (Donator[] memory) {
        return campaigns[_id].donators;
    }

    // Returns all campaigns regardless of state
    function getCampaigns() public view returns (Campaign[] memory) {
        Campaign[] memory allCampaigns = new Campaign[](numberOfCampaigns);

        for (uint256 i = 0; i < numberOfCampaigns; i++) {
            Campaign storage item = campaigns[i];
            allCampaigns[i] = item;
        }

        return allCampaigns;
    }
}