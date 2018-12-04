pragma solidity ^0.4.24;

import "/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "/openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "/openzeppelin-solidity/contracts/payment/PullPayment.sol";

contract CrowdFunding is Pausable, PullPayment{

	using SafeMath for uint256;
    
    uint256 registrationPeriodStart;
    uint256 registrationPeriodEnd;
    uint256 investingPeriodStart;
    uint256 investingPeriodEnd;
    
    uint256 winnerIndex;
    uint256 winnerAmount;
    
	// boolean necessary to set the state of the crowdfunding as finished.
    bool finalized;

	// a mirror to the ether sent to the contract by an investor. the power can be used to vote on ideas.
	mapping (address => uint256) investorPower;
    
	// modifier to check if the current period is the Idea Registration period.
    modifier inIdeaRegistrationPeriod () {
        require(now < registrationPeriodEnd, "Idea Registration period still in process.");
        _;
    }
    
	// modifier to check if the current period is the Investing/Voting Period.
    modifier inInvestingPeriod () {
        require(now > investingPeriodStart, "Investing/Voting period has not started yet.");
        require(now < investingPeriodEnd, "Investing/Voting period still in process.");
        _;
    }
    
	// modifier to check if a certain idea (index) was registered.
    modifier ideaIsRegistered (uint256 index){
		require(ideas[index].registered == true, "Idea was not registered.");
        _;
    }
    
	// modifier to check if the investing period has ended. if yes, the whole process can be finalized.
    modifier hasEnded () {
        require(now > investingPeriodEnd, "Investing/Voting or Idea Registration period has not ended yet.");
        _;
    }
    
    modifier isFinalized () {
        require(finalized == true, "Investing/Voting and Idea Registration are still in process.");
        _;
    }

    struct Idea {
        string githubURL;
        string commitHash;
        uint256 amountNeeded;
		bool registered;
		address owner;
		uint256 nrVotes;
		uint256 nrContributors;
		bool available;
		uint256 timestamp;
		mapping (address => uint256) amountInvestedByInvestorAddress;
    }
    
    Idea[] public ideas;
    
    event CreateIdea (uint256 index, string gitHubURL, string commitHash, uint256 amountNeeded);
    event SentInvestment(address investor, uint256 amount);
    event Vote(address investor, uint256 ideaIndex, uint256 amountVoted);
    event CrowdFundingFinished(address winner, uint256 amountRaised, address closedBy);
	event ClaimedReward(address investor, uint256 amountClaimed);
    
    constructor(uint256 rpe, uint256 ipe) public {
        require(now < rpe, "Idea Registration start date lower than end date.");
        require(rpe < ipe, "Investing/Voting start date lower than end date.");
        
        registrationPeriodStart = now;
        registrationPeriodEnd = rpe;
        investingPeriodStart = registrationPeriodEnd;
        investingPeriodEnd = ipe;
    }
    
    function createIdea (string _githubURL, string _commitHash, uint256 _amountNeeded) public inIdeaRegistrationPeriod whenNotPaused {
        //TODO add verifications to ideas parameteres
        
        Idea memory newIdea = Idea({
            githubURL: _githubURL,
            commitHash: _commitHash,
            amountNeeded: _amountNeeded, 
            registered: true,
            owner: msg.sender,
            nrVotes: 0,
            nrContributors: 0,
            available: true,
            timestamp: block.timestamp //https://consensys.github.io/smart-contract-best-practices/recommendations/#timestamp-dependence
        });
        
        uint256 newIdeaIndex = ideas.push(newIdea) - 1;

        emit CreateIdea(newIdeaIndex, _githubURL, _commitHash, _amountNeeded);
    }
    
    function sendInvestment() public payable inInvestingPeriod whenNotPaused {
		require(msg.value > 0, "Increase amount.");

        investorPower[msg.sender] = SafeMath.add(investorPower[msg.sender], msg.value);
        
        emit SentInvestment(msg.sender, msg.value);
    }
    
    function vote (uint256 index, uint256 amount) public ideaIsRegistered(index) inInvestingPeriod  whenNotPaused {
        
        Idea storage idea = ideas[index];
        
        require(investorPower[msg.sender] > 0, "Investor has no investing power.");
        
        investorPower[msg.sender] = SafeMath.sub(investorPower[msg.sender], amount);
		
		// investor has not invested in this idea yet. so it is considered a new contributor. increment nrContributors.
		if(idea.amountInvestedByInvestorAddress[msg.sender] == 0) idea.nrContributors = SafeMath.add(idea.nrContributors, 1);
        
		idea.amountInvestedByInvestorAddress[msg.sender] = SafeMath.add(idea.amountInvestedByInvestorAddress[msg.sender], amount);

        idea.nrVotes = SafeMath.add(idea.nrVotes, amount);
		
        /*necessary logic to identify the winner. this prevents a useless unbounded 
          iteration that is considered an anti-pattern; loops
        */
        if(idea.nrVotes > winnerAmount){
            winnerIndex = index;
            winnerAmount = idea.nrVotes;
        }
        
        emit Vote(msg.sender, index, amount);
    }
    
    /*sends the raised amount to the winner*/
    function finalize () public hasEnded whenNotPaused{
        Idea memory idea = ideas[winnerIndex];
        
        require(idea.amountNeeded <= idea.nrVotes);
		require(finalized == false);
        
        _asyncTransfer(idea.owner, idea.amountNeeded);
        
        finalized = true;
        emit CrowdFundingFinished(idea.owner, idea.amountNeeded, msg.sender);
    }

    function claimReward () public isFinalized whenNotPaused {
        Idea storage idea = ideas[winnerIndex];
        
        require(idea.amountInvestedByInvestorAddress[msg.sender] > 0, "Investor has not invested in winner.");
		require(idea.nrVotes > idea.amountNeeded);
        
		/**
			Proportional "reward"

			amountNeeded = 1000
			nrVotes = 2000
			investor1Votes = 500
			investor2Votes = 1500

			amountToStartup = 1000

			i1prop = 500/2000 = 0.25 = 25%
			i2prop = 1500/2000 = 0.75 = 75%

			excess = 2000 - 1000 = 1000

			amountToInvestor1 = 1000*0.25 = 250
			amountToInvestor2 = 1000*0.75 = 750
		*/

		uint256 investmentProportion = SafeMath.mul(idea.amountInvestedByInvestorAddress[msg.sender], 100);
		investmentProportion = SafeMath.div(investmentProportion, idea.nrVotes);

        uint256 raisedExcess = SafeMath.sub(idea.nrVotes, idea.amountNeeded);

        uint256 amountToInvestor = SafeMath.mul(raisedExcess, investmentProportion);
		amountToInvestor = SafeMath.div(amountToInvestor, 100);
        
        _asyncTransfer(msg.sender, amountToInvestor);

		emit ClaimedReward(msg.sender, amountToInvestor);
    }
    
    function getTotalIdeasRegistered () public view returns( uint256 ){
        return ideas.length;
    }
    
    function getInvestorPowerByAddress (address _investor) public view returns(uint256){
        return investorPower[_investor];
    }
    
    function getIdeaByIndex (uint256 _index) public view 
		returns (string, string, uint256, bool, address, uint256, uint256, bool, uint256){
        Idea memory idea = ideas[_index];
        return (
			idea.githubURL, 
			idea.commitHash, 
			idea.amountNeeded,
			idea.registered,
			idea.owner,
			idea.nrVotes,
			idea.nrContributors,
			idea.available,
			idea.timestamp
		);
    }

	function getAmountInvestedByAddressOnIdea(address _investor, uint256 _index) public view returns (uint256){
		Idea storage idea = ideas[_index];
		return (idea.amountInvestedByInvestorAddress[_investor]);
	}

	function getWinner() public view returns (uint256, uint256){
		return (winnerIndex, winnerAmount);
	}

    function getSummary () public view returns (uint256){
        return(address(this).balance);
    } 

	function getDates() public view returns (uint256, uint256, uint256, uint256) {
		return ( registrationPeriodStart,  registrationPeriodEnd, investingPeriodStart, investingPeriodEnd);
	} 

	function isInvestingPeriod() public view returns (bool) {
		if(now >= investingPeriodStart && now < investingPeriodEnd) return true;
		else return false;
	}

	function isRegistrationPeriod() public view returns (bool) {
		if(now >= registrationPeriodStart && now < registrationPeriodEnd) return true;
		else return false;
	}

	// As it was not mentioned what to do with the losers' money, it will 
	// be trapped in the contract forever. Maybe do something about this in the future.
	// This could be the beggining of it...

	// function claimAll() public isFinalized whenNotPaused {
	// 	uint256 totalAmount = getTotalInvestedByAddress();
	// 	_asyncTransfer(msg.sender, totalAmount);
	// }

	// function getTotalInvestedByAddress() public view returns (uint256){
	// 	uint256 totalAmount = 0;
	// 	for(uint256 index; index < ideas.length; index++){
	// 		totalAmount = SafeMath.add(totalAmount, ideas[index].amountInvestedByInvestorAddress[msg.sender]);
	// 	}
	// 	return totalAmount;
	// }
}